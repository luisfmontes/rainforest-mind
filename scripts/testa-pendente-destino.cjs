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
casoRecusa('destino que e lista com resolvida (nao texto) e recusado', [{ pendente: A, destino: ['resolvida'], evidencia: 'x' }], ['destino']);
casoRecusa('item sem o campo destino e recusado',[{ pendente: A, motivo: 'x' }], ['destino']);
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

// ---------------------------------------------------------------- tarefa 3: `parcial` que omite avisa e mantem

caso('parcial que omite a pendencia anterior continua com ela em pendentes', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B] }).status, 0);
  const r = parcial(cx, slug, { pendentes: [B] });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.ok(r.stderr.includes(A), `stderr devia citar A: ${r.stderr}`);
  assert.ok(!r.stderr.includes(B), `stderr nao devia citar B: ${r.stderr}`);
  assert.deepStrictEqual(bloco(cx, slug, 'executar').pendentes, [A, B]);
});

caso('parcial que omite A mas traz destino para A nao avisa e fica so com B', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B] }).status, 0);
  const r = parcial(cx, slug, { pendentes: [B], destinos: [DEST_A] });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.ok(!r.stderr.includes(A), `stderr nao devia citar A: ${r.stderr}`);
  assert.deepStrictEqual(bloco(cx, slug, 'executar').pendentes, [B]);
});

caso('parcial com pendencia nova avisa so da omitida e mantem a ordem A,B,C', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B] }).status, 0);
  const r = parcial(cx, slug, { pendentes: [B, C] });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.ok(r.stderr.includes(A), `stderr devia citar A (omitida): ${r.stderr}`);
  assert.ok(!r.stderr.includes(B) && !r.stderr.includes(C), `stderr nao devia citar B nem C: ${r.stderr}`);
  assert.deepStrictEqual(bloco(cx, slug, 'executar').pendentes, [A, B, C]);
});

caso('parcial sem a chave pendentes nao avisa e mantem as anteriores', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B] }).status, 0);
  const r = parcial(cx, slug, { tarefas_ok: 1 });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.ok(!r.stderr.includes(A) && !r.stderr.includes(B), `stderr nao devia citar pendencia: ${r.stderr}`);
  assert.deepStrictEqual(bloco(cx, slug, 'executar').pendentes, [A, B]);
});

caso('a pendencia omitida volta a barrar o ok', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B] }).status, 0);
  assert.strictEqual(parcial(cx, slug, { pendentes: [B] }).status, 0);
  const antes = bytes(cx, slug);
  const r = fecharOk(cx, slug, { destinos: [DEST_B] });
  recusado(r, antes, bytes(cx, slug), [A]);
});

caso('reprovado nao exige destino e mantem as pendencias gravadas', () => {
  const slug = abrir(cx);
  assert.strictEqual(parcial(cx, slug, { pendentes: [A, B] }).status, 0);
  const r = marcar(cx, slug, 'executar', 'reprovado', '{}');
  assert.strictEqual(r.status, 0, r.stderr);
  assert.deepStrictEqual(bloco(cx, slug, 'executar').pendentes, [A, B]);
});

caso('parcial com destino para todas deixa pendentes vazio e guarda os destinos', () => {
  const slug = abrir(cx);
  const r = parcial(cx, slug, { pendentes: [A, B], destinos: [DEST_A, DEST_B] });
  assert.strictEqual(r.status, 0, r.stderr);
  const b = bloco(cx, slug, 'executar');
  assert.deepStrictEqual(b.pendentes, []);
  assert.strictEqual(b.destinos.length, 2);
});

// ---------------------------------------------------------------- tarefa 4: `exigir fechar` recusa orfa

/** Fluxo com os sete estagios fechados, reescrito a mao (cenario "editado a mao"). `mexer(est)` ajusta o objeto. */
function fluxoFechadoAMao(cx, mexer) {
  const slug = iniciarSo(cx);
  const arq = arquivoDe(cx, slug);
  const est = JSON.parse(fs.readFileSync(arq, 'utf8'));
  for (const e of ['arqueologia', 'design', 'plano', 'executar', 'revisar', 'verificar', 'fechar']) {
    est[e] = { ...(est[e] || {}), status: e === 'design' ? 'aprovado' : 'ok', em: '2026-10-09' };
  }
  if (mexer) mexer(est);
  fs.writeFileSync(arq, JSON.stringify(est, null, 2) + '\n', 'utf8');
  return slug;
}
const exigir = (cx, slug, est) => estado(cx, ['exigir', '--slug', slug, '--estagio', est]);

caso('exigir fechar sem pendencia nenhuma passa', () => {
  const slug = fluxoFechadoAMao(cx);
  const r = exigir(cx, slug, 'fechar');
  assert.strictEqual(r.status, 0, r.stderr);
  assert.ok(r.stdout.includes("ok: pre-requisitos de 'fechar' fechados"), r.stdout);
});

caso('exigir fechar recusa pendencia sem destino num bloco editado a mao', () => {
  const slug = fluxoFechadoAMao(cx, (est) => { est.executar.pendentes = [A]; });
  const r = exigir(cx, slug, 'fechar');
  assert.strictEqual(r.status, 2, `esperava exit 2, veio ${r.status}: ${r.stdout}`);
  assert.ok(r.stderr.includes('executar') && r.stderr.includes(A), r.stderr);
});

caso('exigir fechar passa quando destinos cobrem a pendencia', () => {
  const slug = fluxoFechadoAMao(cx, (est) => { est.executar.pendentes = [A]; est.executar.destinos = [DEST_A]; });
  const r = exigir(cx, slug, 'fechar');
  assert.strictEqual(r.status, 0, r.stderr);
});

caso('exigir fechar cita os dois estagios com orfa (a varredura nao para na primeira)', () => {
  const slug = fluxoFechadoAMao(cx, (est) => { est.plano.pendentes = [A]; est.verificar.pendentes = [B]; });
  const r = exigir(cx, slug, 'fechar');
  assert.strictEqual(r.status, 2, `esperava exit 2, veio ${r.status}`);
  assert.ok(r.stderr.includes('plano') && r.stderr.includes('verificar'), r.stderr);
  assert.ok(r.stderr.includes(A) && r.stderr.includes(B), r.stderr);
});

caso('M3: destino invalido (sem campo; destino fora dos tres) nao conta: exigir fechar recusa A e B', () => {
  const slug = fluxoFechadoAMao(cx, (est) => {
    est.executar.pendentes = [A, B];
    est.executar.destinos = [{ pendente: A }, { pendente: B, destino: 'adiada', motivo: 'x' }];
  });
  const r = exigir(cx, slug, 'fechar');
  assert.strictEqual(r.status, 2, `esperava exit 2, veio ${r.status}: ${r.stdout}`);
  assert.ok(r.stderr.includes(A) && r.stderr.includes(B), r.stderr);
});

caso('exigir fechar ignora chave que nao e estagio (historico)', () => {
  const slug = fluxoFechadoAMao(cx, (est) => { est.revisar_historico_1_23_0 = { status: 'reprovado', pendentes: [A] }; });
  const r = exigir(cx, slug, 'fechar');
  assert.strictEqual(r.status, 0, r.stderr);
});

caso('exigir fechar com pendentes vazio passa', () => {
  const slug = fluxoFechadoAMao(cx, (est) => { est.executar.pendentes = []; });
  const r = exigir(cx, slug, 'fechar');
  assert.strictEqual(r.status, 0, r.stderr);
});

caso('a checagem de orfa e so do fechar: exigir revisar passa com a mesma orfa', () => {
  const slug = fluxoFechadoAMao(cx, (est) => { est.executar.pendentes = [A]; });
  // `exigir revisar` captura snapshot via git: a caixa (tmp, fora do repo) vira repo com um commit.
  const git = (...a) => spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...a], { cwd: cx.raiz, env: cx.env, encoding: 'utf8' });
  assert.strictEqual(git('init', '-q').status, 0);
  git('add', '-A');
  assert.strictEqual(git('commit', '-q', '-m', 'caixa').status, 0);
  const r = exigir(cx, slug, 'revisar');
  assert.strictEqual(r.status, 0, r.stderr);
});

// ---------------------------------------------------------------- tarefa 5: verbo `deixado`

const deixado = (cx, slug, extra) => estado(cx, ['deixado', '--slug', slug, ...(extra || [])]);
const DEST_PLANTADA = { pendente: C, destino: 'plantada', ref: '#449' };

caso('deixado de fluxo sem pendencia nem destino diz que nada ficou', () => {
  const slug = iniciarSo(cx);
  const r = deixado(cx, slug);
  assert.strictEqual(r.status, 0, r.stderr);
  assert.strictEqual(r.stdout.trim(), 'nada ficou para depois');
});

caso('deixado lista os destinos de todos os estagios em markdown', () => {
  const slug = fluxoFechadoAMao(cx, (est) => {
    est.executar.pendentes = [];
    est.executar.destinos = [DEST_A, DEST_B, DEST_PLANTADA];
  });
  const r = deixado(cx, slug);
  assert.strictEqual(r.status, 0, r.stderr);
  assert.strictEqual(r.stdout.trim().split('\n').join('|'), [
    `- executar: ${A} → resolvida: rodou: 3 de 3 ok`,
    `- executar: ${B} → descartada: fora do escopo`,
    `- executar: ${C} → plantada: #449`,
  ].join('|'));
});

caso('deixado poe os destinos do plano antes dos do executar', () => {
  const slug = fluxoFechadoAMao(cx, (est) => {
    est.executar.pendentes = []; est.executar.destinos = [DEST_B];
    est.plano.pendentes = []; est.plano.destinos = [DEST_A];
  });
  const linhas = deixado(cx, slug).stdout.trim().split('\n');
  assert.strictEqual(linhas.length, 2);
  assert.ok(linhas[0].startsWith('- plano:') && linhas[1].startsWith('- executar:'), linhas.join('|'));
});

caso('deixado mostra a pendencia orfa como (sem destino) e sai 0', () => {
  const slug = fluxoFechadoAMao(cx, (est) => { est.executar.pendentes = [A]; });
  const r = deixado(cx, slug);
  assert.strictEqual(r.status, 0, r.stderr);
  assert.strictEqual(r.stdout.trim(), `- executar: ${A} → (sem destino)`);
});

caso('M3: deixado mostra destino invalido como (sem destino)', () => {
  const slug = fluxoFechadoAMao(cx, (est) => {
    est.executar.pendentes = [A, B];
    est.executar.destinos = [{ pendente: A }, { pendente: B, destino: 'adiada', motivo: 'x' }];
  });
  const r = deixado(cx, slug);
  assert.strictEqual(r.status, 0, r.stderr);
  assert.strictEqual(r.stdout.trim().split('\n').join('|'), `- executar: ${A} → (sem destino)|- executar: ${B} → (sem destino)`);
});

caso('deixado com quebra de linha e espacos repetidos mantem um item por linha', () => {
  const slug = fluxoFechadoAMao(cx, (est) => {
    est.executar.pendentes = [];
    est.executar.destinos = [{ pendente: 'x\n- executar: forjado   item', destino: 'resolvida', evidencia: 'linha1\n\nlinha2    fim' }];
  });
  const linhas = deixado(cx, slug).stdout.trim().split('\n');
  assert.strictEqual(linhas.length, 1, linhas.join('|'));
  assert.strictEqual(linhas[0], '- executar: x - executar: forjado item → resolvida: linha1 linha2 fim');
});

caso('deixado com slug inexistente sai 1 dizendo que nao existe', () => {
  const r = deixado(cx, 'slug-que-nao-existe');
  assert.strictEqual(r.status, 1);
  assert.ok(r.stderr.includes('nao existe'), r.stderr);
});

caso('deixado com flag desconhecida sai 1', () => {
  const slug = iniciarSo(cx);
  const r = estado(cx, ['deixado', '--slug', slug, '--estagio', 'executar']);
  assert.strictEqual(r.status, 1);
  assert.ok(r.stderr.includes('flag desconhecida: --estagio'), r.stderr);
});

caso('deixado e somente leitura: o arquivo de estado fica igual', () => {
  const slug = fluxoFechadoAMao(cx, (est) => { est.executar.pendentes = [A, B]; est.executar.destinos = [DEST_A]; });
  const antes = bytes(cx, slug);
  const r = deixado(cx, slug);
  assert.strictEqual(r.status, 0, r.stderr);
  assert.strictEqual(bytes(cx, slug), antes);
});

// ---------------------------------------------------------------- fim

try { fs.rmSync(cx.raiz, { recursive: true, force: true }); } catch (_) { /* limpeza best-effort */ }

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
