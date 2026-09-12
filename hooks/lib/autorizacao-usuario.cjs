const fs = require('fs');

/**
 * Lê a autorização de subagentes do usuário no transcript.
 *
 * Estratégia:
 * - Lê apenas a cauda do arquivo (últimos ~50 KB) para não estourar orçamento de tempo
 * - Procura por linhas com type:"user", "queue-operation" ou "attachment"
 * - Reconhece "autorizo" perto de "subagente(s)" por frase livre (não comando)
 * - Nega se marcador subordinado ("falo que", "disse que", etc.) envolver "autorizo"
 * - Nega se houver "não autorizo" explícito
 * - Retorna true se houver autorização válida na cauda, false caso contrário
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

    // Lê apenas a cauda: até 1 MB (se arquivo > 2 MB) ou arquivo inteiro (se < 2 MB)
    // Justificativa: sessão típica tem 2400-3400 bytes/linha (444 linhas em 1,05 MB).
    // 1 MB captura ~295-415 linhas desde o final. Medido no transcript real:
    // autorização em linha 88-113 está em byte ~512 KB, então 1 MB garante cobertura.
    // Se arquivo < 2 MB, lê arquivo inteiro (rápido, < 50 ms para 1,5 MB).
    // Trade-off: autorização dada MUITO cedo (primeiras 1% em arquivo > 2 MB) pode
    // não ser capturada. Aceitável: leitor é rápido ~20ms, nunca bloqueia.
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
 * Verifica se objeto contém negação explícita ("não autorizo")
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

  return /\bnão\s+autorizo|não\s+autorizar/i.test(conteudo);
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

  const conteudoLower = conteudo.toLowerCase();

  // Procura por "autorizo" ou "autorizar" perto de "subagente(s)"
  const temAutoriz = /\bautorizo|autorizando|autorizar|autorização/i.test(conteudoLower);
  const temSubagente = /\bsubagente|subagentes|sub-agente|sub-agentes/i.test(conteudoLower);

  if (!temAutoriz || !temSubagente) {
    return false;
  }

  // Verifica se a autorização está em cláusula PRINCIPAL
  // Sinais de cláusula SUBORDINADA: "falo que", "disse que", "digo que", "quando eu autorizo", "se eu autorizo", "que autorizo"
  const sinaisSubordinados = [
    /\bfalo\s+que\b/i,
    /\bdisse\s+que\b/i,
    /\bdigo\s+que\b/i,
    /\bquando\s+eu\s+autorizo/i,
    /\bse\s+eu\s+autorizo/i,
    /\bque\s+autorizo/i,
  ];

  // Se a palavra "autorizo" estiver após um dos sinais subordinados, NÃO é autorização principal
  for (const sinal of sinaisSubordinados) {
    // Encontra posição do sinal
    const matchSinal = conteudoLower.match(sinal);
    if (matchSinal) {
      // Encontra posição de "autorizo" após o sinal
      const posicaoSinal = conteudoLower.indexOf(matchSinal[0]);
      const trechoApos = conteudoLower.substring(posicaoSinal);

      if (/\bautorizo|autorizando|autorizar/i.test(trechoApos)) {
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
