#!/bin/bash
# Bateria para hooks/gate-fechar-issue.cjs com trava

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# Criar stub compatível com Windows
mkdir -p "$SBP/bin"

# Criar versão .cmd para Windows
cat > "$SBP/bin/gh.cmd" <<'STUB'
@echo off
setlocal enabledelayedexpansion
if "%1"=="issue" if "%2"=="view" (
  if "!GH_COM_MARCADOR!"=="1" (
    echo [{"body":"<!-- rainforest-evidencia --> Marcador presente"}]
  ) else (
    echo [{"body":"Sem marcador aqui"}]
  )
  exit /b 0
)
exit /b 0
STUB

# Também criar versão shell para bash, caso resolvedor procure sem extensão
cat > "$SBP/bin/gh" <<'STUB'
#!/bin/bash
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  if [ "$GH_COM_MARCADOR" = "1" ]; then
    echo '[{"body":"<!-- rainforest-evidencia --> Marcador presente"}]'
  else
    echo '[{"body":"Sem marcador aqui"}]'
  fi
  exit 0
fi
exit 0
STUB
chmod +x "$SBP/bin/gh"

# TRAVA: verificar que gh existe no sandbox (versão .cmd)
echo "== TRAVA: verificar que gh é do sandbox =="
if [ -f "$SBP/bin/gh.cmd" ]; then
  echo "  ok   gh.cmd está no sandbox"
else
  echo "  FALHA gh.cmd não criado"
  echo "== resultado: 0 ok, 1 falha(s) =="
  exit 1
fi

# Caso (a): `gh issue close 12` → exit 2, stderr aponta scripts/fechar-issue.cjs
echo
echo "== (a) gh issue close <n> direto → exit 2, stderr aponta script =="
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh issue close 12"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-a"
EXIT_A=$?
[ $EXIT_A -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_A)"
ERR_A="$(cat "$SBP/err-a")"
echo "$ERR_A" | grep -q "scripts/fechar-issue.cjs" && test_ok "stderr aponta script" || test_fail "stderr não aponta script"

# Caso (b): `gh pr create --body "closes #12"` sem marcador → exit 2
echo
echo "== (b) gh pr create com closes #12 SEM marcador → exit 2 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"closes #12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-b"
EXIT_B=$?
[ $EXIT_B -eq 2 ] && test_ok "exit 2" || test_fail "exit code (foi $EXIT_B)"

# Caso (c): `gh pr create --body "closes #12"` COM marcador → exit 0
echo
echo "== (c) gh pr create com closes #12 COM marcador → exit 0 =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body \"closes #12\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-c"
EXIT_C=$?
[ $EXIT_C -eq 0 ] && test_ok "exit 0" || test_fail "exit code (foi $EXIT_C)"

# Caso (d): `gh pr create --body-file arquivo` lendo closes #12
echo
echo "== (d) gh pr create --body-file com closes #12 → mesma checagem =="
echo "closes #99" > "$SBP/corpo.txt"
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=""
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body-file '"$SBP"'/corpo.txt"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-d"
EXIT_D=$?
[ $EXIT_D -eq 2 ] && test_ok "exit 2 sem marcador" || test_fail "exit code sem marcador (foi $EXIT_D)"

# Caso (d2): Mesmo arquivo, COM marcador
(
  export PATH="$SBP/bin:$PATH"
  export GH_COM_MARCADOR=1
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh pr create --body-file '"$SBP"'/corpo.txt"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-d2"
EXIT_D2=$?
[ $EXIT_D2 -eq 0 ] && test_ok "exit 0 com marcador" || test_fail "exit code com marcador (foi $EXIT_D2)"

# Caso (e): RAINFOREST_GATE_OFF=1 → libera tudo
echo
echo "== (e) RAINFOREST_GATE_OFF=1 libera gh issue close =="
(
  export PATH="$SBP/bin:$PATH"
  export RAINFOREST_GATE_OFF=1
  PAYLOAD='{"cwd":"'"$SBP"'","tool_name":"Bash","tool_input":{"command":"gh issue close 999"}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-e"
EXIT_E=$?
[ $EXIT_E -eq 0 ] && test_ok "exit 0 (emergência ativa)" || test_fail "exit code (foi $EXIT_E)"

# Caso (f): .rainforest-gate-off na raiz → libera tudo
echo
echo "== (f) .rainforest-gate-off libera gh pr merge =="
mkdir -p "$SBP/repo"
cd "$SBP/repo"
git init . >/dev/null 2>&1
touch "$SBP/repo/.rainforest-gate-off"
(
  export PATH="$SBP/bin:$PATH"
  PAYLOAD='{"cwd":"'"$SBP/repo"'","tool_name":"Bash","tool_input":{"command":"gh pr merge --body \"closes #888\""}}'
  echo "$PAYLOAD" | node "$SRC/hooks/gate-fechar-issue.cjs"
) 2>"$SBP/err-f"
EXIT_F=$?
[ $EXIT_F -eq 0 ] && test_ok "exit 0 (arquivo de emergência)" || test_fail "exit code (foi $EXIT_F)"

# Resultado final
echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ] && exit 0 || exit 1
