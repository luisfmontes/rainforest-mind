#!/usr/bin/env node
// @categoria: sensor
/**
 * Confere que toda reference longa (> 100 linhas) de `skills/<skill>/references/`
 * abre com um indice de secoes. Uso: node scripts/conferir-indice-referencias.cjs [pasta-skills]
 *
 * Por que: o modelo le reference com `Read` e `limit` por conta propria — 7 de 16
 * leituras medidas nos transcripts em 2026-10-08 pararam no meio (regra-12 lida
 * ate a linha 52 de 181). Sem indice no topo, quem parou nao sabe o que ficou.
 *
 * O indice e o bloco `<!-- indice -->` ... `<!-- /indice -->`, nas primeiras
 * 100 linhas, com 3+ itens `- <texto>`. Cada item e o comeco de uma secao sem a
 * marcacao (`**`, crase, `#`, `> `), e tem de aparecer no corpo, NA ORDEM — item
 * que nao acha secao e indice mentindo. Sem numero de linha de proposito: linha
 * deriva a cada edicao, o texto da secao nao.
 *
 * A abertura do mod tira o bloco das regras injetadas inteiras
 * (`tirarIndice` em hooks/lib/contexto-sessao.cjs).
 *
 * Exit 0 = tudo conferido; 1 = alguma reference reprovada (motivo por linha).
 */
'use strict';
const fs = require('fs');
const path = require('path');

const LIMIAR = 100;
const raiz = process.argv[2] || path.join(__dirname, '..', 'skills');

const limpa = (s) => s.replace(/^#+ |^> /, '').split('**').join('').split('`').join('').trim();

function conferir(arquivo) {
  const linhas = fs.readFileSync(arquivo, 'utf8').replace(/\r\n/g, '\n').split('\n');
  if (linhas.length <= LIMIAR) return null;
  const ini = linhas.indexOf('<!-- indice -->');
  const fim = linhas.indexOf('<!-- /indice -->');
  if (ini < 0 || fim < 0 || fim < ini) return `sem bloco <!-- indice --> ... <!-- /indice -->`;
  if (fim >= LIMIAR) return `indice termina na linha ${fim + 1}, depois da ${LIMIAR}`;
  const itens = linhas.slice(ini + 1, fim).filter((l) => l.startsWith('- ')).map((l) => l.slice(2).trim());
  if (itens.length < 3) return `indice com ${itens.length} item(ns); minimo 3`;
  const corpo = linhas.slice(fim + 1).map(limpa);
  let de = 0;
  for (const item of itens) {
    const n = corpo.findIndex((l, i) => i >= de && l.includes(item));
    if (n < 0) return `item "${item}" nao acha secao no corpo depois do item anterior`;
    de = n + 1;
  }
  return '';
}

let reprovadas = 0, conferidas = 0;
for (const skill of fs.readdirSync(raiz)) {
  const dir = path.join(raiz, skill, 'references');
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.md')).sort()) {
    const motivo = conferir(path.join(dir, f));
    if (motivo === null) continue;
    conferidas++;
    if (motivo) { reprovadas++; console.log(`FALHA ${skill}/references/${f}: ${motivo}`); }
    else console.log(`ok    ${skill}/references/${f}`);
  }
}
console.log(`${conferidas} reference(s) longa(s), ${reprovadas} reprovada(s)`);
process.exit(reprovadas ? 1 : 0);
