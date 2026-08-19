#!/usr/bin/env node
/**
 * Teste do Achado 2: migração de schema UNIQUE(projeto, origem)
 */

const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const fs = require('fs');
const { abrirBanco, criarSchema } = require('./scripts/memoria.cjs');

const caixa = path.join(process.env.TEMP || '/tmp', 'teste-achado2-' + Math.random().toString(36).slice(2, 8));
const rainforest = path.join(caixa, 'rainforest');
fs.mkdirSync(rainforest, { recursive: true });

process.env.RFM_ROOT = rainforest;

console.log('Usando:', rainforest);
console.log('');

// Step 1: Criar banco com schema ANTIGO
console.log('== Step 1: Criar banco com schema ANTIGO ==');
const dbPath = path.join(rainforest, 'rainforest.db');
const db1 = new DatabaseSync(dbPath);
db1.exec('PRAGMA journal_mode = WAL;');

// Schema ANTIGO: sem UNIQUE(projeto, origem)
db1.exec(`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
`);

// Inserir 3 linhas
db1.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)').run('proj-a', 'obs1', '2026-01-01T10:00:00Z', 'sessao:a:offset:0');
db1.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)').run('proj-a', 'obs2', '2026-02-01T10:00:00Z', 'sessao:a:offset:100');
db1.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)').run('proj-b', 'obs3', '2026-03-01T10:00:00Z', 'sessao:b:offset:0');

db1.close();
console.log('OK: 3 linhas inseridas');

// Step 2: Verificar ANTES
console.log('');
console.log('== Step 2: ANTES da migração ==');
const db2 = new DatabaseSync(dbPath);
const cntBefore = db2.prepare('SELECT COUNT(*) as cnt FROM observacoes').all()[0].cnt;
console.log('Linhas:', cntBefore);
const idxBefore = db2.prepare(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='observacoes'`).all();
console.log('Índices:', idxBefore.length > 0 ? idxBefore.map(i => i.name).join(', ') : 'nenhum');
db2.close();

// Step 3: Executar migração
console.log('');
console.log('== Step 3: Executar criarSchema ==');
process.env.DEBUG_SCHEMA = '1';
const db3 = abrirBanco(dbPath);
criarSchema(db3);
db3.close();
console.log('OK: Migração concluída');

// Step 4: Verificar DEPOIS
console.log('');
console.log('== Step 4: DEPOIS da migração ==');
const db4 = new DatabaseSync(dbPath);
const cntAfter = db4.prepare('SELECT COUNT(*) as cnt FROM observacoes').all()[0].cnt;
console.log('Linhas:', cntAfter);
const idxAfter = db4.prepare(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='observacoes'`).all();
console.log('Índices:', idxAfter.length > 0 ? idxAfter.map(i => i.name).join(', ') : 'nenhum');

console.log('');
console.log('Dados:');
const dados = db4.prepare('SELECT id, projeto, origem FROM observacoes ORDER BY id').all();
for (const d of dados) {
  console.log('  id=' + d.id + ' projeto=' + d.projeto + ' origem=' + d.origem);
}

db4.close();

console.log('');
if (cntAfter === cntBefore) {
  console.log('✓ SUCESSO: ' + cntAfter + ' linhas preservadas');
  process.exit(0);
} else {
  console.log('✗ FALHA: ' + cntBefore + ' linhas antes, ' + cntAfter + ' depois');
  process.exit(1);
}
