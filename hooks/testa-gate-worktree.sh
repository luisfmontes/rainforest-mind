#!/bin/bash
# Bateria do gate-worktree.cjs. Monta repo e worktree git de verdade e alimenta
# o hook com payloads reais de PreToolUse, conferindo o exit code.
# Uso: bash hooks/testa-gate-worktree.sh
#
# O que este teste precisa provar, nesta ordem de importancia:
#   1. que ele BARRA o caso do relatorio (exit 2) — trava que nunca travou nao
#      e evidencia de nada;
#   2. que ele NAO barra a janela principal, nem worktree legitimo, nem leitura,
#      nem arquivo fora de repo git. Falso positivo aqui para o trabalho do usuario
#      em todos os repos, entao os casos que devem PASSAR sao a maioria.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SRC/hooks/gate-worktree.cjs"
# Caminho NATIVO, nao o /tmp/... do Git Bash: o Node no Windows nao resolve
# caminho MSYS, o git falha e o gate libera — a bateria passaria verde
# testando nada. Custou uma rodada inteira em 2026-08-09.
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0
# roda o hook com um payload e confere o exit: 0 = passou, 2 = barrou
gate() { # nome, exit esperado, json
  local nome="$1" esp="$2" json="$3"
  local saida; saida=$(printf '%s' "$json" | node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -6; fi
}

R="$RAIZ/principal"
git init -q "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
echo v1 > "$R/a.txt"; git -C "$R" add .; git -C "$R" commit -qm base
WT="$RAIZ/wt"; git -C "$R" worktree add -q -b trabalho "$WT" >/dev/null 2>&1
FORA="$RAIZ/sem-git"; mkdir -p "$FORA"

j() { # tool, campo-alvo, valor, [extra]
  printf '{"agent_id":"ag-1","agent_type":"executor","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s"}}' \
    "${4:-$R}" "$1" "$2" "$3"
}
esc() { printf '%s' "$1" | sed 's|\\|/|g'; }

echo "== deve BARRAR (exit 2) =="
gate "subagente escreve no repo principal"        2 "$(j Write file_path "$(esc "$R/novo.txt")")"
gate "subagente edita arquivo do repo principal"  2 "$(j Edit file_path "$(esc "$R/a.txt")")"
gate "subagente usa MultiEdit no principal"       2 "$(j MultiEdit file_path "$(esc "$R/a.txt")")"
gate "subagente roda git stash no principal (N1)" 2 "$(printf '{"agent_id":"ag-1","agent_type":"executor","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git stash push -u"}}' "$(esc "$R")")"
gate "subagente roda git checkout no principal"   2 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git checkout main"}}' "$(esc "$R")")"

echo
echo "== deve PASSAR (exit 0) — falso positivo aqui para o trabalho do usuario =="
gate "JANELA PRINCIPAL escrevendo no repo (sem agent_id)" 0 \
  "$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' "$(esc "$R")" "$(esc "$R/x.txt")")"
gate "subagente escrevendo no worktree dele"      0 "$(j Write file_path "$(esc "$WT/novo.txt")" "$(esc "$WT")")"
gate "subagente editando no worktree dele"        0 "$(j Edit file_path "$(esc "$WT/a.txt")" "$(esc "$WT")")"
gate "subagente escrevendo fora de repo git"      0 "$(j Write file_path "$(esc "$FORA/nota.txt")" "$(esc "$FORA")")"
gate "subagente LENDO o repo principal"           0 "$(j Read file_path "$(esc "$R/a.txt")")"
gate "subagente rodando git status (leitura)"     0 \
  "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git status --porcelain"}}' "$(esc "$R")")"
gate "subagente rodando git log (leitura)"        0 \
  "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git log --oneline -5"}}' "$(esc "$R")")"
gate "subagente rodando ls"                       0 \
  "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"ls -la"}}' "$(esc "$R")")"
gate "payload vazio nunca trava"                  0 "{}"
gate "payload ilegivel nunca trava"               0 "isto nao e json"

echo
echo
echo "== o cd do encadeamento: o falso positivo e o falso negativo que ele abre =="
# Ate 2026-08-09 o alvo era ev.cwd — o cwd REGISTRADO da sessao, que num subagente e
# sempre o diretorio principal. Resultado: `cd <worktree> && git commit` era barrado,
# e toda entrega de subagente passou a exigir commit da janela principal.
# Os 22 testes anteriores ficaram VERDES com esse bug de pe, porque nenhum deles
# encadeava `cd`. Estes sao os que faltavam — e o par do meio existe porque a correcao
# obvia (ler o cd e mandar ver) troca o falso positivo por um falso negativo.
b() { # comando, cwd  -> payload Bash
  printf '{"agent_id":"ag-1","agent_type":"executor","tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' \
    "$(esc "$2")" "$(esc "$1")"
}
gate "cd worktree && git commit (O BUG: tem que PASSAR)" 0 \
  "$(b "cd $WT && git commit -m x" "$R")"
gate "git -C worktree commit, cwd no principal"          0 \
  "$(b "git -C $WT commit -m x" "$R")"
gate "cd worktree && git -C PRINCIPAL commit (falso negativo)" 2 \
  "$(b "cd $WT && git -C $R commit -m x" "$R")"
gate "cd worktree, commita, volta e commita no principal" 2 \
  "$(b "cd $WT && git commit -m x && cd $R && git commit -m y" "$R")"
gate "cd para variavel nao resolvivel: barra por conservadorismo" 2 \
  "$(b "cd \$ALVO && git commit -m x" "$R")"
gate "cd para fora de repo git && git commit"            0 \
  "$(b "cd $FORA && git commit -m x" "$R")"

echo "== saidas de emergencia =="
saida=$(printf '%s' "$(j Write file_path "$(esc "$R/novo.txt")")" | RAINFOREST_GATE_OFF=1 node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   RAINFOREST_GATE_OFF=1 libera (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA RAINFOREST_GATE_OFF nao liberou (exit $rc)"; fi

touch "$R/.rainforest-gate-off"
gate ".rainforest-gate-off na raiz libera o repo" 0 "$(j Write file_path "$(esc "$R/novo.txt")")"
rm "$R/.rainforest-gate-off"
gate "  ... e volta a barrar quando o arquivo sai"  2 "$(j Write file_path "$(esc "$R/novo.txt")")"

echo
echo "== a mensagem de bloqueio serve pra alguma coisa? =="
# Desde a P1 (relatorio 2026-08-11-escotilha-do-gate-usada-para-contornar) a
# mensagem MUDA conforme quem a le. Um implementador bloqueado leu o nome do
# arquivo de escape na propria mensagem, criou `.rainforest-gate-off` na raiz do
# checkout principal do usuario e seguiu trabalhando, reportando DONE. A escotilha e
# da JANELA PRINCIPAL — quem tem autoridade de decidir seguir sem isolamento.
#
# Este bloco antes exigia que as escotilhas aparecessem SEMPRE. Testar o texto
# velho depois da mudanca de comportamento so prova que o teste ficou para tras.
msg=$(printf '%s' "$(j Write file_path "$(esc "$R/novo.txt")")" | node "$GATE" 2>&1)
for t in "PARE e reporte" "regra 11"; do
  if printf '%s' "$msg" | grep -q -- "$t"; then ok=$((ok+1)); echo "  ok   a mensagem diz '$t'"
  else falhou=$((falhou+1)); echo "  FALHA a mensagem nao diz '$t'"; fi
done

# Sem agent_id o gate sai cedo (a janela principal e livre), entao a mensagem
# acima ja e a do SUBAGENTE — e nela a escotilha nao pode aparecer.
for t in "RAINFOREST_GATE_OFF" ".rainforest-gate-off" "setup.cjs --desligar"; do
  if printf '%s' "$msg" | grep -q -- "$t"; then
    falhou=$((falhou+1)); echo "  FALHA a mensagem ao subagente REVELA '$t'"
  else
    ok=$((ok+1)); echo "  ok   a mensagem ao subagente nao revela '$t'"
  fi
done
if printf '%s' "$msg" | grep -q -- "a decisao nao e sua"; then
  ok=$((ok+1)); echo "  ok   e o proibe de criar o contorno sozinho"
else
  falhou=$((falhou+1)); echo "  FALHA nao proibe o contorno explicitamente"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
