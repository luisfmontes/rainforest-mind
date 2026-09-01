#!/bin/bash
# Bateria para segunda-opiniao.cjs — segunda opinião de modelo externo
# Uso: bash scripts/testa-segunda-opiniao.sh
#
# Testa segunda-opiniao contra fixtures (nunca contra CLI real — D7).

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_M="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"


# Usar diretório temporário (fora do worktree para limpeza correta)
RAIZ_BASE="/tmp/test-segunda-opiniao-$$"
mkdir -p "$RAIZ_BASE"
RAIZ="$RAIZ_BASE"
trap 'sleep 1; rm -rf "$RAIZ_BASE" 2>/dev/null' EXIT

echo "(caixa de areia: $RAIZ)"
echo ""

ok=0
falhou=0
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
git config user.email "test@<email>"
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
git config user.email "test@<email>"
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
git config user.email "test@<email>"
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
git config user.email "test@<email>"
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
git config user.email "test@<email>"
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
echo "== CASO 10: externo-indisponivel-exit =="

TEMP_REPO_INDISPONIVEL="$RAIZ/test-indisponivel-exit-repo"
mkdir -p "$TEMP_REPO_INDISPONIVEL"
cd "$TEMP_REPO_INDISPONIVEL"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_INDISPONIVEL=$(git rev-parse HEAD)

echo "modified" > file.txt
git add file.txt
git commit --quiet -m "head"
HEAD_SHA_INDISPONIVEL=$(git rev-parse HEAD)

CRITERIO_FILE_INDISPONIVEL="$TEMP_REPO_INDISPONIVEL/criterio.md"
cat > "$CRITERIO_FILE_INDISPONIVEL" << 'EOF'
# Critério: modificação válida
Validar se a mudança é apropriada.
EOF

FIXTURE_EXIT="$SRC_M/scripts/fixtures/segunda-opiniao/externo-indisponivel-exit.cjs"
OUTPUT_INDISPONIVEL=$(cd "$TEMP_REPO_INDISPONIVEL" && node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA_INDISPONIVEL" --head "$HEAD_SHA_INDISPONIVEL" --criterio "$CRITERIO_FILE_INDISPONIVEL" --cli-cmd "node $FIXTURE_EXIT" 2>&1); EXIT_INDISPONIVEL=$?
if [ "$EXIT_INDISPONIVEL" != "0" ]; then
  if echo "$OUTPUT_INDISPONIVEL" | grep -q "indisponível (exit ≠ 0)"; then
    ok=$((ok + 1))
    echo "  ok   externo-indisponivel-exit sai ≠ 0 com mensagem específica"
  else
    falhou=$((falhou + 1))
    echo "  FALHA externo-indisponivel-exit: não tem mensagem '(exit ≠ 0)'"
    echo "$OUTPUT_INDISPONIVEL" | head -5
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA externo-indisponivel-exit: deveria sair ≠ 0, saiu 0"
fi

echo ""
echo "== CASO 11: externo-indisponivel-vazio =="

TEMP_REPO_VAZIO="$RAIZ/test-indisponivel-vazio-repo"
mkdir -p "$TEMP_REPO_VAZIO"
cd "$TEMP_REPO_VAZIO"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_VAZIO=$(git rev-parse HEAD)

echo "modified" > file.txt
git add file.txt
git commit --quiet -m "head"
HEAD_SHA_VAZIO=$(git rev-parse HEAD)

CRITERIO_FILE_VAZIO="$TEMP_REPO_VAZIO/criterio.md"
cat > "$CRITERIO_FILE_VAZIO" << 'EOF'
# Critério: modificação válida
Validar se a mudança é apropriada.
EOF

FIXTURE_VAZIO="$SRC_M/scripts/fixtures/segunda-opiniao/externo-indisponivel-vazio.cjs"
OUTPUT_VAZIO=$(cd "$TEMP_REPO_VAZIO" && node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA_VAZIO" --head "$HEAD_SHA_VAZIO" --criterio "$CRITERIO_FILE_VAZIO" --cli-cmd "node $FIXTURE_VAZIO" 2>&1); EXIT_VAZIO=$?
if [ "$EXIT_VAZIO" != "0" ]; then
  if echo "$OUTPUT_VAZIO" | grep -q "indisponível (stdout vazio)"; then
    ok=$((ok + 1))
    echo "  ok   externo-indisponivel-vazio sai ≠ 0 com mensagem específica"
  else
    falhou=$((falhou + 1))
    echo "  FALHA externo-indisponivel-vazio: não tem mensagem '(stdout vazio)'"
    echo "$OUTPUT_VAZIO" | head -5
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA externo-indisponivel-vazio: deveria sair ≠ 0, saiu 0"
fi

echo ""
echo "== CASO 12: externo-indisponivel-timeout =="

TEMP_REPO_TIMEOUT2="$RAIZ/test-indisponivel-timeout-repo"
mkdir -p "$TEMP_REPO_TIMEOUT2"
cd "$TEMP_REPO_TIMEOUT2"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_TIMEOUT2=$(git rev-parse HEAD)

echo "modified" > file.txt
git add file.txt
git commit --quiet -m "head"
HEAD_SHA_TIMEOUT2=$(git rev-parse HEAD)

CRITERIO_FILE_TIMEOUT2="$TEMP_REPO_TIMEOUT2/criterio.md"
cat > "$CRITERIO_FILE_TIMEOUT2" << 'EOF'
# Critério: resposta rápida
Modelo deve responder dentro do teto.
EOF

FIXTURE_TIMEOUT_INDISPONIVEL="$SRC_M/scripts/fixtures/segunda-opiniao/externo-indisponivel-timeout.cjs"
OUTPUT_TIMEOUT_INDISPONIVEL=$(cd "$TEMP_REPO_TIMEOUT2" && TIMEOUT_SEGUNDA_OPINIAO_MS=100 node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA_TIMEOUT2" --head "$HEAD_SHA_TIMEOUT2" --criterio "$CRITERIO_FILE_TIMEOUT2" --cli-cmd "node $FIXTURE_TIMEOUT_INDISPONIVEL" 2>&1); EXIT_TIMEOUT_INDISPONIVEL=$?
if [ "$EXIT_TIMEOUT_INDISPONIVEL" != "0" ]; then
  if echo "$OUTPUT_TIMEOUT_INDISPONIVEL" | grep -q "indisponível (timeout"; then
    ok=$((ok + 1))
    echo "  ok   externo-indisponivel-timeout sai ≠ 0 com mensagem específica"
  else
    falhou=$((falhou + 1))
    echo "  FALHA externo-indisponivel-timeout: não tem mensagem '(timeout'"
    echo "$OUTPUT_TIMEOUT_INDISPONIVEL" | head -5
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA externo-indisponivel-timeout: deveria sair ≠ 0, saiu 0"
fi

echo ""
echo "== CASO 13: divergencia-registrada-com-motivo =="

TEMP_REPO_REG="$RAIZ/test-divergencia-reg-repo"
mkdir -p "$TEMP_REPO_REG"
cd "$TEMP_REPO_REG"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_REG=$(git rev-parse HEAD)

# Criar .rainforest para marcar raiz de dados
mkdir -p "$TEMP_REPO_REG/.rainforest"
touch "$TEMP_REPO_REG/.rainforest/FOCO.md"

REGISTRO_LOGFILE="$TEMP_REPO_REG/.rainforest/.logs/divergencias-segunda-opiniao.jsonl"
# Limpar log se existir
rm -f "$REGISTRO_LOGFILE"

# Registrar divergência
node "$SRC/scripts/segunda-opiniao.cjs" registrar-divergencia \
  --veredito discordo \
  --motivo "Critério não foi atendido plenamente" \
  --base "$BASE_SHA_REG" > /dev/null 2>&1; EXIT_REG=$?

if [ "$EXIT_REG" = "0" ]; then
  # Verificar se arquivo foi gravado
  if [ -f "$REGISTRO_LOGFILE" ]; then
    # Ler o registro e validar conteúdo
    if grep -q "\"veredito\":\"discordo\"" "$REGISTRO_LOGFILE" && \
       grep -q "\"motivo\":\"Critério não foi atendido plenamente\"" "$REGISTRO_LOGFILE" && \
       grep -q "\"base\":\"$BASE_SHA_REG\"" "$REGISTRO_LOGFILE"; then
      ok=$((ok + 1))
      echo "  ok   divergencia-registrada-com-motivo: arquivo contém veredito, motivo e base"
    else
      falhou=$((falhou + 1))
      echo "  FALHA divergencia-registrada-com-motivo: arquivo não tem conteúdo esperado"
      cat "$REGISTRO_LOGFILE" | head -5
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA divergencia-registrada-com-motivo: arquivo não foi criado em $REGISTRO_LOGFILE"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA divergencia-registrada-com-motivo: saiu $EXIT_REG em vez de 0"
fi

echo ""

echo ""
echo "== CASO 14: divergencia-com-motivo-so-whitespace-recusa =="

TEMP_REPO_WHITESPACE="$RAIZ/test-divergencia-whitespace-repo"
mkdir -p "$TEMP_REPO_WHITESPACE"
cd "$TEMP_REPO_WHITESPACE"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_WHITESPACE=$(git rev-parse HEAD)

# Criar .rainforest para marcar raiz de dados
mkdir -p "$TEMP_REPO_WHITESPACE/.rainforest"
touch "$TEMP_REPO_WHITESPACE/.rainforest/FOCO.md"

REGISTRO_LOGFILE_WHITESPACE="$TEMP_REPO_WHITESPACE/.rainforest/.logs/divergencias-segunda-opiniao.jsonl"
rm -f "$REGISTRO_LOGFILE_WHITESPACE"

OUTPUT_WHITESPACE=$(cd "$TEMP_REPO_WHITESPACE" && node "$SRC/scripts/segunda-opiniao.cjs" registrar-divergencia \
  --veredito discordo \
  --motivo "   " \
  --base "$BASE_SHA_WHITESPACE" 2>&1); EXIT_WHITESPACE=$?

if [ "$EXIT_WHITESPACE" != "0" ]; then
  if [ ! -f "$REGISTRO_LOGFILE_WHITESPACE" ]; then
    ok=$((ok + 1))
    echo "  ok   divergencia-com-motivo-so-whitespace-recusa: exit ≠ 0 e nada gravado"
  else
    falhou=$((falhou + 1))
    echo "  FALHA divergencia-com-motivo-so-whitespace-recusa: arquivo não deveria ter sido criado"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA divergencia-com-motivo-so-whitespace-recusa: deveria sair ≠ 0, saiu 0"
fi

echo ""
echo "== CASO 15: prompt-carrega-o-diff-de-tres-pontos =="

TEMP_REPO_PROMPT_DIFF="$RAIZ/test-prompt-diff-repo"
mkdir -p "$TEMP_REPO_PROMPT_DIFF"
cd "$TEMP_REPO_PROMPT_DIFF"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

# Criar um cenário com branches divergentes (para garantir que 3 pontos ≠ 2 pontos)
cat > file1.txt << 'EOF'
line 1
line 2
line 3
EOF
git add file1.txt
git commit --quiet -m "common base"
COMMON_SHA=$(git rev-parse HEAD)

# Criar branch 1 (base para o teste)
cat > file1.txt << 'EOF'
line 1 modified on branch1
line 2
line 3
EOF
git add file1.txt
git commit --quiet -m "branch1"
BASE_SHA_PROMPT=$(git rev-parse HEAD)

# Criar branch 2 a partir do COMMON
git checkout "$COMMON_SHA" --quiet
git checkout -b branch2 --quiet
cat > file1.txt << 'EOF'
line 1
line 2 modified on branch2
line 3
EOF
git add file1.txt
git commit --quiet -m "branch2 v1"

cat > file1.txt << 'EOF'
line 1
line 2 modified on branch2
line 3 modified on branch2
EOF
git add file1.txt
git commit --quiet -m "branch2 v2"
HEAD_SHA_PROMPT=$(git rev-parse HEAD)

CRITERIO_FILE_PROMPT="$TEMP_REPO_PROMPT_DIFF/criterio.md"
cat > "$CRITERIO_FILE_PROMPT" << 'EOF'
# Critério: validar diff de três pontos

O diff deve usar merge-base (três pontos) e incluir todas as mudanças de base até head.
EOF

# Usar fixture que valida tamanho do prompt
FIXTURE_VALIDAR_DIFF="$SRC_M/scripts/fixtures/segunda-opiniao/validar-diff-tamanho.cjs"
PROMPT_OUTPUT=$(cd "$TEMP_REPO_PROMPT_DIFF" && node "$SRC/scripts/segunda-opiniao.cjs" --base "$BASE_SHA_PROMPT" --head "$HEAD_SHA_PROMPT" --criterio "$CRITERIO_FILE_PROMPT" --cli-cmd "node $FIXTURE_VALIDAR_DIFF" 2>&1)
EXIT_PROMPT=$?

# Contar linhas do diff esperado (três pontos)
DIFF_TRES_PONTOS=$(cd "$TEMP_REPO_PROMPT_DIFF" && git diff "$BASE_SHA_PROMPT"..."$HEAD_SHA_PROMPT" | wc -l)
# Fixture imprime: "Total de linhas no diff do prompt: <N>"
LINHAS_NO_PROMPT=$(echo "$PROMPT_OUTPUT" | grep "Total de linhas no diff" | sed 's/.*: //g')

if [ "$EXIT_PROMPT" = "0" ]; then
  if [ "$LINHAS_NO_PROMPT" -eq "$DIFF_TRES_PONTOS" ]; then
    ok=$((ok + 1))
    echo "  ok   prompt-carrega-o-diff-de-tres-pontos: prompt tem $LINHAS_NO_PROMPT linhas (git diff <base>...<head> | wc -l = $DIFF_TRES_PONTOS)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA prompt-carrega-o-diff-de-tres-pontos: prompt tem $LINHAS_NO_PROMPT linhas, esperava $DIFF_TRES_PONTOS"
    echo "$PROMPT_OUTPUT" | head -5
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA prompt-carrega-o-diff-de-tres-pontos: exit deveria ser 0, foi $EXIT_PROMPT"
  echo "$PROMPT_OUTPUT" | head -5
fi

echo ""
echo "== CASO 16: divergencia-log-em-raiz-isolada =="

# Teste com RFM_ROOT apontando para raiz isolada (dentro do tmp)
# Valida que o log vai para a raiz explícita, não para a global do usuário
FORA_REPO="/tmp/segunda-opiniao-isolada-$$"
rm -rf "$FORA_REPO"
mkdir -p "$FORA_REPO"
trap 'rm -rf "$FORA_REPO" 2>/dev/null' EXIT

# Criar uma raiz de dados isolada e um repositório dentro do /tmp
RAIZ_ISOLADA="$FORA_REPO/dados"
mkdir -p "$RAIZ_ISOLADA"
touch "$RAIZ_ISOLADA/FOCO.md"

REPO_ISOLADA="$FORA_REPO/repo"
mkdir -p "$REPO_ISOLADA"
cd "$REPO_ISOLADA"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_ISOLADA=$(git rev-parse HEAD)

# Registrar com RFM_ROOT apontando para raiz isolada
OUTPUT_ISOLADA=$(cd "$REPO_ISOLADA" && RFM_ROOT="$RAIZ_ISOLADA" node "$SRC/scripts/segunda-opiniao.cjs" registrar-divergencia \
  --veredito discordo \
  --motivo "Rodando com RFM_ROOT isolado" \
  --base "$BASE_SHA_ISOLADA" 2>&1); EXIT_ISOLADA=$?

if [ "$EXIT_ISOLADA" = "0" ]; then
  # Arquivo deve estar em RAIZ_ISOLADA/.logs, NÃO em ~/.rainforest
  LOGFILE_ISOLADA="$RAIZ_ISOLADA/.logs/divergencias-segunda-opiniao.jsonl"
  if [ -f "$LOGFILE_ISOLADA" ] && grep -q "\"motivo\":\"Rodando com RFM_ROOT isolado\"" "$LOGFILE_ISOLADA"; then
    ok=$((ok + 1))
    echo "  ok   divergencia-log-em-raiz-isolada: arquivo em RFM_ROOT/.logs/, não em ~/.rainforest"
  else
    falhou=$((falhou + 1))
    echo "  FALHA divergencia-log-em-raiz-isolada: arquivo não criado em $LOGFILE_ISOLADA"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA divergencia-log-em-raiz-isolada: deveria sair 0, saiu $EXIT_ISOLADA"
fi

echo ""
echo "== CASO 17: divergencia-log-em-subpasta-de-repo =="

# Teste em subpasta do repositório — o log deve ir para raiz de dados resolvida, não para cwd
# Usa RFM_ROOT para forçar raiz isolada dentro do RAIZ
TEMP_REPO_SUBPASTA="$RAIZ/test-log-subpasta-repo"
mkdir -p "$TEMP_REPO_SUBPASTA"
cd "$TEMP_REPO_SUBPASTA"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_SUBPASTA=$(git rev-parse HEAD)

# Criar uma raiz de dados isolada para este repositório
RAIZ_DADOS_SUBPASTA="$RAIZ/dados-subpasta"
mkdir -p "$RAIZ_DADOS_SUBPASTA"
touch "$RAIZ_DADOS_SUBPASTA/FOCO.md"

# Criar subpasta dentro do repo e rodar de lá
mkdir -p "$TEMP_REPO_SUBPASTA/subdir"
REGISTRO_LOGFILE_RAIZ="$RAIZ_DADOS_SUBPASTA/.logs/divergencias-segunda-opiniao.jsonl"
REGISTRO_LOGFILE_SUBDIR="$TEMP_REPO_SUBPASTA/subdir/.logs/divergencias-segunda-opiniao.jsonl"

rm -f "$REGISTRO_LOGFILE_RAIZ" "$REGISTRO_LOGFILE_SUBDIR"

# Registrar divergência rodando de dentro da subpasta COM RFM_ROOT isolado
(cd "$TEMP_REPO_SUBPASTA/subdir" && RFM_ROOT="$RAIZ_DADOS_SUBPASTA" node "$SRC/scripts/segunda-opiniao.cjs" registrar-divergencia \
  --veredito discordo \
  --motivo "Log deve ir para raiz de dados, não subdir" \
  --base "$BASE_SHA_SUBPASTA" > /dev/null 2>&1); EXIT_SUBPASTA=$?

# Deve sair com 0
if [ "$EXIT_SUBPASTA" = "0" ]; then
  # Arquivo deve estar na raiz de dados, NÃO na subpasta
  if [ -f "$REGISTRO_LOGFILE_RAIZ" ] && [ ! -f "$REGISTRO_LOGFILE_SUBDIR" ]; then
    if grep -q "\"motivo\":\"Log deve ir para raiz de dados, não subdir\"" "$REGISTRO_LOGFILE_RAIZ"; then
      ok=$((ok + 1))
      echo "  ok   divergencia-log-em-subpasta-de-repo: arquivo em raiz de dados, não em subdir"
    else
      falhou=$((falhou + 1))
      echo "  FALHA divergencia-log-em-subpasta-de-repo: conteúdo não bate"
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA divergencia-log-em-subpasta-de-repo: arquivo deveria estar em raiz de dados"
    [ -f "$REGISTRO_LOGFILE_RAIZ" ] && echo "    (existe em raiz de dados)" || echo "    (não existe em raiz de dados)"
    [ -f "$REGISTRO_LOGFILE_SUBDIR" ] && echo "    (existe em subdir - ERRADO)" || echo "    (não existe em subdir - correto)"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA divergencia-log-em-subpasta-de-repo: deveria sair 0, saiu $EXIT_SUBPASTA"
fi

echo ""
echo "== CASO 18: divergencia-sem-flag-motivo-recusa =="

TEMP_REPO_SEM_MOT="$RAIZ/test-divergencia-sem-motivo-repo"
mkdir -p "$TEMP_REPO_SEM_MOT"
cd "$TEMP_REPO_SEM_MOT"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_SEM_MOT=$(git rev-parse HEAD)

# Criar .rainforest para marcar raiz de dados
mkdir -p "$TEMP_REPO_SEM_MOT/.rainforest"
touch "$TEMP_REPO_SEM_MOT/.rainforest/FOCO.md"

REGISTRO_LOGFILE_SEM_MOT="$TEMP_REPO_SEM_MOT/.rainforest/.logs/divergencias-segunda-opiniao.jsonl"
rm -f "$REGISTRO_LOGFILE_SEM_MOT"

OUTPUT_SEM_MOT=$(cd "$TEMP_REPO_SEM_MOT" && node "$SRC/scripts/segunda-opiniao.cjs" registrar-divergencia \
  --veredito discordo \
  --base "$BASE_SHA_SEM_MOT" 2>&1); EXIT_SEM_MOT=$?

if [ "$EXIT_SEM_MOT" != "0" ]; then
  if [ ! -f "$REGISTRO_LOGFILE_SEM_MOT" ]; then
    if echo "$OUTPUT_SEM_MOT" | grep -q "requer --veredito, --motivo e --base"; then
      ok=$((ok + 1))
      echo "  ok   divergencia-sem-flag-motivo-recusa: exit ≠ 0, nada gravado, mensagem correta"
    else
      falhou=$((falhou + 1))
      echo "  FALHA divergencia-sem-flag-motivo-recusa: mensagem não contém 'requer --veredito, --motivo e --base'"
      echo "$OUTPUT_SEM_MOT" | head -3
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA divergencia-sem-flag-motivo-recusa: arquivo não deveria ter sido criado"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA divergencia-sem-flag-motivo-recusa: deveria sair ≠ 0, saiu 0"
fi

echo ""
echo "== CASO 19: divergencia-de-dentro-de-worktree-grava-em-raiz-dados =="

# Teste em worktree — o log deve ir para raiz de dados, não desaparecer com worktree
# Isso testa o cenário normal de uso: revisar (que roda em worktree agente) rejeita,
# registrar-divergencia é chamado de dentro do worktree, log deve ficar na raiz de dados
# compartilhada (nível global ou projeto, não dentro do worktree)
TEMP_REPO_WORKTREE="$RAIZ/test-worktree-repo"
mkdir -p "$TEMP_REPO_WORKTREE"
cd "$TEMP_REPO_WORKTREE"
git init --quiet
git config user.email "test@<email>"
git config user.name "Test"

echo "content" > file.txt
git add file.txt
git commit --quiet -m "base"
BASE_SHA_WORKTREE=$(git rev-parse HEAD)

# Criar uma raiz de dados compartilhada (nível principal, não no worktree)
RAIZ_DADOS_WORKTREE="$RAIZ/dados-worktree"
mkdir -p "$RAIZ_DADOS_WORKTREE"
touch "$RAIZ_DADOS_WORKTREE/FOCO.md"

# Criar um worktree
WORKTREE_PATH="$TEMP_REPO_WORKTREE/.github-worktree"
git worktree add "$WORKTREE_PATH" -b worktree-branch HEAD > /dev/null 2>&1

# Caminhos esperados — o log vai para a raiz compartilhada, não morre com worktree
LOG_IN_RAIZ="$RAIZ_DADOS_WORKTREE/.logs/divergencias-segunda-opiniao.jsonl"
LOG_IN_WORKTREE="$WORKTREE_PATH/.logs/divergencias-segunda-opiniao.jsonl"

# Limpar logs se existirem
rm -f "$LOG_IN_RAIZ" "$LOG_IN_WORKTREE"

# Registrar divergência RODANDO DE DENTRO DO WORKTREE COM RFM_ROOT
(cd "$WORKTREE_PATH" && RFM_ROOT="$RAIZ_DADOS_WORKTREE" node "$SRC/scripts/segunda-opiniao.cjs" registrar-divergencia \
  --veredito discordo \
  --motivo "Teste de worktree — log não morre" \
  --base "$BASE_SHA_WORKTREE" > /dev/null 2>&1); EXIT_WORKTREE=$?

# Deve sair com 0
if [ "$EXIT_WORKTREE" = "0" ]; then
  # Arquivo DEVE estar na raiz compartilhada, NÃO no worktree
  if [ -f "$LOG_IN_RAIZ" ] && [ ! -f "$LOG_IN_WORKTREE" ]; then
    if grep -q "\"motivo\":\"Teste de worktree — log não morre\"" "$LOG_IN_RAIZ"; then
      ok=$((ok + 1))
      echo "  ok   divergencia-de-dentro-de-worktree-grava-em-raiz-dados: arquivo em raiz compartilhada, não em worktree"
    else
      falhou=$((falhou + 1))
      echo "  FALHA divergencia-de-dentro-de-worktree-grava-em-raiz-dados: conteúdo não bate"
      cat "$LOG_IN_RAIZ" | head -3
    fi
  else
    falhou=$((falhou + 1))
    echo "  FALHA divergencia-de-dentro-de-worktree-grava-em-raiz-dados: arquivo não onde deveria estar"
    [ -f "$LOG_IN_RAIZ" ] && echo "    (existe em raiz compartilhada)" || echo "    (não existe em raiz compartilhada - ERRADO)"
    [ -f "$LOG_IN_WORKTREE" ] && echo "    (existe em worktree - ERRADO)" || echo "    (não existe em worktree - correto)"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA divergencia-de-dentro-de-worktree-grava-em-raiz-dados: deveria sair 0, saiu $EXIT_WORKTREE"
fi

# Limpar worktree
git worktree remove "$WORKTREE_PATH" 2>/dev/null

# Contar todas as fixtures do diretório e verificar se cada uma é referenciada
echo "== AUDITORIA DE FIXTURES =="
FIXTURES_DIR="$SRC/scripts/fixtures/segunda-opiniao"
for fixture in "$FIXTURES_DIR"/*.cjs; do
  fixture_name=$(basename "$fixture" .cjs)
  # Conta so INVOCACAO real: linha nao-comentada citando o arquivo com extensao.
  # Contar o nome cru deixava passar orfa cujo nome sobrevive so num comentario
  # — a auditoria tinha o mesmo defeito que existe para pegar (revisao 4, achado 2).
  count=$(grep -v "^[[:space:]]*#" "$SRC/scripts/testa-segunda-opiniao.sh" | grep -c "$fixture_name.cjs")
  if [ -z "$count" ] || [ "$count" -eq 0 ]; then
    falhou=$((falhou + 1))
    echo "  FALHA: fixture órfã '$fixture_name' não é referenciada em testa-segunda-opiniao.sh"
  fi
done

echo ""
echo "== RESUMO =="
echo "Ok: $ok"
echo "Falhou: $falhou"
echo ""


echo ""

if [ "$falhou" -eq 0 ]; then
  echo "Bateria passou!"
  exit 0
else
  echo "Bateria teve falhas."
  exit 1
fi
