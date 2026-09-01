#!/usr/bin/env node
/**
 * Fixture para segunda-opiniao: modelo externo indisponível — timeout
 * Simula CLI externo que trava ou está indisponível por muito tempo
 * Dorme por um tempo muito longo, causando timeout
 * Caso de teste: externo-indisponivel-timeout
 */

// Drenata stdin para parecer normal, depois dorme muito
let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  // Dorme por 100 segundos (muito mais que qualquer timeout típico)
  setTimeout(() => {
    process.exit(0);
  }, 100000);
});

// Fallback
setTimeout(() => {
  setTimeout(() => {
    process.exit(0);
  }, 100000);
}, 500);
