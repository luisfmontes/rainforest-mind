#!/bin/bash
# Bateria da busca por janela de datas do scripts/memoria.cjs (`buscar --desde/--ate`, D6).
# Uso: bash scripts/testa-memoria-janela.sh
#
# Caixa de areia: o banco vive em RFM_ROOT=<mktemp -d>, nunca em ~/.rainforest. Três
# observações com criada_em em 2026-10-01, 2026-10-10 e 2026-10-20 (marcas ALFA, BETA, GAMA).
# Casos, nesta ordem:
#   1. --desde/--ate excluem a observação fora da janela
#   2. --desde é inclusivo na data exata
#   3. --texto combina com --desde/--ate
#   4. data fora do formato ou impossível sai exit 2 com AAAA-MM-DD no stderr
#   5. sem --desde/--ate, o JSON traz as 3 observações com as colunas de sempre

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

CAIXA="$(novo_sandbox)"
export RFM_ROOT="$CAIXA"
MEMORIA="node $SRC/scripts/memoria.cjs"

total=0
vermelhas=()
verde() { total=$((total+1)); echo "  ok   $1"; }
vermelha() { total=$((total+1)); vermelhas+=("$1"); echo "  FALHA $1: $2"; }

# Lê o JSON do buscar na entrada e devolve as marcas das observações, em ordem alfabética
# (a ordem de saída do buscar não é o que este teste afirma).
marcas() {
  node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const a=JSON.parse(s);console.log(a.map(o=>o.conteudo.match(/MARCA(\w+)/)[1]).sort().join(','))})"
}

# Recusa esperada: exit 2 e a forma AAAA-MM-DD no stderr.
recusa() {
  $MEMORIA "$@" >/dev/null 2>"$CAIXA/err.txt"
  local c=$?
  [ "$c" = "2" ] && grep -q 'AAAA-MM-DD' "$CAIXA/err.txt"
}

echo "== semeadura: tres observacoes em 2026-10-01, 2026-10-10 e 2026-10-20 =="
$MEMORIA iniciar >/dev/null 2>&1
SRC_MEM="$SRC/scripts/memoria.cjs" node -e "
  const { abrirBanco } = require(process.env.SRC_MEM);
  const db = abrirBanco(require('path').join(process.env.RFM_ROOT, 'rainforest.db'));
  const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  ins.run('proj-janela', 'janela MARCAALFA primeira observacao', '2026-10-01T12:00:00.000Z', 'teste-janela-alfa');
  ins.run('proj-janela', 'janela MARCABETA segunda observacao', '2026-10-10T12:00:00.000Z', 'teste-janela-beta');
  ins.run('proj-janela', 'janela MARCAGAMA terceira observacao', '2026-10-20T12:00:00.000Z', 'teste-janela-gama');
  db.close();
"

echo "== janela: --desde e --ate excluem a observacao anterior =="
got=$($MEMORIA buscar --desde 2026-10-05 --ate 2026-10-15 --json 2>/dev/null | marcas)
if [ "$got" = "BETA" ]; then verde "--desde exclui a observação anterior à data"
else vermelha "--desde exclui a observação anterior à data" "esperava BETA, veio [$got]"; fi

echo "== janela: --desde e inclusivo na data exata =="
got=$($MEMORIA buscar --desde 2026-10-10 --json 2>/dev/null | marcas)
if [ "$got" = "BETA,GAMA" ]; then verde "--desde 2026-10-10 inclui a de 10-10"
else vermelha "--desde 2026-10-10 inclui a de 10-10" "esperava BETA,GAMA, veio [$got]"; fi

echo "== janela: --texto combina com --desde e --ate =="
got=$($MEMORIA buscar --texto janela --desde 2026-10-05 --ate 2026-10-15 --json 2>/dev/null | marcas)
if [ "$got" = "BETA" ]; then verde "--texto combina com --desde e --ate"
else vermelha "--texto combina com --desde e --ate" "esperava BETA, veio [$got]"; fi

echo "== janela: data invalida sai exit 2 com AAAA-MM-DD =="
if recusa buscar --desde 2026-13-01 && recusa buscar --desde ontem \
   && recusa buscar --desde 2026-02-30 && recusa buscar --ate 2026-02-30; then
  verde "data inválida (2026-13-01, ontem, 2026-02-30) sai exit 2 com AAAA-MM-DD"
else
  vermelha "data inválida sai exit 2 com AAAA-MM-DD" "algum caso não saiu 2 com AAAA-MM-DD no stderr"
fi

echo "== sem --desde/--ate: as 3 observacoes e as colunas de sempre =="
got=$($MEMORIA buscar --json 2>/dev/null | marcas)
colunas=$($MEMORIA buscar --json 2>/dev/null | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(Object.keys(JSON.parse(s)[0]).join(',')))")
if [ "$got" = "ALFA,BETA,GAMA" ] && [ "$colunas" = "id,projeto,conteudo,criada_em" ]; then
  verde "sem --desde/--ate devolve as 3 observações com id,projeto,conteudo,criada_em"
else
  vermelha "sem --desde/--ate devolve as 3 observações" "marcas [$got], colunas [$colunas]"
fi

echo
echo "total=$total vermelhas:[$(IFS=,; echo "${vermelhas[*]:-}")]"
if [ "${#vermelhas[@]}" -eq 0 ]; then exit 0; else exit 1; fi
