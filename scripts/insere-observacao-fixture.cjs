#!/usr/bin/env node
/**
 * Insere uma observação de teste (fixture) em um banco de rainforest.
 * Uso: node scripts/insere-observacao-fixture.cjs <projeto> <conteudo>
 */

const path = require('path');
const { abrirBanco, resolverCaminhos } = require('./memoria.cjs');

function main() {
  const projeto = process.argv[2];
  const conteudo = process.argv[3];

  if (!projeto || !conteudo) {
    console.error('Uso: node scripts/insere-observacao-fixture.cjs <projeto> <conteudo>');
    process.exit(1);
  }

  const { caminhoDb } = resolverCaminhos();
  const conexao = abrirBanco(caminhoDb);

  try {
    conexao.exec('PRAGMA journal_mode = WAL;');
    conexao.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em) VALUES (?, ?, ?)')
      .run(projeto, conteudo, '2026-08-17T10:00:00');

    // Consolidar o WAL no arquivo principal antes de retornar
    conexao.exec('PRAGMA wal_checkpoint(TRUNCATE);');

    console.log('ok');
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
