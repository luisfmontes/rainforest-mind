#!/usr/bin/env node
/**
 * Fixture para segunda-opiniao: modelo externo indisponível — stdout vazio
 * Simula CLI externo que processa a entrada mas devolve nada (ex.: crash silencioso)
 * Sai com exit 0 mas stdout é vazio
 * Caso de teste: externo-indisponivel-vazio
 */

// Drena stdin para parecer normal
let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  // Não escreve nada, só sai
  process.exit(0);
});

// Fallback
setTimeout(() => {
  process.exit(0);
}, 500);
