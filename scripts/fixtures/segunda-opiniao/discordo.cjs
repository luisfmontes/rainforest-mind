#!/usr/bin/env node
/**
 * Fixture para segunda-opiniao: retorna veredito "discordo"
 * Lê stdin (prompt) e retorna texto com "discordo" como última linha
 */

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  const resposta = `Analisando o diff... O critério NÃO é atendido.

discordo
`;
  process.stdout.write(resposta);
  process.exit(0);
});

// Fallback para quando não há stdin
setTimeout(() => {
  const resposta = `Análise indica problema.

discordo
`;
  process.stdout.write(resposta);
  process.exit(0);
}, 500);
