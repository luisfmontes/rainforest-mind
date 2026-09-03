// Resolver que honra a ordem do PATH — incidente 2026-09-03:
// Node no Windows não honra a ordem do PATH quando resolve executáveis;
// gh.cmd (sandbox) é vencido por gh.exe (sistema). Resolver manual.
// Node 18.20+ recusa .cmd/.bat sem shell (CVE-2024-27980 EINVAL); executar() ajusta.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

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

function executar(nome, args, opts = {}) {
  const exe = resolverExecutavel(nome);
  if (!exe) {
    return {
      status: 127,
      stdout: '',
      stderr: `${nome} not found`,
      error: new Error(`${nome} not found`)
    };
  }

  const ehCmd = /\.(cmd|bat)$/i.test(exe);
  return spawnSync(exe, args, {
    ...opts,
    shell: ehCmd ? true : (opts.shell !== undefined ? opts.shell : false),
    encoding: 'utf-8'
  });
}

module.exports = { resolverExecutavel, executar };
