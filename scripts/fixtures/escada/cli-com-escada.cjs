#!/usr/bin/env node
/**
 * CLI fake para testes — retorna código diferente conforme tenha escada
 * Código COM escada é mais curto (ganho > 0)
 * Uso: echo "prompt" | node cli-com-escada.cjs
 */
const dublador = require('./dublador-com-escada.cjs');

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', async () => {
  const resultado = await dublador.chamarLLM(entrada);
  console.log(resultado || '');
});
