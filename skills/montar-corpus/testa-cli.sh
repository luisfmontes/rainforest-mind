#!/bin/bash
# Bateria do CLI. Testa montar-corpus contra wiki-minima.
# Usa sandbox com projetos.json temporário, sem alterar config do usuário.
# Uso: bash skills/montar-corpus/testa-cli.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

# Cria sandbox para RFM_ROOT temporário
SBP="$(mktemp -d)"
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
export RFM_ROOT="$SB"
trap 'rm -rf "$SBP"' EXIT

# Inicializa sandbox com projetos.json
mkdir -p "$RFM_ROOT"
touch "$RFM_ROOT/FOCO.md"
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

CLI="node $SRC_WIN/skills/montar-corpus/cli.cjs"
TMPDIR="$SBP/output"
mkdir -p "$TMPDIR"

ok=0; falhou=0

esperado() {
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    echo "$saida" | sed 's/^/         /' | head -10
  fi
}

contem() {
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt' na saida"; fi
}

echo "Bateria do CLI montar-corpus:"
echo ""

echo "1. Sem flags, recusa com mensagem:"
esperado "  exit != 0" 1 $CLI
contem "  menciona --repo" "--repo" $CLI
contem "  menciona --corpus" "--corpus" $CLI
echo ""

echo "2. Corpus inexistente, recusa nomeando o slug:"
esperado "  exit != 0" 1 $CLI --corpus corpus-inexistente
contem "  nomeia o slug" "corpus-inexistente" $CLI --corpus corpus-inexistente
echo ""

echo "3. Corpus wiki-minima, sucesso:"
esperado "  exit 0" 0 $CLI --corpus wiki-minima
if [ -f "$SB/acervo/wiki-minima/INDEX.md" ]; then
  ok=$((ok+1)); echo "  ok   acervo/wiki-minima/INDEX.md existe"
else
  falhou=$((falhou+1)); echo "  FALHA acervo/wiki-minima/INDEX.md não existe"
fi
if [ -f "$SB/acervo/wiki-minima/conceito-a.md" ]; then
  ok=$((ok+1)); echo "  ok   acervo/wiki-minima/conceito-a.md existe"
else
  falhou=$((falhou+1)); echo "  FALHA acervo/wiki-minima/conceito-a.md não existe"
fi
echo ""

echo "4. Acervo foi criado com conteúdo:"
if [ -s "$SB/acervo/wiki-minima/INDEX.md" ] && grep -q "conceito-a" "$SB/acervo/wiki-minima/INDEX.md"; then
  ok=$((ok+1)); echo "  ok   acervo com conteúdo verificado"
else
  falhou=$((falhou+1)); echo "  FALHA acervo ou INDEX.md sem conteúdo"
fi
echo ""

echo "========================================"
echo "$ok ok   $falhou falha(s)"
echo "========================================"

if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
