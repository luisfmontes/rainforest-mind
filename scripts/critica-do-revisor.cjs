#!/usr/bin/env node
/**
 * Crítica do revisor para o laço executor → revisor. Design
 * docs/rainforest/design/2026-10-10-laco-executor-revisor.md, D6 e D9.
 *
 * Lê o ÚLTIMO veredito `reprovado` de `revisar` no estado do fluxo, abre o
 * transcrito que o hook SubagentStop gravou e imprime a última mensagem do
 * revisor sem a linha `VEREDITO:`. É o literal que vai ao redespacho do
 * executor (D3): a janela principal não parafraseia a crítica.
 *
 * D3 (lote 6, docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-6.md): achado
 * com a marca `[preexistente]` que o diff não toca sai do redespacho (stdout) e
 * vai para a seção `## Preexistentes (não são da entrega — Issue, não correção)`
 * no stderr, para a janela abrir Issue. A marca recusada pelo diff fica na
 * crítica, sem a marca, e o stderr diz `marca [preexistente] recusada`. Sem base
 * conferível, o stderr diz `marca [preexistente] não conferida: sem base`.
 *
 * D4 (lote 5, docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-5.md): com
 * `--comparacao`, imprime só o bloco `## Comparação com a volta anterior` (sai 0,
 * também com veredito ok): cada achado atual marcado `novo` ou `persiste (mesmo
 * arquivo)` (chave = arquivo, sem a linha) e cada arquivo da volta anterior que
 * sumiu. Sem volta anterior, imprime `(sem volta anterior)`. O bloco vai no
 * briefing do revisor da volta seguinte, nunca no do executor (D10a, lote 6). A
 * chave por arquivo é o limite da comparação: não prova que o achado foi corrigido.
 *
 * Uso: node scripts/critica-do-revisor.cjs --slug <slug> [--comparacao]
 *
 * Saídas:
 *   0   crítica impressa (ou, com --comparacao, o bloco de comparação)
 *   3   crítica com achado [design]: o laço para e sobe ao usuário (D5, D7)
 *   4   sem veredito reprovado em `revisar`, estado inexistente, ou reprovado sem
 *       achado marcado ([alta]/[media]/[baixa] no início do item; D3 do lote 2);
 *       com --comparacao, sem nenhum veredito com transcrito em `revisar`
 *   69  transcrito ausente ou sem mensagem do assistente (nao-verificavel)
 *   1   erro de uso
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { ultimaMensagemAssistente } = require('./lib/primeiro-prompt-jsonl.cjs');
const {
  contarAchados, listarAchados, itensAchados, preexistentesNoDiff, tirarMarcaPreexistente, fimDoItem,
} = require(path.join(__dirname, '..', 'hooks', 'lib', 'achados-revisor.cjs'));

// Mesma raiz de scripts/estado.cjs: o estado mora no projeto em que se trabalha.
const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

const USO = 'uso: node scripts/critica-do-revisor.cjs --slug <slug> [--comparacao]';

function expandeTil(caminho) {
  if (caminho.startsWith('~/') || caminho.startsWith('~\\')) {
    return path.join(os.homedir(), caminho.slice(2));
  }
  return caminho;
}

// D4 (lote 5): a volta anterior é a última de `revisar.voltas` que tem um
// veredito reprovado com transcrito. Sem ela, nada muda na saída.
function voltaAnterior(estado) {
  const voltas = estado && estado.revisar && Array.isArray(estado.revisar.voltas) ? estado.revisar.voltas : [];
  for (let i = voltas.length - 1; i >= 0; i -= 1) {
    const vs = voltas[i] && Array.isArray(voltas[i].vereditos) ? voltas[i].vereditos : [];
    let reprovado = null;
    for (const v of vs) {
      if (v && v.veredito === 'reprovado' && v.transcrito) reprovado = v;
    }
    if (reprovado) return reprovado;
  }
  return null;
}

// Último veredito de qualquer tipo com transcrito na janela atual (--comparacao).
function vereditoAtual(estado) {
  const vs = estado && estado.revisar && Array.isArray(estado.revisar.vereditos) ? estado.revisar.vereditos : [];
  let atual = null;
  for (const v of vs) {
    if (v && v.transcrito) atual = v;
  }
  return atual;
}

// Bloco `## Comparação com a volta anterior`. A chave é o arquivo do primeiro
// caminho:linha de cada achado (lib achados-revisor.cjs).
function blocoComparacao(anterior, critica) {
  const linhas = ['## Comparação com a volta anterior'];
  const mensagem = ultimaMensagemAssistente(expandeTil(anterior.transcrito));
  if (mensagem === null) {
    linhas.push('transcrito da volta anterior ausente');
    return `${linhas.join('\n')}\n`;
  }
  const criticaAnterior = mensagem.split(/\r?\n/).filter((l) => !/^[\s*_`]*VEREDITO:/i.test(l)).join('\n');
  const antes = listarAchados(criticaAnterior);
  const agora = listarAchados(critica);
  const chavesAnteriores = new Set(antes.filter((x) => x.arquivo).map((x) => x.arquivo));
  const chavesAtuais = new Set(agora.filter((x) => x.arquivo).map((x) => x.arquivo));
  for (const a of agora) {
    if (!a.arquivo) continue;
    const marca = chavesAnteriores.has(a.arquivo) ? 'persiste (mesmo arquivo)' : 'novo';
    linhas.push(`- [${a.sev}] ${a.arquivo} — ${marca}`);
  }
  const vistos = new Set();
  for (const b of antes) {
    if (!b.arquivo || chavesAtuais.has(b.arquivo) || vistos.has(b.arquivo)) continue;
    vistos.add(b.arquivo);
    linhas.push(`- [${b.sev}] ${b.arquivo} — sumiu — confirmar se foi corrigido`);
  }
  const semAtual = agora.filter((x) => !x.arquivo).length;
  const semAnterior = antes.filter((x) => !x.arquivo).length;
  linhas.push(`achados sem caminho:linha, fora da comparação: ${semAtual} na crítica atual, ${semAnterior} na volta anterior`);
  return `${linhas.join('\n')}\n`;
}

function lerSlug(argv) {
  const i = argv.indexOf('--slug');
  if (i === -1 || !argv[i + 1]) return null;
  const slug = argv[i + 1];
  // O slug vira nome de arquivo: sem barra, sem `..`.
  return /^[A-Za-z0-9._-]+$/.test(slug) ? slug : null;
}

function lerEstado(slug) {
  const arquivoEstado = path.join(RAIZ, 'docs', 'rainforest', 'estado', `${slug}.json`);
  try {
    return { estado: JSON.parse(fs.readFileSync(arquivoEstado, 'utf8')) };
  } catch (err) {
    if (err.code === 'ENOENT') {
      process.stderr.write(`estado inexistente: ${arquivoEstado}\n`);
      return { saida: 4 };
    }
    throw err;
  }
}

// --comparacao (D10a): só o bloco, sai 0 também com veredito ok.
function modoComparacao(estado) {
  const anterior = voltaAnterior(estado);
  if (!anterior) {
    process.stdout.write('(sem volta anterior)\n');
    return 0;
  }
  const atual = vereditoAtual(estado);
  if (!atual) {
    process.stderr.write('sem veredito com transcrito em revisar para o slug\n');
    return 4;
  }
  const mensagem = ultimaMensagemAssistente(expandeTil(atual.transcrito));
  if (mensagem === null) {
    process.stderr.write(`nao-verificavel: transcrito ausente ou sem mensagem do assistente: ${expandeTil(atual.transcrito)}\n`);
    return 69;
  }
  const critica = mensagem.split(/\r?\n/).filter((l) => !/^[\s*_`]*VEREDITO:/i.test(l)).join('\n');
  process.stdout.write(blocoComparacao(anterior, critica));
  return 0;
}

function main() {
  const argv = process.argv.slice(2);
  const slug = lerSlug(argv);
  if (!slug) {
    process.stderr.write(`${USO}\n`);
    return 1;
  }

  const lido = lerEstado(slug);
  if (lido.saida !== undefined) return lido.saida;
  const estado = lido.estado;

  if (argv.includes('--comparacao')) return modoComparacao(estado);

  const vereditos = estado && estado.revisar && Array.isArray(estado.revisar.vereditos)
    ? estado.revisar.vereditos
    : [];
  let reprovado = null;
  for (const v of vereditos) {
    if (v && v.veredito === 'reprovado') reprovado = v;
  }
  if (!reprovado) {
    process.stderr.write(`sem veredito reprovado em revisar para o slug ${slug}\n`);
    return 4;
  }

  if (!reprovado.transcrito) {
    process.stderr.write('nao-verificavel: veredito reprovado sem campo transcrito\n');
    return 69;
  }
  const caminho = expandeTil(reprovado.transcrito);
  const mensagem = ultimaMensagemAssistente(caminho);
  if (mensagem === null) {
    process.stderr.write(`nao-verificavel: transcrito ausente ou sem mensagem do assistente: ${caminho}\n`);
    return 69;
  }

  // A linha VEREDITO: sai mesmo decorada (**, _, crase), como o hook aceita.
  const linhasSemVeredito = mensagem.split(/\r?\n/).filter((l) => !/^[\s*_`]*VEREDITO:/i.test(l));
  const critica = linhasSemVeredito.join('\n');

  // D3 (lote 6): marca [preexistente] conferida pelo diff. Recusada = volta a
  // bloquear (sem a marca no texto); aceita = sai do redespacho para a seção.
  const marcados = itensAchados(critica).filter((x) => x.preexistente);
  const recusadas = preexistentesNoDiff(critica, RAIZ);
  if (recusadas === null && marcados.length > 0) {
    process.stderr.write('marca [preexistente] não conferida: sem base\n');
  }
  const recusadasIdx = new Set((recusadas || []).map((x) => x.indice));
  for (const r of recusadas || []) {
    process.stderr.write(`marca [preexistente] recusada: ${r.motivo}\n`);
  }
  const semMarcaRecusada = tirarMarcaPreexistente(critica, recusadas || []);
  const linhas = semMarcaRecusada.split(/\r?\n/);
  const aceitas = marcados.filter((x) => !recusadasIdx.has(x.indice));
  const fora = new Set();
  const secao = [];
  for (const x of aceitas) {
    const fim = fimDoItem(linhas, x.indice);
    for (let i = x.indice; i < fim; i += 1) fora.add(i);
    secao.push(...linhas.slice(x.indice, fim));
  }
  const redespacho = linhas.filter((_, i) => !fora.has(i)).join('\n');

  // Contagem sobre o texto com as recusas já sem marca: [design] de item aceito
  // continua contando (para o exit 3), só a marca [preexistente] não bloqueia.
  const achados = contarAchados(semMarcaRecusada);
  // [design] na abertura do item (lib achados-revisor.cjs) para o laço, antes
  // da contagem: achado só de [design] continua parando o laço com exit 3.
  if (achados.design > 0) {
    process.stdout.write(`${redespacho}\n`);
    if (secao.length) process.stderr.write(`## Preexistentes (não são da entrega — Issue, não correção)\n${secao.join('\n')}\n`);
    process.stderr.write('[design]: achado contesta D<n> do design ou o plano; o laço para e sobe ao usuário (D5)\n');
    return 3;
  }
  // D3 (lote 2): reprovado sem achado marcado ([alta], [media] ou [baixa] no
  // início do item) não é crítica que o executor consiga atender.
  if (achados.total === 0) {
    process.stderr.write('reprovado sem achado marcado: nenhum item abre com [alta], [media], [baixa] ou [design]\n');
    return 4;
  }

  process.stdout.write(`${redespacho}\n`);
  if (secao.length) process.stderr.write(`## Preexistentes (não são da entrega — Issue, não correção)\n${secao.join('\n')}\n`);
  return 0;
}

process.exitCode = main();
