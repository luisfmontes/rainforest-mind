const fs = require('fs');

/**
 * Lê a autorização de subagentes do usuário no transcript.
 *
 * Estratégia:
 * - Lê a cauda do arquivo para não estourar orçamento de tempo.
 *   Se arquivo < 2 MB: lê arquivo inteiro (caso comum).
 *   Se arquivo >= 2 MB: lê apenas últimos 1 MB.
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

    // Lê a cauda para performance (nunca lê arquivo inteiro > 2 MB)
    // Limite 2 MB escolhido pq a maioria das sessões cabe: transcript real é 1,5 MB.
    // Se arquivo >= 2 MB, lê últimos 1 MB (capture ~300-400 linhas desde o fim).
    // Trade-off: autorização dada muito cedo (primeiras 1%) em arquivo gigante não é
    // capturada. Aceitável: lê 1 MB em ~30ms, nunca bloqueia o hook.
    const cauda_bytes = fileSize < 2 * 1024 * 1024 ? fileSize : 1024 * 1024;
    const startPos = Math.max(0, fileSize - cauda_bytes);

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

  for (const negacao of negacoes) {
    if (negacao.test(normalizado)) {
      return true;
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
