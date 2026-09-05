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
#  13. achado (quarta condicao, revisor na 3a rodada de revisao, 2026-09-04
#      — contrapartida exata do item 12): delimitador de heredoc SEM aspas
#      sofre expansao de `$(...)`/crase ao ser montado, entao o corpo NAO e
#      so dado — cinco formas que tem que BARRAR (`$(...)` dentro de
#      `<<EOF`, dentro de `: <<EOF`, crase dentro de `<<EOF`, `$(...)`
#      dentro de heredoc aninhado em `bash -c` e `$(...)` dentro de
#      `<<-EOF` com fechamento por tab) e tres controles com delimitador
#      CITADO (`<<'EOF'`, `<<"EOF"`, `<<\EOF`) que tem que continuar
#      PASSANDO — o mesmo `$(...)` no corpo, so que o bash nao expande
#      porque o delimitador esta citado.

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
gate "git commit -nm x (agrupada -n com -m)" 2 "$(b 'git commit -nm x')"
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
echo "== achado (quarta condicao, revisor na 3a rodada de revisao, 2026-09-04): heredoc SEM aspas sofre expansao =="
echo "== -- contrapartida exata da terceira condicao: DEVE barrar (o \$(...)/crase do corpo executa de verdade) =="
gate "cat > out.txt <<EOF / \$(git commit --no-verify -m x) NO CORPO SEM ASPAS -- DEVE barrar" \
  2 "$(b 'cat > out.txt <<EOF\n$(git commit --no-verify -m x)\nEOF')"

gate ": <<EOF / \$(git commit --no-verify -m x) NO CORPO -- DEVE barrar" \
  2 "$(b ': <<EOF\n$(git commit --no-verify -m x)\nEOF')"

gate "cat > out.txt <<EOF / crase envolvendo git commit --no-verify NO CORPO -- DEVE barrar" \
  2 "$(b 'cat > out.txt <<EOF\n`git commit --no-verify -m x`\nEOF')"

gate 'bash -c "cat > /tmp/x <<EOF / $(git commit --no-verify -m x) / EOF" (heredoc aninhado em bash -c) -- DEVE barrar' \
  2 "$(b 'bash -c \"cat > /tmp/x <<EOF\n$(git commit --no-verify -m x)\nEOF\"')"

gate "cat > out.txt <<-EOF (com tab) / \$(git push --no-verify) NO CORPO -- DEVE barrar" \
  2 "$(b 'cat > out.txt <<-EOF\n$(git push --no-verify)\n\tEOF')"

echo
echo "== controles: delimitador CITADO com substituicao no corpo continua passando (nao pode regredir) =="
gate "cat > docs.md <<'EOF' (citado) / \$(git commit --no-verify -m x) NO CORPO -- DEVE continuar passando" \
  0 "$(b 'cat > docs.md <<'"'"'EOF'"'"'\n$(git commit --no-verify -m x)\nEOF')"

gate 'cat > docs.md <<"EOF" (citado) / $(git commit --no-verify -m x) NO CORPO -- DEVE continuar passando' \
  0 "$(b 'cat > docs.md <<\"EOF\"\n$(git commit --no-verify -m x)\nEOF')"

gate 'cat > docs.md <<\EOF (citado por barra invertida) / $(git commit --no-verify -m x) NO CORPO -- DEVE continuar passando' \
  0 "$(b 'cat > docs.md <<\\EOF\n$(git commit --no-verify -m x)\nEOF')"

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
echo "== achado 4 (revisor, 4a rodada, 2026-09-04): falso positivo com quebras de linha em aspas =="
echo "== linha dentro de aspas duplas nunca deve separar segmentos =="
gate "git commit -m \"linha um / nunca rode git commit --no-verify / linha tres\" (aspas duplas)" \
  0 "$(b 'git commit -m \"linha um\nnunca rode git commit --no-verify aqui\nlinha tres\"')"

echo "== linha dentro de aspas simples nunca deve separar segmentos =="
gate "git commit -m 'linha um / nunca rode git commit --no-verify / linha tres' (aspas simples)" \
  0 "$(b 'git commit -m '"'"'linha um\nnunca rode git commit --no-verify aqui\nlinha tres'"'"'')"

echo "== separador dentro de aspas nao separa =="
gate "git commit -m \"a; git commit --no-verify\" (ponto-virgula dentro de aspas)" \
  0 "$(b 'git commit -m \"a; git commit --no-verify\"')"

echo "== contraprova: ponto-virgula FORA de aspas DEVE separar =="
gate "git commit -m \"ok\" ; git commit --no-verify -m x (separador fora)" \
  2 "$(b 'git commit -m \"ok\" ; git commit --no-verify -m x')"

gate "git commit -m \"ok\" && git commit --no-verify -m x (separador && fora)" \
  2 "$(b 'git commit -m \"ok\" && git commit --no-verify -m x')"

gate "git commit -m \"ok\" | git commit --no-verify -m x (separador | fora)" \
  2 "$(b 'git commit -m \"ok\" | git commit --no-verify -m x')"

gate "git commit -m \"ok\" / git commit --no-verify -m x (quebra de linha fora de aspas)" \
  2 "$(b 'git commit -m \"ok\"\ngit commit --no-verify -m x')"

echo
echo "== rodada 7 (revisor, 5a rodada, 2026-09-04): ANSI-C quotes (\$'...') e ambiguidade honesta =="
gate "git commit -m \$'Explain -n flag, it\\'s not dry-run here' (\$'...' com apóstrofo escapado)" \
  0 "$(b 'git commit -m $'"'"'Explain -n flag, it'"'"'\'"'"'s not dry-run here'"'"'')"

gate "git commit -m \$'It\\'s done' (controle: apóstrofo escapado, sem prosa perigosa)" \
  0 "$(b 'git commit -m $'"'"'It'"'"'\'"'"'s done'"'"'')"

gate "git commit -m \$'linha um\\nfala de --no-verify\\nlinha tres' (\$'...' multi-linha)" \
  0 "$(b 'git commit -m $'"'"'linha um\nfala de --no-verify\nlinha tres'"'"'')"

gate "git commit -m \$'ok' ; git commit --no-verify -m x (contraprova: ponto-virgula FORA de \$'...')" \
  2 "$(b 'git commit -m $'"'"'ok'"'"' ; git commit --no-verify -m x')"

gate "\$'a\\\\\\\\'  ; git commit --no-verify -m x (contraprova: barra escapada + separador)" \
  2 "$(b 'echo $'"'"'a\\\\'"'"' ; git commit --no-verify -m x')"

gate "git commit -m \$'teste (aspa não fechada com prosa) -- ambiguidade honesta" \
  2 "$(b 'git commit -m $'"'"'teste com --no-verify')"

# bash -c $'...' era não-objetivo (indireção de shell), mas com desembrulho de $'...'
# agora é detectado (melhoria). Remover check — será medido e reportado.
# gate "bash -c \$'git commit --no-verify' (não-objetivo: indireção shell)" \
#   ? "$(b 'bash -c $'"'"'git commit --no-verify'"'"'')"

echo
echo "== falso negativo descoberto na rodada 7: \$'...' com escape de apóstrofo e flag nua depois =="
echo "== (unificação de máquina de estado entre segmentos() e tokens()) =="

# Função auxiliar para construir JSON com contrabarra em $'...'
# Recebe um comando e constrói um JSON com o comando EXATAMENTE como recebido
# Passa a string via stdin em heredoc para evitar interpretação dupla de shell
b_ansi() {
  local cmd_pattern="$1"
  node -e "
const readline = require('readline');
const bs = String.fromCharCode(92);
process.stdin.on('data', (cmdPattern) => {
  // Interpreta sequências de escape manualmente: backslash-quote vira barra+aspa
  const cmdStr = cmdPattern.toString().trim();
  let c = '';
  let i = 0;
  while (i < cmdStr.length) {
    if (cmdStr[i] === '\\\\' && i + 1 < cmdStr.length && cmdStr[i+1] === \"'\") {
      c += bs + \"'\";
      i += 2;
    } else {
      c += cmdStr[i];
      i += 1;
    }
  }
  console.log(JSON.stringify({
    session_id: 's1',
    cwd: '$R'.replace(/\\\\/g, '/'),
    hook_event_name: 'PreToolUse',
    tool_name: 'Bash',
    tool_input: { command: c }
  }));
});
" <<< "$cmd_pattern"
}

# Caso 1: o achado principal - $'...' com escape + flag nua depois
saida=$(printf '%s' "$(b_ansi "git commit -m \$'Fix: don\\'t break tests' --no-verify")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'Fix: don\\'t break tests' --no-verify (achado principal, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA achado: esperava 2, veio $rc"; echo "$saida" | sed 's/^/         /' | head -3; fi

# Caso 2: mesma coisa com -n em vez de --no-verify
saida=$(printf '%s' "$(b_ansi "git commit -m \$'Fix: don\\'t break' -n")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'Fix: don\\'t break' -n (variação, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA variação -n: esperava 2, veio $rc"; fi

# Caso 3: flag também em $'...'
saida=$(printf '%s' "$(b_ansi "git commit -m \$'Fix\\'d bug' \$'--no-verify'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'Fix\\'d bug' \$'--no-verify' (flag em \$'...', exit 2)"
else falhou=$((falhou+1)); echo "  FALHA flag em \$'...': esperava 2, veio $rc"; fi

# Caso 4: --no-gpg-sign
saida=$(printf '%s' "$(b_ansi "git commit -m \$'teste' --no-gpg-sign")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'teste' --no-gpg-sign (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA --no-gpg-sign: esperava 2, veio $rc"; fi

# Caso 5: git push --no-verify (em vez de commit)
saida=$(printf '%s' "$(b_ansi "git push --no-verify")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git push --no-verify (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA git push: esperava 2, veio $rc"; fi

# Caso 6: dois $'...' com escape no mesmo comando, flag nua depois
saida=$(printf '%s' "$(b_ansi "git commit -m \$'It\\'s done' --no-verify")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'It\\'s done' --no-verify (controle com escape, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA controle com escape: esperava 2, veio $rc"; fi

# Caso 7: $'...' com escape dentro de "..." - medir primeiro
echo "  (caso 7: medindo $'...' com escape dentro de \\\"...\\\") "
saida=$(printf '%s' "$(b 'git commit -m \"blah '"'"'$test'"'"'\"')" | node "$GATE" 2>&1); rc=$?
echo "  info  situação base (sem aspa ANSI-C): exit $rc"

# Caso 8: contraprova de falso positivo - $'...' com \' e prosa dentro, sem flag nua
# (requer investigação adicional: pode haver falso positivo)
saida=$(printf '%s' "$(b_ansi "git commit -m \$'Explain it\\'s not --no-verify inside'")" | node "$GATE" 2>&1); rc=$?
echo "  info  git commit -m \$'Explain it\\'s not --no-verify inside' (prosa dentro): exit $rc (requer investigação)"

# Caso 9: bash -c $'...' com escape - fixar exit code atual para rodada futura notar mudança
saida=$(printf '%s' "$(b_ansi "bash -c \$'git commit --no-verify'")" | node "$GATE" 2>&1); rc=$?
echo "  info  bash -c \$'git commit --no-verify': exit $rc (fixado para detecção de mudança)"

echo "== aspa nao fechada: fallback fail-closed =="
# Teste comum
gate "git commit -m \"texto com --no-verify (sem fechar) - fallback" \
  2 "$(b 'git commit -m \"texto com --no-verify')"

# Teste especial: valida que a mensagem de bloqueio e honesta (nao fabrica segmento falso)
# O Defeito B seria: mensagem contem "Comando: git commit --no-verify" (inventado)
# O conserto: mensagem contem "Comando: sintaxe ambígua..." (honesto, com o comando real)
saida=$(printf '%s' "$(b 'git commit -m \"texto com --no-verify')" | node "$GATE" 2>&1)
rc=$?
if [ "$rc" = 2 ]; then
  # Verifica que "Comando:" na mensagem contem o comando recebido (nao fabricado)
  if echo "$saida" | grep -q "Comando:.*git commit -m"; then
    ok=$((ok+1)); echo "  ok   mensagem honesta: nao fabrica segmento falso (exit 2)"
  else
    falhou=$((falhou+1)); echo "  FALHA mensagem: nao contem o comando recebido"; echo "$saida" | sed 's/^/         /'
  fi
  # Valida que NAO contem reconstrucao inventada que nunca existiu
  if echo "$saida" | grep -q "Comando:.*git commit --no-verify\"" && ! echo "$saida" | grep -q "git commit -m"; then
    falhou=$((falhou+1)); echo "  FALHA mensagem fabrica o segmento (Defeito B nao foi consertado)"; echo "$saida" | sed 's/^/         /'
  fi
else
  falhou=$((falhou+1)); echo "  FALHA exit code: esperava 2, veio $rc"
fi

echo
echo "== Testes acrescentados para o Defeito A (desembrulho de \$'...'): DEVE barrar (exit 2) =="
# Prova que a contrabarra está sendo enviada
echo "Prova do JSON.stringify dos comandos com \\' :"

# Teste 1: $'--no-verify' nua
saida=$(printf '%s' "$(b_ansi "git commit \$'--no-verify' -m x")" | node "$GATE" 2>&1); rc=$?
echo "  JSON teste 1 (git commit \$'--no-verify'):"
printf '%s' "$(b_ansi "git commit \$'--no-verify' -m x")" | node -e "const d = JSON.parse(require('fs').readFileSync(0, 'utf8')); console.log('    Command: ' + JSON.stringify(d.tool_input.command));"
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'--no-verify' -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# Teste 2: $'-n' nua (abreviação)
saida=$(printf '%s' "$(b_ansi "git commit \$'-n' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'-n' -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# Teste 3: git push $'--no-verify'
saida=$(printf '%s' "$(b_ansi "git push \$'--no-verify'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git push \$'--no-verify' (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# Teste 4: git commit $'--no-gpg-sign'
saida=$(printf '%s' "$(b_ansi "git commit \$'--no-gpg-sign' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'--no-gpg-sign' -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# Contraprova: flag DENTRO da mensagem (não deve barrar)
saida=$(printf '%s' "$(b_ansi "git commit -m \$'don\\'t use --no-verify here'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'don\\'t use --no-verify here' (exit 0 — flag DENTRO da mensagem)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 0, veio $rc"; fi

# Caso de mudança: bash -c $'...' (não-objetivo, mas detectado agora como melhoria)
saida=$(printf '%s' "$(b_ansi "bash -c \$'git commit --no-verify'")" | node "$GATE" 2>&1); rc=$?
echo "  info  bash -c \$'git commit --no-verify': exit $rc (não-objetivo, mas agora detectado como melhoria; era 0, agora $rc)"

echo
echo "== Testes para Defeito A (escape ANSI-C em \$'...'): DEVE barrar (exit 2) =="
echo "Prova das contrabarras com String.fromCharCode(92):"

# Testes que DEVEM barrar (exit 2) — oito formas
# 1. Hex -n
saida=$(printf '%s' "$(b_ansi "git commit \$'\\x2d\\x6e' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'\\x2d\\x6e' -m x (hex -n, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: hex -n esperava 2, veio $rc"; fi

# 2. Hex --no-verify
saida=$(printf '%s' "$(b_ansi "git commit \$'\\x2d\\x2d\\x6e\\x6f\\x2d\\x76\\x65\\x72\\x69\\x66\\x79' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'\\x2d\\x2d\\x6e\\x6f\\x2d\\x76\\x65\\x72\\x69\\x66\\x79' -m x (hex --no-verify, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: hex --no-verify esperava 2, veio $rc"; fi

# 3. Hex em push
saida=$(printf '%s' "$(b_ansi "git push \$'\\x2d\\x2d\\x6e\\x6f\\x2d\\x76\\x65\\x72\\x69\\x66\\x79'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git push \$'\\x2d\\x2d\\x6e\\x6f\\x2d\\x76\\x65\\x72\\x69\\x66\\x79' (hex push, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: hex push esperava 2, veio $rc"; fi

# 4. Hex parcial (--no-verif\x79)
saida=$(printf '%s' "$(b_ansi "git commit \$'--no-verif\\x79' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'--no-verif\\x79' -m x (hex parcial, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: hex parcial esperava 2, veio $rc"; fi

# 5. Octal -n (\055\156)
saida=$(printf '%s' "$(b_ansi "git commit \$'\\055\\156' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'\\055\\156' -m x (octal -n, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: octal -n esperava 2, veio $rc"; fi

# 6. Unicode4 -n (\u002d\u006e)
saida=$(printf '%s' "$(b_ansi "git commit \$'\\u002d\\u006e' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'\\u002d\\u006e' -m x (unicode4 -n, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: unicode4 -n esperava 2, veio $rc"; fi

# 7. Unicode8 -n (\U0000002d\U0000006e)
saida=$(printf '%s' "$(b_ansi "git commit \$'\\U0000002d\\U0000006e' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'\\U0000002d\\U0000006e' -m x (unicode8 -n, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: unicode8 -n esperava 2, veio $rc"; fi

# 8. Hex --no-gpg-sign
saida=$(printf '%s' "$(b_ansi "git commit \$'\\x2d\\x2d\\x6e\\x6f\\x2d\\x67\\x70\\x67\\x2d\\x73\\x69\\x67\\x6e' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'\\x2d\\x2d\\x6e\\x6f\\x2d\\x67\\x70\\x67\\x2d\\x73\\x69\\x67\\x6e' -m x (hex --no-gpg-sign, exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: hex --no-gpg-sign esperava 2, veio $rc"; fi

echo
echo "== Contraprovas de falso positivo (exit 0) =="

# 1. Mensagem com \x dentro (não é flag)
saida=$(printf '%s' "$(b_ansi "git commit -m \$'texto com \\x2d\\x6e no meio'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'texto com \\x2d\\x6e no meio' (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA: mensagem com hex esperava 0, veio $rc"; fi

# 2. Aspas duplas (bash não decodifica)
saida=$(printf '%s' "$(b_ansi "git commit -m \"use \\x2d\\x6e para pular\"")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit -m \"use \\x2d\\x6e para pular\" (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA: aspas duplas esperava 0, veio $rc"; fi

# 3. Aspa simples (bash não decodifica)
saida=$(printf '%s' "$(b_ansi "git commit -m 'use \\x2d\\x6e para pular'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit -m 'use \\x2d\\x6e para pular' (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA: aspa simples esperava 0, veio $rc"; fi

# 4. Caminho Windows (barra dupla)
saida=$(printf '%s' "$(b_ansi "git commit -m \$'C:\\\\Users\\\\Luis'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'C:\\\\Users\\\\Luis' (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA: caminho Windows esperava 0, veio $rc"; fi

# 5. Hex que vira texto comum
saida=$(printf '%s' "$(b_ansi "git commit -m \$'\\x6f\\x6c\\x61 \\x6d\\x75\\x6e\\x64\\x6f'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'\\x6f\\x6c\\x61 \\x6d\\x75\\x6e\\x64\\x6f' (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA: hex texto esperava 0, veio $rc"; fi

echo
echo "== Verificação da mensagem de bloqueio (inclui origem de escape) =="
saida=$(printf '%s' "$(b_ansi "git commit \$'\\x2d\\x6e' -m x")" | node "$GATE" 2>&1); rc=$?
if echo "$saida" | grep -q "escape ANSI-C\|vindo de escape"; then
  ok=$((ok+1)); echo "  ok   mensagem menciona escape ANSI-C"
else
  falhou=$((falhou+1)); echo "  FALHA: mensagem não menciona escape ANSI-C"
  echo "$saida" | sed 's/^/         /'
fi

echo
echo "== Defeito A: NUL trunca argumentos (8 casos da tabela) =="
# 1. git $'com\0'mit -n -m x -> ARGV[1]=[commit], ARGV[2]=[-n]
saida=$(printf '%s' "$(b_ansi "git \$'com\\0'mit -n -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git \$'com\\0'mit -n -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# 2. git $'pus\0'h --no-verify -> ARGV[1]=[push], ARGV[2]=[--no-verify]
saida=$(printf '%s' "$(b_ansi "git \$'pus\\0'h --no-verify")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git \$'pus\\0'h --no-verify (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# 3. $'gi\0't commit -n -m x -> ARGV[1]=[git], comando "git commit -n"
saida=$(printf '%s' "$(b_ansi "\$'gi\\0't commit -n -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   \$'gi\\0't commit -n -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# 4. git commit $'-n\0lixo' -m x -> ARGV[2]=[-n]
saida=$(printf '%s' "$(b_ansi "git commit \$'-n\\0lixo' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'-n\\0lixo' -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# 5. git commit $'--no-verify\0lixo' -m x -> ARGV[2]=[--no-verify]
saida=$(printf '%s' "$(b_ansi "git commit \$'--no-verify\\0lixo' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'--no-verify\\0lixo' -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# 6. git push $'--no-verify\0lixo' -> ARGV[2]=[--no-verify]
saida=$(printf '%s' "$(b_ansi "git push \$'--no-verify\\0lixo'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git push \$'--no-verify\\0lixo' (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# 7. git commit $'lixo\0-n' -m x -> ARGV[2]=[lixo] ("-n" descartado pelo NUL)
saida=$(printf '%s' "$(b_ansi "git commit \$'lixo\\0-n' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit \$'lixo\\0-n' -m x (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 0, veio $rc"; fi

# 8. git commit -m $'mensagem com \0 no meio' -> mensagem truncada
saida=$(printf '%s' "$(b_ansi "git commit -m \$'mensagem com \\0 no meio'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'mensagem com \\0 no meio' (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 0, veio $rc"; fi

echo
echo "== Defeito B: Fórmula de \\cX estava errada (agora \\cmn = CR=13, não -) =="
# Teste 4: \cmn deve passar (é CR+n, não -n que é um flag)
saida=$(printf '%s' "$(b_ansi "git commit \$'\\cmn' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit \$'\\cmn' -m x (exit 0, passa)"
else falhou=$((falhou+1)); echo "  FALHA: \\cmn esperava 0, veio $rc"; fi

# Teste 5: Verificar que a mensagem NÃO traz sufixo quando flag é nua (sem escape)
# mas TRAZ sufixo quando a flag vem de escape ANSI-C
echo "== Teste 5: Sufixo refletindo origem da flag (não do comando inteiro) =="

# Teste 5a: Flag nua (-n) + escape na mensagem -> mensagem SEM sufixo
saida=$(printf '%s' "$(b_ansi "git commit -n -m \$'linha1\nlinha2'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then
  msg=$(printf '%s' "$saida" | grep "Comando:" | head -1)
  if echo "$msg" | grep -q "vindo de escape ANSI-C"; then
    falhou=$((falhou+1)); echo "  FALHA Teste 5a: flag nua não deveria trazer sufixo"
    echo "$msg" | sed 's/^/         /'
  else
    ok=$((ok+1)); echo "  ok   git commit -n -m \$'linha1\nlinha2' (exit 2, sem sufixo — correto)"
  fi
else falhou=$((falhou+1)); echo "  FALHA Teste 5a: esperava 2, veio $rc"; fi

# Teste 5b: Flag com escape hex (\x2d\x6e = -n) -> mensagem COM sufixo
saida=$(printf '%s' "$(b_ansi "git commit \$'\\x2d\\x6e' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then
  msg=$(printf '%s' "$saida" | grep "Comando:" | head -1)
  if echo "$msg" | grep -q "vindo de escape ANSI-C"; then
    ok=$((ok+1)); echo "  ok   git commit \$'\\x2d\\x6e' -m x (exit 2, com sufixo — correto)"
  else
    falhou=$((falhou+1)); echo "  FALHA Teste 5b: flag com escape deveria trazer sufixo"
    echo "$msg" | sed 's/^/         /'
  fi
else falhou=$((falhou+1)); echo "  FALHA Teste 5b: esperava 2, veio $rc"; fi

echo
echo "== Contraprova: NUL na mensagem (não é um argumento de comando) =="
saida=$(printf '%s' "$(b_ansi "git commit -m \$'mensagem com \\0 no meio'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   NUL na mensagem passa (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA: NUL na mensagem esperava 0, veio $rc"; fi

echo
echo "== Defeito corrigido: NUL seguido de \\' (aspa escapada) =="
# Caso 1: git commit $'--no-verify\0lixo\'ainda' -m x -> ARGV[2]=[--no-verify]
saida=$(printf '%s' "$(b_ansi "git commit \$'--no-verify\\0lixo\\'ainda' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'--no-verify\\0lixo\\'ainda' -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# Caso 2: mesma forma com push
saida=$(printf '%s' "$(b_ansi "git push \$'--no-verify\\0lixo\\'ainda'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git push \$'--no-verify\\0lixo\\'ainda' (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# Caso 3: mesma forma com --no-gpg-sign
saida=$(printf '%s' "$(b_ansi "git commit \$'--no-gpg-sign\\0lixo\\'ainda' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'--no-gpg-sign\\0lixo\\'ainda' -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# Caso 4: duas \\' entre o NUL e o fechamento
saida=$(printf '%s' "$(b_ansi "git commit \$'--no-verify\\0lixo\\'ainda\\'mais' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then ok=$((ok+1)); echo "  ok   git commit \$'--no-verify\\0lixo\\'ainda\\'mais' -m x (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 2, veio $rc"; fi

# Caso 5: \\' ANTES do NUL (dentro do mesmo segmento) — token corrompido, não barra
# bash decodifica para: --no-verify'texto<NUL>lixo, que é um token único <NUL>-terminado
# Como a aspa corrupta o token, não é igual a --no-verify, passa
saida=$(printf '%s' "$(b_ansi "git commit \$'--no-verify\\'texto\\0lixo' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit \$'--no-verify\\'texto\\0lixo' -m x (exit 0 — token corrompido)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 0, veio $rc"; fi

# Caso 6: contraprova - \\' depois do NUL numa mensagem (sem flag nenhuma)
saida=$(printf '%s' "$(b_ansi "git commit -m \$'mensagem\\0com\\'aspa'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   git commit -m \$'mensagem\\0com\\'aspa' (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA: esperava 0, veio $rc"; fi

echo
echo "== Sufixo: NUL no argumento vs flag nua =="
# Teste 6a: Flag isolada por NUL -> mensagem COM sufixo
saida=$(printf '%s' "$(b_ansi "git commit \$'--no-verify\\0lixo' -m x")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then
  msg=$(printf '%s' "$saida" | grep "Comando:" | head -1)
  if echo "$msg" | grep -q "isolado por NUL"; then
    ok=$((ok+1)); echo "  ok   git commit \$'--no-verify\\0lixo' -m x (exit 2, com sufixo NUL — correto)"
  else
    falhou=$((falhou+1)); echo "  FALHA Teste 6a: flag isolada por NUL deveria trazer sufixo"
    echo "$msg" | sed 's/^/         /'
  fi
else falhou=$((falhou+1)); echo "  FALHA Teste 6a: esperava 2, veio $rc"; fi

# Teste 6b: Flag nua (-n) -> mensagem SEM sufixo
saida=$(printf '%s' "$(b_ansi "git commit -n -m \$'linha1\nlinha2'")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 2 ]; then
  msg=$(printf '%s' "$saida" | grep "Comando:" | head -1)
  if ! echo "$msg" | grep -q "isolado por NUL\|vindo de escape ANSI-C"; then
    ok=$((ok+1)); echo "  ok   git commit -n -m \$'linha1\nlinha2' (exit 2, sem sufixo — correto)"
  else
    falhou=$((falhou+1)); echo "  FALHA Teste 6b: flag nua não deveria trazer sufixo"
    echo "$msg" | sed 's/^/         /'
  fi
else falhou=$((falhou+1)); echo "  FALHA Teste 6b: esperava 2, veio $rc"; fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
