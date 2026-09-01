#!/usr/bin/env node
/**
 * Fixture de teste: eco de stdin
 * Lê do stdin e escreve exatamente o mesmo byte a byte no stdout.
 * Uso sem argumentos — a entrada vem por stdin.
 */

const fs = require('fs');

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  // Echo exato do stdin — sem processamento, sem normalização
  process.stdout.write(entrada);
  process.exit(0);
});

// Timeout: se não receber nada em 2s, sai
setTimeout(() => {
  if (!entrada) {
    process.exit(0);
  }
}, 2000);
