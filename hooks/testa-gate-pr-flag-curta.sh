#!/usr/bin/env bash
# Bateria: o gate-fechar-issue acha o corpo do PR em toda grafia de flag que o
# gh (pflag) aceita — -b/-F com valor colado, -F=, -F separado — e ignora -B
# e -f como corpo. Cada caso e uma linha da tabela de casos do design
# docs/rainforest/design/gate-pr-flag-curta.md (D1, D2, D3, D5). Cobre tambem a
# ajuda do gh (D3/D4 do design fechar-issue-pronto-e-ajuda).
#
# Cada caso manda o payload real de PreToolUse ao gate e le o stderr. Um gh
# falso (sai 1) fica a frente do PATH: nenhum caso consulta o GitHub real.

set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
SBP_WIN="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }

mkdir -p "$SBP/bin"
printf '#!/bin/sh\nexit 1\n' > "$SBP/bin/gh"
chmod +x "$SBP/bin/gh"

# Os tres arquivos da tabela: <C> com Closes #12, <N> sem palavra, <F> com Fecha #12.
printf 'Closes #12\n' > "$SBP/c.md"
printf 'corpo sem palavra de fechamento\n' > "$SBP/n.md"
printf 'Fecha #12\n' > "$SBP/f.md"

# roda <comando>: deixa o exit em $E e o stderr em $SBP/err
roda() {
  local payload
  payload=$(node -e 'const [cwd,cmd]=process.argv.slice(1);process.stdout.write(JSON.stringify({cwd,tool_name:"Bash",tool_input:{command:cmd}}))' "$SBP_WIN" "$1")
  printf '%s' "$payload" | PATH="$SBP/bin:$PATH" node "$SRC/hooks/gate-fechar-issue.cjs" >/dev/null 2>"$SBP/err"
  E=$?
}
# tem <nome> <trecho>: o stderr contem o trecho
tem() {
  if grep -qF -- "$2" "$SBP/err"; then test_ok "$1: stderr tem '$2'"
  else test_fail "$1: stderr sem '$2' -- $(head -4 "$SBP/err" | tr '\n' ' ')"; fi
}
sai() { # <nome> <exit esperado>
  if [ "$E" = "$2" ]; then test_ok "$1: exit $2"
  else test_fail "$1: exit esperado $2, veio $E -- $(head -4 "$SBP/err" | tr '\n' ' ')"; fi
}

echo "== (c1..c15) recusas: o corpo com palavra de fechamento é achado =="

roda "gh pr create -B main --title t --body-file $SBP_WIN/c.md"
sai "(c1) create -B main antes do --body-file" 2
tem "(c1) create -B main antes do --body-file" "#12"

roda "gh pr edit 5 -B main --body-file $SBP_WIN/c.md"
sai "(c2) edit -B main antes do --body-file" 2
tem "(c2) edit -B main antes do --body-file" "#12"

roda "gh pr create --title t -F $SBP_WIN/c.md"
sai "(c3) create -F" 2
tem "(c3) create -F" "#12"

roda "gh pr edit 5 -F $SBP_WIN/c.md"
sai "(c4) edit -F" 2
tem "(c4) edit -F" "#12"

roda "gh pr edit 5 -F=$SBP_WIN/c.md"
sai "(c5) edit -F=" 2
tem "(c5) edit -F=" "#12"

roda "gh pr edit 5 -F$SBP_WIN/c.md"
sai "(c6) edit -F colado" 2
tem "(c6) edit -F colado" "#12"

roda 'gh pr edit 5 -b"Closes #12"'
sai "(c7) edit -b colado" 2
tem "(c7) edit -b colado" "#12"

roda "gh pr create --title t -b x --body-file $SBP_WIN/c.md"
sai "(c8) -b benigno antes do --body-file" 2
tem "(c8) -b benigno antes do --body-file" "#12"

roda "gh pr create --title t --body-file $SBP_WIN/n.md -b \"Closes #12\""
sai "(c9) --body-file benigno antes do -b" 2
tem "(c9) --body-file benigno antes do -b" "#12"

roda "gh pr create -B main --fill"
sai "(c10) create -B main --fill" 2
tem "(c10) create -B main --fill" "editor interativo"

roda "gh issue comment 1 -F $SBP_WIN/f.md"
sai "(c11) issue comment -F com palavra falsa" 2
tem "(c11) issue comment -F com palavra falsa" "Closes #12"

roda 'gh pr create --fill --title "-bar"'
sai "(c12) create --fill com título -bar" 2
tem "(c12) create --fill com título -bar" "editor interativo"

roda 'gh pr create --fill -t "-Fx"'
sai "(c13) create --fill com -t -Fx" 2
tem "(c13) create --fill com -t -Fx" "editor interativo"

roda "gh issue comment 1 -b \"Fecha #12\" -F $SBP_WIN/nao-existe.md"
sai "(c14) issue comment com palavra falsa e -F inexistente" 2
tem "(c14) issue comment com palavra falsa e -F inexistente" "Closes #12"

roda 'gh pr create --fill --attach "-bar"'
sai "(c15) create --fill com --attach -bar" 2
tem "(c15) create --fill com --attach -bar" "editor interativo"

echo "== (v1..v8) vizinhos legítimos passam =="

roda "gh pr create --title t -F $SBP_WIN/n.md"
sai "(v1) create -F sem fechamento" 0

roda "gh pr create -B main --title t --body-file $SBP_WIN/n.md"
sai "(v2) create -B main com corpo benigno" 0

roda "gh pr edit 5 -B main"
sai "(v3) edit -B sem corpo" 0

roda "gh pr edit 5 --title x"
sai "(v4) edit só título" 0

roda 'gh pr create --title "-bar" --body-file '"$SBP_WIN"'/n.md'
sai "(v5) título -bar com corpo benigno" 0

roda 'gh pr create --title t --body "-Fx sem fechamento"'
sai "(v6) corpo direto começando com -F" 0

roda "gh issue comment 1 -b \"Segue #12\" -F $SBP_WIN/nao-existe.md"
sai "(v7) issue comment benigno com -F inexistente" 0

roda 'gh issue create --title t --type "-bar" -b ok'
sai "(v8) issue create com --type -bar" 0

echo "== (f1) -f não é corpo =="

roda "gh pr create --title t -f"
sai "(f1) create -f" 2
tem "(f1) create -f" "editor interativo"

echo "== (h1..h10) ajuda do gh =="

roda "gh pr create --help"
sai "(h1) pr create --help" 0

roda "gh pr create -h"
sai "(h2) pr create -h" 0

roda "gh pr edit --help"
sai "(h3) pr edit --help" 0

roda "gh issue create --help"
sai "(h4) issue create --help" 0

roda "gh issue comment --help"
sai "(h5) issue comment --help" 0

roda "gh help pr create"
sai "(h6) help pr create" 0

roda "gh pr create --title t"
sai "(h7) pr create --title t" 2

roda "gh pr create --title t --help"
sai "(h8) pr create --title t --help" 2

roda 'gh pr create --help --body "Closes #12"'
sai "(h9) pr create --help --body Closes" 2

roda "gh pr create -dh"
sai "(h10) pr create -dh" 2

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
exit 0
