#!/usr/bin/env node
/**
 * Fixture para salvar o prompt recebido em arquivo
 * Lê stdin (prompt) e salva em /tmp/segunda-opiniao-prompt.txt
 * Retorna "concordo" como veredito
 */

const fs = require('fs');
const path = require('path');

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  try {
    fs.writeFileSync('/tmp/segunda-opiniao-prompt.txt', entrada, 'utf8');
  } catch (e) {
    // Ignore write errors
  }
  process.stdout.write('concordo\n');
  process.exit(0);
});

// Fallback
setTimeout(() => {
  process.stdout.write('concordo\n');
  process.exit(0);
}, 500);
