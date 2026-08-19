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
echo "[LADO D: crash de verdade no meio da transação (Tarefa 23 - item 4a)]"
# Os lados A a C provam a migração inteira e a recuperação de estados já
# quebrados. Nenhum deles mata processo, e o critério da tarefa 23 pede a morte
# no meio: o banco tem de ficar no estado anterior, com as N linhas originais.
# O abort é injetado numa CÓPIA do memoria.cjs — o arquivo rastreado não é tocado.
#
# O QUE ESTE TESTE NÃO PROVA, medido em 2026-08-19: ele não discrimina a
# presença do BEGIN/COMMIT. Rodei uma cópia com a transação removida, com o
# abort logo depois do RENAME e também logo antes do DROP, e nos dois pontos o
# banco voltou ao estado anterior igual (`observacoes` com 3 linhas, sem tabela
# órfã) — o `node:sqlite` já descarta o que não foi consolidado quando o
# processo morre. Ou seja: este lado cobre o critério ("sobreviveu ao crash"),
# não a atomicidade explícita. Quem quiser proteger o BEGIN/COMMIT de uma
# remoção acidental precisa de outro teste, e ele ainda não existe.

MUT_DIR="$(mktemp -d)"
DADOS_CRASH="$(mktemp -d)"
# A cópia leva `hooks/` junto: `memoria.cjs` faz require de `../hooks/lib/raiz.cjs`,
# e sem isso o processo mutado morre no carregamento do módulo, ANTES da migração
# — o banco fica intacto por não ter sido tocado, e o teste passa medindo nada.
cp -r "$RAIZ/scripts" "$MUT_DIR/scripts"
cp -r "$RAIZ/hooks" "$MUT_DIR/hooks"

node -e '
const fs = require("fs");
const alvo = process.argv[1];
const src = fs.readFileSync(alvo, "utf8");
const marca = "conexao.exec(`ALTER TABLE observacoes RENAME TO observacoes_backup;`);";
if (!src.includes(marca)) { console.error("alvo-ausente"); process.exit(3); }
// A marca no stderr é o que distingue "morreu no ponto certo" de "morreu antes":
// sem ela, qualquer falha precoce (módulo faltando, permissão) viraria falso verde.
fs.writeFileSync(alvo, src.replace(marca, marca + "\n    console.error(\"CHEGOU-AO-RENAME\");\n    process.abort(); /* MUTACAO CRASH */"));
' "$MUT_DIR/scripts/memoria.cjs" || { echo "  FALHA D. a injeção do crash não casou com o fonte — este teste virou decorativo"; rm -rf "$MUT_DIR" "$DADOS_CRASH"; exit 1; }

RFM_ROOT="$DADOS_CRASH" node << 'CREATE_PRE_CRASH'
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
`);
const stmt = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
stmt.run('p', 'linha 1', '2026-08-19', 'sessao:a');
stmt.run('p', 'linha 2', '2026-08-19', 'sessao:b');
stmt.run('p', 'linha 3', '2026-08-19', 'sessao:c');
db.close();
CREATE_PRE_CRASH

# `set -e` está ligado nesta bateria, e aqui a morte do processo é o resultado
# esperado: sem o `|| CRASH_EXIT=$?` o script inteiro morreria junto, antes de
# chegar na única pergunta que importa (o banco sobreviveu?).
CRASH_EXIT=0
CRASH_SAIDA="$(RFM_ROOT="$DADOS_CRASH" node "$MUT_DIR/scripts/memoria.cjs" iniciar 2>&1)" || CRASH_EXIT=$?

if [ "$CRASH_EXIT" -eq 0 ]; then
  echo "  FALHA D. o processo mutado saiu 0 — o abort não chegou a rodar, e o teste não mediu crash nenhum"
  rm -rf "$MUT_DIR" "$DADOS_CRASH"
  exit 1
fi
case "$CRASH_SAIDA" in
  *CHEGOU-AO-RENAME*)
    echo "  ok   processo morreu DENTRO da migração, depois do RENAME (exit $CRASH_EXIT)" ;;
  *)
    echo "  FALHA D. o processo morreu ANTES de chegar na migração — o banco intacto não prova rollback nenhum"
    echo "        saida: $(echo "$CRASH_SAIDA" | head -3)"
    rm -rf "$MUT_DIR" "$DADOS_CRASH"
    exit 1 ;;
esac

DEPOIS=$(RFM_ROOT="$DADOS_CRASH" node << 'CHECK_POS_CRASH' 2>/dev/null
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const t = db.prepare(`SELECT name FROM sqlite_master WHERE type='table'`).all().map(r => r.name);
const temObs = t.includes('observacoes');
const cnt = temObs ? db.prepare('SELECT COUNT(*) as c FROM observacoes').all()[0].c : -1;
console.log((temObs && !t.includes('observacoes_backup') && cnt === 3)
  ? 'ok'
  : 'falha:' + JSON.stringify({ tabelas: t, linhas: cnt }));
db.close();
CHECK_POS_CRASH
)

rm -rf "$MUT_DIR" "$DADOS_CRASH"

if [ "$DEPOIS" = "ok" ]; then
  echo "  ok   D. as 3 linhas continuam em observacoes, sem tabela órfã: o rollback cobriu o crash"
else
  echo "  FALHA D. banco não voltou ao estado anterior ao crash — $DEPOIS"
  exit 1
fi

echo ""
echo "✅ Tarefa 20/23 PASSOU: migração atômica + recuperação (4 cenários)"
exit 0
