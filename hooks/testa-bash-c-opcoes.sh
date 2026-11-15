#!/bin/bash
# Bateria do desempacotador de `bash -c` com opcoes agrupadas, com valor ou
# citadas (zerar-issues-14, tarefa 5). O script de `bash -c` e a palavra depois
# das opcoes: `-co errexit 'gh ...'` tem `errexit` como valor do `-o`, e uma
# palavra citada que vira opcao (`'-o'`) nao e lida, falha fechada.
# Roda o payload real de PreToolUse (Bash) em hooks/gate-fechar-issue.cjs.
# Exit 2 = bloqueado. Exit 0 = passa.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC")"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
SBP_WIN="$(cygpath -m "$SBP")"
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# Devolve o exit code do gate para o comando literal $1 no payload Bash.
saida_do_gate() {
  local payload
  payload="$(node -e 'process.stdout.write(JSON.stringify({cwd:process.argv[1],tool_name:"Bash",tool_input:{command:process.argv[2]}}))' "$SBP_WIN" "$1")"
  printf '%s' "$payload" | node "$SRC/hooks/gate-fechar-issue.cjs" >/dev/null 2>"$SBP/err"
  echo $?
}

espera_bloqueio() {
  local rc
  rc="$(saida_do_gate "$1")"
  if [ "$rc" = 2 ]; then test_ok "exit 2  $1"; else test_fail "$1 (esperado exit 2, saiu $rc)"; fi
}

espera_passa() {
  local rc
  rc="$(saida_do_gate "$1")"
  if [ "$rc" = 0 ]; then test_ok "exit 0  $1"; else test_fail "$1 (esperado exit 0, saiu $rc)"; fi
}

echo
echo "== bloqueia: o script lido tem gh issue close =="
espera_bloqueio "bash -co errexit 'gh issue close 12'"
espera_bloqueio "bash -oc errexit 'gh issue close 12'"
espera_bloqueio "bash -c '-o' errexit 'gh issue close 12'"
espera_bloqueio "bash -c \"-x\" 'gh issue close 12'"
espera_bloqueio "bash -c -xo errexit 'gh issue close 12'"
espera_bloqueio "bash -c 'echo' 'gh issue close 12'"
espera_bloqueio "bash -c -o errexit 'gh issue close 12'"

echo
echo "== passa: o script lido nao fecha Issue =="
espera_passa "bash -co errexit 'echo hi'"
espera_passa "bash -c -xo errexit 'echo hi' x"
espera_passa "bash -c 'echo hi' x"
espera_passa "bash -xc 'echo hi'"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
if [ "$falhou" -ne 0 ]; then exit 1; fi
exit 0
