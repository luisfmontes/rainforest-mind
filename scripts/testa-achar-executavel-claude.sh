#!/bin/bash
# Testa acharExecutavelClaude (#282): .cmd/.bat do PATH resolvem para o
# claude.exe real do pacote npm, ou são ignorados — nunca devolvidos, porque
# spawn sem shell não executa .cmd (EINVAL) e shell:true não é opção.
#
# O PATH falso vive só dentro do node (process.env.PATH), não no bash: trocar
# o PATH do bash some com o próprio `node` e o teste mede outra coisa.
set -euo pipefail
cd "$(dirname "$0")/.."

node - <<'JS'
const fs = require('fs');
const os = require('os');
const path = require('path');
const { acharExecutavelClaude } = require('./scripts/lib/achar-executavel-claude.cjs');

const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-achar-claude-'));
const sep = process.platform === 'win32' ? ';' : ':';
let ok = 0, falhas = 0;

function arquivo(...partes) {
  const p = path.join(raiz, ...partes);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, '');
  fs.chmodSync(p, 0o755);
  return p;
}
function caso(nome, dirs, esperado, env = {}) {
  process.env.PATH = dirs.map((d) => path.join(raiz, d)).join(sep);
  delete process.env.RFM_CLAUDE_EXECUTAVEL;
  Object.assign(process.env, env);
  const obtido = acharExecutavelClaude();
  if (obtido === esperado) { ok++; console.log(`ok   ${nome}`); }
  else { falhas++; console.log(`FALHA ${nome}: esperava ${esperado}, obteve ${obtido}`); }
}

try {
  if (process.platform === 'win32') {
    arquivo('p1', 'claude.cmd');
    const exe1 = arquivo('p1', 'node_modules', '@anthropic-ai', 'claude-code', 'bin', 'claude.exe');
    caso('.cmd com o .exe do pacote ao lado devolve o .exe', ['p1'], exe1);

    arquivo('p2a', 'claude.cmd');
    const exe2 = arquivo('p2b', 'claude.exe');
    caso('.cmd sem pacote é ignorado e a varredura segue', ['p2a', 'p2b'], exe2);

    arquivo('p3', 'claude.cmd');
    caso('só .cmd, sem .exe em lugar nenhum, devolve null', ['p3'], null);

    arquivo('p5', 'claude.bat');
    const exe5 = arquivo('p5', 'node_modules', '@anthropic-ai', 'claude-code', 'bin', 'claude.exe');
    caso('.bat segue a mesma regra do .cmd', ['p5'], exe5);
  }
  caso('RFM_CLAUDE_EXECUTAVEL sobrepõe a varredura', ['p3'], '/custom/claude',
    { RFM_CLAUDE_EXECUTAVEL: '/custom/claude' });
} finally {
  fs.rmSync(raiz, { recursive: true, force: true });
}
console.log(`${ok} ok, ${falhas} falha(s)`);
process.exit(falhas ? 1 : 0);
JS
