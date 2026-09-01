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
echo "== CASO 8: timeout-configuravel-por-ambiente =="

TEMP_REPO_TIMEOUT="$RAIZ/test-timeout-repo"
mkdir -p "$TEMP_REPO_TIMEOUT"
cd "$TEMP_REPO_TIMEOUT"
git init --quiet
git config user.email "test@example.com"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_TIMEOUT=$(git rev-parse HEAD)

echo "modified" > file.txt
git add file.txt
git commit --quiet -m "head"
HEAD_SHA_TIMEOUT=$(git rev-parse HEAD)

CRITERIO_FILE_TIMEOUT="$TEMP_REPO_TIMEOUT/criterio.md"
cat > "$CRITERIO_FILE_TIMEOUT" << 'EOF'
# Critério: resposta rápida
Modelo deve responder dentro do limite.
EOF

# Fixture que dorme 35 segundos (entre 30s antigo e 300s novo padrão)
# Com env=10ms: vai timeout
# Com padrão 300s: vai passar
# Com mutação (30s fixo): vai timeout — QUEBRA!
FIXTURE_35S="$SRC_M/scripts/fixtures/segunda-opiniao/timeout-35s.cjs"

# Teste 1: com timeout curto (10ms), fixture que dorme 35s deve falhar
OUTPUT_TIMEOUT=$(cd "$TEMP_REPO_TIMEOUT" && TIMEOUT_SEGUNDA_OPINIAO_MS=10 TIMEOUT_SEGUNDA_OPINIAO_DEBUG=1 node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA_TIMEOUT" --head "$HEAD_SHA_TIMEOUT" --criterio "$CRITERIO_FILE_TIMEOUT" --cli-cmd "node $FIXTURE_35S" 2>&1); EXIT_TIMEOUT=$?
if [ "$EXIT_TIMEOUT" != "0" ]; then
  # Validar que timeout curto está sendo usado
  if echo "$OUTPUT_TIMEOUT" | grep -q "TIMEOUT_SEGUNDA_OPINIAO_MS=10"; then
    ok=$((ok + 1))
    echo "  ok   timeout com env=10ms sai ≠ 0, valor efetivo é 10ms"
  else
    falhou=$((falhou + 1))
    echo "  FALHA timeout com env=10ms saiu ≠0 mas não encontrei 'TIMEOUT_SEGUNDA_OPINIAO_MS=10' no log"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA timeout com env=10ms deveria sair ≠ 0, saiu 0"
fi

# Teste 2: sem env var, validar que default é 300000ms
FIXTURE_RAPIDA_PATH="$SRC_M/scripts/fixtures/segunda-opiniao/concordo.cjs"
OUTPUT_DEFAULT=$(cd "$TEMP_REPO_TIMEOUT" && TIMEOUT_SEGUNDA_OPINIAO_DEBUG=1 node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA_TIMEOUT" --head "$HEAD_SHA_TIMEOUT" --criterio "$CRITERIO_FILE_TIMEOUT" --cli-cmd "node $FIXTURE_RAPIDA_PATH" 2>&1); EXIT_DEFAULT=$?
if [ "$EXIT_DEFAULT" = "0" ]; then
  # Validar que default 300000 está sendo usado
  if echo "$OUTPUT_DEFAULT" | grep -q "TIMEOUT_SEGUNDA_OPINIAO_MS=300000"; then
    ok=$((ok + 1))
    echo "  ok   default (sem env): valor efetivo é 300000ms"
  else
    falhou=$((falhou + 1))
    echo "  FALHA default deveria ser 300000ms, log diz: $(echo "$OUTPUT_DEFAULT" | grep TIMEOUT)"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA default sem env deveria passar, saiu $EXIT_DEFAULT"
fi

echo ""
echo "== CASO 9: parecer-preservado-com-veredito =="

TEMP_REPO_PARECER="$RAIZ/test-parecer-repo"
mkdir -p "$TEMP_REPO_PARECER"
cd "$TEMP_REPO_PARECER"
git init --quiet
git config user.email "test@example.com"
git config user.name "Test"

echo "file content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_PARECER=$(git rev-parse HEAD)

echo "modified file content" > file.txt
git add file.txt
git commit --quiet -m "head"
HEAD_SHA_PARECER=$(git rev-parse HEAD)

CRITERIO_FILE_PARECER="$TEMP_REPO_PARECER/criterio.md"
cat > "$CRITERIO_FILE_PARECER" << 'EOF'
# Critério: qualidade da modificação
Análise profunda requerida.
EOF

FIXTURE_PARECER="$SRC_M/scripts/fixtures/segunda-opiniao/parecer-multilinhas.cjs"

# Fixture retorna parecer multilinhas + veredito "concordo"
# Teste deve recuperar AMBOS (parecer via stderr, veredito via stdout)
PARECER_OUTPUT=$(cd "$TEMP_REPO_PARECER" && node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA_PARECER" --head "$HEAD_SHA_PARECER" --criterio "$CRITERIO_FILE_PARECER" --cli-cmd "node $FIXTURE_PARECER" 2>&1)
EXIT_PARECER=$?

# Verificar que saiu 0
if [ "$EXIT_PARECER" != "0" ]; then
  falhou=$((falhou + 1))
  echo "  FALHA parecer: exit deveria ser 0, foi $EXIT_PARECER"
else
  # Verificar que stdout (última linha) tem veredito
  VEREDITO=$(cd "$TEMP_REPO_PARECER" && node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA_PARECER" --head "$HEAD_SHA_PARECER" --criterio "$CRITERIO_FILE_PARECER" --cli-cmd "node $FIXTURE_PARECER" 2>/dev/null)
  if [ "$VEREDITO" = "concordo" ]; then
    ok=$((ok + 1))
    echo "  ok   parecer: stdout = veredito '$VEREDITO'"
  else
    falhou=$((falhou + 1))
    echo "  FALHA parecer: stdout deveria ser 'concordo', foi '$VEREDITO'"
  fi

  # Verificar que stderr tem parecer (multilinhas)
  PARECER_STDERR=$(cd "$TEMP_REPO_PARECER" && node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA_PARECER" --head "$HEAD_SHA_PARECER" --criterio "$CRITERIO_FILE_PARECER" --cli-cmd "node $FIXTURE_PARECER" 2>&1 1>/dev/null | head -2)
  if echo "$PARECER_STDERR" | grep -q "Analisando"; then
    ok=$((ok + 1))
    echo "  ok   parecer: stderr tem texto do parecer"
  else
    falhou=$((falhou + 1))
    echo "  FALHA parecer: stderr deveria conter parecer, foi: $PARECER_STDERR"
  fi
fi

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
