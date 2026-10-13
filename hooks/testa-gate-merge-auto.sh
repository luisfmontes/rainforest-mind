#!/bin/bash
# Bateria para o `--auto` barrado no `gh pr merge` (hooks/gate-fechar-issue.cjs,
# chave `gate-merge-auto`). Neste repo não há check obrigatório: `--auto`
# mergeia na hora, sem esperar o CI.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
SBP_WIN="$(cygpath -m "$SBP")"
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }

mkdir -p "$SBP/bin" "$SBP/proj" "$SBP/lar/.rainforest"
# Config do usuário isolada: sem ela, o teste leria a config real da máquina.
export RFM_ROOT="$SBP/lar/.rainforest"

# Stub de gh: só `pr view` importa (devolve o corpo de GH_PR_VIEW_BODY).
# Versão POSIX (sem extensão) e .cmd, a que o resolvedor escolhe no Windows.
cat > "$SBP/bin/gh" <<'STUB'
#!/bin/bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  node -e "console.log(JSON.stringify({body: process.env.GH_PR_VIEW_BODY || ''}))"
  exit 0
fi
exit 0
STUB
chmod +x "$SBP/bin/gh"
cat > "$SBP/bin/gh.cmd" <<'STUB'
@echo off
if "%1"=="pr" if "%2"=="view" (
  node -e "console.log(JSON.stringify({body: process.env.GH_PR_VIEW_BODY || ''}))"
  exit /b 0
)
exit /b 0
STUB

echo "== TRAVA: o stub é o do sandbox =="
RESOLVIDO="$(PATH="$SBP/bin:$PATH" command -v gh)"
case "$RESOLVIDO" in
  "$SBP/bin/gh") test_ok "command -v gh aponta para o sandbox" ;;
  *) test_fail "command -v gh fora do sandbox (veio: $RESOLVIDO)"; echo "ok: $ok   falhou: $falhou"; exit 1 ;;
esac

# gate CMD_FERRAMENTA COMANDO CWD [VAR=valor ...] → exit do gate; stderr em $SBP/err
gate() {
  local f="$1" c="$2" d="$3"; shift 3
  GT="$f" GC="$c" GD="$d" node -e 'process.stdout.write(JSON.stringify({tool_name:process.env.GT,tool_input:{command:process.env.GC},cwd:process.env.GD}))' > "$SBP/payload.json"
  env "$@" PATH="$SBP/bin:$PATH" node "$SRC/hooks/gate-fechar-issue.cjs" < "$SBP/payload.json" 2> "$SBP/err"
  return $?
}

# barra_motivo: stderr cita o script e o motivo
barra_motivo() {
  grep -q "publicar-branch.cjs esperar-ci" "$SBP/err" && grep -q "mergeia na hora" "$SBP/err"
}

echo
echo "== gh pr merge 5 --squash --auto barra =="
for cmd in "gh pr merge 5 --squash --auto" "gh pr merge --auto 5" "gh pr merge https://github.com/o/r/pull/5 --auto --squash"; do
  gate Bash "$cmd" "$SBP_WIN"; E=$?
  if [ "$E" -eq 2 ] && barra_motivo; then test_ok "Bash: $cmd → exit 2 com motivo"; else test_fail "Bash: $cmd → exit $E (esperado 2 com motivo)"; fi
done
gate PowerShell "gh pr merge 5 --squash --auto" "$SBP_WIN"; E=$?
if [ "$E" -eq 2 ] && barra_motivo; then test_ok "PowerShell: gh pr merge 5 --squash --auto → exit 2 com motivo"; else test_fail "PowerShell: gh pr merge 5 --squash --auto → exit $E (esperado 2 com motivo)"; fi

echo
echo "== formas sem --auto passam =="
for cmd in "gh pr merge 5 --squash" "gh pr merge 5 --disable-auto" "gh pr view 5 --json autoMergeRequest" "grep -n -- \"--auto\" README.md" "echo \"gh pr merge 5 --auto\""; do
  gate Bash "$cmd" "$SBP_WIN"; E=$?
  if [ "$E" -eq 0 ]; then test_ok "$cmd → exit 0"; else test_fail "$cmd → exit $E (esperado 0): $(head -c 300 "$SBP/err")"; fi
done

echo
echo "== desligar: RAINFOREST_GATE_OFF e chave gate-merge-auto =="
gate Bash "gh pr merge 5 --squash --auto" "$SBP_WIN" RAINFOREST_GATE_OFF=1; E=$?
if [ "$E" -eq 0 ]; then test_ok "RAINFOREST_GATE_OFF=1 desliga o gate inteiro, --auto incluso (exit 0; a chave propria e o caso seguinte)"; else test_fail "RAINFOREST_GATE_OFF=1 → exit $E (esperado 0)"; fi

mkdir -p "$SBP/proj/.rainforest"
echo '{"gate-merge-auto": false}' > "$SBP/proj/.rainforest/config.json"
gate Bash "gh pr merge 5 --squash --auto" "$SBP_WIN/proj"; E=$?
if [ "$E" -eq 0 ]; then test_ok "config do projeto gate-merge-auto=false → --auto passa (exit 0)"; else test_fail "config do projeto gate-merge-auto=false → exit $E (esperado 0): $(head -c 300 "$SBP/err")"; fi

echo '{"gate-merge-auto": true}' > "$SBP/proj/.rainforest/config.json"
gate Bash "gh pr merge 5 --squash --auto" "$SBP_WIN/proj"; E=$?
if [ "$E" -eq 2 ] && barra_motivo; then test_ok "config do projeto gate-merge-auto=true → barra"; else test_fail "config do projeto gate-merge-auto=true → exit $E (esperado 2)"; fi

echo
echo "== config ilegivel deixa a trava LIGADA =="
printf '{nao e json' > "$SBP/proj/.rainforest/config.json"
gate Bash "gh pr merge 5 --squash --auto" "$SBP_WIN/proj"; E=$?
if [ "$E" -eq 2 ] && barra_motivo; then test_ok "json quebrado no projeto → --auto continua barrado"; else test_fail "json quebrado no projeto → exit $E (esperado 2)"; fi
rm -f "$SBP/proj/.rainforest/config.json"

echo
echo "ok: $ok   falhou: $falhou"
[ $falhou -eq 0 ] && exit 0 || exit 1
