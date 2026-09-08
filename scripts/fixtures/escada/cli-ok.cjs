#!/usr/bin/env node
/**
 * CLI fake para testes — retorna código curto que passa no gate
 * Uso: echo "prompt" | node cli-ok.cjs
 */
const dublador = require('../../dubliador-llm-ok.cjs');

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', async () => {
  const resultado = await dublador.chamarLLM(entrada);
  console.log(resultado || '');
});
