#!/bin/bash
set -e

# Teste do resolvodor de raiz de dados em vigias/dados-batedor-repos.js
# Roda em caixa de areia (HOME/USERPROFILE temporário) com ideias.jsonl fabricado.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Cria caixa de areia
SANDBOX=$(mktemp -d)
cleanup() {
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

export USERPROFILE="$SANDBOX"
export HOME="$SANDBOX"

# Limpa RFM_ROOT para testar o default (cadeia de resolução)
unset RFM_ROOT

# ==============================================================================
# TESTE 1: sem RFM_ROOT, com raiz de dados fabricada, reporta N ideias abertas
# ==============================================================================
echo "=== TESTE 1: Resolve raiz de dados sem RFM_ROOT ==="

# Cria ~/.rainforest com ideias.jsonl
mkdir -p "$SANDBOX/.rainforest"
cat > "$SANDBOX/.rainforest/ideias.jsonl" << 'EOF'
{"id":"idea-1","tipo":"ideia","status":"plantada","titulo":"Primeira ideia","projeto":"teste","plantada_em":"2026-08-20T10:00:00Z"}
{"id":"idea-2","tipo":"ideia","status":"plantada","titulo":"Segunda ideia","projeto":"teste","plantada_em":"2026-08-21T10:00:00Z"}
{"id":"obs-1","tipo":"observacao","status":"plantada","titulo":"Primeira observacao","projeto":"teste","plantada_em":"2026-08-22T10:00:00Z"}
{"id":"idea-3","tipo":"ideia","status":"colhida","titulo":"Colhida (nao conta)","projeto":"teste","colhida_em":"2026-08-23T10:00:00Z"}
EOF

SAIDA=$(node "$REPO_ROOT/vigias/dados-batedor-repos.js")
IDEIAS=$(echo "$SAIDA" | grep "^IDEIAS ABERTAS" | grep -oE '\([0-9]+\)' | grep -oE '[0-9]+')
OBS=$(echo "$SAIDA" | grep "^OBSERVACOES DA REGRA 13 ABERTAS" | grep -oE '\([0-9]+\)' | grep -oE '[0-9]+')

echo "Ideias abertas encontradas: $IDEIAS (esperado: 2)"
echo "Observacoes abertas encontradas: $OBS (esperado: 1)"

[ "$IDEIAS" = "2" ] || { echo "FALHA: esperava 2 ideias, encontrou $IDEIAS"; exit 1; }
[ "$OBS" = "1" ] || { echo "FALHA: esperava 1 observação, encontrou $OBS"; exit 1; }
echo "✓ TESTE 1 passou"
echo

# ==============================================================================
# TESTE 2: sem RFM_ROOT, continua achando propostas de relatório do repo
# ==============================================================================
echo "=== TESTE 2: Propostas de relatorio do PLUGIN (guarda de regressao) ==="

PROPOSTAS=$(echo "$SAIDA" | grep "^PROPOSTAS NOS 4 RELATORIOS" | grep -oE '\([0-9]+\)' | grep -oE '[0-9]+')
echo "Propostas encontradas: $PROPOSTAS (esperado: nao-zero)"

# Verifica se encontrou algumas propostas (ha relatorios reais no repo)
[ "$PROPOSTAS" -gt 0 ] || { echo "FALHA: esperava propostas, encontrou $PROPOSTAS"; exit 1; }
echo "✓ TESTE 2 passou (encontrou $PROPOSTAS propostas)"
echo

# ==============================================================================
# TESTE 3: RFM_ROOT explícito vence a cadeia
# ==============================================================================
echo "=== TESTE 3: RFM_ROOT explícito vence a cadeia ==="

# Cria outra raiz de dados em pasta alternativa
ALT_ROOT=$(mktemp -d)
cleanup_alt() {
  rm -rf "$ALT_ROOT"
}
trap "cleanup; cleanup_alt" EXIT

mkdir -p "$ALT_ROOT"
cat > "$ALT_ROOT/ideias.jsonl" << 'EOF'
{"id":"alt-idea-1","tipo":"ideia","status":"plantada","titulo":"Idea alternativa 1","projeto":"alt","plantada_em":"2026-08-20T10:00:00Z"}
{"id":"alt-idea-2","tipo":"ideia","status":"plantada","titulo":"Idea alternativa 2","projeto":"alt","plantada_em":"2026-08-21T10:00:00Z"}
{"id":"alt-idea-3","tipo":"ideia","status":"plantada","titulo":"Idea alternativa 3","projeto":"alt","plantada_em":"2026-08-22T10:00:00Z"}
EOF

export RFM_ROOT="$ALT_ROOT"
SAIDA_ALT=$(node "$REPO_ROOT/vigias/dados-batedor-repos.js")
IDEIAS_ALT=$(echo "$SAIDA_ALT" | grep "^IDEIAS ABERTAS" | grep -oE '\([0-9]+\)' | grep -oE '[0-9]+')

echo "Ideias com RFM_ROOT alternativo: $IDEIAS_ALT (esperado: 3)"
[ "$IDEIAS_ALT" = "3" ] || { echo "FALHA: esperava 3 ideias, encontrou $IDEIAS_ALT"; exit 1; }
echo "✓ TESTE 3 passou"
echo

echo "=== Todos os testes passaram ==="
