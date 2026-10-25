'use strict';

/**
 * caminho-real.cjs — caminho canônico de arquivo para os hooks de aviso.
 *
 * O cwd da sessão pode vir em nome curto 8.3 (o temp do runner do CI é `RUNNER~1`) e o git
 * devolve o nome longo; sem resolver os dois lados, o `path.relative` não casa o próprio arquivo.
 * Arquivo que ainda não existe resolve pela pasta. Usado por aviso-duplicata.cjs e aviso-fluxo.cjs.
 */

const fs = require('node:fs');
const path = require('node:path');

function caminhoReal(p) {
  try {
    return fs.realpathSync.native(p);
  } catch {
    try {
      return path.join(fs.realpathSync.native(path.dirname(p)), path.basename(p));
    } catch {
      return p;
    }
  }
}

module.exports = { caminhoReal };
