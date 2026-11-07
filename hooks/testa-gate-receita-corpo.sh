#!/usr/bin/env bash
# Bateria: as recusas do corpo do PR no gate-fechar-issue terminam todas na
# mesma receita, e a do arquivo ilegivel diz o caminho e o motivo.
# Design: docs/rainforest/design/2026-11-07-receita-corpo-pr.md (D1, D2).
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
nao_tem() {
  if grep -qF -- "$2" "$SBP/err"; then test_fail "$1: stderr ainda tem '$2'"
  else test_ok "$1: stderr sem '$2'"; fi
}
sai() { # <nome> <exit esperado>
  if [ "$E" = "$2" ]; then test_ok "$1: exit $2"
  else test_fail "$1: exit esperado $2, veio $E -- $(head -4 "$SBP/err" | tr '\n' ' ')"; fi
}

echo "== (1) variável no --body-file =="
roda 'gh pr create --title t --body-file "$X/pr.md"'
sai "(1) variável" 2
tem "(1) variável" "variável que o gate não resolve"
tem "(1) variável" "Receita que passa:"
tem "(1) variável" "--body-file \"<caminho literal>\""

echo "== (2) cwd incerto =="
roda 'cd $(pwd)/x && gh pr create --title t --body-file corpo.md'
sai "(2) cwd incerto" 2
tem "(2) cwd incerto" "Receita que passa:"

echo "== (3) arquivo inexistente =="
INEX="C:/rfm-nao-existe-$$/pr.md"
roda "gh pr create --title t --body-file \"$INEX\""
sai "(3) arquivo inexistente" 2
tem "(3) arquivo inexistente" "Receita que passa:"
tem "(3) arquivo inexistente" "Grave o corpo antes"
tem "(3) arquivo inexistente" "não existe em $INEX"

echo "== (4) /tmp do Git Bash =="
roda "gh pr create --title t --body-file /tmp/rfm-$$.md"
sai "(4) /tmp do Git Bash" 2
tem "(4) /tmp do Git Bash" "/tmp do Git Bash"
tem "(4) /tmp do Git Bash" "Receita que passa:"

echo "== (5) --body com crase =="
roda 'gh pr create --title t --body "uso de `x`"'
sai "(5) --body com crase" 2
tem "(5) --body com crase" "substituição de comando"
tem "(5) --body com crase" "Receita que passa:"
nao_tem "(5) --body com crase" "texto-plano"

echo "== (6) editor interativo =="
roda 'gh pr create --title t'
sai "(6) editor interativo" 2
tem "(6) editor interativo" "Receita que passa:"

echo "== (7) vizinho legítimo: --body-file literal existente, sem fechamento =="
printf 'corpo sem palavra de fechamento\n' > "$SBP/corpo-ok.md"
roda "gh pr create --title t --body-file \"$SBP_WIN/corpo-ok.md\""
sai "(7) vizinho legítimo" 0

echo "== (8) diretório no lugar do arquivo =="
roda "gh pr create --title t --body-file \"$SBP_WIN\""
sai "(8) diretório" 2
tem "(8) diretório" "EISDIR"
tem "(8) diretório" "Receita que passa:"

echo "== (10) relativo: a mensagem diz onde o gate procurou =="
roda "gh pr create --title t --body-file corpo-inexistente-$$.md"
sai "(10) relativo" 2
tem "(10) relativo" "(resolvido para $SBP_WIN/corpo-inexistente-$$.md)"

echo "== (10b) absoluto com contrabarra não repete o caminho =="
INEXB="C:\\rfm-nao-existe-$$\\pr.md"
roda "gh pr create --title t --body-file \"$INEXB\""
sai "(10b) contrabarra" 2
nao_tem "(10b) contrabarra" "resolvido para"

echo "== (11) UNC não é caminho do Git Bash =="
roda "gh pr create --title t --body-file //rfm-srv-$$/share/pr.md"
sai "(11) UNC" 2
nao_tem "(11) UNC" "Git Bash"
tem "(11) UNC" "Receita que passa:"

echo "== (12) --body-file - (stdin) =="
roda "gh pr create --title t --body-file -"
sai "(12) stdin" 2
tem "(12) stdin" "lê o corpo do stdin"

echo "== (9) heredoc ilegível cria o --body-file =="
CMD9="$(printf 'cat > x9.md <<EOF\nCloses #$N\nEOF\ngh pr create --title t --body-file x9.md')"
roda "$CMD9"
sai "(9) heredoc ilegível" 2
tem "(9) heredoc ilegível" "heredoc deste comando"
tem "(9) heredoc ilegível" "Receita que passa:"
nao_tem "(9) heredoc ilegível" "não consegui ler"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
exit 0
