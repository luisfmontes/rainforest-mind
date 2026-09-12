#!/usr/bin/env node
/**
 * Confere duplicação byte a byte e homônimos de função dentro do plugin.
 *
 * POR QUE EXISTE (2026-09-12, análise do marketplace de plugins de um terceiro,
 * autor autorizou a leitura): `ch_mcp.py` era byte a byte idêntico entre duas
 * skills — cópia de quem tinha uma funcionando, nunca reconciliada — e 20
 * funções homônimas se repetiam entre os helpers do mesmo plugin. Nenhum dos
 * dois é bug de lógica: é entropia de cópia, e cresce em silêncio porque
 * ninguém vai abrir dois arquivos de 400 linhas para comparar byte a byte.
 * Duplicata idêntica é certeza — vira falha (exit 2). Homônimo é só inventário
 * — quem decide se é problema é quem lê a lista, então sai sempre 0.
 *
 * Uso:
 *   node scripts/conferir-duplicacao.cjs [--raiz <dir>] [--json]
 *   node scripts/conferir-duplicacao.cjs --funcoes [--raiz <dir>] [--json]
 *
 * Sem `--raiz`, usa o toplevel do git do cwd. Ignora `.git/`, `node_modules/`,
 * `fixtures/`, qualquer diretório dentro de `.claude/worktrees/` e arquivos
 * vazios (hash de conteúdo vazio não significa cópia de nada).
 *
 * Protege contra: dois ou mais arquivos byte a byte idênticos dentro do
 * plugin, fora de fixture declarada — o sintoma que motivou o script.
 * Não protege contra: função com nome diferente e lógica idêntica, duplicação
 * PARCIAL (um trecho copiado dentro de um arquivo maior), ou qualquer arquivo
 * fora da árvore de `--raiz`.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIRS_IGNORADOS = new Set(['.git', 'node_modules', 'fixtures']);

function resolverRaizPadrao() {
  const r = spawnSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' });
  if (r.status === 0 && r.stdout && r.stdout.trim()) return r.stdout.trim();
  return process.cwd();
}

function relPosix(raiz, alvo) {
  return path.relative(raiz, alvo).split(path.sep).join('/');
}

function deveIgnorarDir(raiz, caminhoAbs, nome) {
  if (DIRS_IGNORADOS.has(nome)) return true;
  const rel = relPosix(raiz, caminhoAbs);
  return rel === '.claude/worktrees' || rel.startsWith('.claude/worktrees/');
}

/** Varre a árvore a partir de `raiz` e agrupa arquivos por hash sha256 do conteúdo. */
function agruparPorHash(raiz) {
  const porHash = new Map();
  const pilha = [raiz];
  while (pilha.length) {
    const dir = pilha.pop();
    let entradas;
    try {
      entradas = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue; // sem permissão de leitura: não é achado deste script
    }
    for (const ent of entradas) {
      const caminhoAbs = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (deveIgnorarDir(raiz, caminhoAbs, ent.name)) continue;
        pilha.push(caminhoAbs);
        continue;
      }
      if (!ent.isFile()) continue; // symlink e afins: fora de escopo
      let buf;
      try {
        buf = fs.readFileSync(caminhoAbs);
      } catch {
        continue;
      }
      if (buf.length === 0) continue; // arquivo vazio não é duplicata de nada
      const hash = crypto.createHash('sha256').update(buf).digest('hex');
      const rel = relPosix(raiz, caminhoAbs);
      if (!porHash.has(hash)) porHash.set(hash, []);
      porHash.get(hash).push(rel);
    }
  }
  const grupos = [];
  for (const arquivos of porHash.values()) {
    if (arquivos.length < 2) continue;
    arquivos.sort();
    grupos.push(arquivos);
  }
  grupos.sort((a, b) => a[0].localeCompare(b[0]));
  return grupos;
}

/**
 * Nomes declarados como `function <x>(`, `exports.<x> =` ou dentro de
 * `module.exports = { <x> }`. Inventário — não valida se o corpo é igual.
 */
function extrairNomes(conteudo) {
  const nomes = new Set();

  const reFuncao = /(?:^|[\r\n])\s*(?:async\s+)?function\s*\*?\s+([A-Za-z_$][\w$]*)\s*\(/g;
  let m;
  while ((m = reFuncao.exec(conteudo))) nomes.add(m[1]);

  const reExports = /exports\.([A-Za-z_$][\w$]*)\s*=/g;
  while ((m = reExports.exec(conteudo))) nomes.add(m[1]);

  const reModuleExports = /module\.exports\s*=\s*\{([^}]*)\}/g;
  while ((m = reModuleExports.exec(conteudo))) {
    for (const parte of m[1].split(',')) {
      const nome = parte.split(':')[0].trim().replace(/^\.\.\./, '');
      if (/^[A-Za-z_$][\w$]*$/.test(nome)) nomes.add(nome);
    }
  }

  return nomes;
}

function coletarHomonimos(raiz) {
  const dirScripts = path.join(raiz, 'scripts');
  let arquivos;
  try {
    arquivos = fs.readdirSync(dirScripts).filter((f) => f.endsWith('.cjs')).sort();
  } catch {
    arquivos = [];
  }

  const porNome = new Map();
  for (const f of arquivos) {
    let conteudo;
    try {
      conteudo = fs.readFileSync(path.join(dirScripts, f), 'utf8');
    } catch {
      continue;
    }
    for (const nome of extrairNomes(conteudo)) {
      if (!porNome.has(nome)) porNome.set(nome, new Set());
      porNome.get(nome).add(`scripts/${f}`);
    }
  }

  return [...porNome.entries()]
    .filter(([, arqs]) => arqs.size >= 2)
    .map(([nome, arqs]) => ({ nome, arquivos: [...arqs].sort() }))
    .sort((a, b) => a.nome.localeCompare(b.nome));
}

function rodarDuplicacao(raiz, json) {
  const grupos = agruparPorHash(raiz);
  if (json) {
    console.log(JSON.stringify({ raiz, duplicados: grupos }, null, 2));
    process.exit(grupos.length ? 2 : 0);
    return;
  }
  if (!grupos.length) {
    console.log('CONFERIDO — nenhuma duplicata byte a byte');
    process.exit(0);
    return;
  }
  for (const g of grupos) console.log(g.join(' == '));
  process.exit(2);
}

function rodarFuncoes(raiz, json) {
  const homonimos = coletarHomonimos(raiz);
  if (json) {
    console.log(JSON.stringify({ raiz, homonimos }, null, 2));
    process.exit(0);
    return;
  }
  if (!homonimos.length) {
    console.log('nenhum nome homonimo entre scripts/*.cjs');
    process.exit(0);
    return;
  }
  for (const h of homonimos) console.log(`${h.nome}: ${h.arquivos.join(', ')}`);
  process.exit(0);
}

function main() {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const funcoes = args.includes('--funcoes');
  const idxRaiz = args.indexOf('--raiz');
  const raizArg = idxRaiz !== -1 ? args[idxRaiz + 1] : null;
  const raiz = path.resolve(raizArg || resolverRaizPadrao());

  if (funcoes) return rodarFuncoes(raiz, json);
  return rodarDuplicacao(raiz, json);
}

if (require.main === module) main();
module.exports = { agruparPorHash, coletarHomonimos, extrairNomes, resolverRaizPadrao };
