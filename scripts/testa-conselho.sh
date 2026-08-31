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
echo "== CASO 4: pareceres-completos-fecham =="
TEMPDIR4="$RAIZ/test-pareceres-completos"
mkdir -p "$TEMPDIR4"

# Create test question file
echo "# Questão de teste para rodada com pareceres" > "$TEMPDIR4/questao-pareceres.md"

# Create membros.json with valid config
mkdir -p "$TEMPDIR4/.rainforest/conselho"
cat > "$TEMPDIR4/.rainforest/conselho/membros.json" << 'EOF'
{
  "membros": [
    {"nome": "cetico", "cmd": "echo ok", "ligado": true},
    {"nome": "arquiteto", "cmd": "echo ok", "ligado": true},
    {"nome": "usuario-final", "cmd": "echo ok", "ligado": true}
  ]
}
EOF

# Open rodada
testa "pareceres: abrir rodada" "0" \
  bash -c "cd '$TEMPDIR4' && RFM_ESTADO_ROOT='$TEMPDIR4' node '$CONSELHO' abrir --questao questao-pareceres.md"

# Find the rodada directory that was just created
RODADA_DIR4=$(ls -1d "$TEMPDIR4/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -z "$RODADA_DIR4" ]; then
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada para os pareceres"
else
  # Manually create parecer files with valid JSON for all 3 members
  mkdir -p "$RODADA_DIR4"
  echo '{"posicao":"OK","argumentos":["A1","A2"],"objecoes":["O1"],"riscos":["R1"]}' > "$RODADA_DIR4/parecer-cetico.json"
  echo '{"posicao":"OK","argumentos":["A1","A2"],"objecoes":["O1"],"riscos":["R1"]}' > "$RODADA_DIR4/parecer-arquiteto.json"
  echo '{"posicao":"OK","argumentos":["A1","A2"],"objecoes":["O1"],"riscos":["R1"]}' > "$RODADA_DIR4/parecer-usuario-final.json"

  # Check that all 3 parecer files were created
  PARECER_COUNT=$(ls "$RODADA_DIR4"/parecer-*.json 2>/dev/null | wc -l)
  if [ "$PARECER_COUNT" = "3" ]; then
    ok=$((ok + 1))
    echo "  ok   3 arquivos de parecer criados"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $PARECER_COUNT arquivos de parecer, esperava 3"
  fi

  # Run conferir --fase pareceres - should pass
  testa "pareceres: conferir fase pareceres" "0" \
    bash -c "cd '$TEMPDIR4' && RFM_ESTADO_ROOT='$TEMPDIR4' node '$CONSELHO' conferir --fase pareceres"
fi

echo ""
echo "== CASO 5: membro-indisponivel-reprova =="
TEMPDIR5="$RAIZ/test-membro-indisponivel"
mkdir -p "$TEMPDIR5"

# Create test question file
echo "# Questão para teste de membro indisponível" > "$TEMPDIR5/questao-indisponivel.md"

# Create membros.json with one failed member
FIXTURE_OK="$SRC/scripts/fixtures/conselho/membro-ok.cjs"
FIXTURE_FALHA="$SRC/scripts/fixtures/conselho/membro-falha.cjs"
FIXTURE_OK_JSON=$(echo "$FIXTURE_OK" | sed 's/\\/\\\\/g')
FIXTURE_FALHA_JSON=$(echo "$FIXTURE_FALHA" | sed 's/\\/\\\\/g')

mkdir -p "$TEMPDIR5/.rainforest/conselho"
cat > "$TEMPDIR5/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_OK_JSON\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_FALHA_JSON\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_OK_JSON\" {prompt} {saida}", "ligado": true}
  ]
}
EOF

# Open rodada
bash -c "cd '$TEMPDIR5' && RFM_ESTADO_ROOT='$TEMPDIR5' node '$CONSELHO' abrir --questao questao-indisponivel.md" 2>/dev/null

# Find the rodada directory
RODADA_DIR5=$(ls -1d "$TEMPDIR5/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR5" ]; then
  # Try to run pareceres - should fail
  saida_pareceres=$(bash -c "cd '$TEMPDIR5' && RFM_ESTADO_ROOT='$TEMPDIR5' node '$CONSELHO' pareceres" 2>&1)
  exit_pareceres=$?

  if [ "$exit_pareceres" != "0" ]; then
    ok=$((ok + 1))
    echo "  ok   pareceres reprovou com exit $exit_pareceres"
    # Check if it mentions the failed member
    if echo "$saida_pareceres" | grep -q "arquiteto"; then
      ok=$((ok + 1))
      echo "  ok   saída menciona o membro indisponível"
    else
      falhou=$((falhou + 1))
      echo "  FALHA saída não menciona o membro indisponível"
      echo "$saida_pareceres" | sed 's/^/         /'
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA pareceres deveria ter saído com erro"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 6: json-invalido-reprova-apontando-campo =="
TEMPDIR6="$RAIZ/test-json-invalido"
mkdir -p "$TEMPDIR6"

# Create test question file
echo "# Questão para teste de JSON inválido" > "$TEMPDIR6/questao-json-invalido.md"

# Create membros.json with valid config
mkdir -p "$TEMPDIR6/.rainforest/conselho"
cat > "$TEMPDIR6/.rainforest/conselho/membros.json" << 'EOF'
{
  "membros": [
    {"nome": "cetico", "cmd": "echo ok", "ligado": true},
    {"nome": "arquiteto", "cmd": "echo ok", "ligado": true},
    {"nome": "usuario-final", "cmd": "echo ok", "ligado": true}
  ]
}
EOF

# Open rodada
bash -c "cd '$TEMPDIR6' && RFM_ESTADO_ROOT='$TEMPDIR6' node '$CONSELHO' abrir --questao questao-json-invalido.md" 2>/dev/null

# Find the rodada directory
RODADA_DIR6=$(ls -1d "$TEMPDIR6/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR6" ]; then
  # Manually create parecer files with invalid JSON for one member
  mkdir -p "$RODADA_DIR6"
  echo '{"posicao":"OK","argumentos":["A"],"objecoes":["O"],"riscos":["R"]}' > "$RODADA_DIR6/parecer-cetico.json"
  echo 'isso não é json válido {]' > "$RODADA_DIR6/parecer-arquiteto.json"
  echo '{"posicao":"OK","argumentos":["A"],"objecoes":["O"],"riscos":["R"]}' > "$RODADA_DIR6/parecer-usuario-final.json"

  # Try to conferir - should fail with JSON error
  saida_conferir=$(bash -c "cd '$TEMPDIR6' && RFM_ESTADO_ROOT='$TEMPDIR6' node '$CONSELHO' conferir --fase pareceres" 2>&1)
  exit_conferir=$?

  if [ "$exit_conferir" != "0" ]; then
    ok=$((ok + 1))
    echo "  ok   conferir reprovou com exit $exit_conferir"
    # Check if it mentions the member with invalid JSON
    if echo "$saida_conferir" | grep -q "arquiteto"; then
      ok=$((ok + 1))
      echo "  ok   saída menciona o membro com JSON inválido"
    else
      falhou=$((falhou + 1))
      echo "  FALHA saída não menciona o membro"
      echo "$saida_conferir" | sed 's/^/         /'
    fi
    # Check if it mentions JSON error
    if echo "$saida_conferir" | grep -q -i "json"; then
      ok=$((ok + 1))
      echo "  ok   saída menciona erro JSON"
    else
      falhou=$((falhou + 1))
      echo "  FALHA saída não menciona erro JSON"
      echo "$saida_conferir" | sed 's/^/         /'
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA conferir deveria ter saído com erro"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 7: saida-vazia-reprova =="
TEMPDIR7="$RAIZ/test-saida-vazia"
mkdir -p "$TEMPDIR7"

# Create test question file
echo "# Questão para teste de saída vazia" > "$TEMPDIR7/questao-vazia.md"

# Create membros.json com um membro que sai vazio
FIXTURE_OK_FWD=$(echo "$SRC/scripts/fixtures/conselho/membro-ok.cjs" | tr '\\' '/')
FIXTURE_VAZIO_FWD=$(echo "$SRC/scripts/fixtures/conselho/membro-vazio.cjs" | tr '\\' '/')

mkdir -p "$TEMPDIR7/.rainforest/conselho"
cat > "$TEMPDIR7/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node $FIXTURE_OK_FWD {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node $FIXTURE_VAZIO_FWD {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node $FIXTURE_OK_FWD {prompt} {saida}", "ligado": true}
  ]
}
EOF

# Open rodada
bash -c "cd '$TEMPDIR7' && RFM_ESTADO_ROOT='$TEMPDIR7' node '$CONSELHO' abrir --questao questao-vazia.md" 2>/dev/null

# Find the rodada directory
RODADA_DIR7=$(ls -1d "$TEMPDIR7/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR7" ]; then
  # Try to run pareceres - should fail
  saida_pareceres=$(bash -c "cd '$TEMPDIR7' && RFM_ESTADO_ROOT='$TEMPDIR7' node '$CONSELHO' pareceres" 2>&1)
  exit_pareceres=$?

  if [ "$exit_pareceres" != "0" ]; then
    ok=$((ok + 1))
    echo "  ok   pareceres reprovou com exit $exit_pareceres"
    # Check if it mentions the member with empty output
    if echo "$saida_pareceres" | grep -q "arquiteto"; then
      ok=$((ok + 1))
      echo "  ok   saída menciona o membro com saída vazia"
    else
      falhou=$((falhou + 1))
      echo "  FALHA saída não menciona o membro"
      echo "$saida_pareceres" | sed 's/^/         /'
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA pareceres deveria ter saído com erro"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== Resultado =="
echo "total=$((ok + falhou)) vermelhas:[$falhou]"
if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
