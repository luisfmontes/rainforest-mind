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

# Chega ao 'plano' ok e 'design' aprovado (sem 'executar'), para o 'executar ok' do D4.
ate_plano() {
  node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));j.design={...j.design,status:"aprovado"};j.plano={...j.plano,status:"ok"};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
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

echo "-- (e) verificar ok com --raiz noutra arvore nao grava head e o fechar nao tranca --"
# A outra arvore e worktree do MESMO repo (objetos compartilhados), como o PR para
# upstream do --raiz: o HEAD dela existe aqui, e o diff contra ele acusaria o codigo
# da branch do estado para sempre.
caixa_nova
mkdir -p "$CX/src" && printf 'x\n' > "$CX/src/a.js"
git -C "$CX" add -- src/a.js
git -C "$CX" commit -q -m "codigo da branch do estado"
OUTRA="$(mktemp -d)/wt"; SANDBOXES+=("$(dirname "$OUTRA")")
git -C "$CX" worktree add -q -b outra "$OUTRA" main
printf 'y\n' > "$OUTRA/b.js"
git -C "$OUTRA" add -- b.js
git -C "$OUTRA" commit -q -m "codigo na outra arvore"
node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));j.design={...j.design,status:"aprovado"};j.plano={...j.plano,status:"ok"};j.executar={...j.executar,status:"ok"};j.revisar={...j.revisar,status:"ok"};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
esperado "marcar verificar ok com --raiz sai 0" 0 $E marcar --slug "$SLUG" --estagio verificar --status ok --raiz "$OUTRA" --json '{"comando":"bash scripts/testa-estado-reabrir.sh","saida":"ok: 1   falhou: 0"}'
igual "verificar.head ausente com --raiz" "null" "$(J 'j.verificar.head' < "$ARQ")"
esperado "exigir fechar depois de verificar com --raiz sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (f) trazer a main depois do verificar nao acusa o que veio dela --"
caixa_nova
fechar_ate_verificar
git -C "$CX" checkout -q main
mkdir -p "$CX/lib" && printf 'da main\n' > "$CX/lib/m.js"
git -C "$CX" add -- lib/m.js
git -C "$CX" commit -q -m "outro PR na main"
git -C "$CX" push -q origin main
git -C "$CX" checkout -q fluxo/x
git -C "$CX" merge -q --no-edit main
igual "lib/m.js chegou pela main" "1" "$(git -C "$CX" ls-files lib/m.js | grep -c 'lib/m.js')"
esperado "exigir fechar depois de trazer a main sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar
mkdir -p "$CX/src" && printf 'x\n' > "$CX/src/a.js"
git -C "$CX" add -- src/a.js
git -C "$CX" commit -q -m "codigo da branch depois do merge"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "codigo da branch depois do merge sai 2" "2" "$rc"
igual "saida nomeia src/a.js" "1" "$(echo "$saida" | grep -c 'src/a.js')"
igual "saida nao nomeia lib/m.js" "0" "$(echo "$saida" | grep -c 'lib/m.js')"

echo "-- (g) edicao de codigo nao commitada depois do verificar sai 2 --"
caixa_nova
mkdir -p "$CX/src" && printf 'x\n' > "$CX/src/a.js"
git -C "$CX" add -- src/a.js
git -C "$CX" commit -q -m "codigo antes do verificar"
fechar_ate_verificar
printf 'y\n' >> "$CX/src/a.js"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "src/a.js sujo depois do verificar sai 2" "2" "$rc"
igual "saida nomeia src/a.js sujo" "1" "$(echo "$saida" | grep -c 'src/a.js')"
printf 'z\n' > "$CX/solto.txt"
git -C "$CX" checkout -q -- src/a.js
esperado "arquivo nao rastreado nao conta" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (g2) nome com espaco sujo numa pasta isenta nao conta; fora dela sai sem aspas --"
caixa_nova
mkdir -p "$CX/relatorios" "$CX/src" && printf 'r\n' > "$CX/relatorios/meu rel.md" && printf 'x\n' > "$CX/src/a b.js"
git -C "$CX" add -- "relatorios/meu rel.md" "src/a b.js"
git -C "$CX" commit -q -m "arquivos com espaco antes do verificar"
fechar_ate_verificar
printf 's\n' >> "$CX/relatorios/meu rel.md"
esperado "relatorios/meu rel.md sujo (isento) sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar
printf 'y\n' >> "$CX/src/a b.js"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "src/a b.js sujo sai 2" "2" "$rc"
igual "saida nomeia src/a b.js sem aspas" "1" "$(echo "$saida" | grep -c '^  src/a b.js$')"

echo "-- (h) estado de outro slug commitado depois do verificar nao reabre --"
caixa_nova
fechar_ate_verificar
printf '{"slug":"2026-10-18-outro"}\n' > "$CX/docs/rainforest/estado/2026-10-18-outro.json"
git -C "$CX" add -- docs/rainforest/estado/2026-10-18-outro.json
git -C "$CX" commit -q -m "fechar ok do fluxo anterior"
esperado "exigir fechar com estado de outro slug sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (i) emenda 2: marcar fechar ok tambem recusa codigo depois do verificar --"
caixa_nova
fechar_ate_verificar
esperado "exigir fechar antes do conserto sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar
mkdir -p "$CX/src" && printf 'x\n' > "$CX/src/a.js"
git -C "$CX" add -- src/a.js
git -C "$CX" commit -q -m "conserto de CI depois do exigir"
saida=$($E marcar --slug "$SLUG" --estagio fechar --status ok --json '{"acao":"merge"}' 2>&1); rc=$?
igual "marcar fechar ok com codigo depois do verificar sai 2" "2" "$rc"
igual "marcar fechar ok nomeia src/a.js" "1" "$(echo "$saida" | grep -c '^  src/a.js$')"
igual "fechar segue nao-ok no JSON" "1" "$(J 'j.fechar&&j.fechar.status==="ok"?0:1' < "$ARQ")"

echo "-- (j) emenda 2: verificar ok refeito sobre codigo que o revisar nao viu sai 2 --"
caixa_nova
node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));j.design={...j.design,status:"aprovado"};j.plano={...j.plano,status:"ok"};j.executar={...j.executar,status:"ok"};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
esperado "exigir revisar tira o instantaneo" 0 $E exigir --slug "$SLUG" --estagio revisar
node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));j.revisar={...j.revisar,status:"ok"};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
mkdir -p "$CX/src" && printf 'x\n' > "$CX/src/a.js"
git -C "$CX" add -- src/a.js
git -C "$CX" commit -q -m "codigo depois da revisao"
saida=$($E marcar --slug "$SLUG" --estagio verificar --status ok --json '{"comando":"bash scripts/testa-estado-reabrir.sh","saida":"ok: 1   falhou: 0"}' 2>&1); rc=$?
igual "verificar ok com codigo depois do revisar sai 2" "2" "$rc"
igual "saida cita o revisar e src/a.js" "2" "$(echo "$saida" | grep -cE "depois do 'revisar'|^  src/a.js$")"
esperado "reabrir destrava o caminho" 0 $E reabrir --slug "$SLUG" --estagio executar --motivo "codigo depois da revisao"

echo "-- (k) emenda 2: branch e main mexem no mesmo arquivo em linhas distantes --"
caixa_nova
git -C "$CX" checkout -q main
seq 1 30 > "$CX/CHANGELOG.md"
git -C "$CX" add -- CHANGELOG.md
git -C "$CX" commit -q -m "changelog na main"
git -C "$CX" push -q origin main
git -C "$CX" checkout -q fluxo/x
git -C "$CX" merge -q --no-edit main
sed -i '1s/.*/1 da branch/' "$CX/CHANGELOG.md"
git -C "$CX" add -- CHANGELOG.md
git -C "$CX" commit -q -m "changelog da branch"
fechar_ate_verificar
git -C "$CX" checkout -q main
sed -i '30s/.*/30 da main/' "$CX/CHANGELOG.md"
git -C "$CX" add -- CHANGELOG.md
git -C "$CX" commit -q -m "changelog de outro PR"
git -C "$CX" push -q origin main
git -C "$CX" checkout -q fluxo/x
git -C "$CX" merge -q --no-edit main
igual "merge trouxe a linha da main" "1" "$(grep -c '30 da main' "$CX/CHANGELOG.md")"
esperado "exigir fechar com a main no mesmo arquivo sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (l) emenda 2: arquivo da branch apagado depois do verificar sai 2 --"
caixa_nova
mkdir -p "$CX/src" && printf 'n\n' > "$CX/src/n.js"
git -C "$CX" add -- src/n.js
git -C "$CX" commit -q -m "arquivo novo antes do verificar"
fechar_ate_verificar
git -C "$CX" rm -q -- src/n.js
git -C "$CX" commit -q -m "apaga depois do verificar"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "src/n.js apagado depois do verificar sai 2" "2" "$rc"
igual "saida nomeia src/n.js" "1" "$(echo "$saida" | grep -c '^  src/n.js$')"

# Prepara a main com `$2` (conteudo) em `$1` e traz para fluxo/x antes de tudo.
na_main_e_traz() {
  git -C "$CX" checkout -q main
  printf '%s' "$2" > "$CX/$1"
  git -C "$CX" add -- "$1"
  git -C "$CX" commit -q -m "base de $1 na main"
  git -C "$CX" push -q origin main
  git -C "$CX" checkout -q fluxo/x
  git -C "$CX" merge -q --no-edit main
}
# Commit na main de `sed $2` sobre `$1`, push e merge em fluxo/x (sem conflito).
main_muda_e_traz() {
  git -C "$CX" checkout -q main
  sed -i "$2" "$CX/$1"
  git -C "$CX" add -- "$1"
  git -C "$CX" commit -q -m "outro PR muda $1"
  git -C "$CX" push -q origin main
  git -C "$CX" checkout -q fluxo/x
  git -C "$CX" merge -q --no-edit main
}

echo "-- (m) emenda 3: arquivo com diff acima de 1 MiB depois do verificar sai 2 --"
caixa_nova
fechar_ate_verificar
mkdir -p "$CX/src" && node -e 'process.stdout.write("linha de teste grande\n".repeat(80000))' > "$CX/src/grande.js"
git -C "$CX" add -- src/grande.js
git -C "$CX" commit -q -m "arquivo grande depois do verificar"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "src/grande.js de 1,7 MB sai 2" "2" "$rc"
igual "saida nomeia src/grande.js" "1" "$(echo "$saida" | grep -c '^  src/grande.js$')"

echo "-- (n) emenda 3: main muda linha vizinha (2 linhas) da mudanca da branch --"
caixa_nova
na_main_e_traz f.txt "$(seq 1 30)
"
sed -i '5s/.*/5 da branch/' "$CX/f.txt"
git -C "$CX" add -- f.txt
git -C "$CX" commit -q -m "branch muda a linha 5"
fechar_ate_verificar
main_muda_e_traz f.txt '7s/.*/7 da main/'
igual "merge trouxe a linha 7 da main" "1" "$(grep -c '7 da main' "$CX/f.txt")"
esperado "exigir fechar com a main na linha vizinha sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (o) emenda 3: so a indentacao da linha da branch muda depois do verificar --"
caixa_nova
na_main_e_traz s.py "for i in r:
    h(i)
"
sed -i 's/    h(i)/    h2(i)/' "$CX/s.py"
git -C "$CX" add -- s.py
git -C "$CX" commit -q -m "branch troca h por h2"
fechar_ate_verificar
sed -i 's/    h2(i)/h2(i)/' "$CX/s.py"
git -C "$CX" add -- s.py
git -C "$CX" commit -q -m "tira a indentacao"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "indentacao mudada sai 2" "2" "$rc"
igual "saida nomeia s.py" "1" "$(echo "$saida" | grep -c '^  s.py$')"

echo "-- (p) emenda 3: conflito de versao resolvido para o valor da branch --"
caixa_nova
na_main_e_traz p.json '{
  "nome": "x",
  "version": "1.69.1"
}
'
sed -i 's/1.69.1/1.70.0/' "$CX/p.json"
git -C "$CX" add -- p.json
git -C "$CX" commit -q -m "branch sobe para 1.70.0"
fechar_ate_verificar
git -C "$CX" checkout -q main
sed -i 's/1.69.1/1.69.2/' "$CX/p.json"
git -C "$CX" add -- p.json
git -C "$CX" commit -q -m "main publica 1.69.2"
git -C "$CX" push -q origin main
git -C "$CX" checkout -q fluxo/x
git -C "$CX" merge -q --no-edit main >/dev/null 2>&1
git -C "$CX" checkout -q --ours -- p.json
git -C "$CX" add -- p.json
git -C "$CX" commit -q --no-edit
igual "merge resolvido com 1.70.0" "1" "$(grep -c '1.70.0' "$CX/p.json")"
esperado "exigir fechar com conflito resolvido para a branch sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (q) emenda 3: exigir fechar numa arvore com o squash da branch na main --"
caixa_nova
mkdir -p "$CX/src" && printf 'x\n' > "$CX/src/a.js"
git -C "$CX" add -- src/a.js
git -C "$CX" commit -q -m "codigo da branch"
fechar_ate_verificar
git -C "$CX" checkout -q main
git -C "$CX" merge -q --squash fluxo/x
git -C "$CX" commit -q -m "squash do PR"
git -C "$CX" push -q origin main
esperado "exigir fechar com o squash na main sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (r) emenda 3: git mv de codigo para pasta isenta, sem commit, sai 2 --"
caixa_nova
mkdir -p "$CX/src" "$CX/relatorios" && printf 'x\n' > "$CX/src/a.js"
git -C "$CX" add -- src/a.js
git -C "$CX" commit -q -m "codigo antes do verificar"
fechar_ate_verificar
git -C "$CX" mv src/a.js relatorios/a.js
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "git mv para relatorios/ sai 2" "2" "$rc"
igual "saida nomeia o nome antigo src/a.js" "1" "$(echo "$saida" | grep -c '^  src/a.js$')"

echo "-- (s) emenda 3: marcar fechar ok sem verificar.head avisa --"
caixa_nova
fechar_ate_verificar
node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));delete j.verificar.head;fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
saida=$($E marcar --slug "$SLUG" --estagio fechar --status ok --json '{"acao":"merge"}' 2>&1); rc=$?
igual "marcar fechar ok sem head sai 0" "0" "$rc"
igual "marcar fechar ok sem head avisa" "1" "$(echo "$saida" | grep -c "verificar' sem HEAD gravado")"

echo "-- (t) emenda 4: com a main parada, a mesma linha mudada de lugar sai 2 --"
caixa_nova
mkdir -p "$CX/src" && printf '[a]\nretries = 3\n[b]\nretries = 3\n' > "$CX/src/cfg.txt"
git -C "$CX" add -- src/cfg.txt
git -C "$CX" commit -q -m "cfg com dois blocos"
git -C "$CX" push -q origin fluxo/x:main
git -C "$CX" fetch -q origin
sed -i '2s/3/5/' "$CX/src/cfg.txt"
git -C "$CX" add -- src/cfg.txt
git -C "$CX" commit -q -m "branch muda o bloco a"
fechar_ate_verificar
printf '[a]\nretries = 3\n[b]\nretries = 5\n' > "$CX/src/cfg.txt"
git -C "$CX" add -- src/cfg.txt
git -C "$CX" commit -q -m "conserto troca o bloco"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "mudanca de bloco com a main parada sai 2" "2" "$rc"
igual "saida nomeia src/cfg.txt" "1" "$(echo "$saida" | grep -c '^  src/cfg.txt$')"

echo "-- (u) emenda 4: git mv commitado de codigo da main para pasta isenta sai 2 --"
caixa_nova
na_main_e_traz a.js 'x
'
fechar_ate_verificar
mkdir -p "$CX/relatorios"
git -C "$CX" mv a.js relatorios/a.js
git -C "$CX" commit -q -m "move para relatorios"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "git mv commitado para relatorios/ sai 2" "2" "$rc"
igual "saida nomeia o nome antigo a.js" "1" "$(echo "$saida" | grep -c '^  a.js$')"

echo "-- (v) emenda 4: patch da branch acima de 1 MiB com a main mexendo longe no arquivo sai 0 --"
caixa_nova
na_main_e_traz g.txt "$(seq 1 10)
"
node -e 'process.stdout.write("linha de teste grande\n".repeat(80000))' >> "$CX/g.txt"
git -C "$CX" add -- g.txt
git -C "$CX" commit -q -m "branch acrescenta 1,7 MB ao fim"
igual "g.txt passou de 1 MiB" "1" "$([ "$(wc -c < "$CX/g.txt")" -gt 1048576 ] && echo 1 || echo 0)"
fechar_ate_verificar
main_muda_e_traz g.txt '1s/.*/primeira da main/'
igual "merge trouxe a primeira linha da main" "1" "$(head -1 "$CX/g.txt" | grep -c 'primeira da main')"
esperado "exigir fechar com a main no arquivo grande sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar

echo "-- (w) emenda 4: estado do fluxo numa subpasta do repositorio --"
caixa_nova
SUP="$(mktemp -d)"; SANDBOXES+=("$SUP")
mkdir -p "$SUP/proj" && cp -r "$CX/." "$SUP/proj/" && rm -rf "$SUP/proj/.git"
git -C "$SUP" init -q -b main
git -C "$SUP" config user.email "teste@exemplo.invalid"
git -C "$SUP" config user.name "teste"
git -C "$SUP" add -- proj
git -C "$SUP" commit -q -m "projeto na subpasta"
git -C "$SUP" remote add origin "$ORIG/origin.git"
git -C "$SUP" push -q -f origin main
git -C "$SUP" checkout -q -b fluxo/x
export RFM_ESTADO_ROOT="$(cygpath -m "$SUP/proj" 2>/dev/null || printf '%s' "$SUP/proj")"
cd "$SUP/proj" || exit 1
fechar_ate_verificar
esperado "subpasta: estado rastreado e sujo nao conta" 0 $E exigir --slug "$SLUG" --estagio fechar
mkdir -p "$SUP/proj/src" && printf 'x\n' > "$SUP/proj/src/a.js"
git -C "$SUP" add -- proj/src/a.js
git -C "$SUP" commit -q -m "codigo depois do verificar"
saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
igual "subpasta: codigo depois do verificar sai 2" "2" "$rc"
igual "subpasta: saida nomeia src/a.js" "1" "$(echo "$saida" | grep -c '^  src/a.js$')"

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

echo "== D4: de que nao casa =="

# Plano com uma tarefa cujo bloco `mutacao:` e o argumento (linhas cruas, aspas simples).
plano_com() {
  {
    printf '# Plano: teste de D4\n\n## Tarefas\n\n### 1. Primeira [tipo: implementar]\n'
    printf 'arquivos: `src/a.js`\ndepende de: nenhuma\nprova: `true`\n'
    printf '%s\n' "$1"
  } > "$CX/docs/rainforest/planos/$SLUG.md"
}
JSON_OK='{"comando":"bash scripts/testa-estado-reabrir.sh","saida":"ok: 1   falhou: 0","tarefas_ok":1,"tarefas":1,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caixa de teste"}]}'

echo "-- (a) de: que nao casa no fonte: marcar executar ok sai 2, nomeia tarefa e arquivo --"
caixa_nova
mkdir -p "$CX/src" && printf 'const x = 1;\n' > "$CX/src/a.js"
plano_com 'mutacao:
  arquivo: `src/a.js`
  de: trecho que nao existe
  para: x
  bateria: `bash scripts/testa-estado-reabrir.sh`'
ate_plano
esperado "exigir executar arma a catraca sai 0" 0 $E exigir --slug "$SLUG" --estagio executar
antes="$(soma)"
saida=$($E marcar --slug "$SLUG" --estagio executar --status ok --json "$JSON_OK" 2>&1); rc=$?
igual "marcar executar ok com de: que nao casa sai 2" "2" "$rc"
igual "saida nomeia tarefa 1 e src/a.js" "1" "$(echo "$saida" | grep -c 'tarefa 1: de: nao casa em src/a.js')"
igual "de: que nao casa: JSON intacto" "$antes" "$(soma)"

echo "-- (b) de: que aparece no fonte: marcar executar ok sai 0 --"
caixa_nova
mkdir -p "$CX/src" && printf 'const x = 1;\n' > "$CX/src/a.js"
plano_com 'mutacao:
  arquivo: `src/a.js`
  de: const x = 1;
  para: const x = 2;
  bateria: `bash scripts/testa-estado-reabrir.sh`'
ate_plano
esperado "exigir executar arma a catraca sai 0" 0 $E exigir --slug "$SLUG" --estagio executar
esperado "marcar executar ok com de: que casa sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status ok --json "$JSON_OK"
igual "executar.status = ok" "ok" "$(J 'j.executar.status' < "$ARQ")"

echo "-- (c) mutacao: n/a e arquivo: inexistente nao recusam --"
caixa_nova
plano_com 'mutacao: n/a
motivo: tarefa so de docs'
ate_plano
esperado "exigir executar arma a catraca (n/a) sai 0" 0 $E exigir --slug "$SLUG" --estagio executar
esperado "marcar executar ok com mutacao n/a sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status ok --json "$JSON_OK"
caixa_nova
plano_com 'mutacao:
  arquivo: `src/nao-existe.js`
  de: x
  para: y
  bateria: `bash scripts/testa-estado-reabrir.sh`'
ate_plano
esperado "exigir executar arma a catraca (inexistente) sai 0" 0 $E exigir --slug "$SLUG" --estagio executar
esperado "marcar executar ok com arquivo inexistente sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status ok --json "$JSON_OK"
caixa_nova
mkdir -p "$CX/src/pasta" && printf 'x\n' > "$CX/src/pasta/f.js"
plano_com 'mutacao:
  arquivo: `src/pasta`
  de: x
  para: y
  bateria: `bash scripts/testa-estado-reabrir.sh`'
ate_plano
esperado "exigir executar arma a catraca (diretorio) sai 0" 0 $E exigir --slug "$SLUG" --estagio executar
esperado "marcar executar ok com arquivo: sendo diretorio sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status ok --json "$JSON_OK"

echo "== D5: raiz por junction (#578) =="

# Cria a junction $2 apontando para $1 (mklink /J; ln -s fora do Windows). Falha = FALHA, nunca pula.
junction_pronta() {
  if command -v cygpath >/dev/null 2>&1; then
    MSYS2_ARG_CONV_EXCL="*" cmd /c mklink /J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null 2>&1
  else
    ln -s "$1" "$2"
  fi
  [ -d "$2" ]
}
# Remove so o link (rmdir sem /s num junction nao toca o alvo).
desfaz_junction() {
  if command -v cygpath >/dev/null 2>&1; then
    MSYS2_ARG_CONV_EXCL="*" cmd /c rmdir "$(cygpath -w "$1")" >/dev/null 2>&1
  else
    rm -f "$1"
  fi
}
# Caixa nova com design e plano commitados, estado declarando plano.doc ($1) e design.doc,
# raiz por junction e verificar ok. Devolve 1 se a junction nao for criada.
caixa_d5() {
  caixa_nova
  mkdir -p "$CX/docs/rainforest/design" && printf '# Design de teste\n' > "$CX/docs/rainforest/design/$SLUG.md"
  git -C "$CX" add -- "docs/rainforest/design/$SLUG.md" "docs/rainforest/planos/$SLUG.md"
  git -C "$CX" commit -q -m "design e plano do slug"
  node -e 'const fs=require("fs");const [f,p,d]=process.argv.slice(1);const j=JSON.parse(fs.readFileSync(f,"utf8"));j.plano={...j.plano,doc:p};j.design={...j.design,doc:d};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ" "$1" "docs/rainforest/design/$SLUG.md"
  JP="$(mktemp -u)"
  junction_pronta "$CX" "$JP" || return 1
  export RFM_ESTADO_ROOT="$(cygpath -m "$JP" 2>/dev/null || printf '%s' "$JP")"
  fechar_ate_verificar
}

echo "-- (a) commit so no plano depois do verificar ok com a raiz numa junction: exigir fechar sai 0 --"
if caixa_d5 "docs/rainforest/planos/$SLUG.md"; then
  printf '\n- nota depois do verificar\n' >> "$CX/docs/rainforest/planos/$SLUG.md"
  git -C "$CX" add -- "docs/rainforest/planos/$SLUG.md"
  git -C "$CX" commit -q -m "so plano depois do verificar"
  esperado "junction: exigir fechar com commit so no plano sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar
else
  falhou=$((falhou+1)); echo "  FALHA junction (a): nao consegui criar a junction da raiz"
fi
desfaz_junction "$JP"

echo "-- (b) commit de codigo depois do verificar ok com a raiz numa junction: exigir fechar sai diferente de 0 --"
if caixa_d5 "docs/rainforest/planos/$SLUG.md"; then
  mkdir -p "$CX/scripts" && printf 'x\n' > "$CX/scripts/x.cjs"
  git -C "$CX" add -- scripts/x.cjs
  git -C "$CX" commit -q -m "codigo depois do verificar"
  saida=$($E exigir --slug "$SLUG" --estagio fechar 2>&1); rc=$?
  igual "junction: exigir fechar com scripts/x.cjs sai diferente de 0" "1" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
  igual "junction: recusa de codigo depois do verificar ok" "1" "$(echo "$saida" | grep -c "depois do 'verificar ok'")"
  igual "junction: saida nomeia scripts/x.cjs" "1" "$(echo "$saida" | grep -c 'scripts/x.cjs')"
else
  falhou=$((falhou+1)); echo "  FALHA junction (b): nao consegui criar a junction da raiz"
fi
desfaz_junction "$JP"

echo "-- (c) plano.doc por link dentro da raiz apontando para fora da raiz: nao e adotado --"
OUTD="$(mktemp -d)"; SANDBOXES+=("$OUTD")
printf '# plano externo\n' > "$OUTD/plano.md"
if caixa_d5 "docs/rainforest/planos/$SLUG.md"; then
  LINK="$CX/docs/rainforest/externo"
  if junction_pronta "$OUTD" "$LINK"; then
    node -e 'const fs=require("fs");const f=process.argv[1];const j=JSON.parse(fs.readFileSync(f,"utf8"));j.plano={...j.plano,doc:"docs/rainforest/externo/plano.md"};fs.writeFileSync(f,JSON.stringify(j,null,2));' "$ARQ"
    printf '\n- nota depois do verificar\n' >> "$CX/docs/rainforest/planos/$SLUG.md"
    git -C "$CX" add -- "docs/rainforest/planos/$SLUG.md"
    git -C "$CX" commit -q -m "so plano padrao depois do verificar"
    esperado "plano.doc externo por link nao adotado: commit so no plano padrao sai 0" 0 $E exigir --slug "$SLUG" --estagio fechar
    desfaz_junction "$LINK"
  else
    falhou=$((falhou+1)); echo "  FALHA junction (c): nao consegui criar o link para fora da raiz"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA junction (c): nao consegui criar a junction da raiz"
fi
desfaz_junction "$JP"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
