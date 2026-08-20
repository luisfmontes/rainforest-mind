#!/usr/bin/env node
// Teste ponta a ponta com LLM de verdade - versão simplificada
const path = require('path');
const fs = require('fs');
const os = require('os');

// Setup
const CAIXA_TESTE = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-test-'));
process.env.RFM_ROOT = path.join(CAIXA_TESTE, 'rainforest');
process.env.CLAUDE_CONFIG_DIR = CAIXA_TESTE;

// Cleanup ao sair
process.on('exit', () => {
  try {
    require('child_process').execSync(`rm -rf "${CAIXA_TESTE}"`);
  } catch (e) {}
});

const { abrirBanco } = require('./scripts/memoria.cjs');
const { execSync } = require('child_process');

// Criar diretórios e banco
const rfmRoot = process.env.RFM_ROOT;
fs.mkdirSync(path.join(rfmRoot, 'projects', 'teste-llm-real'), { recursive: true });

// Inicializar banco
const memoriaPath = path.join(__dirname, 'scripts', 'memoria.cjs');
const iniciarScript = `const mem = require('${memoriaPath}'); mem.criarSchema(mem.abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db')));`;
const result = require('child_process').execSync(`node -e "${iniciarScript.replace(/"/g, '\\"')}"`, {
  env: process.env,
  stdio: 'pipe'
}).toString();

// Criar transcrito
const TRANSCRITO = path.join(rfmRoot, 'projects', 'teste-llm-real', 'sessao.jsonl');
const conteudo = `{"type":"user","message":{"role":"user","content":"Qual é o capital da França?"},"timestamp":"2026-08-20T10:00:00Z","sessionId":"sessao-real","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"O capital da França é Paris"}]},"timestamp":"2026-08-20T10:00:01Z","sessionId":"sessao-real","version":"2.1.0","cwd":"test"}`;

fs.writeFileSync(TRANSCRITO, conteudo);

// Criar marca
const db = abrirBanco(path.join(rfmRoot, 'rainforest.db'));
const stmt = db.prepare('INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em) VALUES (?, ?, ?, ?, ?)');
stmt.run('teste-llm-real', 'sessao-real', TRANSCRITO, 0, new Date().toISOString());
db.close();

console.log('=== Setup completo, disparando observador com LLM de verdade ===');

// Disparar observador (SEM dublê)
delete process.env.TESTADOR_CHAMAR_LLM;
const observadorPath = path.join(__dirname, 'scripts', 'observar.cjs');
const { processarSessao } = require(observadorPath);

processarSessao('sessao-real', 'teste-llm-real').then(() => {
  console.log('\n=== Verificando observação no banco ===');
  const db2 = abrirBanco(path.join(rfmRoot, 'rainforest.db'));
  const rows = db2.prepare('SELECT projeto, conteudo FROM observacoes WHERE projeto = ? LIMIT 1').all('teste-llm-real');
  if (rows.length > 0) {
    console.log('✓ Observação encontrada:');
    console.log('  projeto:', rows[0].projeto);
    console.log('  conteudo:', rows[0].conteudo.substring(0, 100) + (rows[0].conteudo.length > 100 ? '...' : ''));
  } else {
    console.log('✗ Nenhuma observação foi gravada');
  }
  db2.close();
});
