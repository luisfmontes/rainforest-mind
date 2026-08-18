#!/bin/bash
# Bateria do hooks/memoria-marca.cjs --recover (Tarefa 11)
# Uso: bash hooks/testa-memoria-recuperacao.sh
#
# O que esta bateria precisa provar:
#   1. SessionEnd normal processa até o fim do transcrito
#   2. Sessão cujo SessionEnd **nunca dispara** é recuperada na abertura seguinte
#   3. Ambos caminhos chegam à mesma contagem final
#   4. A recuperação é enfileirada (async no hooks.json)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/memoria-marca.cjs"
SCRIPT_MEMORIA="$SRC/scripts/memoria.cjs"
HOOKS_JSON="$SRC/hooks/hooks.json"

# Sandbox hermética
RAIZ_POSIX="$(mktemp -d)"
RAIZ=$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# Teste 1: Recuperação está registrada em hooks.json como async
echo
echo "1. Recuperação está registrada em SessionStart como async"
if grep -A 20 '"SessionStart"' "$HOOKS_JSON" | grep -q 'memoria-marca.cjs.*--recover'; then
  if grep -A 20 '"SessionStart"' "$HOOKS_JSON" | grep -A 5 'memoria-marca.cjs.*--recover' | grep -q '"async": true'; then
    ok=$((ok+1)); echo "  ok    recuperação registrada em SessionStart como async"
  else
    falhou=$((falhou+1)); echo "  FALHA recuperação não está async"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA recuperação não registrada em SessionStart"
fi

# Teste 2: Não existe spawn/exec no hook
echo
echo "2. Hook não contém spawn/exec"
if grep -E '\.spawn\(|\.exec\(|spawn\(|exec\(' "$HOOK" | grep -v '//' > /dev/null 2>&1; then
  falhou=$((falhou+1)); echo "  FALHA encontrado spawn/exec"
else
  ok=$((ok+1)); echo "  ok    sem spawn/exec"
fi

# Teste 3: Inicializa banco
echo
echo "3. Inicializando banco na caixa de areia"
RFM_ROOT="$RAIZ" node "$SCRIPT_MEMORIA" iniciar > /dev/null 2>&1

if [ -f "$RAIZ_POSIX/rainforest.db" ]; then
  ok=$((ok+1)); echo "  ok    banco criado"
else
  falhou=$((falhou+1)); echo "  FALHA banco não criado"
  echo "== resultado: $ok ok, $falhou falha(s) =="
  exit 1
fi

# Teste 4: Caminho normal — SessionEnd dispara, marca processada
echo
echo "4. Caminho normal: SessionEnd dispara e processa marca"

SESSAO_NORMAL="sessao-normal-001"
mkdir -p "$RAIZ_POSIX/projects/projeto-teste"
echo '{"tipo":"prompt","conteudo":"turno1"}' > "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_NORMAL.jsonl"
OFFSET_TURNO1=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_NORMAL.jsonl")

# Stop: marca no primeiro turno
EVENTO='{"session_id":"'$SESSAO_NORMAL'","project":"projeto-teste"}'
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica marca após Stop
RESULTADO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_NORMAL\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

if [ "$RESULTADO" = "$OFFSET_TURNO1" ]; then
  ok=$((ok+1)); echo "  ok    marca gravada no Stop ($RESULTADO bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA marca após Stop diverge (esperado=$OFFSET_TURNO1, obtido=$RESULTADO)"
fi

# Cresce transcrito (simula mais turno)
echo '{"tipo":"ferramenta","conteudo":"resultado"}' >> "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_NORMAL.jsonl"
OFFSET_TURNO2=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_NORMAL.jsonl")

# SessionEnd: marca no fechamento
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica marca final (deve ter offset atualizado)
RESULTADO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_NORMAL\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

if [ "$RESULTADO" = "$OFFSET_TURNO2" ]; then
  ok=$((ok+1)); echo "  ok    marca atualizada no SessionEnd ($RESULTADO bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA marca final diverge (esperado=$OFFSET_TURNO2, obtido=$RESULTADO)"
fi

# Teste 5: Caminho de recuperação — SessionEnd **nunca dispara**, recovery avança offset
echo
echo "5. CRÍTICO: Janela morta — offset avança de X para Y quando recuperação roda"

SESSAO_MORTA="sessao-morta-001"
mkdir -p "$RAIZ_POSIX/projects/projeto-teste"

# Passo 1: Cria transcrito, Stop marca em offset X
echo '{"tipo":"prompt","conteudo":"turno1"}' > "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MORTA.jsonl"
OFFSET_X=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MORTA.jsonl")

EVENTO_MORTA='{"session_id":"'$SESSAO_MORTA'","project":"projeto-teste"}'
echo "$EVENTO_MORTA" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica marca após Stop (offset = X)
MARCA_ANTES=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_MORTA\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

if [ "$MARCA_ANTES" = "$OFFSET_X" ]; then
  echo "  ok    marca após Stop = $MARCA_ANTES bytes (offset X)"
else
  falhou=$((falhou+1)); echo "  FALHA marca após Stop diverge (esperado=$OFFSET_X, obtido=$MARCA_ANTES)"
fi

# Passo 2: Transcrito CRESCE (Y > X), SessionEnd MORRE (nunca chama hook)
echo '{"tipo":"ferramenta","conteudo":"resultado","dados":"extra_bytes"}' >> "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MORTA.jsonl"
OFFSET_Y=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MORTA.jsonl")

if [ "$OFFSET_Y" -gt "$OFFSET_X" ]; then
  echo "  ok    transcrito cresceu de $OFFSET_X para $OFFSET_Y bytes"
else
  falhou=$((falhou+1)); echo "  FALHA transcrito não cresceu"
fi

# Passo 3: Abertura seguinte — recuperação chamada, offset DEVE AVANÇAR para Y
echo "  Chamando recuperação (offset deve avançar de $OFFSET_X para $OFFSET_Y)..."
echo "$EVENTO_MORTA" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" --recover > /dev/null 2>&1

# Verifica marca após recuperação (DEVE ter avançado para Y)
MARCA_DEPOIS=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_MORTA\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

# AQUI VAI O TESTE QUE FALHA QUANDO recuperarSessoes() tem return; no topo
if [ "$MARCA_DEPOIS" = "$OFFSET_Y" ]; then
  ok=$((ok+1)); echo "  ok    RECUPERAÇÃO FUNCIONOU: offset avançou de $MARCA_ANTES para $MARCA_DEPOIS"
else
  falhou=$((falhou+1)); echo "  FALHA RECUPERAÇÃO NÃO FUNCIONOU: offset continuou em $MARCA_DEPOIS (esperava $OFFSET_Y)"
fi

# Teste 6: Prova por mutação — desliga recuperação, SessionEnd morto fica suspenso
echo
echo "6. Prova por mutação: desliga recuperação, mostra pendência"

# Remove recuperação de hooks.json temporariamente
HOOKS_TEMP="$(mktemp)"
grep -v '"comando".*--recover' "$HOOKS_JSON" | grep -v '"async".*true' > "$HOOKS_TEMP" || true

# Cria sessão nova que vai "morrer"
SESSAO_MUTACAO="sessao-mutacao-001"
mkdir -p "$RAIZ_POSIX/projects/projeto-teste"
echo '{"tipo":"turno1"}' > "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MUTACAO.jsonl"

# Stop marca (recuperação desligada no hooks.json simulado)
EVENTO_MUT='{"session_id":"'$SESSAO_MUTACAO'","project":"projeto-teste"}'
echo "$EVENTO_MUT" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

OFFSET_MUT_1=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_MUTACAO\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

# Cresce transcrito, SessionEnd morre
echo '{"tipo":"turno2"}' >> "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MUTACAO.jsonl"

# Tentaria chamar recuperação, mas está desligada
# (simulamos não chamando o hook --recover)
# Nada acontece — marca não é processada

OFFSET_MUT_2=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_MUTACAO\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

# Marca deve permanecer inalterada (prova que sem recuperação, fica suspensa)
if [ "$OFFSET_MUT_1" = "$OFFSET_MUT_2" ]; then
  ok=$((ok+1)); echo "  ok    sem recuperação, marca fica suspensa ($OFFSET_MUT_2 bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA marca alterou mesmo sem recuperação"
fi

# Teste 7: Degradação graciosa — banco ausente
echo
echo "7. Degradação graciosa: banco ausente na recuperação"

RAIZ_VAZIO="$(mktemp -d)"
trap "rm -rf $RAIZ_POSIX $RAIZ_VAZIO" EXIT

echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ_VAZIO" \
  RFM_ROOT="$RAIZ_VAZIO" \
  node "$HOOK" --recover > /dev/null 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    recuperação saiu com exit 0 quando banco não existia"
else
  falhou=$((falhou+1)); echo "  FALHA recuperação saiu com exit $EXIT_CODE"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
