#!/usr/bin/env node
/**
 * Membro fixture para testes — simula saída vazia (exit 0 sem escrever parecer).
 * Uso: node membro-vazio.cjs <prompt> <saida>
 *
 * Lê arquivo de prompt, mas NÃO escreve parecer (ou escreve vazio).
 * exit 0 (não é erro do membro), mas saída vazia será rejeitada na validação.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Uso: membro-vazio.cjs <prompt> <saida>');
    process.exit(1);
  }

  const [caminhoPrompt, caminhoSaida] = args;

  try {
    // Validate prompt file exists
    if (!fs.existsSync(caminhoPrompt)) {
      console.error(`Erro: arquivo de prompt não encontrado: ${caminhoPrompt}`);
      process.exit(1);
    }

    // Membro que não escreve nada (saída vazia)
    // Não escreve o arquivo de saída
    process.exit(0);
  } catch (err) {
    console.error(`Erro: ${err.message}`);
    process.exit(1);
  }
}

main();
