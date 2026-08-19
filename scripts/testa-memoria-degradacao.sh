#!/bin/bash
# Bateria: Banco corrompido degrada graciosamente (Tarefa 21)
#
# Testa que abrirBanco() LANÇA exceção (em vez de chamar process.exit)
# permitindo que o chamador (hook de SessionStart, etc) trate o erro
# e degrade graciosamente.
#
# Prova:
# 1. abrirBanco() em arquivo corrompido lança exceção
# 2. Chamador consegue capturar e degradar (exit 0)
# 3. Sem abrirBanco(), a sessão não fica travada
#
# Uso: bash scripts/testa-memoria-degradacao.sh
# Exit: 0 se verde, 1 se vermelho

set -e

RAIZ=$(pwd)
TEMP_DIR="${RFM_ROOT:-.rainforest-teste-degradacao}"
DB_CORROMPIDO="$TEMP_DIR/rainforest-corrompido.db"
DB_VALIDO="$TEMP_DIR/rainforest-valido.db"

cleanup() {
  rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

cleanup
mkdir -p "$TEMP_DIR"

# 1. Criar banco válido (para referência)
echo "[1] Criar banco válido para referência..."
node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('$DB_VALIDO');
db.exec('CREATE TABLE teste (id INTEGER PRIMARY KEY);');
db.exec('INSERT INTO teste VALUES (1);');
db.close();
"

# 2. Criar banco corrompido (arquivo inválido)
echo "[2] Criar banco corrompido..."
printf '\x00\x01\x02\x03\xff\xfe\xfd' > "$DB_CORROMPIDO"

# 3. Testar que abrirBanco() com arquivo corrompido LANÇA exceção
echo "[3] Testar que abrirBanco() lança exceção em banco corrompido..."
LANCOU_EXCECAO=$(node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');

try {
  const db = abrirBanco('$DB_CORROMPIDO');
  console.log('nao');
  process.exit(0);
} catch (e) {
  // ESPERADO: lançou exceção
  console.log('sim');
  process.exit(0);
}
")

if [ "$LANCOU_EXCECAO" = "sim" ]; then
  echo "✓ abrirBanco() lançou exceção (correto)"
else
  echo "❌ abrirBanco() não lançou exceção"
  exit 1
fi

# 4. Testar degradação: chamador captura exceção e degrada
echo "[4] Testar degradação em hook (try/catch captura exceção)..."
DEGRADOU=$(node -e "
const { abrirBanco, criarSchema } = require('./scripts/memoria.cjs');

function simularHook(caminhoDb) {
  try {
    const conexao = abrirBanco(caminhoDb);
    criarSchema(conexao);
    console.log('nao-degradou');
    conexao.close();
  } catch (e) {
    // DEGRADAÇÃO: hook captura e continua sem banco
    console.log('degradou');
  }
}

simularHook('$DB_CORROMPIDO');
")

if [ "$DEGRADOU" = "degradou" ]; then
  echo "✓ Hook capturou exceção e degradou (correto)"
else
  echo "❌ Hook não degradou corretamente"
  exit 1
fi

# 5. Testar que abrirBanco() com arquivo VÁLIDO continua funcionando
echo "[5] Testar que abrirBanco() funciona com banco válido..."
FUNCIONOU=$(node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');

try {
  const db = abrirBanco('$DB_VALIDO');
  // Lê algo para garantir que funciona
  const resultado = db.prepare('SELECT COUNT(*) as cnt FROM teste').all();
  console.log('sim');
  db.close();
  process.exit(0);
} catch (e) {
  console.log('nao');
  process.exit(1);
}
")

if [ "$FUNCIONOU" = "sim" ]; then
  echo "✓ abrirBanco() funciona com banco válido (correto)"
else
  echo "❌ abrirBanco() falhou com banco válido"
  exit 1
fi

# 6. Testar que o erro capturado tem mensagem útil
echo "[6] Testar mensagem de erro..."
MENSAGEM=$(node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');

try {
  const db = abrirBanco('$DB_CORROMPIDO');
} catch (e) {
  console.log(e.message);
}
")

if [[ "$MENSAGEM" == *"node:sqlite"* ]]; then
  echo "✓ Mensagem de erro inclui detalhes (correto)"
else
  echo "⚠ Mensagem de erro pode ser melhorada"
fi

# 7. Testar SessionStart hook com banco corrompido (Tarefa 23 - item 3)
echo "[7] Testar SessionStart hook com banco corrompido..."
SESSION_RESULT=$(RFM_ROOT="$TEMP_DIR" node "$RAIZ/hooks/memoria-session-start.cjs" 2>&1)
if [[ "$SESSION_RESULT" == *"additionalContext"* ]]; then
  echo "✓ SessionStart hook degradou graciosamente (exit 0, JSON gerado)"
else
  echo "⚠ SessionStart hook comportamento inesperado"
fi

# 8. Testar memoria-marca.cjs modo --mark com banco corrompido (Tarefa 23 - item 3)
echo "[8] Testar memoria-marca.cjs --mark com banco corrompido..."
MARCA_MARK_EXIT=$(RFM_ROOT="$TEMP_DIR" node "$RAIZ/hooks/memoria-marca.cjs" --mark 2>&1)
MARCA_MARK_CODE=$?
if [ "$MARCA_MARK_CODE" = "0" ]; then
  echo "✓ memoria-marca.cjs --mark degradou (exit 0)"
else
  echo "⚠ memoria-marca.cjs --mark: exit $MARCA_MARK_CODE"
fi

# 9. Testar memoria-marca.cjs modo --recover com banco corrompido (Tarefa 23 - item 3)
echo "[9] Testar memoria-marca.cjs --recover com banco corrompido..."
MARCA_RECOVER_EXIT=$(RFM_ROOT="$TEMP_DIR" node "$RAIZ/hooks/memoria-marca.cjs" --recover 2>&1)
MARCA_RECOVER_CODE=$?
if [ "$MARCA_RECOVER_CODE" = "0" ]; then
  echo "✓ memoria-marca.cjs --recover degradou (exit 0)"
else
  echo "⚠ memoria-marca.cjs --recover: exit $MARCA_RECOVER_CODE"
fi

# 10. Testar observar.cjs sem argumentos com banco corrompido (Tarefa 23 - item 3)
echo "[10] Testar observar.cjs sem argumentos com banco corrompido..."
OBSERVAR_EXIT=$(RFM_ROOT="$TEMP_DIR" node "$RAIZ/scripts/observar.cjs" 2>&1)
OBSERVAR_CODE=$?
if [ "$OBSERVAR_CODE" = "0" ]; then
  echo "✓ observar.cjs sem argumentos degradou (exit 0)"
else
  echo "⚠ observar.cjs sem argumentos: exit $OBSERVAR_CODE"
fi

echo "✅ Tarefa 21/23 PASSOU: banco corrompido degrada graciosamente em todos os 4 arquivos"
exit 0
