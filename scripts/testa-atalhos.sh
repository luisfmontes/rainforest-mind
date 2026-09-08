#!/bin/bash
set -euo pipefail

# Testa o coletor de atalhos
TMPDIR="${TMPDIR:-/tmp}"
TEST_ROOT="$TMPDIR/test-atalhos-$$"
mkdir -p "$TEST_ROOT"
trap "rm -rf '$TEST_ROOT'" EXIT

# Cria estrutura de teste
mkdir -p "$TEST_ROOT/src"
mkdir -p "$TEST_ROOT/.git"
mkdir -p "$TEST_ROOT/node_modules"
mkdir -p "$TEST_ROOT/.claude/worktrees"

# Variáveis para construir comentários dinamicamente (evita serem detectados no arquivo versionado)
COMMENT_MARKER="atalho"

# Caso 1: Marcador com teto e volta quando (deve contar normalmente)
cat > "$TEST_ROOT/src/file1.js" << 'EOF'
// Aqui vem algum código
// COMMENT_PLACEHOLDER: até 10 linhas. volta quando: precisar de performance.
console.log('test');
EOF
sed -i "s|// COMMENT_PLACEHOLDER:|// $COMMENT_MARKER:|" "$TEST_ROOT/src/file1.js"

# Caso 2: Marcador sem volta quando (deve marcar sem-gatilho)
cat > "$TEST_ROOT/src/file2.js" << 'EOF'
// Outro arquivo
// COMMENT_PLACEHOLDER: simplificação temporária
let x = 1;
EOF
sed -i "s|// COMMENT_PLACEHOLDER:|// $COMMENT_MARKER:|" "$TEST_ROOT/src/file2.js"

# Caso 3: Múltiplos marcadores no mesmo arquivo
cat > "$TEST_ROOT/src/file3.sh" << 'EOF'
#!/bin/bash
# COMMENT_PLACEHOLDER: sem logging. volta quando: precisar debug.
echo "test"
# COMMENT_PLACEHOLDER: sem validação entrada
var="value"
EOF
sed -i "s|# COMMENT_PLACEHOLDER:|# $COMMENT_MARKER:|g" "$TEST_ROOT/src/file3.sh"

# Caso 4: Arquivo em .git deve ser ignorado
cat > "$TEST_ROOT/.git/ignored.js" << 'EOF'
// COMMENT_PLACEHOLDER: isto não deve aparecer
EOF
sed -i "s|// COMMENT_PLACEHOLDER:|// $COMMENT_MARKER:|" "$TEST_ROOT/.git/ignored.js"

# Caso 5: Arquivo em node_modules deve ser ignorado
mkdir -p "$TEST_ROOT/node_modules/pkg"
cat > "$TEST_ROOT/node_modules/pkg/index.js" << 'EOF'
// COMMENT_PLACEHOLDER: também ignorado
EOF
sed -i "s|// COMMENT_PLACEHOLDER:|// $COMMENT_MARKER:|" "$TEST_ROOT/node_modules/pkg/index.js"

# Caso 6: Arquivo em .claude/worktrees deve ser ignorado
cat > "$TEST_ROOT/.claude/worktrees/ignored.js" << 'EOF'
// COMMENT_PLACEHOLDER: também ignorado
EOF
sed -i "s|// COMMENT_PLACEHOLDER:|// $COMMENT_MARKER:|" "$TEST_ROOT/.claude/worktrees/ignored.js"

# Roda o coletor com override de ROOT
export RFM_ROOT="$TEST_ROOT"
OUTPUT=$(node "$(dirname "$0")/atalhos.cjs")

# Verifica os resultados
echo "=== Output do coletor ===" >&2
echo "$OUTPUT" >&2
echo "========================" >&2

# Conta os marcadores encontrados (deve ser 4: file1.js, file2.js, file3.sh x2)
ENCONTRADOS=$(echo "$OUTPUT" | grep -cE "(src[\\/]file[123]|^file[123])" || true)
ESPERADOS=4

if [ "$ENCONTRADOS" -ne "$ESPERADOS" ]; then
  echo "ERRO: Esperava $ESPERADOS marcadores em arquivos válidos, encontrou $ENCONTRADOS" >&2
  exit 1
fi

# Verifica que file1.js tem "volta quando:"
if ! echo "$OUTPUT" | grep -i "file1.*volta quando: precisar de performance" | grep -q .; then
  echo "ERRO: file1.js não tem volta quando correto" >&2
  exit 1
fi

# Verifica que file2.js tem "sem-gatilho"
if ! echo "$OUTPUT" | grep -i "file2.*sem-gatilho" | grep -q .; then
  echo "ERRO: file2.js não marcado como sem-gatilho" >&2
  exit 1
fi

# Verifica que arquivos ignorados não aparecem
if echo "$OUTPUT" | grep -E "(\.git|node_modules|worktrees)" | grep -q .; then
  echo "ERRO: Arquivos que deveriam ser ignorados foram encontrados" >&2
  exit 1
fi

# Verifica a contagem final (deve ser "4 marcadores, 2 sem gatilho")
if ! echo "$OUTPUT" | grep -q "4 marcadores, 2 sem gatilho"; then
  echo "ERRO: Contagem final incorreta" >&2
  exit 1
fi

echo "✓ Testes passaram" >&2
exit 0
