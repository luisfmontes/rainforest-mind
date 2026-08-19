#!/usr/bin/env node
/**
 * Teste do Achado 4: /saude detecta schema quebrado
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const caixa = path.join(process.env.TEMP || '/tmp', 'teste-achado4-' + Math.random().toString(36).slice(2, 8));
fs.mkdirSync(caixa, { recursive: true });

process.env.RFM_ROOT = path.join(caixa, 'rainforest');
fs.mkdirSync(process.env.RFM_ROOT, { recursive: true });

console.log('Teste Achado 4: /saude detecta schema quebrado');
console.log('usando:', process.env.RFM_ROOT);
console.log('');

// Step 1: Criar banco com schema ANTIGO (sem UNIQUE constraint)
console.log('== Step 1: Criar banco com schema ANTIGO ==');
const { DatabaseSync } = require('node:sqlite');
const dbPath = path.join(process.env.RFM_ROOT, 'rainforest.db');
const db = new DatabaseSync(dbPath);
db.exec('PRAGMA journal_mode = WAL;');
db.exec(`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
`);
db.close();
console.log('OK: banco criado com schema antigo (sem UNIQUE)');

// Step 2: Executar /saude
console.log('');
console.log('== Step 2: Executar node scripts/saude.cjs ==');
const output = execSync('node scripts/saude.cjs', { encoding: 'utf8' });
console.log(output);

// Step 3: Verificar se detectou o problema
console.log('');
console.log('== Step 3: Verificação ==');
const temAlerta = output.includes('esquema de banco');
const temMensagemMigração = output.includes('UNIQUE(projeto, origem)') || output.includes('offset_processado');

if (temAlerta && temMensagemMigração) {
  console.log('✓ SUCESSO: /saude detectou schema quebrado');
  process.exit(0);
} else {
  console.log('✗ FALHA: /saude não detectou problema');
  process.exit(1);
}
