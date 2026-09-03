#!/bin/bash
# Bateria para scripts/fechar-issue.cjs com trava: verifica que gh é do sandbox

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# Criar stub em batch
mkdir -p "$SBP/bin"
cat > "$SBP/bin/gh.cmd" <<'STUB'
@echo off
setlocal enabledelayedexpansion
if not "!GH_LOG!"=="" echo CHAMADA: gh %* >> "!GH_LOG!"
if not "!GH_LOG!"=="" (
  for %%A in (%*) do (
    if "%%A"=="--body-file" (
      set "next=1"
    ) else if !next! equ 1 (
      echo CORPO: >> "!GH_LOG!"
      type "%%A" >> "!GH_LOG!"
      echo --- >> "!GH_LOG!"
      set "next=0"
    )
  )
)
if "%1"=="issue" if "%2"=="comment" if not "!GH_COMMENT_FAIL!"=="" exit /b 1
exit /b 0
STUB

# TRAVA: verificar que gh resolvido é do sandbox, não do sistema
echo "== TRAVA: verificar que gh é do sandbox =="
(
  export PATH="$SBP/bin:$PATH"
  node "$SRC/scripts/fechar-issue.cjs" --verificar-gh "$SBP/bin"
) >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "  ok   gh é do sandbox"
else
  echo "  FALHA gh NÃO é do sandbox ou não encontrado"
  echo "== resultado: 0 ok, 1 falha(s) =="
  exit 1
fi

# Caso (a): sucesso, exit 0
echo
echo "== (a) gh issue comment com sucesso → gh issue close é chamado =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-a"
  node "$SRC/scripts/fechar-issue.cjs" 999901 --comando "git log -1" --saida "commit abc123"
) >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_A="$(cat "$SBP/log-a" 2>/dev/null || echo '')"
[ -n "$LOG_A" ] && {
  echo "$LOG_A" | grep -q "issue comment" && test_ok "issue comment" || test_fail "issue comment"
  echo "$LOG_A" | grep -q "issue close" && test_ok "issue close" || test_fail "issue close"
  echo "$LOG_A" | grep -q "<!-- rainforest-evidencia -->" && test_ok "marcador" || test_fail "marcador"
  echo "$LOG_A" | grep -q "git log -1" && test_ok "comando" || test_fail "comando"
  echo "$LOG_A" | grep -q "commit abc123" && test_ok "saída" || test_fail "saída"
} || {
  test_fail "log vazio"
  test_fail "issue comment"
  test_fail "issue close"
  test_fail "marcador"
  test_fail "comando"
  test_fail "saída"
}

# Caso (b): comment falha, exit != 0
echo
echo "== (b) gh issue comment falha → gh issue close NUNCA é chamado =="
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-b"
  export GH_COMMENT_FAIL=1
  node "$SRC/scripts/fechar-issue.cjs" 999902 --comando "echo teste" --saida "ok"
) >/dev/null 2>&1
[ $? -ne 0 ] && test_ok "exit != 0" || test_fail "exit code"
LOG_B="$(cat "$SBP/log-b" 2>/dev/null || echo '')"
[ -n "$LOG_B" ] && {
  echo "$LOG_B" | grep -q "issue comment" && test_ok "issue comment" || test_fail "issue comment"
  echo "$LOG_B" | grep -q "issue close" && test_fail "issue close exists" || test_ok "issue close absent"
} || {
  test_fail "log vazio"
  test_fail "issue comment"
}

# Caso (c): --saida-arquivo lê arquivo
echo
echo "== (c) --saida-arquivo lê arquivo e coloca no comentário =="
echo "resultado: sucesso" > "$SBP/arquivo.txt"
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-c"
  node "$SRC/scripts/fechar-issue.cjs" 999903 --comando "bash teste.sh" --saida-arquivo "$SBP/arquivo.txt"
) >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_C="$(cat "$SBP/log-c" 2>/dev/null || echo '')"
[ -n "$LOG_C" ] && {
  echo "$LOG_C" | grep -q "resultado: sucesso" && test_ok "arquivo lido" || test_fail "arquivo lido"
  echo "$LOG_C" | grep -q "<!-- rainforest-evidencia -->" && test_ok "marcador" || test_fail "marcador"
  echo "$LOG_C" | grep -q "bash teste.sh" && test_ok "comando" || test_fail "comando"
} || {
  test_fail "log vazio"
  test_fail "arquivo lido"
  test_fail "marcador"
  test_fail "comando"
}

# Caso (d): --saida com caminho existente trata como texto
echo
echo "== (d) --saida '.env' trata como texto literal, NÃO lê arquivo =="
echo "SECRET_KEY=segredo" > "$SBP/.env"
(
  export PATH="$SBP/bin:$PATH"
  export GH_LOG="$SBP/log-d"
  cd "$SBP"
  node "$SRC/scripts/fechar-issue.cjs" 999904 --comando "test" --saida ".env"
) >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_D="$(cat "$SBP/log-d" 2>/dev/null || echo '')"
[ -n "$LOG_D" ] && {
  echo "$LOG_D" | grep -q "SECRET_KEY" && test_fail "arquivo FOI lido!" || test_ok "arquivo NÃO lido"
  echo "$LOG_D" | grep -q "\.env" && test_ok ".env literal" || test_fail ".env literal"
} || {
  test_fail "log vazio"
  test_ok "arquivo NÃO lido"
  test_fail ".env literal"
}

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
