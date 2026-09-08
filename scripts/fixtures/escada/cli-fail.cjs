#!/usr/bin/env node
/**
 * CLI fake para testes — retorna null (falha no gate)
 * Uso: echo "prompt" | node cli-fail.cjs
 */
const dublador = require('../../dubliador-llm-fail.cjs');

let entrada = '';
process.stdin.on('data', chunk => {
  entrada += chunk.toString();
});

process.stdin.on('end', async () => {
  const resultado = await dublador.chamarLLM(entrada);
  console.log(resultado || '');
});
