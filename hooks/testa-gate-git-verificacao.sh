#!/bin/bash
# Bateria do gate-git-verificacao.cjs. Alimenta o hook com payloads na forma
# real de `.rainforest/portaria/amostra.json` (hook_event_name, tool_name,
# cwd, tool_input.command) e confere o exit code.
# Uso: bash hooks/testa-gate-git-verificacao.sh
#
# O que esta bateria precisa provar, nesta ordem:
#   1. que BARRA (exit 2) `git commit --no-verify`, `git commit -n`,
#      `git commit --no-gpg-sign` e `git push --no-verify` — os quatro pulos
#      de verificacao que o plano nomeia (D8-D11);
#   2. que NAO barra `git push -n`: em push, -n e --dry-run, nao --no-verify,
#      e isto e invariante do plano — barrar aqui seria falso positivo;
#   3. que `--no-verify` dentro de uma STRING de mensagem nao dispara o gate;
#   4. flag agrupada e `git -c ... commit` continuam identificando o
#      subcomando certo;
#   5. que qualquer comando que nao seja `git`, e qualquer `tool_name` que nao
#      seja `Bash`, passa sempre;
#   6. as saidas de emergencia (RAINFOREST_GATE_OFF, .rainforest-gate-off);
#   7. os nove contornos medidos pelo security review (criterio ampliado da
#      tarefa 2, commit 7d0fb268): flag citada de tres formas, abreviacao de
#      long option, separador `&`, prefixo nao-reconhecido (`then`),
#      substituicao de comando `$(...)` e linha continuada com `\`.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SRC/hooks/gate-git-verificacao.cjs"
RAIZ_POSIX="$(mktemp -d)"
# Caminho NATIVO, nao o /tmp/... do Git Bash: o Node no Windows nao resolve
# caminho MSYS, o git falha e o gate liberaria calado — custou uma rodada
# inteira em 2026-08-09 no gate irmao (gate-staging-total).
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

# Raiz de dados descartavel: nao ler a config real de quem roda a bateria
# (Issue #160, mesmo cuidado do testa-gate-staging-total.sh).
export RFM_ROOT="$RAIZ/dados-neutros"; mkdir -p "$RFM_ROOT"

ok=0; falhou=0
gate() { # nome, exit esperado, json
  local nome="$1" esp="$2" json="$3"
  local saida; saida=$(printf '%s' "$json" | node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; fi
}

R="$RAIZ/principal"
git init -q "$R"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false

esc() { printf '%s' "$1" | sed 's|\\|/|g'; }
# payload na forma real de .rainforest/portaria/amostra.json, adaptado para
# tool_name "Bash" e o comando em tool_input.command.
b() { printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "${2:-$(esc "$R")}" "$1"; }

echo "== os quatro criterios do plano: DEVE barrar (exit 2) =="
gate "git commit --no-verify -m x"          2 "$(b 'git commit --no-verify -m x')"
gate "git commit -n -m x"                   2 "$(b 'git commit -n -m x')"
gate "git commit --no-gpg-sign -m x"        2 "$(b 'git commit --no-gpg-sign -m x')"
gate "git push --no-verify"                 2 "$(b 'git push --no-verify')"

echo
echo "== os dois criterios do plano: DEVE passar (exit 0) =="
gate "git commit -m x"                      0 "$(b 'git commit -m x')"
gate "git push -n (e --dry-run, nao --no-verify)" 0 "$(b 'git push -n')"

echo
echo "== a flag dentro da MENSAGEM nao conta =="
gate 'git commit -m "removi o --no-verify do script"' 0 "$(b 'git commit -m \"removi o --no-verify do script\"')"
gate "git commit -m 'tirei o -n do fluxo'"  0 "$(b "git commit -m 'tirei o -n do fluxo'")"

echo
echo "== os nove contornos do security review: DEVE barrar (exit 2) =="
gate "flag citada com aspas simples"            2 "$(b "git commit '--no-verify' -m x")"
gate 'flag citada com aspas duplas'              2 "$(b 'git commit \"--no-verify\" -m x')"
gate 'flag com aspas coladas (--no-"verify")'    2 "$(b 'git commit --no-\"verify\" -m x')"
gate "abreviacao --no-veri (git aceita)"         2 "$(b 'git commit --no-veri -m x')"
gate "abreviacao --no-ver (git aceita)"          2 "$(b 'git commit --no-ver -m x')"
gate "separador & solto"                         2 "$(b 'foo & git commit --no-verify -m x')"
gate "prefixo nao-reconhecido (then)"            2 "$(b 'if true; then git commit --no-verify -m x; fi')"
gate 'substituicao de comando $(...)'            2 "$(b 'echo $(git commit --no-verify -m x)')"
gate "linha continuada com \\ + quebra"          2 "$(b 'git commit \\\n --no-verify -m x')"

echo
echo "== --no-edit nao e prefixo de nenhuma flag proibida: DEVE passar =="
gate "git commit --no-edit --amend"              0 "$(b 'git commit --no-edit --amend')"

echo
echo "== flag agrupada e git -c ... commit =="
gate "git commit -an (agrupada com -n)"     2 "$(b 'git commit -an -m x')"
gate "git commit -am (sem -n, so -a)"       0 "$(b 'git commit -am mensagem')"
gate "git -c commit.gpgsign=false commit -m x (identifica o subcomando certo)" 0 "$(b 'git -c commit.gpgsign=false commit -m x')"
gate "git -C <dir> commit --no-verify (cwd em outro lugar)" 2 "$(printf '{"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git -C %s commit --no-verify -m x"}}' "$(esc "$RAIZ")" "$(esc "$R")")"

echo
echo "== o resto passa sempre =="
gate "git status"                           0 "$(b 'git status')"
gate "git log --oneline"                    0 "$(b 'git log --oneline -5')"
gate "git push (sem flag nenhuma)"          0 "$(b 'git push')"
gate "git commit --amend --no-edit"         0 "$(b 'git commit --amend --no-edit')"
gate "comando que nao e git"                0 "$(b 'ls -la')"
gate "tool_name diferente de Bash"          0 "$(printf '{"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"x"}}' "$(esc "$R")")"
gate "payload vazio nunca trava"            0 "{}"
gate "payload ilegivel nunca trava"         0 "isto nao e json"

echo
echo "== saidas de emergencia =="
saida=$(printf '%s' "$(b 'git commit --no-verify -m x')" | RAINFOREST_GATE_OFF=1 node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   RAINFOREST_GATE_OFF=1 libera (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA RAINFOREST_GATE_OFF nao liberou (exit $rc)"; fi

touch "$R/.rainforest-gate-off"
gate ".rainforest-gate-off na raiz libera o repo"   0 "$(b 'git commit --no-verify -m x')"
rm "$R/.rainforest-gate-off"
gate "  ... e volta a barrar quando o arquivo sai"  2 "$(b 'git commit --no-verify -m x')"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
