#!/usr/bin/env node
// @categoria: guia
// Dados do relogio do mod: janelas esperando o usuario e a ociosidade do foco.
// Somente leitura. Saida: JSON em uma linha. Contrato em
// docs/rainforest/planos/2026-10-03-mod-jornada-relogio.md ("Contrato dos dados").
//
// Uso: node scripts/relogio-sessoes.cjs --cwd <dir> --sessao <id>
// Exit 2 sem --sessao; exit 1 sem raiz ou com sessoes.json ausente/ilegivel.
const fs = require('fs');
const path = require('path');
const { sessoesVivas, ociosidadeDoFoco } = require('../hooks/lib/contexto-sessao.cjs');
const { resolverRaiz } = require('../hooks/lib/raiz.cjs');

const PLUGIN = path.resolve(__dirname, '..');
// Mesmo teto do radar da abertura (hooks/foco-session-start.cjs).
const JANELA_VIVA_MS = 6 * 3600 * 1000;
const OCIOSIDADE_PADRAO_MIN = 45;
const TETO_BYTES = 256 * 1024;

function valorDe(nome) {
  const i = process.argv.indexOf(nome);
  return i !== -1 && i + 1 < process.argv.length ? process.argv[i + 1] : null;
}

function main() {
  const eu = valorDe('--sessao');
  if (!eu) {
    process.stderr.write('relogio-sessoes: falta --sessao <id>\n');
    return 2;
  }
  const cwd = path.resolve(valorDe('--cwd') || process.cwd());
  const { raiz } = resolverRaiz({ cwd, plugin: PLUGIN });
  if (!raiz) {
    process.stderr.write('relogio-sessoes: sem raiz de dados\n');
    return 1;
  }
  let state;
  try {
    const caminhoSessoes = path.join(raiz, 'sessoes.json');
    const stats = fs.statSync(caminhoSessoes);
    if (stats.size > TETO_BYTES) {
      process.stderr.write(`relogio-sessoes: sessoes.json acima de 256 KB (${stats.size} bytes)\n`);
      return 1;
    }
    state = JSON.parse(fs.readFileSync(caminhoSessoes, 'utf8'));
  } catch (e) {
    process.stderr.write(`relogio-sessoes: sessoes.json ausente ou ilegivel (${e.message})\n`);
    return 1;
  }
  let ociosidade = OCIOSIDADE_PADRAO_MIN;
  try {
    const n = ociosidadeDoFoco(fs.readFileSync(path.join(raiz, 'FOCO.md'), 'utf8'));
    if (n !== null) ociosidade = n;
  } catch {}
  const janelas = sessoesVivas(state, Date.now(), JANELA_VIVA_MS)
    .filter(([id]) => id !== eu)
    .map(([, s]) => ({ cwd: s.cwd, p: s.prompt_ts || 0, t: s.stop_ts || 0 }))
    .filter(({ p, t }) => !(p > t))
    .map(({ cwd: c, p, t }) => ({ cwd: c, desde: t || p }))
    .sort((a, b) => a.desde - b.desde);
  process.stdout.write(`${JSON.stringify({ ociosidade_min: ociosidade, janelas })}\n`);
  return 0;
}

process.exitCode = main();
