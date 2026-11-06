#!/usr/bin/env node
// @categoria: sensor
/**
 * Catálogo de funções para a passada de duplicata semântica do `enxugar` (D7, D9, D10 do design
 * lgpd-e-duplicata). Fase mecânica: não decide nada, só lista, mede e confere.
 *
 * Subcomandos:
 *   listar   [--raiz <dir>] [--contexto N (padrão 15)] [--incluir-testes]
 *            JSON: [{arquivo, linha, nome, assinatura, contexto, linguagem}]. `arquivo` é relativo
 *            à raiz, com `/`; `linha` é 1-based; `contexto` são as N linhas seguintes à definição.
 *   maiores  [--raiz <dir>] [--top N (padrão 10)]
 *            Linhas `<n> linhas  <caminho>`, da maior para a menor (contexto, não achado: D10).
 *   complexas [--raiz <dir>] [--top N (padrão 10)]
 *            Complexidade cognitiva e ciclomática por função JS/TS e Dart, da maior para a menor,
 *            com as 3 maiores contribuições de cada uma e o que não foi medido (design
 *            complexidade-por-funcao). Medida aproximada, por leitura de texto: scripts/lib/complexidade.cjs.
 *   separar  --catalogo <arq-categorizado.json> --saida <dir> [--minimo 3]
 *            Grava <dir>/<categoria>.json só para categorias com ao menos --minimo funções.
 *            Categoria agrupa pela caixa baixa. Stderr: `sem categoria: N` quando há entrada
 *            sem category. Exit 1, sem gravar nada, se <dir> já tem .json ou se duas categorias
 *            viram o mesmo nome de arquivo.
 *   conferir --catalogo <catalogo.json> --grupos <grupos.json>
 *            Confere cada função do grupo contra o catálogo (arquivo, nome e linha iguais).
 *            Stdout: só os grupos válidos. Stderr: `arquivo:linha nome` de cada função inválida,
 *            `grupo N: ...` para grupo com menos de 2 funções distintas e para CONSOLIDATE cujo
 *            survivor não é função do grupo (esse grupo sai no stdout rebaixado para INVESTIGATE).
 *            Exit 1 se houver função inválida ou grupo com menos de 2 distintas; o rebaixamento
 *            sozinho sai 0 — leia o stderr.
 *
 * Arquivos: `git ls-files` (respeita .gitignore) quando a raiz está num repo git; senão varre a
 * pasta. Só extensões da tabela de hooks/lib/definicoes.cjs. Gerados (node_modules, build, dist,
 * .dart_tool, *.g.dart, *.freezed.dart) saem sempre. Testes (*.test.*, *.spec.*, __tests__/, test/,
 * tests/, *_test.dart) saem salvo --incluir-testes.
 *
 * Só node:fs, node:path e node:child_process (execFileSync, sem shell).
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { EXTENSOES, casar } = require(path.join(__dirname, '..', 'hooks', 'lib', 'definicoes.cjs'));
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));
const { medirArquivo } = require(path.join(__dirname, 'lib', 'complexidade.cjs'));

const DIRETORIOS_GERADOS = new Set(['node_modules', 'build', 'dist', '.dart_tool', '.git']);
const MAX_CAMINHO_ASSINATURA = 200;

const USO = `uso: node scripts/catalogo-funcoes.cjs <listar|maiores|complexas|separar|conferir> [opções]
  listar   [--raiz <dir>] [--contexto N] [--incluir-testes]
  maiores  [--raiz <dir>] [--top N]
  complexas [--raiz <dir>] [--top N]
  separar  --catalogo <arq> --saida <dir> [--minimo 3]
  conferir --catalogo <arq> --grupos <arq>
`;

class ErroDeUso extends Error {}

function opcoes(args) {
  const o = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (!a.startsWith('--')) throw new ErroDeUso(`argumento solto: ${a}`);
    const chave = a.slice(2);
    if (chave === 'incluir-testes') {
      o[chave] = true;
      continue;
    }
    const valor = args[i + 1];
    if (valor === undefined || valor.startsWith('--')) throw new ErroDeUso(`falta valor para --${chave}`);
    o[chave] = valor;
    i++;
  }
  return o;
}

function inteiro(valor, padrao, nome) {
  if (valor === undefined) return padrao;
  if (!/^\d+$/.test(valor)) throw new ErroDeUso(`--${nome} pede inteiro não negativo, veio: ${valor}`);
  return Number(valor);
}

function normal(caminho) {
  return String(caminho ?? '').split('\\').join('/');
}

function repoGit(raiz) {
  try {
    const saida = execFileSync(caminhoExecutavel('git'), ['rev-parse', '--is-inside-work-tree'], {
      cwd: raiz,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 10000,
      windowsHide: true,
    });
    return saida.trim() === 'true';
  } catch {
    return false;
  }
}

function arquivosDoGit(raiz) {
  const saida = execFileSync(caminhoExecutavel('git'), ['-c', 'core.quotePath=false', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], {
    cwd: raiz,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
    maxBuffer: 256 * 1024 * 1024,
    windowsHide: true,
  });
  return saida.split('\0').filter(Boolean).map(normal);
}

function varrerPasta(dir, base, saida) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const abs = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (!DIRETORIOS_GERADOS.has(ent.name)) varrerPasta(abs, base, saida);
    } else if (ent.isFile()) {
      saida.push(normal(path.relative(base, abs)));
    }
  }
  return saida;
}

function ehGerado(rel) {
  const partes = rel.split('/');
  if (partes.slice(0, -1).some((p) => DIRETORIOS_GERADOS.has(p))) return true;
  const base = partes[partes.length - 1];
  return /\.g\.dart$/.test(base) || /\.freezed\.dart$/.test(base);
}

function ehTeste(rel) {
  const partes = rel.split('/');
  const base = partes[partes.length - 1];
  if (/\.(test|spec)\.[^.]+$/.test(base)) return true;
  if (/_test\.dart$/.test(base)) return true;
  return partes.slice(0, -1).some((p) => p === '__tests__' || p === 'test' || p === 'tests');
}

/** Arquivos da raiz que entram na varredura: extensão conhecida, sem gerado e (salvo flag) sem teste. */
function candidatos(raiz, incluirTestes) {
  const todos = repoGit(raiz) ? arquivosDoGit(raiz) : varrerPasta(raiz, raiz, []);
  return todos
    .filter((rel) => EXTENSOES[path.extname(rel).toLowerCase()])
    .filter((rel) => !ehGerado(rel))
    .filter((rel) => incluirTestes || !ehTeste(rel))
    .sort();
}

function definicoesDoArquivo(raiz, rel, contextoN) {
  const linguagem = EXTENSOES[path.extname(rel).toLowerCase()];
  let texto;
  try {
    texto = fs.readFileSync(path.join(raiz, rel), 'utf8');
  } catch {
    return [];
  }
  const linhas = texto.split(/\r?\n/);
  const conjuntos = linguagem === 'dart' || linguagem === 'js' ? ['topo', 'metodo'] : ['topo'];
  const achados = [];
  linhas.forEach((linha, i) => {
    for (const conjunto of conjuntos) {
      const nome = casar(linha, linguagem, conjunto);
      if (!nome) continue;
      achados.push({
        linha: i + 1,
        nome,
        assinatura: linha.trim().slice(0, MAX_CAMINHO_ASSINATURA),
        contexto: linhas.slice(i + 1, i + 1 + contextoN).join('\n'),
        linguagem,
      });
      break;
    }
  });
  return achados;
}

function listar(raiz, contextoN, incluirTestes) {
  const catalogo = [];
  for (const rel of candidatos(raiz, incluirTestes)) {
    for (const d of definicoesDoArquivo(raiz, rel, contextoN)) {
      catalogo.push({ arquivo: rel, ...d });
    }
  }
  return catalogo;
}

/** Quebras de linha em bytes, o mesmo número que `wc -l` devolve (arquivo sem quebra final conta menos 1). */
function contarQuebras(buf) {
  let n = 0;
  for (let i = 0; i < buf.length; i++) if (buf[i] === 10) n++;
  return n;
}

function maiores(raiz, top) {
  const medidos = [];
  for (const rel of candidatos(raiz, false)) {
    let buf;
    try {
      buf = fs.readFileSync(path.join(raiz, rel));
    } catch {
      continue;
    }
    medidos.push({ rel, n: contarQuebras(buf) });
  }
  medidos.sort((a, b) => b.n - a.n || (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
  return medidos.slice(0, top);
}

/** Funções JS/TS e Dart medidas, da maior cognitiva para a menor, e o que ficou sem medida (D6). */
function complexas(raiz, top) {
  const medidas = [];
  const semChaves = {};
  const naoMedidas = [];
  for (const rel of candidatos(raiz, false)) {
    const linguagem = EXTENSOES[path.extname(rel).toLowerCase()];
    const defs = definicoesDoArquivo(raiz, rel, 0);
    if (!defs.length) continue;
    if (linguagem !== 'js' && linguagem !== 'dart') {
      semChaves[linguagem] = (semChaves[linguagem] || 0) + defs.length;
      continue;
    }
    let texto;
    try {
      texto = fs.readFileSync(path.join(raiz, rel), 'utf8');
    } catch {
      naoMedidas.push({ rel, linha: 1, nome: '(arquivo)', motivo: 'arquivo ilegível' });
      continue;
    }
    const r = medirArquivo(texto, linguagem, defs);
    for (const m of r.medidas) medidas.push({ rel, ...m });
    for (const m of r.naoMedidas) naoMedidas.push({ rel, ...m });
  }
  medidas.sort((a, b) => b.cognitiva - a.cognitiva || b.ciclomatica - a.ciclomatica || (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0) || a.linha - b.linha);
  return { medidas: medidas.slice(0, top), semChaves, naoMedidas };
}

function lerJson(arquivo, nome) {
  try {
    return JSON.parse(fs.readFileSync(arquivo, 'utf8'));
  } catch (e) {
    throw new Error(`não consegui ler ${nome} (${arquivo}): ${e.message}`);
  }
}

function separar(catalogoArq, saida, minimo) {
  const entradas = lerJson(catalogoArq, '--catalogo');
  if (!Array.isArray(entradas)) throw new Error('--catalogo tem de ser um array');
  // Categoria agrupa pela caixa baixa: "Auth" e "auth" são a mesma, e em disco que não
  // distingue caixa (Windows, macOS) os dois arquivos se sobrescreviam.
  const categorias = new Map();
  let semCategoria = 0;
  for (const e of entradas) {
    if (!e || typeof e.category !== 'string' || e.category.trim() === '') {
      semCategoria++;
      continue;
    }
    const k = e.category.trim().toLowerCase();
    if (!categorias.has(k)) categorias.set(k, { nome: e.category.trim(), funcoes: [] });
    categorias.get(k).funcoes.push(e);
  }
  if (fs.existsSync(saida)) {
    const velhos = fs.readdirSync(saida).filter((n) => n.toLowerCase().endsWith('.json'));
    if (velhos.length) throw new Error(`--saida ${saida} já tem ${velhos.length} .json de outra rodada; use uma pasta vazia`);
  }
  // Nome de arquivo de cada categoria validado ANTES de gravar: colisão no meio deixava a
  // pasta com parte dos arquivos, e a rodada seguinte caía na recusa de pasta suja.
  const usados = new Map();
  const aGravar = [];
  for (const { nome, funcoes } of categorias.values()) {
    if (funcoes.length < minimo) continue;
    const base = nome.replace(/[^\p{L}\p{N}_-]+/gu, '-').replace(/^-+|-+$/g, '') || 'sem-nome';
    const bk = base.toLowerCase();
    if (usados.has(bk)) throw new Error(`categorias "${usados.get(bk)}" e "${nome}" viram o mesmo arquivo ${base}.json`);
    usados.set(bk, nome);
    aGravar.push({ base, funcoes });
  }
  fs.mkdirSync(saida, { recursive: true });
  for (const { base, funcoes } of aGravar) {
    fs.writeFileSync(path.join(saida, `${base}.json`), JSON.stringify(funcoes, null, 2) + '\n');
  }
  const gravadas = aGravar.length;
  return { gravadas, semCategoria };
}

function conferir(catalogoArq, gruposArq) {
  const catalogo = lerJson(catalogoArq, '--catalogo');
  const grupos = lerJson(gruposArq, '--grupos');
  if (!Array.isArray(catalogo)) throw new Error('--catalogo tem de ser um array');
  if (!Array.isArray(grupos)) throw new Error('--grupos tem de ser um array');
  const chave = (arquivo, nome, linha) => `${normal(arquivo)}\u0000${nome}\u0000${Number(linha)}`;
  const existentes = new Set(catalogo.map((e) => chave(e.arquivo, e.nome, e.linha)));
  const validos = [];
  const avisos = [];
  let todasValidas = true;
  grupos.forEach((g, gi) => {
    const funcoes = g && Array.isArray(g.functions) ? g.functions : [];
    let ok = true;
    const distintas = new Set();
    for (const f of funcoes) {
      const k = f ? chave(f.file, f.name, f.line) : '';
      if (!f || !existentes.has(k)) {
        avisos.push(`${normal(f && f.file)}:${f && f.line} ${f && f.name}`);
        ok = false;
      } else distintas.add(k);
    }
    // Duplicata pede duas funções diferentes: grupo de uma só, ou a mesma citada duas
    // vezes com barra trocada (lib/a.dart e lib\a.dart), não compara nada.
    if (ok && distintas.size < 2) {
      avisos.push(`grupo ${gi + 1}: ${distintas.size} função distinta; duplicata pede 2 ou mais`);
      ok = false;
    }
    if (!ok) {
      todasValidas = false;
      return;
    }
    // CONSOLIDATE cujo survivor não é o nome de uma função do grupo não diz o que manter:
    // vira INVESTIGATE, com aviso, em vez de virar achado duplicar: sem sobrevivente.
    const rec = g.recommendation;
    if (rec && rec.action === 'CONSOLIDATE' && !funcoes.some((f) => f.name === rec.survivor)) {
      avisos.push(`grupo ${gi + 1}: survivor "${rec.survivor}" não é função do grupo; rebaixado para INVESTIGATE`);
      validos.push({ ...g, recommendation: { ...rec, action: 'INVESTIGATE' } });
      return;
    }
    validos.push(g);
  });
  return { validos, avisos, todasValidas };
}

function principal(argv) {
  const [sub, ...resto] = argv;
  const subs = ['listar', 'maiores', 'complexas', 'separar', 'conferir'];
  if (!subs.includes(sub)) {
    process.stderr.write(USO);
    process.exitCode = 1;
    return;
  }
  const o = opcoes(resto);
  if (sub === 'listar') {
    const raiz = path.resolve(o.raiz || '.');
    const contextoN = inteiro(o.contexto, 15, 'contexto');
    process.stdout.write(JSON.stringify(listar(raiz, contextoN, Boolean(o['incluir-testes']))) + '\n');
    return;
  }
  if (sub === 'maiores') {
    const raiz = path.resolve(o.raiz || '.');
    const top = inteiro(o.top, 10, 'top');
    const linhas = maiores(raiz, top).map((m) => `${m.n} linhas  ${m.rel}`);
    process.stdout.write(linhas.map((l) => l + '\n').join(''));
    return;
  }
  if (sub === 'complexas') {
    const raiz = path.resolve(o.raiz || '.');
    const top = inteiro(o.top, 10, 'top');
    const { medidas, semChaves, naoMedidas } = complexas(raiz, top);
    const saida = [];
    for (const m of medidas) {
      saida.push(`${m.cognitiva} cognitiva  ${m.ciclomatica} ciclomática  ${m.rel}:L${m.linha} ${m.nome}`);
      for (const c of m.contribuicoes.slice(0, 3)) saida.push(`    +${c.valor} L${c.linha} ${c.rotulo}`);
    }
    for (const ling of Object.keys(semChaves).sort()) saida.push(`não medido: ${semChaves[ling]} função(ões) ${ling} — linguagem sem chaves`);
    for (const m of naoMedidas) saida.push(`não medido: ${m.rel}:L${m.linha} ${m.nome} — ${m.motivo}`);
    saida.push('medida aproximada (leitura de texto, sem parser): confira no código antes de concluir');
    process.stdout.write(saida.map((l) => l + '\n').join(''));
    return;
  }
  if (sub === 'separar') {
    if (!o.catalogo || !o.saida) throw new ErroDeUso('separar pede --catalogo e --saida');
    const minimo = inteiro(o.minimo, 3, 'minimo');
    const { gravadas, semCategoria } = separar(path.resolve(o.catalogo), path.resolve(o.saida), minimo);
    process.stdout.write(`categorias gravadas: ${gravadas}\n`);
    if (semCategoria) process.stderr.write(`sem categoria: ${semCategoria} entrada(s) ignorada(s)\n`);
    return;
  }
  // conferir
  if (!o.catalogo || !o.grupos) throw new ErroDeUso('conferir pede --catalogo e --grupos');
  const { validos, avisos, todasValidas } = conferir(path.resolve(o.catalogo), path.resolve(o.grupos));
  for (const a of avisos) process.stderr.write(`${a}\n`);
  process.stdout.write(JSON.stringify(validos, null, 2) + '\n');
  process.exitCode = todasValidas ? 0 : 1;
}

try {
  principal(process.argv.slice(2));
} catch (e) {
  if (e instanceof ErroDeUso) {
    process.stderr.write(`${e.message}\n${USO}`);
  } else {
    process.stderr.write(`erro: ${e.message}\n`);
  }
  process.exitCode = 1;
}
