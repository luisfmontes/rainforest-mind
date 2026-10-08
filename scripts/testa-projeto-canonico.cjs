#!/usr/bin/env node
'use strict';
/**
 * Bateria de scripts/lib/projeto-canonico.cjs (#435, D1 e D2).
 *
 * Monta repositórios git REAIS numa pasta temporária (nunca toca ~/.rainforest):
 * um repositório principal, um worktree na convenção `.claude/worktrees/`, uma
 * subpasta desse worktree e um worktree fora da convenção, resolvido pelo commondir.
 * Nenhum caso lê o texto do fonte.
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const lib = require(path.join(__dirname, 'lib', 'projeto-canonico.cjs'));
const {
  slugDoCaminho,
  ehSlugDeCaminho,
  topoPrincipal,
  canonicoDoCaminho,
  canonicoDaPasta,
  casarCurto,
} = lib;

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

const git = (cwd, args) =>
  execFileSync('git', args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });

const base = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'projeto-canonico-')));
const alfa = path.join(base, 'alfa');
const w1 = path.join(alfa, '.claude', 'worktrees', 'w1');
const w1Sub = path.join(w1, 'src', 'profundo');
const alfaWt = path.join(base, 'alfa-wt');
const w2 = path.join(alfaWt, 'w2');
const semGit = path.join(base, 'sem-git', 'pasta');
const sub = path.join(base, 'submodulo-sem-commondir');
const subGitdir = path.join(base, 'modulos', 'sub');

try {
  fs.mkdirSync(alfa, { recursive: true });
  git(alfa, ['init', '-q']);
  git(alfa, ['-c', 'user.name=t', '-c', 'user.email=t@t.invalid', 'commit', '-q', '--allow-empty', '-m', 'base']);
  fs.mkdirSync(path.dirname(w1), { recursive: true });
  git(alfa, ['worktree', 'add', '-q', '--detach', w1]);
  fs.mkdirSync(w1Sub, { recursive: true });
  fs.mkdirSync(alfaWt, { recursive: true });
  git(alfa, ['worktree', 'add', '-q', '--detach', w2]);
  fs.mkdirSync(semGit, { recursive: true });
  // `.git` de arquivo apontando para um diretório sem `commondir` (formato de submódulo).
  fs.mkdirSync(subGitdir, { recursive: true });
  fs.mkdirSync(sub, { recursive: true });
  fs.writeFileSync(path.join(sub, '.git'), `gitdir: ${subGitdir.split(path.sep).join('/')}\n`);
} catch (e) {
  console.log(`FALHOU  preparo dos repositorios de teste\n  ${String(e.message).split('\n')[0]}`);
  falhou++;
}

const slugAlfa = slugDoCaminho(alfa);

caso('slug de caminho Windows de worktree na convencao', () => {
  assert.strictEqual(
    slugDoCaminho('C:/Projetos/alfa/.claude/worktrees/w1'),
    'C--Projetos-alfa--claude-worktrees-w1',
  );
});

caso('caminho com ponto, sublinhado, espaco e acento vira so hifen (regra do harness)', () => {
  assert.strictEqual(slugDoCaminho('alfa.beta_gama delta/çã'), 'alfa-beta-gama-delta---');
});

caso('ehSlugDeCaminho reconhece drive e caminho Unix, recusa nome comum', () => {
  assert.strictEqual(ehSlugDeCaminho('C--Projetos-alfa'), true);
  assert.strictEqual(ehSlugDeCaminho('-home-luis-alfa'), true);
  assert.strictEqual(ehSlugDeCaminho('alfa'), false);
  assert.strictEqual(ehSlugDeCaminho('meu-alfa'), false);
  assert.strictEqual(ehSlugDeCaminho('C-Projetos'), false);
});

caso('canonicoDoCaminho do repositorio principal: canonico = slug de alfa, curto = alfa', () => {
  const r = canonicoDoCaminho(alfa);
  assert.strictEqual(r.canonico, slugAlfa);
  assert.strictEqual(r.curto, 'alfa');
});

caso('canonicoDoCaminho de worktree na convencao: mesmo canonico do principal', () => {
  const r = canonicoDoCaminho(w1);
  assert.strictEqual(r.canonico, slugAlfa);
  assert.strictEqual(r.curto, 'alfa');
});

caso('canonicoDoCaminho de subpasta do worktree: mesmo canonico do principal', () => {
  const r = canonicoDoCaminho(w1Sub);
  assert.strictEqual(r.canonico, slugAlfa);
  assert.strictEqual(r.curto, 'alfa');
});

caso('canonicoDoCaminho de worktree fora da convencao resolve pelo commondir, nao pelo nome da pasta', () => {
  const r = canonicoDoCaminho(w2);
  assert.strictEqual(r.canonico, slugAlfa);
  assert.strictEqual(r.curto, 'alfa');
  assert.strictEqual(topoPrincipal(w2), alfa);
});

caso('canonicoDoCaminho de pasta sem .git: canonico = slug da pasta, curto = basename', () => {
  const r = canonicoDoCaminho(semGit);
  assert.strictEqual(r.canonico, slugDoCaminho(semGit));
  assert.strictEqual(r.curto, 'pasta');
  assert.strictEqual(topoPrincipal(semGit), null);
});

caso('.git de arquivo sem commondir: devolve o proprio diretório, nao o pai', () => {
  assert.strictEqual(topoPrincipal(sub), sub);
});

caso('canonicoDaPasta separa a marca de worktree do nome do repositorio', () => {
  assert.deepStrictEqual(canonicoDaPasta('C--Projetos-alfa--claude-worktrees-fluxo-x-y'), {
    canonico: 'C--Projetos-alfa',
    worktree: 'fluxo-x-y',
  });
});

caso('canonicoDaPasta sem marca devolve worktree null', () => {
  assert.deepStrictEqual(canonicoDaPasta('C--Projetos-alfa'), { canonico: 'C--Projetos-alfa', worktree: null });
});

caso('canonicoDaPasta reconhece a marca em outra caixa', () => {
  assert.deepStrictEqual(canonicoDaPasta('C--Projetos-alfa--CLAUDE-WORKTREES-fluxo-x'), {
    canonico: 'C--Projetos-alfa',
    worktree: 'fluxo-x',
  });
});

caso('casarCurto com um unico candidato devolve unico', () => {
  const r = casarCurto('alfa', ['C--Projetos-alfa', 'C--Projetos-beta']);
  assert.strictEqual(r.tipo, 'unico');
  assert.strictEqual(r.canonico, 'C--Projetos-alfa');
});

caso('casarCurto com dois repositorios de mesmo nome devolve ambiguo com os dois candidatos', () => {
  const r = casarCurto('alfa', ['C--Projetos-alfa', 'C--Outros-alfa']);
  assert.strictEqual(r.tipo, 'ambiguo');
  assert.strictEqual(r.canonico, null);
  assert.deepStrictEqual(r.candidatos.slice().sort(), ['C--Outros-alfa', 'C--Projetos-alfa']);
});

caso('casarCurto sem candidato devolve nenhum', () => {
  const r = casarCurto('gama', ['C--Projetos-alfa', 'C--Projetos-beta']);
  assert.strictEqual(r.tipo, 'nenhum');
  assert.deepStrictEqual(r.candidatos, []);
});

caso('casarCurto casa sem diferenciar caixa', () => {
  assert.strictEqual(casarCurto('ALFA', ['C--Projetos-alfa', 'C--Projetos-beta']).tipo, 'unico');
});

caso('casarCurto nao casa pedaco no meio do nome (fronteira de hifen)', () => {
  assert.strictEqual(casarCurto('lfa', ['C--Projetos-alfa', 'C--Projetos-beta']).tipo, 'nenhum');
});

caso('casarCurto compara meu_alfa como meu-alfa', () => {
  const r = casarCurto('meu_alfa', ['C--Projetos-meu-alfa', 'C--Projetos-alfa']);
  assert.strictEqual(r.tipo, 'unico');
  assert.strictEqual(r.canonico, 'C--Projetos-meu-alfa');
});

try {
  fs.rmSync(base, { recursive: true, force: true });
} catch {
  /* limpeza é melhor esforço: pasta temporária do sistema */
}

console.log(`ok: ${ok}   falhou: ${falhou}   (${falhou} falha(s))`);
process.exitCode = falhou ? 1 : 0;
