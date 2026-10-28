#!/usr/bin/env node
/**
 * Bateria do gate-pergunta-memoria.cjs (Stop, D6 do plano 2026-10-28-colheita-observacoes).
 *
 * Processo real do hook, payload real de Stop (session_id, transcript_path, cwd,
 * hook_event_name, stop_hook_active). Cada caso monta um mkdtemp com o transcrito e a
 * pasta memory/ do fixture, e um RFM_ROOT com sessoes.json de duas sessões vivas: uma
 * do mesmo repositório do cwd e uma de outro.
 *
 *   P1 memoria-responde.jsonl: exit 2; stderr traz Q1, o arquivo, a description e a sessão do OUTRO repo
 *   P2 o mesmo texto com marcador **Q2 -**: exit 2 e Q2 no stderr
 *   P3 memoria-nao-responde.jsonl: exit 0
 *   P4 o texto do P1 sem nenhum Q<n>: exit 0
 *   P5 P1 com stop_hook_active: exit 0
 *   P6 P1 com agent_id: exit 0
 *   P7 P1 sem pasta memory/: exit 0
 *   P8 P1 com .rainforest/config.json do cwd com gate-pergunta-memoria false: exit 0
 *   P9 transcript_path inexistente: exit 0
 *
 * Os exit 0 de P5 a P9 são contrastados com o P1 do mesmo jeito: a mesma montagem, só
 * a condição muda, então um exit 0 sem o mecanismo não passa por acidente.
 *
 * Uso: node hooks/testa-gate-pergunta-memoria.cjs   (exit 1 se alguma falhar)
 */

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');

const HOOK = path.join(__dirname, 'gate-pergunta-memoria.cjs');
const FIX = path.join(__dirname, 'fixtures', 'pergunta-memoria');
const DESCRICAO = 'desligar gate é RAINFOREST_GATE_OFF/config; arquivo .rainforest-gate-off não, por causa de repo de cliente';

const tmpdirs = [];
let ok = 0;
let falhou = 0;

function novoTmp(prefixo) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), prefixo));
  tmpdirs.push(d);
  return d;
}

function lerFixture(nome) {
  return fs.readFileSync(path.join(FIX, nome), 'utf8');
}

// Troca um trecho do transcrito com asserção de contagem: se o trecho não estiver
// exatamente uma vez no fixture, o caso não é o que diz ser, e o teste cai.
function trocar(texto, de, para) {
  const n = texto.split(de).length - 1;
  if (n !== 1) throw new Error(`trecho a trocar apareceu ${n} vezes (esperava 1): ${de}`);
  return texto.replace(de, () => para);
}

const TRECHO_Q1 = '**Q1 — Desligar o gate**:';

// Monta o cenário: transcrito (texto), memoria (copia pasta memory/?), projeto com config opcional.
function cenario({ transcrito, comMemoria = true, configProjeto = null, sessao = 'sess-atual' }) {
  const base = novoTmp('rfm-pergunta-base-');
  const proj = path.join(base, 'proj');
  const outro = path.join(base, 'outro-repo');
  fs.mkdirSync(proj, { recursive: true });
  fs.mkdirSync(outro, { recursive: true });

  const transcriptPath = path.join(proj, `${sessao}.jsonl`);
  fs.writeFileSync(transcriptPath, transcrito);

  if (comMemoria) {
    const memDst = path.join(proj, 'memory');
    fs.mkdirSync(memDst, { recursive: true });
    fs.copyFileSync(path.join(FIX, 'memory', 'gate-off-so-por-variavel.md'), path.join(memDst, 'gate-off-so-por-variavel.md'));
  }

  if (configProjeto) {
    fs.mkdirSync(path.join(proj, '.rainforest'), { recursive: true });
    fs.writeFileSync(path.join(proj, '.rainforest', 'config.json'), JSON.stringify(configProjeto));
  }

  // RFM_ROOT com sessoes vivas: pid = o desta bateria, que está de pé enquanto ela roda.
  const rfm = novoTmp('rfm-pergunta-raiz-');
  const agora = Date.now();
  const estado = {
    'sess-mesmo-repo': { cwd: proj, prompt_ts: agora - 60000, stop_ts: agora - 30000, pid: process.pid },
    'sess-outro-repo': { cwd: outro, prompt_ts: agora - 120000, stop_ts: agora - 60000, pid: process.pid },
  };
  fs.writeFileSync(path.join(rfm, 'sessoes.json'), JSON.stringify(estado));

  return { proj, outro, transcriptPath, rfm };
}

function payload(c, extra = {}) {
  return {
    session_id: 'sess-atual',
    transcript_path: c.transcriptPath,
    cwd: c.proj,
    hook_event_name: 'Stop',
    ...extra,
  };
}

function rodar(c, extra = {}, transcriptOverride = null) {
  const p = payload(c, extra);
  if (transcriptOverride !== null) p.transcript_path = transcriptOverride;
  const env = { ...process.env, RFM_ROOT: c.rfm };
  delete env.RAINFOREST_GATE_OFF;
  delete env.CLAUDE_PROJECT_DIR;
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(p),
    encoding: 'utf8',
    env,
    timeout: 30000,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function teste(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`  ok   ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`  FALHA ${nome}: ${e.message}`);
  }
}

const TRANSCRITO_RESPONDE = lerFixture('memoria-responde.jsonl');
const TRANSCRITO_NAO_RESPONDE = lerFixture('memoria-nao-responde.jsonl');

teste('P1 memoria-responde: exit 2, Q1, o arquivo, a description e a sessão do outro repo (não a do mesmo)', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE });
  const r = rodar(c);
  assert(r.status === 2, `esperado exit 2, obteve ${r.status} (stderr: ${r.stderr})`);
  assert(r.stderr.includes('Q1'), 'stderr sem Q1');
  assert(r.stderr.includes('gate-off-so-por-variavel.md'), 'stderr sem o nome do arquivo de memória');
  assert(r.stderr.includes(DESCRICAO), 'stderr sem a description');
  assert(r.stderr.includes(c.outro), 'stderr sem a sessão do outro repositório');
  assert(!r.stderr.includes(c.proj), 'stderr traz a sessão do MESMO repositório');
});

teste('P2 marcador **Q2 -** (hífen): exit 2 e Q2 no stderr', () => {
  const texto = trocar(TRANSCRITO_RESPONDE, TRECHO_Q1, '**Q2 -** Desligar o gate:');
  const c = cenario({ transcrito: texto });
  const r = rodar(c);
  assert(r.status === 2, `esperado exit 2, obteve ${r.status} (stderr: ${r.stderr})`);
  assert(r.stderr.includes('Q2'), 'stderr sem Q2');
});

teste('P3 memoria-nao-responde: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_NAO_RESPONDE });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P4 o texto do P1 sem nenhum Q<n>: exit 0', () => {
  const texto = trocar(TRANSCRITO_RESPONDE, TRECHO_Q1, '**Desligar o gate**:');
  assert(!/\bQ\d+\b/.test(texto), 'o fixture sem Q ainda tem Q<n>');
  const c = cenario({ transcrito: texto });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P5 P1 com stop_hook_active: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE });
  const r = rodar(c, { stop_hook_active: true });
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P6 P1 com agent_id: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE });
  const r = rodar(c, { agent_id: 'agent-123' });
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P7 P1 sem pasta memory/: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE, comMemoria: false });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P8 P1 com .rainforest/config.json do cwd: gate-pergunta-memoria false: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE, configProjeto: { 'gate-pergunta-memoria': false } });
  const r = rodar(c);
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

teste('P9 transcript_path inexistente: exit 0', () => {
  const c = cenario({ transcrito: TRANSCRITO_RESPONDE });
  const r = rodar(c, {}, path.join(c.proj, 'nao-existe.jsonl'));
  assert(r.status === 0, `esperado exit 0, obteve ${r.status} (stderr: ${r.stderr})`);
});

for (const d of tmpdirs) {
  try { fs.rmSync(d, { recursive: true, force: true }); } catch { /* melhor esforço */ }
}

console.log(`\nok: ${ok}   falhou: ${falhou}   skipped: 0`);
process.exit(falhou > 0 ? 1 : 0);
