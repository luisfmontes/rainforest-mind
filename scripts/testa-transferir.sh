#!/bin/bash
# Bateria para transferir.cjs — despacho de /transferir por destino
# Uso: bash scripts/testa-transferir.sh
#
# Testa o despacho de transferir.cjs: 'claude' é recusado (aponta o /conta),
# o resto segue para transferir-para-codex.cjs.
# Contra dublê que grava argv e sai com código conhecido.

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_M="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

# Usar diretório temporário (fora do worktree para limpeza correta)
RAIZ_BASE="/tmp/test-transferir-$$"
mkdir -p "$RAIZ_BASE"
RAIZ="$RAIZ_BASE"

# UM trap de EXIT para a bateria inteira
A_LIMPAR="$RAIZ_BASE"
limpa() {
  cd "$SRC" 2>/dev/null || cd /
  sleep 0.1
  local d
  for d in $A_LIMPAR; do
    rm -rf "$d" 2>/dev/null || true
  done
}
trap limpa EXIT

echo "(caixa de areia: $RAIZ)"
echo ""

ok=0
falhou=0

# ===== SETUP =====

mkdir -p "$RAIZ/plugin/scripts"
mkdir -p "$RAIZ/plugin/hooks/lib"
PLUGIN="$RAIZ/plugin"

# Copia o script despachante
cp "$SRC/scripts/transferir.cjs" "$PLUGIN/scripts/transferir.cjs"

# Copia lib de contas
cp "$SRC/hooks/lib/contas-claude.cjs" "$PLUGIN/hooks/lib/contas-claude.cjs"

# Dublê transferir-para-codex.cjs: exit code 9, grava argv em arquivo
mkdir -p "$RAIZ/logs"
DUBLE_CODEX="$RAIZ/duble-codex.cjs"
cat > "$DUBLE_CODEX" << 'DUBLEEOF'
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const argv = process.argv.slice(2);
const logFile = process.env.DUBLE_CODEX_LOG || '/tmp/duble-codex.log';

// Grava argv como JSON
fs.writeFileSync(logFile, JSON.stringify(argv), 'utf8');

process.exit(9);
DUBLEEOF
chmod +x "$DUBLE_CODEX"

# ===== CASOS =====

echo "== CASO 1: transferir claude recusa e aponta o /conta ==="

LOG_CODEX_1="$RAIZ/codex-1.log"
rm -f "$LOG_CODEX_1"

saida_1=$(RFM_TEST=1 \
  RFM_TRANSFERIR_CODEX="$DUBLE_CODEX" \
  DUBLE_CODEX_LOG="$LOG_CODEX_1" \
  node "$PLUGIN/scripts/transferir.cjs" claude 2>&1)
exit_1=$?

if [ "$exit_1" = "2" ] && echo "$saida_1" | grep -qF '/conta' && [ ! -f "$LOG_CODEX_1" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 1: transferir claude recusa com exit 2 e aponta o /conta (dublê codex não chamado)"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 1: esperava exit 2 com /conta e sem dublê codex, veio exit $exit_1"
  echo "    saída: $saida_1"
  [ -f "$LOG_CODEX_1" ] && echo "    (dublê codex foi chamado por engano)"
fi

echo ""
echo "== CASO 2: claude --para trabalho também recusa com o /conta ==="

LOG_CODEX_2="$RAIZ/codex-2.log"
rm -f "$LOG_CODEX_2"

saida_2=$(RFM_TEST=1 \
  RFM_TRANSFERIR_CODEX="$DUBLE_CODEX" \
  DUBLE_CODEX_LOG="$LOG_CODEX_2" \
  node "$PLUGIN/scripts/transferir.cjs" claude --para trabalho 2>&1)
exit_2=$?

if [ "$exit_2" = "2" ] && echo "$saida_2" | grep -qF '/conta' && [ ! -f "$LOG_CODEX_2" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 2: claude --para trabalho recusa com exit 2 e aponta o /conta"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 2: esperava exit 2 com /conta, veio exit $exit_2"
  echo "    saída: $saida_2"
  [ -f "$LOG_CODEX_2" ] && echo "    (dublê codex foi chamado por engano)"
fi

echo ""
echo "== CASO 3: sem argumento despacha para transferir-para-codex ==="

LOG_CODEX_3="$RAIZ/codex-3.log"
rm -f "$LOG_CODEX_3"

saida_3=$(RFM_TEST=1 \
  RFM_TRANSFERIR_CODEX="$DUBLE_CODEX" \
  DUBLE_CODEX_LOG="$LOG_CODEX_3" \
  node "$PLUGIN/scripts/transferir.cjs" 2>&1)
exit_3=$?

if [ "$exit_3" = "9" ] && [ -f "$LOG_CODEX_3" ]; then
  argv_3=$(cat "$LOG_CODEX_3")
  if [ "$argv_3" = "[]" ]; then
    ok=$((ok + 1))
    echo "  ok   caso 3: sem argumento despacha para transferir-para-codex (exit 9, argv vazio)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA caso 3: transferir-para-codex recebeu argv não vazio: $argv_3"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 3: esperava exit 9 com dublê codex, veio exit $exit_3"
  [ ! -f "$LOG_CODEX_3" ] && echo "    (dublê codex não foi chamado)"
fi

echo ""
echo "== CASO 4: --ultimas 3 despacha para transferir-para-codex com argumento ==="

LOG_CODEX_4="$RAIZ/codex-4.log"
rm -f "$LOG_CODEX_4"

saida_4=$(RFM_TEST=1 \
  RFM_TRANSFERIR_CODEX="$DUBLE_CODEX" \
  DUBLE_CODEX_LOG="$LOG_CODEX_4" \
  node "$PLUGIN/scripts/transferir.cjs" --ultimas 3 2>&1)
exit_4=$?

if [ "$exit_4" = "9" ] && [ -f "$LOG_CODEX_4" ]; then
  argv_4=$(cat "$LOG_CODEX_4")
  if echo "$argv_4" | grep -q '"--ultimas"' && echo "$argv_4" | grep -q '"3"'; then
    ok=$((ok + 1))
    echo "  ok   caso 4: --ultimas 3 passa argumentos para transferir-para-codex"
  else
    falhou=$((falhou + 1))
    echo "  FALHA caso 4: argv não contém --ultimas 3: $argv_4"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 4: esperava exit 9 com dublê codex, veio exit $exit_4"
fi

echo ""
echo "== CASO 5: commands/transferir.md chama scripts/transferir.cjs com \$ARGUMENTS ==="

# Lê commands/transferir.md e procura pela linha de comando
if grep -q 'node.*scripts/transferir\.cjs.*\$ARGUMENTS' "$SRC/commands/transferir.md"; then
  # Verifica que não chama mais o script do Codex direto
  if ! grep -q 'transferir-para-codex\.cjs' "$SRC/commands/transferir.md"; then
    ok=$((ok + 1))
    echo "  ok   caso 5: commands/transferir.md chama scripts/transferir.cjs (não mais transferir-para-codex.cjs direto)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA caso 5: commands/transferir.md ainda chama transferir-para-codex.cjs"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 5: commands/transferir.md não chama scripts/transferir.cjs com \$ARGUMENTS"
fi

# ===== SUMÁRIO =====

echo ""
echo "========================================"
echo "Resultados: $ok passaram, $falhou falharam"
echo "========================================"

if [ "$falhou" -gt 0 ]; then
  exit 1
fi

exit 0
