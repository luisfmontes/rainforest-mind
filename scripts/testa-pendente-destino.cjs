#!/usr/bin/env node
'use strict';
/**
 * Bateria da pendencia com destino (#449).
 *
 * Roda o `scripts/estado.cjs` do repositorio numa caixa `mkdtemp`: RFM_ESTADO_ROOT e
 * RFM_ROOT apontam para a caixa, entao nada toca ~/.rainforest nem o estado do
 * repositorio. `spawnSync` com vetor de argumentos: o `--json` com aspas e acento
 * chega intacto (o `bash` comeria contrabarra). Cada caso usa um slug proprio.
 *
 * Prova o EFEITO (exit code, stderr e o arquivo de estado), nunca le o fonte.
 * Fixtures sem nome real: textos genericos, repositorio `alfa/beta`.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const SRC = path.resolve(__dirname, '..');
const ESTADO = path.join(SRC, 'scripts', 'estado.cjs');

let ok = 0;
let falhou = 0;
function caso(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`ok  ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`FALHOU  ${nome}\n  ${String(e.message).split('\n')[0]}`);
  }
}

const A = 'tarefa-3: worktree nao respondeu';
const B = 'tarefa-6: falta rodar';
const C = 'tarefa-9: revisar o rotulo';
const EVIDENCIA_OK = { comando: 'c', saida: 's', mutacao: [{ tarefa: 1, resultado: 'n/a', motivo: 'm' }] };

// ---------------------------------------------------------------- caixa

function caixa() {
  const raiz = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'pendente-destino-')));
  fs.writeFileSync(path.join(raiz, 'FOCO.md'), '# foco\n', 'utf8');
  const env = { ...process.env };
  delete env.CLAUDE_PROJECT_DIR;
  delete env.CLAUDE_CODE_SESSION_ID;
  Object.assign(env, { RFM_ESTADO_ROOT: raiz, RFM_ROOT: raiz, HOME: raiz, USERPROFILE: raiz, CI: '1' });
  return { raiz, env };
}

function estado(cx, args) {
  const r = spawnSync(process.execPath, [ESTADO, ...args], { cwd: cx.raiz, env: cx.env, encoding: 'utf8' });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

function arquivoDe(cx, slug) {
  return path.join(cx.raiz, 'docs', 'rainforest', 'estado', `${slug}.json`);
}
function bytes(cx, slug) {
  return fs.readFileSync(arquivoDe(cx, slug), 'utf8');
}
function bloco(cx, slug, est) {
  return JSON.parse(bytes(cx, slug))[est];
}

let n = 0;
/** Abre um fluxo novo ate o `executar` armado (iniciar, design, plano, exigir executar). */
function abrir(cx) {
  n += 1;
  const slug = `caso-${n}`;
  const passos = [
    ['iniciar', '--slug', slug],
    ['marcar', '--slug', slug, '--estagio', 'design', '--status', 'aprovado'],
    ['marcar', '--slug', slug, '--estagio', 'plano', '--status', 'ok'],
    ['exigir', '--slug', slug, '--estagio', 'executar'],
  ];
  for (const p of passos) {
    const r = estado(cx, p);
    assert.strictEqual(r.status, 0, `abrir ${p[0]} saiu ${r.status}: ${r.stderr}`);
  }
  return slug;
}

function marcar(cx, slug, est, status, json) {
  const args = ['marcar', '--slug', slug, '--estagio', est, '--status', status];
  if (json !== undefined) args.push('--json', typeof json === 'string' ? json : JSON.stringify(json));
  return estado(cx, args);
}
const parcial = (cx, slug, json) => marcar(cx, slug, 'executar', 'parcial', json);
const fecharOk = (cx, slug, extra) => marcar(cx, slug, 'executar', 'ok', { ...EVIDENCIA_OK, ...(extra || {}) });

/** Recusa: exit 2, estado byte a byte igual, stderr cita todos os `cita`. */
function recusado(r, antes, depois, cita) {
  assert.strictEqual(r.status, 2, `esperava exit 2, veio ${r.status}\nstdout: ${r.stdout}\nstderr: ${r.stderr}`);
  assert.strictEqual(depois, antes, 'recusa nao pode gravar');
  for (const c of cita || []) assert.ok(r.stderr.includes(c), `stderr nao cita ${JSON.stringify(c)}: ${r.stderr}`);
}

const cx = caixa();

// ---------------------------------------------------------------- tarefa 1: validar `destinos`

function casoRecusa(nome, destinos, cita, extraJson) {
  caso(nome, () => {
    const slug = abrir(cx);
    const antes = bytes(cx, slug);
    const r = parcial(cx, slug, { pendentes: [A, B], destinos, ...(extraJson || {}) });
    recusado(r, antes, bytes(cx, slug), cita);
  });
}

casoRecusa('resolvida sem evidencia e recusada', [{ pendente: A, destino: 'resolvida' }], ['evidencia']);
casoRecusa('resolvida com evidencia so de espacos e recusada', [{ pendente: A, destino: 'resolvida', evidencia: '   ' }], ['evidencia']);
casoRecusa('descartada sem motivo e recusada', [{ pendente: A, destino: 'descartada' }], ['motivo']);
casoRecusa('plantada sem ref e recusada', [{ pendente: A, destino: 'plantada' }], ['ref']);
casoRecusa('plantada com ref que nao e issue nem ideia e recusada', [{ pendente: A, destino: 'plantada', ref: 'qualquer coisa' }], ['ref']);
for (const ref of ['#0', '#abc', '#12 x', 'https://github.com/alfa/beta/pull/3', 'https://github.com/alfa/beta/issues/',
  'http://github.com/alfa/beta/issues/3', 'ideia:Maiusculo', 'ideia:a--b']) {
  casoRecusa(`plantada com ref ${JSON.stringify(ref)} e recusada`, [{ pendente: A, destino: 'plantada', ref }], ['ref']);
}
casoRecusa('destino fora dos tres (adiada) e recusado', [{ pendente: A, destino: 'adiada', motivo: 'x' }], ['adiada']);
casoRecusa('item sem o campo destino e recusado', [{ pendente: A, motivo: 'x' }], ['destino']);
casoRecusa('pendente que nao casa com nenhuma pendencia e recusado', [{ pendente: 'texto que nao existe', destino: 'descartada', motivo: 'x' }], ['texto que nao existe']);
casoRecusa('destinos que e objeto e nao lista e recusado', { pendente: A, destino: 'descartada', motivo: 'x' }, ['destinos']);

caso('pendentes que e texto e nao lista e recusado', () => {
  const slug = abrir(cx);
  const antes = bytes(cx, slug);
  const r = parcial(cx, slug, { pendentes: 'texto solto' });
  recusado(r, antes, bytes(cx, slug), ['pendentes']);
});
caso('pendentes com um item que e numero e recusado', () => {
  const slug = abrir(cx);
  const antes = bytes(cx, slug);
  const r = parcial(cx, slug, { pendentes: [A, 7] });
  recusado(r, antes, bytes(cx, slug), ['pendentes']);
});

function casoAceito(nome, destino) {
  caso(nome, () => {
    const slug = abrir(cx);
    const r = parcial(cx, slug, { pendentes: [A, B], destinos: [{ pendente: A, ...destino }] });
    assert.strictEqual(r.status, 0, `esperava exit 0, veio ${r.status}: ${r.stderr}`);
  });
}
casoAceito('plantada com #449 e aceita', { destino: 'plantada', ref: '#449' });
casoAceito('plantada com URL de issue e aceita', { destino: 'plantada', ref: 'https://github.com/alfa/beta/issues/449' });
casoAceito('plantada com ideia:<id> e aceita', { destino: 'plantada', ref: 'ideia:regua-d7-memoria-por-assunto' });
casoAceito('resolvida com evidencia e aceita', { destino: 'resolvida', evidencia: 'rodou: 6 de 6 ok' });
casoAceito('descartada com motivo e aceita', { destino: 'descartada', motivo: 'fora do escopo' });

caso('destino aceito fica no bloco executar', () => {
  const slug = abrir(cx);
  const d = { pendente: A, destino: 'resolvida', evidencia: 'rodou: 6 de 6 ok' };
  const r = parcial(cx, slug, { pendentes: [A, B], destinos: [d] });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.deepStrictEqual(bloco(cx, slug, 'executar').destinos, [d]);
});

// ---------------------------------------------------------------- tarefa 2: `ok` so fecha com destino

const DEST_A = { pendente: A, destino: 'resolvida', evidencia: 'rodou: 3 de 3 ok' };
const DEST_B = { pendente: B, destino: 'descartada', motivo: 'fora do escopo' };

/** Apenas `iniciar`: para os casos de estagios sem pre-requisito. */
function iniciarSo(cx) {
  n += 1;
  const slug = `caso-${n}`;
  const r = estado(cx, ['iniciar', '--slug', slug]);
  assert.strictEqual(r.status, 0, r.stderr);
  return slug;
}

caso('ok com pendencia sem destino e recusado em vez de apagar em silencio', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B] }).status, 0);
  const antes = bytes(cx, slug);
  const r = fecharOk(cx, slug);
  recusado(r, antes, bytes(cx, slug), [A, B]);
  assert.strictEqual(bloco(cx, slug, 'executar').status, 'parcial');
});

caso('ok com destino so para A recusa e lista so B', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B] }).status, 0);
  const antes = bytes(cx, slug);
  const r = fecharOk(cx, slug, { destinos: [DEST_A] });
  recusado(r, antes, bytes(cx, slug), [B]);
  assert.ok(!r.stderr.includes(A), `stderr nao devia citar A: ${r.stderr}`);
});

caso('ok com pendentes e destinos no mesmo json fecha sem pendentes e com destinos', () => {
  const slug = abrir(cx);
  const r = fecharOk(cx, slug, { pendentes: [A, B], destinos: [DEST_A, DEST_B] });
  assert.strictEqual(r.status, 0, r.stderr);
  const b = bloco(cx, slug, 'executar');
  assert.strictEqual(b.status, 'ok');
  assert.ok(!('pendentes' in b), 'pendentes devia sumir');
  assert.deepStrictEqual(b.destinos, [DEST_A, DEST_B]);
  assert.ok(b.catraca_mutacao, 'catraca_mutacao devia sobreviver');
});

caso('parcial com pendentes e ok so com destinos fecha sem pendentes', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B] }).status, 0);
  const r = fecharOk(cx, slug, { destinos: [DEST_A, DEST_B] });
  assert.strictEqual(r.status, 0, r.stderr);
  const b = bloco(cx, slug, 'executar');
  assert.ok(!('pendentes' in b), 'pendentes devia sumir');
  assert.strictEqual(b.destinos.length, 2);
});

caso('destinos acumula entre dois parciais e o ok seguinte fecha', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B], destinos: [DEST_A] }).status, 0);
  assert.strictEqual(parcial(cx, slug, { destinos: [DEST_B] }).status, 0);
  assert.deepStrictEqual(bloco(cx, slug, 'executar').destinos, [DEST_A, DEST_B]);
  const r = fecharOk(cx, slug);
  assert.strictEqual(r.status, 0, r.stderr);
});

caso('o destino mais novo de uma pendencia substitui o antigo', () => {
  const slug = abrir(cx);
  const antigo = { pendente: A, destino: 'descartada', motivo: 'achei que nao importava' };
  assert.strictEqual(parcial(cx, slug, { pendentes: [A], destinos: [antigo] }).status, 0);
  assert.strictEqual(parcial(cx, slug, { destinos: [DEST_A] }).status, 0);
  assert.deepStrictEqual(bloco(cx, slug, 'executar').destinos, [DEST_A]);
});

caso('ok sem pendencia nenhuma fecha e o bloco nao ganha pendentes nem destinos', () => {
  const slug = abrir(cx);
  const r = fecharOk(cx, slug);
  assert.strictEqual(r.status, 0, r.stderr);
  const b = bloco(cx, slug, 'executar');
  assert.ok(!('pendentes' in b) && !('destinos' in b), JSON.stringify(b));
});

caso('design aprovado com pendencia sem destino e recusado (vale em qualquer estagio)', () => {
  const slug = iniciarSo(cx);
  const antes = bytes(cx, slug);
  const r = marcar(cx, slug, 'design', 'aprovado', { pendentes: [A] });
  recusado(r, antes, bytes(cx, slug), [A]);
});

caso('arqueologia dispensada com pendencia sem destino e recusada', () => {
  const slug = iniciarSo(cx);
  const antes = bytes(cx, slug);
  const r = marcar(cx, slug, 'arqueologia', 'dispensada', { pendentes: [A] });
  recusado(r, antes, bytes(cx, slug), [A]);
});

// ---------------------------------------------------------------- fim

try { fs.rmSync(cx.raiz, { recursive: true, force: true }); } catch (_) { /* limpeza best-effort */ }

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
