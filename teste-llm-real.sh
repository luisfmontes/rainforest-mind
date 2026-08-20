#!/bin/bash
# Teste ponta a ponta com LLM de verdade
set -u

CAIXA_TESTE="$(mktemp -d)"
trap 'rm -rf "$CAIXA_TESTE"' EXIT

export RFM_ROOT="$CAIXA_TESTE/rainforest"
export CLAUDE_CONFIG_DIR="$CAIXA_TESTE"
mkdir -p "$RFM_ROOT/projects/teste-llm-real"

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SRC"

# Inicializar banco
node scripts/memoria.cjs iniciar >/dev/null 2>&1

# Criar transcrito pequeno
TRANSCRITO="$RFM_ROOT/projects/teste-llm-real/sessao.jsonl"
cat > "$TRANSCRITO" <<'EOF'
{"type":"user","message":{"role":"user","content":"Qual é o capital da França?"},"timestamp":"2026-08-20T10:00:00Z","sessionId":"sessao-real","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"O capital da França é Paris"}]},"timestamp":"2026-08-20T10:00:01Z","sessionId":"sessao-real","version":"2.1.0","cwd":"test"}
EOF

# Gravar marca d'água
node <<CRIA_MARCA 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em) VALUES (?, ?, ?, ?, ?)');
const caminhoTranscrito = path.join(process.env.RFM_ROOT, 'projects', 'teste-llm-real', 'sessao.jsonl');
stmt.run('teste-llm-real', 'sessao-real', caminhoTranscrito, 0, new Date().toISOString());
db.close();
console.log('marca criada');
CRIA_MARCA

# Chamar observador SEM dublê (usa LLM de verdade)
echo "=== Chamando observador com LLM de verdade ==="
unset TESTADOR_CHAMAR_LLM
node scripts/observar.cjs --sessao sessao-real --projeto teste-llm-real 2>&1
EXIT_CODE=$?
echo "Exit code: $EXIT_CODE"

# Verificar observação gravada
echo ""
echo "=== Verificando observação no banco ==="
node <<LEI 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT projeto, conteudo FROM observacoes WHERE projeto = ? LIMIT 1');
const rows = stmt.all('teste-llm-real');
if (rows.length > 0) {
  console.log('Observação encontrada:');
  console.log('  projeto:', rows[0].projeto);
  console.log('  conteudo:', rows[0].conteudo);
} else {
  console.log('Nenhuma observação foi gravada');
}
db.close();
LEI
