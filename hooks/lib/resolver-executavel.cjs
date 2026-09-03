// Resolver que honra a ordem do PATH — incidente 2026-09-03:
// Node no Windows não honra a ordem do PATH quando resolve executáveis;
// gh.cmd (sandbox) é vencido por gh.exe (sistema). Resolver manual.

const fs = require('fs');
const path = require('path');

function resolverExecutavel(nome, env = process.env) {
  const PATH = env.PATH || '';
  const separador = process.platform === 'win32' ? ';' : ':';
  const extensoes = process.platform === 'win32' ? ['.cmd', '.bat', '.exe', ''] : [''];

  const diretrios = PATH.split(separador).filter(d => d);

  for (const dir of diretrios) {
    for (const ext of extensoes) {
      const caminhoCompleto = path.join(dir, nome + ext);
      if (fs.existsSync(caminhoCompleto)) {
        return caminhoCompleto;
      }
    }
  }

  return null;
}

module.exports = { resolverExecutavel };
