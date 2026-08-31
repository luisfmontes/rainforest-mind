#!/bin/bash
# Bateria para conselho.cjs — debate estruturado de decisões de design
# Uso: bash scripts/testa-conselho.sh
#
# Testa o comando `abrir --questao`, resolução de membros, quórum e geração de rodada.
# Roda em diretório temporário, nunca modifica o repo.

set -u

# Get source directory
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONSELHO="$SRC/scripts/conselho.cjs"

# Create sandbox
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT

echo "(caixa de areia: $RAIZ)"
echo ""

ok=0
falhou=0

# Test helper: runs command in sandbox and checks exit code
testa() {
  local nome="$1"
  local exit_esperado="$2"
  shift 2

  local saida
  saida=$("$@" 2>&1); local exit_obtido=$?

  if [ "$exit_obtido" = "$exit_esperado" ]; then
    ok=$((ok + 1))
    echo "  ok   $nome (exit $exit_obtido)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $nome: esperava exit $exit_esperado, veio $exit_obtido"
    echo "$saida" | sed 's/^/         /' | head -15
  fi
}

echo "== CASO 1: quorum-dois-membros =="
TEMPDIR1="$RAIZ/test-quorum-dois"
mkdir -p "$TEMPDIR1/.rainforest/conselho"

# Create membros.json with only 2 linked
cat > "$TEMPDIR1/.rainforest/conselho/membros.json" << 'EOF'
{
  "membros": [
    {"nome": "cetico", "cmd": "echo test", "ligado": true},
    {"nome": "arquiteto", "cmd": "echo test", "ligado": true}
  ]
}
EOF

# Create test question file
echo "# Questão de teste" > "$TEMPDIR1/questao.md"

# Run abrir command and expect it to fail (exit != 0)
testa "quorum-dois-membros: exit != 0" "1" \
  bash -c "cd '$TEMPDIR1' && node '$CONSELHO' abrir --questao questao.md"

echo ""
echo "== CASO 2: abrir-padrao (sem membros.json) =="
TEMPDIR2="$RAIZ/test-padrao"
mkdir -p "$TEMPDIR2"

# Create test question file
echo "# Questão de teste para rodada" > "$TEMPDIR2/questao-design.md"

# Run abrir - should succeed and create rodada
testa "abrir-padrao: exit 0" "0" \
  bash -c "cd '$TEMPDIR2' && node '$CONSELHO' abrir --questao questao-design.md"

# Check that membros.json was created
if [ -f "$TEMPDIR2/.rainforest/conselho/membros.json" ]; then
  ok=$((ok + 1))
  echo "  ok   membros.json gerado"
else
  falhou=$((falhou + 1))
  echo "  FALHA membros.json não foi criado"
fi

# Check that it has 5 members
MEMBRO_COUNT=$(grep -c '"nome"' "$TEMPDIR2/.rainforest/conselho/membros.json" 2>/dev/null || echo 0)
if [ "$MEMBRO_COUNT" = "5" ]; then
  ok=$((ok + 1))
  echo "  ok   membros.json tem 5 membros"
else
  falhou=$((falhou + 1))
  echo "  FALHA membros.json tem $MEMBRO_COUNT membros, esperava 5"
fi

# Check that 3 are linked (cetico, arquiteto, usuario-final)
LIGADOS=$(grep '"ligado": true' "$TEMPDIR2/.rainforest/conselho/membros.json" 2>/dev/null | wc -l)
if [ "$LIGADOS" = "3" ]; then
  ok=$((ok + 1))
  echo "  ok   3 membros ligados"
else
  falhou=$((falhou + 1))
  echo "  FALHA $LIGADOS membros ligados, esperava 3"
fi

# Check that rodada directory was created
RODADA_DIR=$(ls -1d "$TEMPDIR2/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR" ]; then
  ok=$((ok + 1))
  echo "  ok   diretório de rodada criado"
else
  falhou=$((falhou + 1))
  echo "  FALHA diretório de rodada não foi criado"
fi

# Check that 3 prompt files were created (only linked members)
if [ -n "$RODADA_DIR" ]; then
  PROMPT_COUNT=$(ls "$RODADA_DIR"/prompt-*.md 2>/dev/null | wc -l)
  if [ "$PROMPT_COUNT" = "3" ]; then
    ok=$((ok + 1))
    echo "  ok   3 arquivos de prompt gerados"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $PROMPT_COUNT arquivos de prompt, esperava 3"
  fi

  # Check that estado.json was created in rodada
  if [ -f "$RODADA_DIR/estado.json" ]; then
    ok=$((ok + 1))
    echo "  ok   estado.json criado na rodada"
  else
    falhou=$((falhou + 1))
    echo "  FALHA estado.json não foi criado na rodada"
  fi
fi

echo ""
echo "== CASO 3: atribuicao-no-cabecalho =="

# Check that conselho.cjs header contains karpathy attribution
if grep -q "karpathy/llm-council" "$CONSELHO"; then
  ok=$((ok + 1))
  echo "  ok   atribuição a karpathy/llm-council presente"
else
  falhou=$((falhou + 1))
  echo "  FALHA atribuição a karpathy/llm-council não encontrada"
fi

# Check for https://github.com/karpathy/llm-council URL
if grep -q "https://github.com/karpathy/llm-council" "$CONSELHO"; then
  ok=$((ok + 1))
  echo "  ok   URL do repositório presente"
else
  falhou=$((falhou + 1))
  echo "  FALHA URL do repositório não encontrada"
fi

echo ""
echo "== Resultado =="
echo "total=$((ok + falhou)) vermelhas:[$falhou]"
if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
