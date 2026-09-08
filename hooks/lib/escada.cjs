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
 * Extrai a escada de degraus YAGNI do texto da skill.
 * @param {string} skillText - Conteúdo de skills/modo-dev/SKILL.md
 * @returns {string} A escada em prosa, ou string vazia se não encontrada
 */
function extrairEscada(skillText) {
  if (!skillText || typeof skillText !== 'string') {
    return '';
  }

  const inicioMarker = '<!-- escada-inicio -->';
  const fimMarker = '<!-- escada-fim -->';

  const inicioIdx = skillText.indexOf(inicioMarker);
  if (inicioIdx === -1) {
    return '';
  }

  const fimIdx = skillText.indexOf(fimMarker, inicioIdx);
  if (fimIdx === -1) {
    return '';
  }

  const inicio = inicioIdx + inicioMarker.length;
  const escadaRaw = skillText.substring(inicio, fimIdx).trim();

  // Normalizar: remover linhas vazias excessivas, preservar o conteúdo
  const linhas = escadaRaw
    .split('\n')
    .map(l => l.trim())
    .filter(l => l.length > 0)
    .join('\n');

  return linhas;
}

module.exports = {
  extrairEscada,
};
