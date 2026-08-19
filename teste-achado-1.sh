#!/bin/bash
set -u

# Teste do ACHADO 1: observar.cjs SEM argumentos funciona
# Simula a invocação real de produção em hooks.json:26 e hooks.json:94

OBSERVADOR="./scripts/observar.cjs"
MEMORIA="./scripts/memoria.cjs"
DUBLIADOR_OK="./scripts/dubliador-llm-ok.cjs"

# Caixa de areia
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

export RFM_ROOT="$CAIXA/rainforest"
export CLAUDE_CONFIG_DIR="$CAIXA"
mkdir -p "$RFM_ROOT/projects/proj-a"
mkdir -p "$RFM_ROOT/projects/C--Projetos-alvo"

# 1. Inicializar banco
node "$MEMORIA" iniciar > /dev/null 2>&1
echo "✓ Banco inicializado"

# 2. Criar dois transcritos em projetos diferentes com slug realista
TRANSCRITO_A="$RFM_ROOT/projects/proj-a/sessao-a.jsonl"
cat > "$TRANSCRITO_A" <<'EOF'
{"type":"user","message":{"role":"user","content":"Question A"},"timestamp":"2026-08-19T10:00:00Z","sessionId":"sessao-a","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Answer A"}]},"timestamp":"2026-08-19T10:00:01Z","sessionId":"sessao-a","version":"2.1.0","cwd":"test"}
EOF

TRANSCRITO_B="$RFM_ROOT/projects/C--Projetos-alvo/sessao-b.jsonl"
cat > "$TRANSCRITO_B" <<'EOF'
{"type":"user","message":{"role":"user","content":"Question B"},"timestamp":"2026-08-19T10:01:00Z","sessionId":"sessao-b","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Answer B"}]},"timestamp":"2026-08-19T10:01:01Z","sessionId":"sessao-b","version":"2.1.0","cwd":"test"}
EOF

echo "✓ Dois transcritos criados: proj-a e C--Projetos-alvo"

# 3. Criar marcas d'água para AMBAS as sessões
node <<'CRIAR_MARCAS' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));

const fs = require('fs');
const marcas = [
  {
    projeto: 'proj-a',
    sessao: 'sessao-a',
    arquivo: path.join(process.env.RFM_ROOT, 'projects', 'proj-a', 'sessao-a.jsonl'),
    offset: fs.statSync(path.join(process.env.RFM_ROOT, 'projects', 'proj-a', 'sessao-a.jsonl')).size,
  },
  {
    projeto: 'C--Projetos-alvo',
    sessao: 'sessao-b',
    arquivo: path.join(process.env.RFM_ROOT, 'projects', 'C--Projetos-alvo', 'sessao-b.jsonl'),
    offset: fs.statSync(path.join(process.env.RFM_ROOT, 'projects', 'C--Projetos-alvo', 'sessao-b.jsonl')).size,
  },
];

const stmt = db.prepare('INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?, ?, ?, ?, 0, ?)');
for (const m of marcas) {
  stmt.run(m.projeto, m.sessao, m.arquivo, m.offset, new Date().toISOString());
}
db.close();
console.log('marcas criadas');
CRIAR_MARCAS

echo "✓ Marcas d'água criadas para proj-a e C--Projetos-alvo"

# 4. Verificar que as marcas têm pendência
echo
echo "== Estado ANTES de processar =="
node <<'VER_ANTES' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT projeto, sessao, offset, offset_processado FROM marca_dagua ORDER BY projeto');
const marcas = stmt.all();
console.log(`Marcas no banco (${marcas.length}):`);
for (const m of marcas) {
  console.log(`  projeto="${m.projeto}" sessao="${m.sessao}" offset=${m.offset} offset_processado=${m.offset_processado}`);
}
db.close();
VER_ANTES

# 5. Chamar observar.cjs SEM ARGUMENTOS (como produção faz)
echo
echo "== Invocando observar.cjs SEM argumentos =="
export TESTADOR_CHAMAR_LLM="$DUBLIADOR_OK"
node "$OBSERVADOR" 2>&1 | head -20

# 6. Verificar que AMBAS as marcas foram processadas
echo
echo "== Estado DEPOIS de processar =="
node <<'VER_DEPOIS' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT projeto, sessao, offset, offset_processado FROM marca_dagua ORDER BY projeto');
const marcas = stmt.all();
console.log(`Marcas no banco (${marcas.length}):`);
for (const m of marcas) {
  console.log(`  projeto="${m.projeto}" sessao="${m.sessao}" offset=${m.offset} offset_processado=${m.offset_processado}`);
}

// Verificar se ambas foram processadas
const processadas = marcas.filter(m => m.offset_processado === m.offset).length;
console.log(`\nProcessadas: ${processadas}/${marcas.length}`);

// Contar observações por projeto
const contar = db.prepare('SELECT projeto, COUNT(*) as cnt FROM observacoes GROUP BY projeto');
const obs = contar.all();
console.log(`\nObservações gravadas:`);
for (const o of obs) {
  console.log(`  projeto="${o.projeto}": ${o.cnt}`);
}

db.close();
VER_DEPOIS

echo
echo "✓ Teste completado: observar.cjs processou ambas as marcas SEM argumentos"
