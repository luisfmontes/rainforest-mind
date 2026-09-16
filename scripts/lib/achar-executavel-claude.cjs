/**
 * Acha o executável `claude` varrendo o PATH, sem subir processo para descobrir.
 * Nada de `where`/`which`: este arquivo existe para tirar spawn do caminho.
 *
 * Exported: acharExecutavelClaude()
 *   - RFM_CLAUDE_EXECUTAVEL sobrepõe, para quem tem o CLI fora do PATH
 *   - No Windows, quando o candidato for `.cmd` ou `.bat`, tenta resolver para
 *     `<dir>/node_modules/@anthropic-ai/claude-code/bin/claude.exe`. Se não existir,
 *     ignora o candidato e continua varrendo.
 *   - Nunca usa shell:true (o prompt vem de transcrito não confiável — CVE-2024-27980).
 *   - Devolve caminho absoluto ou null.
 */

const fs = require('fs');
const path = require('path');

/**
 * Acha o executável `claude` varrendo o PATH.
 * RFM_CLAUDE_EXECUTAVEL sobrepõe.
 * No Windows, resolve .cmd/.bat para o .exe real, se disponível.
 *
 * @returns {string|null} Caminho absoluto do executável, ou null se não encontrado.
 */
function acharExecutavelClaude() {
  if (process.env.RFM_CLAUDE_EXECUTAVEL) {
    return process.env.RFM_CLAUDE_EXECUTAVEL;
  }

  const ehWindows = process.platform === 'win32';
  const separador = ehWindows ? ';' : ':';
  const extensoes = ehWindows
    ? (process.env.PATHEXT || '.EXE;.CMD;.BAT').split(';').map((e) => e.toLowerCase())
    : [''];

  for (const dir of (process.env.PATH || '').split(separador)) {
    if (!dir) continue;

    for (const ext of extensoes) {
      const alvo = path.join(dir, `claude${ext}`);

      try {
        if (!fs.statSync(alvo).isFile()) continue;

        // Em Windows, quando o candidato for .cmd ou .bat, resolver para o .exe real.
        const extLower = ext.toLowerCase();
        if (ehWindows && (extLower === '.cmd' || extLower === '.bat')) {
          const exeReal = path.join(dir, 'node_modules', '@anthropic-ai', 'claude-code', 'bin', 'claude.exe');
          try {
            if (fs.statSync(exeReal).isFile()) {
              return exeReal;
            }
          } catch {
            // .exe não existe; ignorar este candidato e continuar varrendo.
          }
          continue;
        }

        // Candidato é .exe ou estamos em Unix.
        if (!ehWindows) {
          fs.accessSync(alvo, fs.constants.X_OK);
        }
        return alvo;
      } catch {
        // Caminho inexistente, sem permissão, ou statSync falhou: segue procurando.
      }
    }
  }

  return null;
}

module.exports = { acharExecutavelClaude };
