#!/usr/bin/env node

/**
 * Conta as ocorrências de um trecho de texto num texto maior.
 *
 * @param {string} texto - O texto a buscar em
 * @param {string} trecho - O trecho a contar
 * @returns {number} O número de vezes que `trecho` aparece em `texto`
 */
function contarOcorrencias(texto, trecho) {
  if (!texto || !trecho) return 0;
  return texto.split(trecho).length - 1;
}

module.exports = { contarOcorrencias };
