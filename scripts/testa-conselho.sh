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
CONSELHO="$SRC_M/scripts/conselho.cjs"

# Create sandbox
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT

echo "(caixa de areia: $RAIZ)"
echo ""

# Diretório de "dados" (~/.rainforest) vazio e isolado — usado pelos casos que
# precisam de config REALMENTE padrão (nenhuma chave ligada em lugar nenhum),
# sem depender do que estiver ligado no ~/.rainforest desta máquina real.
DADOS_VAZIO="$RAIZ/dados-vazio"
mkdir -p "$DADOS_VAZIO"

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
echo "== CASO 19: externo-desligado-fica-fora =="
# ACHADO da tarefa 8 (auditoria): a versão anterior deste caso não exercitava
# `abrir` nenhuma vez — o `node -e` só fazia `require(conselho.cjs)`, e como
# `main()` roda incondicionalmente no fim do módulo (sem guarda `require.main
# === module`), aquele require chamava main() com `process.argv[2]` indefinido,
# imprimia "Uso: ..." e saía com exit 1 ANTES de tocar em resolverMembros().
# O teste então só comparava o membros.json que ELE MESMO escreveu — nunca
# tocado pela produção — e por isso passava sempre, com qualquer implementação.
# Reescrito para rodar `abrir` de verdade, com projeto e dados isolados (config
# real desta máquina não deve vazar), e conferir os prompts realmente gerados —
# no mesmo padrão do CASO 20 (externo-ligado-entra), só que no estado oposto.
TEMPDIR19="$RAIZ/test-externo-desligado"
mkdir -p "$TEMPDIR19/.rainforest/conselho"

# Create membros.json - não deve ter codex/gemini ligados por padrão
cat > "$TEMPDIR19/.rainforest/conselho/membros.json" << 'EOF'
{
  "membros": [
    {"nome": "cetico", "cmd": "echo test", "ligado": true},
    {"nome": "arquiteto", "cmd": "echo test", "ligado": true},
    {"nome": "usuario-final", "cmd": "echo test", "ligado": true}
  ]
}
EOF

echo "# Questão de teste" > "$TEMPDIR19/questao.md"

# Roda `abrir` de verdade: CLAUDE_PROJECT_DIR sem .rainforest/config.json e
# RFM_ROOT apontando para uma pasta de dados vazia (sem config.json) — as duas
# camadas de config caem no padrão do código (conselho-codex/gemini = false).
testa "externo-desligado-fica-fora: abrir exit 0" "0" \
  bash -c "cd '$TEMPDIR19' && CLAUDE_PROJECT_DIR='$TEMPDIR19' RFM_ROOT='$DADOS_VAZIO' node '$CONSELHO' abrir --questao questao.md"

RODADA_DIR19=$(ls -1d "$TEMPDIR19/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR19" ]; then
  PROMPT_COUNT19=$(ls "$RODADA_DIR19"/prompt-*.md 2>/dev/null | wc -l)
  if [ "$PROMPT_COUNT19" = "3" ]; then
    ok=$((ok + 1))
    echo "  ok   config padrão: 3 prompts gerados (sem externo)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $PROMPT_COUNT19 prompts gerados, esperava 3"
  fi

  if ls "$RODADA_DIR19"/prompt-codex.md >/dev/null 2>&1 || ls "$RODADA_DIR19"/prompt-gemini.md >/dev/null 2>&1; then
    falhou=$((falhou + 1))
    echo "  FALHA prompt de membro externo (codex/gemini) foi gerado sem a chave ligada"
  else
    ok=$((ok + 1))
    echo "  ok   nenhum prompt de membro externo (codex/gemini) foi gerado"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 20: externo-ligado-entra =="
TEMPDIR20="$RAIZ/test-externo-ligado"
mkdir -p "$TEMPDIR20/.rainforest/conselho"

# Config com conselho-codex ligado - no projeto
echo '{"conselho-codex": true}' > "$TEMPDIR20/.rainforest/config.json"

# Create membros.json - padrão
cat > "$TEMPDIR20/.rainforest/conselho/membros.json" << 'EOF'
{
  "membros": [
    {"nome": "cetico", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "cat '$FIXTURE_DIR/membro-ok.cjs' > {saida}", "ligado": true}
  ]
}
EOF

# Create test question file
echo "# Questão de teste" > "$TEMPDIR20/questao.md"

# Teste: com chave ligada, abrir deve contar 4 membros
testa "externo-ligado-entra: exit 0" "0" \
  bash -c "cd '$TEMPDIR20' && CLAUDE_PROJECT_DIR='$TEMPDIR20' node '$CONSELHO' abrir --questao questao.md"

# Verificar que a rodada foi criada e tem 4 prompts (3 personas + codex)
RODADA_DIR20=$(ls -1d "$TEMPDIR20/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR20" ]; then
  PROMPT_COUNT=$(ls "$RODADA_DIR20"/prompt-*.md 2>/dev/null | wc -l)
  if [ "$PROMPT_COUNT" = "4" ]; then
    ok=$((ok + 1))
    echo "  ok   com chave ligada: 4 prompts gerados (3 personas + codex)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $PROMPT_COUNT prompts, esperava 4"
  fi
  # Verificar que codex está nos prompts
  if ls "$RODADA_DIR20"/prompt-codex.md >/dev/null 2>&1; then
    ok=$((ok + 1))
    echo "  ok   prompt-codex.md foi criado"
  else
    falhou=$((falhou + 1))
    echo "  FALHA prompt-codex.md não foi criado"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 21: gemini-sem-credencial-falha =="
TEMPDIR21="$RAIZ/test-gemini-credencial"
mkdir -p "$TEMPDIR21"

# Criar um arquivo de prompt fake
echo "# Teste" > "$TEMPDIR21/prompt.md"

# Injetar fixture para não chamar o binário real (D7: fixture sempre)
# O guard if (!process.env.GEMINI_API_KEY) deve BARRAR a execução ANTES
# da fixture ser chamada — caso contrário, não há proteção testável.
CONSELHO_CMD_GEMINI="node \"$SRC_M/scripts/fixtures/conselho/membro-gemini-fake.cjs\" {prompt} {saida}"

# Tentar rodar adaptador-gemini SEM GEMINI_API_KEY com fixture injetada
# Deve sair com exit ≠ 0 (guard barra) e NÃO criar arquivo de saída
testa "gemini-sem-credencial-falha: exit != 0" "1" \
  bash -c "cd '$TEMPDIR21' && unset GEMINI_API_KEY; CONSELHO_CMD_GEMINI='$CONSELHO_CMD_GEMINI' node '$CONSELHO' adaptador-gemini prompt.md saida.json"

# Verificar que saida.json NÃO foi criado
if [ ! -f "$TEMPDIR21/saida.json" ]; then
  ok=$((ok + 1))
  echo "  ok   arquivo de saída NÃO foi criado (falha fechada)"
else
  falhou=$((falhou + 1))
  echo "  FALHA arquivo de saída foi criado em falha"
fi

echo ""
echo "== CASO 21b: gemini-com-credencial-sucede =="
# Caso simétrico: COM credencial, o adaptador chega a chamar a fixture
# e escreve saída com sucesso.
TEMPDIR21b="$RAIZ/test-gemini-com-credencial"
rm -f "$TEMPDIR21b/saida.json"  # Limpar de execução anterior se houver
mkdir -p "$TEMPDIR21b"

# Criar arquivo de prompt fake
echo "# Teste com credencial" > "$TEMPDIR21b/prompt.md"

# Mesma fixture, mesma variável de ambiente injetada
export CONSELHO_CMD_GEMINI="node \"$SRC_M/scripts/fixtures/conselho/membro-gemini-fake.cjs\" {prompt} {saida}"

# Rodar COM GEMINI_API_KEY definida (valor fake)
# Deve sair com exit 0 e CRIAR arquivo de saída
# Export a variável para que bash -c a veja
SAIDA_DEBUG=$(bash -c "cd '$TEMPDIR21b' && GEMINI_API_KEY='fake-key-for-testing' node '$CONSELHO' adaptador-gemini prompt.md saida.json" 2>&1)
EXIT_DEBUG=$?

if [ "$EXIT_DEBUG" = "0" ]; then
  ok=$((ok + 1))
  echo "  ok   gemini-com-credencial-sucede: exit = 0 (exit 0)"
else
  falhou=$((falhou + 1))
  echo "  FALHA gemini-com-credencial-sucede: exit = 0: esperava exit 0, veio $EXIT_DEBUG"
  echo "         $SAIDA_DEBUG"
fi

# Verificar que saida.json FOI criado
if [ -f "$TEMPDIR21b/saida.json" ]; then
  ok=$((ok + 1))
  echo "  ok   arquivo de saída foi criado (sucesso fechado)"
else
  falhou=$((falhou + 1))
  echo "  FALHA arquivo de saída não foi criado em sucesso"
fi

echo ""
echo "== CASO 22: agregacao-discorda-desempate =="
# ACHADO da tarefa 8 (auditoria + endurecimento pedido no item 2): o CASO 12
# (agregacao-conhecida) usa 3 membros; com 3 membros e N-1=2 avaliações por
# candidato, a média só pode valer 0, 0.5 ou 1 — e essas três médias mapeiam
# 1-para-1 com a contagem de primeiros-lugares (0<->2, 0.5<->1, 1<->0). Ou seja,
# NUNCA existe discórdia entre "ordenar por média" e "ordenar só por
# primeiros-lugares" com 3 membros: matar a comparação de média
# (`if (metA.media !== metB.media) {...}` -> `if (false) {...}`) cai direto no
# desempate por primeiros-lugares, que já concorda com a média — mutação
# sobrevive (medido na integração da T4/T8: bateria fica verde com a mutação).
#
# Este caso usa 4 membros (N-1=3 avaliações por candidato), onde média e
# primeiros-lugares PODEM discordar de verdade. Cálculo à mão:
#
#   Revisor arquiteto (avalia usuario-final=C, cetico=A, revisor-extra=D):
#     ranking = [C, A, D]  ->  C=pos0, A=pos1, D=pos2
#   Revisor usuario-final (avalia cetico=A, arquiteto=B, revisor-extra=D):
#     ranking = [A, B, D]  ->  A=pos0, B=pos1, D=pos2
#   Revisor cetico (avalia arquiteto=B, usuario-final=C, revisor-extra=D):
#     ranking = [D, B, C]  ->  D=pos0, B=pos1, C=pos2
#   Revisor revisor-extra (avalia cetico=A, arquiteto=B, usuario-final=C):
#     ranking = [A, B, C]  ->  A=pos0, B=pos1, C=pos2
#
#   membro-A (cetico):        avaliado por arquiteto=1, usuario-final=0, revisor-extra=0
#                              soma=1  média=1/3=0.333  primeirosPor=2
#   membro-B (arquiteto):     avaliado por cetico=1, usuario-final=1, revisor-extra=1
#                              soma=3  média=3/3=1.000  primeirosPor=0
#   membro-C (usuario-final): avaliado por arquiteto=0, cetico=2, revisor-extra=2
#                              soma=4  média=4/3=1.333  primeirosPor=1
#   membro-D (revisor-extra): avaliado por arquiteto=2, usuario-final=2, cetico=0
#                              soma=4  média=4/3=1.333  primeirosPor=1
#
#   Ranking CORRETO (média asc; empate C/D por primeirosPor igual (1) então
#   alfabético): [A, B, C, D] = [cetico, arquiteto, usuario-final, revisor-extra]
#
#   Ranking com a MUTAÇÃO (média sempre "empatada" -> só primeirosPor desc,
#   empate alfabético): primeirosPor A=2, C=1, D=1, B=0
#     -> [A, C, D, B] = [cetico, usuario-final, revisor-extra, arquiteto]
#
#   Os dois arrays DIVERGEM (posições 2..4 trocadas) — esta fixture mata a
#   mutação que "agregacao-conhecida" (CASO 12) deixa passar.
TEMPDIR22="$RAIZ/test-agregacao-discorda"
mkdir -p "$TEMPDIR22/.rainforest/conselho"

FIXTURE_OK_T22="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
cat > "$TEMPDIR22/.rainforest/conselho/membros.json" << EOF
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_OK_T22\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_OK_T22\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_OK_T22\" {prompt} {saida}", "ligado": true},
    {"nome": "revisor-extra", "cmd": "node \"$FIXTURE_OK_T22\" {prompt} {saida}", "ligado": true}
  ]
}
EOF

echo "# Questão para teste de desempate na agregação" > "$TEMPDIR22/questao-desempate.md"

bash -c "cd '$TEMPDIR22' && RFM_ESTADO_ROOT='$TEMPDIR22' node '$CONSELHO' abrir --questao questao-desempate.md" 2>/dev/null

RODADA_DIR22=$(ls -1d "$TEMPDIR22/.rainforest/conselho/202"* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR22" ]; then
  bash -c "cd '$TEMPDIR22' && RFM_ESTADO_ROOT='$TEMPDIR22' node '$CONSELHO' pareceres" 2>/dev/null

  cat > "$RODADA_DIR22/mapa-anonimato.json" << 'EOF'
{
  "cetico": "membro-A",
  "arquiteto": "membro-B",
  "usuario-final": "membro-C",
  "revisor-extra": "membro-D"
}
EOF

  mkdir -p "$RODADA_DIR22/fase2"

  cat > "$RODADA_DIR22/fase2/revisao-arquiteto.json" << 'EOF'
{"ranking": ["membro-C", "membro-A", "membro-D"], "criticas": {"membro-C": "Crítica C", "membro-A": "Crítica A", "membro-D": "Crítica D"}}
EOF

  cat > "$RODADA_DIR22/fase2/revisao-usuario-final.json" << 'EOF'
{"ranking": ["membro-A", "membro-B", "membro-D"], "criticas": {"membro-A": "Crítica A", "membro-B": "Crítica B", "membro-D": "Crítica D"}}
EOF

  cat > "$RODADA_DIR22/fase2/revisao-cetico.json" << 'EOF'
{"ranking": ["membro-D", "membro-B", "membro-C"], "criticas": {"membro-D": "Crítica D", "membro-B": "Crítica B", "membro-C": "Crítica C"}}
EOF

  cat > "$RODADA_DIR22/fase2/revisao-revisor-extra.json" << 'EOF'
{"ranking": ["membro-A", "membro-B", "membro-C"], "criticas": {"membro-A": "Crítica A", "membro-B": "Crítica B", "membro-C": "Crítica C"}}
EOF

  testa "agregacao-discorda-desempate: conferir fase revisao" "0" \
    bash -c "cd '$TEMPDIR22' && RFM_ESTADO_ROOT='$TEMPDIR22' node '$CONSELHO' conferir --fase revisao"

  testa "agregacao-discorda-desempate: sintetizar exit 0" "0" \
    bash -c "cd '$TEMPDIR22' && RFM_ESTADO_ROOT='$TEMPDIR22' node '$CONSELHO' sintetizar"

  if [ -f "$RODADA_DIR22/sintese.json" ]; then
    RANKING_REAL=$(node -e "const fs=require('fs'); const s=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); console.log(JSON.stringify(s.ranking_agregado));" "$RODADA_DIR22/sintese.json" 2>&1)
    RANKING_ESPERADO='["cetico","arquiteto","usuario-final","revisor-extra"]'

    if [ "$RANKING_REAL" = "$RANKING_ESPERADO" ]; then
      ok=$((ok + 1))
      echo "  ok   ranking_agregado bate com o cálculo à mão: $RANKING_REAL"
    else
      falhou=$((falhou + 1))
      echo "  FALHA ranking_agregado='$RANKING_REAL', esperava '$RANKING_ESPERADO'"
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA sintese.json não foi criado"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA não conseguiu encontrar diretório de rodada"
fi

echo ""
echo "== CASO 23: lint-require-sem-npm =="
# D14: nenhuma dependência npm entra no repo. Verifica que scripts/conselho.cjs
# e as fixtures scripts/fixtures/conselho/*.cjs só fazem require() de módulo
# nativo do Node (fs, path, child_process, os, ...) ou de caminho relativo
# (./ ou ../). Qualquer outra coisa (um pacote de node_modules) é achado.
NATIVOS_REGEX="^(assert|buffer|child_process|cluster|console|constants|crypto|dgram|dns|domain|events|fs|http|http2|https|inspector|module|net|os|path|perf_hooks|process|punycode|querystring|readline|repl|stream|string_decoder|sys|timers|tls|trace_events|tty|url|util|v8|vm|worker_threads|zlib|async_hooks)$"

ACHADOS_LINT=""
for ARQ_LINT in "$SRC/scripts/conselho.cjs" "$SRC"/scripts/fixtures/conselho/*.cjs; do
  while IFS= read -r MODULO; do
    [ -z "$MODULO" ] && continue
    case "$MODULO" in
      node:*|./*|../*) continue ;;
    esac
    if echo "$MODULO" | grep -qE "$NATIVOS_REGEX"; then
      continue
    fi
    ACHADOS_LINT="${ACHADOS_LINT}$(basename "$ARQ_LINT"): require('$MODULO')"$'\n'
  done < <(grep -oE "require\(['\"][^'\"]+['\"]\)" "$ARQ_LINT" | sed -E "s/require\(['\"]([^'\"]+)['\"]\)/\1/")
done

if [ -z "$ACHADOS_LINT" ]; then
  ok=$((ok + 1))
  echo "  ok   lint-require-sem-npm: nenhuma dependência externa em conselho.cjs/fixtures"
else
  falhou=$((falhou + 1))
  echo "  FALHA lint-require-sem-npm: dependência(s) externa(s) encontrada(s):"
  echo "$ACHADOS_LINT" | sed 's/^/         /'
fi

echo ""
echo "== CASO 24: parecer-cercado-passa (parse tolerante a cerca de codigo) =="
TEMPDIR24="$RAIZ/test-parecer-cercado"
mkdir -p "$TEMPDIR24/.rainforest/conselho"
FIXTURE_CERCADO="$SRC_M/scripts/fixtures/conselho/membro-json-cercado.cjs"
cat > "$TEMPDIR24/.rainforest/conselho/membros.json" << EOF24
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_CERCADO\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_CERCADO\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_CERCADO\" {prompt} {saida}", "ligado": true}
  ]
}
EOF24
echo "# Questao cercada" > "$TEMPDIR24/questao-cercada.md"
testa "cercado: abrir" "0"   bash -c "cd '$TEMPDIR24' && RFM_ESTADO_ROOT='$TEMPDIR24' node '$CONSELHO' abrir --questao questao-cercada.md"
testa "cercado: pareceres com JSON em cerca fecham" "0"   bash -c "cd '$TEMPDIR24' && RFM_ESTADO_ROOT='$TEMPDIR24' node '$CONSELHO' pareceres"
testa "cercado: conferir fase pareceres" "0"   bash -c "cd '$TEMPDIR24' && RFM_ESTADO_ROOT='$TEMPDIR24' node '$CONSELHO' conferir --fase pareceres"
echo ""

echo "== CASO 25: caminho-com-espaco =="
TEMPDIR25="$RAIZ/pasta com espaco"
mkdir -p "$TEMPDIR25/.rainforest/conselho"
FIXTURE_ESPACO="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
cat > "$TEMPDIR25/.rainforest/conselho/membros.json" << EOF25
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_ESPACO\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_ESPACO\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_ESPACO\" {prompt} {saida}", "ligado": true}
  ]
}
EOF25
echo "# Questão com espaço no path" > "$TEMPDIR25/questao-espaco.md"
testa "caminho-com-espaco: abrir" "0" bash -c "cd '$TEMPDIR25' && RFM_ESTADO_ROOT='$TEMPDIR25' node '$CONSELHO' abrir --questao questao-espaco.md"
testa "caminho-com-espaco: pareceres" "0" bash -c "cd '$TEMPDIR25' && RFM_ESTADO_ROOT='$TEMPDIR25' node '$CONSELHO' pareceres"
RODADA_DIR25=$(ls -1d "$TEMPDIR25/.rainforest/conselho"/202* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR25" ]; then
  PARECER_COUNT25=$(ls -1 "$RODADA_DIR25/parecer-"*.json 2>/dev/null | wc -l)
  if [ "$PARECER_COUNT25" -eq 3 ]; then
    ok=$((ok + 1))
    echo "  ok   3 pareceres criados com sucesso"
  else
    falhou=$((falhou + 1))
    echo "  FALHA pareceres: $PARECER_COUNT25, esperava 3"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA rodada não encontrada"
fi

echo ""
echo "== CASO 26: retry-seletivo-so-reexecuta-um =="
TEMPDIR26="$RAIZ/test-retry-seletivo"
mkdir -p "$TEMPDIR26/.rainforest/conselho"
FIXTURE_RET="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
cat > "$TEMPDIR26/.rainforest/conselho/membros.json" << EOF26
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FIXTURE_RET\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FIXTURE_RET\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FIXTURE_RET\" {prompt} {saida}", "ligado": true}
  ]
}
EOF26
echo "# Questão para retry" > "$TEMPDIR26/questao-retry.md"
testa "retry-seletivo: abrir" "0" bash -c "cd '$TEMPDIR26' && RFM_ESTADO_ROOT='$TEMPDIR26' node '$CONSELHO' abrir --questao questao-retry.md"
testa "retry-seletivo: pareceres completo" "0" bash -c "cd '$TEMPDIR26' && RFM_ESTADO_ROOT='$TEMPDIR26' node '$CONSELHO' pareceres"
testa "retry-seletivo: conferir fase" "0" bash -c "cd '$TEMPDIR26' && RFM_ESTADO_ROOT='$TEMPDIR26' node '$CONSELHO' conferir --fase pareceres"
RODADA_DIR26=$(ls -1d "$TEMPDIR26/.rainforest/conselho"/202* 2>/dev/null | head -1)
if [ -n "$RODADA_DIR26" ]; then
  rm -f "$RODADA_DIR26/parecer-arquiteto.json"
  # Sentinela: se cetico/usuario-final forem REexecutados, a fixture sobrescreve e o marcador some
  node -e "const fs=require('fs');for(const n of ['cetico','usuario-final']){const p='$RODADA_DIR26/parecer-'+n+'.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));j.marcador_intacto=true;fs.writeFileSync(p,JSON.stringify(j,null,2));}"
  testa "retry-seletivo: pareceres --membro arquiteto" "0" bash -c "cd '$TEMPDIR26' && RFM_ESTADO_ROOT='$TEMPDIR26' node '$CONSELHO' pareceres --membro arquiteto"
  if [ -f "$RODADA_DIR26/parecer-arquiteto.json" ]; then
    ok=$((ok + 1))
    echo "  ok   parecer-arquiteto.json recriado"
  else
    falhou=$((falhou + 1))
    echo "  FALHA parecer-arquiteto.json não foi recriado"
  fi
  if node -e "const f=require('$RODADA_DIR26/parecer-cetico.json'),g=require('$RODADA_DIR26/parecer-usuario-final.json');process.exit(f.marcador_intacto===true&&g.marcador_intacto===true?0:1)"; then
    ok=$((ok + 1))
    echo "  ok   cetico e usuario-final NAO foram reexecutados (sentinela intacta)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA retry --membro reexecutou membro que nao devia (sentinela sumiu)"
  fi
  INVALID_OUT=$(bash -c "cd '$TEMPDIR26' && RFM_ESTADO_ROOT='$TEMPDIR26' node '$CONSELHO' pareceres --membro invalido" 2>&1 || true)
  if echo "$INVALID_OUT" | grep -q "Erro.*desconhecido"; then
    ok=$((ok + 1))
    echo "  ok   --membro inválido reprova com erro"
  else
    falhou=$((falhou + 1))
    echo "  FALHA --membro inválido não reprovou corretamente"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA rodada não encontrada para retry"
fi

echo ""
echo "== CASO 27: fases-fecham-no-estado (portao que passa marca a fase) =="
TEMPDIR27="$RAIZ/test-fases-fecham"
mkdir -p "$TEMPDIR27/.rainforest/conselho"
F27="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
R27="$SRC_M/scripts/fixtures/conselho/membro-revisor-ok.cjs"
cat > "$TEMPDIR27/.rainforest/conselho/membros.json" << EOF27
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$F27\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$F27\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$F27\" {prompt} {saida}", "ligado": true}
  ]
}
EOF27
echo "# Fases fecham" > "$TEMPDIR27/q27.md"
RODA27() { bash -c "cd '$TEMPDIR27' && RFM_ESTADO_ROOT='$TEMPDIR27' node '$CONSELHO' $1"; }
RODA27 "abrir --questao q27.md" > /dev/null 2>&1
RODA27 "pareceres" > /dev/null 2>&1
RODA27 "conferir --fase pareceres" > /dev/null 2>&1
EST27=$(ls -1d "$TEMPDIR27/.rainforest/conselho/202"* | head -1)/estado.json
if grep -q '"pareceres": {\s*"status": "ok"' "$EST27" || node -e "const j=require('$EST27');process.exit(j.fases.pareceres.status==='ok'?0:1)"; then
  ok=$((ok + 1)); echo "  ok   portao de pareceres marcou a fase como ok no estado"
else
  falhou=$((falhou + 1)); echo "  FALHA fase pareceres continua '$(node -e "console.log(require('$EST27').fases.pareceres.status)")' apos portao exit 0"
fi
# troca os cmds para o revisor fixture e fecha as outras duas fases
node -e "const fs=require('fs');const p='$TEMPDIR27/.rainforest/conselho/membros.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));j.membros.forEach(m=>m.cmd='node \"$R27\" {prompt} {saida}');fs.writeFileSync(p,JSON.stringify(j,null,2));"
RODA27 "revisar" > /dev/null 2>&1
RODA27 "conferir --fase revisao" > /dev/null 2>&1
RODA27 "sintetizar" > /dev/null 2>&1
RODA27 "conferir --fase sintese" > /dev/null 2>&1
if node -e "const j=require('$EST27');const f=j.fases;process.exit(f.pareceres.status==='ok'&&f.revisao.status==='ok'&&f.sintese.status==='ok'?0:1)"; then
  ok=$((ok + 1)); echo "  ok   as 3 fases fechadas no estado apos os 3 portoes"
else
  falhou=$((falhou + 1)); echo "  FALHA estado das fases: $(node -e "const j=require('$EST27');console.log(JSON.stringify(j.fases))")"
fi
echo ""

echo "== CASO 28: revisar-membro-retry (mapa reusado, pacote completo) =="
TEMPDIR28="$RAIZ/test-revisar-membro"
mkdir -p "$TEMPDIR28/.rainforest/conselho"
FO28="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
FR28="$SRC_M/scripts/fixtures/conselho/membro-revisor-ok.cjs"
cat > "$TEMPDIR28/.rainforest/conselho/membros.json" << EOF28
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FO28\" {prompt} {saida}", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FO28\" {prompt} {saida}", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FO28\" {prompt} {saida}", "ligado": true}
  ]
}
EOF28
echo "# Retry fase 2" > "$TEMPDIR28/q28.md"
RODA28() { bash -c "cd '$TEMPDIR28' && RFM_ESTADO_ROOT='$TEMPDIR28' node '$CONSELHO' $1"; }
RODA28 "abrir --questao q28.md" > /dev/null 2>&1
RODA28 "pareceres" > /dev/null 2>&1
node -e "const fs=require('fs');const p='$TEMPDIR28/.rainforest/conselho/membros.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));j.membros.forEach(m=>m.cmd='node \"$FR28\" {prompt} {saida}');fs.writeFileSync(p,JSON.stringify(j,null,2));"
RODA28 "revisar" > /dev/null 2>&1
R28=$(ls -1d "$TEMPDIR28/.rainforest/conselho/202"* | head -1)
MAPA_ANTES=$(cat "$R28/mapa-anonimato.json")
rm -f "$R28/fase2/revisao-arquiteto.json"
testa "revisar --membro arquiteto (retry)" "0" bash -c "cd '$TEMPDIR28' && RFM_ESTADO_ROOT='$TEMPDIR28' node '$CONSELHO' revisar --membro arquiteto"
if [ "$(cat "$R28/mapa-anonimato.json")" = "$MAPA_ANTES" ]; then
  ok=$((ok + 1)); echo "  ok   mapa de anonimato intacto no retry (3 entradas)"
else
  falhou=$((falhou + 1)); echo "  FALHA retry reescreveu o mapa: $(cat "$R28/mapa-anonimato.json")"
fi
if node -e "const j=require('$R28/fase2/pacote-prompt-arquiteto.json');process.exit(j.pareceres.length===2?0:1)"; then
  ok=$((ok + 1)); echo "  ok   pacote do retry tem os 2 pareceres alheios"
else
  falhou=$((falhou + 1)); echo "  FALHA pacote do retry: $(node -e "console.log(require('$R28/fase2/pacote-prompt-arquiteto.json').pareceres.length)") pareceres"
fi
testa "portao da revisao fecha apos retry" "0" bash -c "cd '$TEMPDIR28' && RFM_ESTADO_ROOT='$TEMPDIR28' node '$CONSELHO' conferir --fase revisao"
echo ""

echo "== CASO 29: aspas-ja-presentes no cmd do dev =="
TEMPDIR29="$RAIZ/test-aspas-presentes"
mkdir -p "$TEMPDIR29/.rainforest/conselho"
FO29="$SRC_M/scripts/fixtures/conselho/membro-ok.cjs"
cat > "$TEMPDIR29/.rainforest/conselho/membros.json" << EOF29
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FO29\" \"{prompt}\" \"{saida}\"", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FO29\" \"{prompt}\" \"{saida}\"", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FO29\" \"{prompt}\" \"{saida}\"", "ligado": true}
  ]
}
EOF29
echo "# Aspas presentes" > "$TEMPDIR29/q29.md"
testa "aspas-ja-presentes: abrir" "0" bash -c "cd '$TEMPDIR29' && RFM_ESTADO_ROOT='$TEMPDIR29' node '$CONSELHO' abrir --questao q29.md"
testa "aspas-ja-presentes: pareceres sem aspas duplicadas" "0" bash -c "cd '$TEMPDIR29' && RFM_ESTADO_ROOT='$TEMPDIR29' node '$CONSELHO' pareceres"
R29=$(ls -1d "$TEMPDIR29/.rainforest/conselho/202"* | head -1)
N29=$(ls "$R29"/parecer-*.json 2>/dev/null | wc -l)
if [ "$N29" = "3" ]; then
  ok=$((ok + 1)); echo "  ok   3 pareceres com cmd ja-aspado"
else
  falhou=$((falhou + 1)); echo "  FALHA $N29 pareceres com cmd ja-aspado"
fi
echo ""

echo "== CASO 30: membro-que-trava-e-cortado (timeout rápido) =="
TEMPDIR30="$RAIZ/test-timeout"
mkdir -p "$TEMPDIR30/.rainforest/conselho"
FO30="$SRC_M/scripts/fixtures/conselho/membro-que-trava-e-cortado.cjs"
cat > "$TEMPDIR30/.rainforest/conselho/membros.json" << EOF30
{
  "membros": [
    {"nome": "cetico", "cmd": "node \"$FO30\" \"{prompt}\" \"{saida}\"", "ligado": true},
    {"nome": "arquiteto", "cmd": "node \"$FO30\" \"{prompt}\" \"{saida}\"", "ligado": true},
    {"nome": "usuario-final", "cmd": "node \"$FO30\" \"{prompt}\" \"{saida}\"", "ligado": true}
  ]
}
EOF30
echo "# Questão com timeout" > "$TEMPDIR30/q30.md"
testa "timeout-rápido: abrir" "0" bash -c "cd '$TEMPDIR30' && RFM_ESTADO_ROOT='$TEMPDIR30' node '$CONSELHO' abrir --questao q30.md"
# Executa pareceres com timeout curto (100ms) — deve falhar
testa "timeout-rápido: pareceres sai com exit 1 (cortado por timeout)" "1" bash -c "cd '$TEMPDIR30' && CONSELHO_TIMEOUT_MS=100 RFM_ESTADO_ROOT='$TEMPDIR30' node '$CONSELHO' pareceres"
echo ""

echo "== Resultado =="
echo "total=$((ok + falhou)) vermelhas:[$falhou]"
if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
