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
 * D4 (lote 5, docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-5.md): no
 * caminho de saída 0, se há uma volta anterior guardada em `revisar.voltas`
 * com veredito reprovado e transcrito, acrescenta o bloco
 * `## Comparação com a volta anterior`: cada achado atual marcado `novo` ou
 * `persiste (mesmo arquivo)` (chave = arquivo, sem a linha) e cada arquivo da
 * volta anterior que sumiu. Sem volta anterior, a saída é a de antes. A chave
 * por arquivo é o limite da comparação: não prova que o achado foi corrigido.
 *
 * Uso: node scripts/critica-do-revisor.cjs --slug <slug>
 *
 * Saídas:
 *   0   crítica impressa (com o bloco de comparação, quando há volta anterior)
 *   3   crítica com achado [design]: o laço para e sobe ao usuário (D5, D7)
 *   4   sem veredito reprovado em `revisar`, estado inexistente, ou reprovado sem
 *       achado marcado ([alta]/[media]/[baixa] no início do item; D3 do lote 2)
 *   69  transcrito ausente ou sem mensagem do assistente (nao-verificavel)
 *   1   erro de uso
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { ultimaMensagemAssistente } = require('./lib/primeiro-prompt-jsonl.cjs');
const { contarAchados, listarAchados } = require(path.join(__dirname, '..', 'hooks', 'lib', 'achados-revisor.cjs'));

// Mesma raiz de scripts/estado.cjs: o estado mora no projeto em que se trabalha.
const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

const USO = 'uso: node scripts/critica-do-revisor.cjs --slug <slug>';

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

// Bloco `## Comparação com a volta anterior`, ou '' sem volta anterior. A chave
// é o arquivo do primeiro caminho:linha de cada achado (lib achados-revisor.cjs).
function blocoComparacao(estado, critica) {
  const anterior = voltaAnterior(estado);
  if (!anterior) return '';
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

function main() {
  const slug = lerSlug(process.argv.slice(2));
  if (!slug) {
    process.stderr.write(`${USO}\n`);
    return 1;
  }

  const arquivoEstado = path.join(RAIZ, 'docs', 'rainforest', 'estado', `${slug}.json`);
  let estado;
  try {
    estado = JSON.parse(fs.readFileSync(arquivoEstado, 'utf8'));
  } catch (err) {
    if (err.code === 'ENOENT') {
      process.stderr.write(`estado inexistente: ${arquivoEstado}\n`);
      return 4;
    }
    throw err;
  }

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
  const linhas = mensagem.split(/\r?\n/).filter((l) => !/^[\s*_`]*VEREDITO:/i.test(l));
  const critica = linhas.join('\n');
  const achados = contarAchados(critica);
  // [design] na abertura do item (lib achados-revisor.cjs) para o laço, antes
  // da contagem: achado só de [design] continua parando o laço com exit 3.
  if (achados.design > 0) {
    process.stdout.write(`${critica}\n`);
    process.stderr.write('[design]: achado contesta D<n> do design ou o plano; o laço para e sobe ao usuário (D5)\n');
    return 3;
  }
  // D3 (lote 2): reprovado sem achado marcado ([alta], [media] ou [baixa] no
  // início do item) não é crítica que o executor consiga atender.
  if (achados.total === 0) {
    process.stderr.write('reprovado sem achado marcado: nenhum item abre com [alta], [media], [baixa] ou [design]\n');
    return 4;
  }

  process.stdout.write(`${critica}\n`);
  // D4 (lote 5): só no caminho 0; sem volta anterior, o bloco é '' e nada sai.
  const comparacao = blocoComparacao(estado, critica);
  if (comparacao) process.stdout.write(comparacao);
  return 0;
}

process.exitCode = main();
