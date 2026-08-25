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
echo "== redirecionamento e ferramentas de escrita em Bash (Issue #88) =="
gate "echo para arquivo FORA do worktree (novo)"     2 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"echo x > '"'"'%s/novo.txt'"'"'"}}' "$(esc "$R")" "$(esc "$R")")"
gate "echo >> append FORA do worktree"               2 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"echo x >> '"'"'%s/novo.txt'"'"'"}}' "$(esc "$R")" "$(esc "$R")")"
gate "tee para arquivo FORA do worktree"             2 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"echo x | tee '"'"'%s/novo.txt'"'"'"}}' "$(esc "$R")" "$(esc "$R")")"
gate "sed -i arquivo FORA do worktree"               2 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"sed -i '"'"'s/x/y/'"'"' '"'"'%s/a.txt'"'"'"}}' "$(esc "$R")" "$(esc "$R")")"
gate "cp para FORA do worktree"                      2 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"cp '"'"'%s/a.txt'"'"' '"'"'%s/copia.txt'"'"'"}}' "$(esc "$R")" "$(esc "$R")" "$(esc "$R")")"
gate "mv para FORA do worktree"                      2 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"mv '"'"'%s/a.txt'"'"' '"'"'%s/renomeado.txt'"'"'"}}' "$(esc "$R")" "$(esc "$R")" "$(esc "$R")")"
gate "criar .rainforest-gate-off (escape file)"      2 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"echo 1 > '"'"'%s/.rainforest-gate-off'"'"'"}}' "$(esc "$R")" "$(esc "$R")")"

echo
echo "== redirecionamento e escrita DENTRO do worktree PASSA =="
gate "echo para arquivo dentro do worktree"          0 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"echo x > '"'"'%s/novo.txt'"'"'"}}' "$(esc "$WT")" "$(esc "$WT")")"
gate "echo >> append dentro do worktree"             0 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"echo x >> '"'"'%s/novo.txt'"'"'"}}' "$(esc "$WT")" "$(esc "$WT")")"
gate "tee dentro do worktree"                        0 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"echo x | tee '"'"'%s/novo.txt'"'"'"}}' "$(esc "$WT")" "$(esc "$WT")")"
gate "sed -i dentro do worktree"                     0 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"sed -i '"'"'s/x/y/'"'"' '"'"'%s/a.txt'"'"'"}}' "$(esc "$WT")" "$(esc "$WT")")"
gate "cp dentro do worktree"                         0 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"cp '"'"'%s/a.txt'"'"' '"'"'%s/copia.txt'"'"'"}}' "$(esc "$WT")" "$(esc "$WT")" "$(esc "$WT")")"
gate "mv dentro do worktree"                         0 "$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"mv '"'"'%s/a.txt'"'"' '"'"'%s/renomeado.txt'"'"'"}}' "$(esc "$WT")" "$(esc "$WT")" "$(esc "$WT")")"

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

echo
echo "== mutacao: prova que a inspeção funciona (Issue #88) =="
# MUTACAO CIRURGICA, e o "cirurgica" e o ponto todo.
#
# A primeira versao desta secao fazia `sed '/alvosBashEscrita/d'`, que apaga TAMBEM
# a linha da declaracao da funcao e deixa um `{` orfao: o mutante nao compilava.
# `node --check` acusava SyntaxError, o processo morria com exit 1, e a assercao
# `[ "$rc" != "0" ]` creditava `ok` — por CRASH, nao por protecao removida. E o
# mesmo modo de falha que o comentario do testa-contexto-sessao.sh ja documenta:
# mutante que nao roda faz a bateria passar verde sem ter medido nada.
#
# Aqui a mutacao troca o CORPO da funcao por `return []` — JS valido, funcao viva,
# protecao neutralizada. E a assercao inverte: o mutante tem de sair com exit 0
# (deixou passar). Exit != 0 agora e FALHA, porque so pode significar crash.
GATE_MUTADO="$RAIZ/gate-sem-escrita.cjs"
node -e '
const fs = require("fs");
let t = fs.readFileSync(process.argv[1], "utf8");
const achar = "function alvosBashEscrita(comando, cwdInicial) {";
if (!t.includes(achar)) { console.error("ANCORA NAO BATE"); process.exit(1); }
t = t.replace(achar, achar + "\n  return [];");
fs.writeFileSync(process.argv[2], t);
' "$GATE" "$GATE_MUTADO"
if ! node --check "$GATE_MUTADO" 2>/dev/null; then
  falhou=$((falhou+1)); echo "  FALHA mutante nao compila — a secao mediria crash, nao protecao"
else
  saida=$(printf '{"agent_id":"ag-1","tool_name":"Bash","cwd":"%s","tool_input":{"command":"echo x > '"'"'%s/novo.txt'"'"'"}}' "$(esc "$R")" "$(esc "$R")" | node "$GATE_MUTADO" 2>&1); rc=$?
  if [ "$rc" = "0" ]; then ok=$((ok+1)); echo "  ok   mutacao expos a inspecao: com alvosBashEscrita neutralizada, a escrita fora PASSA"
  else falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito ou mutante quebrado (exit $rc): $saida"; fi
fi

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
echo
echo "== o til: expansao de home so no COMECO, e caminho 8.3 tem til no meio =="
# Achado pelo CI em 2026-08-17 (Issue #16): o TEMP do runner do GitHub e
# `C:/Users/RUNNER~1/...` na forma 8.3. O teste de `cd` nao-resolvivel era
# /[$`~]/, que casa com til em QUALQUER posicao — entao `cd <worktree>` num
# caminho 8.3 virava INCERTO, o conservadorismo somava o cwd principal aos alvos,
# e o gate BARRAVA um commit legitimo dentro do worktree. Vermelho la, verde aqui,
# porque `C:/Users/Luis` nao tem alias 8.3.
#
# Aqui a condicao se reproduz sem depender do 8.3 do SO: uma pasta chamada
# literalmente `RUNNER~1`. Os dois lados sao testados de proposito — sem o par,
# "resolveu o til" e indistinguivel de "parou de barrar til nenhum".
TIL="$RAIZ_POSIX/RUNNER~1"; mkdir -p "$TIL"
RT="$TIL/principal"
git init -q "$RT"; git -C "$RT" config user.email t@t; git -C "$RT" config user.name t
git -C "$RT" config commit.gpgsign false
echo v1 > "$RT/a.txt"; git -C "$RT" add .; git -C "$RT" commit -qm base
WTT="$TIL/wt"; git -C "$RT" worktree add -q -b trabalho-til "$WTT" >/dev/null 2>&1
RTW="$(cygpath -m "$RT" 2>/dev/null || printf '%s' "$RT")"
WTTW="$(cygpath -m "$WTT" 2>/dev/null || printf '%s' "$WTT")"
bt() { printf '{"agent_id":"ag-1","agent_type":"executor","tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' \
  "$(esc "$2")" "$(esc "$1")"; }

gate "til NO MEIO (8.3): cd worktree && git commit PASSA" 0 \
  "$(bt "cd $WTTW && git commit -m x" "$RTW")"
gate "til no meio: cd principal && git commit ainda BARRA" 2 \
  "$(bt "cd $RTW && git commit -m x" "$RTW")"

# O outro lado da moeda: til no COMECO continua sendo expansao de home, e
# continua incerto. Se este par ficar verde com o anterior, a correcao e a certa;
# se `cd ~` passar a nao barrar, o conserto virou buraco.
gate "til no COMECO (cd ~) segue INCERTO e barra" 2 \
  "$(bt "cd ~ && git commit -m x" "$RTW")"
gate "til no COMECO (cd ~/algo) segue INCERTO e barra" 2 \
  "$(bt "cd ~/algo && git commit -m x" "$RTW")"

echo
echo
echo "== sessao co-locada: a UNICA condicao que barra a janela principal =="
# O INCIDENTE (2026-08-21, Issues #25 e #38, 11 registros do acervo): duas janelas do
# Claude Code abertas no MESMO diretorio. Um `git checkout -b` numa delas arrancou a
# outra da branch em que ela trabalhava, e ela commitou tres vezes na branch alheia sem
# perceber. HEAD e do CHECKOUT, nao da janela.
#
# Este bloco e o mais perigoso da bateria inteira, e por isso os casos que devem PASSAR
# sao a maioria de novo: ate hoje o gate NUNCA barrava a janela principal, e todo falso
# positivo aqui trava quem esta sozinho no repo. Cada saida de emergencia tem caso
# proprio — a que nao for testada e a que vai estar quebrada no dia do incidente.
DADOS="$RAIZ_POSIX/dados"; mkdir -p "$DADOS"; : > "$DADOS/FOCO.md"
DADOSW="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"
export SESSOES="$DADOSW/sessoes.json"
EU="11111111-1111-1111-1111-111111111111"
OUTRA="22222222-2222-2222-2222-222222222222"

# cada argumento e "id|cwd|minutos_desde_o_prompt|minutos_desde_o_stop".
# O fixture e proprio, e nao o `sessoes.json` real do usuario, porque o real muda a
# cada heartbeat: bateria que le dado vivo passa por sorte e falha por sorte.
monta_sessoes() {
  node -e '
    const fs = require("fs"), agora = Date.now(), estado = {};
    for (const arg of process.argv.slice(1)) {
      const [id, cwd, p, s] = arg.split("|");
      estado[id] = { cwd, prompt_ts: agora - Number(p) * 60000, stop_ts: agora - Number(s) * 60000 };
    }
    fs.writeFileSync(process.env.SESSOES, JSON.stringify(estado, null, 2));
  ' "$@"
}

# Igual ao `gate()`, mas apontando a raiz de DADOS para a caixa de areia. RFM_ROOT e o
# nivel 1 da cadeia do raiz.cjs e vence tudo, entao a trava le o fixture daqui e nao o
# `~/.rainforest/sessoes.json` da maquina de quem roda a bateria.
gatec() { # nome, exit esperado, json
  local nome="$1" esp="$2" json="$3"
  local saida; saida=$(printf '%s' "$json" | RFM_ROOT="$DADOSW" node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; fi
}

# Payload no formato REAL do harness para a janela principal: tem `session_id`, NAO tem
# `agent_id`. Testar com `agent_id` provaria o gate velho e nao este.
p() { # comando, cwd, [session_id]
  printf '{"session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' \
    "${3:-$EU}" "$(esc "$2")" "$(esc "$1")"
}

monta_sessoes "$EU|$(esc "$R")|1|1" "$OUTRA|$(esc "$R")|15|2" \
  "so-eu|$(esc "$WT")|1|1" "outra-pasta|$(esc "$FORA")|1|1"

echo "-- deve BARRAR (exit 2) --"
gatec "checkout -b com outra sessao no mesmo cwd" 2 "$(p "git checkout -b x" "$R")"
gatec "checkout de branch existente idem"         2 "$(p "git checkout main" "$R")"
gatec "switch -c idem (o verbo novo do mesmo ato)" 2 "$(p "git switch -c x" "$R")"
# A outra sessao esta PARADA (stop_ts mais recente que prompt_ts) e continua dona: em
# 2026-08-21 o usuario pausou a outra janela e ela seguiu dona da branch. Uma janela
# curta de vivacidade teria liberado o checkout exatamente no momento em que ele doia.
gatec "a outra sessao PARADA ha 2 min ainda barra" 2 "$(p "git checkout -b x" "$R")"

echo "-- deve PASSAR (exit 0) — cada um destes travaria quem esta certo --"
# D2: so os verbos que movem o HEAD (VERBOS_QUE_MOVEM). Barrar o VERBOS_QUE_MEXEM
# inteiro barraria as duas sessoes simetricamente, inclusive a DONA legitima da
# branch, que so quer commitar no trabalho dela.
gatec "commit no mesmo cwd co-locado"             0 "$(p "git commit -m x" "$R")"
gatec "merge no mesmo cwd co-locado"              0 "$(p "git merge outra" "$R")"
gatec "rebase no mesmo cwd co-locado"             0 "$(p "git rebase main" "$R")"
gatec "reset no mesmo cwd co-locado"              0 "$(p "git reset --soft HEAD~1" "$R")"
gatec "git status (leitura) no cwd co-locado"     0 "$(p "git status --porcelain" "$R")"
# A saida que a propria mensagem de bloqueio recomenda nao pode ser barrada por ela.
gatec "cd worktree && checkout -b (a saida recomendada)" 0 "$(p "cd $WT && git checkout -b y" "$R")"
gatec "cwd sem entrada nenhuma no sessoes.json"   0 "$(p "git checkout -b y" "$RTW")"
# ...mas duas janelas DENTRO do mesmo worktree se atrapalham igual: a medida e o `cwd`,
# nao o repositorio (D1). O que o worktree resolve e nao compartilhar o checkout.
gatec "duas sessoes no MESMO worktree tambem barra" 2 "$(p "git checkout -b y" "$WT")"
# A entrada existe e e a MINHA — o gate se exclui pelo `session_id` do evento (D5).
# Testar so o cwd sem entrada nenhuma nao provaria a exclusao: a lista viria vazia
# pelos dois motivos ao mesmo tempo, e a trava barraria quem esta sozinho.
gatec "sozinho no cwd (a unica entrada sou eu)"   0 "$(p "git checkout -b x" "$WT" "so-eu")"

monta_sessoes "$EU|$(esc "$R")|1|1" "$OUTRA|$(esc "$R")|15|2"
# Fail-open, um caso por motivo. Sem session_id a trava nao distingue quem pergunta de
# quem esta la — as duas entradas do incidente tinham `cwd` identico (D5).
gatec "sem session_id no evento (fail-open)"      0 \
  "$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"git checkout -b x"}}' "$(esc "$R")")"
gatec "cwd fora de repo git nao tem HEAD a mover" 0 "$(p "git checkout -b x" "$FORA")"

echo "-- deve PASSAR: as tres saidas de emergencia, no caso que barraria --"
saida=$(printf '%s' "$(p "git checkout -b x" "$R")" | RFM_ROOT="$DADOSW" RAINFOREST_GATE_OFF=1 node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   RAINFOREST_GATE_OFF=1 libera a co-locada (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA RAINFOREST_GATE_OFF nao liberou a co-locada (exit $rc)"; fi

touch "$R/.rainforest-gate-off"
gatec ".rainforest-gate-off libera a co-locada"   0 "$(p "git checkout -b x" "$R")"
rm "$R/.rainforest-gate-off"
# O toggle do setup e o motivo pelo qual as saidas de emergencia subiram para antes do
# `if (!ev.agent_id)`: enquanto elas ficavam depois, a janela principal saia do hook
# antes de o config ser sequer lido, e `--desligar gate-worktree` nao desligaria o unico
# ramo que barra a janela principal — que e o ramo em que desligar mais importa.
mkdir -p "$R/.rainforest"; printf '{"gate-worktree": false}' > "$R/.rainforest/config.json"
gatec "toggle do config (projeto) libera a co-locada" 0 "$(p "git checkout -b x" "$R")"
rm -rf "$R/.rainforest"
gatec "  ... e volta a barrar quando o toggle sai"    2 "$(p "git checkout -b x" "$R")"

echo "-- deve PASSAR: fail-open quando a trava nao consegue MEDIR --"
mv "$DADOS/sessoes.json" "$DADOS/sessoes.bak"
gatec "sessoes.json ausente (fail-open)"          0 "$(p "git checkout -b x" "$R")"
printf 'isto nao e json' > "$DADOS/sessoes.json"
gatec "sessoes.json ilegivel (fail-open)"         0 "$(p "git checkout -b x" "$R")"
mv "$DADOS/sessoes.bak" "$DADOS/sessoes.json"
saida=$(printf '%s' "$(p "git checkout -b x" "$R")" | RFM_ROOT="$RAIZ/nao-existe" node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   raiz de dados sem sessoes.json (fail-open, exit 0)"
else falhou=$((falhou+1)); echo "  FALHA raiz inexistente nao liberou (exit $rc)"; fi

# Janela de 4h: a entrada velha deixa de ser dona. O par com o caso "parada ha 2 min"
# la em cima e o que separa "a janela e longa" de "a janela nao existe" — sem os dois,
# uma trava que ignora o tempo por completo ficaria verde.
monta_sessoes "$EU|$(esc "$R")|1|1" "$OUTRA|$(esc "$R")|300|300"
gatec "a outra sessao sumiu ha 5h: nao e mais dona" 0 "$(p "git checkout -b x" "$R")"
# Worktree de subagente e rastro MEU, nao janela dele — mesmo motivo pelo qual ela ja
# sai do radar da regra 17.
monta_sessoes "$EU|$(esc "$R")|1|1" "$OUTRA|$(esc "$R")/.claude/worktrees/agent-abc|1|1"
gatec "worktree de subagente nao conta como co-locada" 0 "$(p "git checkout -b x" "$R")"

echo "-- o comportamento antigo com agent_id fica intacto --"
monta_sessoes "$EU|$(esc "$R")|1|1" "$OUTRA|$(esc "$R")|1|1"
gatec "subagente no worktree dele segue passando" 0 \
  "$(printf '{"session_id":"%s","agent_id":"ag-1","agent_type":"executor","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git checkout -b y"}}' "$EU" "$(esc "$WT")")"
gatec "subagente no principal segue barrado"      2 \
  "$(printf '{"session_id":"%s","agent_id":"ag-1","agent_type":"executor","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git checkout -b y"}}' "$EU" "$(esc "$R")")"

echo "-- a mensagem oferece a saida certa --"
msgc=$(printf '%s' "$(p "git checkout -b x" "$R")" | RFM_ROOT="$DADOSW" node "$GATE" 2>&1)
for t in "git worktree add" "$OUTRA" "checkout"; do
  if printf '%s' "$msgc" | grep -q -- "$t"; then ok=$((ok+1)); echo "  ok   a mensagem diz '$t'"
  else falhou=$((falhou+1)); echo "  FALHA a mensagem nao diz '$t'"; fi
done
# A escotilha APARECE aqui, ao contrario da mensagem ao subagente. O P1 de 2026-08-11 e
# sobre autoridade: quem le esta mensagem e a janela principal, que e quem decide.
if printf '%s' "$msgc" | grep -q -- "RAINFOREST_GATE_OFF"; then
  ok=$((ok+1)); echo "  ok   e nomeia a escotilha para quem TEM autoridade de usa-la"
else
  falhou=$((falhou+1)); echo "  FALHA nao diz a janela principal como seguir"
fi

echo
echo "== casos do conserto da âncora: checkout/switch na posição certa =="
# A âncora antiga casava "checkout"/"switch" em QUALQUER lugar do comando e barrava
# `git commit -m "checkout later"`. A segunda tentativa exigia nome sem ponto nem
# barra — e deixou passar `git checkout agente/t7`, que e o comando do incidente.
#
# A que vale reconhece a posição de subcomando (aspas nao viram argumento) e decide
# HEAD-moving vs file-restore pelo DISCO: caminho existe, ref nao. `$R/a.txt` existe
# desde a linha 36, e e o que faz o caso do `checkout a.txt` significar alguma coisa.
# O que sobra ambiguo BARRA — barrar errado custa uma mensagem, passar errado custa
# o HEAD da outra sessao.
#
# Testam a trava de sessao co-locada (`moveOHead`), nao a write-protect.

monta_sessoes "$EU|$(esc "$R")|1|1" "$OUTRA|$(esc "$R")|15|2"

gatec "commit com 'checkout' na mensagem PASSA"    0 "$(p "git commit -m \"checkout later\"" "$R")"
gatec "commit com 'switch' na mensagem PASSA"      0 "$(p "git commit -m \"add login switch\"" "$R")"
gatec "checkout -- arquivo PASSA (nao move HEAD)"  0 "$(p "git checkout -- a.txt" "$R")"
gatec "checkout de caminho PASSA (ambiguo)"        0 "$(p "git checkout a.txt" "$R")"
gatec "log --grep=checkout PASSA (nao e subcomando)" 0 "$(p "git log --grep=checkout" "$R")"

gatec "status PASSA (nem e verbo que move)"        0 "$(p "git status" "$R")"
gatec "checkout HEAD -- arquivo PASSA"             0 "$(p "git checkout HEAD -- a.txt" "$R")"
gatec "checkout -p PASSA (restaura em pedaco)"     0 "$(p "git checkout -p" "$R")"

gatec "checkout -b nova BARRA (cria branch)"       2 "$(p "git checkout -b nova" "$R")"
gatec "switch -c nova BARRA (cria branch)"         2 "$(p "git switch -c nova" "$R")"
gatec "checkout main BARRA (move HEAD)"            2 "$(p "git checkout main" "$R")"
gatec "co -b nova BARRA (alias, cria branch)"      2 "$(p "git co -b nova" "$R")"

# Os SEIS buracos que a segunda tentativa deixou passar. O primeiro e o comando
# literal do incidente de 2026-08-21: branch com barra tem a mesma cara de caminho,
# e so o disco desempata.
gatec "checkout agente/t7 BARRA (branch com barra)" 2 "$(p "git checkout agente/t7" "$R")"
gatec "switch feature/login BARRA"                  2 "$(p "git switch feature/login" "$R")"
gatec "checkout origin/main BARRA (ref remota)"     2 "$(p "git checkout origin/main" "$R")"
gatec "checkout v1.0 BARRA (tag tem ponto)"         2 "$(p "git checkout v1.0" "$R")"
gatec "--no-pager checkout -b BARRA (opcao global)" 2 "$(p "git --no-pager checkout -b nova" "$R")"
gatec "checkout @{-1} BARRA (branch anterior)"      2 "$(p "git checkout @{-1}" "$R")"

# E os que so a decisao por disco resolve.
gatec "checkout de caminho inexistente BARRA"       2 "$(p "git checkout nao-existe.txt" "$R")"
gatec "switch pelado BARRA (o git decide, nos nao)" 2 "$(p "git switch" "$R")"
gatec "-C com valor nao vira subcomando"            2 "$(p "git -c core.pager=cat switch main" "$R")"
gatec "checkout no fim de encadeamento BARRA"       2 "$(p "git status && git checkout main" "$R")"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
