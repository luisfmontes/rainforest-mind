#!/usr/bin/env node
/**
 * Resolve o estágio ativo na partida do processo de poda, a partir da branch git.
 *
 * Delega a `estagio-ativo.cjs` para obter o estágio e slug da branch atual.
 * Suporta prefixos de branch como `fluxo/` e datas no slug.
 *
 * Uso:
 *   const {estagioAtivo} = require('./poda-estagio.cjs');
 *   const r = estagioAtivo({cwd, env}); // devolve {slug, estagio} ou null
 *
 * CLI (para depuração):
 *   node hooks/lib/poda-estagio.cjs [--cwd /caminho]
 */

/**
 * Resolve o estágio ativo na partida do proxy poda.
 *
 * @param {object} o
 * @param {string} [o.cwd] default: process.cwd()
 * @param {object} [o.env] default: process.env (não mais usado, mantido por compatibilidade)
 * @returns {{slug: string, estagio: string} | null}
 */
function estagioAtivo(o = {}) {
  const cwd = o.cwd || process.cwd();

  // Delega a estagio-ativo.resolver()
  const resultado = require('./estagio-ativo.cjs').resolver({ cwd });
  return resultado;
}

// CLI para depuração
if (require.main === module) {
  const args = process.argv.slice(2);
  const o = {};

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--cwd') {
      o.cwd = args[++i];
    } else if (args[i] === '--projeto') {
      o.cwd = args[++i];
    }
  }

  const r = estagioAtivo(o);
  if (r) {
    console.log(JSON.stringify(r));
  } else {
    console.log('null');
  }
}

module.exports = { estagioAtivo };
