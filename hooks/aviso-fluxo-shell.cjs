#!/usr/bin/env node
// @categoria: sensor
/**
 * Aviso de código escrito pelo shell sem fluxo aberto (#564).
 *
 * O `aviso-fluxo.cjs` barra o Edit/Write de código sem fluxo, mas escrita por Bash ou
 * PowerShell (`python patch.py`, `sed -i`, `cat >`) passava em silêncio. Este hook roda no
 * PostToolUse de Bash|PowerShell e decide por fato, não por grafia de comando: guarda, por
 * sessão e repositório, o conjunto de arquivos de código sujos no `git status`, e avisa
 * quando o comando fez aparecer um caminho novo nele. O comando já rodou, então não barra:
 * o exit 2 só leva o aviso ao modelo, sem desfazer nada (D3 do design
 * 2026-10-21-portaria-aviso-bash).
 *
 * Valem os critérios do `aviso-fluxo.cjs`: sessão principal (sem agent_id), repositório com
 * trilho, chave `aviso-fluxo` ligada, nenhum fluxo aberto na branch e sem `leve`. Arquivo
 * sob `docs/` e extensão que não é de código ficam de fora. Sem conjunto guardado, a base é
 * vazia: o código já sujo avisa uma vez. Arquivo já sujo que muda de novo não reaparece.
 * A foto guarda também o HEAD: código criado e commitado na mesma chamada conta pelos commits que
 * a sessão fez desde ela, lidos no reflog. A foto acumula o que a sessão já viu, então cada caminho
 * avisa uma vez. Código em pasta ignorada pelo git não aparece (o Edit já o barra).
 */

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const { caminhoExecutavel } = require(path.join(__dirname, 'lib', 'resolver-executavel.cjs'));
const { leveDaBranch } = require('./lib/caminho-leve.cjs');
const {
  EXTENSOES_CODIGO, toplevel, branchAtual, ehBranchPadraoDoRepo,
  detectarTrilho, fluXoAberto, mensagemHeadDestacado, mensagemBloqueio,
} = require('./lib/aviso-fluxo-comum.cjs');

const MAX_LISTADOS = 10;

function ehCodigo(caminho) {
  return caminho.split('/')[0] !== 'docs' && EXTENSOES_CODIGO.has(path.extname(caminho).toLowerCase());
}

function git(gitTop, args) {
  try {
    return execFileSync(caminhoExecutavel('git'), ['-C', gitTop, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return null;
  }
}

// Código criado e commitado na mesma chamada deixa a árvore limpa: contam os commits que a
// própria sessão fez desde a última foto, lidos no reflog do HEAD. Só as entradas `commit` e
// `commit (amend)`/`(initial)` contam; `pull`, `merge`, `rebase`, `reset`, `checkout`,
// `cherry-pick` e o `commit (merge)` que fecha um merge trazem trabalho alheio e ficam de
// fora (D3, emendas das rodadas 1 e 2 da revisão).
const MAX_REFLOG = 50;
function codigoComitadoDesde(gitTop, guardado, headAtual) {
  if (!guardado.head || !headAtual || guardado.head === headAtual || !guardado.ts) return [];
  const reflog = git(gitTop, ['log', '-g', '--date=unix', '--format=%gd%x09%H%x09%gs', `-n${MAX_REFLOG}`, 'HEAD']);
  if (!reflog) return [];
  const caminhos = [];
  for (const linha of reflog.split(/\r?\n/)) {
    const [seletor, hash, assunto = ''] = linha.split('\t');
    const quando = Number((/\{(\d+)\}/.exec(seletor || '') || [])[1]);
    // Para no HEAD da foto (o que veio antes dela já estava lá) ou, sem ele no reflog, pela hora.
    if (!hash || hash === guardado.head || !Number.isFinite(quando) || quando < guardado.ts - 1) break;
    if (!/^commit( \((amend|initial)\))?:/.test(assunto)) continue;
    const arquivos = git(gitTop, ['-c', 'core.quotepath=false', 'diff-tree', '--no-commit-id', '-r', '-z',
      '--name-only', '--diff-filter=ACMR', '--root', hash]);
    for (const c of (arquivos || '').split('\0')) if (c && ehCodigo(c)) caminhos.push(c);
  }
  return caminhos;
}

// Caminhos de código sujos (modificados, novos ou não rastreados) fora de docs/.
// `-z` evita o escape de caminho com acento; renomeado traz o destino e depois a origem.
function codigoSujo(gitTop) {
  let saida;
  try {
    saida = execFileSync(caminhoExecutavel('git'), ['-C', gitTop, 'status', '--porcelain', '-z', '--untracked-files=all'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return null;
  }
  const partes = saida.split('\0');
  const caminhos = new Set();
  for (let i = 0; i < partes.length; i++) {
    const entrada = partes[i];
    if (entrada.length < 4) continue;
    const xy = entrada.slice(0, 2);
    const caminho = entrada.slice(3);
    if (xy[0] === 'R' || xy[0] === 'C') i++; // pula a origem do renomeado
    if (ehCodigo(caminho)) caminhos.add(caminho);
  }
  return caminhos;
}

function arquivoDoConjunto(sessao, gitTop) {
  const chave = crypto.createHash('sha1').update(`${sessao}\n${path.resolve(gitTop).toLowerCase()}`).digest('hex').slice(0, 16);
  return path.join(os.tmpdir(), 'rainforest-aviso-shell', `${chave}.json`);
}

function lerConjunto(arquivo) {
  try {
    const foto = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
    return { caminhos: new Set(Array.isArray(foto.caminhos) ? foto.caminhos : []), head: foto.head || null, ts: foto.ts || 0 };
  } catch {
    return { caminhos: new Set(), head: null, ts: 0 };
  }
}

function gravarConjunto(arquivo, conjunto, head) {
  try {
    fs.mkdirSync(path.dirname(arquivo), { recursive: true });
    const tmp = `${arquivo}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify({ caminhos: [...conjunto].sort(), head, ts: Math.floor(Date.now() / 1000) }));
    fs.renameSync(tmp, arquivo);
  } catch {}
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0);
  }
  if (!ev || typeof ev !== 'object') process.exit(0);
  if (typeof ev.agent_id === 'string' && ev.agent_id) process.exit(0);
  if (!ev.cwd) process.exit(0);

  const gitTop = toplevel(ev.cwd);
  if (!gitTop) process.exit(0);
  const trilho = detectarTrilho(gitTop);
  if (!trilho) process.exit(0);
  try {
    if (!require('./lib/config.cjs').ligado('aviso-fluxo', { projeto: gitTop })) process.exit(0);
  } catch {}

  const atual = codigoSujo(gitTop);
  if (!atual) process.exit(0);
  // O conjunto se atualiza antes de olhar o fluxo: o que mudou com fluxo aberto não volta a
  // avisar quando o fluxo fechar.
  const arquivo = arquivoDoConjunto(ev.session_id || 'sem-sessao', gitTop);
  const headAtual = (git(gitTop, ['rev-parse', 'HEAD']) || '').trim() || null;
  const guardado = lerConjunto(arquivo);
  const comitados = codigoComitadoDesde(gitTop, guardado, headAtual);
  // A foto acumula tudo o que a sessão já viu: caminho avisado (ou visto com fluxo aberto) não
  // volta a avisar quando é commitado, emendado, rebaseado ou volta de um stash.
  const vistos = new Set([...guardado.caminhos, ...atual, ...comitados]);
  gravarConjunto(arquivo, vistos, headAtual);
  const sujosNovos = [...atual].filter((c) => !guardado.caminhos.has(c));
  const novos = [...new Set([...sujosNovos, ...comitados.filter((c) => !guardado.caminhos.has(c))])].sort();
  if (novos.length === 0) process.exit(0);

  if (fluXoAberto(gitTop, trilho)) process.exit(0);
  const branch = branchAtual(gitTop);
  const headDestacado = branch === 'HEAD';
  if (!headDestacado && branch && leveDaBranch({ gitTop, branch })) process.exit(0);

  const ehBranchPadrao = ehBranchPadraoDoRepo(gitTop, branch);
  const ofereceLeve = !headDestacado && !(trilho === 'rainforest' && ehBranchPadrao);
  const saidas = (headDestacado
    ? mensagemHeadDestacado(trilho)
    : mensagemBloqueio(trilho, branch || 'desconhecida', ofereceLeve, gitTop)).split('\n').slice(1);
  const listados = novos.slice(0, MAX_LISTADOS).join(', ') + (novos.length > MAX_LISTADOS ? ` e mais ${novos.length - MAX_LISTADOS}` : '');
  const onde = headDestacado ? 'em HEAD destacado (sem branch)' : `sem fluxo aberto na branch '${branch || 'desconhecida'}'`;
  const texto = [
    `AVISO: este repositório tem fluxo ${trilho} e há código novo, sujo ou commitado nesta sessão, ${onde}: ${listados}. Visto depois deste comando (o comando já rodou e nada foi desfeito); código não deveria nascer fora de um fluxo.`,
    ...saidas,
  ].join('\n');
  fs.writeSync(2, texto + '\n');
  process.exit(2);
}

main();
