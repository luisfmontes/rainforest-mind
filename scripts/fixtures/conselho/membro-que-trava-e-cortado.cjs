#!/usr/bin/env node
/**
 * Membro fixture para testes — trava além do timeout.
 * Uso: node membro-que-trava-e-cortado.cjs <prompt> <saida>
 *
 * Dorme por 500ms, destinado a ser usado com timeout curto (100ms).
 * Deve ser cortado por timeout em testes.
 * exit 1 (timeout), não escreve arquivo de saída.
 */

const fs = require('fs');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Uso: membro-que-trava-e-cortado.cjs <prompt> <saida>');
    process.exit(1);
  }

  const [caminhoPrompt, caminhoSaida] = args;

  try {
    // Validate prompt file exists
    if (!fs.existsSync(caminhoPrompt)) {
      console.error(`Erro: arquivo de prompt não encontrado: ${caminhoPrompt}`);
      process.exit(1);
    }

    // Sleep for 500ms (500 ms) — to be used with a timeout shorter than this
    const sleepMs = 500;
    const endTime = Date.now() + sleepMs;
    while (Date.now() < endTime) {
      // Busy wait
    }

    // This should not be reached due to timeout
    console.error('Erro: sleep completado (não deveria acontecer)');
    process.exit(1);
  } catch (err) {
    console.error(`Erro: ${err.message}`);
    process.exit(1);
  }
}

main();
