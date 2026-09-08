#!/usr/bin/env node
/**
 * Extrator da escada YAGNI/laziness de skills/modo-dev/SKILL.md
 *
 * Esta é a ÚNICA fonte da escada. Todos os outros arquivos que precisem dela
 * devem chamar `extrairEscada(skillText)` em vez de replicá-la.
 *
 * A escada é delimitada por marcadores HTML estáveis (`<!-- escada-inicio -->`
 * e `<!-- escada-fim -->`). A mudança no arquivo de origem é automaticamente
 * refletida em todos os consumidores (hooks, agentes, etc).
 */

/**
 * Extrai um bloco delimitado por marcadores HTML.
 * @param {string} text - Texto de entrada
 * @param {string} inicioMarker - Marcador de início
 * @param {string} fimMarker - Marcador de fim
 * @returns {string} O bloco extraído, ou string vazia se não encontrado
 */
function extrairBloco(text, inicioMarker, fimMarker) {
  if (!text || typeof text !== 'string') {
    return '';
  }

  const inicioIdx = text.indexOf(inicioMarker);
  if (inicioIdx === -1) {
    return '';
  }

  const fimIdx = text.indexOf(fimMarker, inicioIdx);
  if (fimIdx === -1) {
    return '';
  }

  const inicio = inicioIdx + inicioMarker.length;
  const blocoRaw = text.substring(inicio, fimIdx).trim();

  // Normalizar: remover linhas vazias excessivas, preservar o conteúdo
  const linhas = blocoRaw
    .split('\n')
    .map(l => l.trim())
    .filter(l => l.length > 0)
    .join('\n');

  return linhas;
}

/**
 * Extrai a escada de degraus YAGNI do texto da skill.
 * @param {string} skillText - Conteúdo de skills/modo-dev/SKILL.md
 * @returns {string} A escada em prosa, ou string vazia se não encontrada
 */
function extrairEscada(skillText) {
  return extrairBloco(skillText, '<!-- escada-inicio -->', '<!-- escada-fim -->');
}

/**
 * Extrai as proteções (carve-outs) e a regra de causa raiz do texto da skill.
 * @param {string} skillText - Conteúdo de skills/modo-dev/SKILL.md
 * @returns {string} Os carve-outs em prosa, ou string vazia se não encontrados
 */
function extrairCarveOuts(skillText) {
  return extrairBloco(skillText, '<!-- carve-outs-inicio -->', '<!-- carve-outs-fim -->');
}

/**
 * Comprime a escada para o nível 'enxuto'.
 * Mantém a estrutura de 7 degraus mas com texto mínimo.
 *
 * @param {string} escada - Texto da escada completa
 * @returns {string} Escada comprimida, ou string vazia se falhar
 */
function comprimirEscada(escada) {
  if (!escada) {
    return '';
  }

  // Dividir em linhas de degraus: cada degrau começa com "**Degrau N.**"
  const degraus = [];
  const linhas = escada.split('\n');
  let degrauAtual = [];

  for (const linha of linhas) {
    if (linha.match(/^\*\*Degrau \d+\.\*\*/)) {
      if (degrauAtual.length > 0) {
        degraus.push(degrauAtual.join('\n'));
      }
      degrauAtual = [linha];
    } else {
      degrauAtual.push(linha);
    }
  }
  if (degrauAtual.length > 0) {
    degraus.push(degrauAtual.join('\n'));
  }

  // Comprimir: extrair primeira sentença de cada degrau
  const comprimidos = degraus.map((d) => {
    // Extrair a linha do degrau (começa com **Degrau N.**)
    const match = d.match(/^\*\*Degrau (\d+)\.\*\* (.+)/);
    if (!match) {
      return '';
    }

    const numero = match[1];
    const resto = match[2];

    // Primeira sentença é até o primeiro ponto (.) seguido de espaço ou fim
    const sentencaMatch = resto.match(/^([^.]+\.)/);
    const primeira = sentencaMatch ? sentencaMatch[1] : resto;

    return `**Degrau ${numero}.** ${primeira}`;
  });

  return comprimidos.filter((d) => d.length > 0).join('\n');
}

/**
 * Filtra a escada por nível de intensidade.
 *
 * Níveis disponíveis:
 *   - 'enxuto': escada comprimida (7 degraus resumidos) + carve-outs
 *   - 'padrão': escada completa (7 degraus + carve-outs)
 *
 * @param {string} escada - Texto da escada extraída
 * @param {string} carveOuts - Texto dos carve-outs extraído
 * @param {string} nivel - Nível de intensidade ('enxuto', 'padrão')
 * @returns {string} A escada filtrada de acordo com o nível
 */
function filtrarEscadaPorNivel(escada, carveOuts, nivel) {
  // Best-effort: nível inválido cai no padrão
  const niveisValidos = ['enxuto', 'padrão'];
  const nivelEfetivo = niveisValidos.includes(nivel) ? nivel : 'padrão';

  let resultado = '';

  if (nivelEfetivo === 'enxuto') {
    // Escada comprimida + carve-outs
    const escadaComprimida = comprimirEscada(escada);
    if (escadaComprimida) {
      resultado = escadaComprimida;
    }
  } else {
    // 'padrão': escada completa
    if (escada) {
      resultado = escada;
    }
  }

  // Adicionar carve-outs em todos os níveis
  if (carveOuts) {
    if (resultado) {
      resultado += '\n\n' + carveOuts;
    } else {
      resultado = carveOuts;
    }
  }

  return resultado;
}

module.exports = {
  extrairEscada,
  extrairCarveOuts,
  filtrarEscadaPorNivel,
  comprimirEscada,
};
