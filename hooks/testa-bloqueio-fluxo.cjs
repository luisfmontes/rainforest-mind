#!/usr/bin/env node
/**
 * Bateria do bloqueio de edição sem fluxo e sem caminho leve (#430, design
 * docs/rainforest/design/2026-10-08-fluxo-pulado-bloqueio.md, D1, D2, D4, D8, D9).
 *
 * Cada caso cria um repositório git real em sandbox, monta o payload do PreToolUse
 * como o harness manda (session_id, cwd, hook_event_name, tool_name, tool_input, e
 * agent_id só nos casos de subagente) e roda o hook de verdade pelo stdin. O `leve`
 * é gravado pelo scripts/estado.cjs real, não por fixture.
 *
 * Toda asserção tem os dois ramos: `bloqueado` confere exit 2 e o trecho esperado
 * no stderr; `passa` confere exit 0 com saída vazia. Nenhum caso confere só um lado.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const HOOK = path.join(__dirname, 'aviso-fluxo.cjs');
const ESTADO = path.resolve(__dirname, '..', 'scripts', 'estado.cjs');
const ESTADO_BARRAS = ESTADO.split(path.sep).join('/');

// ============================================================================
// SANDBOX
// ============================================================================

function git(cwd, args) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8', stdio: 'pipe' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} saiu ${r.status}: ${r.stderr}`);
  return r.stdout;
}

function criarSandbox() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bloqueio-fluxo-'));
  git(dir, ['init', '-q']);
  git(dir, ['config', 'user.email', 't@t']);
  git(dir, ['config', 'user.name', 't']);
  git(dir, ['config', 'commit.gpgsign', 'false']);
  git(dir, ['checkout', '-q', '-b', 'main']);
  fs.writeFileSync(path.join(dir, 'README.md'), 'test\n');
  git(dir, ['add', 'README.md']);
  git(dir, ['commit', '-q', '-m', 'init']);
  return dir;
}

function limparSandbox(dir) {
  if (process.platform === 'win32') {
    spawnSync('cmd', ['/d', '/c', 'rmdir', '/s', '/q', dir], { stdio: 'ignore' });
  } else {
    spawnSync('rm', ['-rf', dir], { stdio: 'ignore' });
  }
}

function branch(sandbox, nome) {
  git(sandbox, ['checkout', '-q', '-b', nome]);
}

function criarDirEstado(sandbox) {
  fs.mkdirSync(path.join(sandbox, 'docs', 'rainforest', 'estado'), { recursive: true });
}

function gravarEstado(sandbox, nomeArquivo, conteudo) {
  const dir = path.join(sandbox, 'docs', 'rainforest', 'estado');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${nomeArquivo}.json`), JSON.stringify(conteudo, null, 2) + '\n');
}

function estadoAberto(slug) {
  return {
    slug,
    titulo: slug,
    criado_em: '2026-01-01',
    arqueologia: { status: 'pendente' },
    design: { status: 'pendente' },
    plano: { status: 'pendente' },
    executar: { status: 'pendente' },
    revisar: { status: 'pendente' },
    verificar: { status: 'pendente' },
    fechar: { status: 'pendente' },
  };
}

function criarGates(sandbox, horasAtras) {
  const dir = path.join(sandbox, 'docs', 'plans');
  fs.mkdirSync(dir, { recursive: true });
  const arq = path.join(dir, 'x.gates.json');
  fs.writeFileSync(arq, JSON.stringify({ gates: [] }, null, 2) + '\n');
  const t = (Date.now() - horasAtras * 3600 * 1000) / 1000;
  fs.utimesSync(arq, t, t);
}

function desligarAvisoFluxo(sandbox) {
  fs.mkdirSync(path.join(sandbox, '.rainforest'), { recursive: true });
  fs.writeFileSync(path.join(sandbox, '.rainforest', 'config.json'), JSON.stringify({ 'aviso-fluxo': false }));
}

function escreverCodigo(sandbox, relativo) {
  const arq = path.join(sandbox, relativo);
  fs.mkdirSync(path.dirname(arq), { recursive: true });
  fs.writeFileSync(arq, 'console.log("test");\n');
  return arq;
}

// ============================================================================
// HOOK, ESTADO E PAYLOAD
// ============================================================================

// Roda o hook como o harness: JSON no stdin. Ambiente isolado do config do usuário.
function rodarHook(entrada, cwd) {
  const input = typeof entrada === 'string' ? entrada : JSON.stringify(entrada);
  const r = spawnSync(process.execPath, [HOOK], {
    input,
    encoding: 'utf8',
    cwd,
    env: { ...process.env, CLAUDE_PROJECT_DIR: cwd, RFM_ROOT: path.join(cwd, '.dados-teste') },
  });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

// O scripts/estado.cjs real, com a raiz fixada no sandbox.
function estado(args, cwd) {
  const r = spawnSync(process.execPath, [ESTADO, ...args], {
    cwd,
    encoding: 'utf8',
    env: { ...process.env, RFM_ESTADO_ROOT: cwd, CLAUDE_PROJECT_DIR: cwd },
  });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

function payload({ cwd, file, tool = 'Edit', sessao = 'sess-bloqueio', agente = null }) {
  let tool_input;
  if (tool === 'Write') {
    tool_input = { file_path: file, content: 'x\n' };
  } else if (tool === 'MultiEdit') {
    tool_input = { file_path: file, edits: [{ old_string: 'a', new_string: 'b' }] };
  } else {
    tool_input = { file_path: file, old_string: 'a', new_string: 'b' };
  }
  const p = { session_id: sessao, cwd, hook_event_name: 'PreToolUse', tool_name: tool, tool_input };
  if (agente) p.agent_id = agente;
  return p;
}

// ============================================================================
// ASSERÇÕES: os dois ramos
// ============================================================================

function bloqueado(r, trechos = []) {
  if (r.status !== 2) return `esperado exit 2, obtido ${r.status}; stdout=${r.stdout} stderr=${r.stderr}`;
  for (const t of trechos) {
    if (!r.stderr.includes(t)) return `stderr sem "${t}": ${r.stderr}`;
  }
  return null;
}

function passa(r) {
  if (r.status !== 0) return `esperado exit 0, obtido ${r.status}; stderr=${r.stderr}`;
  if (r.stdout !== '' || r.stderr !== '') return `esperado saida vazia; stdout=${r.stdout} stderr=${r.stderr}`;
  return null;
}

// ============================================================================
// CASOS
// ============================================================================

const casos = [];
function caso(nome, fn) {
  casos.push([nome, fn]);
}

caso('rainforest sem fluxo: Edit de .cjs sai 2 na primeira edicao', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    return bloqueado(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('rainforest sem fluxo: Edit de .cjs sai 2 de novo na segunda edicao da mesma sessao', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    const p = payload({ cwd: s, file: arq, sessao: 'sess-dupla' });
    const primeira = bloqueado(rodarHook(p, s));
    if (primeira) return `primeira edicao: ${primeira}`;
    return bloqueado(rodarHook(p, s));
  } finally { limparSandbox(s); }
});

caso('rainforest sem fluxo: a mensagem nomeia as duas saidas com comando pronto', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    return bloqueado(rodarHook(payload({ cwd: s, file: arq }), s), [
      `${ESTADO_BARRAS} iniciar`,
      '/rainforest-mind:brainstorm',
      `${ESTADO_BARRAS} leve --motivo`,
    ]);
  } finally { limparSandbox(s); }
});

caso('depois de estado.cjs leve --motivo na branch, Edit de .cjs passa', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    const leve = estado(['leve', '--motivo', 'hotfix mecanico'], s);
    if (leve.status !== 0) return `leve saiu ${leve.status}: ${leve.stderr}`;
    if (!leve.stdout.includes("leve: 'fluxo/x' registrado")) return `leve sem confirmacao: ${leve.stdout}`;
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    return passa(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('o leve da branch fluxo/x nao libera a branch fluxo/y', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    const leve = estado(['leve', '--motivo', 'hotfix mecanico'], s);
    if (leve.status !== 0) return `leve saiu ${leve.status}: ${leve.stderr}`;
    branch(s, 'fluxo/y');
    const arq = escreverCodigo(s, 'scripts/y.cjs');
    return bloqueado(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('registro leve gravado a mao com motivo vazio nao libera a branch', () => {
  const s = criarSandbox();
  try {
    gravarEstado(s, '2026-10-08-w', { slug: '2026-10-08-w', titulo: 'w', leve: { motivo: '', data: '2026-10-08' } });
    branch(s, 'fluxo/w');
    const arq = escreverCodigo(s, 'scripts/w.cjs');
    return bloqueado(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('fluxo aberto na branch: Edit de .cjs passa', () => {
  const s = criarSandbox();
  try {
    gravarEstado(s, '2026-01-01-w', estadoAberto('2026-01-01-w'));
    branch(s, 'fluxo/w');
    const arq = escreverCodigo(s, 'scripts/w.cjs');
    return passa(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('payload com agent_id (subagente) passa: a portaria barra o despacho, nao o Edit', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    return passa(rodarHook(payload({ cwd: s, file: arq, agente: 'subagent-123' }), s));
  } finally { limparSandbox(s); }
});

caso('Edit de README.md passa mesmo sem fluxo', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    return passa(rodarHook(payload({ cwd: s, file: path.join(s, 'README.md') }), s));
  } finally { limparSandbox(s); }
});

caso('Edit de docs/x.cjs passa mesmo sem fluxo', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    const arq = escreverCodigo(s, 'docs/x.cjs');
    return passa(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('chave aviso-fluxo desligada no config: Edit de .cjs passa', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    desligarAvisoFluxo(s);
    branch(s, 'fluxo/x');
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    return passa(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('repositorio sem fluxo nenhum: Edit de .cjs passa', () => {
  const s = criarSandbox();
  try {
    branch(s, 'fluxo/x');
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    return passa(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('payload vazio passa', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    return passa(rodarHook({}, s));
  } finally { limparSandbox(s); }
});

caso('payload ilegivel passa', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    return passa(rodarHook('isto nao e json', s));
  } finally { limparSandbox(s); }
});

caso('protheus sem fluxo: sai 2 nomeando /protheus:trabalhar e o leve', () => {
  const s = criarSandbox();
  try {
    criarGates(s, 48);
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    return bloqueado(rodarHook(payload({ cwd: s, file: arq }), s), [
      '/protheus:trabalhar',
      `${ESTADO_BARRAS} leve --motivo`,
    ]);
  } finally { limparSandbox(s); }
});

caso('protheus: .gates.json com menos de 24 h e fluxo aberto, passa', () => {
  const s = criarSandbox();
  try {
    criarGates(s, 1);
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    return passa(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('protheus: estado.cjs leve libera a branch, sem fluxo aberto', () => {
  const s = criarSandbox();
  try {
    criarGates(s, 48);
    branch(s, 'fluxo/p');
    const leve = estado(['leve', '--motivo', 'hotfix mecanico'], s);
    if (leve.status !== 0) return `leve saiu ${leve.status}: ${leve.stderr}`;
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    return passa(rodarHook(payload({ cwd: s, file: arq }), s));
  } finally { limparSandbox(s); }
});

caso('Write e MultiEdit no mesmo arquivo continuam bloqueados', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    const arq = escreverCodigo(s, 'scripts/x.cjs');
    const w = bloqueado(rodarHook(payload({ cwd: s, file: arq, tool: 'Write' }), s));
    if (w) return `Write: ${w}`;
    return bloqueado(rodarHook(payload({ cwd: s, file: arq, tool: 'MultiEdit' }), s));
  } finally { limparSandbox(s); }
});

caso('file_path relativo ao cwd continua bloqueado', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    escreverCodigo(s, 'scripts/x.cjs');
    return bloqueado(rodarHook(payload({ cwd: s, file: 'scripts/x.cjs' }), s));
  } finally { limparSandbox(s); }
});

caso('cwd num subdiretorio do repo continua bloqueado', () => {
  const s = criarSandbox();
  try {
    criarDirEstado(s);
    branch(s, 'fluxo/x');
    const sub = path.join(s, 'sub', 'dir');
    fs.mkdirSync(sub, { recursive: true });
    escreverCodigo(s, 'sub/dir/x.cjs');
    return bloqueado(rodarHook(payload({ cwd: sub, file: 'x.cjs' }), sub));
  } finally { limparSandbox(s); }
});

// ============================================================================
// EXECUÇÃO
// ============================================================================

let ok = 0;
let falhou = 0;
for (const [nome, fn] of casos) {
  let erro = null;
  try {
    erro = fn();
  } catch (e) {
    erro = `excecao: ${e.message}`;
  }
  if (erro) {
    falhou++;
    console.log(`falhou: ${nome}`);
    console.log(`  ${erro}`);
  } else {
    ok++;
    console.log(`ok: ${nome}`);
  }
}

console.log('');
console.log(`ok: ${ok}   falhou: ${falhou}   skipped: 0`);
process.exit(falhou === 0 ? 0 : 1);
