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

        // Verifica negação explícita primeiro (a mais forte)
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
      const temSubagente = /\bsubagente\b|\bsubagentes\b|\bsub-agente\b|\bsub-agentes\b|\bagente\b|\bagentes\b/.test(normalizado);
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
  const temSubagente = /\bsubagente\b|\bsubagentes\b|\bsub-agente\b|\bsub-agentes\b/.test(normalizado);

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
  const frases = normalizado.split(/(?<=[.!?])\s+|\n+/);

  // Marcador que subordina a concessão. Só vale dentro da MESMA frase e ANTES da
  // palavra: "vou pensar no design" numa frase anterior não subordina nada.
  //
  // `posso autoriz` e `poderia autoriz` estão aqui, e não só na regra do `?`,
  // porque pergunta sem ponto de interrogação é como se digita com pressa —
  // "posso autorizar subagentes" continua sendo pedido de opinião.
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
    const texto = frase.trim();
    if (!texto) continue;

    const posAutoriz = texto.search(/\bautorizo\b|\bautorizando\b|\bautorizar\b/);
    if (posAutoriz === -1) continue;
    if (!/\bsubagente\b|\bsubagentes\b|\bsub-agente\b|\bsub-agentes\b/.test(texto)) continue;

    // PERGUNTA NÃO É CONSENTIMENTO. "posso autorizar subagentes nesse projeto ou
    // fica arriscado?" é o usuário pedindo opinião, e abria o portão. A marca é
    // o ponto de interrogação nesta frase — não no turno inteiro, senão
    // "autorizo subagentes. e o build, passou?" seria recusado.
    if (texto.endsWith('?')) continue;

    let subordinada = false;
    for (const sinal of sinaisSubordinados) {
      const achado = texto.match(sinal);
      if (achado && texto.indexOf(achado[0]) < posAutoriz) {
        subordinada = true;
        break;
      }
    }
    if (subordinada) continue;

    // Concessão em cláusula principal, nesta frase.
    return true;
  }

  return false;
}

module.exports = {
  autorizado,
  temNegacaoExplicita,
};
