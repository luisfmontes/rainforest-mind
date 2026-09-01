#!/bin/bash
# Bateria para segunda-opiniao.cjs — segunda opinião de modelo externo
# Uso: bash scripts/testa-segunda-opiniao.sh
#
# Testa segunda-opiniao contra fixtures (nunca contra CLI real — D7).

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_M="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT

echo "(caixa de areia: $RAIZ)"
echo ""

ok=0
falhou=0

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
    echo "$saida" | sed 's/^/         /' | head -10
  fi
}

echo "== CASO 1: veredito-concordo =="

TEMP_REPO="$RAIZ/test-concordo-repo"
mkdir -p "$TEMP_REPO"
cd "$TEMP_REPO"
git init --quiet
git config user.email "test@example.com"
git config user.name "Test"

echo "base file" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA=$(git rev-parse HEAD)

echo "modified content" > file.txt
git add file.txt
git commit --quiet -m "head"
HEAD_SHA=$(git rev-parse HEAD)

CRITERIO_FILE="$TEMP_REPO/criterio.md"
cat > "$CRITERIO_FILE" << 'EOF'
# Critério: modificação válida

A entrega modifica o arquivo com conteúdo válido.
EOF

FIXTURE_CONCORDO="$SRC_M/scripts/fixtures/segunda-opiniao/concordo.cjs"
OUTPUT=$(cd "$TEMP_REPO" && node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA" --head "$HEAD_SHA" --criterio "$CRITERIO_FILE" --cli-cmd "node $FIXTURE_CONCORDO" 2>&1)
EXIT_CODE=$?
if [ "$EXIT_CODE" = "0" ] && echo "$OUTPUT" | grep -q "^concordo$"; then
  ok=$((ok + 1))
  echo "  ok   veredito-concordo sai 0 com output 'concordo'"
else
  falhou=$((falhou + 1))
  echo "  FALHA output: $OUTPUT (exit $EXIT_CODE)"
fi

echo ""
echo "== CASO 2: veredito-discordo =="

TEMP_REPO2="$RAIZ/test-discordo-repo"
mkdir -p "$TEMP_REPO2"
cd "$TEMP_REPO2"
git init --quiet
git config user.email "test@example.com"
git config user.name "Test"

echo "initial" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA2=$(git rev-parse HEAD)

echo "broken content" > file.txt
git add file.txt
git commit --quiet -m "head"
HEAD_SHA2=$(git rev-parse HEAD)

CRITERIO_FILE2="$TEMP_REPO2/criterio.md"
cat > "$CRITERIO_FILE2" << 'EOF'
# Critério: conteúdo deve ser válido

A modificação deve manter a validade.
EOF

FIXTURE_DISCORDO="$SRC_M/scripts/fixtures/segunda-opiniao/discordo.cjs"
OUTPUT2=$(cd "$TEMP_REPO2" && node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA2" --head "$HEAD_SHA2" --criterio "$CRITERIO_FILE2" --cli-cmd "node $FIXTURE_DISCORDO" 2>&1)
EXIT_CODE2=$?
if [ "$EXIT_CODE2" = "0" ] && echo "$OUTPUT2" | grep -q "^discordo$"; then
  ok=$((ok + 1))
  echo "  ok   veredito-discordo sai 0 com output 'discordo'"
else
  falhou=$((falhou + 1))
  echo "  FALHA veredito-discordo: output=$OUTPUT2, exit=$EXIT_CODE2"
fi

echo ""
echo "== CASO 3: veredito-fora-do-vocabulario (deve sair ≠ 0) =="

TEMP_REPO3="$RAIZ/test-invalido-repo"
mkdir -p "$TEMP_REPO3"
cd "$TEMP_REPO3"
git init --quiet
git config user.email "test@example.com"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA3=$(git rev-parse HEAD)

echo "modified" > file.txt
git add file.txt
git commit --quiet -m "head"
HEAD_SHA3=$(git rev-parse HEAD)

CRITERIO_FILE3="$TEMP_REPO3/criterio.md"
cat > "$CRITERIO_FILE3" << 'EOF'
# Critério simples
Validar modificação.
EOF

FIXTURE_INVALID="$SRC_M/scripts/fixtures/segunda-opiniao/veredito-fora-do-vocabulario.cjs"
testa "veredito-inválido sai ≠ 0" "1" \
  bash -c "cd '$TEMP_REPO3' && node '$SRC/scripts/segunda-opiniao.cjs' --base '$BASE_SHA3' --head '$HEAD_SHA3' --criterio '$CRITERIO_FILE3' --cli-cmd 'node $FIXTURE_INVALID'"

echo ""
echo "== CASO 4: falta --base =="

testa "sem --base sai ≠ 0" "1" \
  bash -c "cd '$TEMP_REPO' && node '$SRC/scripts/segunda-opiniao.cjs' --head '$HEAD_SHA' --criterio '$CRITERIO_FILE' --cli-cmd 'node $FIXTURE_CONCORDO'"

echo ""
echo "== CASO 5: falta --head =="

testa "sem --head sai ≠ 0" "1" \
  bash -c "cd '$TEMP_REPO' && node '$SRC/scripts/segunda-opiniao.cjs' --base '$BASE_SHA' --criterio '$CRITERIO_FILE' --cli-cmd 'node $FIXTURE_CONCORDO'"

echo ""
echo "== CASO 6: diff vazio (base == head) =="

testa "diff vazio sai ≠ 0" "1" \
  bash -c "cd '$TEMP_REPO' && node '$SRC/scripts/segunda-opiniao.cjs' --base '$BASE_SHA' --head '$BASE_SHA' --criterio '$CRITERIO_FILE' --cli-cmd 'node $FIXTURE_CONCORDO'"

echo ""
echo "== CASO 7: criterio não existe =="

testa "criterio inexistente sai ≠ 0" "1" \
  bash -c "cd '$TEMP_REPO' && node '$SRC/scripts/segunda-opiniao.cjs' --base '$BASE_SHA' --head '$HEAD_SHA' --criterio /nao/existe.md --cli-cmd 'node $FIXTURE_CONCORDO'"

echo ""
echo "== RESUMO =="
echo "Ok: $ok"
echo "Falhou: $falhou"
echo ""

if [ "$falhou" -eq 0 ]; then
  echo "Bateria passou!"
  exit 0
else
  echo "Bateria teve falhas."
  exit 1
fi
