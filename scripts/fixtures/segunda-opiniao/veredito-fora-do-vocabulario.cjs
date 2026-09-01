#!/usr/bin/env node
/**
 * Fixture para segunda-opiniao: retorna veredito fora do vocabulário
 * Lê stdin (prompt) e retorna texto com linha final inválida
 * Caso de teste: veredito-fora-do-vocabulario
 */

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  const resposta = `Análise...

talvez
`;
  process.stdout.write(resposta);
  process.exit(0);
});

// Fallback para quando não há stdin
setTimeout(() => {
  const resposta = `Resposta vaga.

talvez
`;
  process.stdout.write(resposta);
  process.exit(0);
}, 500);
