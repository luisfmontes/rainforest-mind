#!/usr/bin/env node
/**
 * Membro fixture para testes — escreve um parecer válido.
 * Uso: node membro-ok.cjs <prompt> <saida>
 *
 * Lê arquivo de prompt, escreve JSON de parecer no arquivo de saída.
 * exit 0 em sucesso, exit 1 em erro.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Uso: membro-ok.cjs <prompt> <saida>');
    process.exit(1);
  }

  const [caminhoPrompt, caminhoSaida] = args;

  try {
    // Validate prompt file exists
    if (!fs.existsSync(caminhoPrompt)) {
      console.error(`Erro: arquivo de prompt não encontrado: ${caminhoPrompt}`);
      process.exit(1);
    }

    const prompt = fs.readFileSync(caminhoPrompt, 'utf8');

    // Generate a valid parecer JSON
    const parecer = {
      posicao: 'Esta é uma posição fundamentada.',
      argumentos: [
        'Argumento 1 bem fundamentado',
        'Argumento 2 bem fundamentado',
        'Argumento 3 bem fundamentado'
      ],
      objecoes: [
        'Objeção concreta e verificável à questão',
        'Segundo ponto de risco identificado'
      ],
      riscos: [
        'Risco potencial 1',
        'Risco potencial 2'
      ]
    };

    // Write saida file
    fs.writeFileSync(caminhoSaida, JSON.stringify(parecer, null, 2) + '\n', 'utf8');
    process.exit(0);
  } catch (err) {
    console.error(`Erro: ${err.message}`);
    process.exit(1);
  }
}

main();
