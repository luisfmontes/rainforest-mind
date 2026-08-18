#!/bin/bash
# Bateria do hooks/memoria-marca.cjs
# Uso: bash hooks/testa-memoria-marca.sh
#
# O que esta bateria precisa provar:
#   1. que o hook grava sessão, caminho do transcrito e offset
#   2. que nenhum spawn/exec existe no arquivo
#   3. que reprocessar após recuar o offset é idempotente (mesma contagem)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/memoria-marca.cjs"
SCRIPT_MEMORIA="$SRC/scripts/memoria.cjs"

# Sandbox hermética
RAIZ_POSIX="$(mktemp -d)"
RAIZ=$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# Teste 1: Não existe spawn/exec no arquivo
echo
echo "1. Não existe spawn/exec no arquivo"
if grep -E '\.spawn\(|\.exec\(|spawn\(|exec\(' "$HOOK" | grep -v '//' > /dev/null 2>&1; then
  falhou=$((falhou+1)); echo "  FALHA encontrado spawn/exec"
else
  ok=$((ok+1)); echo "  ok    sem spawn/exec"
fi

# Teste 2: Inicializa banco
echo
echo "2. Inicializando banco na caixa de areia"
RFM_ROOT="$RAIZ" node "$SCRIPT_MEMORIA" iniciar > /dev/null 2>&1

if [ -f "$RAIZ_POSIX/rainforest.db" ]; then
  ok=$((ok+1)); echo "  ok    banco criado"
else
  falhou=$((falhou+1)); echo "  FALHA banco não criado"
  echo "== resultado: $ok ok, $falhou falha(s) =="
  exit 1
fi

# Teste 3: Cria transcrito e roda hook
echo
echo "3. Hook grava marca d'água"
mkdir -p "$RAIZ_POSIX/projects/projeto-teste"
echo '{"tipo":"prompt","conteudo":"Teste"}' > "$RAIZ_POSIX/projects/projeto-teste/sessao-teste-001.jsonl"
OFFSET_ESPERADO=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/sessao-teste-001.jsonl")

EVENTO='{"session_id":"sessao-teste-001","project":"projeto-teste"}'
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica se foi gravado
RESULTADO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT * FROM marca_dagua WHERE sessao=\\'sessao-teste-001\\'');
const rows = stmt.all();
console.log(rows.length);
if (rows.length > 0) console.log(JSON.stringify(rows[0]));
db.close();
" 2>/dev/null)

LINHA=$(echo "$RESULTADO" | head -1)
if [ "$LINHA" = "1" ]; then
  ok=$((ok+1)); echo "  ok    marca d'água gravada (sessão=sessao-teste-001)"

  # Verifica offset
  DADOS=$(echo "$RESULTADO" | tail -1)
  OFFSET_GRAVADO=$(echo "$DADOS" | grep -o '"offset":[0-9]*' | cut -d':' -f2)

  if [ "$OFFSET_GRAVADO" = "$OFFSET_ESPERADO" ]; then
    ok=$((ok+1)); echo "  ok    offset correto ($OFFSET_GRAVADO bytes)"
  else
    falhou=$((falhou+1)); echo "  FALHA offset diverge (esperado=$OFFSET_ESPERADO, obtido=$OFFSET_GRAVADO)"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA marca d'água não foi gravada"
fi

# Teste 4: Idempotência
echo
echo "4. Reprocessamento é idempotente"
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

RESULTADO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COUNT(*) FROM marca_dagua WHERE sessao=\\'sessao-teste-001\\'');
const rows = stmt.all();
console.log(rows[0]['COUNT(*)']);
db.close();
" 2>/dev/null)

if [ "$RESULTADO" = "1" ]; then
  ok=$((ok+1)); echo "  ok    idempotente (1 linha após 2 execuções)"
else
  falhou=$((falhou+1)); echo "  FALHA contagem mudou ($RESULTADO linhas)"
fi

# Teste 5: Recuar offset e reprocessar
echo
echo "5. Recuar offset e reprocessar preserva idempotência"

# Muda transcrito (maior)
echo '{"tipo":"nova_ferramenta"}' >> "$RAIZ_POSIX/projects/projeto-teste/sessao-teste-001.jsonl"
NOVO_OFFSET=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/sessao-teste-001.jsonl")

# Roda hook com novo offset
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica offset atualizado
RESULTADO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'sessao-teste-001\\'');
const rows = stmt.all();
console.log(rows[0].offset);
db.close();
" 2>/dev/null)

if [ "$RESULTADO" = "$NOVO_OFFSET" ]; then
  ok=$((ok+1)); echo "  ok    offset atualizado ($NOVO_OFFSET bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA offset não foi atualizado (esperado=$NOVO_OFFSET, obtido=$RESULTADO)"
fi

# Roda novamente (deve ser idempotente)
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

RESULTADO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COUNT(*) FROM marca_dagua WHERE sessao=\\'sessao-teste-001\\'');
const rows = stmt.all();
console.log(rows[0]['COUNT(*)']);
db.close();
" 2>/dev/null)

if [ "$RESULTADO" = "1" ]; then
  ok=$((ok+1)); echo "  ok    idempotente com novo offset (1 linha)"
else
  falhou=$((falhou+1)); echo "  FALHA idempotência quebrou após update (contagem=$RESULTADO)"
fi

# Teste 6: Degradação graciosa
echo
echo "6. Degradação graciosa: banco ausente"

RAIZ_VAZIO="$(mktemp -d)"
trap "rm -rf $RAIZ_POSIX $RAIZ_VAZIO" EXIT

echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ_VAZIO" \
  RFM_ROOT="$RAIZ_VAZIO" \
  node "$HOOK" > /dev/null 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    hook saiu com exit 0 quando banco não existia"
else
  falhou=$((falhou+1)); echo "  FALHA hook saiu com exit $EXIT_CODE"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
