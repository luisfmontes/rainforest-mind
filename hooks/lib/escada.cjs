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

module.exports = {
  extrairEscada,
  extrairCarveOuts,
};
