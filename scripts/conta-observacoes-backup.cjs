#!/usr/bin/env node
/**
 * Conta observações em um arquivo de backup de banco de dados.
 * Uso: node scripts/conta-observacoes-backup.cjs <caminho-do-backup>
 * Saída: número inteiro
 */

const path = require('path');
const { abrirBancoSomenteLeitura } = require('./memoria.cjs');

function main() {
  const caminhoBackup = process.argv[2];

  if (!caminhoBackup) {
    console.error('Uso: node scripts/conta-observacoes-backup.cjs <caminho-do-backup>');
    process.exit(1);
  }

  const db = abrirBancoSomenteLeitura(caminhoBackup);
  if (!db) {
    console.error('erro: nao consegui abrir o backup');
    process.exit(1);
  }

  try {
    const result = db.prepare('SELECT COUNT(*) as cnt FROM observacoes').get();
    console.log(result.cnt);
  } catch (e) {
    console.error('erro: ' + e.message);
    process.exit(1);
  } finally {
    db.close();
  }
}

if (require.main === module) {
  main();
}

module.exports = { };
