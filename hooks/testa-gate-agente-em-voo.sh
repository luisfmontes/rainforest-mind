#!/bin/bash
set -e

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RAIZ/hooks/gate-agente-em-voo.cjs"
CWD="$RAIZ"

testes_OK=0
testes_FALHARAM=0

function teste() {
  local descricao="$1"
  local input="$2"
  local exit_esperado="$3"
  local deve_conter="$4"  # opcional

  echo "● $descricao"

  local saida stderr_tmp
  stderr_tmp=$(mktemp)

  if saida=$(echo "$input" | node "$HOOK" 2>"$stderr_tmp"); then
    exit_obtido=0
  else
    exit_obtido=$?
  fi

  local stderr_conteudo
  stderr_conteudo=$(cat "$stderr_tmp")
  rm -f "$stderr_tmp"

  local passou=1

  # Verifica exit code
  if [ "$exit_obtido" != "$exit_esperado" ]; then
    echo "  ✗ exit code: esperado $exit_esperado, obtido $exit_obtido"
    passou=0
  fi

  # Verifica conteúdo de stderr se foi fornecido
  if [ -n "$deve_conter" ] && [ "$passou" = "1" ]; then
    if ! echo "$stderr_conteudo" | grep -q "$deve_conter"; then
      echo "  ✗ mensagem não contém: '$deve_conter'"
      echo "  Stderr obtido: $stderr_conteudo"
      passou=0
    fi
  fi

  if [ "$passou" = "1" ]; then
    echo "  ✓"
    ((testes_OK++))
  else
    ((testes_FALHARAM++))
  fi
}

# ============================================================================
# TESTE 1: Payload com cwd, stop_hook_active=false, com em_voo
# Esperado: exit 2 com mensagem nomeando agente
# ============================================================================

teste "1. Payload com stop_hook_active=false e em_voo → exit 2" \
  "{\"cwd\":\"$CWD\",\"stop_hook_active\":false}" \
  2 \
  "revisor-teste"

# ============================================================================
# TESTE 2: Mesmo payload com stop_hook_active=true
# Esperado: exit 0
# ============================================================================

teste "2. Payload com stop_hook_active=true e em_voo → exit 0" \
  "{\"cwd\":\"$CWD\",\"stop_hook_active\":true}" \
  0

# ============================================================================
# TESTE 3: Payload vazio
# Esperado: exit 0
# ============================================================================

teste "3. Payload vazio → exit 0" \
  "{}" \
  0

# ============================================================================
# TESTE 4: Payload ilegível
# Esperado: exit 0
# ============================================================================

teste "4. Payload ilegível → exit 0" \
  "isto nao e json" \
  0

# ============================================================================
# TESTE 5: Payload com cwd que não é repositório git
# Esperado: exit 0
# ============================================================================

teste "5. CWD sem repositório git → exit 0" \
  "{\"cwd\":\"/tmp\",\"stop_hook_active\":false}" \
  0

# ============================================================================
# TESTE 6: Verificar que sem em_voo, exit 0
# ============================================================================

# Primeiro, marca revisar com status ok para remover em_voo
node "$RAIZ/scripts/estado.cjs" marcar \
  --slug "2026-09-04-worktree-agent-ad251062fd468da54" \
  --estagio revisar \
  --status ok \
  --json '{"achados":0}' \
  > /dev/null 2>&1 || true

teste "6. Estado sem em_voo → exit 0" \
  "{\"cwd\":\"$CWD\",\"stop_hook_active\":false}" \
  0

# ============================================================================
# Resultado final
# ============================================================================

echo ""
if [ $testes_FALHARAM -eq 0 ]; then
  echo "✓ $testes_OK teste(s) — 0 falha(s)"
  exit 0
else
  echo "✗ $testes_OK passaram, $testes_FALHARAM falharam"
  exit 1
fi
