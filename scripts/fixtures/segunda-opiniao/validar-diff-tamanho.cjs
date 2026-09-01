#!/usr/bin/env node
/**
 * Fixture para validar tamanho do prompt
 * Lê stdin (prompt) e retorna uma contagem de linhas
 * Formato de resposta: "<linhas_do_prompt>\nconcordo"
 */

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  const lines = entrada.split('\n').length;
  const resposta = `Total de linhas no prompt: ${lines}\n\nconcordo\n`;
  process.stdout.write(resposta);
  process.exit(0);
});

// Fallback
setTimeout(() => {
  const resposta = `Total: 0\n\nconcordo\n`;
  process.stdout.write(resposta);
  process.exit(0);
}, 500);
