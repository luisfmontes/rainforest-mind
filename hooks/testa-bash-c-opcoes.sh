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
# achado 4 (zerar-issues-14, tarefa 5): `'-o'` citado vira opcao, nao script; so ehOpcaoDisfarcada barra.
espera_bloqueio "bash -c '-o' errexit 'g\\h issue close 12'"
# achado 5: a rede olha palavra por palavra; `/usr/bin/gh` e `gh` como palavra barram.
espera_bloqueio "bash -c 'echo hi' x /usr/bin/gh"
# achado 7: o cmd aceita o comando colado a //c.
espera_bloqueio "cmd //cgh issue close 12"
espera_bloqueio "cmd //c\"gh issue close 12\""
# achado 8: -Command depois de outros parametros, e parametro com valor consome o valor.
espera_bloqueio "pwsh -NoProfile -Command \"gh issue close 12\""
espera_bloqueio "powershell -NoProfile -ExecutionPolicy Bypass -Command \"gh issue close 12\""
# achado 9: fish roda o script de -c.
espera_bloqueio "fish -c 'gh issue close 12'"
# Revisao de seguranca do commit 6b306b39: fish com contrabarra/parenteses, pwsh
# sem -Command com gh colado a separador, -Version com valor, $' no meio do eval.
espera_bloqueio "fish -c 'g\\h issue close 12'"
espera_bloqueio "fish -c '(echo gh) issue close 12'"
espera_bloqueio "pwsh -NoProfile \"gh;issue close 12\""
espera_bloqueio "powershell -Version 5 -Command \"gh issue close 12\""
espera_bloqueio "eval echo hi\\; \$'gh' issue close 12"
# Revisao de seguranca do commit c66b56ee: fish por lista do que e permitido,
# $' em qualquer ponto do script de bash -c, texto posicional do powershell.
espera_bloqueio "fish -c 'g{h,} issue close 12'"
espera_bloqueio "bash -c \"echo hi; \"\$'gh issue close 12'"
espera_bloqueio "powershell \"gh issue close 12\""

echo
echo "== passa: o script lido nao fecha Issue =="
espera_passa "bash -co errexit 'echo hi'"
espera_passa "bash -c -xo errexit 'echo hi' x"
espera_passa "bash -c 'echo hi' x"
espera_passa "bash -xc 'echo hi'"
# achado 5: `gh` dentro de um caminho ou de um argumento nao e a palavra gh.
espera_passa "bash -c 'echo hi' x --repo gh/foo"
espera_passa "bash -c 'ls' x /srv/gh/y"
# achado 8 e 9: o -Command sem gh, o cmd com comando seguro e o fish sem gh passam.
espera_passa "pwsh -NoProfile -Command \"Get-ChildItem\""
espera_passa "cmd //c dir"
espera_passa "fish -c 'echo hi'"
espera_passa "pwsh -NoProfile -File x.ps1"
espera_passa "powershell Get-ChildItem"
espera_passa "powershell -NoProfile -Command \"Write-Host gh\""

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
if [ "$falhou" -ne 0 ]; then exit 1; fi
exit 0
