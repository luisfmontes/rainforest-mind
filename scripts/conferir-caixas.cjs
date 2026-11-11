#!/usr/bin/env node
// @categoria: sensor
/**
 * Caixa de bateria que copia um script do repositorio sem copiar a lib que ele
 * carrega por `require`.
 *
 * O INCIDENTE. A classe derrubou o CI em 2026-09-12, 2026-10-05, 2026-10-19 e
 * 2026-11-09: a bateria monta a caixa com `cp` de um script e esquece o `.cjs`
 * que o script exige. Em umas baterias o `require` quebra e a bateria sai
 * "pulada (erro de execucao)" com exit 0; em outras, o CI acusa 25 min depois.
 *
 * O QUE FAZ. Estatico, sem executar bateria: le `hooks/testa-*.sh` e
 * `scripts/testa-*.sh` da raiz, monta o conjunto copiado (linhas com `cp`, laco
 * `for <v> in ...; do` de uma linha, `cp -r` de pasta) e confere os `require`
 * de cada `.cjs` copiado, no topo e dentro de funcao.
 *
 * Linha `# caixa-sem: <caminho> — <motivo>` na bateria declara que a ausencia e
 * intencional (um `require` tardio que degrada para aviso). Sem o motivo, nao vale.
 *
 * Com `--base <ref>` (D6), roda a mesma analise sobre a arvore de `hooks/` e
 * `scripts/` do commit <ref> e reprova so o achado que nao existe la.
 *
 * Uso:   node scripts/conferir-caixas.cjs [--raiz <dir>] [--base <ref>]
 * Saida: 0 sem achado (novo), 1 com achado, 2 uso.
 *
 * Design: docs/rainforest/design/caixa-confere-requires.md (D1 a D6).
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));

const GIT = caminhoExecutavel('git');

const USO = 'uso: node scripts/conferir-caixas.cjs [--raiz <dir>] [--base <ref>]';

const RE_CP = /(^|[\s;&(|])cp\s/;
const RE_TRECHO = /\$\{?[A-Za-z_]+\}?\/((?:scripts|hooks)\/[^"' ]+\.cjs)/g;
const RE_FOR = /^\s*for\s+([A-Za-z_]\w*)\s+in\s+([^;]*);\s*do\b(.*)$/;
const RE_DONE = /(^|[\s;])done\s*$/;
const RE_CAIXA_SEM = /^\s*#\s*caixa-sem:\s*(\S+)\s+(?:—|-)\s*(\S.*)$/;
const RE_REQ_JOIN = /require\(path\.join\(__dirname,\s*([^)]*)\)\)/g;
const RE_REQ_REL = /require\(\s*['"](\.{1,2}\/[^'"]+)['"]\s*\)/g;
const RE_PASTA_INTEIRA = /(?:^|\/)(scripts|hooks)$/;
const RE_PASTA_LIB = /(?:^|\/)((?:scripts|hooks)\/lib)$/;

function uso() {
  console.error(USO);
  process.exit(2);
}

function ehPasta(p) {
  return fs.existsSync(p) && fs.statSync(p).isDirectory();
}

function ehArquivo(p) {
  return fs.existsSync(p) && fs.statSync(p).isFile();
}

function lerArgs(argv) {
  let raiz = path.resolve(__dirname, '..');
  let base = null;
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    if ((flag !== '--raiz' && flag !== '--base') || i + 1 >= argv.length) uso();
    if (flag === '--raiz') raiz = path.resolve(argv[i + 1]);
    else base = argv[i + 1];
  }
  if (!ehPasta(raiz)) uso();
  return { raiz, base };
}

// D6: extrai hooks/ e scripts/ do commit <ref> para uma pasta temporaria.
// Qualquer falha de git ou tar sai com exit 2 (nunca vira "0 achados").
function extrairBase(raiz, ref) {
  const rev = spawnSync(GIT, ['-C', raiz, 'rev-parse', '--verify', `${ref}^{commit}`], { encoding: 'utf8' });
  if (rev.error || rev.status !== 0) {
    console.error(`conferir-caixas: base '${ref}' não existe`);
    process.exit(2);
  }
  const arc = spawnSync(GIT, ['-C', raiz, 'archive', '--format=tar', ref, 'hooks', 'scripts'], {
    maxBuffer: 512 * 1024 * 1024,
  });
  if (arc.error || arc.status !== 0) {
    console.error(`conferir-caixas: não deu para ler hooks/ e scripts/ de '${ref}'`);
    process.exit(2);
  }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'conferir-base-'));
  const tar = spawnSync('tar', ['-x', '-f', '-', '-C', dir], { input: arc.stdout });
  if (tar.error || tar.status !== 0) {
    fs.rmSync(dir, { recursive: true, force: true });
    console.error(`conferir-caixas: não deu para extrair a base '${ref}'`);
    process.exit(2);
  }
  return dir;
}

function listarBaterias(raiz) {
  const achadas = [];
  for (const pasta of ['hooks', 'scripts']) {
    const dir = path.join(raiz, pasta);
    if (!ehPasta(dir)) continue;
    for (const nome of fs.readdirSync(dir)) {
      if (/^testa-.*\.sh$/.test(nome) && ehArquivo(path.join(dir, nome))) {
        achadas.push(`${pasta}/${nome}`);
      }
    }
  }
  return achadas.sort();
}

function listarCjs(dir) {
  if (!ehPasta(dir)) return [];
  return fs.readdirSync(dir).filter((n) => n.endsWith('.cjs') && ehArquivo(path.join(dir, n)));
}

// Le a bateria e devolve o conjunto copiado, a pasta inteira copiada (se houver,
// a bateria e pulada) e os caminhos declarados com `caixa-sem` e motivo.
function lerCopia(texto, raiz) {
  const copiados = new Set();
  let pulada = null;
  let laco = null;

  const cp = (linha) => {
    if (!RE_CP.test(linha)) return;
    const tokens = linha.trim().split(/\s+/);
    const i = tokens.indexOf('cp');
    const resto = i < 0 ? [] : tokens.slice(i + 1);
    const opcoes = resto.filter((t) => t.startsWith('-'));
    const args = resto
      .filter((t) => !t.startsWith('-'))
      .map((t) => t.replace(/["']/g, '').replace(/\/+$/, '').replace(/\/\.$/, ''));
    const recursivo = opcoes.some((o) => /^-[a-zA-Z]*[rRa]/.test(o) || o === '--recursive' || o === '--archive');
    if (recursivo) {
      const origens = args.slice(0, -1);
      for (const o of origens) {
        const inteira = RE_PASTA_INTEIRA.exec(o);
        if (inteira) pulada = pulada || inteira[1];
      }
      for (const o of origens) {
        const lib = RE_PASTA_LIB.exec(o);
        if (lib) {
          for (const nome of listarCjs(path.join(raiz, lib[1]))) copiados.add(`${lib[1]}/${nome}`);
        }
      }
    }
    for (const m of linha.matchAll(RE_TRECHO)) copiados.add(m[1]);
  };

  const trata = (corpo) => {
    if (laco === null) return cp(corpo);
    let c = corpo;
    const fim = RE_DONE.exec(c);
    if (fim) c = c.slice(0, fim.index);
    const re = new RegExp(`\\$\\{?${laco.v}\\}?(?![A-Za-z_])`, 'g');
    for (const palavra of laco.palavras) cp(c.replace(re, () => palavra));
    if (fim) laco = null;
  };

  for (const linha of texto.split(/\r?\n/)) {
    if (/^\s*#/.test(linha)) continue;
    const f = laco === null ? RE_FOR.exec(linha) : null;
    if (f) {
      laco = { v: f[1], palavras: f[2].trim().split(/\s+/) };
      trata(f[3]);
    } else {
      trata(linha);
    }
  }

  const caixaSem = new Set();
  for (const linha of texto.split(/\r?\n/)) {
    const m = RE_CAIXA_SEM.exec(linha);
    if (m) caixaSem.add(m[1]);
  }
  return { pulada, copiados, caixaSem };
}

// Os caminhos que o texto de um .cjs carrega por require, relativos a raiz.
function requiresDe(texto, dir) {
  const achados = [];
  for (const m of texto.matchAll(RE_REQ_JOIN)) {
    const partes = m[1].split(',').map((p) => p.trim());
    const literais = partes.map((p) => {
      const q = /^(['"])(.*)\1$/.exec(p);
      return q ? q[2] : null;
    });
    if (literais.some((x) => x === null)) continue;
    achados.push(path.posix.join(dir, ...literais));
  }
  for (const m of texto.matchAll(RE_REQ_REL)) achados.push(path.posix.join(dir, m[1]));
  return achados;
}

function exigidosDe(copiados, raiz) {
  const exigidos = [];
  const porQuem = new Map();
  for (const rel of copiados) {
    const abs = path.join(raiz, rel);
    if (!ehArquivo(abs)) continue;
    const dir = path.posix.dirname(rel);
    for (const alvo of requiresDe(fs.readFileSync(abs, 'utf8'), dir)) {
      if (!alvo.endsWith('.cjs') || alvo.startsWith('../') || !ehArquivo(path.join(raiz, alvo))) continue;
      exigidos.push(alvo);
      if (!porQuem.has(alvo)) porQuem.set(alvo, new Set());
      porQuem.get(alvo).add(rel);
    }
  }
  return { exigidos, porQuem };
}

function conferirBateria(bat, raiz) {
  const texto = fs.readFileSync(path.join(raiz, bat), 'utf8');
  const { pulada, copiados, caixaSem } = lerCopia(texto, raiz);
  if (pulada) return { pulada };
  const { exigidos, porQuem } = exigidosDe(copiados, raiz);
  const faltando = exigidos.filter((c) => !copiados.has(c));
  const achados = [];
  for (const alvo of [...new Set(faltando)].sort()) {
    if (caixaSem.has(alvo)) continue;
    for (const por of [...porQuem.get(alvo)].sort()) {
      achados.push(`falta ${alvo} (exigido por ${por})`);
    }
  }
  return { achados };
}

// Analisa a raiz inteira: `linhas` e a saida na ordem (inclui as puladas),
// `achados` so as linhas de achado, ja formatadas.
function analisar(raiz) {
  const baterias = listarBaterias(raiz);
  const linhas = [];
  const achados = [];
  for (const bat of baterias) {
    const r = conferirBateria(bat, raiz);
    if (r.pulada) {
      linhas.push(`${bat}: pulada (cp -r de ${r.pulada})`);
      continue;
    }
    for (const a of r.achados) {
      const linha = `${bat}: ${a}`;
      linhas.push(linha);
      achados.push(linha);
    }
  }
  return { baterias, linhas, achados };
}

function main() {
  const { raiz, base } = lerArgs(process.argv.slice(2));
  const atual = analisar(raiz);
  if (base === null) {
    for (const l of atual.linhas) console.log(l);
    console.log(`conferir-caixas: ${atual.baterias.length} bateria(s), ${atual.achados.length} achado(s)`);
    process.exitCode = atual.achados.length > 0 ? 1 : 0;
    return;
  }
  const dirBase = extrairBase(raiz, base);
  let daBase;
  try {
    daBase = new Set(analisar(dirBase).achados);
  } finally {
    fs.rmSync(dirBase, { recursive: true, force: true });
  }
  const linhas = atual.achados;
  const novos = linhas.filter((l) => !daBase.has(l));
  for (const l of novos) console.log(l);
  const ja = linhas.length - novos.length;
  console.log(`conferir-caixas: ${atual.baterias.length} bateria(s), ${novos.length} achado(s) novo(s), ${ja} já existente(s) na base`);
  process.exitCode = novos.length > 0 ? 1 : 0;
}

main();
