const fs = require('fs');

/**
 * Lê a autorização de subagentes do usuário no transcript.
 *
 * Estratégia:
 * - Lê o arquivo INTEIRO. A cauda foi tentada e removida — ver o comentário do
 *   `TETO_GUARDA` abaixo, que traz a medição que a matou.
 * - Procura por linhas com type:"user", "queue-operation" ou "attachment"
 * - NORMALIZA acentos antes de todo casamento (NFD + remoção de diacríticos)
 * - Reconhece "autorizo" perto de "subagente(s)" por frase livre (não comando)
 * - Nega se marcador subordinado ("falo que", "disse que", etc.) envolver "autorizo"
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
const ENVELOPE_DE_SISTEMA = /<task-notification>|<system-reminder>|<cross-session-message|<command-name>/;

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
  } else if (obj.type === 'attachment' && obj.attachment) {
    conteudo = obj.attachment.prompt;
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
  } else if (obj.type === 'attachment' && obj.attachment) {
    conteudo = obj.attachment.prompt;
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

  // Verifica se a autorização está em cláusula PRINCIPAL
  // Sinais de cláusula SUBORDINADA (também normalizados): "falo que", "disse que", "digo que", "quando eu autorizo", "se eu autorizo", "que autorizo"
  const sinaisSubordinados = [
    /\bfalo\s+que\b/,
    /\bdisse\s+que\b/,
    /\bdigo\s+que\b/,
    /\bquando\s+eu\s+autorizo\b/,
    /\bse\s+eu\s+autorizo\b/,
    /\bque\s+autorizo\b/,
  ];

  // Se a palavra "autorizo" estiver após um dos sinais subordinados, NÃO é autorização principal
  for (const sinal of sinaisSubordinados) {
    // Encontra posição do sinal
    const matchSinal = normalizado.match(sinal);
    if (matchSinal) {
      // Encontra posição de "autorizo" após o sinal
      const posicaoSinal = normalizado.indexOf(matchSinal[0]);
      const trechoApos = normalizado.substring(posicaoSinal);

      if (/\bautorizo\b|\bautorizando\b|\bautorizar\b/.test(trechoApos)) {
        // Autorização está dentro de cláusula subordinada
        return false;
      }
    }
  }

  // Se chegou aqui, é autorização em cláusula principal
  return true;
}

module.exports = {
  autorizado,
};
