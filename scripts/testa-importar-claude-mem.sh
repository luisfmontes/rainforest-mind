#!/bin/bash
# Bateria do scripts/importar-claude-mem.cjs — importador de observações.
# Uso: bash scripts/testa-importar-claude-mem.sh
#
# O que esta bateria prova, nesta ordem:
#   1. importa N observacoes num banco vazio
#   2. reimportar sem novidade insere 0 (idempotencia)
#   3. origem ausente devolve exit 0 com mensagem, nunca erro
#
# Caixa de areia hermetica: banco de origem syntético, RFM_ROOT isolado,
# nunca toca ~/.rainforest ou ~/.claude-mem reais. Usa TESTADOR_ORIGEM_CLAUDE_MEM
# para apontar para origem customizada nos testes.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

# Caminhos dentro da caixa — totalmente isolados
ORIGEM="$CAIXA/origem-sintética.db"
export ORIGEM
export RFM_ROOT="$CAIXA/rainforest-root"
export TESTADOR_ORIGEM_CLAUDE_MEM="$ORIGEM"
mkdir -p "$RFM_ROOT"

# Inicializar origem sintetica com 3 observacoes
node <<'SETUP_ORIGEM'
const fs = require('fs');
const { DatabaseSync } = require('node:sqlite');

const db = new DatabaseSync(process.env.ORIGEM);

// Schema idêntico ao claude-mem
db.exec(`
  CREATE TABLE observations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_session_id TEXT,
    project TEXT,
    text TEXT NOT NULL,
    type TEXT,
    title TEXT,
    subtitle TEXT,
    facts TEXT,
    narrative TEXT,
    concepts TEXT,
    files_read TEXT,
    files_modified TEXT,
    prompt_number INTEGER,
    created_at TEXT NOT NULL,
    created_at_epoch INTEGER,
    content_hash TEXT,
    agent_type TEXT
  );
`);

// 3 observações de teste com conteúdo único
db.prepare(`
  INSERT INTO observations (text, created_at, content_hash, created_at_epoch)
  VALUES (?, ?, ?, ?)
`).run(
  'observacao teste 1 - conteudo unico xyz',
  '2026-08-01T10:00:00Z',
  'hash-unico-1',
  Math.floor(new Date('2026-08-01').getTime() / 1000)
);

db.prepare(`
  INSERT INTO observations (text, created_at, content_hash, created_at_epoch)
  VALUES (?, ?, ?, ?)
`).run(
  'observacao teste 2 - conteudo unico abc',
  '2026-08-02T10:00:00Z',
  'hash-unico-2',
  Math.floor(new Date('2026-08-02').getTime() / 1000)
);

db.prepare(`
  INSERT INTO observations (text, created_at, content_hash, created_at_epoch)
  VALUES (?, ?, ?, ?)
`).run(
  'observacao teste 3 - conteudo unico 123',
  '2026-08-03T10:00:00Z',
  'hash-unico-3',
  Math.floor(new Date('2026-08-03').getTime() / 1000)
);

db.close();
console.log('origem sintética criada com 3 observações');
SETUP_ORIGEM

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -6; fi
}

contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"; fi
}

echo "== 1. inicializar banco de destino com schema =="
esperado "memoria.cjs iniciar" 0 node "$SRC/scripts/memoria.cjs" iniciar
if [ -f "$RFM_ROOT/rainforest.db" ]; then
  ok=$((ok+1)); echo "  ok   banco em $RFM_ROOT/rainforest.db"
else
  falhou=$((falhou+1)); echo "  FALHA banco não criado"
fi

echo
echo "== 2. importar 3 observações num banco vazio =="
saida_imp=$(node "$SRC/scripts/importar-claude-mem.cjs" 2>&1); got=$?
if [ "$got" = "0" ]; then ok=$((ok+1)); echo "  ok   primeira importação (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA primeira importação: exit $got"; fi

if echo "$saida_imp" | grep -q "importadas: 3"; then ok=$((ok+1)); echo "  ok   relata importadas: 3"
else falhou=$((falhou+1)); echo "  FALHA relata importadas: 3"; fi

echo
echo "== 3. reimportar sem novidade insere 0 =="
saida_imp2=$(node "$SRC/scripts/importar-claude-mem.cjs" 2>&1); got2=$?
if [ "$got2" = "0" ]; then ok=$((ok+1)); echo "  ok   segunda importação (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA segunda importação: exit $got2"; fi

if echo "$saida_imp2" | grep -q "importadas: 0"; then ok=$((ok+1)); echo "  ok   relata importadas: 0"
else falhou=$((falhou+1)); echo "  FALHA relata importadas: 0"; fi

echo
echo "== 4. origem ausente devolve exit 0 com mensagem =="
# Definir origem para um caminho que NÃO existe
export TESTADOR_ORIGEM_CLAUDE_MEM="/tmp/origem-que-nao-existe-12345.db"
saida_sem=$(node "$SRC/scripts/importar-claude-mem.cjs" 2>&1); got3=$?
if [ "$got3" = "0" ]; then ok=$((ok+1)); echo "  ok   sem origem (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA sem origem: exit $got3"; fi

if echo "$saida_sem" | grep -q "nenhuma origem encontrada"; then ok=$((ok+1)); echo "  ok   relata origem ausente"
else falhou=$((falhou+1)); echo "  FALHA relata origem ausente"; echo "$saida_sem" | head -3 | sed 's/^/         /'; fi

echo
echo "== 5. duas observações com texto idêntico, origem diferente =="
# Este é o achado 5 da revisão: origem é o verdadeiro discriminador
# (não conteúdo). Duas observações do mesmo texto de fontes diferentes
# devem AMBAS ser importadas, não descartar uma por "duplicada".

ORIGEM2="$CAIXA/origem-segunda.db"
export ORIGEM2

# Criar segunda origem com uma observação de texto idêntico à primeira origem
node <<SETUP_ORIGEM2
const { DatabaseSync } = require('node:sqlite');

const db = new DatabaseSync(process.env.ORIGEM2);

db.exec(\`
  CREATE TABLE observations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_session_id TEXT,
    project TEXT,
    text TEXT NOT NULL,
    type TEXT,
    title TEXT,
    subtitle TEXT,
    facts TEXT,
    narrative TEXT,
    concepts TEXT,
    files_read TEXT,
    files_modified TEXT,
    prompt_number INTEGER,
    created_at TEXT NOT NULL,
    created_at_epoch INTEGER,
    content_hash TEXT,
    agent_type TEXT
  );
\`);

// Observação com MESMO TEXTO que a primeira da origem anterior, mas origem diferente
db.prepare(\`
  INSERT INTO observations (text, created_at, content_hash, created_at_epoch)
  VALUES (?, ?, ?, ?)
\`).run(
  'observacao teste 1 - conteudo unico xyz',
  '2026-08-04T10:00:00Z',
  'hash-diferente-99',
  Math.floor(new Date('2026-08-04').getTime() / 1000)
);

db.close();
SETUP_ORIGEM2

# Importar da segunda origem
export TESTADOR_ORIGEM_CLAUDE_MEM="$ORIGEM2"
saida_imp3=$(node "$SRC/scripts/importar-claude-mem.cjs" 2>&1); got3=$?
if [ "$got3" = "0" ]; then ok=$((ok+1)); echo "  ok   importação de segunda origem (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA importação de segunda origem: exit $got3"; fi

if echo "$saida_imp3" | grep -q "importadas: 1"; then ok=$((ok+1)); echo "  ok   segunda origem importou 1 observação (não descartada por texto idêntico)"
else falhou=$((falhou+1)); echo "  FALHA segunda origem deveria importar 1, não descartá-la"; echo "$saida_imp3" | sed 's/^/         /'; fi

# Verificar que agora temos 4 observações no total (3 da primeira + 1 da segunda)
CONTA=$(node <<'CONTA_FINAL'
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco(process.env.RFM_ROOT + '/rainforest.db');
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes');
const rows = stmt.all();
console.log(rows[0].cnt);
db.close();
CONTA_FINAL
)

if [ "$CONTA" = "4" ]; then ok=$((ok+1)); echo "  ok   total de 4 observações (3 + 1), não descartada"
else falhou=$((falhou+1)); echo "  FALHA total deveria ser 4, mas é $CONTA"; fi

echo
echo "== 6. Tarefa 2 — projeto é lido e normalizado da origem =="
# Criar terceira origem com 3 observações de projetos distintos (um deles com caminho pai/filho)
ORIGEM3="$CAIXA/origem-terceira.db"
export ORIGEM3

node <<SETUP_ORIGEM3
const { DatabaseSync } = require('node:sqlite');

const db = new DatabaseSync(process.env.ORIGEM3);

db.exec(\`
  CREATE TABLE observations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_session_id TEXT,
    project TEXT,
    text TEXT NOT NULL,
    type TEXT,
    title TEXT,
    subtitle TEXT,
    facts TEXT,
    narrative TEXT,
    concepts TEXT,
    files_read TEXT,
    files_modified TEXT,
    prompt_number INTEGER,
    created_at TEXT NOT NULL,
    created_at_epoch INTEGER,
    content_hash TEXT,
    agent_type TEXT
  );
\`);

// 3 observações com projetos diferentes
db.prepare(\`
  INSERT INTO observations (text, project, created_at, content_hash, created_at_epoch)
  VALUES (?, ?, ?, ?, ?)
\`).run(
  'obs do projeto A',
  'projeto-a',
  '2026-08-10T10:00:00Z',
  'hash-proj-a-1',
  Math.floor(new Date('2026-08-10').getTime() / 1000)
);

db.prepare(\`
  INSERT INTO observations (text, project, created_at, content_hash, created_at_epoch)
  VALUES (?, ?, ?, ?, ?)
\`).run(
  'obs do projeto B',
  'projeto-b',
  '2026-08-11T10:00:00Z',
  'hash-proj-b-1',
  Math.floor(new Date('2026-08-11').getTime() / 1000)
);

// Projeto com caminho (deve ser normalizado para o último segmento)
db.prepare(\`
  INSERT INTO observations (text, project, created_at, content_hash, created_at_epoch)
  VALUES (?, ?, ?, ?, ?)
\`).run(
  'obs do projeto pai/filho',
  'inovacao/gestao-projetos-template',
  '2026-08-12T10:00:00Z',
  'hash-proj-c-1',
  Math.floor(new Date('2026-08-12').getTime() / 1000)
);

db.close();
SETUP_ORIGEM3

# Limpar banco destino e reimportar
rm -f "$RFM_ROOT/rainforest.db"
export RFM_ROOT="$CAIXA/rainforest-root-3"
mkdir -p "$RFM_ROOT"

# Inicializar novo banco
node "$SRC/scripts/memoria.cjs" iniciar >/dev/null 2>&1

# Importar da terceira origem
export TESTADOR_ORIGEM_CLAUDE_MEM="$ORIGEM3"
node "$SRC/scripts/importar-claude-mem.cjs" >/dev/null 2>&1
got=$?

if [ "$got" = "0" ]; then ok=$((ok+1)); echo "  ok   importação de origem com 3 projetos (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA importação de origem com 3 projetos: exit $got"; fi

# Verificar que os 3 projetos foram importados com seus nomes distintos
RESULTADO=$(node <<'QUERY_PROJETOS'
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco(process.env.RFM_ROOT + '/rainforest.db');
const stmt = db.prepare('SELECT DISTINCT projeto FROM observacoes ORDER BY 1');
const rows = stmt.all();
db.close();
process.stdout.write(JSON.stringify(rows));
QUERY_PROJETOS
)

NUM_PROJETOS=$(echo "$RESULTADO" | node -e "const d = JSON.parse(require('fs').readFileSync(0, 'utf-8')); process.stdout.write(String(d.length))")

if [ "$NUM_PROJETOS" = "3" ]; then ok=$((ok+1)); echo "  ok   3 projetos distintos importados"
else falhou=$((falhou+1)); echo "  FALHA esperava 3 projetos, mas encontrou $NUM_PROJETOS"; echo "$RESULTADO" | sed 's/^/         /'; fi

# Verificar que o projeto com caminho foi normalizado para o último segmento
PROJETOS_JSON="$RESULTADO"
if echo "$PROJETOS_JSON" | grep -q 'gestao-projetos-template' && ! echo "$PROJETOS_JSON" | grep -q 'inovacao'; then
  ok=$((ok+1)); echo "  ok   projeto pai/filho normalizado para 'gestao-projetos-template'"
else
  falhou=$((falhou+1)); echo "  FALHA projeto não foi normalizado corretamente"
  echo "         Projetos encontrados:" | sed 's/^/         /'
  echo "$PROJETOS_JSON" | sed 's/^/         /'
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
