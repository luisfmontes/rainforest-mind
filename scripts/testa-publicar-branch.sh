#!/bin/bash
# Bateria do scripts/publicar-branch.cjs — o publicar conferido do `fechar`.
# Uso: bash scripts/testa-publicar-branch.sh
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR. O passo 5 do `fechar` era prosa, e a
# sessão declarava "pushado" e "mergeado" pelo texto do CLI. O script só vale se
# disser NAO nos casos em que a prosa dizia SIM:
#
#   1. empurrar sobre uma base que andou com conflito — o push sai sem aviso e a
#      branch chega no remoto quebrada (casos b e d);
#   2. declarar o push feito quando o remoto recusou ou divergiu (caso e);
#   3. mergear sem autorização, ou dar o merge por feito pela linha do CLI (casos g
#      e h).
#
# Remoto de teste: um repositório bare local. O `origin` do repo-caixa tem URL
# GitHub, reescrita por `url.<bare>.insteadOf` — por isso o `remote.origin.url`
# declara github.com e o push vai para o bare. O `gh` é um stub; a bateria nunca
# chama o gh real. A raiz de dados é isolada (RFM_ROOT), para a config do usuário
# não contaminar o resultado.

# Git herdado do ambiente (GIT_DIR, GIT_INDEX_FILE...) desviaria as operações
# para outro repositório. Limpa antes de qualquer comando git.
unset $(env | grep -o '^GIT_[A-Z_]*') 2>/dev/null

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/publicar-branch.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }

ok=0; falhou=0
afirma() { # nome, status (0 = passou)
  if [ "$2" -eq 0 ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1"; fi
}

S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
CAIXA="$S/caixa"; BARE="$S/remoto.git"; BASEWC="$S/base-wc"
DADOS="$S/dados"; SAIDA="$S/saida.txt"; ERRO="$S/erro.txt"; BIN="$S/bin"
mkdir -p "$DADOS" "$BIN"
BARE_W="$(cygpath -m "$BARE" 2>/dev/null || printf '%s' "$BARE")"

# ----------------------------------------------------- stub de gh (caminho POSIX)
# `gh` (shell) para `command -v gh`; `gh.cmd` + `gh-stub.js` para o resolver do
# repo, que no Windows só acha .cmd/.exe. Mesmo padrao de scripts/testa-fechar-issue.sh.
cat > "$BIN/gh" <<'STUB'
#!/bin/bash
exec node "$(dirname "$0")/gh-stub.js" "$@"
STUB
chmod +x "$BIN/gh"
cat > "$BIN/gh.cmd" <<'STUB'
@node "%~dp0gh-stub.js" %*
STUB
cat > "$BIN/gh-stub.js" <<'STUB'
const fs = require('fs');
const args = process.argv.slice(2);
if (process.env.STUB_LOG) fs.appendFileSync(process.env.STUB_LOG, 'CHAMADA: gh ' + args.join(' ') + '\n');
if (args[0] === 'auth') process.exit(process.env.STUB_AUTH_FAIL ? 1 : 0);
if (args[0] === 'pr' && args[1] === 'list') {
  process.stdout.write((process.env.STUB_PR === undefined ? '' : process.env.STUB_PR) + '\n');
  process.exit(0);
}
if (args[0] === 'pr' && args[1] === 'checks' && args.includes('--json')) {
  process.stdout.write((process.env.STUB_CHECKS_JSON || '[{"name":"baterias","bucket":"pass"}]') + '\n');
  process.exit(0);
}
if (args[0] === 'pr' && args[1] === 'checks') process.exit(Number(process.env.STUB_CHECKS_EXIT || 0));
if (args[0] === 'api' && String(args[1]).includes('actions/workflows')) {
  if (process.env.STUB_API_FAIL) { process.stderr.write('HTTP 502\n'); process.exit(1); }
  process.stdout.write((process.env.STUB_WORKFLOWS === undefined ? '1' : process.env.STUB_WORKFLOWS) + '\n');
  process.exit(0);
}
if (args[0] === 'pr' && args[1] === 'view') {
  process.stdout.write(JSON.stringify({ state: process.env.STUB_STATE || 'OPEN' }) + '\n');
  process.exit(0);
}
process.exit(0);
STUB

# ----------------------------------------------------------- ambiente de execução
NODE_DIR="$(dirname "$(command -v node)")"
GIT_DIR="$(dirname "$(command -v git)")"
PATH_COM_STUB="$BIN:$PATH"
PATH_SEM_GH="$NODE_DIR:$GIT_DIR"

# Roda o script na caixa. Argumentos: diretorio, subcomando e flags. O STDOUT vai
# para $SAIDA (é o resultado que a sessao le: a ultima linha e' o `PR aberto:`);
# o STDERR vai para $ERRO (diagnostico). Não misturar: o aviso DEP0190 do Node,
# disparado pelo shell:true que o resolver usa para o gh.cmd do stub, sai no stderr
# e, misturado, ficaria por cima da linha de resultado.
roda() {
  local dir="$1"; shift
  (cd "$dir" && RFM_ROOT="$DADOS" PATH="$PATH_COM_STUB" node "$SCRIPT" "$@") > "$SAIDA" 2> "$ERRO"
  CODIGO=$?
}
roda_sem_gh() {
  local dir="$1"; shift
  (cd "$dir" && RFM_ROOT="$DADOS" PATH="$PATH_SEM_GH" node "$SCRIPT" "$@") > "$SAIDA" 2> "$ERRO"
  CODIGO=$?
}
ultima_linha() { tail -n 1 "$SAIDA" | tr -d '\r'; }
caixa_git() { (cd "$CAIXA" && git "$@"); }

# ---------------------------------------------------------------- o fixture
rm -rf "$CAIXA"; mkdir -p "$CAIXA"
git init -q --bare -b main "$BARE"
(cd "$CAIXA" && git init -q -b main && git config user.name "Teste" && git config user.email "teste@teste.invalid" \
  && printf 'linha1\nlinha2\nlinha3\n' > arquivo.txt && git add arquivo.txt && git commit -q -m base \
  && git remote add origin https://github.com/caixa/repo.git \
  && git config "url.$BARE_W.insteadOf" https://github.com/caixa/repo.git \
  && git push -q -u origin main) >/dev/null 2>&1
afirma "fixture: caixa com base main publicada no bare" $?

git clone -q "$BARE" "$BASEWC" >/dev/null 2>&1
(cd "$BASEWC" && git config user.name "Base" && git config user.email "base@teste.invalid") >/dev/null 2>&1

# Ninguem sabe o caminho do stub antes da caixa ficar pronta; o gate abaixo prova
# que `gh` resolve para o stub e que o PATH sem stub NAO acha gh.
GATE_STUB="$(cd "$CAIXA" && PATH="$PATH_COM_STUB" command -v gh)"
case "$GATE_STUB" in "$BIN"/gh) gate_stub=0 ;; *) gate_stub=1 ;; esac
afirma "gate: 'command -v gh' com o stub no PATH resolve para o stub ($GATE_STUB)" $gate_stub
GATE_SEM="$(cd "$CAIXA" && PATH="$PATH_SEM_GH" command -v gh)"
[ -z "$GATE_SEM" ]; afirma "gate: sem o stub no PATH, 'command -v gh' fica vazio" $?

# ============================================================ (a) branch limpa
echo "== (a) branch limpa sobre a base"
caixa_git checkout -q -b feat-a main && (cd "$CAIXA" && echo "feat-a" > novo-a.txt) && caixa_git add novo-a.txt && caixa_git commit -q -m feat-a
LOG="$S/log-a.txt"; export STUB_LOG="$LOG"; export STUB_PR="null"
roda "$CAIXA" publicar
[ "$CODIGO" -eq 0 ]; afirma "(a1) sai 0 (exit=$CODIGO)" $?
H="$(caixa_git rev-parse HEAD)"; U="$(caixa_git rev-parse @{u})"
[ "$H" = "$U" ]; afirma "(a1) HEAD == @{u} ($H)" $?
[ "$(ultima_linha)" = "PR aberto: nenhum" ]; afirma "(a1) ultima linha 'PR aberto: nenhum' (saida: $(ultima_linha))" $?
grep -q "CHAMADA: gh pr list" "$LOG"; afirma "(a1) o stub foi consultado por pr list" $?
! grep -q "pr create" "$LOG"; afirma "(a1) o stub nao registra pr create" $?

export STUB_PR="7"; : > "$LOG"
roda "$CAIXA" publicar
[ "$CODIGO" -eq 0 ] && [ "$(ultima_linha)" = "PR aberto: 7" ]; afirma "(a2) com PR 7 aberto: sai 0 e ultima linha 'PR aberto: 7'" $?
! grep -q "pr create" "$LOG"; afirma "(a2) o stub nao registra pr create" $?

# ============================================================ (b) conflito com a base
echo "== (b) base andou com mudança na mesma linha do mesmo arquivo"
caixa_git checkout -q -b feat-b main && (cd "$CAIXA" && sed -i '1s/.*/linha1-feat-b/' arquivo.txt) \
  && caixa_git add arquivo.txt && caixa_git commit -q -m feat-b
(cd "$BASEWC" && sed -i '1s/.*/linha1-base/' arquivo.txt && git add arquivo.txt && git commit -q -m base-b && git push -q origin main) >/dev/null 2>&1
afirma "fixture (b): base andou no bare" $?
LOG="$S/log-b.txt"; export STUB_LOG="$LOG"; export STUB_PR="null"
roda "$CAIXA" publicar
[ "$CODIGO" -eq 3 ]; afirma "(b) sai 3 (exit=$CODIGO)" $?
grep -q "arquivo.txt" "$SAIDA"; afirma "(b) imprime o caminho do arquivo em conflito" $?
[ -z "$(caixa_git ls-remote origin refs/heads/feat-b)" ]; afirma "(b) git ls-remote do bare nao tem a branch feat-b" $?
! grep -q "PR aberto" "$SAIDA"; afirma "(b) nao imprime 'PR aberto' (nao publicou)" $?

# ============================================================ (c) base andou sem conflito
echo "== (c) base andou sem conflito"
caixa_git checkout -q -b feat-c main && (cd "$CAIXA" && echo "feat-c" > novo-c.txt) && caixa_git add novo-c.txt && caixa_git commit -q -m feat-c
(cd "$BASEWC" && echo "base-c" > base-c.txt && git add base-c.txt && git commit -q -m base-c && git push -q origin main) >/dev/null 2>&1
afirma "fixture (c): base andou sem conflito no bare" $?
roda "$CAIXA" publicar
[ "$CODIGO" -eq 0 ]; afirma "(c) sai 0 (exit=$CODIGO)" $?
[ -n "$(caixa_git ls-remote origin refs/heads/feat-c)" ]; afirma "(c) fez o push: feat-c existe no bare" $?

# ============================================================ (d) base inexistente
echo "== (d) base inexistente"
caixa_git checkout -q -b feat-d main && (cd "$CAIXA" && echo "feat-d" > novo-d.txt) && caixa_git add novo-d.txt && caixa_git commit -q -m feat-d
roda "$CAIXA" publicar --base nao-existe
[ "$CODIGO" -eq 69 ]; afirma "(d) sai 69 (exit=$CODIGO)" $?
[ -z "$(caixa_git ls-remote origin refs/heads/feat-d)" ]; afirma "(d) sem push: feat-d nao existe no bare" $?

# (d2) o fetch passa, mas origin/<base> nao vira ref de tracking (refspec estreito):
# o merge-tree sai 1 sem arvore ("not something we can merge"), e isso nao e conflito.
echo "== (d2) fetch ok, origin/<base> ausente"
(cd "$BASEWC" && git push -q origin main:outra) >/dev/null 2>&1
afirma "fixture (d2): branch outra existe no bare" $?
caixa_git config remote.origin.fetch "+refs/heads/main:refs/remotes/origin/main"
roda "$CAIXA" publicar --base outra
[ "$CODIGO" -eq 69 ]; afirma "(d2) sai 69, nao 3 (exit=$CODIGO)" $?
! grep -q "CONFLITO" "$SAIDA"; afirma "(d2) nao anuncia conflito" $?
[ -z "$(caixa_git ls-remote origin refs/heads/feat-d)" ]; afirma "(d2) sem push" $?
caixa_git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

# (d3) base de historia sem relacao: o merge-tree sai 128, falha do comando, nunca "limpo".
echo "== (d3) base sem historia em comum"
(cd "$BASEWC" && git checkout -q --orphan orfa && git rm -rq --cached . && git commit -q --allow-empty -m orfa && git push -q origin orfa && git checkout -q -f main) >/dev/null 2>&1
afirma "fixture (d3): branch orfa existe no bare" $?
roda "$CAIXA" publicar --base orfa
[ "$CODIGO" -eq 69 ]; afirma "(d3) sai 69 (exit=$CODIGO)" $?
[ -z "$(caixa_git ls-remote origin refs/heads/feat-d)" ]; afirma "(d3) sem push" $?

# ============================================================ (e) push recusado
echo "== (e) push recusado pelo remoto"
caixa_git checkout -q -b feat-e main && (cd "$CAIXA" && echo "feat-e" > novo-e.txt) && caixa_git add novo-e.txt && caixa_git commit -q -m feat-e
printf '#!/bin/sh\necho "recusado pelo teste" >&2\nexit 1\n' > "$BARE/hooks/pre-receive"; chmod +x "$BARE/hooks/pre-receive"
roda "$CAIXA" publicar
[ "$CODIGO" -eq 4 ]; afirma "(e) sai 4 (exit=$CODIGO)" $?
! grep -q "PR aberto" "$SAIDA"; afirma "(e) nao imprime 'PR aberto'" $?
rm -f "$BARE/hooks/pre-receive"

# ============================================================ (f) remoto não GitHub
echo "== (f) remoto sem github.com"
caixa_git remote set-url origin "$BARE_W"
caixa_git checkout -q -b feat-f main && (cd "$CAIXA" && echo "feat-f" > novo-f.txt) && caixa_git add novo-f.txt && caixa_git commit -q -m feat-f
LOG="$S/log-f.txt"; export STUB_LOG="$LOG"
roda "$CAIXA" publicar
[ "$CODIGO" -eq 0 ]; afirma "(f) sai 0 (exit=$CODIGO)" $?
[ "$(ultima_linha)" = "PR aberto: n/a (remoto não é GitHub)" ]; afirma "(f) ultima linha 'PR aberto: n/a (remoto não é GitHub)' (saida: $(ultima_linha))" $?
[ ! -s "$LOG" ]; afirma "(f) o stub gh nao foi chamado" $?
caixa_git remote set-url origin https://github.com/caixa/repo.git

# ============================================================ (g) esperar-ci
echo "== (g) esperar-ci --pr 7"
export STUB_LOG="$S/log-g.txt"
mkdir -p "$CAIXA/.rainforest"
printf '{"fechar-mergear": true}\n' > "$CAIXA/.rainforest/config.json"
export STUB_CHECKS_EXIT=0
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 0 ]; afirma "(g1) CI verde + fechar-mergear ligada: sai 0 (exit=$CODIGO)" $?
grep -q "merge autorizado" "$SAIDA"; afirma "(g1) imprime 'merge autorizado'" $?

rm -f "$CAIXA/.rainforest/config.json"
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 7 ]; afirma "(g2) CI verde + chave ausente: sai 7 (exit=$CODIGO)" $?

printf '{"fechar-mergear": false}\n' > "$CAIXA/.rainforest/config.json"
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 7 ]; afirma "(g3) CI verde + chave false: sai 7 (exit=$CODIGO)" $?

printf '{\n' > "$CAIXA/.rainforest/config.json"
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 7 ]; afirma "(g4) CI verde + config ilegivel: sai 7 (exit=$CODIGO)" $?

printf '{"fechar-mergear": true}\n' > "$CAIXA/.rainforest/config.json"
export STUB_CHECKS_EXIT=1
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g5) CI vermelho: sai 5 (exit=$CODIGO)" $?
export STUB_CHECKS_EXIT=0

# gh 2.96 sai 0 do --watch com um check CANCELLED (PR #537): o bucket decide.
export STUB_CHECKS_JSON='[{"name":"shard 1/2","bucket":"cancel"},{"name":"shard 2/2","bucket":"pass"}]'
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g7) watch sai 0 com check cancelado: sai 5 (exit=$CODIGO)" $?
grep -q "shard 1/2 (cancel)" "$ERRO"; afirma "(g7) stderr nomeia o check cancelado" $?
! grep -q "merge autorizado" "$SAIDA"; afirma "(g7) nao imprime 'merge autorizado'" $?

export STUB_CHECKS_JSON='[{"name":"a","bucket":"pass"},{"name":"b","bucket":"skipping"}]'
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 0 ]; afirma "(g8) pass + skipping: sai 0 (exit=$CODIGO)" $?

export STUB_CHECKS_JSON='[]'
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g9) lista de checks vazia: sai 5 (exit=$CODIGO)" $?

export STUB_CHECKS_JSON='nao e json'
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g10) JSON ilegivel: sai 5 (exit=$CODIGO)" $?
unset STUB_CHECKS_JSON

# #576: repositorio sem workflow nenhum e PR sem check e CI ausente, nao vermelho.
export STUB_WORKFLOWS=0 STUB_CHECKS_JSON='[]' STUB_CHECKS_EXIT=1
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g11) zero workflows e PR sem check: sai 8 (exit=$CODIGO)" $?
grep -q "repositório sem CI" "$SAIDA"; afirma "(g11) stdout diz repositorio sem CI" $?
grep -q "merge autorizado" "$SAIDA"; afirma "(g11) com fechar-mergear ligada, diz merge autorizado" $?
printf '{"fechar-mergear": false}\n' > "$CAIXA/.rainforest/config.json"
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g12) sem CI e chave desligada: sai 8 (exit=$CODIGO)" $?
grep -q "pare no PR aberto" "$SAIDA"; afirma "(g12) diz pare no PR aberto" $?
printf '{"fechar-mergear": true}\n' > "$CAIXA/.rainforest/config.json"
export STUB_WORKFLOWS=2
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g13) com workflow e PR sem check: segue 5 (exit=$CODIGO)" $?
export STUB_WORKFLOWS=0 STUB_API_FAIL=1
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g14) API que falha nao vira 8: sai 5 (exit=$CODIGO)" $?
unset STUB_API_FAIL
export STUB_CHECKS_JSON='[{"name":"externo","bucket":"pass"}]' STUB_CHECKS_EXIT=0
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 0 ]; afirma "(g15) zero workflows mas PR com check verde: segue 0 (exit=$CODIGO)" $?
unset STUB_WORKFLOWS STUB_CHECKS_JSON STUB_CHECKS_EXIT

roda_sem_gh "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 69 ]; afirma "(g6) gh ausente do PATH: sai 69 (exit=$CODIGO)" $?
rm -rf "$CAIXA/.rainforest"

# ============================================================ (h) confirmar-merge
echo "== (h) confirmar-merge --pr 7"
export STUB_LOG="$S/log-h.txt"
export STUB_STATE="MERGED"
roda "$CAIXA" confirmar-merge --pr 7
[ "$CODIGO" -eq 0 ]; afirma "(h1) state MERGED: sai 0 (exit=$CODIGO)" $?
export STUB_STATE="OPEN"
RFM_MERGE_PRAZO_S=2 roda "$CAIXA" confirmar-merge --pr 7
[ "$CODIGO" -eq 6 ]; afirma "(h2) state OPEN com prazo de 2 s: sai 6 (exit=$CODIGO)" $?
export STUB_STATE="CLOSED"
roda "$CAIXA" confirmar-merge --pr 7
[ "$CODIGO" -eq 6 ]; afirma "(h3) state CLOSED: sai 6 (exit=$CODIGO)" $?

# ============================================================ (i) uso
echo "== (i) uso"
roda "$CAIXA"
[ "$CODIGO" -eq 1 ]; afirma "(i1) sem subcomando: sai 1 (exit=$CODIGO)" $?
roda "$CAIXA" publicar --flag-desconhecida x
[ "$CODIGO" -eq 1 ]; afirma "(i2) flag desconhecida: sai 1 (exit=$CODIGO)" $?
roda "$CAIXA" esperar-ci --pr abc
[ "$CODIGO" -eq 1 ]; afirma "(i3) --pr abc: sai 1 (exit=$CODIGO)" $?
roda "$CAIXA" confirmar-merge --pr 0
[ "$CODIGO" -eq 1 ]; afirma "(i4) --pr 0: sai 1 (exit=$CODIGO)" $?

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
