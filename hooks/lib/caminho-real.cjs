'use strict';

/**
 * caminho-real.cjs — caminho canônico de arquivo para os hooks de aviso.
 *
 * O cwd da sessão pode vir em nome curto 8.3 (o temp do runner do CI é `RUNNER~1`) e o git
 * devolve o nome longo; sem resolver os dois lados, o `path.relative` não casa o próprio arquivo.
 * Arquivo que ainda não existe resolve pela pasta. Usado por aviso-duplicata.cjs, aviso-fluxo.cjs e
 * gate-worktree.cjs. `acharGitAcima` responde se há repositório acima sem depender do git: o gate e a
 * catraca precisam distinguir "fora de repositório" de "git que não respondeu".
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

// Primeira pasta, de `dir` para cima, que tem `.git`. Em worktree linkado e submódulo `.git` é arquivo.
function acharGitAcima(dir) {
  for (let d = path.resolve(dir); ; d = path.dirname(d)) {
    const git = path.join(d, '.git');
    if (fs.existsSync(git)) {
      let ehArquivo = false;
      try { ehArquivo = !fs.statSync(git).isDirectory(); } catch {}
      return { dir: d, ehArquivo };
    }
    if (path.dirname(d) === d) return null;
  }
}

module.exports = { caminhoReal, acharGitAcima };
