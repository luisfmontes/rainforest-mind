#!/bin/bash
set -euo pipefail

# Testa acharExecutavelClaude com cenários de .cmd / .bat e node_modules/@anthropic-ai/claude-code/bin/claude.exe

TMPDIR="${TMPDIR:-/tmp}"
TEST_ROOT="$TMPDIR/test-achar-exe-$$"
mkdir -p "$TEST_ROOT"
trap "rm -rf '$TEST_ROOT'" EXIT

# Cenário 1: PATH com dir contendo só claude.cmd + node_modules/.../claude.exe
# Esperado: devolve o .exe
echo "[Cenário 1] .cmd + node_modules/.../claude.exe" >&2
PATH1="$TEST_ROOT/path1"
mkdir -p "$PATH1/node_modules/@anthropic-ai/claude-code/bin"
touch "$PATH1/claude.cmd"
touch "$PATH1/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
chmod +x "$PATH1/node_modules/@anthropic-ai/claude-code/bin/claude.exe"

export PATH="$PATH1"
unset RFM_CLAUDE_EXECUTAVEL || true
RESULT=$(node -e "console.log(require('./scripts/lib/achar-executavel-claude.cjs').acharExecutavelClaude())")
EXPECTED="$PATH1/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
if [ "$RESULT" != "$EXPECTED" ]; then
  echo "ERRO Cenário 1: esperava '$EXPECTED', obteve '$RESULT'" >&2
  exit 1
fi
echo "✓ Cenário 1 passou" >&2

# Cenário 2: dir com só claude.cmd sem node_modules, seguido de outro dir com claude.exe
# Esperado: devolve o .exe do segundo dir
echo "[Cenário 2] .cmd sem node_modules + outro dir com .exe" >&2
PATH2A="$TEST_ROOT/path2a"
PATH2B="$TEST_ROOT/path2b"
mkdir -p "$PATH2A"
mkdir -p "$PATH2B"
touch "$PATH2A/claude.cmd"
touch "$PATH2B/claude.exe"
chmod +x "$PATH2B/claude.exe"

export PATH="$PATH2A:$PATH2B"
unset RFM_CLAUDE_EXECUTAVEL || true
RESULT=$(node -e "console.log(require('./scripts/lib/achar-executavel-claude.cjs').acharExecutavelClaude())")
EXPECTED="$PATH2B/claude.exe"
if [ "$RESULT" != "$EXPECTED" ]; then
  echo "ERRO Cenário 2: esperava '$EXPECTED', obteve '$RESULT'" >&2
  exit 1
fi
echo "✓ Cenário 2 passou" >&2

# Cenário 3: só .cmd sem .exe em lugar nenhum
# Esperado: null (vazio)
echo "[Cenário 3] só .cmd sem .exe" >&2
PATH3="$TEST_ROOT/path3"
mkdir -p "$PATH3"
touch "$PATH3/claude.cmd"

export PATH="$PATH3"
unset RFM_CLAUDE_EXECUTAVEL || true
RESULT=$(node -e "console.log(require('./scripts/lib/achar-executavel-claude.cjs').acharExecutavelClaude() || 'null')")
EXPECTED="null"
if [ "$RESULT" != "$EXPECTED" ]; then
  echo "ERRO Cenário 3: esperava '$EXPECTED', obteve '$RESULT'" >&2
  exit 1
fi
echo "✓ Cenário 3 passou" >&2

# Cenário 4: RFM_CLAUDE_EXECUTAVEL sobrepõe
echo "[Cenário 4] RFM_CLAUDE_EXECUTAVEL sobrepõe" >&2
CUSTOM_PATH="/custom/path/to/claude"
export RFM_CLAUDE_EXECUTAVEL="$CUSTOM_PATH"
export PATH="$PATH3"
RESULT=$(node -e "console.log(require('./scripts/lib/achar-executavel-claude.cjs').acharExecutavelClaude())")
EXPECTED="$CUSTOM_PATH"
if [ "$RESULT" != "$EXPECTED" ]; then
  echo "ERRO Cenário 4: esperava '$EXPECTED', obteve '$RESULT'" >&2
  exit 1
fi
echo "✓ Cenário 4 passou" >&2

# Cenário 5: .bat é tratado como .cmd (tenta node_modules/.../claude.exe)
echo "[Cenário 5] .bat + node_modules/.../claude.exe" >&2
PATH5="$TEST_ROOT/path5"
mkdir -p "$PATH5/node_modules/@anthropic-ai/claude-code/bin"
touch "$PATH5/claude.bat"
touch "$PATH5/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
chmod +x "$PATH5/node_modules/@anthropic-ai/claude-code/bin/claude.exe"

export PATH="$PATH5"
unset RFM_CLAUDE_EXECUTAVEL || true
RESULT=$(node -e "console.log(require('./scripts/lib/achar-executavel-claude.cjs').acharExecutavelClaude())")
EXPECTED="$PATH5/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
if [ "$RESULT" != "$EXPECTED" ]; then
  echo "ERRO Cenário 5: esperava '$EXPECTED', obteve '$RESULT'" >&2
  exit 1
fi
echo "✓ Cenário 5 passou" >&2

echo "✓ Todos os testes passaram" >&2
exit 0
