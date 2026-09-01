#!/usr/bin/env node
/**
 * Membro fixture para testes — simula falha (exit ≠ 0).
 * Uso: node membro-falha.cjs <prompt> <saida>
 *
 * Lê arquivo de prompt, mas falha (exit 1) sem escrever parecer.
 * Simula indisponibilidade ou erro de processamento.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Uso: membro-falha.cjs <prompt> <saida>');
    process.exit(1);
  }

  const [caminhoPrompt, caminhoSaida] = args;

  try {
    // Validate prompt file exists
    if (!fs.existsSync(caminhoPrompt)) {
      console.error(`Erro: arquivo de prompt não encontrado: ${caminhoPrompt}`);
      process.exit(1);
    }

    // Membro indisponível: não escreve parecer, sai com erro
    console.error('Erro: membro indisponível ou falha ao processar');
    process.exit(1);
  } catch (err) {
    console.error(`Erro: ${err.message}`);
    process.exit(1);
  }
}

main();
