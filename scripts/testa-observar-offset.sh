#!/bin/bash
# Bateria: Offset é byte de ponta a ponta (Tarefa 19)
#
# Caso: primeira linha com acentuação PT-BR (16 caracteres multibyte = 32 bytes extras).
# Primeira linha ~100 bytes, segunda linha começa no byte ~100.
# Se usar substring (char-based), offset em caracteres ≠ offset em bytes.
#
# Esperado: código ANTIGO (substring) => falha ao parsear JSON (0 eventos)
#           código NOVO (Buffer.toString) => sucesso (1+ eventos)
#
# Uso: bash scripts/testa-observar-offset.sh
# Exit: 0 se verde, 1 se vermelho

set -e

RAIZ=$(pwd)
TEMP_DIR="${RFM_ROOT:-.rainforest-teste-offset}"
DB="$TEMP_DIR/rainforest.db"
TRANSCRIPT="$TEMP_DIR/test-session.jsonl"

cleanup() {
  rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

cleanup
mkdir -p "$TEMP_DIR"

echo "[1] Iniciar banco..."
RFM_ROOT="$TEMP_DIR" node scripts/memoria.cjs iniciar >/dev/null 2>&1

echo "[2] Criar transcrito com acentuação PT-BR..."
# Primeira linha: JSON com acentos (16 acentos = 32 bytes extras)
# String: {"type":"user","message":{"content":"àáâãäèéêëìíîïòóôõöùúûüç"},"session_id":"S001"}\n
# ~120 bytes
cat > "$TRANSCRIPT" << 'EOF'
{"type":"user","message":{"content":"àáâãäèéêëìíîïòóôõöùúûüç payload"},"session_id":"S001"}
{"type":"assistant","message":{"content":"Segunda linha para testar JSON parse"},"session_id":"S001"}
EOF

FIRST_LINE_BYTES=$(head -1 "$TRANSCRIPT" | wc -c)
FIRST_LINE_BYTES=$((FIRST_LINE_BYTES - 1))  # remove newline
OFFSET_BYTES=$((FIRST_LINE_BYTES + 1))

echo "[3] Tamanho primeira linha: $FIRST_LINE_BYTES bytes, offset: $OFFSET_BYTES bytes"

# Gravar offset no banco
echo "[4] Gravar offset no banco..."
export TEMP_DIR DB OFFSET_BYTES TRANSCRIPT
node << 'NODEJS'
const fs = require('fs');
const { DatabaseSync } = require('node:sqlite');

const db = new DatabaseSync(process.env.DB);
const offset = parseInt(process.env.OFFSET_BYTES);

const stmt = db.prepare(`
  INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em)
  VALUES (?, ?, ?, ?, 0, ?)
  ON CONFLICT(projeto, sessao) DO UPDATE SET offset = excluded.offset, processada_em = excluded.processada_em
`);
stmt.run('teste', 'S001', process.env.TRANSCRIPT, offset, new Date().toISOString());
db.close();
NODEJS

# Testar código NOVO
echo "[5] Testando código NOVO (Buffer.toString byte-aware)..."
RESULT_NEW=1
export TEMP_DIR DB OFFSET_BYTES TRANSCRIPT
RESULT_NEW=$(node << 'NODEJS'
const fs = require('fs');

const offset = parseInt(process.env.OFFSET_BYTES);
const buffer = fs.readFileSync(process.env.TRANSCRIPT);
const conteudo = buffer.toString('utf8', offset);

let eventos = 0;
for (const linha of conteudo.split('\n').filter(l => l.trim())) {
  try {
    JSON.parse(linha);
    eventos++;
  } catch { }
}

process.stdout.write(String(eventos > 0 ? 0 : 1));
process.exit(0);
NODEJS
)

# Testar código ANTIGO
echo "[6] Testando código ANTIGO (substring char-based)..."
RESULT_OLD=1
export TEMP_DIR DB OFFSET_BYTES TRANSCRIPT
RESULT_OLD=$(node << 'NODEJS'
const fs = require('fs');

const offset = parseInt(process.env.OFFSET_BYTES);
const conteudo = fs.readFileSync(process.env.TRANSCRIPT, 'utf8');
const textoAposOffset = conteudo.substring(offset);  // ERRO: char-based, não byte

let eventos = 0;
for (const linha of textoAposOffset.split('\n').filter(l => l.trim())) {
  try {
    JSON.parse(linha);
    eventos++;
  } catch { }
}

process.stdout.write(String(eventos > 0 ? 0 : 1));
process.exit(0);
NODEJS
)

echo ""
echo "[7] Resultados:"
echo "   Código ANTIGO (substring):      exit=$RESULT_OLD (esperado 1 = falha)"
echo "   Código NOVO (Buffer.toString):  exit=$RESULT_NEW (esperado 0 = sucesso)"

if [ "$RESULT_OLD" != "0" ] && [ "$RESULT_NEW" = "0" ]; then
  echo "✅ Tarefa 19 PASSOU"
  exit 0
else
  echo "❌ Tarefa 19 FALHOU"
  exit 1
fi
