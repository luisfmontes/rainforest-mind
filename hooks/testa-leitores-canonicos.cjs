#!/usr/bin/env node
'use strict';
// Bateria dos leitores do nome canonico de projeto (#435, D2/D3/D4): resolverCaminhos, a abertura
// (hooks/memoria-session-start.cjs como processo), o hook do pedido, o hook do Agent e o apelido.
//
// Monta repositorios git REAIS numa pasta temporaria: `alfa` (com um worktree em
// `.claude/worktrees/w1`) e uma pasta sem `.git`. Cada caixa de dados e criada pelo criarSchema REAL
// e marcada com `PRAGMA user_version = 2`: a bateria mede o leitor, nao a migracao 7. Os processos
// filhos recebem RFM_ROOT explicito; nunca toca ~/.rainforest. Nenhum caso le o texto do fonte.
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');

const memoria = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));
const { slugDoCaminho } = require(path.join(__dirname, '..', 'scripts', 'lib', 'projeto-canonico.cjs'));
const { apelidoDe, formatarObservacao, montarLegendaMemoria } = require('./lib/memoria-sessao.cjs');

const HOOK_ABERTURA = path.join(__dirname, 'memoria-session-start.cjs');
const HOOK_PEDIDO = path.join(__dirname, 'memoria-assunto-prompt.cjs');
const HOOK_AGENTE = path.join(__dirname, 'memoria-assunto-agente.cjs');

let ok = 0;
let falhou = 0;
function caso(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`ok  ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`FALHA  ${nome}\n  ${String(e.message).split('\n')[0]}`);
  }
}

const git = (cwd, args) => execFileSync('git', args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });

const tmp = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'testa-leitores-canonicos-')));
const alfa = path.join(tmp, 'alfa');
const w1 = path.join(alfa, '.claude', 'worktrees', 'w1');
const w1Sub = path.join(w1, 'src', 'fundo');
const alfaSub = path.join(alfa, 'scripts');
const semGit = path.join(tmp, 'sem-git', 'pasta-solta');
const neutra = path.join(tmp, 'neutra');
let preparoOk = true;
try {
  fs.mkdirSync(alfa, { recursive: true });
  git(alfa, ['init', '-q']);
  git(alfa, ['-c', 'user.name=t', '-c', 'user.email=t@t.invalid', 'commit', '-q', '--allow-empty', '-m', 'base']);
  fs.mkdirSync(path.dirname(w1), { recursive: true });
  git(alfa, ['worktree', 'add', '-q', '--detach', w1]);
  fs.mkdirSync(w1Sub, { recursive: true });
  fs.mkdirSync(alfaSub, { recursive: true });
  fs.mkdirSync(semGit, { recursive: true });
  fs.mkdirSync(neutra, { recursive: true });
} catch (e) {
  preparoOk = false;
  falhou++;
  console.log(`FALHA  preparo dos repositorios de teste\n  ${String(e.message).split('\n')[0]}`);
}

const CANONICO = slugDoCaminho(alfa);
const GRAFIA_OUTRA = CANONICO.toUpperCase();
const BETA = 'C--Projetos-beta';

// ---- caixas de dados ----
let seqCaixa = 0;
function novaCaixa() {
  seqCaixa += 1;
  const dir = path.join(tmp, 'caixa-' + seqCaixa);
  fs.mkdirSync(dir, { recursive: true });
  const db = new DatabaseSync(path.join(dir, 'rainforest.db'));
  memoria.criarSchema(db);
  db.exec('PRAGMA user_version = 2');
  return { dir, db };
}
function inserir(db, projeto, conteudo, criadaEm, origem) {
  return Number(db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run(projeto, conteudo, criadaEm, origem).lastInsertRowid);
}
function enchimento(db, quantas) {
  const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  db.exec('BEGIN');
  for (let i = 0; i < quantas; i++) {
    ins.run('enchimento-' + (i % 50), 'Fundo ' + i + '\n\nenchimento' + i + ' fundo' + i + ' rotina comum', '2026-10-01T10:00:00.000Z', 'f' + i);
  }
  db.exec('COMMIT');
}

function rodarHook(hook, { raiz, stdin = '{}', cwd = neutra, projectDir } = {}) {
  const env = { ...process.env, RFM_ROOT: raiz };
  delete env.CLAUDE_PROJECT_DIR;
  if (projectDir) env.CLAUDE_PROJECT_DIR = projectDir;
  const t0 = Date.now();
  const r = spawnSync(process.execPath, [hook], { input: stdin, env, cwd, encoding: 'utf8', timeout: 20000 });
  return { codigo: r.status, saida: r.stdout, erro: r.stderr, ms: Date.now() - t0 };
}
const contextoDe = (saida) => JSON.parse(saida).hookSpecificOutput.additionalContext;
const linhasDeMemoria = (ctx) => ctx.split('\n').filter((l) => l.startsWith('[20'));

// ---- resolverCaminhos ----
{
  const caixa = novaCaixa();
  caixa.db.close();
  process.env.RFM_ROOT = caixa.dir;
  delete process.env.CLAUDE_PROJECT_DIR;

  caso('resolverCaminhos devolve { raiz, caminhoDb, projeto, canonico } sem o campo projetos', () => {
    const r = memoria.resolverCaminhos(alfa);
    assert.deepStrictEqual(Object.keys(r).sort(), ['caminhoDb', 'canonico', 'projeto', 'raiz']);
    assert.strictEqual(r.projeto, 'alfa');
    assert.strictEqual(r.canonico, CANONICO);
    assert.strictEqual(r.caminhoDb, path.join(caixa.dir, 'rainforest.db'));
  });
  caso('no worktree real de alfa o canonico e o do topo principal e o projeto e alfa', () => {
    const r = memoria.resolverCaminhos(w1);
    assert.strictEqual(r.canonico, CANONICO);
    assert.strictEqual(r.projeto, 'alfa');
  });
  caso('em subpasta do worktree e em subpasta da raiz o canonico e o mesmo', () => {
    for (const dir of [w1Sub, alfaSub]) {
      const r = memoria.resolverCaminhos(dir);
      assert.strictEqual(r.canonico, CANONICO, dir);
      assert.strictEqual(r.projeto, 'alfa', dir);
    }
  });
  caso('sem .git o canonico e o slug do proprio cwd e o projeto e o basename', () => {
    const r = memoria.resolverCaminhos(semGit);
    assert.strictEqual(r.canonico, slugDoCaminho(semGit));
    assert.strictEqual(r.projeto, 'pasta-solta');
  });
  caso('chaveHarness saiu do modulo', () => {
    assert.strictEqual(memoria.chaveHarness, undefined);
  });
}

// ---- apelidoDe ----
caso('apelidoDe compara sem diferenciar caixa e devolve undefined sem par', () => {
  const ap = { 'C--Projetos-alfa': 'alfa' };
  assert.strictEqual(apelidoDe(ap, 'c--projetos-ALFA'), 'alfa');
  assert.strictEqual(apelidoDe(ap, 'C--Projetos-alfa'), 'alfa');
  assert.strictEqual(apelidoDe(ap, 'C--Projetos-beta'), undefined);
  assert.strictEqual(apelidoDe(null, 'C--Projetos-alfa'), undefined);
  assert.strictEqual(apelidoDe(ap, ''), undefined);
});
caso('a linha da abertura e a legenda usam o apelido mesmo com a caixa do slug diferente', () => {
  const obs = { projeto: 'C--PROJETOS-ALFA', conteudo: '## Titulo\n\nSubtitulo', criada_em: '2026-09-05T12:00:00Z' };
  const ap = { 'C--Projetos-alfa': 'alfa' };
  assert.ok(formatarObservacao(obs, ap).includes('(alfa)'), formatarObservacao(obs, ap));
  const legenda = montarLegendaMemoria({ observacoes: [obs], apelidos: ap });
  assert.ok(legenda.includes(' alfa ') && !legenda.includes('C--PROJETOS-ALFA'), legenda);
});

// ---- a abertura, como processo ----
{
  const caixa = novaCaixa();
  const idsAlfa = [];
  idsAlfa.push(inserir(caixa.db, GRAFIA_OUTRA, '## Alfa um\n\nPrimeira de alfa', '2026-09-05T10:00:00Z', 'a1'));
  idsAlfa.push(inserir(caixa.db, GRAFIA_OUTRA, '## Alfa dois\n\nSegunda de alfa', '2026-09-06T10:00:00Z', 'a2'));
  idsAlfa.push(inserir(caixa.db, GRAFIA_OUTRA, '## Alfa tres\n\nTerceira de alfa', '2026-09-07T10:00:00Z', 'a3'));
  inserir(caixa.db, BETA, '## Beta um\n\nPrimeira de beta', '2026-09-01T10:00:00Z', 'b1');
  inserir(caixa.db, BETA, '## Beta dois\n\nSegunda de beta', '2026-09-02T10:00:00Z', 'b2');
  caixa.db.prepare('INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?, ?, ?, ?)')
    .run(GRAFIA_OUTRA, 'Resumo de alfa', 'Sintese do que alfa fez', '2026-09-08T10:00:00Z');
  caixa.db.close();

  caso('abertura acha linhas e resumos gravados com o slug em outra caixa', () => {
    assert.ok(preparoOk, 'repositorios de teste ausentes');
    const r = rodarHook(HOOK_ABERTURA, { raiz: caixa.dir, projectDir: w1 });
    assert.strictEqual(r.codigo, 0, r.erro);
    const ctx = contextoDe(r.saida);
    const linhas = linhasDeMemoria(ctx);
    const deAlfa = linhas.filter((l) => /^\[[^\]]*\(alfa\)\]/.test(l));
    assert.strictEqual(deAlfa.filter((l) => !l.includes('[resumo')).length, 3, ctx);
    assert.strictEqual(deAlfa.filter((l) => l.includes('[resumo')).length, 1, 'resumo de alfa ausente: ' + ctx);
    assert.ok(!ctx.toLowerCase().includes(CANONICO.toLowerCase()), 'a chave longa vazou no bloco');
    const deBeta = linhas.filter((l) => l.includes(`(${BETA})`));
    assert.strictEqual(deBeta.length, 2, ctx);
    assert.strictEqual(linhas.length, 6, ctx);
  });
  caso('a legenda visivel da abertura tambem usa o nome curto', () => {
    const r = rodarHook(HOOK_ABERTURA, { raiz: caixa.dir, projectDir: w1 });
    const msg = JSON.parse(r.saida).systemMessage || '';
    assert.ok(msg.includes(' alfa ') && !msg.toLowerCase().includes(CANONICO.toLowerCase()), msg);
  });
}

// ---- o hook do pedido e o do Agent ----
{
  const caixa = novaCaixa();
  enchimento(caixa.db, 400);
  const TEXTO = 'Reconciliacao zarquon flibbertigibbet\n\n' + 'zarquon flibbertigibbet zarquon flibbertigibbet quasar '.repeat(3);
  // Beta primeiro: ids menores. Sem a preferencia pelo projeto atual, o desempate por id poria beta antes.
  const idsBeta = [
    inserir(caixa.db, BETA, TEXTO, '2026-09-20T10:00:00.000Z', 'pb1'),
    inserir(caixa.db, BETA, TEXTO, '2026-09-21T10:00:00.000Z', 'pb2'),
  ];
  const idsAlfa = [2, 3, 4].map((d, i) => inserir(caixa.db, GRAFIA_OUTRA, TEXTO, `2026-10-0${d}T10:00:00.000Z`, 'pa' + i));
  caixa.db.close();
  const PEDIDO = 'quero entender a reconciliacao zarquon flibbertigibbet quasar';

  caso('o hook do pedido semeia os ids que a abertura serviu (projeto atual em outra caixa)', () => {
    assert.ok(preparoOk, 'repositorios de teste ausentes');
    const abertura = rodarHook(HOOK_ABERTURA, { raiz: caixa.dir, projectDir: w1 });
    assert.strictEqual(abertura.codigo, 0, abertura.erro);
    const ctxAbertura = contextoDe(abertura.saida);
    assert.strictEqual(linhasDeMemoria(ctxAbertura).filter((l) => l.includes('(alfa)')).length, 3, ctxAbertura);
    const transcrito = path.join(tmp, 'sessao-p.jsonl');
    fs.writeFileSync(transcrito, JSON.stringify({
      type: 'attachment',
      attachment: { type: 'hook_success', hookEvent: 'SessionStart', hookName: 'SessionStart:startup', stdout: abertura.saida.trim() },
    }) + '\n');
    const payload = JSON.stringify({
      session_id: 'sessao-p', transcript_path: transcrito, cwd: w1, hook_event_name: 'UserPromptSubmit', prompt: PEDIDO,
    });
    const r = rodarHook(HOOK_PEDIDO, { raiz: caixa.dir, stdin: payload });
    assert.strictEqual(r.codigo, 0, r.erro);
    const arquivo = path.join(caixa.dir, 'memoria-assunto', 'sessao-p.json');
    const ids = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
    for (const id of idsAlfa) assert.ok(ids.includes(id), `id ${id} de alfa nao foi semeado: ${ids.join(',')}`);
    // As de alfa ja foram servidas: o pedido traz so o que a abertura nao serviu (as duas de beta).
    const injetado = JSON.parse(r.saida).hookSpecificOutput.additionalContext;
    const linhas = injetado.split('\n').filter((l) => l.startsWith('['));
    assert.strictEqual(linhas.length, 2, injetado);
    assert.ok(linhas.every((l) => l.includes(BETA)), injetado);
    for (const id of idsBeta) assert.ok(!idsAlfa.includes(id));
  });

  caso('o hook do Agent usa o canonico como projeto atual: as de alfa vem antes das de beta', () => {
    assert.ok(preparoOk, 'repositorios de teste ausentes');
    const payload = JSON.stringify({
      session_id: 'sessao-ag', cwd: w1, hook_event_name: 'PreToolUse', tool_name: 'Agent', tool_input: { prompt: PEDIDO },
    });
    const r = rodarHook(HOOK_AGENTE, { raiz: caixa.dir, stdin: payload });
    assert.strictEqual(r.codigo, 0, r.erro);
    const novo = JSON.parse(r.saida).hookSpecificOutput.updatedInput.prompt;
    const linhas = novo.split('\n').filter((l) => l.startsWith('[20'));
    assert.strictEqual(linhas.length, 3, novo);
    assert.ok(linhas.every((l) => l.includes(`(${GRAFIA_OUTRA})`)), novo);
  });
}

// ---- tempo da abertura numa caixa grande ----
{
  const caixa = novaCaixa();
  enchimento(caixa.db, 14000);
  for (let i = 0; i < 3; i++) {
    inserir(caixa.db, GRAFIA_OUTRA, '## Alfa ' + i + '\n\nLinha de alfa', `2026-10-0${i + 2}T10:00:00.000Z`, 'ga' + i);
  }
  caixa.db.close();
  caso('com 14.000 observacoes de enchimento a abertura sai 0 em menos de 3 s', () => {
    assert.ok(preparoOk, 'repositorios de teste ausentes');
    const r = rodarHook(HOOK_ABERTURA, { raiz: caixa.dir, projectDir: w1 });
    console.log(`  tempo da abertura: ${r.ms} ms`);
    assert.strictEqual(r.codigo, 0, r.erro);
    assert.ok(r.ms < 3000, `levou ${r.ms} ms`);
    const linhas = linhasDeMemoria(contextoDe(r.saida));
    assert.strictEqual(linhas.filter((l) => l.includes('(alfa)')).length, 3, linhas.join('\n'));
  });
}

try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* melhor esforco */ }
console.log(`${ok} ok, ${falhou} falha(s)`);
process.exit(falhou > 0 ? 1 : 0);
