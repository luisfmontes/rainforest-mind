#!/bin/bash
# Bateria do gate-staging-total.cjs. Monta repo e worktree git de verdade e
# alimenta o hook com payloads reais de PreToolUse, conferindo o exit code.
# Uso: bash hooks/testa-gate-staging-total.sh
#
# O que esta bateria precisa provar, nesta ordem:
#   1. que BARRA o caso dos dois incidentes (exit 2) — inclusive vindo da
#      JANELA PRINCIPAL, que e o oposto do gate-worktree e o ponto todo daqui;
#   2. que a mensagem MOSTRA o arquivo que seria varrido — trava que so diz
#      "nao" vira trava desligada, entao a ajuda faz parte do mecanismo e
#      precisa ser observada funcionando, nao presumida;
#   3. que NAO barra staging por caminho, leitura, worktree, nem
#      `git commit -m "suporte a add -A"` — falso positivo aqui atrapalha o
#      o usuario em todos os repos, entao os casos que devem PASSAR sao a maioria.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SRC/hooks/gate-staging-total.cjs"
# Caminho NATIVO, nao o /tmp/... do Git Bash: o Node no Windows nao resolve
# caminho MSYS, o git falha e o gate libera — a bateria passaria verde
# testando nada. Custou uma rodada inteira em 2026-08-09.
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

# Issue #160: a bateria lia a config REAL de quem a roda — quem desligou um gate
# no escopo usuario pelo `/setup` via a suite vermelha sem pista da causa. A raiz
# de dados passa a ser uma pasta descartavel, como faz o `testa-orcamento.sh`
# (Issue #81). Caso que precisa de outra raiz sobrescreve por chamada.
export RFM_ROOT="$RAIZ/dados-neutros"; mkdir -p "$RFM_ROOT"

ok=0; falhou=0
gate() { # nome, exit esperado, json
  local nome="$1" esp="$2" json="$3"
  local saida; saida=$(printf '%s' "$json" | node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; fi
}

R="$RAIZ/principal"
git init -q "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
echo v1 > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm base
WT="$RAIZ/wt"; git -C "$R" worktree add -q -b trabalho "$WT" >/dev/null 2>&1
FORA="$RAIZ/sem-git"; mkdir -p "$FORA"
# Tarefa 2 (Rev3): um segundo repositorio de VERDADE (nao `git worktree add` —
# esse tem gitDir com "/worktrees/" e o gate o ignora de proposito, linha
# "so o dono escreve la"). Simula o worktree do fluxo: repo proprio, raiz
# diferente da do evento, para provar que a mensagem cita o caminho EFETIVO.
WT2="$RAIZ/wt-fluxo"; git init -q "$WT2"
git -C "$WT2" config user.email t@t; git -C "$WT2" config user.name t
git -C "$WT2" config commit.gpgsign false
echo v1 > "$WT2/a.txt"; git -C "$WT2" add a.txt; git -C "$WT2" commit -qm base
mkdir -p "$R/sub"  # Tarefa 2: criar subdir para teste de cd efetivo

esc() { printf '%s' "$1" | sed 's|\\|/|g'; }
# payload da JANELA PRINCIPAL (sem agent_id) — o caso dos dois incidentes
b() { printf '{"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "${2:-$(esc "$R")}" "$1"; }
# payload de SUBAGENTE
ba() { printf '{"agent_id":"ag-1","agent_type":"executor","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "${2:-$(esc "$R")}" "$1"; }

echo "== deve BARRAR (exit 2) — inclusive na janela principal =="
gate "JANELA PRINCIPAL: git add -A (incidente 1 e 2)" 2 "$(b 'git add -A')"
gate "JANELA PRINCIPAL: git add --all"                2 "$(b 'git add --all')"
gate "JANELA PRINCIPAL: git add ."                    2 "$(b 'git add .')"
gate "git add :/"                                     2 "$(b 'git add :/')"
gate "git add -- ."                                   2 "$(b 'git add -- .')"
gate "git add -u"                                     2 "$(b 'git add -u')"
gate "git commit -a"                                  2 "$(b 'git commit -a')"
gate "git commit -am (flag combinada)"                2 "$(b 'git commit -am mensagem')"
gate "git commit --all"                               2 "$(b 'git commit --all')"
gate "encadeado: cd x && git add -A"                  2 "$(b 'cd sub && git add -A')"
gate "git -C <repo> add -A (cwd em outro lugar)"      2 "$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"git -C %s add -A"}}' "$(esc "$FORA")" "$(esc "$R")")"
gate "SUBAGENTE: git add -A no principal"             2 "$(ba 'git add -A')"
gate "D2: cd <worktree> && git add -A (cwd no principal, WT limpo)" 0 "$(b 'cd '"$(esc "$WT")"' && git add -A' "$(esc "$R")")"

echo
echo "== a ajuda faz parte do mecanismo: a mensagem MOSTRA o que varreria? =="
# Envenena a caixa de areia com o caso real: arquivo de "outra sessao", nao rastreado.
mkdir -p "$R/relatorios"
echo "relatorio de outra janela" > "$R/relatorios/2026-08-09-de-outra-sessao.md"
# E um arquivo RASTREADO modificado, que sai como ' M a.txt' — duas colunas de
# status, espaco a esquerda. Precisa vir ANTES na ordem do git para ocupar a
# primeira linha: era exatamente essa linha que o .trim() mutilava, e a bateria
# passou verde sem ela porque so tinha '??' (sem espaco a esquerda) na caixa.
echo v2 >> "$R/a.txt"
msg=$(printf '%s' "$(b 'git add -A')" | node "$GATE" 2>&1)
for t in "relatorios/2026-08-09-de-outra-sessao.md" "git status --porcelain" "Adicione por caminho" "RAINFOREST_GATE_OFF" ".rainforest-gate-off"; do
  if printf '%s' "$msg" | grep -qF -- "$t"; then ok=$((ok+1)); echo "  ok   a mensagem mostra '$t'"
  else falhou=$((falhou+1)); echo "  FALHA a mensagem NAO mostra '$t'"; fi
done
# e o comando pronto tem que vir com o caminho citado, colavel
if printf '%s' "$msg" | grep -qF -- 'git add "a.txt" "relatorios/2026-08-09-de-outra-sessao.md"'; then
  ok=$((ok+1)); echo "  ok   a mensagem monta o 'git add' por caminho, colavel"
else falhou=$((falhou+1)); echo "  FALHA a mensagem nao monta o comando por caminho"
  printf '%s' "$msg" | grep -F 'git add "' | sed 's/^/         /'; fi
# regressao do ' M ': a PRIMEIRA linha nao pode perder a primeira letra
if printf '%s' "$msg" | grep -qF -- '".txt"'; then
  falhou=$((falhou+1)); echo "  FALHA primeira linha mutilada: caminho saiu como '.txt'"
else ok=$((ok+1)); echo "  ok   primeira linha do porcelain (' M a.txt') sai inteira"; fi

echo
echo "== deve PASSAR (exit 0) — falso positivo aqui atrapalha todo repo do usuario =="
gate "git add por caminho"                        0 "$(b 'git add relatorios/foo.md')"
gate "git add dois caminhos citados"              0 "$(b 'git add \"a.txt\" \"b.txt\"')"
gate "git add ./caminho/arquivo.md"               0 "$(b 'git add ./relatorios/foo.md')"
gate "git commit -m com 'add -A' no TEXTO"        0 "$(b 'git commit -m \"suporte a add -A\"')"
gate "git commit -m normal"                       0 "$(b 'git commit -m mensagem')"
gate "git commit --amend --no-edit"               0 "$(b 'git commit --amend --no-edit')"
gate "git status"                                 0 "$(b 'git status --porcelain')"
gate "git log"                                    0 "$(b 'git log --oneline -5')"
gate "git diff"                                   0 "$(b 'git diff --stat')"
gate "git stash push -u (nao e staging)"          0 "$(b 'git stash push -u')"
gate "ls -la"                                     0 "$(b 'ls -la')"
gate "git add -A DENTRO de worktree linkado"      0 "$(ba 'git add -A' "$(esc "$WT")")"
gate "git add -A fora de repo git"                0 "$(b 'git add -A' "$(esc "$FORA")")"
gate "ferramenta que nao e Bash (Write)"          0 "$(printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$(esc "$R")" "$(esc "$R/x.txt")")"
gate "payload vazio nunca trava"                  0 "{}"
gate "payload ilegivel nunca trava"               0 "isto nao e json"

echo
echo "== Tarefa 2 (Rev3): a mensagem de bloqueio cita o caminho EFETIVO lido, nao o cwd do evento =="
msg2=$(printf '%s' "$(b 'cd '"$(esc "$WT2")"' && git add -A' "$(esc "$R")")" | node "$GATE" 2>&1); rc2=$?
if [ "$rc2" = 2 ]; then ok=$((ok+1)); echo "  ok   cd <worktree-do-fluxo> && git add -A (cwd no principal) barra (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA esperava exit 2, veio $rc2"; printf '%s' "$msg2" | sed 's/^/         /' | head -8; fi
if printf '%s' "$msg2" | grep -qF -- "$WT2"; then
  ok=$((ok+1)); echo "  ok   stderr cita o caminho do worktree EFETIVO ($WT2)"
else
  falhou=$((falhou+1)); echo "  FALHA stderr NAO cita o caminho efetivo"
  printf '%s' "$msg2" | sed 's/^/         /' | head -8
fi
if printf '%s' "$msg2" | grep -qF -- "Repo: $R"; then
  falhou=$((falhou+1)); echo "  FALHA stderr cita o cwd do EVENTO ($R) como Repo, em vez do efetivo"
else
  ok=$((ok+1)); echo "  ok   stderr NAO cita o cwd do evento como Repo"
fi

echo
echo "== H1 (rodada 5): cwd do SEGMENTO onde o verbo aparece, nao o cwd final da linha =="
# Ate aqui o cwd efetivo era o da linha INTEIRA: `git add -A && cd <worktree>`
# fazia o `add` de verdade no principal, mas o cwd apos o `cd` caia no
# worktree, e o gate liberava lendo o lugar errado.
gate "git add -A && cd <worktree> no principal BARRA (H1)" 2 "$(b 'git add -A && cd '"$(esc "$WT")")"
gate "cd <worktree> && git add -A no principal PASSA (regressao)" 0 "$(b 'cd '"$(esc "$WT")"' && git add -A')"

echo
echo "== K1/K2 do auditor (rodada 6, lote 3, 2026-09-03): '&' simples e git por posicao =="
# K1: 'echo hi' rodava em background e o '&' nao separava segmento em lugar
# nenhum — o 'git add -A' ficava escondido no MESMO segmento opaco.
gate "echo hi & git add -A na JANELA PRINCIPAL BARRA (K1)" 2 "$(b 'echo hi & git add -A')"
# K2: '-C 3' e o CONTEXTO do grep, nada a ver com git — regressao a evitar e
# o segmento do grep virar 'incerto' ou mudar de cwd so por ter '-C' no texto,
# o que faria o 'git add -A' seguinte escapar da deteccao.
gate "grep -rn -C 3 \"gitignore\" . && git add -A na JANELA PRINCIPAL BARRA (K2)" 2 "$(b 'grep -rn -C 3 \"gitignore\" . && git add -A')"
gate "git add -A 2>&1 DENTRO de worktree PASSA (K1, 2>&1 nao e separador)" 0 "$(ba 'git add -A 2>&1' "$(esc "$WT")")"

echo
echo "== M1 (auditor, 5a revisao, 2026-09-03): git por POSICAO DE COMANDO, nao so PREFIXO_NEUTRO de token unico =="
# Antes disto o tokenizador so pulava o wrapper como token UNICO: parava na
# flag dele (`-C`, `-u`, o valor de `env FOO=1`) e nunca via o 'git' depois —
# o 'git add -A' passava sem checagem, o incidente de 2026-08-09 de novo.
gate "env -C . git add -A na JANELA PRINCIPAL BARRA (M1)"          2 "$(b 'env -C . git add -A')"
gate "sudo -u x git add -A na JANELA PRINCIPAL BARRA (M1)"         2 "$(b 'sudo -u x git add -A')"
gate "env FOO=1 git add -A na JANELA PRINCIPAL BARRA (M1)"         2 "$(b 'env FOO=1 git add -A')"
gate "nice -n 5 git add -A na JANELA PRINCIPAL BARRA (M1)"         2 "$(b 'nice -n 5 git add -A')"
# regressao do cwd efetivo: o -C do proprio env manda, e aponta pro worktree
# linkado (dono escreve la, gate libera) mesmo com cwd do evento no principal.
gate "env -C <worktree> git add -A com cwd no principal PASSA (M1, -C do env manda)" 0 "$(b 'env -C '"$(esc "$WT")"' git add -A')"
# 'git' ali e ARGUMENTO do grep (padrao de busca), nunca comando — nao e git.
gate "env -C . grep git . NAO e git (M1)"                          0 "$(b 'env -C . grep git .')"

echo
echo "== P1/P5 (rodada 8, lote 3, 2026-09-04): mais flags de env/sudo, e cd via wrapper =="
# P1: 'env -u'/'sudo -E' ainda paravam a busca na PROPRIA flag (so -C/--chdir
# e -u/-g/--user/--group de sudo eram conhecidas) — 'git add -A' escapava.
gate "env -u OneDrive git add -A na JANELA PRINCIPAL BARRA (P1)" 2 "$(b 'env -u OneDrive git add -A')"
gate "env -i git add -A na JANELA PRINCIPAL BARRA (P1)"          2 "$(b 'env -i git add -A')"
gate "sudo -E git add -A na JANELA PRINCIPAL BARRA (P1)"         2 "$(b 'sudo -E git add -A')"
# P5: '\cd' (escapa alias/funcao) nao casava com o CD ancorado no inicio do
# segmento — o cwd efetivo ficava preso no worktree, e o 'git add -A' que de
# verdade rodava no PRINCIPAL escapava do gate. `b`/`ba` rodam o comando por
# `esc` (troca toda barra invertida por barra normal, pensado pra caminho
# Windows) — usa `node -e` direto aqui para o `\cd` chegar intacto no JSON.
saidaP5=$(MSYS_NO_PATHCONV=1 node -e 'const [c,d]=process.argv.slice(1);process.stdout.write(JSON.stringify({agent_id:"ag-1",agent_type:"executor",cwd:d,tool_name:"Bash",tool_input:{command:c}}))' "\\cd $R && git add -A" "$WT" | node "$GATE" 2>&1); rcP5=$?
if [ "$rcP5" = 2 ]; then ok=$((ok+1)); echo "  ok   SUBAGENTE: \\cd <principal> && git add -A, do worktree BARRA (P5) (exit 2)"
else falhou=$((falhou+1)); echo "  FALHA \\cd <principal> && git add -A do worktree: esperava 2, veio $rcP5"; printf '%s' "$saidaP5" | sed 's/^/         /' | head -8; fi

echo
echo "== saidas de emergencia =="
saida=$(printf '%s' "$(b 'git add -A')" | RAINFOREST_GATE_OFF=1 node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   RAINFOREST_GATE_OFF=1 libera (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA RAINFOREST_GATE_OFF nao liberou (exit $rc)"; fi

touch "$R/.rainforest-gate-off"
gate ".rainforest-gate-off na raiz libera o repo"   0 "$(b 'git add -A')"
rm "$R/.rainforest-gate-off"
gate "  ... e volta a barrar quando o arquivo sai"  2 "$(b 'git add -A')"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
