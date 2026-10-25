#!/usr/bin/env node
// @categoria: sensor
/**
 * Aviso de duplicata de definição na edição (D4 do design 2026-10-24-apoio-ao-dev-lote-3).
 *
 * PostToolUse de Write|Edit|MultiEdit. Lê do texto novo os nomes de definição de topo
 * (JS/TS, Python, ADVPL/TLPP), procura todos os nomes numa chamada só de `git grep -z -F -w`
 * em outro arquivo rastreado e, achando uma definição com o mesmo nome, devolve `additionalContext`
 * curto: "`x` já está definido em `caminho:linha`; reusar antes de duplicar". No máximo 3 nomes.
 *
 * Modelo de ameaça (D7): o hook lê só texto que a própria sessão escreveu e o índice do git.
 * Protege contra duplicar sem saber, não contra quem quer duplicar. Fica fora: nome dinâmico
 * (`module.exports[x]`), definição gerada e repositório sem git. Nunca executa nada do texto lido.
 * Caminho achado que tenha crase, controle, aspas ou mais de 200 caracteres é descartado: o
 * nome de arquivo do repo não chega ao contexto. Cada `git` roda com `core.fsmonitor=false`.
 * Limite conhecido: a definição só é vista nas primeiras 50 ocorrências do nome em cada arquivo.
 *
 * Nunca bloqueia: não imprime `decision` e sai sempre 0. Sem git, fora de repo, timeout,
 * payload inválido ou chave `aviso-duplicata` desligada: sai 0 calado.
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { caminhoExecutavel } = require(path.join(__dirname, 'lib', 'resolver-executavel.cjs'));
const { caminhoReal } = require(path.join(__dirname, 'lib', 'caminho-real.cjs'));

const ORCAMENTO_MS = 3000;
const ORCAMENTO_TOPO_MS = 1000;
const MAX_NOMES = 3;
const MAX_NOMES_BUSCA = 50;
const MAX_POR_ARQUIVO = 50;
const MAX_BUFFER = 4 * 1024 * 1024;
const MAX_CAMINHO = 200;
const IDENTIFICADOR = /^[A-Za-z_$][A-Za-z0-9_$]*$/;
const CAMINHO_SEGURO = /^[\w./ À-ſ-]+$/;

const EXTENSOES = {
  '.js': 'js', '.cjs': 'js', '.mjs': 'js', '.ts': 'js', '.tsx': 'js', '.jsx': 'js',
  '.py': 'py',
  '.prw': 'advpl', '.prx': 'advpl', '.tlpp': 'advpl', '.ch': 'advpl',
};

// Definição de topo por linguagem. JS e Python só olham a coluna zero (topo do arquivo); ADVPL
// aceita recuo, porque o fonte costuma vir indentado dentro de bloco.
const REGRAS = {
  js: [
    /^(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s+([\w$]+)/,
    /^(?:export\s+)?(?:const|let|var)\s+([\w$]+)\s*=\s*(?:async\b|\()/,
    /^(?:export\s+)?class\s+([\w$]+)/,
    /^exports\.([\w$]+)\s*=/,
  ],
  py: [/^(?:async\s+)?def\s+(\w+)/, /^class\s+(\w+)/],
  advpl: [/^\s*(?:user\s+function|static\s+function|function|class)\s+(\w+)/i],
};

function nomeDaLinha(linha, tipo) {
  for (const re of REGRAS[tipo]) {
    const m = re.exec(linha);
    if (m) return m[1];
  }
  return null;
}

function textoNovo(ti) {
  if (typeof ti.content === 'string') return ti.content;
  if (typeof ti.new_string === 'string') return ti.new_string;
  if (Array.isArray(ti.edits)) {
    return ti.edits.map((e) => (e && typeof e.new_string === 'string' ? e.new_string : '')).join('\n');
  }
  return '';
}

// Nomes de definição válidos. Nome que não casa com identificador é descartado antes de qualquer git.
function nomesDoTexto(texto, tipo) {
  const nomes = new Map();
  for (const linha of texto.split(/\r?\n/)) {
    const nome = nomeDaLinha(linha, tipo);
    if (!nome || !IDENTIFICADOR.test(nome)) continue;
    const chave = tipo === 'advpl' ? nome.toLowerCase() : nome;
    if (!nomes.has(chave)) nomes.set(chave, nome);
  }
  return [...nomes.values()];
}

function caminhoSeguro(caminho) {
  return caminho.length <= MAX_CAMINHO && CAMINHO_SEGURO.test(caminho);
}

function mesmoArquivo(a, b) {
  return process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;
}

// Uma chamada de git grep para todos os nomes. Com -z cada registro vem como caminho\0linha\0conteúdo,
// sem aspas nem escape. Primeira definição de cada nome em outro arquivo rastreado; linha de uso não conta.
function acharDefinicoes(gitTop, nomes, tipo, editados, restante) {
  const args = ['-c', 'core.fsmonitor=false', '-c', 'core.quotePath=false', 'grep', '-z', '-n', '-w', '-F',
    ...(tipo === 'advpl' ? ['-i'] : []), `--max-count=${MAX_POR_ARQUIVO}`];
  for (const nome of nomes) args.push('-e', nome);
  args.push('--');
  let saida;
  try {
    saida = execFileSync(caminhoExecutavel('git'), args, {
      cwd: gitTop,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: restante,
      maxBuffer: MAX_BUFFER,
      windowsHide: true,
    });
  } catch {
    return new Map();
  }
  const chave = (n) => (tipo === 'advpl' ? n.toLowerCase() : n);
  const pedidos = new Map(nomes.map((n) => [chave(n), n]));
  const achados = new Map();
  for (const registro of saida.split('\n')) {
    const partes = registro.replace(/\r$/, '').split('\0');
    if (partes.length < 3) continue;
    const [caminho, num, ...resto] = partes;
    const achado = nomeDaLinha(resto.join('\0'), tipo);
    if (!achado) continue;
    const nome = pedidos.get(chave(achado));
    if (!nome || achados.has(nome)) continue;
    if (!caminhoSeguro(caminho) || editados.some((e) => mesmoArquivo(caminho, e))) continue;
    achados.set(nome, { caminho, linha: Number(num) });
  }
  return achados;
}

// Rev-parse próprio, com timeout e sem fsmonitor: o hook não herda o toplevel de outra biblioteca.
function topo(cwd, timeout) {
  try {
    return execFileSync(caminhoExecutavel('git'), ['-c', 'core.fsmonitor=false', 'rev-parse', '--show-toplevel'], {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout,
      windowsHide: true,
    }).trim() || null;
  } catch {
    return null;
  }
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0);
  }
  if (!ev || typeof ev !== 'object' || !ev.cwd) process.exit(0);
  const ti = ev.tool_input && typeof ev.tool_input === 'object' ? ev.tool_input : {};
  if (typeof ti.file_path !== 'string' || !ti.file_path) process.exit(0);

  const tipo = EXTENSOES[path.extname(ti.file_path).toLowerCase()];
  if (!tipo) process.exit(0);

  // Nomes antes do git: edição sem definição de topo não sobe processo nenhum.
  const nomes = nomesDoTexto(textoNovo(ti), tipo).slice(0, MAX_NOMES_BUSCA);
  if (nomes.length === 0) process.exit(0);

  const fim = Date.now() + ORCAMENTO_MS;
  const gitTop = topo(ev.cwd, ORCAMENTO_TOPO_MS);
  if (!gitTop) process.exit(0);
  try {
    if (!require(path.join(__dirname, 'lib', 'config.cjs')).ligado('aviso-duplicata', { projeto: gitTop })) process.exit(0);
  } catch {}

  const restante = fim - Date.now();
  if (restante <= 0) process.exit(0);

  // O próprio arquivo tem dois nomes: o real (resolve 8.3 do cwd e junction) e o relativo ao
  // toplevel sem resolver (a junction rastreada no repo aparece assim no git grep). Qualquer um casa.
  const absoluto = path.resolve(ev.cwd, ti.file_path);
  const editados = [
    path.relative(caminhoReal(gitTop), caminhoReal(absoluto)).split(path.sep).join('/'),
    path.relative(gitTop, absoluto).split(path.sep).join('/'),
  ];
  const encontrados = acharDefinicoes(gitTop, nomes, tipo, editados, restante);
  const achados = [];
  for (const nome of nomes) {
    const a = encontrados.get(nome);
    if (a && achados.length < MAX_NOMES) achados.push({ nome, ...a });
  }

  if (achados.length === 0) process.exit(0);

  const texto = achados
    .map((a) => `\`${a.nome}\` já está definido em \`${a.caminho}:${a.linha}\`; reusar antes de duplicar`)
    .join('\n');
  fs.writeSync(1, JSON.stringify({ hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: texto } }) + '\n');
  process.exit(0);
}

try {
  main();
} catch {
  process.exit(0);
}
process.exit(0);
