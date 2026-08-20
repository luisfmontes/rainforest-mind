#!/usr/bin/env bash
# Tarefa 19 — o offset é byte de ponta a ponta.
#
# A marca d'água grava `fs.statSync().size`, que é BYTE. Quem lê o transcrito
# a partir dela precisa fatiar em BYTE também. A versão que usava
# `conteudo.substring(offset)` fatiava em unidade UTF-16: uma primeira linha com
# acentuação PT-BR (122 bytes / 106 caracteres) fazia o corte cair 16 caracteres
# dentro da linha seguinte, quebrando o JSON. Como `processarMarca` volta cedo
# com zero eventos, o `offset_processado` nunca avançava e a sessão travava ali
# para sempre — em silêncio, com exit 0.
#
# Esta bateria exercita o `scripts/observar.cjs` de verdade. Uma versão anterior
# reimplementava `substring` e `Buffer.toString` dentro do próprio teste e
# comparava os dois: provava uma verdade sobre JavaScript, não sobre este repo,
# e continuava verde com o defeito de volta no lugar. O teste tem que falhar
# quando o produto regride, não quando a linguagem muda.
set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAIZ_POSIX="$(mktemp -d)"
# O node aqui é o do Windows: caminho MSYS (/tmp/...) chega nele como inexistente,
# e o hook grava offset 0 sem reclamar. Mesma convenção das outras baterias.
RAIZ=$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")
trap 'rm -rf "$RAIZ_POSIX"' EXIT

export RFM_ROOT="$RAIZ"
export TESTADOR_CHAMAR_LLM="$SRC/scripts/dubliador-llm-ok.cjs"
export DEBUG_OBSERVADOR=1

ok=0
falhou=0

node "$SRC/scripts/memoria.cjs" iniciar >/dev/null 2>&1

TRANSCRITO="$RAIZ/transcrito.jsonl"
SESSAO="sessao-acentos"
PROJETO="proj-acentos"

# Linha 1 com acentuação PT-BR trivial de aparecer numa sessão real, e linha 2
# em ASCII puro: o desalinhamento byte-vs-caractere cai inteiro dentro dela.
node -e '
const fs = require("fs");
const l1 = JSON.stringify({type:"user",message:{role:"user",content:"É uma pergunta com acentuação: ção çã éé ãã ôô üü ñ"}}) + "\n";
const l2 = JSON.stringify({type:"assistant",message:{role:"assistant",content:"plain ascii answer here"}}) + "\n";
fs.writeFileSync(process.argv[1], l1 + l2);
fs.writeFileSync(process.argv[1] + ".medida", JSON.stringify({
  l1_bytes: Buffer.byteLength(l1),
  l1_chars: l1.length,
  total_bytes: Buffer.byteLength(l1 + l2),
}));
' "$TRANSCRITO"

MEDIDA=$(cat "$TRANSCRITO.medida")
L1_BYTES=$(node -pe 'JSON.parse(process.argv[1]).l1_bytes' "$MEDIDA")
L1_CHARS=$(node -pe 'JSON.parse(process.argv[1]).l1_chars' "$MEDIDA")

echo "== 1. a primeira linha tem mesmo diferença entre byte e caractere =="
if [ "$L1_BYTES" -gt "$L1_CHARS" ]; then
  ok=$((ok+1)); echo "  ok   linha 1: $L1_BYTES bytes, $L1_CHARS caracteres (diferença: $((L1_BYTES-L1_CHARS)))"
else
  falhou=$((falhou+1)); echo "  FALHA fixture sem multibyte ($L1_BYTES bytes = $L1_CHARS chars): a bateria não testaria nada"
fi

# O caminho real: o hook grava a marca a partir do payload do harness.
echo "{\"session_id\":\"$SESSAO\",\"transcript_path\":\"$TRANSCRITO\",\"cwd\":\"$RAIZ/$PROJETO\"}" \
  | node "$SRC/hooks/memoria-marca.cjs" >/dev/null 2>&1

PROJ_REAL=$(node -e '
const { abrirBancoSomenteLeitura } = require(process.argv[1] + "/scripts/memoria.cjs");
const db = abrirBancoSomenteLeitura(process.env.RFM_ROOT + "/rainforest.db");
const r = db.prepare("SELECT projeto FROM marca_dagua WHERE sessao = ?").all(process.argv[2]);
console.log(r.length ? r[0].projeto : "");
' "$SRC" "$SESSAO" 2>/dev/null)

echo "== 2. primeira passada processa e avança o offset =="
SAIDA1=$(node "$SRC/scripts/observar.cjs" --sessao "$SESSAO" --projeto "$PROJ_REAL" 2>&1)
if echo "$SAIDA1" | grep -q "observacao gravada\|observação gravada"; then
  ok=$((ok+1)); echo "  ok   primeira passada gravou observação"
else
  falhou=$((falhou+1)); echo "  FALHA primeira passada não gravou:"; echo "$SAIDA1" | sed 's/^/        /'
fi

OFFSET_PROC=$(node -e '
const { abrirBancoSomenteLeitura } = require(process.argv[1] + "/scripts/memoria.cjs");
const db = abrirBancoSomenteLeitura(process.env.RFM_ROOT + "/rainforest.db");
const r = db.prepare("SELECT offset_processado FROM marca_dagua WHERE sessao = ?").all(process.argv[2]);
console.log(r.length ? (r[0].offset_processado || 0) : 0);
' "$SRC" "$SESSAO" 2>/dev/null)

if [ "$OFFSET_PROC" -ge "$L1_BYTES" ]; then
  ok=$((ok+1)); echo "  ok   offset_processado avançou para $OFFSET_PROC (>= os $L1_BYTES bytes da linha 1)"
else
  falhou=$((falhou+1)); echo "  FALHA offset_processado ficou em $OFFSET_PROC, esperado >= $L1_BYTES"
fi

# Agora a sessão cresce: é aqui que o offset em byte encontra o corte em caractere.
node -e '
const fs = require("fs");
fs.appendFileSync(process.argv[1], JSON.stringify({type:"user",message:{role:"user",content:"segunda rodada, ainda ascii"}}) + "\n");
' "$TRANSCRITO"

echo "{\"session_id\":\"$SESSAO\",\"transcript_path\":\"$TRANSCRITO\",\"cwd\":\"$RAIZ/$PROJETO\"}" \
  | node "$SRC/hooks/memoria-marca.cjs" >/dev/null 2>&1

echo "== 3. segunda passada lê a janela sem corromper o JSON =="
SAIDA2=$(node "$SRC/scripts/observar.cjs" --sessao "$SESSAO" --projeto "$PROJ_REAL" 2>&1)

if echo "$SAIDA2" | grep -q "linha malformada"; then
  falhou=$((falhou+1))
  echo "  FALHA o corte caiu no meio de um evento — offset em byte lido como índice de caractere:"
  echo "$SAIDA2" | grep "linha malformada" | sed 's/^/        /'
else
  ok=$((ok+1)); echo "  ok   nenhuma linha malformada na janela"
fi

EVENTOS=$(echo "$SAIDA2" | sed -n 's/.*eventos lidos: \([0-9]*\).*/\1/p' | tail -1)
if [ "${EVENTOS:-0}" -ge 1 ]; then
  ok=$((ok+1)); echo "  ok   segunda passada leu ${EVENTOS} evento(s) novo(s)"
else
  falhou=$((falhou+1)); echo "  FALHA segunda passada leu ${EVENTOS:-0} eventos — a captura travou nesta sessão"
fi

OFFSET_PROC2=$(node -e '
const { abrirBancoSomenteLeitura } = require(process.argv[1] + "/scripts/memoria.cjs");
const db = abrirBancoSomenteLeitura(process.env.RFM_ROOT + "/rainforest.db");
const r = db.prepare("SELECT offset_processado FROM marca_dagua WHERE sessao = ?").all(process.argv[2]);
console.log(r.length ? (r[0].offset_processado || 0) : 0);
' "$SRC" "$SESSAO" 2>/dev/null)

echo "== 4. o offset volta a avançar (a sessão não travou) =="
if [ "$OFFSET_PROC2" -gt "$OFFSET_PROC" ]; then
  ok=$((ok+1)); echo "  ok   offset_processado: $OFFSET_PROC -> $OFFSET_PROC2"
else
  falhou=$((falhou+1)); echo "  FALHA offset_processado parado em $OFFSET_PROC2: a sessão travaria aqui para sempre"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
exit 0
