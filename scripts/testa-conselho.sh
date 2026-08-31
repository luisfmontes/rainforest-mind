#!/bin/bash
# Bateria para conselho.cjs — debate estruturado de decisões de design
# Uso: bash scripts/testa-conselho.sh
#
# Testa o comando `abrir --questao`, resolução de membros, quórum e geração de rodada.
# Roda em diretório temporário, nunca modifica o repo.

set -u

# Get source directory
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_M="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
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

# Create membros.json apontando os 3 membros para a fixture membro-ok
FIXTURE_OK4_JSON="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
mkdir -p "$TEMPDIR4/.rainforest/conselho"
cat > "$TEMPDIR4/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_OK4_JSON\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_OK4_JSON\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_OK4_JSON\" {prompt} {saida}", "ligado": true}
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
  # Run the REAL pareceres subcommand — o caminho feliz que este caso mede
  testa "pareceres: subcomando pareceres coleta os 3" "0"     bash -c "cd '$TEMPDIR4' && RFM_ESTADO_ROOT='$TEMPDIR4' node '$CONSELHO' pareceres"

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
FIXTURE_OK="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
FIXTURE_FALHA="$SRC_M/scripts/fixtures/conselho/membro-falha.cjs"
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
FIXTURE_OK_FWD=$(echo "$SRC_M/scripts/fixtures/conselho/membro-ok.cjs" | tr '\\' '/')
FIXTURE_VAZIO_FWD=$(echo "$SRC_M/scripts/fixtures/conselho/membro-vazio.cjs" | tr '\\' '/')

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
echo "== CASO 8: revisar-fecha-com-3 =="
TEMPDIR8="$RAIZ/test-revisar-ok"
mkdir -p "$TEMPDIR8"

# Create test question file
echo "# Questão para teste de revisão" > "$TEMPDIR8/questao-revisao.md"

# Create membros.json com fixtures ok para parecer + revisor ok para revisão
FIXTURE_OK_M="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
FIXTURE_REVISOR_OK="$SRC_M/scripts/fixtures/conselho/membro-revisor-ok.cjs"

mkdir -p "$TEMPDIR8/.rainforest/conselho"
cat > "$TEMPDIR8/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_OK_M\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_OK_M\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_OK_M\" {prompt} {saida}", "ligado": true}
  ]
}
EOF

# Open rodada
bash -c "cd '$TEMPDIR8' && RFM_ESTADO_ROOT='$TEMPDIR8' node '$CONSELHO' abrir --questao questao-revisao.md" 2>/dev/null

# Find the rodada directory
RODADA_DIR8=$(ls -1d "$TEMPDIR8/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR8" ]; then
  # Collect pareceres
  bash -c "cd '$TEMPDIR8' && RFM_ESTADO_ROOT='$TEMPDIR8' node '$CONSELHO' pareceres" 2>/dev/null

  # Check pareceres phase
  testa "revisar: fase pareceres válida" "0" \
    bash -c "cd '$TEMPDIR8' && RFM_ESTADO_ROOT='$TEMPDIR8' node '$CONSELHO' conferir --fase pareceres"

  # Now change membros.json to use revisores para a fase 2
  cat > "$TEMPDIR8/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_REVISOR_OK\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_REVISOR_OK\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_REVISOR_OK\" {prompt} {saida}", "ligado": true}
  ]
}
EOF

  # Run revisar
  testa "revisar: subcomando revisar coleta os 3" "0" \
    bash -c "cd '$TEMPDIR8' && RFM_ESTADO_ROOT='$TEMPDIR8' node '$CONSELHO' revisar"

  # Check that fase2 directory exists and has revisao files
  if [ -d "$RODADA_DIR8/fase2" ]; then
    REVISAO_COUNT=$(ls "$RODADA_DIR8/fase2"/revisao-*.json 2>/dev/null | wc -l)
    if [ "$REVISAO_COUNT" = "3" ]; then
      ok=$((ok + 1))
      echo "  ok   3 arquivos de revisão criados"
    else
      falhou=$((falhou + 1))
      echo "  FALHA $REVISAO_COUNT arquivos de revisão, esperava 3"
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA diretório fase2 não foi criado"
  fi

  # Run conferir --fase revisao - should pass
  testa "revisar: conferir fase revisao" "0" \
    bash -c "cd '$TEMPDIR8' && RFM_ESTADO_ROOT='$TEMPDIR8' node '$CONSELHO' conferir --fase revisao"
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 9: identidade-nao-vaza =="
if [ -d "$RODADA_DIR8/fase2" ]; then
  # Check that real member names do not appear in distributed files
  GREP_RESULT=$(grep -rE 'cetico|arquiteto|usuario-final' "$RODADA_DIR8/fase2" 2>&1)
  if [ -z "$GREP_RESULT" ]; then
    ok=$((ok + 1))
    echo "  ok   nenhum nome real na fase2"
  else
    falhou=$((falhou + 1))
    echo "  FALHA nomes reais encontrados na fase2:"
    echo "$GREP_RESULT" | sed 's/^/         /'
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu verificar (fase2 não existe)"
fi

echo ""
echo "== CASO 10: ranking-incompleto-reprova =="
TEMPDIR10="$RAIZ/test-ranking-incompleto"
mkdir -p "$TEMPDIR10"

# Create test question file
echo "# Questão para teste de ranking incompleto" > "$TEMPDIR10/questao-incompleto.md"

# Create membros.json with ok parecers and one incomplete reviewer
FIXTURE_OK_T10="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
FIXTURE_INCOMPLETO="$SRC_M/scripts/fixtures/conselho/membro-ranking-incompleto.cjs"

mkdir -p "$TEMPDIR10/.rainforest/conselho"
cat > "$TEMPDIR10/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_OK_T10\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_OK_T10\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_OK_T10\" {prompt} {saida}", "ligado": true}
  ]
}
EOF

# Open rodada
bash -c "cd '$TEMPDIR10' && RFM_ESTADO_ROOT='$TEMPDIR10' node '$CONSELHO' abrir --questao questao-incompleto.md" 2>/dev/null

# Find rodada
RODADA_DIR10=$(ls -1d "$TEMPDIR10/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR10" ]; then
  # Collect pareceres
  bash -c "cd '$TEMPDIR10' && RFM_ESTADO_ROOT='$TEMPDIR10' node '$CONSELHO' pareceres" 2>/dev/null

  # Now manually create fase2 with incomplete ranking for one member
  mkdir -p "$RODADA_DIR10/fase2"

  # Create incomplete revisao for cetico
  cat > "$RODADA_DIR10/fase2/revisao-cetico.json" << 'EOF'
{"ranking": ["membro-A"], "criticas": {"membro-A": "Crítica"}}
EOF

  # Create complete revisoes for others
  cat > "$RODADA_DIR10/fase2/revisao-arquiteto.json" << 'EOF'
{"ranking": ["membro-A", "membro-B"], "criticas": {"membro-A": "Crítica A", "membro-B": "Crítica B"}}
EOF

  cat > "$RODADA_DIR10/fase2/revisao-usuario-final.json" << 'EOF'
{"ranking": ["membro-A", "membro-B"], "criticas": {"membro-A": "Crítica A", "membro-B": "Crítica B"}}
EOF

  # Try to conferir - should fail
  saida_conferir=$(bash -c "cd '$TEMPDIR10' && RFM_ESTADO_ROOT='$TEMPDIR10' node '$CONSELHO' conferir --fase revisao" 2>&1)
  exit_conferir=$?

  if [ "$exit_conferir" != "0" ]; then
    ok=$((ok + 1))
    echo "  ok   ranking incompleto reprovou com exit $exit_conferir"
    # Check if it mentions the member
    if echo "$saida_conferir" | grep -q "cetico"; then
      ok=$((ok + 1))
      echo "  ok   saída menciona o membro com ranking incompleto"
    else
      falhou=$((falhou + 1))
      echo "  FALHA saída não menciona o membro"
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
echo "== CASO 11: cada-um-recebe-so-os-outros =="
if [ -d "$RODADA_DIR8/fase2" ]; then
  # Check that pacote-prompt for cetico does not contain parecer do cetico himself
  PACOTE_CETICO="$RODADA_DIR8/fase2/pacote-prompt-cetico.json"

  if [ -f "$PACOTE_CETICO" ]; then
    # Extract posicao values from pareceres (they have distinguishing text)
    POSICOES=$(grep -o '"posicao": "[^"]*' "$PACOTE_CETICO" | wc -l)
    # Expected: 2 pareceres (from arquiteto and usuario-final), not 3

    if [ "$POSICOES" = "2" ]; then
      ok=$((ok + 1))
      echo "  ok   cetico recebe 2 pareceres (dos outros 2 membros)"
    else
      falhou=$((falhou + 1))
      echo "  FALHA cetico recebe $POSICOES pareceres, esperava 2"
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA pacote-prompt-cetico.json não encontrado"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu verificar (fase2 não existe)"
fi

echo ""
echo "== CASO 12: agregacao-conhecida =="
# Test with THREE FIXED rankings where the aggregated result differs from FIRST reviewer
# With 3 members, each reviewer rates 2 others (N-1)
# Reviewer 1 (cetico): [membro-B, membro-C] — primeira posição para B
# Reviewer 2 (arquiteto): [membro-C, membro-B] — primeira posição para C
# Reviewer 3 (usuario-final): [membro-C, membro-B] — primeira posição para C
#
# Aggregation by average position (lower is better):
#   membro-B: (0 + 1 + 1) / 3 = 0.666...
#   membro-C: (1 + 0 + 0) / 3 = 0.333...
#
# Expected ranking: [membro-C, membro-B]  (C has lower average)
# This DIFFERS from reviewer 1's ranking [membro-B, membro-C]
# Mutation that uses just first reviewer should get [membro-B, membro-C] and FAIL

TEMPDIR12="$RAIZ/test-agregacao-conhecida"
mkdir -p "$TEMPDIR12"

# Create test question file
echo "# Questão para teste de agregação" > "$TEMPDIR12/questao-agregacao.md"

# Create membros.json
FIXTURE_OK_AGR="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"

mkdir -p "$TEMPDIR12/.rainforest/conselho"
cat > "$TEMPDIR12/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_OK_AGR\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_OK_AGR\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_OK_AGR\" {prompt} {saida}", "ligado": true}
  ]
}
EOF

# Open rodada
bash -c "cd '$TEMPDIR12' && RFM_ESTADO_ROOT='$TEMPDIR12' node '$CONSELHO' abrir --questao questao-agregacao.md" 2>/dev/null

# Find rodada
RODADA_DIR12=$(ls -1d "$TEMPDIR12/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR12" ]; then
  # Collect pareceres
  bash -c "cd '$TEMPDIR12' && RFM_ESTADO_ROOT='$TEMPDIR12' node '$CONSELHO' pareceres" 2>/dev/null

  # Now create mapa-anonimato manually for the test
  # With 3 members, each reviewer will rate 2 others
  # cetico will rate: arquiteto (membro-B) and usuario-final (membro-C)
  # arquiteto will rate: cetico (membro-A) and usuario-final (membro-C)
  # usuario-final will rate: cetico (membro-A) and arquiteto (membro-B)
  cat > "$RODADA_DIR12/mapa-anonimato.json" << 'EOF'
{
  "cetico": "membro-A",
  "arquiteto": "membro-B",
  "usuario-final": "membro-C"
}
EOF

  # Create fase2 with FIXED rankings based on the mapa above
  # Each reviewer rates N-1 = 2 others
  mkdir -p "$RODADA_DIR12/fase2"

  # cetico rates [membro-B, membro-C] — FIRST REVIEWER (mutation will copy this)
  cat > "$RODADA_DIR12/fase2/revisao-cetico.json" << 'EOF'
{"ranking": ["membro-B", "membro-C"], "criticas": {"membro-B": "Crítica B", "membro-C": "Crítica C"}}
EOF

  # arquiteto rates [membro-C, membro-B]
  cat > "$RODADA_DIR12/fase2/revisao-arquiteto.json" << 'EOF'
{"ranking": ["membro-C", "membro-B"], "criticas": {"membro-B": "Crítica B", "membro-C": "Crítica C"}}
EOF

  # usuario-final rates [membro-C, membro-B]
  cat > "$RODADA_DIR12/fase2/revisao-usuario-final.json" << 'EOF'
{"ranking": ["membro-C", "membro-B"], "criticas": {"membro-B": "Crítica B", "membro-C": "Crítica C"}}
EOF

  # Validate revisao phase
  bash -c "cd '$TEMPDIR12' && RFM_ESTADO_ROOT='$TEMPDIR12' node '$CONSELHO' conferir --fase revisao" 2>/dev/null

  # Run sintetizar — should succeed WITHOUT --unanime (divergências presentes)
  saida_sintese=$(bash -c "cd '$TEMPDIR12' && RFM_ESTADO_ROOT='$TEMPDIR12' node '$CONSELHO' sintetizar" 2>&1)
  exit_sintese=$?

  if [ "$exit_sintese" = "0" ]; then
    # Read sintese.json and check ranking_agregado
    if [ -f "$RODADA_DIR12/sintese.json" ]; then
      RANKING_JSON=$(cat "$RODADA_DIR12/sintese.json")

      ok=$((ok + 1))
      echo "  ok   agregacao-conhecida: sintetizar exit 0 SEM --unanime"

      # Extract ranking_agregado from JSON
      # Expected: membro-C (avg 0.33), membro-B (avg 0.66)
      # The aggregated ranking should be: [usuario-final, arquiteto] (desanonymized)
      # This DIFFERS from first reviewer's [arquiteto, usuario-final]
      # Check ranking_agregado field and verify first element is usuario-final
      FIRST_ELEM=$(echo "$RANKING_JSON" | grep -oE '"ranking_agregado"[^]]+\[' | grep -oE '\["[^"]*' | grep -oE '"[^"]*"' | head -1 | tr -d '"')

      if [ -z "$FIRST_ELEM" ]; then
        # Try alternative extraction if above fails
        FIRST_ELEM=$(echo "$RANKING_JSON" | sed -n '/"ranking_agregado":/,/]/p' | grep -oE '"[a-z-]*"' | head -1 | tr -d '"')
      fi

      if [ "$FIRST_ELEM" = "usuario-final" ]; then
        ok=$((ok + 1))
        echo "  ok   ranking_agregado correto: usuario-final é primeiro"
      else
        falhou=$((falhou + 1))
        echo "  FALHA ranking_agregado: primeiro elemento é '$FIRST_ELEM', esperava 'usuario-final'"
      fi
    else
      falhou=$((falhou + 1))
      echo "  FALHA agregacao-conhecida: sintese.json não foi criado"
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA agregacao-conhecida: sintetizar deveria ter exit 0"
    echo "$saida_sintese" | sed 's/^/         /'
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 13: sintese-grava-com-divergencias =="
TEMPDIR13="$RAIZ/test-sintese-divergencias"
mkdir -p "$TEMPDIR13"

# Create test question file
echo "# Questão para teste de síntese com divergências" > "$TEMPDIR13/questao-sintese.md"

# Create membros.json with revisores
FIXTURE_OK_SIN="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
FIXTURE_REVISOR_SIN="$SRC_M/scripts/fixtures/conselho/membro-revisor-ok.cjs"

mkdir -p "$TEMPDIR13/.rainforest/conselho"
# First stage: parecerers use OK fixture
cat > "$TEMPDIR13/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_OK_SIN\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_OK_SIN\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_OK_SIN\" {prompt} {saida}", "ligado": true}
  ]
}
EOF

# Open rodada
bash -c "cd '$TEMPDIR13' && RFM_ESTADO_ROOT='$TEMPDIR13' node '$CONSELHO' abrir --questao questao-sintese.md" 2>/dev/null

# Find rodada
RODADA_DIR13=$(ls -1d "$TEMPDIR13/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR13" ]; then
  # Collect pareceres
  bash -c "cd '$TEMPDIR13' && RFM_ESTADO_ROOT='$TEMPDIR13' node '$CONSELHO' pareceres" 2>/dev/null

  # Update membros.json to use revisor fixture for phase 2
  cat > "$TEMPDIR13/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_REVISOR_SIN\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_REVISOR_SIN\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_REVISOR_SIN\" {prompt} {saida}", "ligado": true}
  ]
}
EOF

  # Run revisar
  bash -c "cd '$TEMPDIR13' && RFM_ESTADO_ROOT='$TEMPDIR13' node '$CONSELHO' revisar" 2>/dev/null

  # Validate revisao
  bash -c "cd '$TEMPDIR13' && RFM_ESTADO_ROOT='$TEMPDIR13' node '$CONSELHO' conferir --fase revisao" 2>/dev/null

  # Run sintetizar — should succeed WITHOUT --unanime (divergências presentes = honesto)
  saida_sintese=$(bash -c "cd '$TEMPDIR13' && RFM_ESTADO_ROOT='$TEMPDIR13' node '$CONSELHO' sintetizar" 2>&1)
  exit_sintese=$?

  if [ "$exit_sintese" = "0" ]; then
    ok=$((ok + 1))
    echo "  ok   sintese-grava-com-divergencias: exit 0 SEM --unanime"

    # Check that sintese.json was created with 4 fields
    if [ -f "$RODADA_DIR13/sintese.json" ]; then
      SINTESE_CONTENT=$(cat "$RODADA_DIR13/sintese.json")

      # Check for required fields
      if echo "$SINTESE_CONTENT" | grep -q '"decisao_recomendada"'; then
        ok=$((ok + 1))
        echo "  ok   sintese.json contém decisao_recomendada"
      else
        falhou=$((falhou + 1))
        echo "  FALHA sintese.json sem decisao_recomendada"
      fi

      if echo "$SINTESE_CONTENT" | grep -q '"fundamentos"'; then
        ok=$((ok + 1))
        echo "  ok   sintese.json contém fundamentos"
      else
        falhou=$((falhou + 1))
        echo "  FALHA sintese.json sem fundamentos"
      fi

      if echo "$SINTESE_CONTENT" | grep -q '"divergencias_nao_resolvidas"'; then
        ok=$((ok + 1))
        echo "  ok   sintese.json contém divergencias_nao_resolvidas"
      else
        falhou=$((falhou + 1))
        echo "  FALHA sintese.json sem divergencias_nao_resolvidas"
      fi

      if echo "$SINTESE_CONTENT" | grep -q '"ranking_agregado"'; then
        ok=$((ok + 1))
        echo "  ok   sintese.json contém ranking_agregado"
      else
        falhou=$((falhou + 1))
        echo "  FALHA sintese.json sem ranking_agregado"
      fi

      # Verify ranking_agregado has real names (desanonymized), not apelidos
      if echo "$SINTESE_CONTENT" | grep -q 'cetico\|arquiteto\|usuario-final'; then
        ok=$((ok + 1))
        echo "  ok   ranking_agregado com nomes reais (desanonymized)"
      else
        falhou=$((falhou + 1))
        echo "  FALHA ranking_agregado sem nomes reais"
        echo "$SINTESE_CONTENT" | sed 's/^/         /'
      fi
    else
      falhou=$((falhou + 1))
      echo "  FALHA sintese.json não foi criado"
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA sintese-grava-com-divergencias: sintetizar deveria ter exit 0 com --unanime"
    echo "$saida_sintese" | sed 's/^/         /'
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 14: sintese-unanime-exige-flag =="
# Cenário: pareceres SEM objeções + rankings idênticos = divergências VAZIAS
# Esperado: sem --unanime → exit ≠ 0; com --unanime → exit 0
TEMPDIR14="$RAIZ/test-sintese-unanime"
mkdir -p "$TEMPDIR14"

# Create test question file
echo "# Questão para teste de unanimidade" > "$TEMPDIR14/questao-unanime.md"

# Create membros.json
mkdir -p "$TEMPDIR14/.rainforest/conselho"
cat > "$TEMPDIR14/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_OK_SIN\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_OK_SIN\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_OK_SIN\" {prompt} {saida}", "ligado": true}
  ]
}
EOF

# Open rodada
bash -c "cd '$TEMPDIR14' && RFM_ESTADO_ROOT='$TEMPDIR14' node '$CONSELHO' abrir --questao questao-unanime.md" 2>/dev/null

# Find rodada
RODADA_DIR14=$(ls -1d "$TEMPDIR14/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR14" ]; then
  # Manually create PARECERES SEM OBJEÇÕES
  mkdir -p "$RODADA_DIR14"
  cat > "$RODADA_DIR14/parecer-cetico.json" << 'EOF'
{"posicao": "Posição A", "argumentos": ["Arg 1", "Arg 2"], "objecoes": [], "riscos": []}
EOF
  cat > "$RODADA_DIR14/parecer-arquiteto.json" << 'EOF'
{"posicao": "Posição A", "argumentos": ["Arg 1", "Arg 2"], "objecoes": [], "riscos": []}
EOF
  cat > "$RODADA_DIR14/parecer-usuario-final.json" << 'EOF'
{"posicao": "Posição A", "argumentos": ["Arg 1", "Arg 2"], "objecoes": [], "riscos": []}
EOF

  # Create mapa-anonimato
  cat > "$RODADA_DIR14/mapa-anonimato.json" << 'EOF'
{"cetico": "membro-A", "arquiteto": "membro-B", "usuario-final": "membro-C"}
EOF

  # Create fase2 with IDENTICAL rankings (no spread, no divergencies)
  mkdir -p "$RODADA_DIR14/fase2"
  cat > "$RODADA_DIR14/fase2/revisao-cetico.json" << 'EOF'
{"ranking": ["membro-B", "membro-C"], "criticas": {"membro-B": "Crítica B", "membro-C": "Crítica C"}}
EOF
  cat > "$RODADA_DIR14/fase2/revisao-arquiteto.json" << 'EOF'
{"ranking": ["membro-B", "membro-C"], "criticas": {"membro-B": "Crítica B", "membro-C": "Crítica C"}}
EOF
  cat > "$RODADA_DIR14/fase2/revisao-usuario-final.json" << 'EOF'
{"ranking": ["membro-B", "membro-C"], "criticas": {"membro-B": "Crítica B", "membro-C": "Crítica C"}}
EOF

  # Try sintetizar WITHOUT --unanime flag — should fail (consenso fabricado sem divergências)
  saida_sem_flag=$(bash -c "cd '$TEMPDIR14' && RFM_ESTADO_ROOT='$TEMPDIR14' node '$CONSELHO' sintetizar" 2>&1)
  exit_sem_flag=$?

  if [ "$exit_sem_flag" != "0" ]; then
    ok=$((ok + 1))
    echo "  ok   sem divergências SEM --unanime: exit != 0"
  else
    falhou=$((falhou + 1))
    echo "  FALHA sem divergências SEM --unanime: deveria ter saído com erro"
  fi

  # Try sintetizar WITH --unanime flag — should succeed (escape explícito autorizado)
  saida_com_flag=$(bash -c "cd '$TEMPDIR14' && RFM_ESTADO_ROOT='$TEMPDIR14' node '$CONSELHO' sintetizar --unanime" 2>&1)
  exit_com_flag=$?

  if [ "$exit_com_flag" = "0" ]; then
    ok=$((ok + 1))
    echo "  ok   sem divergências COM --unanime: exit 0"
  else
    falhou=$((falhou + 1))
    echo "  FALHA sem divergências COM --unanime: deveria ter exit 0"
    echo "$saida_com_flag" | sed 's/^/         /'
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 15: parecer-sem-objecao-reprova-citando-membro =="
TEMPDIR15="$RAIZ/test-parecer-sem-objecao"
mkdir -p "$TEMPDIR15/.rainforest/conselho"

# Create minimal membros.json
cat > "$TEMPDIR15/.rainforest/conselho/membros.json" << 'EOF'
{
  "membros": [
    {"nome": "cetico", "cmd": "cat '$FIXTURE_DIR/membro-sem-objecao.cjs' > {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true}
  ]
}
EOF

echo "# Questão de teste" > "$TEMPDIR15/questao.md"

# Use fixture directory via environment
FIXTURE_DIR="$SRC_M/scripts/fixtures/conselho"

# Manually open a rodada
bash -c "cd '$TEMPDIR15' && RFM_ESTADO_ROOT='$TEMPDIR15' node '$CONSELHO' abrir --questao questao.md" 2>/dev/null

# Create specific parecer files
RODADA_DIR15=$(ls -1d "$TEMPDIR15/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR15" ]; then
  # cetico with objecoes: []
  cat > "$RODADA_DIR15/parecer-cetico.json" << 'EOF'
{"posicao": "A", "argumentos": ["Arg 1"], "objecoes": [], "riscos": []}
EOF
  # arquiteto with objecoes: [obj]
  cat > "$RODADA_DIR15/parecer-arquiteto.json" << 'EOF'
{"posicao": "A", "argumentos": ["Arg 1"], "objecoes": ["Objecao 1"], "riscos": []}
EOF
  # usuario-final with objecoes: [obj]
  cat > "$RODADA_DIR15/parecer-usuario-final.json" << 'EOF'
{"posicao": "A", "argumentos": ["Arg 1"], "objecoes": ["Objecao 1"], "riscos": []}
EOF

  # Run conferir - should fail with cetico cited
  saida=$(bash -c "cd '$TEMPDIR15' && RFM_ESTADO_ROOT='$TEMPDIR15' node '$CONSELHO' conferir --fase pareceres" 2>&1)
  exit_code=$?

  if [ "$exit_code" != "0" ]; then
    ok=$((ok + 1))
    echo "  ok   parecer sem objeção: exit != 0"

    # Check that cetico is cited in output
    if echo "$saida" | grep -q "cetico"; then
      ok=$((ok + 1))
      echo "  ok   mensagem cita membro cetico"
    else
      falhou=$((falhou + 1))
      echo "  FALHA mensagem deveria citar cetico"
      echo "$saida" | sed 's/^/         /'
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA conferir deveria ter saído com erro para parecer sem objeção"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 16: sintese-invalida-reprova =="
TEMPDIR16="$RAIZ/test-sintese-invalida"
mkdir -p "$TEMPDIR16/.rainforest/conselho"

# Create minimal membros.json
cat > "$TEMPDIR16/.rainforest/conselho/membros.json" << 'EOF'
{
  "membros": [
    {"nome": "cetico", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true}
  ]
}
EOF

echo "# Questão de teste" > "$TEMPDIR16/questao.md"

# Manually open a rodada
bash -c "cd '$TEMPDIR16' && RFM_ESTADO_ROOT='$TEMPDIR16' node '$CONSELHO' abrir --questao questao.md" 2>/dev/null

RODADA_DIR16=$(ls -1d "$TEMPDIR16/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR16" ]; then
  # Create INVALID sintese.json (missing ranking_agregado)
  cat > "$RODADA_DIR16/sintese.json" << 'EOF'
{"decisao_recomendada": "A", "fundamentos": ["F1"], "divergencias_nao_resolvidas": ["D1"]}
EOF

  # Run conferir --fase sintese - should fail pointing to missing field
  saida=$(bash -c "cd '$TEMPDIR16' && RFM_ESTADO_ROOT='$TEMPDIR16' node '$CONSELHO' conferir --fase sintese" 2>&1)
  exit_code=$?

  if [ "$exit_code" != "0" ]; then
    ok=$((ok + 1))
    echo "  ok   sintese inválida: exit != 0"

    # Check that error mentions ranking_agregado
    if echo "$saida" | grep -q "ranking_agregado"; then
      ok=$((ok + 1))
      echo "  ok   mensagem aponta campo ranking_agregado"
    else
      falhou=$((falhou + 1))
      echo "  FALHA mensagem deveria apontar ranking_agregado"
      echo "$saida" | sed 's/^/         /'
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA conferir deveria ter saído com erro para sintese inválida"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 17: terceira-reprovacao-abandona =="
TEMPDIR17="$RAIZ/test-terceira-reprova"
mkdir -p "$TEMPDIR17/.rainforest/conselho"

# Create minimal membros.json
cat > "$TEMPDIR17/.rainforest/conselho/membros.json" << 'EOF'
{
  "membros": [
    {"nome": "cetico", "cmd": "echo bad", "ligado": true},
    {"nome": "arquiteto", "cmd": "echo bad", "ligado": true},
    {"nome": "usuario-final", "cmd": "echo bad", "ligado": true}
  ]
}
EOF

echo "# Questão de teste" > "$TEMPDIR17/questao.md"

# Manually open a rodada
bash -c "cd '$TEMPDIR17' && RFM_ESTADO_ROOT='$TEMPDIR17' node '$CONSELHO' abrir --questao questao.md" 2>/dev/null

RODADA_DIR17=$(ls -1d "$TEMPDIR17/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR17" ]; then
  # Create invalid pareceres (empty JSON files)
  echo "{}" > "$RODADA_DIR17/parecer-cetico.json"
  echo "{}" > "$RODADA_DIR17/parecer-arquiteto.json"
  echo "{}" > "$RODADA_DIR17/parecer-usuario-final.json"

  # First conferir - should fail (tentativa = 1)
  bash -c "cd '$TEMPDIR17' && RFM_ESTADO_ROOT='$TEMPDIR17' node '$CONSELHO' conferir --fase pareceres" 2>/dev/null
  TENTATIVA_1=$?

  # Check estado after first failure
  if [ -f "$RODADA_DIR17/estado.json" ]; then
    RESULTADO_1=$(grep -o '"resultado"' "$RODADA_DIR17/estado.json" 2>/dev/null || echo "")
    if [ -z "$RESULTADO_1" ]; then
      ok=$((ok + 1))
      echo "  ok   após 1ª reprovação: sem ABANDONA"
    else
      falhou=$((falhou + 1))
      echo "  FALHA após 1ª reprovação: não deveria ter ABANDONA"
    fi
  fi

  # Second conferir - should fail (tentativa = 2)
  bash -c "cd '$TEMPDIR17' && RFM_ESTADO_ROOT='$TEMPDIR17' node '$CONSELHO' conferir --fase pareceres" 2>/dev/null
  TENTATIVA_2=$?

  # Check estado after second failure
  if [ -f "$RODADA_DIR17/estado.json" ]; then
    RESULTADO_2=$(grep -o '"resultado"' "$RODADA_DIR17/estado.json" 2>/dev/null || echo "")
    if [ -z "$RESULTADO_2" ]; then
      ok=$((ok + 1))
      echo "  ok   após 2ª reprovação: sem ABANDONA"
    else
      falhou=$((falhou + 1))
      echo "  FALHA após 2ª reprovação: não deveria ter ABANDONA"
    fi
  fi

  # Third conferir - should fail (tentativa = 3, ABANDONA!)
  bash -c "cd '$TEMPDIR17' && RFM_ESTADO_ROOT='$TEMPDIR17' node '$CONSELHO' conferir --fase pareceres" 2>/dev/null
  TENTATIVA_3=$?

  # Check estado after third failure
  if [ -f "$RODADA_DIR17/estado.json" ]; then
    RESULTADO_3=$(grep '"resultado"' "$RODADA_DIR17/estado.json" 2>/dev/null || echo "")
    if echo "$RESULTADO_3" | grep -q "ABANDONA"; then
      ok=$((ok + 1))
      echo "  ok   após 3ª reprovação: ABANDONA registrado"
    else
      falhou=$((falhou + 1))
      echo "  FALHA após 3ª reprovação: deveria ter ABANDONA"
      cat "$RODADA_DIR17/estado.json" | sed 's/^/         /'
    fi
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 18: sucesso-zera-contador =="
TEMPDIR18="$RAIZ/test-sucesso-zera"
mkdir -p "$TEMPDIR18/.rainforest/conselho"

# Create minimal membros.json
cat > "$TEMPDIR18/.rainforest/conselho/membros.json" << 'EOF'
{
  "membros": [
    {"nome": "cetico", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true}
  ]
}
EOF

echo "# Questão de teste" > "$TEMPDIR18/questao.md"

# Manually open a rodada
bash -c "cd '$TEMPDIR18' && RFM_ESTADO_ROOT='$TEMPDIR18' node '$CONSELHO' abrir --questao questao.md" 2>/dev/null

RODADA_DIR18=$(ls -1d "$TEMPDIR18/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR18" ]; then
  # Create invalid pareceres to cause first failure
  echo "{}" > "$RODADA_DIR18/parecer-cetico.json"
  echo "{}" > "$RODADA_DIR18/parecer-arquiteto.json"
  echo "{}" > "$RODADA_DIR18/parecer-usuario-final.json"

  # First conferir - should fail (tentativa = 1)
  bash -c "cd '$TEMPDIR18' && RFM_ESTADO_ROOT='$TEMPDIR18' node '$CONSELHO' conferir --fase pareceres" 2>/dev/null

  # Now fix the pareceres - create valid ones
  cat > "$RODADA_DIR18/parecer-cetico.json" << 'EOF'
{"posicao": "A", "argumentos": ["Arg 1"], "objecoes": ["Obj 1"], "riscos": []}
EOF
  cat > "$RODADA_DIR18/parecer-arquiteto.json" << 'EOF'
{"posicao": "A", "argumentos": ["Arg 1"], "objecoes": ["Obj 1"], "riscos": []}
EOF
  cat > "$RODADA_DIR18/parecer-usuario-final.json" << 'EOF'
{"posicao": "A", "argumentos": ["Arg 1"], "objecoes": ["Obj 1"], "riscos": []}
EOF

  # Second conferir - should succeed and ZERO the counter
  bash -c "cd '$TEMPDIR18' && RFM_ESTADO_ROOT='$TEMPDIR18' node '$CONSELHO' conferir --fase pareceres" 2>/dev/null
  RESULTADO=$?

  if [ "$RESULTADO" = "0" ]; then
    # Check that tentativa was reset to 0
    if [ -f "$RODADA_DIR18/estado.json" ]; then
      TENTATIVA=$(grep -o '"pareceres": 0' "$RODADA_DIR18/estado.json" 2>/dev/null || echo "")
      if [ -n "$TENTATIVA" ]; then
        ok=$((ok + 1))
        echo "  ok   após sucesso: tentativa zerada para 0"
      else
        falhou=$((falhou + 1))
        echo "  FALHA após sucesso: tentativa deveria estar zerada"
        cat "$RODADA_DIR18/estado.json" | sed 's/^/         /'
      fi
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA conferir deveria ter saído com sucesso"
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
