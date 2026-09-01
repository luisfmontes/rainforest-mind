#!/usr/bin/env node
/**
 * Fixture para segunda-opiniao: retorna parecer multilinhas com veredito
 * Simula parecer detalhado que será capturado em stderr + veredito em stdout
 */

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', () => {
  const resposta = `Analisando o diff fornecido...

Observações:
- A estrutura está bem organizada
- O critério é parcialmente atendido
- Encontrei uma questão de borda que precisa atenção

Parecer detalhado:
O diff modifica comportamento crítico sem cobertura de teste suficiente.
No entanto, a lógica principal está correta.

Veredito final após análise completa:

concordo
`;
  process.stdout.write(resposta);
  process.exit(0);
});

// Fallback
setTimeout(() => {
  const resposta = `Análise simples: concordo
concordo
`;
  process.stdout.write(resposta);
  process.exit(0);
}, 500);
