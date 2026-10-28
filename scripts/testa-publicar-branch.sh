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
  if (process.env.STUB_CHECKS_JSON_VAZIO_N !== undefined) {
    // #616: conta cada chamada em STUB_CONTAGEM; as N primeiras saem vazias, como o gh com run ainda não registrado.
    const n = (fs.existsSync(process.env.STUB_CONTAGEM) ? Number(fs.readFileSync(process.env.STUB_CONTAGEM, 'utf8')) : 0) + 1;
    fs.writeFileSync(process.env.STUB_CONTAGEM, String(n));
    if (n <= Number(process.env.STUB_CHECKS_JSON_VAZIO_N)) {
      process.stderr.write("no checks reported on the 'x' branch\n");
      process.exit(1);
    }
  }
  if (process.env.STUB_CHECKS_JSON_EXIT !== undefined) {
    if (process.env.STUB_CHECKS_JSON_STDERR) process.stderr.write(process.env.STUB_CHECKS_JSON_STDERR + '\n');
    process.exit(Number(process.env.STUB_CHECKS_JSON_EXIT));
  }
  process.stdout.write((process.env.STUB_CHECKS_JSON || '[{"name":"baterias","bucket":"pass"}]') + '\n');
  process.exit(0);
}
if (args[0] === 'pr' && args[1] === 'checks') process.exit(Number(process.env.STUB_CHECKS_EXIT || 0));
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
UL="$(ultima_linha)"; [ "$UL" = "PR aberto: nenhum" ]; afirma "(a1) ultima linha 'PR aberto: nenhum' (saida: $UL)" $?
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
UL="$(ultima_linha)"; [ "$UL" = "PR aberto: n/a (remoto não é GitHub)" ]; afirma "(f) ultima linha 'PR aberto: n/a (remoto não é GitHub)' (saida: $UL)" $?
[ ! -s "$LOG" ]; afirma "(f) o stub gh nao foi chamado" $?
caixa_git remote set-url origin https://github.com/caixa/repo.git

# ============================================================ (g) esperar-ci
echo "== (g) esperar-ci --pr 7"
export STUB_LOG="$S/log-g.txt"
# #616: com workflow de PR e lista vazia, o esperar-ci sonda antes do --watch. Nos
# casos antigos o prazo é 1 s (uma sondagem extra): a saída de cada um é a de hoje.
# Os casos novos (g36 a g38) põem o próprio prazo.
export RFM_CI_PRAZO_REGISTRO_S=1 RFM_CI_SONDA_S=1
# Os workflows entram no indice (git add), que e o que o `git ls-files` le. Ate o
# (g11) a caixa tem um workflow de PR, como a caixa antiga tinha um workflow (count 1):
# g1-g10 e g16-g18 testam o esperar-ci com CI de PR presente. caixa_limpa tira tudo antes de g11.
workflow() { mkdir -p "$CAIXA/.github/workflows" && cat > "$CAIXA/.github/workflows/$1" && caixa_git add .github/workflows; }
caixa_limpa() { caixa_git rm -r -q --cached --ignore-unmatch .github >/dev/null 2>&1; rm -rf "$CAIXA/.github"; }
workflow ci.yml <<'YML'
on: pull_request
YML
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
export STUB_CHECKS_EXIT=1 STUB_CHECKS_JSON='[{"name":"a","bucket":"fail"}]'
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g5) CI vermelho: sai 5 (exit=$CODIGO)" $?
grep -q "a (fail)" "$ERRO"; afirma "(g5) stderr nomeia a (fail)" $?

# #587 (D4): --watch saiu 1 e o relido decide. Relido sem estado legivel = 69, nao 5.
export STUB_CHECKS_JSON_EXIT=1 STUB_CHECKS_JSON_STDERR='error connecting to api.github.com'
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 69 ]; afirma "(g16) watch 1 e releitura sem rede: sai 69 (exit=$CODIGO)" $?
head -n 1 "$ERRO" | grep -q '^nao-verificavel:'; afirma "(g16) primeira linha do stderr comeca por nao-verificavel:" $?
unset STUB_CHECKS_JSON_EXIT STUB_CHECKS_JSON_STDERR

export STUB_CHECKS_JSON='[{"name":"a","bucket":"pending"}]'
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 69 ]; afirma "(g18) watch cai com checks pending: sai 69 (exit=$CODIGO)" $?
head -n 1 "$ERRO" | grep -q '^nao-verificavel:'; afirma "(g18) primeira linha do stderr comeca por nao-verificavel:" $?

export STUB_CHECKS_JSON='[]'
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g17) watch cai com lista vazia: sai 5 (exit=$CODIGO)" $?
export STUB_CHECKS_EXIT=0
unset STUB_CHECKS_JSON

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

# #576 e #591: 8 so quando nenhum workflow DO CHECKOUT alcanca PR e o PR nao tem
# check. Os casos seguintes tiram os workflows da caixa (caixa_limpa) e os põem de
# novo quando precisam; nada vaza entre eles.
caixa_limpa
export STUB_CHECKS_JSON='[]' STUB_CHECKS_EXIT=1

roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g11) sem .github/workflows e PR sem check: sai 8 (exit=$CODIGO)" $?
grep -q "repositório sem CI de PR" "$SAIDA"; afirma "(g11) stdout diz repositorio sem CI de PR" $?
grep -q "merge autorizado" "$SAIDA"; afirma "(g11) com fechar-mergear ligada, diz merge autorizado" $?
printf '{"fechar-mergear": false}\n' > "$CAIXA/.rainforest/config.json"
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g12) sem CI e chave desligada: sai 8 (exit=$CODIGO)" $?
grep -q "pare no PR aberto" "$SAIDA"; afirma "(g12) diz pare no PR aberto" $?
printf '{"fechar-mergear": true}\n' > "$CAIXA/.rainforest/config.json"

# (g13) workflow so de push, sem filtro de branch, alcanca o PR: o CI existe e nao reportou.
workflow ci.yml <<'YML'
on: [push]
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g13) workflow com push sem branches e PR sem check: segue 5 (exit=$CODIGO)" $?
caixa_limpa

# (g14) workflow listado no indice mas ilegivel no disco: leitura que falha nao vira 8.
workflow ci.yml <<'YML'
on: pull_request
YML
rm -f "$CAIXA/.github/workflows/ci.yml"
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g14) workflow listado e ilegivel: sai 5, nao 8 (exit=$CODIGO)" $?
caixa_limpa

# (g15) workflow de PR e PR com check verde: segue 0.
workflow ci.yml <<'YML'
on: pull_request
YML
export STUB_CHECKS_JSON='[{"name":"externo","bucket":"pass"}]' STUB_CHECKS_EXIT=0
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 0 ]; afirma "(g15) workflow de PR e check verde: segue 0 (exit=$CODIGO)" $?
export STUB_CHECKS_JSON='[]' STUB_CHECKS_EXIT=1
caixa_limpa

# (g19) workflow com pull_request e PR sem check: sai 5 (o CI de PR existe e nao reportou).
workflow ci.yml <<'YML'
on: pull_request
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g19) workflow com pull_request e PR sem check: sai 5 (exit=$CODIGO)" $?

# (g25) o mesmo com o formato do gh real (2.96): PR sem check faz a releitura sair 1,
# stdout vazio, "no checks reported" no stderr. Nao e rede caida: sai 5, nao 69.
export STUB_CHECKS_JSON_EXIT=1 STUB_CHECKS_JSON_STDERR="no checks reported on the 'x' branch"
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g25) pull_request e PR sem check no formato do gh real: sai 5, nao 69 (exit=$CODIGO)" $?
caixa_limpa

# (g26) sem workflow e PR sem check no formato do gh real: continua 8.
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g26) sem .github/workflows e PR sem check no formato do gh real: sai 8 (exit=$CODIGO)" $?
unset STUB_CHECKS_JSON_EXIT STUB_CHECKS_JSON_STDERR

# (g20) protect-main.yml com o conteudo real da #591 (push em main): nenhum workflow alcanca PR: sai 8.
workflow protect-main.yml <<'YML'
on:
  push:
    branches: [main]
jobs:
  protect:
    runs-on: ubuntu-latest
    steps:
      - run: echo protect
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g20) so protect-main (push em main) e PR sem check: sai 8 (exit=$CODIGO)" $?

# (g21) protect-main.yml mais um workflow so de schedule: continua sem CI de PR: sai 8.
workflow schedule.yml <<'YML'
on:
  schedule:
    - cron: '0 6 * * *'
jobs:
  nightly:
    runs-on: ubuntu-latest
    steps:
      - run: echo nightly
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g21) protect-main e schedule, PR sem check: sai 8 (exit=$CODIGO)" $?
caixa_limpa

# (g23) push com branches-ignore dispara na branch do PR: o CI existe e nao reportou, segue 5.
workflow ci.yml <<'YML'
on:
  push:
    branches-ignore: [main]
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g23) push com branches-ignore e PR sem check: sai 5, nao 8 (exit=$CODIGO)" $?
caixa_limpa

# (g24) push com glob de branch ("**") dispara na branch do PR: segue 5.
workflow ci.yml <<'YML'
on:
  push:
    branches: ["**"]
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g24) push com branches glob e PR sem check: sai 5, nao 8 (exit=$CODIGO)" $?
caixa_limpa

# (g27) push sem filtro e `branches:` de outro gatilho (workflow_run) e de um step:
# o filtro nao e do push, o push dispara na branch do PR: segue 5, nao 8.
workflow ci.yml <<'YML'
on:
  push:
  workflow_run:
    workflows: [build]
    branches: [main]
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - uses: x/y@v1
        with:
          branches: main
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g27) push sem filtro e branches: de workflow_run/with: sai 5, nao 8 (exit=$CODIGO)" $?
caixa_limpa

# (g28) protect-main com comentario e cron no mesmo arquivo: o filtro do push e de
# nomes fixos, o * do cron e o comentario nao contam: sai 8.
workflow protect-main.yml <<'YML'
on:
  # so na main
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * *'
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g28) push em main com cron no mesmo arquivo: sai 8 (exit=$CODIGO)" $?
caixa_limpa

# (g29) on: push inline dispara em toda branch; um push: com branches: dentro de
# with: nao e o gatilho: segue 5, nao 8.
workflow ci.yml <<'YML'
on: push
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - uses: x/y@v1
        with:
          push:
            branches: [main]
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g29) on: push inline e push: de with: com branches: sai 5, nao 8 (exit=$CODIGO)" $?
caixa_limpa

# (g30) push: so com paths e um comentario de fim de linha citando branches:
# o comentario nao filtra: segue 5, nao 8.
workflow ci.yml <<'YML'
on:
  push:
    paths: [src]  # branches: [main] fica pra depois
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g30) comentario de fim de linha com branches: nao filtra o push: sai 5 (exit=$CODIGO)" $?
caixa_limpa

# (g31) on: em varias linhas com `- push` (lista) e um push: de with: filtrado em
# main: o gatilho dispara em toda branch, o with: nao e filho de on:: sai 5, nao 8.
workflow ci.yml <<'YML'
on:
  - push
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - uses: x/y@v1
        with:
          push:
            branches: [main]
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g31) on: com - push e push: de with: filtrado: sai 5, nao 8 (exit=$CODIGO)" $?
caixa_limpa

# (g32) o mesmo com `push: {}` como filho de on:: forma que nao e bloco, conta: sai 5.
workflow ci.yml <<'YML'
on:
  push: {}
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - uses: x/y@v1
        with:
          push:
            branches: [main]
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g32) on: com push: {} e push: de with: filtrado: sai 5, nao 8 (exit=$CODIGO)" $?
caixa_limpa

# (g33) glob de branch sem `*` (`[a-z]`, em lista de bloco no mesmo recuo): o push
# dispara na branch do PR: sai 5, nao 8.
workflow ci.yml <<'YML'
on:
  push:
    branches:
    - main
    - 'fluxo/[a-z]'
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g33) branches com glob [a-z] em lista de bloco: sai 5, nao 8 (exit=$CODIGO)" $?
caixa_limpa

# (g34) glob `?` em lista de fluxo: sai 5, nao 8.
workflow ci.yml <<'YML'
on:
  push:
    branches: [main, 'fluxo/?']
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g34) branches com glob ? em lista de fluxo: sai 5, nao 8 (exit=$CODIGO)" $?
caixa_limpa

# (g35) nomes fixos em lista de bloco, com paths glob ao lado: o filtro de branch
# e de nomes fixos, o * do paths nao e de branch: sai 8.
workflow protect-main.yml <<'YML'
on:
  push:
    branches:
      - main
      - release
    paths: ['src/**']
YML
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g35) branches fixos em lista de bloco e paths glob: sai 8 (exit=$CODIGO)" $?
caixa_limpa

# #616 (D3): run ainda não registrado. Workflow de PR no checkout e lista vazia: o
# esperar-ci sonda antes do --watch. (g31) já é de `on: com - push`, acima: o caso
# novo fica com o rótulo (g36).
workflow ci.yml <<'YML'
on: pull_request
YML
export STUB_CHECKS_JSON='[{"name":"baterias","bucket":"pass"}]' STUB_CHECKS_EXIT=0
export STUB_CHECKS_JSON_VAZIO_N=2 STUB_CONTAGEM="$S/contagem-g36.txt"
rm -f "$STUB_CONTAGEM"
export RFM_CI_PRAZO_REGISTRO_S=5 RFM_CI_SONDA_S=1
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 0 ]; afirma "(g36) run registrado na 3a sondagem: sai 0 (exit=$CODIGO)" $?
grep -q "aguardando o GitHub registrar o CI do PR 7" "$SAIDA"; afirma "(g36) imprime a linha de espera do registro" $?
# Para na 3a sondagem: 3 sondagens + 1 releitura = 4 chamadas. Sem parar, a
# sondagem gasta o prazo inteiro e a conta sobe: esta linha é a que a mutação derruba.
CONTA="$(cat "$STUB_CONTAGEM")"; [ "$CONTA" -eq 4 ]; afirma "(g36) para na 3a sondagem: pr checks --json chamado 4 vezes (conta=$CONTA)" $?

# (g37) teto do registro estourado: o caminho de hoje, sai 5 com "no checks reported".
export STUB_CHECKS_JSON_VAZIO_N=99 STUB_CONTAGEM="$S/contagem-g37.txt"
export RFM_CI_PRAZO_REGISTRO_S=2 RFM_CI_SONDA_S=1
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 5 ]; afirma "(g37) teto do registro estourado: sai 5 (exit=$CODIGO)" $?
grep -q "no checks reported" "$ERRO"; afirma "(g37) stderr traz 'no checks reported'" $?
grep -q "aguardando o GitHub registrar" "$SAIDA"; afirma "(g37) espera anunciada antes do teto" $?

# (g38) repositorio sem workflow de PR e PR sem check: sai 8 sem sondagem, uma unica chamada.
caixa_limpa
export STUB_CHECKS_JSON='[]' STUB_CHECKS_EXIT=1
unset STUB_CHECKS_JSON_VAZIO_N STUB_CONTAGEM
export STUB_LOG="$S/log-g38.txt"; : > "$STUB_LOG"
roda "$CAIXA" esperar-ci --pr 7
[ "$CODIGO" -eq 8 ]; afirma "(g38) sem workflow de PR e PR sem check: sai 8 (exit=$CODIGO)" $?
[ "$(grep -c 'pr checks 7 --json' "$STUB_LOG")" -eq 1 ]; afirma "(g38) uma unica chamada de pr checks --json antes da saida" $?
! grep -q "aguardando" "$SAIDA"; afirma "(g38) nao imprime linha de espera" $?
export RFM_CI_PRAZO_REGISTRO_S=1 RFM_CI_SONDA_S=1
unset STUB_CHECKS_JSON

# (g22) cwd fora de repositorio git: o script para antes de ler workflow (main), nunca 8.
mkdir -p "$S/fora"
roda "$S/fora" esperar-ci --pr 7
[ "$CODIGO" -eq 69 ]; afirma "(g22) cwd fora de repositorio git: sai 69, nunca 8 (exit=$CODIGO)" $?
unset STUB_CHECKS_JSON STUB_CHECKS_EXIT

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
