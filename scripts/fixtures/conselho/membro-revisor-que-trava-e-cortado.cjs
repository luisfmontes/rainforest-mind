#!/usr/bin/env node
/**
 * Revisor fixture para testes — trava além do timeout.
 * Uso: node membro-revisor-que-trava-e-cortado.cjs <prompt> <saida>
 *
 * Dorme por 5 segundos (5000ms), destinado a ser usado com timeout curto (100ms)
 * ou timeout folgado (10000ms) em testes de timeout.
 * 
 * Com timeout curto (< 5000ms): será cortado por timeout, exit null.
 * Com timeout folgado (> 5000ms): completa sono, escreve saída válida, exit 0.
 */

const fs = require('fs');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Uso: membro-revisor-que-trava-e-cortado.cjs <prompt> <saida>');
    process.exit(1);
  }

  const [caminhoPrompt, caminhoSaida] = args;

  try {
    // Validate prompt file exists
    if (!fs.existsSync(caminhoPrompt)) {
      console.error(`Erro: arquivo de prompt não encontrado: ${caminhoPrompt}`);
      process.exit(1);
    }

    // Sleep for 5 seconds (5000 ms) using setTimeout
    // This allows the timeout mechanism to interrupt if the timeout is shorter
    setTimeout(() => {
      // After sleep completes, write valid output and exit 0
      const revisao = {
        aceita: true,
        justificativa: 'Revisão após timeout delay.',
        sugestoes: [
          'Sugestão 1',
          'Sugestão 2'
        ]
      };

      fs.writeFileSync(caminhoSaida, JSON.stringify(revisao, null, 2) + '\n', 'utf8');
      process.exit(0);
    }, 5000);
  } catch (err) {
    console.error(`Erro: ${err.message}`);
    process.exit(1);
  }
}

main();
