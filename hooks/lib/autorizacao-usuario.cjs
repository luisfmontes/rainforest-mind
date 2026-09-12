const fs = require('fs');

/**
 * Lê a autorização de subagentes do usuário no transcript.
 *
 * Estratégia:
 * - Lê o arquivo INTEIRO. A cauda foi tentada e removida — ver o comentário do
 *   `TETO_GUARDA` abaixo, que traz a medição que a matou.
 * - Só olha linhas que `vozDoUsuario` aceita: type "user" identificado como
 *   humano, e "queue-operation" que não seja envelope de sistema. `attachment`
 *   ficou de FORA de propósito: é canal de conteúdo (arquivo colado, imagem),
 *   e conteúdo é exatamente o vetor que esta trava fecha. A concessão mandada
 *   no meio do turno chega pelo `queue-operation`, medido no transcript real.
 * - NORMALIZA acentos antes de todo casamento (NFD + remoção de diacríticos)
 * - Reconhece "autorizo" perto de "subagente(s)" por frase livre (não comando)
 * - Julga FRASE A FRASE, e basta uma conceder. Marcador subordinado ("falo que",
 *   "disse que", "se autorizo", "ainda não decidi", "vou pensar", "talvez") só
 *   desqualifica a concessão quando está na MESMA frase e antes da palavra —
 *   considerar autorizar não é autorizar, mas duvidar de outra coisa também não
 *   é recusar
 * - Nega a frase que é PERGUNTA: "posso autorizar subagentes ou fica
 *   arriscado?" é pedido de opinião, não consentimento — com ou sem o "?"
 * - Nega se houver negação explícita ("não autorizo", "nunca autorizo", "não vou autorizar")
 * - Retorna true se houver autorização válida, false caso contrário
 *
 * @param {string} transcriptPath - Caminho do arquivo JSONL
 * @returns {boolean} true se usuário autorizou subagentes, false caso contrário
 */
function autorizado(transcriptPath) {
  try {
    if (!fs.existsSync(transcriptPath)) {
      return false;
    }

    const stats = fs.statSync(transcriptPath);
    const fileSize = stats.size;

    // NÃO ler cauda. A primeira versão lia só o último 1 MB quando o arquivo
    // passava de 2 MB, e isso reintroduziu o defeito que este leitor existe para
    // consertar. Medido em 2026-09-12, na própria sessão que desenhou o
    // mecanismo:
    //
    //   tamanho total do transcript ............. 2.070.974 B
    //   "autorizo subagentes" no byte ............... 470.903
    //   cauda de 1 MB comecava no byte ............ 1.022.398
    //   => a concessao ficava FORA da janela, e o leitor devolvia `false`
    //      numa sessao em que o usuario tinha autorizado explicitamente.
    //
    // A cauda é incompatível com o desenho por duas razões que se somam: a
    // autorização vale pela SESSÃO INTEIRA (uma concessão do minuto 5 continua
    // valendo no minuto 300), e a precedência entre concessão e negação depende
    // de ter visto as DUAS. Ler só o fim é ler metade da evidência, e apaga
    // justamente as concessões das sessões longas — que são as que mais
    // despacham agente.
    //
    // O argumento de custo que justificava a cauda não se sustentou na medição:
    // os 2 MB inteiros levam 15 ms. O teto abaixo é guarda contra arquivo fora
    // do normal, não corte no caso comum: a 15 ms / 2 MB, 64 MB dariam ~0,5 s,
    // ainda muito abaixo do orçamento de tempo de um hook.
    const TETO_GUARDA = 64 * 1024 * 1024;
    const startPos = Math.max(0, fileSize - TETO_GUARDA);
    const cauda_bytes = fileSize - startPos;

    const buffer = Buffer.alloc(Math.min(cauda_bytes + 100, fileSize)); // +100 pra margem
    const fd = fs.openSync(transcriptPath, 'r');
    const bytesRead = fs.readSync(fd, buffer, 0, buffer.length, startPos);
    fs.closeSync(fd);

    const caudaText = buffer.toString('utf8', 0, bytesRead);

    // Remove primeira linha incompleta apenas se não estamos lendo desde o início
    let lines;
    if (startPos === 0) {
      // Arquivo inteiro ou pequeno: primeira linha é completa
      lines = caudaText.split('\n');
    } else {
      // Cauda: primeira linha pode estar partida no meio, descarta
      const firstNewline = caudaText.indexOf('\n');
      lines = firstNewline === -1
        ? caudaText.split('\n')
        : caudaText.substring(firstNewline + 1).split('\n');
    }

    // Processa linhas de trás pra frente para pegar a mais recente
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i].trim();
      if (!line) continue;

      try {
        const obj = JSON.parse(line);

        // PORTA DE ENTRADA: só a voz do usuário conta. Ver `vozDoUsuario`.
        if (vozDoUsuario(obj) === null) {
          continue;
        }

        // Verifica negação explícita primeiro (a mais forte).
        //
        // Ela vale pela LINHA inteira, sem noção de ordem de frase, enquanto a
        // concessão é julgada frase a frase. A assimetria é de propósito e foi
        // levantada como lacuna na revisão de 2026-09-12: numa mesma mensagem,
        // "nao autorizo subagentes. autorizo subagentes" nega nas duas ordens.
        // Turno que se contradiz dentro de si não é consentimento claro, e a
        // saída barata é o usuário mandar a concessão sozinha na linha
        // seguinte. Entre abrir o portão com dúvida e pedir uma frase a mais,
        // esta trava escolhe pedir a frase. A ordem ENTRE linhas continua
        // valendo normalmente — negar antes e conceder depois autoriza.
        if (temNegacaoExplicita(obj)) {
          return false;
        }

        // Verifica autorização positiva em cláusula principal
        if (temAutorizacaoPrincipal(obj)) {
          return true;
        }

        // Se tem "autorizo" mas em cláusula subordinada, continua procurando
      } catch (e) {
        // Ignora linhas que não são JSON válido
        continue;
      }
    }

    return false;
  } catch (e) {
    return false;
  }
}

/**
 * Envelopes que o harness entrega DENTRO de uma linha que, de fora, parece do
 * usuário. Nenhum deles foi digitado por ele.
 */
const ENVELOPE_DE_SISTEMA = /<task-notification>|<system-reminder>|<cross-session-message|<command-name>/i;

/**
 * A única porta de entrada: devolve o texto quando a linha é a VOZ DO USUÁRIO,
 * e `null` para todo o resto. Fora daqui, o leitor não olha nada.
 *
 * Isto não é zelo — é a diferença entre uma trava e um buraco. Na primeira
 * versão o leitor aceitava qualquer linha de `type` "user", "queue-operation" ou
 * "attachment", e o efeito foi medido em 2026-09-12 na própria sessão que
 * desenhou o mecanismo:
 *
 *   L91   queue-operation  "autorizo subagentes"          <- o usuario, de verdade
 *   L997  queue-operation  "<task-notification>…"          <- relato de agente
 *   L1070 user             origin.kind=task-notification   <- notificacao
 *   L1117 user             tool_result com o fonte deste modulo dentro
 *
 * As três últimas eram máquina, e entravam no veredito. O leitor devolvia
 * `false` numa sessão em que o usuário tinha autorizado, porque o relato de um
 * subagente citando a string "nao autorizo subagentes" pesava mais que a
 * palavra dele.
 *
 * A direção perigosa é a outra: um `tool_result` com um arquivo, uma fixture ou
 * um design doc contendo "autorizo subagentes" ABRIRIA o portão. Qualquer coisa
 * que a sessão lesse viraria concessão — escalada de privilégio por conteúdo,
 * que é o oposto exato do que esta trava existe para fazer.
 *
 * Os discriminadores abaixo foram medidos no transcript real, não inferidos:
 * turno digitado traz `origin.kind === "human"`; notificação traz
 * `origin.kind === "task-notification"` com `promptSource: "system"`;
 * `tool_result` chega com `message.content` em ARRAY (nunca string) e carrega
 * `toolUseResult`.
 */
function vozDoUsuario(obj) {
  if (!obj || typeof obj !== 'object') return null;

  if (obj.type === 'user') {
    const conteudo = obj.message && obj.message.content;
    // tool_result vem em ARRAY; a fala do usuário vem em string.
    if (typeof conteudo !== 'string') return null;
    // Injeção do harness se identifica, e nunca conta.
    if (obj.promptSource === 'system') return null;
    if (obj.origin && obj.origin.kind !== 'human') return null;
    // Dois sinais afirmativos, qualquer um serve: `origin.kind` é o que o
    // transcript traz hoje, `promptSource` é o que sobra se a forma mudar.
    // Exigir os dois quebraria em transcript antigo; aceitar sem nenhum
    // aceitaria linha que não se identifica, que é o caso a barrar.
    if (obj.origin && obj.origin.kind === 'human') return conteudo;
    if (obj.promptSource === 'typed') return conteudo;
    return null;
  }

  if (obj.type === 'queue-operation') {
    if (typeof obj.content !== 'string') return null;
    if (ENVELOPE_DE_SISTEMA.test(obj.content)) return null;
    return obj.content;
  }

  return null;
}

/**
 * Normaliza texto: remove acentos e baixa caixa
 * Permite casar "não" com "nao", "Não", "NÃO", etc.
 */
function normalizar(texto) {
  if (!texto || typeof texto !== 'string') {
    return '';
  }
  // NFD decomposição + remove combining diacritics (U+0300 a U+036F)
  return texto.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
}

/**
 * Verifica se objeto contém negação explícita
 * Formas cobertas: "não autorizo", "não autorizar", "nunca autorizo", "não vou autorizar"
 * EXIGE proximidade com "subagente(s)" ou "agente" (não qualquer "não autorizo")
 */
function temNegacaoExplicita(obj) {
  let conteudo = null;

  if (obj.type === 'queue-operation') {
    conteudo = obj.content;
  } else if (obj.type === 'user' && obj.message) {
    conteudo = obj.message.content;
  }

  if (!conteudo || typeof conteudo !== 'string') {
    return false;
  }

  const normalizado = normalizar(conteudo);

  // Procura por negações explícitas (todas em forma normalizada)
  const negacoes = [
    /\bnao\s+autorizo\b/,
    /\bnao\s+autorizar\b/,
    /\bnunca\s+autorizo\b/,
    /\bnao\s+vou\s+autorizar\b/,
  ];

  // Só é negação se contém AMBAS: forma de negação + menção a subagente/agente
  for (const negacao of negacoes) {
    if (negacao.test(normalizado)) {
      // Encontra a negação e procura por "subagente" ou "agente" próximo
      const temSubagente = /\bsubagente\b|\bsubagentes\b|\bsub-agente\b|\bsub-agentes\b|\bsub\s+agentes?\b|\bagente\b|\bagentes\b/.test(normalizado);
      if (temSubagente) {
        return true;
      }
    }
  }

  return false;
}

/**
 * Verifica se objeto contém autorização em cláusula principal
 */
function temAutorizacaoPrincipal(obj) {
  let conteudo = null;

  if (obj.type === 'queue-operation') {
    conteudo = obj.content;
  } else if (obj.type === 'user' && obj.message) {
    conteudo = obj.message.content;
  }

  if (!conteudo || typeof conteudo !== 'string') {
    return false;
  }

  const normalizado = normalizar(conteudo);

  // Procura por "autorizo" ou "autorizar" perto de "subagente(s)"
  const temAutoriz = /\bautorizo\b|\bautorizando\b|\bautorizar\b|\bautorizacao\b/.test(normalizado);
  const temSubagente = /\bsubagente\b|\bsubagentes\b|\bsub-agente\b|\bsub-agentes\b|\bsub\s+agentes?\b/.test(normalizado);

  if (!temAutoriz || !temSubagente) {
    return false;
  }

  // O VEREDITO É POR FRASE, não pelo turno inteiro.
  //
  // A primeira versão desta checagem varria do marcador subordinado até o FIM do
  // texto e perguntava se "autorizo" aparecia em algum lugar depois. Com isso um
  // hedge numa frase matava uma concessão em OUTRA. Medido em 2026-09-12, com a
  // correção dos hedges ainda fresca:
  //
  //   "talvez a gente mude o plano depois. autorizo subagentes"  -> recusava
  //   "sera que o CI aguenta? autorizo subagentes agora"         -> recusava
  //   "vou pensar no design amanha. autorizo subagentes ja"      -> recusava
  //
  // Falso negativo aqui é PIOR que o defeito que a correção fechou: o usuário
  // autoriza, nada acontece, e a negação ainda fala de estágio — ele não tem
  // como descobrir que a palavra dele foi lida e descartada. Agora cada frase é
  // julgada sozinha e basta UMA conceder de verdade.
  // URL sai antes de qualquer análise de pontuação. O `?` de query string não é
  // pergunta, e com a regra "`?` em qualquer lugar da frase" ele passou a negar
  // a frase inteira — medido na 4ª rodada de revisão de 2026-09-12:
  //
  //   "autorizo subagentes para investigar esse link
  //    https://example.com/page?ref=x"   -> recusava
  //
  // Trocar por espaço (e não apagar) preserva as fronteiras de palavra.
  //
  // O casamento PARA na pontuação que fecha link em prosa. Com `\S+` guloso, a
  // URL colada na pontuação seguinte engolia a palavra depois dela — inclusive
  // a que decide tudo:
  //
  //   "aqui esta o link:https://…/123?tab=comments,autorizo subagentes"
  //     -> "autorizo" sumia do texto antes de qualquer análise, e recusava
  //
  // Uma URL pode legitimamente conter `,` ou `)`, e aí o pedaço final vira
  // texto. É o lado barato do erro: sobra ruído, não some concessão.
  const semUrl = normalizado.replace(/\bhttps?:\/\/[^\s,)\]}"'<>]+|\bwww\.[^\s,)\]}"'<>]+/g, ' ');

  // O separador de frases corta em `.!?` seguido de espaço, mais um caso: `?`
  // colado na palavra seguinte, sem espaço nenhum — digitação com pressa
  // ("autorizo subagentes?ou nao"). Sem esse corte a frase não termina em `?` e
  // a pergunta passaria por concessão.
  //
  // Uma versão deste separador também cortava em aspas/parênteses de fechamento
  // e na vírgula depois deles, para separar pergunta CITADA da concessão que
  // vem em seguida. Saiu: a catraca de mutação mostrou que apagá-lo não muda
  // nenhum caso. Quem já resolve a citação é a regra de pergunta ser da CAUDA —
  // em 'ele perguntou "isso vai dar certo?" mas eu autorizo subagentes' a cauda
  // é "…mesmo assim", sem `?`. Regra sem efeito observável é comentário que
  // apodrece, não defesa.
  const frases = semUrl.split(/(?<=[.!?])\s+|(?<=\?)(?=\p{L})|\n+/u);

  // Marcador que subordina a concessão. Só vale dentro da MESMA frase e ANTES da
  // palavra: "vou pensar no design" numa frase anterior não subordina nada.
  //
  // `posso autoriz` e `poderia autoriz` estão aqui, e não só na regra do `?`,
  // porque pergunta sem ponto de interrogação é como se digita com pressa —
  // "posso autorizar subagentes" continua sendo pedido de opinião.
  // Rabicho de confirmação: "…, beleza?", "…, ta?", "…, pode ser?". Em fala
  // corrida isso fecha uma concessão, não abre uma pergunta.
  //
  // `sim` e `ne` estavam aqui e saíram na revisão de 2026-09-12: ao contrário
  // de "beleza" e "ta", que só aparecem fechando, essas duas fecham QUALQUER
  // oração anterior — inclusive uma hesitante. Medido:
  //
  //   "nao tenho certeza, autorizo subagentes, sim?"  -> autorizava
  //   "fico em duvida, autorizo subagentes, ne?"      -> autorizava
  //
  // Com elas fora, o `?` final volta a valer e as duas são recusadas. O custo é
  // recusar "autorizo subagentes, sim?" — uma frase a mais para o usuário, do
  // lado seguro da troca.
  const RABICHO_DE_CONFIRMACAO =
    /,\s*(beleza|blz|ta|ok|okay|certo|combinado|fechado|tranquilo|tudo\s+bem|pode\s+ser|hein)\s*[?!.…]*$/;

  const sinaisSubordinados = [
    /\bfalo\s+que\b/,
    /\bdisse\s+que\b/,
    /\bdigo\s+que\b/,
    /\bquando\s+eu\s+autoriz\w*/,
    /\bse\s+eu\s+autoriz\w*/,
    /\bque\s+autorizo\b/,
    /\bse\s+autoriz\w*/,
    /\bnao\s+decidi\b/,
    /\bnao\s+sei\s+se\b/,
    /\bvou\s+pensar\b/,
    /\bpensar\s+se\b/,
    /\btalvez\b/,
    /\bsera\s+que\b/,
    /\bposso\s+autoriz\w*/,
    /\bposso\s+te\s+autoriz\w*/,
    /\bpoderia\s+autoriz\w*/,
    /\bdevo\s+autoriz\w*/,
  ];

  for (const frase of frases) {
    let texto = frase.trim();
    if (!texto) continue;

    if (!/\bautorizo\b|\bautorizando\b|\bautorizar\b/.test(texto)) continue;
    if (!/\bsubagente\b|\bsubagentes\b|\bsub-agente\b|\bsub-agentes\b|\bsub\s+agentes?\b/.test(texto)) continue;

    // Confirmação casual no fim não transforma concessão em pergunta.
    // "autorizo subagentes, beleza?" é o usuário autorizando e checando, não
    // pedindo opinião — e era recusado, que é o lado ruim do erro. O rabicho sai
    // antes da checagem de pergunta; o que sobra ("autorizo subagentes") é
    // julgado normalmente, então "posso autorizar subagentes, ta?" continua
    // caindo no marcador `posso autoriz` e sendo recusado.
    texto = texto.replace(RABICHO_DE_CONFIRMACAO, '').trim();
    if (!texto) continue;

    // PERGUNTA NÃO É CONSENTIMENTO. "posso autorizar subagentes nesse projeto ou
    // fica arriscado?" é o usuário pedindo opinião, e abria o portão. A marca é
    // o ponto de interrogação nesta frase — não no turno inteiro, senão
    // "autorizo subagentes. e o build, passou?" seria recusado.
    //
    // `endsWith('?')` era estreito demais: qualquer coisa colada depois do sinal
    // escapava, e escapava para o lado PERIGOSO. Medido em 2026-09-12, na
    // segunda rodada de revisão:
    //
    //   "autorizo subagentes?!"                 -> autorizava
    //   "autorizo subagentes?😅"                -> autorizava
    //   'ele perguntou "autorizo subagentes?"'  -> autorizava
    //
    // A regra vale sobre a CAUDA: a frase termina como pergunta. Passou por
    // `endsWith('?')` (estreito: `?!` e `?😅` escapavam) e por `?` em qualquer
    // lugar (largo: URL, regex `\d+?` e citação alheia negavam concessão firme —
    // quatro regressões medidas na 4ª rodada). O que resolve o `?` colado na
    // palavra seguinte não é alargar esta regra, é o separador de frases cortar
    // ali — feito acima, junto com a URL que sai antes.
    //
    // Fica um caso conhecido de fora: "autorizo subagentes para responder a
    // pergunta do cliente: 'funciona offline?'" é recusado. Ele é
    // indistinguível, letra a letra, de 'ele perguntou "autorizo subagentes?"',
    // que PRECISA ser recusado — a diferença é quem fala, e isso não está no
    // texto. Entre os dois erros, esta trava fica com o que pede uma frase a
    // mais em vez do que abre o portão.
    const cauda = texto.match(/[^\p{L}\p{N}]*$/u);
    if (cauda && cauda[0].includes('?')) continue;

    // O marcador subordina por ORAÇÃO, não pela frase inteira. Vírgula separa
    // oração, e sem isso "talvez seja arriscado, autorizo subagentes mesmo
    // assim" era recusado — o `talvez` governa "seja arriscado", não a
    // concessão. O que NÃO pode acontecer é o contrário: em "nao sei se
    // autorizo subagentes, mas talvez amanha" o marcador está colado no verbo,
    // na mesma oração, e continua valendo.
    const oracoes = texto.split(/[,;:]+/);

    // AQUI MOROU uma regra que foi REMOVIDA, e o motivo fica escrito porque ele
    // é o limite do que este mecanismo consegue decidir.
    //
    // A regra dizia: mensagem que ACABA pendurada numa condição
    // ("autorizo subagentes, mas so quando") é usuário interrompido no meio da
    // restrição, logo não é concessão fechada. Ela nasceu no texto inteiro
    // (revisão 5: matava concessão de uma frase por hedge de outra), foi para a
    // frase (revisão 6: matava concessão de uma oração por hedge da oração
    // seguinte), e a revisão 6 pediu que descesse para a oração. Descer não
    // resolve, e é aí que a regra morreu:
    //
    //   "autorizo subagentes, mas so quando"             <- devia NEGAR
    //   "autorizo subagentes agora, mas fico pensando se" <- devia CONCEDER
    //
    // As duas têm a mesma forma: oração que concede, depois oração terminada em
    // subordinador nu. O que as separa é sobre O QUE a dúvida fala, e isso não
    // está na letra. Duas revisões seguidas classificaram esta regra como
    // BLOQUEANTE, sempre errando para o lado do falso negativo — a reclamação
    // que abriu este fluxo.
    //
    // Sem ela, "autorizo subagentes, mas so quando" concede. O usuário escreveu
    // "autorizo subagentes"; o limite que ele ia digitar não é representável de
    // todo jeito, porque a autorização vale pela SESSÃO, e os outros portões da
    // portaria (manifesto, worktree, `escreve`) não afrouxam com ela.
    //
    // O que continua segurando dúvida de verdade é o subordinador pendurado por
    // ORAÇÃO, logo abaixo: ali a palavra vem ANTES da concessão, e aí a frase
    // realmente subordina o que vem depois.

    // Oração que termina em subordinador pendurado ("nao sei se, no fim,
    // autorizo subagentes") joga a subordinação para a frente: a vírgula ali é
    // aposto, não fronteira de oração. Frase inteira fica hedgeada.
    //
    // A lista tinha `caso` e `quando`, e saíram na revisão de 2026-09-12: as
    // duas são palavra comum fora do papel de conjunção, e a heurística lexical
    // não distingue papel gramatical. Medido:
    //
    //   "nao sei quando, autorizo subagentes agora mesmo"  -> recusava
    //   "vai depender do caso, autorizo subagentes"        -> recusava
    //
    // Ali "quando" é tempo e "caso" é substantivo — nenhum dos dois subordina a
    // concessão, e recusar é o lado ruim do erro. `se` e `que` ficaram: pendurar
    // uma delas no fim de oração é sempre subordinação.
    //
    // E a subordinação vai para FRENTE, só para frente. Esta checagem já foi um
    // `oracoes.some(...)` sobre a frase inteira, e assim ela também pegava o
    // pendurado que vinha DEPOIS da concessão — a mesma troca de escopo que
    // matou a regra acima, um nível abaixo:
    //
    //   "autorizo subagentes agora, mas ainda fico pensando se"  -> recusava
    //
    // Ali o `se` pendurado abre uma dúvida sobre outra coisa, depois de uma
    // concessão já fechada. Agora só conta oração ANTERIOR à que concede.
    const PENDURADO = /\b(se|que)\s*$/;

    let concedeu = false;
    let herdouPendurado = false;
    for (const oracao of oracoes) {
      const o = oracao.trim();
      if (!o) continue;
      if (herdouPendurado) break;
      if (PENDURADO.test(o)) {
        herdouPendurado = true;
        continue;
      }

      const posAutoriz = o.search(/\bautorizo\b|\bautorizando\b|\bautorizar\b/);
      if (posAutoriz === -1) continue;

      let subordinada = false;
      for (const sinal of sinaisSubordinados) {
        const achado = o.match(sinal);
        if (achado && o.indexOf(achado[0]) < posAutoriz) {
          subordinada = true;
          break;
        }
      }
      if (subordinada) continue;

      concedeu = true;
      break;
    }

    // Concessão em cláusula principal, nesta frase.
    if (concedeu) return true;
  }

  return false;
}

module.exports = {
  autorizado,
  temNegacaoExplicita,
};
