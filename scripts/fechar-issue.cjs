#!/usr/bin/env node
/**
 * Fecha Issue com evidência: comenta com comando + saída, só então fecha.
 *
 * Uso: node scripts/fechar-issue.cjs <n> --comando <c> --saida <arquivo-ou-texto>
 *
 * Exits:
 *   0 — comentário postado, Issue fechada
 *   1 — gh recusou (comentário ou close), saída dele colada
 *   2 — uso errado (sem flags, n inválido, etc.)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');
const { MARCADOR } = require(path.join(__dirname, '..', 'hooks', 'lib', 'marcador-evidencia.cjs'));

// Parse argumentos
const args = process.argv.slice(2);
if (args.length < 4) {
  console.error('Uso: node scripts/fechar-issue.cjs <n> --comando <c> --saida <arquivo-ou-texto>');
  process.exit(2);
}

const n = args[0];
if (!/^\d+$/.test(n)) {
  console.error(`Erro: número de Issue inválido: ${n}`);
  process.exit(2);
}

let comando = null;
let saida = null;

for (let i = 1; i < args.length; i++) {
  if (args[i] === '--comando' && i + 1 < args.length) {
    comando = args[++i];
  } else if (args[i] === '--saida' && i + 1 < args.length) {
    saida = args[++i];
  }
}

if (!comando || saida === null) {
  console.error('Erro: --comando e --saida são obrigatórios');
  process.exit(2);
}

// Ler saída: se for caminho existente, lê o arquivo; senão, trata como texto
let saidaConteudo = saida;
try {
  if (fs.existsSync(saida)) {
    saidaConteudo = fs.readFileSync(saida, 'utf-8');
  }
} catch {
  // Se der erro ao ler, trata como texto literal
}

// Montar corpo do comentário
const corpo = `${MARCADOR}

\`\`\`
${comando}
\`\`\`

\`\`\`
${saidaConteudo}
\`\`\`
`;

// Escrever em arquivo temporário
const tmpFile = path.join(os.tmpdir(), `fechar-issue-${Date.now()}-${Math.random().toString(36).substring(7)}.txt`);
fs.writeFileSync(tmpFile, corpo, 'utf-8');

try {
  // Chamar: gh issue comment
  const ghCmd = process.env.GH_CMD || 'gh';
  let commentResult;
  try {
    commentResult = spawnSync(ghCmd, ['issue', 'comment', n, '--body-file', tmpFile], {
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: false,
      encoding: 'utf-8',
      env: process.env
    });
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }

  if (commentResult.status !== 0) {
    const saida = commentResult.stdout || commentResult.stderr || '';
    console.error(saida);
    process.exit(1);
  }

  // Se comment foi 0, fechar a Issue
  let closeResult;
  try {
    closeResult = spawnSync(ghCmd, ['issue', 'close', n], {
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: false,
      encoding: 'utf-8',
      env: process.env
    });
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }

  if (closeResult.status !== 0) {
    const saida = closeResult.stdout || closeResult.stderr || '';
    console.error(saida);
    process.exit(1);
  }

  process.exit(0);
} finally {
  // Limpar arquivo temporário
  try {
    fs.unlinkSync(tmpFile);
  } catch {
    // Ignorar erro ao deletar
  }
}
