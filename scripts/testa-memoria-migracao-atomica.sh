#!/bin/bash
# Bateria: Migração atômica + recuperação de banco órfão (Tarefa 20)
#
# Lado (a): Transação RENAME → CREATE → INSERT → DROP dentro de BEGIN TRANSACTION.
#
# Lado (b): Recuperação de banco que JÁ ESTÁ no estado quebrado
#           (observacoes_backup existe, observacoes não).
#
# Uso: bash scripts/testa-memoria-migracao-atomica.sh
# Exit: 0 se ambos os lados passam, 1 caso contrário

set -e

RAIZ=$(pwd)
TEMP_DIR="${RFM_ROOT:-.rainforest-teste-migracao}"

cleanup() {
  rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

cleanup
mkdir -p "$TEMP_DIR"

export RFM_ROOT="$TEMP_DIR"

echo "[LADO A: Transação atômica]"
echo "[1] Criar banco com esquema legado (sem UNIQUE)..."

node << 'CREATE_LEGACY'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');

const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));

db.exec(`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
  CREATE TABLE marca_dagua (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    sessao TEXT NOT NULL,
    arquivo TEXT NOT NULL,
    offset INTEGER DEFAULT 0,
    processada_em TEXT
  );
`);

const stmt = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
stmt.run('p1', 'obs1', '2026-01-01', 'o1');
stmt.run('p1', 'obs2', '2026-01-02', 'o2');
stmt.run('p2', 'obs3', '2026-01-03', 'o3');
stmt.run('p2', 'obs4', '2026-01-04', 'o4');

db.close();
CREATE_LEGACY

LINHAS_ANTES=$(node << 'COUNT_BEFORE'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cnt = db.prepare('SELECT COUNT(*) as c FROM observacoes').all()[0].c;
console.log(cnt);
db.close();
COUNT_BEFORE
)
echo "Linhas antes: $LINHAS_ANTES"

echo "[2] Verificar constraint ausente..."
CONSTRAINT=$(node << 'CHECK_CONSTRAINT'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const indices = db.prepare(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='observacoes'`).all();
let temUnique = false;
for (const idx of indices) {
  const cols = db.prepare(`PRAGMA index_info('${idx.name}')`).all();
  if (cols.length === 2 && cols[0].name === 'projeto' && cols[1].name === 'origem') {
    temUnique = true;
    break;
  }
}
console.log(temUnique ? 'sim' : 'nao');
db.close();
CHECK_CONSTRAINT
)
echo "Tem UNIQUE(projeto, origem): $CONSTRAINT"

[ "$CONSTRAINT" = "nao" ] || { echo "❌ Erro: esquema deveria ser legado"; exit 1; }
echo "✓ Esquema legado confirmado"

echo "[3] Chamar memoria.cjs iniciar..."
node scripts/memoria.cjs iniciar >/dev/null 2>&1

echo "[4] Verificar linhas preservadas..."
LINHAS_DEPOIS=$(node << 'COUNT_AFTER'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cnt = db.prepare('SELECT COUNT(*) as c FROM observacoes').all()[0].c;
console.log(cnt);
db.close();
COUNT_AFTER
)
echo "Linhas depois: $LINHAS_DEPOIS"

[ "$LINHAS_ANTES" = "$LINHAS_DEPOIS" ] || { echo "❌ Erro: linhas perdidas"; exit 1; }

echo "[5] Verificar UNIQUE criado..."
CONSTRAINT=$(node << 'CHECK_UNIQUE'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const indices = db.prepare(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='observacoes'`).all();
let temUnique = false;
for (const idx of indices) {
  const cols = db.prepare(`PRAGMA index_info('${idx.name}')`).all();
  if (cols.length === 2 && cols[0].name === 'projeto' && cols[1].name === 'origem') {
    temUnique = true;
    break;
  }
}
console.log(temUnique ? 'ok' : 'nao');
db.close();
CHECK_UNIQUE
)
echo "Constraint criado: $CONSTRAINT"
[ "$CONSTRAINT" = "ok" ] || { echo "❌ Erro: UNIQUE não criado"; exit 1; }

echo "[6] Verificar limpeza (sem backup)..."
TEMBACKUP=$(node << 'CHECK_BACKUP'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const tabelas = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='observacoes_backup'`).all();
console.log(tabelas.length > 0 ? 'sim' : 'nao');
db.close();
CHECK_BACKUP
)
echo "Tabela observacoes_backup existe: $TEMBACKUP"
[ "$TEMBACKUP" = "nao" ] || { echo "❌ Erro: backup deveria ser removido"; exit 1; }

echo ""
echo "[LADO B: Recuperação de banco órfão]"

rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo "[7] Criar banco quebrado (observacoes_backup órfã)..."
node << 'CREATE_BROKEN'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');

const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));

db.exec(`
  CREATE TABLE marca_dagua (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    sessao TEXT NOT NULL,
    arquivo TEXT NOT NULL,
    offset INTEGER DEFAULT 0,
    offset_processado INTEGER DEFAULT 0,
    processada_em TEXT
  );
  CREATE TABLE observacoes_backup (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
`);

const stmt = db.prepare('INSERT INTO observacoes_backup (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
stmt.run('p1', 'dado1', '2026-01-01', 'o1');
stmt.run('p2', 'dado2', '2026-01-02', 'o2');

db.close();
CREATE_BROKEN
echo "✓ Banco quebrado criado"

echo "[8] Verificar estado inicial..."
STATE=$(node << 'CHECK_STATE'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));

const temObservacoes = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='observacoes'`).all().length > 0;
const temBackup = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='observacoes_backup'`).all().length > 0;
const cntBackup = temBackup ? db.prepare('SELECT COUNT(*) as c FROM observacoes_backup').all()[0].c : 0;

console.log((temObservacoes ? '1' : '0') + ' ' + cntBackup);
db.close();
CHECK_STATE
)
echo "observacoes existe: $(echo $STATE | cut -d' ' -f1), observacoes_backup: $(echo $STATE | cut -d' ' -f2) linhas"

echo "[9] Chamar memoria.cjs iniciar..."
node scripts/memoria.cjs iniciar >/dev/null 2>&1

echo "[10] Verificar recuperação..."
RESULTADO=$(node << 'CHECK_RECOVERED'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));

const temObservacoes = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='observacoes'`).all().length > 0;
const temBackup = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='observacoes_backup'`).all().length > 0;
const cntObs = temObservacoes ? db.prepare('SELECT COUNT(*) as c FROM observacoes').all()[0].c : 0;

console.log((temObservacoes && !temBackup && cntObs === 2) ? 'ok' : 'falha');
db.close();
CHECK_RECOVERED
)
echo "Recuperação: $RESULTADO"
[ "$RESULTADO" = "ok" ] || { echo "❌ Erro: banco não recuperado"; exit 1; }

echo ""
echo "[LADO C: Banco com observacoes vazia + backup órfã (Tarefa 23 - item 4)]"

rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo "[11] Criar banco com observacoes vazia + observacoes_backup com dados..."
node << 'CREATE_EMPTY_WITH_BACKUP'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');

const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));

db.exec(`
  CREATE TABLE marca_dagua (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    sessao TEXT NOT NULL,
    arquivo TEXT NOT NULL,
    offset INTEGER DEFAULT 0,
    offset_processado INTEGER DEFAULT 0,
    processada_em TEXT
  );
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
  CREATE TABLE observacoes_backup (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
`);

const stmt = db.prepare('INSERT INTO observacoes_backup (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
stmt.run('p1', 'dado1', '2026-01-01', 'o1');
stmt.run('p2', 'dado2', '2026-01-02', 'o2');

db.close();
CREATE_EMPTY_WITH_BACKUP
echo "✓ Banco com observacoes vazia + backup criado"

echo "[12] Verificar estado inicial..."
STATE=$(node << 'CHECK_EMPTY_STATE'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));

const cntObs = db.prepare('SELECT COUNT(*) as c FROM observacoes').all()[0].c;
const cntBackup = db.prepare('SELECT COUNT(*) as c FROM observacoes_backup').all()[0].c;

console.log(cntObs + ' ' + cntBackup);
db.close();
CHECK_EMPTY_STATE
)
echo "observacoes: $(echo $STATE | cut -d' ' -f1) linhas, observacoes_backup: $(echo $STATE | cut -d' ' -f2) linhas"

echo "[13] Chamar memoria.cjs iniciar..."
node scripts/memoria.cjs iniciar >/dev/null 2>&1

echo "[14] Verificar recuperação..."
RESULTADO=$(node << 'CHECK_EMPTY_RECOVERED'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));

const temObservacoes = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='observacoes'`).all().length > 0;
const temBackup = db.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name='observacoes_backup'`).all().length > 0;
const cntObs = temObservacoes ? db.prepare('SELECT COUNT(*) as c FROM observacoes').all()[0].c : 0;

console.log((temObservacoes && !temBackup && cntObs === 2) ? 'ok' : 'falha');
db.close();
CHECK_EMPTY_RECOVERED
)
echo "Recuperação: $RESULTADO"
[ "$RESULTADO" = "ok" ] || { echo "❌ Erro: banco não recuperado"; exit 1; }

echo ""
echo "✅ Tarefa 20/23 PASSOU: migração atômica + recuperação (3 cenários)"
exit 0
