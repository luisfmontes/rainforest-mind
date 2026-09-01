#!/usr/bin/env node
/**
 * Membro fixture para testes — emite JSON inválido no STDOUT.
 * Uso: node membro-stdout-json-invalido.cjs <prompt> <saida>
 *
 * Diferente de `membro-json-invalido.cjs`, que ESCREVE o arquivo de saída
 * direto: esta fixture imita um CLI externo de verdade — não toca no arquivo
 * de saída, só imprime no stdout. É a única forma de exercitar o ramo de
 * parse dos adaptadores, que leem o stdout e escrevem a saída eles mesmos.
 *
 * Sai 0 (o CLI "funcionou"); quem tem de reprovar é o adaptador, ao não
 * conseguir extrair JSON — e sem criar o arquivo de saída.
 */

const fs = require('fs');

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) {
    console.error('Uso: membro-stdout-json-invalido.cjs <prompt> <saida>');
    process.exit(1);
  }

  const [caminhoPrompt] = args;

  if (!fs.existsSync(caminhoPrompt)) {
    console.error(`Erro: arquivo de prompt não encontrado: ${caminhoPrompt}`);
    process.exit(1);
  }

  // Nada de cerca ```json, nada de {...}, nada de JSON cru parseável:
  // as três tentativas do extrairJson têm de falhar.
  process.stdout.write('isso nao e JSON valido {]\n');
  process.exit(0);
}

main();
