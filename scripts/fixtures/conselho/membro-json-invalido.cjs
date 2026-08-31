#!/usr/bin/env node
/**
 * Membro fixture para testes — escreve JSON inválido.
 * Uso: node membro-json-invalido.cjs <prompt> <saida>
 *
 * Lê arquivo de prompt, escreve saída que não é JSON válido.
 * exit 0 (não é erro do membro), mas JSON será rejeitado na validação.
 */

const fs = require('fs');
const path = require('path');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Uso: membro-json-invalido.cjs <prompt> <saida>');
    process.exit(1);
  }

  const [caminhoPrompt, caminhoSaida] = args;

  try {
    // Validate prompt file exists
    if (!fs.existsSync(caminhoPrompt)) {
      console.error(`Erro: arquivo de prompt não encontrado: ${caminhoPrompt}`);
      process.exit(1);
    }

    // Write invalid JSON (broken JSON syntax)
    fs.writeFileSync(caminhoSaida, 'isso não é JSON válido {]', 'utf8');
    process.exit(0);
  } catch (err) {
    console.error(`Erro: ${err.message}`);
    process.exit(1);
  }
}

main();
