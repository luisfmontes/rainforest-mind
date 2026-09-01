#!/usr/bin/env node
/**
 * Membro fixture para testes de injeção — deixa uma marca se foi chamado.
 * Uso: node membro-marca-injecao.cjs <prompt> <saida>
 *
 * Escreve um marcador em um arquivo fixo e um parecer válido.
 * A existência do marcador prova que a injeção foi usada.
 * exit 0 em sucesso, exit 1 em erro.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Uso: membro-marca-injecao.cjs <prompt> <saida>');
    process.exit(1);
  }

  const [caminhoPrompt, caminhoSaida] = args;

  try {
    // Validate prompt file exists
    if (!fs.existsSync(caminhoPrompt)) {
      console.error(`Erro: arquivo de prompt não encontrado: ${caminhoPrompt}`);
      process.exit(1);
    }

    // Deixar uma marca em um arquivo fixo (relativo ao cwd)
    // Isto prova que a injeção foi usada
    const marcador = path.join(process.cwd(), '.marca-injecao-usada');
    fs.writeFileSync(marcador, 'Injeção foi usada em ' + new Date().toISOString() + '\n');

    // Generate a valid parecer JSON
    const parecer = {
      posicao: 'Parecer de teste com injeção marcada.',
      argumentos: ['Argumento testado'],
      objecoes: [],
      riscos: []
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
