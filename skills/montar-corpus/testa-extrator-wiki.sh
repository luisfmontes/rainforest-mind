#!/bin/bash
# Bateria do extrator-wiki. Testa o extrator contra wiki-minima.
# Usa sandbox com projetos.json temporário, sem alterar config do usuário.
# Uso: bash skills/montar-corpus/testa-extrator-wiki.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

# Cria sandbox para projetos.json temporário
SBP="$(mktemp -d)"
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
export RFM_ROOT="$SB"
trap 'rm -rf "$SBP"' EXIT

# Cria projetos.json dentro da sandbox com wiki-minima
mkdir -p "$RFM_ROOT"
cat > "$RFM_ROOT/projetos.json" <<EOF
{
  "wiki-minima": {
    "caminho": "$SB/wiki-minima",
    "apelidos": []
  }
}
EOF

# Copia fixtures para dentro da sandbox
mkdir -p "$SB/wiki-minima"
cp -r "$SRC/test/fixtures/corpus/wiki-minima/wiki" "$SB/wiki-minima/"

EXTRATOR="node $SRC_WIN/skills/montar-corpus/extratores/wiki.cjs"
VALIDAR="node $SRC_WIN/scripts/validar-grafo.cjs"
TMPDIR="$SBP/output"
mkdir -p "$TMPDIR"

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    echo "$saida" | sed 's/^/         /' | tail -5
  fi
}

contem() { # nome, texto, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt' na saida"; fi
}

# ---------------------------------------------------------------- cenarios

echo "Bateria do extrator-wiki:"
echo ""

# Teste 1: Extração básica
echo "1. Extração de wiki-minima:"
esperado "  exit 0" 0 $EXTRATOR --corpus wiki-minima
$EXTRATOR --corpus wiki-minima > "$TMPDIR/grafo-minima.json" 2>&1
contem "  tem 3 nos" "\"id\": \"conceito" cat "$TMPDIR/grafo-minima.json"
contem "  tem arestas" "\"de\":" cat "$TMPDIR/grafo-minima.json"
echo ""

# Teste 2: Validação do grafo gerado
echo "2. Validação do grafo-minima:"
contem "  valido" "valido" $VALIDAR "$TMPDIR/grafo-minima.json"
esperado "  exit 0" 0 $VALIDAR "$TMPDIR/grafo-minima.json"
echo ""

# Teste 3: Contagem de nós
echo "3. Contagem de nós concept:"
count=$(grep -c '"file_type": "concept"' "$TMPDIR/grafo-minima.json" || echo "0")
if [ "$count" = "3" ]; then ok=$((ok+1)); echo "  ok   total de 3 nos"
else falhou=$((falhou+1)); echo "  FALHA contagem: esperava 3, veio $count"; fi
echo ""

# Teste 4: Aresta com confidence AMBIGUOUS
echo "4. Verificação de ligação inexistente (AMBIGUOUS):"
if grep -q '"confidence": "AMBIGUOUS"' "$TMPDIR/grafo-minima.json" && grep -q '"para": "pagina-inexistente"' "$TMPDIR/grafo-minima.json"; then
  ok=$((ok+1)); echo "  ok   aresta para pagina inexistente presente"
else
  falhou=$((falhou+1)); echo "  FALHA: nao achei aresta para pagina inexistente"
fi
echo ""

# ---------------------------------------------------------------- placar
echo "========================================"
echo "$ok ok   $falhou falha(s)"
echo "========================================"

if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
