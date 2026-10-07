#!/usr/bin/env node
'use strict';
// CLI: imprime onde mora o mapa, o design ou o plano deste repo (relativo à raiz).
//   node scripts/pastas-docs.cjs caminho --tipo <mapas|design|planos> [--slug <s>] [--raiz <dir>]
const path = require('path');
const { caminhoDoc } = require(path.join(__dirname, '..', 'hooks', 'lib', 'pastas-docs.cjs'));

const USO = 'uso: pastas-docs.cjs caminho --tipo <mapas|design|planos> [--slug <s>] [--raiz <dir>]';
const args = process.argv.slice(2);
const arg = (n) => {
  const i = args.indexOf(`--${n}`);
  return i >= 0 ? args[i + 1] : undefined;
};

if (args[0] !== 'caminho') {
  console.error(USO);
  process.exit(2);
}
const tipo = arg('tipo');
const slug = arg('slug');
if (!['mapas', 'design', 'planos'].includes(tipo) || (tipo !== 'mapas' && !slug)) {
  console.error(USO);
  process.exit(2);
}
const raiz = arg('raiz') || process.env.RFM_ESTADO_ROOT || process.env.CLAUDE_PROJECT_DIR || process.cwd();
console.log(caminhoDoc(tipo, slug, { raiz }));
