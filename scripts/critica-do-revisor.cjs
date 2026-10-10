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
 * Uso: node scripts/critica-do-revisor.cjs --slug <slug>
 *
 * Saídas:
 *   0   crítica impressa
 *   3   crítica com achado [design]: o laço para e sobe ao usuário (D5, D7)
 *   4   sem veredito reprovado em `revisar`, ou estado inexistente
 *   69  transcrito ausente ou sem mensagem do assistente (nao-verificavel)
 *   1   erro de uso
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { ultimaMensagemAssistente } = require('./lib/primeiro-prompt-jsonl.cjs');

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
  if (!critica.trim()) {
    process.stderr.write('reprovado sem achado: a critica so tem a linha VEREDITO:\n');
    return 4;
  }

  process.stdout.write(`${critica}\n`);
  // [design] só conta abrindo o achado (marcador, negrito ou rótulo A1. antes);
  // citado no meio da frase, ou entre crases, não para o laço.
  if (/^\s*(?:[-*]\s+)?(?:\*\*)?(?:[A-Z]?\d+[.):]\s*)?(?:\*\*)?\s*\[design\]/im.test(critica)) {
    process.stderr.write('[design]: achado contesta D<n> do design ou o plano; o laço para e sobe ao usuário (D5)\n');
    return 3;
  }
  return 0;
}

process.exitCode = main();
