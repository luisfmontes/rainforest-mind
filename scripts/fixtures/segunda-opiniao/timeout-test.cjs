#!/usr/bin/env node
/**
 * Fixture para testar timeout configurável.
 * Dorme indefinidamente para triggar rodarCli timeout.
 * Entra (via stdin) e nunca retorna — simula demora excessiva.
 */

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  // Dorme indefinidamente (será morto pelo timeout)
  setTimeout(() => {
    process.exit(0);
  }, 999999999);
});

// Fallback também dorme
setTimeout(() => {
  process.exit(0);
}, 999999999);
