#!/bin/bash
# Bateria minimalista para hooks/gate-fechar-issue.cjs — casos (a), (b), (e)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# Criar stub minimalista
mkdir -p "$SBP/bin"
cat > "$SBP/bin/gh.cmd" <<'STUB'
@echo off
exit /b 0
STUB

echo "== TRAVA =="
[ -f "$SBP/bin/gh.cmd" ] && echo "  ok   gh.cmd existe" || { echo "  FALHA gh.cmd"; exit 1; }

# Caso (a): `gh issue close <n>` → exit 2
echo ""
echo "== (a) gh issue close <n> → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) >/dev/null 2>&1
[ $? -eq 2 ] && test_ok "exit 2" || test_fail "exit code"

# Caso (b): `gh pr create --body "closes #12"` → exit 2 (sem checar marcador, só bloqueia padrão)
echo ""
echo "== (b) gh pr create → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"closes #12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) >/dev/null 2>&1
[ $? -eq 2 ] && test_ok "exit 2" || test_fail "exit code"

# Caso (e): `RAINFOREST_GATE_OFF=1` → exit 0
echo ""
echo "== (e) RAINFOREST_GATE_OFF=1 → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export RAINFOREST_GATE_OFF=1
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh issue close 999"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"

echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="
exit $falhou
