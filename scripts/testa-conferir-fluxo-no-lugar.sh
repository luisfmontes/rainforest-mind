#!/bin/bash
# Bateria do campo `no-lugar:` do bloco `mutacao:` em scripts/conferir-fluxo.cjs
# (#527, #569; plano 2026-10-21-mutacao-no-lugar, tarefas 5 e 6).
# Uso: bash scripts/testa-conferir-fluxo-no-lugar.sh
#
# O que precisa provar:
#   F1  `no-lugar: sim` faz a catraca (`mutacoes`) medir na arvore real: a bateria
#       do caso so fica verde no baseline quando o cwd e a raiz real do repo;
#   F2  a mesma tarefa sem o campo passa pela copia e nao sai `vermelho`;
#   C1  `cobertura` recusa `no-lugar:` com valor que nao e `sim`, nomeando a tarefa;
#   C2  `no-lugar: sim` (com crases) passa na `cobertura` sem campo desconhecido.
# Nenhum caso afirma sobre o texto do fonte.
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECADOR="$SRC/scripts/conferir-fluxo.cjs"
OK=0; FALHOU=0
SANDBOXES=()
cleanup() { for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done; }
trap cleanup EXIT
passa() { OK=$((OK + 1)); echo "  ok    $1"; }
falha() { FALHOU=$((FALHOU + 1)); echo "  FALHA $1"; }
mixto() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# novo_repo: S (pasta posix), SM (forma mista) com design, src/x.js, teste e bateria commitados.
novo_repo() {
  S=$(mktemp -d); SANDBOXES+=("$S"); SM=$(mixto "$S")
  mkdir -p "$S/src" "$S/docs/rainforest/design" "$S/docs/rainforest/planos" "$S/tmp"
  printf 'module.exports = (a) => a + 1;\n' > "$S/src/x.js"
  printf "const f = require('./src/x.js');\nif (f(1) !== 2) { console.log('FALHA'); console.log('ok: 0   falhou: 1'); process.exit(1); }\nconsole.log('ok: 1   falhou: 0');\n" > "$S/teste.js"
  cat > "$S/bateria.sh" << 'EOF'
node -e 'const fs=require("fs");const n=p=>fs.realpathSync(p).toLowerCase();process.exit(n(process.cwd())===n(process.env.R_REAL)?0:1)' || { echo 'ok: 0   falhou: 1'; exit 1; }
node teste.js
EOF
  cat > "$S/docs/rainforest/design/t.md" << 'EOF'
# Design

## Objetivo
teste

## Decisões fechadas
- **D1 — teste**

## Avaliado e descartado
teste

## Fora de escopo
teste

## Em aberto
teste
EOF
  git -C "$S" init -q
  git -C "$S" config core.autocrlf false
  git -C "$S" -c user.name=t -c user.email=t@t add -A
  git -C "$S" -c user.name=t -c user.email=t@t commit -qm base
}

# plano <linha extra do bloco mutacao ou vazio>
plano() {
  {
    echo '# Plano'
    echo
    echo '### 1. Tarefa [tipo: implementar]'
    echo 'atende: D1'
    echo 'arquivos: `src/x.js`'
    echo 'depende de: nenhuma'
    echo 'prova-na-base: verde — fixture de bateria'
    echo 'mutacao:'
    echo '  arquivo: `src/x.js`'
    echo '  de: `a + 1`'
    echo '  para: `a + 2`'
    echo '  bateria: `bash bateria.sh`'
    echo '  fixture: `bateria.sh`'
    [ -n "$1" ] && echo "  $1"
    echo 'pronto quando: com `x(1)`, sai 2 — provado por `node teste.js` devolvendo `ok`'
  } > "$S/docs/rainforest/planos/t.md"
}

chk() {
  TMPDIR="$SM/tmp" TEMP="$SM/tmp" TMP="$SM/tmp" R_REAL="$SM" RFM_ESTADO_ROOT="$SM" \
    node "$CHECADOR" "$@" --slug t > "$S/saida.txt" 2>&1 < /dev/null
  echo $?
}

echo "== F1: no-lugar: sim mede na arvore real =="
novo_repo; plano 'no-lugar: sim'
EX=$(chk mutacoes)
if grep -q 'tarefa 1: vermelho' "$S/saida.txt"; then passa "F1 tarefa 1: vermelho (exit $EX)"; else falha "F1 sem 'tarefa 1: vermelho': $(tr '\n' ' ' < "$S/saida.txt" | head -c 600)"; fi
[ "$EX" = "0" ] && passa "F1 mutacoes sai 0" || falha "F1 mutacoes saiu $EX"
if [ "$(git -C "$S" status --porcelain -- src/x.js)" = "" ]; then passa "F1 src/x.js limpo depois"; else falha "F1 src/x.js ficou sujo"; fi

echo "== F2: sem o campo, a copia nao mede essa bateria =="
novo_repo; plano ''
EX=$(chk mutacoes)
if grep -q 'tarefa 1: vermelho' "$S/saida.txt"; then falha "F2 saiu vermelho pela copia"; else passa "F2 nao sai vermelho (exit $EX)"; fi
[ "$EX" != "0" ] && passa "F2 mutacoes sai != 0" || falha "F2 mutacoes saiu 0"

echo "== F3: falha de restauracao no lugar chega ao mutacoes com o motivo e o backup =="
novo_repo; plano 'no-lugar: sim'
cat > "$S/bateria.sh" << 'EOF'
node -e 'const fs=require("fs");const t=fs.readFileSync("src/x.js","utf8");if(t.includes("a + 2")&&!t.includes("EDICAO"))fs.appendFileSync("src/x.js","// EDICAO\n")'
node teste.js
EOF
EX=$(chk mutacoes)
[ "$EX" != "0" ] && passa "F3 mutacoes sai != 0 ($EX)" || falha "F3 mutacoes saiu 0"
if grep -q 'FALHA AO RESTAURAR' "$S/saida.txt" && grep -q 'backup' "$S/saida.txt"; then passa "F3 a linha da tarefa traz FALHA AO RESTAURAR e o backup"; else falha "F3 motivo: $(tr '\n' ' ' < "$S/saida.txt" | head -c 600)"; fi

echo "== C1: no-lugar com valor que nao e sim recusa na cobertura =="
novo_repo; plano 'no-lugar: talvez'
EX=$(chk cobertura)
[ "$EX" != "0" ] && passa "C1 cobertura sai != 0 ($EX)" || falha "C1 cobertura saiu 0"
if grep -q 'tarefa 1' "$S/saida.txt" && grep -q 'talvez' "$S/saida.txt"; then passa "C1 nomeia a tarefa e o valor"; else falha "C1 mensagem: $(tr '\n' ' ' < "$S/saida.txt" | head -c 600)"; fi

echo "== C2: no-lugar: sim passa na cobertura =="
novo_repo; plano 'no-lugar: `sim`'
EX=$(chk cobertura)
[ "$EX" = "0" ] && passa "C2 cobertura sai 0" || falha "C2 cobertura saiu $EX: $(tr '\n' ' ' < "$S/saida.txt" | head -c 600)"
if grep -qi 'desconhecid' "$S/saida.txt"; then falha "C2 acusou campo desconhecido"; else passa "C2 sem campo desconhecido"; fi

echo
echo "-----------------------------------------"
echo "ok: $OK   falhou: $FALHOU"
[ "$FALHOU" -eq 0 ] && echo "== resultado: $OK ok, 0 falha(s) ==" || echo "== resultado: $OK ok, $FALHOU falha(s) =="
[ "$FALHOU" -eq 0 ]
