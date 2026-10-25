'use strict';
/* Baterias vizinhas de um arquivo: as testa-*.(sh|cjs) de scripts/ e hooks/ que
 * citam o nome-base do arquivo.
 *
 * POR QUE EXISTE. Duas peças precisam dessa mesma leitura: o aviso do
 * conferir-entrega (D25, #400) para arquivo fora do escopo, e a escolha de
 * baterias pelo diff (baterias-do-diff.cjs, D3). Extraída para que as duas
 * leiam o repo do mesmo jeito; senão a seleção e o aviso divergem em silêncio.
 *
 * A leitura é textual e de fronteira: `foo.cjs` não casa em `xfoo.cjs` nem em
 * `foo.cjs.bak`. Citação não prova dependência, então quem chama trata o
 * resultado como indício, nunca como prova.
 */
const fs = require('fs');
const path = require('path');

function escaparRegex(texto) {
  return texto.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function ehDir(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

/**
 * Devolve, em ordem de scripts/ e depois hooks/, os caminhos relativos a `raiz`
 * (ex.: `scripts/testa-a.sh`) das baterias que citam o nome-base de `caminho`.
 * Bateria ilegível não entra: não é vizinha conhecida.
 */
function bateriasQueCitam(raiz, caminho) {
  const nome = path.basename(caminho);
  const reNome = new RegExp(`(^|[^A-Za-z0-9_.-])${escaparRegex(nome)}($|[^A-Za-z0-9_-])`);
  const achadas = [];
  for (const pasta of ['scripts', 'hooks']) {
    const dir = path.join(raiz, pasta);
    if (!ehDir(dir)) continue;
    for (const f of fs.readdirSync(dir).sort()) {
      if (!/^testa-.*\.(sh|cjs)$/.test(f)) continue;
      try {
        if (reNome.test(fs.readFileSync(path.join(dir, f), 'utf8'))) achadas.push(`${pasta}/${f}`);
      } catch { /* bateria ilegível: não é vizinha conhecida */ }
    }
  }
  return achadas;
}

module.exports = { bateriasQueCitam };
