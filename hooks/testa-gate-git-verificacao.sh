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
#      substituicao de comando `$(...)` e linha continuada com `\`;
#   8. as tres formas achadas atacando o gate ja consertado (rodada 2 da
#      tarefa 2): `bash -c "..."`, `sh -c '...'` e subshell `(...)` — mais
#      flag combinada (`bash -lc`) e aninhamento (`bash -c "bash -c '...'"`)
#      como cobertura extra; e que `bash -c` com comando inofensivo continua
#      passando.
#   9. as quatro formas achadas atacando a rodada 2 (rodada 3 da tarefa 2,
#      terceira e ultima): nome de shell com caminho na frente (`/bin/bash`,
#      `/usr/bin/sh`, `/bin/bash.exe`), `eval "<comando>"`, escape por barra
#      invertida numa flag (`--no\-verify`) e aninhamento de tres niveis de
#      `bash -c` com aspa dupla escapada — mais confirmacao de que o teto de
#      profundidade e fail-closed de verdade: quatro niveis de `bash -c`
#      (alem do teto) barra mesmo com comando final inofensivo, e tres
#      niveis (no teto) com comando final inofensivo passa.
#  10. rodada 4 (revisor independente, achado 1 da revisao reprovada em
#      2026-09-04): variacao de CAIXA no nome do EXECUTAVEL (`GIT`, `Git`,
#      `gIt`, `BASH`, `/BIN/BASH`) tambem barra — mas `EVAL` (builtin do
#      shell, case-sensitive de verdade) NAO e normalizado e continua
#      passando, porque o shell de verdade nem reconheceria o comando; e
#      flag/subcomando tambem nao sao normalizados (`--No-Verify`, `git
#      COMMIT`), porque normalizar ali criaria falso positivo.
#  11. achado 2 da revisao reprovada em 2026-09-04: o toggle de config
#      `.rainforest/config.json` com a chave `gate-git-verificacao` agora
#      registrada em `hooks/lib/config.cjs` desliga o gate de verdade.
#  12. achado 3 (terceira condicao, revisor na 2a rodada de revisao,
#      2026-09-04): corpo de heredoc e DADO, nao comando — sete formas que
#      tem que PASSAR (`<<EOF` simples com a flag citada no corpo, o proprio
#      padrao de commit da sessao com heredoc dentro de `$(...)`, `-F -
#      <<'MSGEOF'`, `<<-EOF` com fechamento indentado por tab, `<<"EOF"` com
#      aspas duplas, dois heredocs no mesmo comando, e o controle sem mencao
#      a flag que ja passava) e uma que tem que CONTINUAR barrando: heredoc
#      legitimo seguido, no MESMO comando bruto, de `git commit --no-verify`
#      fora dele.

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
echo "== rodada 2: bash -c / sh -c / subshell atacando o gate ja consertado: DEVE barrar =="
gate 'bash -c "git commit --no-verify -m x"'          2 "$(b 'bash -c \"git commit --no-verify -m x\"')"
gate "sh -c 'git commit --no-verify -m x'"             2 "$(b "sh -c 'git commit --no-verify -m x'")"
gate "(git commit --no-verify -m x) subshell"          2 "$(b '(git commit --no-verify -m x)')"
gate 'bash -lc "..." (flag combinada antes do -c)'     2 "$(b 'bash -lc \"git commit --no-verify -m x\"')"
gate "bash -c aninhado (bash -c dentro de bash -c)"    2 "$(b "bash -c \\\"bash -c 'git commit --no-verify -m x'\\\"")"

echo
echo "== rodada 2: bash -c com comando inofensivo: DEVE passar =="
gate 'bash -c "echo oi"'                                0 "$(b 'bash -c \"echo oi\"')"
gate 'bash -c "git status"'                             0 "$(b 'bash -c \"git status\"')"

echo
echo "== rodada 3: nome de shell com caminho, eval, escape por barra invertida e aninhamento (achados atacando a rodada 2): DEVE barrar =="
gate 'shell com caminho: /bin/bash -c'  2 "$(b '/bin/bash -c \"git commit --no-verify -m x\"')"
gate 'shell com caminho: /usr/bin/sh -c'  2 "$(b '/usr/bin/sh -c \"git commit --no-verify -m x\"')"
gate 'shell com caminho e .exe: /bin/bash.exe -c'  2 "$(b '/bin/bash.exe -c \"git commit --no-verify -m x\"')"
gate 'eval "git commit --no-verify -m x"'  2 "$(b 'eval \"git commit --no-verify -m x\"')"
gate "eval 'git push --no-verify'"  2 "$(b "eval 'git push --no-verify'")"
gate 'escape por barra invertida (--no\-verify)'  2 "$(b 'git commit --no\\-verify -m x')"
gate 'bash -c aninhado 3x, git no ultimo nivel'  2 "$(b 'bash -c \"bash -c \\\"bash -c \\\\\\\"git commit --no-verify\\\\\\\"\\\"\"')"

echo
echo "== rodada 3: teto de profundidade e fail-closed de verdade =="
gate 'profundidade 4 (alem do teto), comando final inofensivo: fail-closed barra mesmo assim'  2 "$(b 'bash -c \"bash -c \\\"bash -c \\\\\\\"bash -c \\\\\\\\\\\\\\\"echo hi\\\\\\\\\\\\\\\"\\\\\\\"\\\"\"')"
gate 'profundidade 3 (no teto), comando final inofensivo: passa'  0 "$(b 'bash -c \"bash -c \\\"bash -c \\\\\\\"echo hi\\\\\\\"\\\"\"')"
gate 'eval "echo oi" (inofensivo): passa'  0 "$(b 'eval \"echo oi\"')"

echo
echo "== rodada 4: variacao de caixa no executavel (achado 1 da revisao): DEVE barrar =="
gate "GIT commit --no-verify -m x (executavel maiusculo)"  2 "$(b 'GIT commit --no-verify -m x')"
gate "Git commit --no-verify -m x (Capitalizado)"          2 "$(b 'Git commit --no-verify -m x')"
gate "gIt commit -n -m x (caixa mista)"                    2 "$(b 'gIt commit -n -m x')"
gate "GIT push --no-verify"                                2 "$(b 'GIT push --no-verify')"
gate "GIT commit --no-gpg-sign -m x"                        2 "$(b 'GIT commit --no-gpg-sign -m x')"
gate 'Bash -c "git commit --no-verify -m x" (shell Capitalizado)'  2 "$(b 'Bash -c \"git commit --no-verify -m x\"')"
gate 'BASH -c "git commit --no-verify -m x" (shell maiusculo)'     2 "$(b 'BASH -c \"git commit --no-verify -m x\"')"
gate '/BIN/BASH -c "git commit --no-verify -m x" (caminho e nome maiusculos)'  2 "$(b '/BIN/BASH -c \"git commit --no-verify -m x\"')"

echo
echo "== rodada 4: eval, flag e subcomando NAO sao normalizados por caixa: DEVE passar =="
gate 'EVAL "git commit --no-verify -m x" (eval e builtin case-sensitive, shell de verdade nao reconhece)'  0 "$(b 'EVAL \"git commit --no-verify -m x\"')"
gate "git commit --No-Verify -m x (flag com caixa diferente, git rejeitaria como opcao desconhecida)"  0 "$(b 'git commit --No-Verify -m x')"
gate "git COMMIT --no-verify -m x (subcomando com caixa diferente, git nem reconhece)"  0 "$(b 'git COMMIT --no-verify -m x')"

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
echo "== achado 3 (terceira condicao, revisor na 2a rodada de revisao): corpo de heredoc e DADO, nao comando =="
gate "cat > docs.md <<EOF / git commit --no-verify NO CORPO / EOF -- git nao e invocado, DEVE passar" \
  0 "$(b 'cat > docs.md <<EOF\ngit commit --no-verify\nEOF')"

gate "padrao de commit da sessao: git commit -m \"\$(cat <<'EOF' ... EOF )\" citando a flag em prosa -- DEVE passar" \
  0 "$(b 'git commit -m \"$(cat <<'"'"'EOF'"'"'\nDocumenta a proibicao de git commit --no-verify no briefing.\nEOF\n)\"')"

gate "git commit -q -F - <<'MSGEOF' ... MSGEOF citando a flag no corpo -- DEVE passar" \
  0 "$(b 'git commit -q -F - <<'"'"'MSGEOF'"'"'\nProibe git commit --no-verify no executor\nMSGEOF')"

gate "<<-EOF com linha de fechamento indentada por TAB -- DEVE passar" \
  0 "$(b 'cat > docs.md <<-EOF\ngit commit --no-verify\n\tEOF')"

gate 'heredoc com delimitador entre aspas duplas <<"EOF"' \
  0 "$(b 'cat > docs.md <<\"EOF\"\ngit commit --no-verify\nEOF')"

gate "dois heredocs no mesmo comando, os dois citando a flag em prosa -- DEVE passar" \
  0 "$(b 'cat > a.md <<EOF1\ngit commit --no-verify primeira mencao\nEOF1\ncat > b.md <<EOF2\ngit commit --no-verify segunda mencao\nEOF2')"

gate "controle: heredoc sem mencao a flag (ja passava antes do conserto)" \
  0 "$(b 'cat > docs.md <<EOF\ntexto qualquer\nEOF')"

gate "o caso que mais importa: heredoc legitimo + git commit --no-verify FORA dele no MESMO comando -- DEVE barrar" \
  2 "$(b 'cat > docs.md <<EOF\ntexto qualquer\nEOF\ngit commit --no-verify -m x')"

gate "herestring (<<<) nao e heredoc e nao e alvo deste conserto (git nao e invocado aqui de qualquer forma)" \
  0 "$(b "cat <<< 'algo com --no-verify dentro'")"

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
echo "== achado 2: toggle de config .rainforest/config.json (chave gate-git-verificacao) =="
mkdir -p "$R/.rainforest"
printf '%s' '{"gate-git-verificacao": false}' > "$R/.rainforest/config.json"
gate "config do projeto com a chave em false libera o repo"  0 "$(b 'git commit --no-verify -m x')"
rm -rf "$R/.rainforest"
gate "  ... e volta a barrar sem esse arquivo (padrao ligado)"  2 "$(b 'git commit --no-verify -m x')"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
