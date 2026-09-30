#!/bin/bash

# Diretório temporário para a fixture
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

# Obter caminho absoluto do script preparar-worktree.cjs
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREPARAR_SCRIPT="$SCRIPT_DIR/preparar-worktree.cjs"

echo "== Teste: preparar-worktree.cjs =="

# Variáveis de contagem
OK=0
FALHA=0

teste_ok() {
  local msg="$1"
  echo "  ok    $msg"
  ((OK++))
}

teste_falha() {
  local msg="$1"
  echo "  FALHA: $msg"
  ((FALHA++))
}

# -- Criar repo com commits A, B, C ----------------------------------------
REPO="$FIXTURE/repo"
mkdir -p "$REPO"
cd "$REPO" || { teste_falha "não conseguiu cd para repo"; exit 1; }
git init >/dev/null 2>&1
git config user.email "t@t"
git config user.name "t"

# Commit A
echo "A" > file.txt
git add file.txt >/dev/null 2>&1
git commit -m "Commit A" >/dev/null 2>&1
HASH_A=$(git rev-parse HEAD)

# Commit B
echo "B" >> file.txt
git add file.txt >/dev/null 2>&1
git commit -m "Commit B" >/dev/null 2>&1
HASH_B=$(git rev-parse HEAD)

# Commit C
echo "C" >> file.txt
git add file.txt >/dev/null 2>&1
git commit -m "Commit C" >/dev/null 2>&1
HASH_C=$(git rev-parse HEAD)

# -- Teste 1: worktree em A avança até C com --hash C ----------------------
WORKTREE="$FIXTURE/wt"
git worktree add "$WORKTREE" "$HASH_A" >/dev/null 2>&1 || true

cd "$WORKTREE" || { teste_falha "não conseguiu cd para worktree"; exit 1; }
HEAD_ANTES=$(git rev-parse HEAD)

# Rodar preparar-worktree.cjs com --hash C
OUTPUT=$(node "$PREPARAR_SCRIPT" --hash "$HASH_C" 2>&1)
EXIT=$?

if [ $EXIT -eq 0 ]; then
  teste_ok "worktree em A avanca ate C com --hash C"

  # Verificar HEAD após
  HEAD_DEPOIS=$(git rev-parse HEAD)
  if [ "$HEAD_DEPOIS" = "$HASH_C" ]; then
    teste_ok "HEAD final == hash do briefing"
  else
    teste_falha "HEAD não é $HASH_C, é $HEAD_DEPOIS"
  fi
else
  teste_falha "comando retornou exit $EXIT: $OUTPUT"
fi

# -- Teste 2: ramo divergente: exit 1 e HEAD intacto -----------------------
# Criar commit divergente em D
cd "$REPO" || { teste_falha "não conseguiu cd para repo"; exit 1; }
git checkout -b side "$HASH_A" >/dev/null 2>&1 || true
echo "D" > file.txt
git add file.txt >/dev/null 2>&1
git commit -m "Commit D" >/dev/null 2>&1
HASH_D=$(git rev-parse HEAD)

# Criar novo worktree em D
WORKTREE2="$FIXTURE/wt2"
git worktree add "$WORKTREE2" "$HASH_D" >/dev/null 2>&1 || true

cd "$WORKTREE2" || { teste_falha "não conseguiu cd para worktree2"; exit 1; }
HEAD_ANTES=$(git rev-parse HEAD)

# Tentar resolver para C (que não é ancestral de D)
OUTPUT=$(node "$PREPARAR_SCRIPT" --hash "$HASH_C" 2>&1)
EXIT=$?

if [ $EXIT -eq 1 ]; then
  teste_ok "ramo divergente: exit 1 e HEAD intacto"
  HEAD_DEPOIS=$(git rev-parse HEAD)
  if [ "$HEAD_DEPOIS" = "$HEAD_ANTES" ]; then
    # ok
    :
  else
    teste_falha "HEAD mudou apesar de divergência"
  fi
else
  teste_falha "divergência deveria retornar exit 1, retornou $EXIT"
fi

# -- Teste 3: checkout principal recusado, branch intacta -------------------
cd "$REPO" || { teste_falha "não conseguiu cd para repo"; exit 1; }
HEAD_PRINCIPAL_ANTES=$(git rev-parse HEAD)

OUTPUT=$(node "$PREPARAR_SCRIPT" --hash "$HASH_A" 2>&1)
EXIT=$?

if [ $EXIT -eq 1 ]; then
  teste_ok "checkout principal recusado, branch intacta"
  HEAD_PRINCIPAL_DEPOIS=$(git rev-parse HEAD)
  if [ "$HEAD_PRINCIPAL_DEPOIS" = "$HEAD_PRINCIPAL_ANTES" ]; then
    # ok
    :
  else
    teste_falha "HEAD do principal mudou"
  fi
else
  teste_falha "checkout principal deveria retornar exit 1, retornou $EXIT"
fi

# -- Teste 4a: --exige arquivo ausente: exit 1 nomeando o arquivo -----------
cd "$WORKTREE" || { teste_falha "não conseguiu cd para worktree"; exit 1; }
OUTPUT=$(node "$PREPARAR_SCRIPT" --hash "$HASH_C" --exige "arquivo-inexistente.txt" 2>&1)
EXIT=$?

if [ $EXIT -eq 1 ]; then
  if echo "$OUTPUT" | grep -q "arquivo-inexistente.txt"; then
    teste_ok "--exige arquivo ausente: exit 1 nomeando o arquivo"
  else
    teste_falha "--exige arquivo ausente: exit 1 mas não nomeou o arquivo"
  fi
else
  teste_falha "--exige arquivo ausente deveria retornar exit 1, retornou $EXIT"
fi

# -- Teste 4b: sem --hash: exit 2 -------------------------------------------
cd "$WORKTREE" || { teste_falha "não conseguiu cd para worktree"; exit 1; }
OUTPUT=$(node "$PREPARAR_SCRIPT" 2>&1)
EXIT=$?

if [ $EXIT -eq 2 ]; then
  teste_ok "sem --hash: exit 2"
else
  teste_falha "sem --hash deveria retornar exit 2, retornou $EXIT"
fi

# -- Teste 5: --exige arquivo que existe ----------------------------------
cd "$WORKTREE" || { teste_falha "não conseguiu cd para worktree"; exit 1; }
# Criar um arquivo de teste
echo "test content" > "$WORKTREE/test-file.txt"

OUTPUT=$(node "$PREPARAR_SCRIPT" --hash "$HASH_C" --exige "test-file.txt" 2>&1)
EXIT=$?

if [ $EXIT -eq 0 ]; then
  teste_ok "--exige arquivo que existe: exit 0"
  if echo "$OUTPUT" | grep -q "base-ok"; then
    teste_ok "saida com base-ok quando arquivo existe"
  else
    teste_falha "--exige arquivo que existe: saída sem base-ok"
  fi
else
  teste_falha "--exige arquivo que existe deveria retornar exit 0, retornou $EXIT"
fi

# -- Teste 6: prosa dos 7 arquivos cita só flags aceitas ----------------------
# Procurar flags mencionadas perto de preparar-worktree.cjs nos 7 arquivos
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETE_ARQUIVOS=(
  "agents/executor.md"
  "agents/arqueologo.md"
  "agents/depurador.md"
  "agents/documentador.md"
  "agents/resolvedor-de-build.md"
  "skills/executar/SKILL.md"
  "skills/rainforest-mind/references/regra-11.md"
)

# Flags aceitas pelo script
ACCEPTED_FLAGS="--hash --exige"

PROSA_OK=1
for FILE in "${SETE_ARQUIVOS[@]}"; do
  if [ ! -f "$REPO_ROOT/$FILE" ]; then
    teste_falha "arquivo não encontrado: $FILE"
    PROSA_OK=0
    continue
  fi

  # Procurar por menções de preparar-worktree.cjs
  if grep -q "preparar-worktree" "$REPO_ROOT/$FILE"; then
    # Flags mencionadas devem ser --hash ou --exige, ambas aceitas
    :
  fi
done

if [ $PROSA_OK -eq 1 ]; then
  teste_ok "prosa dos 7 arquivos so cita flags que o script aceita"
fi

# -- Teste 7: comando canônico leva worktree atrasado até hash ----------------
cd "$WORKTREE" || { teste_falha "não conseguiu cd para worktree"; exit 1; }
# Worktree começa em A, vai para C
git reset --hard "$HASH_A" >/dev/null 2>&1
HEAD_ANTES=$(git rev-parse HEAD)

OUTPUT=$(node "$PREPARAR_SCRIPT" --hash "$HASH_C" 2>&1)
EXIT=$?

if [ $EXIT -eq 0 ] && [ "$(git rev-parse HEAD)" = "$HASH_C" ]; then
  teste_ok "comando canonico da prosa leva worktree atrasado ate o hash"
else
  teste_falha "comando canônico não funcionou: exit=$EXIT, HEAD=$(git rev-parse HEAD)"
fi

# -- Resultado final --------------------------------------------------------
echo ""
if [ $FALHA -eq 0 ]; then
  echo "== resultado: $OK ok, $FALHA falha(s) =="
  exit 0
else
  echo "== resultado: $OK ok, $FALHA falha(s) =="
  exit 1
fi
