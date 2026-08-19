#!/bin/bash
# Bateria do scripts/verifica-fidelidade-fixture.cjs — checador de fidelidade de fixtures
# Uso: bash scripts/testa-verifica-fidelidade.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

VERIFICADOR="node $SRC/scripts/verifica-fidelidade-fixture.cjs"

ok=0; falhou=0

echo "== 1. Teste A: Fixture com type válido (deve passar) =="
FIXTURE_A="$CAIXA/fixture-a.jsonl"
cat > "$FIXTURE_A" <<'EOF'
{"type":"user","message":{"role":"user","content":"teste"},"timestamp":"2026-08-19T10:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":"resposta"},"timestamp":"2026-08-19T10:00:01Z"}
EOF

REAL_A="$CAIXA/real-a.jsonl"
cat > "$REAL_A" <<'EOF'
{"type":"user","message":{"role":"user","content":"conteúdo real"},"timestamp":"2026-08-19T10:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":"resposta real"},"timestamp":"2026-08-19T10:00:01Z"}
EOF

$VERIFICADOR "$FIXTURE_A" --real "$REAL_A" >/dev/null 2>&1
EXIT_A=$?
if [ $EXIT_A -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    Fixture com types válidos passa (exit 0)"
else
  falhou=$((falhou+1)); echo "  FALHA Fixture com types válidos deveria passar, saiu $EXIT_A"
fi

echo
echo "== 2. Teste B: Fixture com type inválido (deve falhar) =="
FIXTURE_B="$CAIXA/fixture-b.jsonl"
cat > "$FIXTURE_B" <<'EOF'
{"type":"usuario","message":{"role":"user","content":"teste"},"timestamp":"2026-08-19T10:00:00Z"}
EOF

$VERIFICADOR "$FIXTURE_B" --real "$REAL_A" >/dev/null 2>&1
EXIT_B=$?
if [ $EXIT_B -ne 0 ]; then
  ok=$((ok+1)); echo "  ok    Fixture com type inválido falha (exit $EXIT_B)"
else
  falhou=$((falhou+1)); echo "  FALHA Fixture com type inválido deveria falhar, passou"
fi

echo
echo "== 3. Teste C: Fixture com campo extra (deve falhar) =="
FIXTURE_C="$CAIXA/fixture-c.jsonl"
cat > "$FIXTURE_C" <<'EOF'
{"type":"user","message":{"role":"user","content":"teste"},"timestamp":"2026-08-19T10:00:00Z","campo_extra":"nao existe no real"}
EOF

$VERIFICADOR "$FIXTURE_C" --real "$REAL_A" >/dev/null 2>&1
EXIT_C=$?
if [ $EXIT_C -ne 0 ]; then
  ok=$((ok+1)); echo "  ok    Fixture com campo extra falha (exit $EXIT_C)"
else
  falhou=$((falhou+1)); echo "  FALHA Fixture com campo extra deveria falhar, passou"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
