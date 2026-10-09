#!/usr/bin/env node
'use strict';
/**
 * Bateria da utilidade com projeto canonico (#435; design
 * docs/rainforest/design/2026-10-08-projeto-canonico.md, D2 e D3).
 *
 * Monta repositorios git REAIS numa pasta temporaria: `alfa` (com um worktree em
 * `.claude/worktrees/w1`) e uma pasta sem `.git`. A abertura roda como processo
 * (hooks/memoria-session-start.cjs, RFM_ROOT explicito sobre uma caixa criada pelo
 * criarSchema REAL) e a saida REAL dela vai para o transcrito como o attachment
 * `SessionStart`. Nunca toca ~/.rainforest. Nenhum caso le o texto do fonte.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');
const { DatabaseSync } = require('node:sqlite');

const SRC = path.resolve(__dirname, '..');
const memoria = require(path.join(SRC, 'scripts', 'memoria.cjs'));
const { slugDoCaminho } = require(path.join(SRC, 'scripts', 'lib', 'projeto-canonico.cjs'));
const { pontuarSessao, lerProjetoDoTranscrito } = require(path.join(SRC, 'scripts', 'lib', 'utilidade.cjs'));

const HOOK_ABERTURA = path.join(SRC, 'hooks', 'memoria-session-start.cjs');

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

const tmp = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'testa-utilidade-canonico-')));
const alfa = path.join(tmp, 'alfa');
const alfaSub = path.join(alfa, 'scripts');
const w1 = path.join(alfa, '.claude', 'worktrees', 'w1');
const w1Sub = path.join(w1, 'src', 'fundo');
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

function novaCaixa() {
  const dir = path.join(tmp, 'caixa');
  fs.mkdirSync(dir, { recursive: true });
  const db = new DatabaseSync(path.join(dir, 'rainforest.db'));
  memoria.criarSchema(db);
  db.exec('PRAGMA user_version = 2');
  return { dir, db };
}

function rodarAbertura(raiz, projectDir) {
  const env = { ...process.env, RFM_ROOT: raiz, TZ: 'America/Sao_Paulo' };
  env.CLAUDE_PROJECT_DIR = projectDir;
  return spawnSync(process.execPath, [HOOK_ABERTURA], { input: '{}', env, cwd: neutra, encoding: 'utf8', timeout: 20000 });
}

// Formato real do harness (igual a scripts/testa-utilidade.sh): toda linha leva `cwd`; o
// attachment `SessionStart` guarda a saida do hook em `stdout`.
function escreverTranscrito(arquivo, cwd, saidaDoHook) {
  fs.writeFileSync(arquivo, [
    JSON.stringify({
      cwd,
      type: 'attachment',
      attachment: { type: 'hook_success', hookEvent: 'SessionStart', hookName: 'SessionStart:startup', stdout: saidaDoHook.trim() },
    }),
    JSON.stringify({ cwd, type: 'user', message: { role: 'user', content: 'pedido qualquer da sessao' } }),
  ].join('\n') + '\n');
}

caso('sessao em worktree pontua as servidas do projeto principal', () => {
  assert.ok(preparoOk, 'repositorios de teste ausentes');
  const caixa = novaCaixa();
  const ins = caixa.db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
  ins.run(CANONICO, '## Alfa um\n\nPrimeira de alfa', '2026-09-05T10:00:00Z', 'a1');
  ins.run(CANONICO, '## Alfa dois\n\nSegunda de alfa', '2026-09-06T10:00:00Z', 'a2');
  ins.run(CANONICO, '## Alfa tres\n\nTerceira de alfa', '2026-09-07T10:00:00Z', 'a3');

  const abertura = rodarAbertura(caixa.dir, w1);
  assert.strictEqual(abertura.status, 0, abertura.stderr);
  const ctx = JSON.parse(abertura.stdout).hookSpecificOutput.additionalContext;
  const linhasDoBloco = ctx.split('\n').filter((l) => l.startsWith('[20'));
  assert.strictEqual(linhasDoBloco.length, 3, ctx);

  const transcrito = path.join(tmp, 'sessao-w1.jsonl');
  escreverTranscrito(transcrito, w1, abertura.stdout);
  const r = pontuarSessao(caixa.db, 'sessao-w1', transcrito);
  const servidas = caixa.db.prepare("SELECT COUNT(*) n FROM uso_memoria WHERE sessao = 'sessao-w1' AND servida = 1 AND origem = 'observacao'").get().n;
  caixa.db.close();
  assert.strictEqual(servidas, 3, 'linhas servidas gravadas: ' + servidas);
  assert.strictEqual(r.servidasSemId, 0, 'servidasSemId: ' + r.servidasSemId);
  assert.strictEqual(r.servidasComId, 3);
});

caso('lerProjetoDoTranscrito: raiz, subpasta e worktree resolvem o mesmo projeto', () => {
  assert.ok(preparoOk, 'repositorios de teste ausentes');
  for (const cwd of [alfa, alfaSub, w1, w1Sub]) {
    const arquivo = path.join(tmp, 'so-cwd.jsonl');
    fs.writeFileSync(arquivo, JSON.stringify({ cwd, type: 'user', message: { role: 'user', content: 'x' } }) + '\n');
    assert.deepStrictEqual(lerProjetoDoTranscrito(arquivo), { harnessKey: CANONICO, curto: 'alfa' }, cwd);
  }
});

caso('lerProjetoDoTranscrito: cwd sem .git cai no proprio caminho', () => {
  const arquivo = path.join(tmp, 'sem-git.jsonl');
  fs.writeFileSync(arquivo, JSON.stringify({ cwd: semGit, type: 'user', message: { role: 'user', content: 'x' } }) + '\n');
  assert.deepStrictEqual(lerProjetoDoTranscrito(arquivo), { harnessKey: slugDoCaminho(semGit), curto: 'pasta-solta' });
});

caso('lerProjetoDoTranscrito: transcrito sem cwd ou ilegivel devolve nulos', () => {
  const semCwd = path.join(tmp, 'sem-cwd.jsonl');
  fs.writeFileSync(semCwd, JSON.stringify({ type: 'user', message: { role: 'user', content: 'x' } }) + '\n');
  assert.deepStrictEqual(lerProjetoDoTranscrito(semCwd), { harnessKey: null, curto: null });
  assert.deepStrictEqual(lerProjetoDoTranscrito(path.join(tmp, 'nao-existe.jsonl')), { harnessKey: null, curto: null });
});

try {
  fs.rmSync(tmp, { recursive: true, force: true });
} catch {
  // limpeza best-effort: pasta temporaria
}
console.log(`${ok} ok, ${falhou} falha(s)`);
process.exit(falhou === 0 ? 0 : 1);
