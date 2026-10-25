#!/usr/bin/env node
// @categoria: sensor
/**
 * Aviso de duplicata de definição na edição (D4 do design 2026-10-24-apoio-ao-dev-lote-3).
 *
 * PostToolUse de Write|Edit|MultiEdit. Lê do texto novo os nomes de definição de topo
 * (JS/TS, Python, ADVPL/TLPP), procura cada nome com `git grep -w` em outro arquivo rastreado
 * e, achando uma definição com o mesmo nome, devolve `additionalContext` curto:
 * "`x` já está definido em `caminho:linha`; reusar antes de duplicar". No máximo 3 nomes.
 *
 * Modelo de ameaça (D7): o hook lê só texto que a própria sessão escreveu e o índice do git.
 * Protege contra duplicar sem saber, não contra quem quer duplicar. Fica fora: nome dinâmico
 * (`module.exports[x]`), definição gerada e repositório sem git. Nunca executa nada do texto lido.
 *
 * Nunca bloqueia: não imprime `decision` e sai sempre 0. Sem git, fora de repo, timeout,
 * payload inválido ou chave `aviso-duplicata` desligada: sai 0 calado.
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { caminhoExecutavel } = require(path.join(__dirname, 'lib', 'resolver-executavel.cjs'));
const { toplevel } = require(path.join(__dirname, 'lib', 'aviso-fluxo-comum.cjs'));

const ORCAMENTO_MS = 3000;
const MAX_NOMES = 3;
const IDENTIFICADOR = /^[A-Za-z_][A-Za-z0-9_]*$/;

const EXTENSOES = {
  '.js': 'js', '.cjs': 'js', '.mjs': 'js', '.ts': 'js', '.tsx': 'js', '.jsx': 'js',
  '.py': 'py',
  '.prw': 'advpl', '.prx': 'advpl', '.tlpp': 'advpl', '.ch': 'advpl',
};

// Definição de topo por linguagem. JS e Python só olham a coluna zero (topo do arquivo); ADVPL
// aceita recuo, porque o fonte costuma vir indentado dentro de bloco.
const REGRAS = {
  js: [
    /^(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s+(\w+)/,
    /^(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\b|\()/,
    /^(?:export\s+)?class\s+(\w+)/,
    /^exports\.(\w+)\s*=/,
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

// Primeira definição do mesmo nome em outro arquivo rastreado. Linha de uso (chamada) não conta.
function acharDefinicao(gitTop, nome, tipo, arquivoEditado, restante) {
  const args = ['grep', '-n', '-w', ...(tipo === 'advpl' ? ['-i'] : []), '--', nome];
  let saida;
  try {
    saida = execFileSync(caminhoExecutavel('git'), args, {
      cwd: gitTop,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: restante,
      windowsHide: true,
    });
  } catch {
    return null;
  }
  for (const linha of saida.split('\n')) {
    const m = /^(.+?):(\d+):(.*)$/.exec(linha.replace(/\r$/, ''));
    if (!m) continue;
    const [, caminho, num, conteudo] = m;
    if (caminho === arquivoEditado) continue;
    const achado = nomeDaLinha(conteudo, tipo);
    if (!achado) continue;
    const igual = tipo === 'advpl' ? achado.toLowerCase() === nome.toLowerCase() : achado === nome;
    if (igual) return { caminho, linha: Number(num) };
  }
  return null;
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

  const gitTop = toplevel(ev.cwd);
  if (!gitTop) process.exit(0);
  try {
    if (!require(path.join(__dirname, 'lib', 'config.cjs')).ligado('aviso-duplicata', { projeto: gitTop })) process.exit(0);
  } catch {}

  const nomes = nomesDoTexto(textoNovo(ti), tipo);
  if (nomes.length === 0) process.exit(0);

  const arquivoEditado = path.relative(gitTop, path.resolve(ev.cwd, ti.file_path)).split(path.sep).join('/');
  const fim = Date.now() + ORCAMENTO_MS;
  const achados = [];
  for (const nome of nomes) {
    if (achados.length >= MAX_NOMES) break;
    const restante = fim - Date.now();
    if (restante <= 0) break;
    const achado = acharDefinicao(gitTop, nome, tipo, arquivoEditado, restante);
    if (achado) achados.push({ nome, ...achado });
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
