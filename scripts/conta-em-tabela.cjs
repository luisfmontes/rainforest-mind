#!/usr/bin/env node
/**
 * Conta linhas em uma tabela de rainforest.db.
 * Uso: node scripts/conta-em-tabela.cjs <tabela> [--projeto <projeto>]
 * Saída: número inteiro (count)
 */

const path = require('path');
const { abrirBanco, resolverCaminhos } = require('./memoria.cjs');

function main() {
  const tabela = process.argv[2];

  if (!tabela) {
    console.error('Uso: node scripts/conta-em-tabela.cjs <tabela>');
    process.exit(1);
  }

  // Validar nome da tabela (simples whitelist)
  if (!/^[a-z_]+$/i.test(tabela)) {
    console.error('erro: nome de tabela inválido');
    process.exit(1);
  }

  const { caminhoDb } = resolverCaminhos();
  const conexao = abrirBanco(caminhoDb);

  try {
    const resultado = conexao.prepare(`SELECT COUNT(*) as cnt FROM ${tabela}`).get();
    console.log(resultado.cnt || 0);
  } catch (e) {
    console.error('erro: ' + e.message);
    process.exit(1);
  } finally {
    conexao.close();
  }
}

if (require.main === module) {
  main();
}

module.exports = {};
