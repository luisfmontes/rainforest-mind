#!/bin/bash
set -u

# Teste ponta a ponta com LLM de verdade
RAIZ="$(mktemp -d)"
trap 'rm -rf "$RAIZ"' EXIT

export RFM_ROOT="$RAIZ/rainforest"
mkdir -p "$RFM_ROOT/projects/teste-p2p"

# Inicializar banco
node scripts/memoria.cjs iniciar >/dev/null 2>&1

# Criar transcrito
TRANSCRITO="$RFM_ROOT/projects/teste-p2p/sessao.jsonl"
cat > "$TRANSCRITO" <<'EOF'
{"type":"user","message":{"role":"user","content":"Qual é o capital da França?"},"timestamp":"2026-08-20T10:00:00Z","sessionId":"sessao","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"O capital é Paris"}]},"timestamp":"2026-08-20T10:00:01Z","sessionId":"sessao","version":"2.1.0","cwd":"test"}
EOF

# Criar marca
node <<'CRIA' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em) VALUES (?, ?, ?, ?, ?)');
const caminhoTranscrito = path.join(process.env.RFM_ROOT, 'projects', 'teste-p2p', 'sessao.jsonl');
stmt.run('teste-p2p', 'sessao', caminhoTranscrito, 0, new Date().toISOString());
db.close();
console.log('marca criada');
CRIA

# Chamar observador SEM dublê
echo "Chamando observador com LLM de verdade:"
unset TESTADOR_CHAMAR_LLM
node scripts/observar.cjs --sessao sessao --projeto teste-p2p 2>&1 | head -20

# Verificar
echo ""
echo "Verificando observação no banco:"
node <<'LEI' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const rows = db.prepare('SELECT projeto, conteudo FROM observacoes WHERE projeto = ? LIMIT 1').all('teste-p2p');
if (rows.length > 0) {
  console.log('✓ Observação gravada:');
  console.log('  projeto:', rows[0].projeto);
  console.log('  conteudo:', rows[0].conteudo);
} else {
  console.log('✗ Nenhuma observação foi gravada');
}
db.close();
LEI
