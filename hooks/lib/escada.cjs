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
 * Filtra a escada por nível de intensidade.
 *
 * Níveis disponíveis:
 *   - 'enxuto': apenas carve-outs (proteções), sem degraus
 *   - 'padrão': escada completa (7 degraus + carve-outs)
 *   - 'completo': escada completa com detalhes expandidos (igual a padrão nesta versão)
 *
 * @param {string} escada - Texto da escada extraída
 * @param {string} carveOuts - Texto dos carve-outs extraído
 * @param {string} nivel - Nível de intensidade ('enxuto', 'padrão', 'completo')
 * @returns {string} A escada filtrada de acordo com o nível
 */
function filtrarEscadaPorNivel(escada, carveOuts, nivel) {
  // Best-effort: nível inválido cai no padrão
  const niveisValidos = ['enxuto', 'padrão', 'completo'];
  const nivelEfetivo = niveisValidos.includes(nivel) ? nivel : 'padrão';

  if (nivelEfetivo === 'enxuto') {
    // Apenas carve-outs, sem degraus
    return carveOuts || '';
  }

  // 'padrão' e 'completo' retornam a escada + carve-outs
  // (Na versão atual, ambos são idênticos)
  let resultado = '';
  if (escada) {
    resultado = escada;
  }
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
};
