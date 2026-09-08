#!/bin/bash
# Bateria para transferir-para-codex.cjs — transporte de sessão para Codex CLI
# Uso: bash scripts/testa-transferir-para-codex.sh
#
# Testa transferência de transcript contra dublê (nunca contra Codex real).

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_M="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

# Usar diretório temporário (fora do worktree para limpeza correta)
RAIZ_BASE="/tmp/test-transferir-codex-$$"
mkdir -p "$RAIZ_BASE"
RAIZ="$RAIZ_BASE"

# Home temporária para testes (RFM_HOME)
RFMHOME="$RAIZ/home"
mkdir -p "$RFMHOME/.claude/projects/test-proj"
RFMHOME_M="$(cygpath -m "$RFMHOME" 2>/dev/null || printf '%s' "$RFMHOME")"

# UM trap de EXIT para a bateria inteira
A_LIMPAR="$RAIZ_BASE"
limpa() {
  cd "$SRC" 2>/dev/null || cd /
  sleep 1
  local d
  for d in $A_LIMPAR; do
    rm -rf "$d" 2>/dev/null
  done
}
trap limpa EXIT

echo "(caixa de areia: $RAIZ)"
echo "(RFM_HOME: $RFMHOME)"
echo ""

ok=0
falhou=0

testa() {
  local nome="$1"
  local exit_esperado="$2"
  shift 2

  local saida
  saida=$("$@" 2>&1); local exit_obtido=$?

  if [ "$exit_obtido" = "$exit_esperado" ]; then
    ok=$((ok + 1))
    echo "  ok   $nome (exit $exit_obtido)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $nome: esperava exit $exit_esperado, veio $exit_obtido"
    echo "$saida" | sed 's/^/         /' | head -10
  fi
}

# ===== SETUP =====

mkdir -p "$RAIZ/plugin"
PLUGIN="$RAIZ/plugin"

# Copia hooks/lib/ e hooks
mkdir -p "$PLUGIN/hooks/lib"
cp "$SRC/hooks/lib/cli-externo.cjs" "$PLUGIN/hooks/lib/cli-externo.cjs"
cp "$SRC/hooks/lib/config.cjs" "$PLUGIN/hooks/lib/config.cjs"
cp "$SRC/hooks/lib/raiz.cjs" "$PLUGIN/hooks/lib/raiz.cjs" 2>/dev/null || true
cp "$SRC/hooks/codex-transfer-session-start.cjs" "$PLUGIN/hooks/codex-transfer-session-start.cjs"

# Copia scripts
mkdir -p "$PLUGIN/scripts/fixtures"
cp "$SRC/scripts/transferir-para-codex.cjs" "$PLUGIN/scripts/transferir-para-codex.cjs"
cp "$SRC/scripts/fixtures/codex-duble.cjs" "$PLUGIN/scripts/fixtures/codex-duble.cjs"

# Cria diretório de teste de transcript
PROJ_DIR="$RFMHOME/.claude/projects/test-proj"
mkdir -p "$PROJ_DIR"
PROJ_DIR_M="$(cygpath -m "$PROJ_DIR" 2>/dev/null || printf '%s' "$PROJ_DIR")"

# Cria transcript de teste com 3 mensagens reais + 1 lixo
TRANSCRIPT="$PROJ_DIR/test.jsonl"
cat > "$TRANSCRIPT" << 'JSONEOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Primeira pergunta"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Primeira resposta"}]}}
lixo que não é JSON
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Segunda pergunta"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Segunda resposta"}]}}
JSONEOF

TRANSCRIPT_M="$(cygpath -m "$TRANSCRIPT" 2>/dev/null || printf '%s' "$TRANSCRIPT")"

# Dublê
DUBLE="$PLUGIN/scripts/fixtures/codex-duble.cjs"
DUBLE_M="$(cygpath -m "$DUBLE" 2>/dev/null || printf '%s' "$DUBLE")"

# Cria CWD de teste
mkdir -p "$RAIZ/cwd"
CWD="$RAIZ/cwd"
CWD_M="$(cygpath -m "$CWD" 2>/dev/null || printf '%s' "$CWD")"

# ===== CASOS =====

echo "== CASO 1: transcript fora de ~/.claude/projects → exit 2 ==="
BAD_TRANSCRIPT="$RAIZ/bad.jsonl"
cat > "$BAD_TRANSCRIPT" << 'JSONEOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"teste"}]}}
JSONEOF
BAD_TRANSCRIPT_M="$(cygpath -m "$BAD_TRANSCRIPT" 2>/dev/null || printf '%s' "$BAD_TRANSCRIPT")"

saida_1=$(RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  node "$PLUGIN/scripts/transferir-para-codex.cjs" \
  --source "$BAD_TRANSCRIPT_M" 2>&1)
exit_1=$?

if [ "$exit_1" = "2" ] && echo "$saida_1" | grep -qE "\.claude[/\\]projects"; then
  ok=$((ok + 1))
  echo "  ok   caso 1: exit 2 com mensagem citando .claude/projects"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 1: esperava exit 2 com '.claude/projects', veio exit $exit_1"
  echo "$saida_1" | sed 's/^/    /'
fi

echo ""
echo "== CASO 2: transcript válido + mode transfer do dublê → exit 0, stdout termina com 'codex resume' ==="
STDIN_OUT_2="$RAIZ/stdin-2.txt"
STDIN_OUT_2_M="$(cygpath -m "$STDIN_OUT_2" 2>/dev/null || printf '%s' "$STDIN_OUT_2")"

saida_2=$(DUBLE_MODO=transfer \
DUBLE_STDIN_OUT="$STDIN_OUT_2_M" \
RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
CODEX_CMD="node $DUBLE_M" \
node "$PLUGIN/scripts/transferir-para-codex.cjs" \
  --source "$TRANSCRIPT_M" \
  --cwd "$CWD_M" 2>&1)
exit_2=$?

if [ "$exit_2" = "0" ] && echo "$saida_2" | tail -1 | grep -q "^codex resume"; then
  ok=$((ok + 1))
  echo "  ok   caso 2: exit 0, última linha é 'codex resume <id>'"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 2: esperava exit 0 com 'codex resume' na última linha, veio exit $exit_2"
  echo "$saida_2" | tail -3 | sed 's/^/    /'
fi

# Valida stdin do dublê
if [ -f "$STDIN_OUT_2" ]; then
  stdin=$(cat "$STDIN_OUT_2")
  if echo "$stdin" | grep -q "Primeira pergunta" && \
     echo "$stdin" | grep -q "Segunda pergunta" && \
     echo "$stdin" | grep -q "Primeira resposta"; then
    ok=$((ok + 1))
    echo "    ✓ stdin contém os textos do transcript"
  else
    falhou=$((falhou + 1))
    echo "    ✗ stdin não contém os textos esperados"
    echo "$stdin" | head -10 | sed 's/^/      /'
  fi
fi

echo ""
echo "== CASO 3: --ultimas 1 → coleta só última mensagem ==="
STDIN_OUT_3="$RAIZ/stdin-3.txt"
STDIN_OUT_3_M="$(cygpath -m "$STDIN_OUT_3" 2>/dev/null || printf '%s' "$STDIN_OUT_3")"

DUBLE_MODO=transfer \
DUBLE_STDIN_OUT="$STDIN_OUT_3_M" \
RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
CODEX_CMD="node $DUBLE_M" \
node "$PLUGIN/scripts/transferir-para-codex.cjs" \
  --source "$TRANSCRIPT_M" \
  --ultimas 1 \
  --cwd "$CWD_M" > /dev/null 2>&1

if [ -f "$STDIN_OUT_3" ]; then
  stdin=$(cat "$STDIN_OUT_3")
  # Deve conter Segunda resposta (última), não Primeira
  if echo "$stdin" | grep -q "Segunda resposta" && \
     ! echo "$stdin" | grep -q "Primeira pergunta"; then
    ok=$((ok + 1))
    echo "  ok   caso 3: --ultimas 1 coleta só última mensagem"
  else
    falhou=$((falhou + 1))
    echo "  FALHA caso 3: --ultimas 1 não funcionou"
    echo "$stdin" | sed 's/^/    /'
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 3: stdin não foi gravado"
fi

echo ""
echo "== CASO 4: dublê sem thread.started (modo ok) → exit 1 com 'thread.started' ==="
saida_4=$(DUBLE_MODO=ok \
RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
CODEX_CMD="node $DUBLE_M" \
node "$PLUGIN/scripts/transferir-para-codex.cjs" \
  --source "$TRANSCRIPT_M" \
  --cwd "$CWD_M" 2>&1)
exit_4=$?

if [ "$exit_4" = "1" ] && echo "$saida_4" | grep -q "thread.started"; then
  ok=$((ok + 1))
  echo "  ok   caso 4: sem thread.started, exit 1"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 4: esperava exit 1 com 'thread.started', veio exit $exit_4"
  echo "$saida_4" | head -3 | sed 's/^/    /'
fi

echo ""
echo "== CASO 5: --foo bar desconhecida → exit 1, dublê não chamado ==="
CMD_OUT_5="$RAIZ/cmd-5.txt"
CMD_OUT_5_M="$(cygpath -m "$CMD_OUT_5" 2>/dev/null || printf '%s' "$CMD_OUT_5")"
rm -f "$CMD_OUT_5"

saida_5=$(DUBLE_MODO=ok \
DUBLE_CMD_OUT="$CMD_OUT_5_M" \
RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
CODEX_CMD="node $DUBLE_M" \
node "$PLUGIN/scripts/transferir-para-codex.cjs" \
  --source "$TRANSCRIPT_M" \
  --foo bar 2>&1)
exit_5=$?

if [ "$exit_5" = "1" ] && echo "$saida_5" | grep -q "flag desconhecida: --foo" && [ ! -f "$CMD_OUT_5" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 5: flag desconhecida, exit 1, dublê não chamado"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 5: esperava exit 1 com flag e dublê ausente, veio exit $exit_5"
  [ -f "$CMD_OUT_5" ] && echo "    (dublê foi chamado!)"
  echo "$saida_5" | head -3 | sed 's/^/    /'
fi

echo ""
echo "== CASO 6: hook SessionStart com transfer-codex ligado ==="
# Simula o hook com transfer-codex ligado
HOOK_DIR="$RAIZ/hook-test"
mkdir -p "$HOOK_DIR"
HOOK="$PLUGIN/hooks/codex-transfer-session-start.cjs"

ENV_FILE="$HOOK_DIR/env.txt"
ENV_FILE_M="$(cygpath -m "$ENV_FILE" 2>/dev/null || printf '%s' "$ENV_FILE")"

# Config com transfer-codex = true
CONFIG_DIR="$RFMHOME/.rainforest"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.json" << 'CONFIGEOF'
{
  "transfer-codex": true
}
CONFIGEOF

# Payload do hook
PAYLOAD='{"session_id":"s1","transcript_path":"'"$TRANSCRIPT"'"}'

echo "$PAYLOAD" | \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_ENV_FILE="$ENV_FILE_M" \
  node "$HOOK"

if [ -f "$ENV_FILE" ]; then
  if grep -q "RAINFOREST_TRANSCRIPT_PATH=" "$ENV_FILE" && \
     grep -q "RAINFOREST_SESSION_ID=s1" "$ENV_FILE"; then
    ok=$((ok + 1))
    echo "  ok   caso 6a: hook grava variáveis com transfer-codex ligado"
  else
    falhou=$((falhou + 1))
    echo "  FALHA caso 6a: hook não gravou as variáveis"
    cat "$ENV_FILE" | sed 's/^/    /'
  fi
fi

# Caso 6b: com transfer-codex desligado
echo ""
echo "== CASO 6b: hook com transfer-codex desligado ==="

ENV_FILE_OFF="$HOOK_DIR/env-off.txt"
ENV_FILE_OFF_M="$(cygpath -m "$ENV_FILE_OFF" 2>/dev/null || printf '%s' "$ENV_FILE_OFF")"
touch "$ENV_FILE_OFF"

# Config com transfer-codex = false
cat > "$CONFIG_DIR/config.json" << 'CONFIGEOF'
{
  "transfer-codex": false
}
CONFIGEOF

echo "$PAYLOAD" | \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_ENV_FILE="$ENV_FILE_OFF_M" \
  node "$HOOK"

if [ ! -s "$ENV_FILE_OFF" ] || ! grep -q "RAINFOREST" "$ENV_FILE_OFF"; then
  ok=$((ok + 1))
  echo "  ok   caso 6b: hook não escreve com transfer-codex desligado"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 6b: hook escreveu quando deveria ter ficado calado"
  cat "$ENV_FILE_OFF" | sed 's/^/    /'
fi

echo ""
echo "== RESULTADO =="
echo "resultado: $ok ok, $falhou falha(s)"
if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
