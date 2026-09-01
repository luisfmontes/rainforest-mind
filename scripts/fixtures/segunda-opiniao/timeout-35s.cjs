#!/usr/bin/env node
/**
 * Fixture que dorme 35 segundos.
 * Usada para testar que timeout configurável funciona.
 * 35s está entre 30s (timeout antigo fixo) e 300s (novo padrão),
 * então uma mutação que volta para 30s fixo será detectada.
 */

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  // Dorme 35 segundos
  setTimeout(() => {
    process.stdout.write('concordo\n');
    process.exit(0);
  }, 35000);
});

// Fallback também dorme 35s
setTimeout(() => {
  process.stdout.write('concordo\n');
  process.exit(0);
}, 35000);
