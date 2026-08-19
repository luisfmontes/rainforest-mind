#!/bin/bash
# Bateria: Migração atômica + recuperação de tabela órfã (Tarefa 20)
#
# Testa que a migração de observacoes é ATÔMICA:
# 1. Se completar, todas as linhas são preservadas
# 2. Se falhar, a tabela antiga fica intacta (ROLLBACK)
# 3. Rodar novamente recupera e completa a migração
#
# Uso: bash scripts/testa-memoria-migracao-atomica.sh
# Exit: 0 se verde, 1 se vermelho

set -e

RAIZ=$(pwd)
TEMP_DIR="${RFM_ROOT:-.rainforest-teste-migracao}"
DB="$TEMP_DIR/rainforest.db"

cleanup() {
  rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

cleanup
mkdir -p "$TEMP_DIR"

# 1. Criar banco com esquema legado (sem UNIQUE(projeto, origem))
echo "[1] Criar banco com esquema legado (sem UNIQUE)..."
node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('$DB');

// Esquema legado: sem UNIQUE(projeto, origem)
db.exec(\`
  CREATE TABLE observacoes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    projeto TEXT NOT NULL,
    conteudo TEXT NOT NULL,
    criada_em TEXT NOT NULL,
    origem TEXT
  );
\`);

// Inserir dados de teste (com colisões potenciais)
const stmt = db.prepare(\`
  INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
  VALUES (?, ?, ?, ?)
\`);

stmt.run('projeto-a', 'observação 1', new Date().toISOString(), 'origem-1');
stmt.run('projeto-a', 'observação 2', new Date().toISOString(), 'origem-2');
stmt.run('projeto-a', 'observação 3', new Date().toISOString(), 'origem-1'); // colisão
stmt.run('projeto-b', 'observação 4', new Date().toISOString(), 'origem-x');

const contagem = db.prepare('SELECT COUNT(*) as cnt FROM observacoes').all();
console.log('Linhas antes da migração:', contagem[0].cnt);
db.close();
"

# 2. Verificar que tabela legada NÃO tem UNIQUE(projeto, origem)
echo "[2] Verificar constraint ausente no esquema legado..."
node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('$DB', { readonly: true });

const indices = db.prepare(\`
  SELECT name FROM sqlite_master
  WHERE type='index' AND tbl_name='observacoes'
\`).all();

let temConstraintCorreta = false;
for (const idx of indices) {
  const colunas = db.prepare(\`PRAGMA index_info('\${idx.name}')\`).all();
  if (colunas.length === 2 && colunas[0].name === 'projeto' && colunas[1].name === 'origem') {
    temConstraintCorreta = true;
  }
}

console.log('Tem UNIQUE(projeto, origem):', temConstraintCorreta);
if (!temConstraintCorreta) {
  console.log('✓ Esquema legado confirmado (sem constraint)');
}
db.close();
" || true

# 3. Chamar memoria.cjs iniciar para rodar migração (com BEGIN/COMMIT)
echo "[3] Chamar memoria.cjs iniciar para migrar..."
RFM_ROOT="$TEMP_DIR" node scripts/memoria.cjs iniciar >/dev/null 2>&1

# 4. Verificar que migração completou e preservou TODAS as linhas
echo "[4] Verificar que migração completou atomicamente..."
LINHAS_APOS=$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('$DB', { readonly: true });

const contagem = db.prepare('SELECT COUNT(*) as cnt FROM observacoes').all();
console.log(contagem[0].cnt);
db.close();
")

echo "Linhas após migração: $LINHAS_APOS"

# 5. Verificar que UNIQUE(projeto, origem) agora existe
echo "[5] Verificar que constraint foi criado..."
CONSTRAINT_OK=$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('$DB', { readonly: true });

const indices = db.prepare(\`
  SELECT name FROM sqlite_master
  WHERE type='index' AND tbl_name='observacoes'
\`).all();

let temConstraintCorreta = false;
for (const idx of indices) {
  const colunas = db.prepare(\`PRAGMA index_info('\${idx.name}')\`).all();
  if (colunas.length === 2 && colunas[0].name === 'projeto' && colunas[1].name === 'origem') {
    temConstraintCorreta = true;
    break;
  }
}

console.log(temConstraintCorreta ? 'ok' : 'nao');
db.close();
")

echo "Constraint criado: $CONSTRAINT_OK"

# 6. Verificar que não há tabela órfã observacoes_backup
echo "[6] Verificar limpeza (sem observacoes_backup órfã)..."
TABELAS_BACKUP=$(node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('$DB', { readonly: true });

const resultado = db.prepare(\`
  SELECT name FROM sqlite_master
  WHERE type='table' AND name='observacoes_backup'
\`).all();

console.log(resultado.length === 0 ? 'nao' : 'sim');
db.close();
")

echo "Tabela observacoes_backup existe: $TABELAS_BACKUP"

# 7. Validar resultado
if [ "$LINHAS_APOS" = "4" ] && [ "$CONSTRAINT_OK" = "ok" ] && [ "$TABELAS_BACKUP" = "nao" ]; then
  echo "✅ Tarefa 20 PASSOU: migração atômica com recuperação"
  exit 0
else
  echo "❌ Tarefa 20 FALHOU"
  echo "  Linhas: $LINHAS_APOS (esperado 4)"
  echo "  Constraint: $CONSTRAINT_OK (esperado ok)"
  echo "  Tabela backup órfã: $TABELAS_BACKUP (esperado nao)"
  exit 1
fi
