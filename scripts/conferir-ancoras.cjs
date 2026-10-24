#!/usr/bin/env node
// @categoria: sensor
/**
 * Confere as âncoras de um mapa da arqueologia contra o fonte: cada citação
 * tem que apontar para um arquivo que existe, para linhas que existem e, quando
 * carrega símbolo, para um lugar onde o símbolo aparece.
 *
 * POR QUE EXISTE. A releitura dos `CONFIRMADO` era feita por agente, que relia
 * cada `arquivo:linha` à mão (skills/arqueologia/SKILL.md, passo de conferência).
 * A parte mecânica (o arquivo existe, a linha cabe nele, o nome da função ainda
 * está lá) não precisa de agente: sai por script. Mecanismo de referência:
 * BMAD-METHOD `recon_kit.py anchors` (recon_kit.py:389-481, `symbol_found`).
 *
 * FORMAS ACEITAS (o que o mapa escreve, o que este script lê):
 *   `arquivo.ext:N`          linha N
 *   `arquivo.ext:N-M`        intervalo; as DUAS pontas têm que caber no arquivo
 *   `arquivo.ext#Simbolo`    símbolo em qualquer lugar do arquivo
 *   `arquivo.ext:N` + símbolo entre crases logo após a citação, com ou sem
 *     parênteses: `` `zfiscal01.prw:120` (`MontaNFe`) `` ou
 *     `` zfiscal01.prw:120 `MontaNFe` ``. O símbolo tem que aparecer entre a
 *     linha N-80 e a N (no intervalo, entre N-80 e M).
 *   A extensão é obrigatória (ao menos uma letra depois do ponto), então
 *   horário (`10:30`) e número decimal não viram citação. URLs `http(s)://`
 *   são ignoradas.
 *
 * STATUS, por âncora:
 *   ok                arquivo existe, linhas existem, símbolo (se houver) acha-se
 *   arquivo-ausente   o arquivo não existe sob a raiz (--repo, padrão: cwd)
 *   linha-fora        alguma ponta da linha/intervalo cai fora do arquivo
 *   simbolo-ausente   o símbolo não aparece na janela (ou no arquivo, na forma #)
 *
 * CODIFICAÇÃO. O fonte é lido como bytes. Se for UTF-8 válido, decodifica como
 * UTF-8; se não for, decodifica como latin1 (ADVPL é CP-1252). Nunca lança por
 * codificação: uma linha com `\xe7` em CP-1252 não vira falha falsa.
 *
 * SAÍDA. Uma linha por âncora (`<status> <citação>`) e o resumo
 * `N âncoras: X ok, Y falhas`. Mapa sem âncora sai `0 âncoras: 0 ok, 0 falhas`.
 * Exit: 0 tudo ok (ou zero âncoras) · 1 alguma falha · 2 uso ou mapa/raiz inexistente.
 *
 * Uso: node scripts/conferir-ancoras.cjs <mapa.md> [--repo <raiz>]
 */
const fs = require('fs');
const path = require('path');

const JANELA = 80;

const USO = `uso: node scripts/conferir-ancoras.cjs <mapa.md> [--repo <raiz>]
  <mapa.md>   mapa da arqueologia cujas âncoras serão conferidas
  --repo      raiz do código onde os arquivos citados moram (padrão: diretório atual)`;

function erroUso(msg) {
  console.error(`erro: ${msg}\n${USO}`);
  process.exit(2);
}

const args = process.argv.slice(2);
let mapa = null;
let raiz = process.cwd();
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--repo') {
    if (i + 1 >= args.length) erroUso('--repo veio sem valor');
    raiz = args[++i];
  } else if (a.startsWith('--')) {
    erroUso(`opção desconhecida: ${a}`);
  } else if (mapa === null) {
    mapa = a;
  } else {
    erroUso(`argumento extra: ${a}`);
  }
}
if (mapa === null) erroUso('falta o mapa');
if (!fs.existsSync(mapa) || !fs.statSync(mapa).isFile()) erroUso(`mapa inexistente: ${mapa}`);
if (!fs.existsSync(raiz) || !fs.statSync(raiz).isDirectory()) erroUso(`--repo não é uma pasta: ${raiz}`);

// caminho(.ext) seguido de :N, :N-M ou #Simbolo. A extensão exige letra.
const RE_CIT = /([A-Za-z0-9_][A-Za-z0-9_./\\-]*\.[A-Za-z][A-Za-z0-9]{0,9})(?::(\d+)(?:-(\d+))?(?!\d)|#([A-Za-z_][A-Za-z0-9_]*))/g;
// símbolo entre crases logo após uma citação de linha (com ou sem crase de fechamento e parênteses)
const RE_SIMBOLO_DEPOIS = /^`?\s*\(?\s*`([A-Za-z_][A-Za-z0-9_]*)`/;
const RE_URL = /https?:\/\/\S+/g;

function extrairCitacoes(texto) {
  const cits = [];
  texto.split(/\r?\n/).forEach((bruta) => {
    // URL vira espaço de mesmo tamanho: não gera citação, e o resto da linha mantém posição
    const linha = bruta.replace(RE_URL, (m) => ' '.repeat(m.length));
    for (const m of linha.matchAll(RE_CIT)) {
      const arquivo = m[1];
      if (m[4] !== undefined) {
        cits.push({ forma: 'nome', arquivo, ini: null, fim: null, simbolo: m[4] });
        continue;
      }
      const ini = Number(m[2]);
      const fim = m[3] !== undefined ? Number(m[3]) : ini;
      const depois = RE_SIMBOLO_DEPOIS.exec(linha.slice(m.index + m[0].length));
      cits.push({ forma: 'linha', arquivo, ini, fim, simbolo: depois ? depois[1] : null });
    }
  });
  return cits;
}

function lerFonte(arquivo) {
  const buf = fs.readFileSync(arquivo);
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch (_e) {
    return buf.toString('latin1');
  }
}

function regexSimbolo(sym) {
  return new RegExp(`(?<![A-Za-z0-9_])${sym}(?![A-Za-z0-9_])`);
}

function linhaDentro(linhas, linha) {
  const dentro = linha >= 1 && linha <= linhas.length;
  return dentro;
}

function avaliar(cit) {
  const arq = path.resolve(raiz, cit.arquivo.replace(/\\/g, '/'));
  if (!fs.existsSync(arq) || !fs.statSync(arq).isFile()) return 'arquivo-ausente';
  const linhas = lerFonte(arq).split(/\r?\n/);
  if (linhas.length && linhas[linhas.length - 1] === '') linhas.pop();
  const re = cit.simbolo ? regexSimbolo(cit.simbolo) : null;

  if (cit.forma === 'nome') {
    return linhas.some((l) => re.test(l)) ? 'ok' : 'simbolo-ausente';
  }
  if (!linhaDentro(linhas, cit.ini) || !linhaDentro(linhas, cit.fim)) return 'linha-fora';
  if (re) {
    const de = Math.max(1, cit.ini - JANELA);
    for (let n = de; n <= cit.fim; n++) {
      if (re.test(linhas[n - 1])) return 'ok';
    }
    return 'simbolo-ausente';
  }
  return 'ok';
}

function rotulo(cit) {
  if (cit.forma === 'nome') return `${cit.arquivo}#${cit.simbolo}`;
  const faixa = cit.fim !== cit.ini ? `${cit.ini}-${cit.fim}` : `${cit.ini}`;
  return `${cit.arquivo}:${faixa}${cit.simbolo ? ` \`${cit.simbolo}\`` : ''}`;
}

const cits = extrairCitacoes(fs.readFileSync(mapa, 'utf8'));
let oks = 0;
for (const cit of cits) {
  const status = avaliar(cit);
  if (status === 'ok') oks++;
  console.log(`${status} ${rotulo(cit)}`);
}
const falhas = cits.length - oks;
console.log(`${cits.length} âncoras: ${oks} ok, ${falhas} falhas`);
process.exitCode = falhas > 0 ? 1 : 0;
