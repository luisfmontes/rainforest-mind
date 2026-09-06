#!/bin/bash
# Bateria do validar-grafo. Testa o validador com grafo válido e inválido.
# Uso: bash scripts/testa-validar-grafo.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDAR="node $SRC/scripts/validar-grafo.cjs"
FIXTURE="$SRC/test/fixtures/corpus/grafo-exemplo.json"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

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

echo "Bateria do validar-grafo:"
echo ""

# Teste 1: Grafo válido
echo "1. Validação de grafo válido:"
contem "  retorna 'valido'" "valido" $VALIDAR "$FIXTURE"
esperado "  exit 0" 0 $VALIDAR "$FIXTURE"
echo ""

# Teste 2: file_type inválido (poema)
echo "2. Validação com file_type inválido:"
cp "$FIXTURE" "$TMPDIR/grafo-invalido.json"
# Substituir o primeiro file_type por "poema"
sed -i 's/"file_type": "concept"/"file_type": "poema"/1' "$TMPDIR/grafo-invalido.json"
contem "  retorna 'invalido: file_type'" "invalido: file_type" $VALIDAR "$TMPDIR/grafo-invalido.json"
esperado "  exit 1" 1 $VALIDAR "$TMPDIR/grafo-invalido.json"
echo ""

# Teste 3: confidence inválido
echo "3. Validação com confidence inválido:"
cp "$FIXTURE" "$TMPDIR/grafo-confidence-invalido.json"
sed -i 's/"confidence": "EXTRACTED"/"confidence": "INVALIDO"/1' "$TMPDIR/grafo-confidence-invalido.json"
contem "  retorna 'invalido: confidence'" "invalido: confidence" $VALIDAR "$TMPDIR/grafo-confidence-invalido.json"
esperado "  exit 1" 1 $VALIDAR "$TMPDIR/grafo-confidence-invalido.json"
echo ""

# Teste 4: Campo obrigatório ausente (id)
echo "4. Validação com campo 'id' ausente:"
cp "$FIXTURE" "$TMPDIR/grafo-sem-id.json"
sed -i 's/"id": "conceito-1",//' "$TMPDIR/grafo-sem-id.json"
contem "  retorna 'invalido: id'" "invalido: id" $VALIDAR "$TMPDIR/grafo-sem-id.json"
esperado "  exit 1" 1 $VALIDAR "$TMPDIR/grafo-sem-id.json"
echo ""

# Teste 5: Arquivo inválido (JSON inválido)
echo "5. Validação com JSON inválido:"
echo "{ broken json" > "$TMPDIR/grafo-json-invalido.json"
esperado "  exit 1" 1 $VALIDAR "$TMPDIR/grafo-json-invalido.json"
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
