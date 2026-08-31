#!/bin/bash
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

ok=0; falhou=0

echo "== 1. Gate com menos de 7 dias (3 dias) =="

RAIZ="$SBP/raiz"
mkdir -p "$RAIZ/poda"

echo '{"timestamp":"2026-08-01T10:00:00.000Z","duracao_ms":100,"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":2,"cache_creation_input_tokens":0}}' > "$RAIZ/poda/metricas.jsonl"
echo '{"timestamp":"2026-08-02T10:00:00.000Z","duracao_ms":110,"usage":{"input_tokens":15,"output_tokens":6,"cache_read_input_tokens":3,"cache_creation_input_tokens":0}}' >> "$RAIZ/poda/metricas.jsonl"
echo '{"timestamp":"2026-08-03T10:00:00.000Z","duracao_ms":105,"usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":2,"cache_creation_input_tokens":0}}' >> "$RAIZ/poda/metricas.jsonl"

RFM_ROOT="$RAIZ" node "$SRC/scripts/relatorio-poda.cjs" 2>&1 | head -1 | grep -q "FECHADO" && ok=$((ok+1)) && echo "  ok   gate closed with 3 days" || (falhou=$((falhou+1)); echo "  FAIL gate should be closed")

RFM_ROOT="$RAIZ" node "$SRC/scripts/relatorio-poda.cjs" > /dev/null 2>&1
EXIT_CODE=$?
[ $EXIT_CODE -ne 0 ] && ok=$((ok+1)) && echo "  ok   exit code 1 when gate closed" || (falhou=$((falhou+1)); echo "  FAIL exit code was $EXIT_CODE")

echo "== 2. Gate com 7 dias (gate aberto) =="

for i in {4..7}; do
  echo "{\"timestamp\":\"2026-08-0${i}T10:00:00.000Z\",\"duracao_ms\":100,\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"cache_read_input_tokens\":2,\"cache_creation_input_tokens\":0}}" >> "$RAIZ/poda/metricas.jsonl"
done

RFM_ROOT="$RAIZ" node "$SRC/scripts/relatorio-poda.cjs" 2>&1 | head -1 | grep -q "ABERTO" && ok=$((ok+1)) && echo "  ok   gate open with 7 days" || (falhou=$((falhou+1)); echo "  FAIL gate should be open")

RFM_ROOT="$RAIZ" node "$SRC/scripts/relatorio-poda.cjs" > /dev/null 2>&1
EXIT_CODE=$?
[ $EXIT_CODE -eq 0 ] && ok=$((ok+1)) && echo "  ok   exit code 0 when gate open" || (falhou=$((falhou+1)); echo "  FAIL exit code was $EXIT_CODE")

echo "== 3. JSON format test =="

RFM_ROOT="$RAIZ" node "$SRC/scripts/relatorio-poda.cjs" --json 2>&1 | head -1 | grep -q '"gate":"ABERTO"' && ok=$((ok+1)) && echo "  ok   json format valid" || (falhou=$((falhou+1)); echo "  FAIL json format")

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
