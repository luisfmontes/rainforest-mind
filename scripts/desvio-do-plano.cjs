#!/usr/bin/env node
// @categoria: guia
// Desvio do plano: o arquivo escrito esta entre os `arquivos:` do plano do fluxo em curso?
// Somente leitura, sem gh. Saida: JSON em uma linha, exit 0.
// Contrato em docs/rainforest/planos/2026-10-07-desk-no-mod.md ("Contrato dos dados").
//
// Uso: node scripts/desvio-do-plano.cjs --cwd <dir> --arquivo <caminho>
//   {"veredito":"dentro"|"fora"|"isento"|"sem-fluxo"|"sem-plano"|"fora-da-raiz","rel":...,"slug":...}
// Exit 2 sem --cwd ou sem --arquivo; exit 1 em erro inesperado.
const path = require('path');
const { spawnSync } = require('child_process');
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));
const { lerFluxos, worktrees } = require('./faixa-dados.cjs');
const { extrairTarefas, lerMarkdown, globMatches, globsIsentos } = require('./conferir-fluxo.cjs');

function valorDe(nome) {
  const i = process.argv.indexOf(nome);
  return i !== -1 && i + 1 < process.argv.length ? process.argv[i + 1] : null;
}

// Barras para frente, letra do drive em minuscula, sem barra final. No Windows o
// sistema de arquivos ignora caixa, entao a chave de comparacao tambem.
function chave(p) {
  const s = p.replace(/\\/g, '/').replace(/^([a-zA-Z]):/, (m, d) => `${d.toLowerCase()}:`).replace(/(.)\/+$/, '$1');
  return process.platform === 'win32' ? s.toLowerCase() : s;
}

// Raiz do worktree de `cwd`. `git -C` fora de repo sobe para o pai em silencio:
// spawnSync com cwd e status conferido; falhou, o proprio cwd.
function raizDe(cwd) {
  const r = spawnSync(caminhoExecutavel('git'), ['rev-parse', '--show-toplevel'], { cwd, encoding: 'utf8' });
  if (r.error || r.status !== 0) return cwd;
  return String(r.stdout).trim() || cwd;
}

// Caminho do arquivo escrito, relativo a `rel` contra a raiz de worktree mais longa que o contem.
function relativo(arquivo, cwd, raizes) {
  const abs = /^[a-zA-Z]:[\\/]/.test(arquivo) || arquivo.startsWith('/')
    ? arquivo.replace(/\\/g, '/')
    : path.resolve(cwd, arquivo.replace(/\\/g, '/')).replace(/\\/g, '/');
  const k = chave(abs);
  let melhor = null;
  for (const r of raizes) {
    const kr = chave(r);
    if ((k === kr || k.startsWith(`${kr}/`)) && (!melhor || kr.length > melhor.length)) melhor = kr;
  }
  return melhor === null ? null : abs.slice(melhor.length).replace(/^\/+/, '');
}

function foraDoPlano(rel, permitidos) {
  return !permitidos.some((glob) => globMatches(rel, glob));
}

function globsDe(plano) {
  const globs = [];
  for (const t of extrairTarefas(plano)) globs.push(...t.arquivos);
  return globs;
}

function veredito(cwd, arquivo) {
  const raiz = raizDe(cwd);
  const fluxo = lerFluxos(cwd).find((f) => chave(f.worktree) === chave(raiz));
  if (!fluxo) return { veredito: 'sem-fluxo', rel: null, slug: null };
  const plano = lerMarkdown(path.join(fluxo.worktree, 'docs', 'rainforest', 'planos', `${fluxo.slug}.md`));
  if (plano === null) return { veredito: 'sem-plano', rel: null, slug: fluxo.slug };
  const rel = relativo(arquivo, cwd, worktrees(cwd));
  if (rel === null) return { veredito: 'fora-da-raiz', rel: null, slug: fluxo.slug };
  const globs = globsDe(plano);
  // Plano sem nenhum `arquivos:` nao declara escopo: tudo sairia `fora`, e isso acusaria sem base.
  if (globs.length === 0) return { veredito: 'sem-arquivos', rel, slug: fluxo.slug };
  if (!foraDoPlano(rel, globs)) return { veredito: 'dentro', rel, slug: fluxo.slug };
  const isentos = globsIsentos({ slug: fluxo.slug, design: null, plano: null, globsDoPlano: globs });
  if (!foraDoPlano(rel, isentos)) return { veredito: 'isento', rel, slug: fluxo.slug };
  return { veredito: 'fora', rel, slug: fluxo.slug };
}

function main() {
  const cwd = valorDe('--cwd');
  const arquivo = valorDe('--arquivo');
  if (!cwd || !arquivo) {
    process.stderr.write('uso: node scripts/desvio-do-plano.cjs --cwd <dir> --arquivo <caminho>\n');
    process.exit(2);
  }
  try {
    process.stdout.write(`${JSON.stringify(veredito(path.resolve(cwd), arquivo))}\n`);
  } catch (e) {
    process.stderr.write(`desvio-do-plano: ${e.message}\n`);
    process.exit(1);
  }
}

if (require.main === module) main();

module.exports = { veredito, foraDoPlano };
