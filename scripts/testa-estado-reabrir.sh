#!/bin/bash
# Bateria da trava de codigo depois do `verificar ok` (D1, D2, D5, D6 do design
# 2026-10-19-estado-reabrir, #567) do scripts/estado.cjs.
# Uso: bash scripts/testa-estado-reabrir.sh
#
# Cada cenario roda numa caixa nova (mktemp -d, fora do worktree): repo git com
# `origin` bare, branch fluxo/x, plano e o fluxo aberto. O `estado.cjs` que roda e a
# copia real; cada caso confere o JSON gravado em disco (`docs/rainforest/estado/`)
# e a saida real do `exigir`, nunca o texto do fonte. Recusa conferida pelo exit.
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
SLUG=2026-10-19-reabrir-teste

igual() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi
}
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}

# J <expressao>: le JSON da entrada padrao e imprime a expressao sobre `j`.
J() {
  node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));const v=(new Function("j","return "+process.argv[1]))(j);console.log(typeof v==="string"?v:JSON.stringify(v===undefined?null:v));' "$1"
}

# Cria uma caixa nova com o fluxo aberto (design e plano ainda pendentes).
caixa_nova() {
  CX="$(mktemp -d)"; SANDBOXES+=("$CX")
  ORIG="$(mktemp -d)"; SANDBOXES+=("$ORIG")
  W="$(cygpath -m "$CX" 2>/dev/null || printf '%s' "$CX")"
  export HOME="$CX/casa" USERPROFILE="$CX/casa" CLAUDE_CONFIG_DIR="$CX/casa/.claude-personal"
  mkdir -p "$HOME" "$CX/scripts/lib" "$CX/hooks/lib" "$CX/docs/rainforest/planos" "$CX/docs/rainforest/estado"
  cp "$SRC/scripts/estado.cjs" "$SRC/scripts/conferir-fluxo.cjs" "$CX/scripts/"
  cp "$SRC/scripts/lib/camadas.cjs" "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SRC/scripts/lib/extrair-veredito.cjs" "$CX/scripts/lib/"
  for lib in raiz config trava-jsonl pastas-docs resolver-executavel contar-ocorrencias caminho-leve teto-despachos; do
    cp "$SRC/hooks/lib/$lib.cjs" "$CX/hooks/lib/"
  done
  touch "$CX/FOCO.md"
  mkdir -p "$CX/.rainforest" && printf '{"principal-livre": true}
' > "$CX/.rainforest/config.json"   # a caixa e um clone dedicado em fluxo/x
  export RFM_ESTADO_ROOT="$W"

  git init -q --bare "$ORIG/origin.git"
  git -C "$CX" init -q -b main
  git -C "$CX" config user.email "teste@exemplo.invalid"
  git -C "$CX" config user.name "teste"
  git -C "$CX" remote add origin "$ORIG/origin.git"
  printf '# teste\n' > "$CX/LEIA.md"
  git -C "$CX" add -- LEIA.md
  git -C "$CX" commit -q -m "base"
  git -C "$CX" push -q origin main
  git -C "$CX" checkout -q -b fluxo/x

  cat > "$CX/docs/rainforest/planos/$SLUG.md" <<'EOF'
# Plano: teste de reabrir

## Tarefas

### 1. Primeira [tipo: implementar]
arquivos: `src/a.js`
depende de: nenhuma
prova: `true`
EOF

  cd "$CX" || exit 1
  $E iniciar --slug "$SLUG" >/dev/null 2>"$CX/err.txt" || { echo "FALHA preparo: iniciar"; cat "$CX/err.txt"; exit 1; }
}

E="node scripts/estado.cjs"
ARQ="docs/rainforest/estado/$SLUG.json"

# Chega aos pre-requisitos do `fechar` gravando os blocos anteriores no JSON
# (design, plano, executar e revisar fechados) e fecha o `verificar` pelo `marcar` real.
fechar_ate_verificar() {
  node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));j.design={...j.design,status:"aprovado"};j.plano={...j.plano,status:"ok"};j.executar={...j.executar,status:"ok"};j.revisar={...j.revisar,status:"ok"};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
  $E marcar --slug "$SLUG" --estagio verificar --status ok --json '{"comando":"bash scripts/testa-estado-reabrir.sh","saida":"ok: 1   falhou: 0"}' >/dev/null 2>"$CX/err.txt" || { echo "FALHA preparo: marcar verificar ok"; cat "$CX/err.txt"; exit 1; }
}

# Chega ao 'revisar' ok gravando os blocos anteriores no JSON (sem o 'verificar').
ate_revisar() {
  node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));j.design={...j.design,status:"aprovado"};j.plano={...j.plano,status:"ok"};j.executar={...j.executar,status:"ok"};j.revisar={...j.revisar,status:"ok"};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
}

# Soma de verificacao do JSON em disco: as recusas do D3 nao podem tocar nele.
soma() { cksum < "$ARQ" | cut -d' ' -f1; }

echo "== D1: commit de codigo depois do verificar ok =="

echo "-- (a) marcar verificar ok grava o HEAD --"
caixa_nova
fechar_ate_verificar
igual "verificar.head no JSON = HEAD da caixa" "$(git -C "$CX" rev-parse HEAD)" "$(J 'j.verificar.head' < "$ARQ")"
esperado "exigir fechar sem commit depois do verificar sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (b) commit de codigo depois do verificar sai 2 e nomeia o arquivo --"
caixa_nova
fechar_ate_verificar
mkdir -p "$CX/src" && printf 'x\n' > "$CX/src/a.js"
git -C "$CX" add -- src/a.js
git -C "$CX" commit -q -m "conserto de CI"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "exigir fechar com src/a.js depois do verificar sai 2" "2" "$rc"
igual "saida nomeia src/a.js" "1" "$(echo "$saida" | grep -c 'src/a.js')"
igual "saida cita reabrir" "1" "$(echo "$saida" | grep -c 'reabrir --slug')"

echo "-- (c) commit so de estado, design ou plano do slug nao reabre --"
caixa_nova
fechar_ate_verificar
printf '\n- nota depois do verificar\n' >> "$CX/docs/rainforest/planos/$SLUG.md"
git -C "$CX" add -- "docs/rainforest/estado/$SLUG.json" "docs/rainforest/planos/$SLUG.md"
git -C "$CX" commit -q -m "so estado e plano"
esperado "exigir fechar com commit so de estado e plano sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (d) estado sem verificar.head: commit de codigo so avisa --"
caixa_nova
fechar_ate_verificar
node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));delete j.verificar.head;fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
mkdir -p "$CX/src" && printf 'x\n' > "$CX/src/a.js"
git -C "$CX" add -- src/a.js
git -C "$CX" commit -q -m "codigo sem head gravado"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "exigir fechar sem verificar.head sai 0" "0" "$rc"
igual "aviso em stderr sobre verificar sem HEAD" "1" "$(echo "$saida" | grep -c "verificar' sem HEAD gravado")"

echo "== D3: reabrir =="

echo "-- (a) com revisar ok, reabrir volta executar e revisar --"
caixa_nova
ate_revisar
esperado "reabrir com revisar ok sai 0" 0 $E reabrir --slug "$SLUG" --estagio executar --motivo "achado A"
igual "executar.status = parcial" "parcial" "$(J 'j.executar.status' < "$ARQ")"
igual "revisar.status = pendente" "pendente" "$(J 'j.revisar.status' < "$ARQ")"
igual "reaberturas[0].motivo = achado A" "achado A" "$(J 'j.reaberturas[0].motivo' < "$ARQ")"
igual "reaberturas[0].de = revisar" "revisar" "$(J 'j.reaberturas[0].de' < "$ARQ")"
igual "reaberturas[0] com data" "1" "$(J 'j.reaberturas[0].em.length>0?1:0' < "$ARQ")"

echo "-- (b) com verificar e fechar ok, reabrir deixa os tres pendentes --"
caixa_nova
fechar_ate_verificar
node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));j.fechar={...j.fechar,status:"ok"};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
esperado "reabrir com fechar ok sai 0" 0 $E reabrir --slug "$SLUG" --estagio executar --motivo "CI vermelho"
igual "revisar|verificar|fechar pendentes" "pendente|pendente|pendente" "$(J '[j.revisar.status,j.verificar.status,j.fechar.status].join("|")' < "$ARQ")"
igual "reaberturas[0].de = fechar" "fechar" "$(J 'j.reaberturas[0].de' < "$ARQ")"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "exigir fechar logo depois do reabrir sai 2" "2" "$rc"

echo "-- (c) depois do reabrir, executar volta a valer --"
caixa_nova
ate_revisar
$E reabrir --slug "$SLUG" --estagio executar --motivo "achado A" >/dev/null 2>&1
esperado "exigir executar depois do reabrir sai 0" 0 $E exigir --slug "$SLUG" --estagio executar
esperado "marcar executar ok depois do reabrir sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status ok --json '{"comando":"bash scripts/testa-estado-reabrir.sh","saida":"ok: 1   falhou: 0","tarefas_ok":1,"tarefas":1,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caixa de teste"}]}'
igual "executar.status = ok de novo" "ok" "$(J 'j.executar.status' < "$ARQ")"

echo "-- (d) recusas saem 2 e o JSON fica igual --"
caixa_nova
ate_revisar
antes="$(soma)"
$E reabrir --slug "$SLUG" --estagio executar --motivo "" >/dev/null 2>&1; rc=$?
igual "motivo vazio sai 2" "2" "$rc"
igual "motivo vazio: JSON intacto" "$antes" "$(soma)"
$E reabrir --slug "$SLUG" --estagio revisar --motivo "x" >/dev/null 2>&1; rc=$?
igual "estagio revisar sai 2" "2" "$rc"
igual "estagio revisar: JSON intacto" "$antes" "$(soma)"
caixa_nova
node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));j.design={...j.design,status:"aprovado"};j.plano={...j.plano,status:"ok"};j.executar={...j.executar,status:"parcial"};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
antes="$(soma)"
$E reabrir --slug "$SLUG" --estagio executar --motivo "x" >/dev/null 2>&1; rc=$?
igual "executar em parcial (nada a reabrir) sai 2" "2" "$rc"
igual "nada a reabrir: JSON intacto" "$antes" "$(soma)"
$E reabrir --slug 2026-10-19-nao-existe --estagio executar --motivo "x" >/dev/null 2>&1; rc=$?
igual "slug inexistente sai 1 (convencao do estado.cjs para slug sem estado)" "1" "$rc"

echo "-- (e) marcar executar parcial com revisar ok segue recusado (#238) --"
caixa_nova
ate_revisar
esperado "marcar executar parcial com revisar ok sai 2" 2 $E marcar --slug "$SLUG" --estagio executar --status parcial

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
