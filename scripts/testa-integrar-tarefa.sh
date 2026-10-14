#!/bin/bash
# Bateria do scripts/integrar-tarefa.cjs (D6 e D7 do design 2026-10-13-executar-autonomo)
# e do `--tarefa N` do conferir-fluxo.cjs mutacoes.
# Uso: bash scripts/testa-integrar-tarefa.sh
#
# Cada cenario roda numa caixa nova (mktemp -d, fora do repo): repo git com `origin`
# bare, plano de 2 tarefas com `mutacao:` real, fluxo aberto em `executar` e um
# worktree de agente com um commit de verdade. Os scripts que rodam sao copias reais
# do SRC; o que muda de cenario para cenario e so a entrega do agente.
#
# O commit e o trailer sao de verdade (`git commit --trailer`), e a sentinela de
# integracao e o git: cada cenario confere HEAD, status e estado depois da chamada.
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOXES=()
cleanup() { for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done; }
trap cleanup EXIT

# GIT_* herdado (de um hook, de outro repo) apontaria as caixas para o repo errado.
for v in $(env | grep -o '^GIT_[A-Z_]*'); do unset "$v"; done
unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID

ok=0; falhou=0
SLUG=2026-10-13-integrar-teste

igual() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi
}

# J <expressao>: le JSON da entrada padrao e imprime a expressao sobre `j`.
J() {
  node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));const v=(new Function("j","return "+process.argv[1]))(j);console.log(typeof v==="string"?v:JSON.stringify(v===undefined?null:v));' "$1"
}

# estado_de <expressao>: a expressao sobre o JSON do estado do fluxo da caixa atual.
estado_de() {
  node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const v=(new Function("j","return "+process.argv[2]))(j);console.log(JSON.stringify(v===undefined?null:v));' \
    "$(cygpath -m "$CX/docs/rainforest/estado/$SLUG.json")" "$1"
}

# Caixa nova: repo com origin bare, scripts e plano commitados na base, branch fluxo/x.
# Deixa em CX o caminho POSIX e em W o caminho Windows (o node le W).
caixa_nova() {
  CX="$(mktemp -d)"; SANDBOXES+=("$CX")
  AUX="$(mktemp -d)"; SANDBOXES+=("$AUX")
  W="$(cygpath -m "$CX" 2>/dev/null || printf '%s' "$CX")"
  export HOME="$AUX/casa" USERPROFILE="$AUX/casa" CLAUDE_CONFIG_DIR="$AUX/casa/.claude-personal"
  mkdir -p "$HOME" "$CX/scripts/lib" "$CX/hooks/lib" "$CX/src" "$CX/docs/rainforest/planos"
  for s in integrar-tarefa.cjs conferir-entrega.cjs conferir-mutacao.cjs conferir-fluxo.cjs estado.cjs; do
    cp "$SRC/scripts/$s" "$CX/scripts/"
  done
  cp "$SRC/scripts/lib/camadas.cjs" "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SRC/scripts/lib/extrair-veredito.cjs" "$CX/scripts/lib/"
  for lib in raiz config trava-jsonl pastas-docs resolver-executavel contar-ocorrencias caminho-leve teto-despachos; do
    cp "$SRC/hooks/lib/$lib.cjs" "$CX/hooks/lib/"
  done
  export RFM_ESTADO_ROOT="$W"

  ORIG="$(mktemp -d)"; SANDBOXES+=("$ORIG")
  git init -q --bare "$ORIG/origin.git"
  cd "$CX" || exit 1
  git init -q -b main
  git config user.email "teste@exemplo.invalid"
  git config user.name "teste"
  git remote add origin "$ORIG/origin.git"

  touch FOCO.md
  mkdir -p .rainforest && printf '{"principal-livre": true}\n' > .rainforest/config.json
  printf '# teste\n' > LEIA.md
  printf 'docs/rainforest/estado/\n' > .gitignore
  printf "module.exports = () => 'alfa-ok';\n" > src/alfa.cjs
  printf "module.exports = () => 'beta-ok';\n" > src/beta.cjs
  cat > scripts/prova-alfa.cjs <<'EOF'
const alfa = require('../src/alfa.cjs');
let ok = 0;
let falhou = 0;
const confere = (nome, cond) => {
  if (cond) ok++;
  else { falhou++; console.log('FALHA ' + nome); }
};
confere('alfa devolve alfa-ok', alfa() === 'alfa-ok');
confere('alfa e funcao', typeof alfa === 'function');
console.log('ok: ' + ok + '   falhou: ' + falhou);
process.exit(falhou ? 1 : 0);
EOF
  cat > scripts/prova-frouxa.cjs <<'EOF'
let ok = 0;
const confere = (nome, cond) => { if (cond) ok++; else console.log('FALHA ' + nome); };
confere('arquivo beta existe', require('fs').existsSync('src/beta.cjs'));
confere('beta e um modulo', typeof require('../src/beta.cjs') === 'function');
console.log('ok: ' + ok + '   falhou: 0');
EOF
  cat > docs/rainforest/planos/$SLUG.md <<'EOF'
# Plano: teste da integracao

## Tarefas

### 1. Alfa [tipo: implementar]
arquivos: `src/alfa.cjs`
depende de: nenhuma
prova: `node scripts/prova-alfa.cjs`
mutacao:
  arquivo: `src/alfa.cjs`
  de: `'alfa-ok'`
  para: `'alfa-x'`
  bateria: `node scripts/prova-alfa.cjs`

### 2. Beta [tipo: implementar]
arquivos: `src/beta.cjs`, `src/nova.cjs`, `src/gestão/contrato final.txt`
depende de: nenhuma
prova: `node scripts/prova-frouxa.cjs`
mutacao:
  arquivo: `src/beta.cjs`
  de: `'beta-ok'`
  para: `'beta-x'`
  bateria: `node scripts/prova-frouxa.cjs`
EOF
  git add -A && git commit -q -m "base do teste"
  git push -q origin main
  git checkout -q -b fluxo/x
}

# Abre o fluxo em `executar`, com as duas tarefas em voo.
abrir_fluxo() {
  cd "$CX" || exit 1
  node scripts/estado.cjs iniciar --slug "$SLUG" >/dev/null 2>&1 || { echo "FALHA preparo: iniciar"; exit 1; }
  node scripts/estado.cjs marcar --slug "$SLUG" --estagio design --status aprovado >/dev/null 2>&1 || { echo "FALHA preparo: design"; exit 1; }
  node scripts/estado.cjs marcar --slug "$SLUG" --estagio plano --status ok >/dev/null 2>&1 || { echo "FALHA preparo: plano"; exit 1; }
  node scripts/estado.cjs exigir --slug "$SLUG" --estagio executar >/dev/null 2>&1 || { echo "FALHA preparo: executar"; exit 1; }
  node scripts/estado.cjs marcar --slug "$SLUG" --estagio executar --status parcial \
    --json '{"em_voo":[{"tarefa":"1 alfa"},{"tarefa":"2 beta"}]}' >/dev/null 2>&1 || { echo "FALHA preparo: em_voo"; exit 1; }
}

# Despacha um agente: worktree novo a partir do HEAD do fluxo, e o snapshot de sujeira
# tirado antes do despacho. Deixa em WT, BR, BASE, HEAD_ANTES, SUJO e PORC_ANTES.
despachar() {
  local nome="$1"
  local raiz; raiz="$(mktemp -d)"; SANDBOXES+=("$raiz")
  WT="$raiz/agente"
  BR="agente-$nome"
  cd "$CX" || exit 1
  BASE="$(git rev-parse HEAD)"
  HEAD_ANTES="$BASE"
  git worktree add -q -b "$BR" "$(cygpath -m "$WT")" HEAD || { echo "FALHA preparo: worktree"; exit 1; }
  SUJO="$AUX/sujo-$nome.txt"
  { printf '# toplevel: %s\n' "$(git rev-parse --show-toplevel)"; git status --porcelain; } > "$SUJO"
  PORC_ANTES="$(git status --porcelain)"
}

# Commit do agente com tudo o que ele editou em WT.
agente_commita() {
  (cd "$WT" && git add -A && git commit -q -m "$1") || { echo "FALHA preparo: commit do agente"; exit 1; }
}

# Roda integrar-tarefa no fluxo. Deixa em SAIDA (stdout), ERR (stderr) e RC (exit).
integrar() {
  cd "$CX" || exit 1
  SAIDA="$(node scripts/integrar-tarefa.cjs --slug "$SLUG" --tarefa "$1" \
    --worktree "$(cygpath -m "$WT")" --base "$BASE" --head-antes "$HEAD_ANTES" \
    --sujo-antes "$(cygpath -m "$SUJO")" --titulo "Integra tarefa $1" 2>"$AUX/err.txt")"
  RC=$?
  ERR="$(cat "$AUX/err.txt")"
}

echo "== entrega boa integra e marca =="
caixa_nova
abrir_fluxo
despachar alfa
printf '// integrada\n' >> "$WT/src/alfa.cjs"
agente_commita "alfa: comentario de integracao"
integrar 1
igual "integrar tarefa 1 sai 0" "0" "$RC"
igual "JSON diz aceito" "aceito" "$(echo "$SAIDA" | J 'j.resultado')"
igual "1 commit novo na branch" "1" "$(cd "$CX" && git rev-list --count "$HEAD_ANTES..HEAD")"
igual "commit do JSON e o HEAD" "$(cd "$CX" && git rev-parse HEAD)" "$(echo "$SAIDA" | J 'j.commit')"
igual "trailer Rainforest-Tarefa do commit" "$SLUG#1" "$(cd "$CX" && git log -1 --format='%(trailers:key=Rainforest-Tarefa,valueonly)')"
igual "integradas [1] no estado" "[1]" "$(estado_de 'j.executar.integradas')"
igual "em_voo sem a tarefa 1" '["2 beta"]' "$(estado_de 'j.executar.em_voo.map(a=>a.tarefa)')"
igual "worktree do agente removido" "nao" "$([ -e "$WT" ] && echo sim || echo nao)"
igual "branch do agente apagada" "" "$(cd "$CX" && git branch --list "$BR")"

echo "== entrega fora do escopo recusa e nao commita =="
caixa_nova
abrir_fluxo
despachar fora
printf '// integrada\n' >> "$WT/src/alfa.cjs"
printf '// fora do escopo\n' >> "$WT/src/beta.cjs"
agente_commita "alfa e beta juntos"
integrar 1
igual "integrar tarefa 1 sai 2" "2" "$RC"
igual "passo conferir-entrega" "conferir-entrega" "$(echo "$SAIDA" | J 'j.passo')"
igual "JSON diz recusado" "recusado" "$(echo "$SAIDA" | J 'j.resultado')"
igual "stderr nomeia o passo" "1" "$(echo "$ERR" | grep -c 'RECUSADO: conferir-entrega')"
igual "HEAD nao se move" "$HEAD_ANTES" "$(cd "$CX" && git rev-parse HEAD)"
igual "git status igual ao de antes" "$PORC_ANTES" "$(cd "$CX" && git status --porcelain)"
igual "nada integrado no estado" "[]" "$(estado_de 'j.executar.integradas||[]')"
igual "worktree do agente continua" "sim" "$([ -e "$WT" ] && echo sim || echo nao)"

echo "== mutacao que sobrevive recusa e desfaz =="
caixa_nova
abrir_fluxo
despachar sobrevive
printf '// comentario\n' >> "$WT/src/beta.cjs"
printf 'module.exports = 1;\n' > "$WT/src/nova.cjs"
mkdir -p "$WT/src/gestão" && printf 'x\n' > "$WT/src/gestão/contrato final.txt"
agente_commita "beta, nova e acentuado"
integrar 2
igual "integrar tarefa 2 sai 2" "2" "$RC"
igual "passo mutacao" "mutacao" "$(echo "$SAIDA" | J 'j.passo')"
igual "stderr traz o veredito da mutacao" "1" "$(echo "$ERR" | grep -c 'tarefa 2: mutante sobreviveu')"
igual "HEAD nao se move" "$HEAD_ANTES" "$(cd "$CX" && git rev-parse HEAD)"
igual "git status igual ao de antes" "$PORC_ANTES" "$(cd "$CX" && git status --porcelain)"
igual "arquivo novo trazido saiu do disco" "nao" "$([ -e "$CX/src/nova.cjs" ] && echo sim || echo nao)"
igual "arquivo novo com acento e espaco saiu do disco" "nao" "$([ -e "$CX/src/gestão/contrato final.txt" ] && echo sim || echo nao)"
igual "pasta que ficou vazia saiu do disco" "nao" "$([ -e "$CX/src/gestão" ] && echo sim || echo nao)"
igual "nada no indice" "" "$(cd "$CX" && git diff --cached --name-only)"
igual "beta volta ao conteudo do HEAD" "0" "$(cd "$CX" && git diff --quiet HEAD -- src/beta.cjs; echo $?)"

echo "== entrega que nao encaixa recusa sem deixar conflito =="
caixa_nova
abrir_fluxo
despachar conflito
printf "module.exports = () => 'alfa-ok'; // agente\n" > "$WT/src/alfa.cjs"
agente_commita "alfa na mesma linha"
# Outra tarefa entrou no fluxo depois do despacho, mexendo na mesma linha.
(cd "$CX" && printf "module.exports = () => 'alfa-ok'; // fluxo\n" > src/alfa.cjs && git commit -q -am "outra tarefa")
HEAD_ANTES="$(cd "$CX" && git rev-parse HEAD)"
{ printf '# toplevel: %s\n' "$(cd "$CX" && git rev-parse --show-toplevel)"; (cd "$CX" && git status --porcelain); } > "$SUJO"
PORC_ANTES="$(cd "$CX" && git status --porcelain)"
integrar 1
igual "integrar tarefa 1 sai 2" "2" "$RC"
igual "passo apply" "apply" "$(echo "$SAIDA" | J 'j.passo')"
igual "HEAD nao se move" "$HEAD_ANTES" "$(cd "$CX" && git rev-parse HEAD)"
igual "git status igual ao de antes" "$PORC_ANTES" "$(cd "$CX" && git status --porcelain)"
igual "nenhum caminho em conflito" "" "$(cd "$CX" && git ls-files -u)"
igual "sem marcador de conflito no arquivo" "0" "$(grep -c '^<<<<<<<' "$CX/src/alfa.cjs")"

echo "== agente com 2 commits traz os dois =="
caixa_nova
abrir_fluxo
despachar dois
{ printf '// c1\n'; cat "$WT/src/alfa.cjs"; } > "$WT/src/alfa.tmp" && mv "$WT/src/alfa.tmp" "$WT/src/alfa.cjs"
agente_commita "c1"
printf '// c2\n' >> "$WT/src/alfa.cjs"
agente_commita "c2"
integrar 1
igual "integrar tarefa 1 sai 0" "0" "$RC"
igual "c1 chegou" "1" "$(grep -c '^// c1$' "$CX/src/alfa.cjs")"
igual "c2 chegou" "1" "$(grep -c '^// c2$' "$CX/src/alfa.cjs")"
igual "1 commit novo na branch" "1" "$(cd "$CX" && git rev-list --count "$HEAD_ANTES..HEAD")"

echo "== indice com stage previo recusa antes de trazer =="
caixa_nova
abrir_fluxo
printf 'preparado\n' > "$CX/preparado.txt"
(cd "$CX" && git add preparado.txt)
despachar indice
printf '// integrada\n' >> "$WT/src/alfa.cjs"
agente_commita "alfa"
integrar 1
igual "integrar tarefa 1 sai 2" "2" "$RC"
igual "passo indice-sujo" "indice-sujo" "$(echo "$SAIDA" | J 'j.passo')"
igual "HEAD nao se move" "$HEAD_ANTES" "$(cd "$CX" && git rev-parse HEAD)"
igual "git status igual ao de antes" "$PORC_ANTES" "$(cd "$CX" && git status --porcelain)"

echo "== marcar que falhou depois do commit retoma sem commit novo =="
caixa_nova
abrir_fluxo
despachar retoma
printf '// integrada\n' >> "$WT/src/alfa.cjs"
agente_commita "alfa"
VAZIO="$(mktemp -d)"; SANDBOXES+=("$VAZIO")
RFM_ESTADO_ROOT="$(cygpath -m "$VAZIO")" integrar 1
igual "1a chamada sem estado sai 69" "69" "$RC"
igual "1a chamada ja commitou" "1" "$(cd "$CX" && git rev-list --count "$HEAD_ANTES..HEAD")"
# O worktree do agente foi removido à mão entre as chamadas: a retomada não depende dele.
(cd "$CX" && git worktree remove --force "$(cygpath -m "$WT")")
integrar 1
igual "2a chamada sai 0" "0" "$RC"
igual "2a chamada diz aceito" "aceito" "$(echo "$SAIDA" | J 'j.resultado')"
igual "stderr diz retomada" "1" "$(echo "$ERR" | grep -c '^retomada:')"
igual "continua 1 commit so" "1" "$(cd "$CX" && git rev-list --count "$HEAD_ANTES..HEAD")"
igual "integradas [1] no estado" "[1]" "$(estado_de 'j.executar.integradas')"
igual "worktree do agente removido" "nao" "$([ -e "$WT" ] && echo sim || echo nao)"

echo "== redespacho da mesma tarefa integra a correcao, sem retomada falsa =="
caixa_nova
abrir_fluxo
despachar alfa1
printf '// v1\n' >> "$WT/src/alfa.cjs"
agente_commita "alfa v1"
integrar 1
igual "1a integracao sai 0" "0" "$RC"
despachar alfa2
printf '// v2 correcao\n' >> "$WT/src/alfa.cjs"
agente_commita "alfa v2"
integrar 1
igual "redespacho sai 0" "0" "$RC"
igual "sem retomada no redespacho" "0" "$(echo "$ERR" | grep -c '^retomada:')"
igual "1 commit novo depois do redespacho" "1" "$(cd "$CX" && git rev-list --count "$BASE..HEAD")"
igual "a correcao chegou" "1" "$(grep -c '^// v2 correcao$' "$CX/src/alfa.cjs")"

echo "== retomada com o worktree do agente presente confere a entrega e segue =="
caixa_nova
abrir_fluxo
despachar presente
printf '// integrada\n' >> "$WT/src/alfa.cjs"
agente_commita "alfa"
VAZIO2="$(mktemp -d)"; SANDBOXES+=("$VAZIO2")
RFM_ESTADO_ROOT="$(cygpath -m "$VAZIO2")" integrar 1
igual "1a chamada sem estado sai 69" "69" "$RC"
integrar 1
igual "retomada com worktree sai 0" "0" "$RC"
igual "stderr diz retomada" "1" "$(echo "$ERR" | grep -c '^retomada:')"
igual "integradas [1] no estado" "[1]" "$(estado_de 'j.executar.integradas')"
igual "worktree do agente removido" "nao" "$([ -e "$WT" ] && echo sim || echo nao)"

echo "== redespacho com --base velha recusa e mantem a correcao =="
caixa_nova
abrir_fluxo
despachar velha1
BASE_VELHA="$BASE"
printf '// v1\n' >> "$WT/src/alfa.cjs"
agente_commita "alfa v1"
integrar 1
igual "1a integracao sai 0" "0" "$RC"
despachar velha2
printf '// v2 correcao\n' >> "$WT/src/alfa.cjs"
agente_commita "alfa v2"
BASE="$BASE_VELHA"
integrar 1
igual "redespacho com base velha sai 2" "2" "$RC"
igual "passo retomada" "retomada" "$(echo "$SAIDA" | J 'j.passo')"
igual "worktree com a correcao continua" "sim" "$([ -e "$WT" ] && echo sim || echo nao)"
igual "a correcao continua no worktree do agente" "1" "$(grep -c '^// v2 correcao$' "$WT/src/alfa.cjs")"

echo "== worktree inexistente sai 69 =="
caixa_nova
abrir_fluxo
despachar sumiu
rm -rf "$WT"
integrar 1
igual "integrar com worktree sumido sai 69" "69" "$RC"
igual "stderr diz nao-verificavel" "1" "$(echo "$ERR" | grep -c '^nao-verificavel:')"
igual "HEAD nao se move" "$HEAD_ANTES" "$(cd "$CX" && git rev-parse HEAD)"

echo "== conferir-fluxo mutacoes --tarefa N mede so a tarefa N =="
caixa_nova
cd "$CX" || exit 1
OUT1="$(node scripts/conferir-fluxo.cjs mutacoes --slug "$SLUG" --tarefa 1 2>/dev/null)"; RC1=$?
igual "tarefa 1 vermelha sai 0" "0" "$RC1"
igual "--tarefa 1 so imprime a tarefa 1" "0" "$(echo "$OUT1" | grep -c '^tarefa 2:')"
OUT2="$(node scripts/conferir-fluxo.cjs mutacoes --slug "$SLUG" --tarefa 2 2>/dev/null)"; RC2=$?
igual "--tarefa 2 imprime a tarefa 2" "1" "$(echo "$OUT2" | grep -c '^tarefa 2:')"
igual "--tarefa 2 nao imprime a tarefa 1" "0" "$(echo "$OUT2" | grep -c '^tarefa 1:')"
igual "--tarefa 2 sobrevivente sai 1" "1" "$RC2"
node scripts/conferir-fluxo.cjs mutacoes --slug "$SLUG" --tarefa 9 >/dev/null 2>"$AUX/e9.txt"; RC9=$?
igual "tarefa inexistente sai 2" "2" "$RC9"
igual "tarefa inexistente nomeia o numero" "1" "$(grep -c 'tarefa 9' "$AUX/e9.txt")"

echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
