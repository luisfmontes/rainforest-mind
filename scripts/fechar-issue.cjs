#!/usr/bin/env node
/**
 * Fecha Issue com evidência: comenta com comando + saída, só então fecha.
 *
 * Uso: node scripts/fechar-issue.cjs <n> --comando <c> (--saida <texto> | --saida-arquivo <caminho>)
 *
 * Exits:
 *   0 — comentário postado, Issue fechada
 *   1 — gh recusou (comentário ou close), saída dele colada
 *   2 — uso errado (sem flags, n inválido, etc.)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { MARCADOR } = require(path.join(__dirname, '..', 'hooks', 'lib', 'marcador-evidencia.cjs'));
const { resolverExecutavel, executar } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));

// Parse argumentos
const args = process.argv.slice(2);

// Modo trava: verificar que gh é do sandbox (uso: node scripts/fechar-issue.cjs --verificar-gh <expected-dir>)
if (args[0] === '--verificar-gh' && args[1]) {
  const ghCmd = resolverExecutavel('gh');
  if (!ghCmd) {
    console.error('gh nao achado');
    process.exit(2);
  }
  const expectedDir = path.resolve(args[1]);
  const ghDir = path.dirname(path.resolve(ghCmd));
  if (ghDir !== expectedDir) {
    console.error(`gh nao eh do sandbox: ${ghCmd}`);
    process.exit(1);
  }
  console.log(`OK: gh eh do sandbox: ${ghCmd}`);
  process.exit(0);
}

if (args.length < 4) {
  console.error('Uso: node scripts/fechar-issue.cjs <n> --comando <c> (--saida <texto> | --saida-arquivo <caminho>)');
  process.exit(2);
}

const n = args[0];
if (!/^\d+$/.test(n)) {
  console.error(`Erro: número de Issue inválido: ${n}`);
  process.exit(2);
}

let comando = null;
let saidaConteudo = null;

for (let i = 1; i < args.length; i++) {
  if (args[i] === '--comando' && i + 1 < args.length) {
    comando = args[++i];
  } else if (args[i] === '--saida' && i + 1 < args.length) {
    saidaConteudo = args[++i];
  } else if (args[i] === '--saida-arquivo' && i + 1 < args.length) {
    const caminhoArquivo = args[++i];
    try {
      saidaConteudo = fs.readFileSync(caminhoArquivo, 'utf-8');
    } catch (err) {
      console.error(`Erro: não consegui ler arquivo ${caminhoArquivo}: ${err.message}`);
      process.exit(2);
    }
  }
}

if (!comando || saidaConteudo === null) {
  console.error('Erro: --comando e (--saida ou --saida-arquivo) são obrigatórios');
  process.exit(2);
}

// Verificar se gh existe (o executar() faz isso também)
if (!resolverExecutavel('gh')) {
  console.error('RECUSADO: nao achei o gh no PATH');
  process.exit(2);
}

// Ler o corpo da Issue para verificar se tem a seção obrigatória
const issueViewResult = executar('gh', ['issue', 'view', n, '--json', 'body'], {
  stdio: ['pipe', 'pipe', 'pipe']
});

if (issueViewResult.status !== 0) {
  const saida = issueViewResult.stdout || issueViewResult.stderr || '';
  console.error(saida);
  process.exit(1);
}

let issueBody = '';
try {
  const viewOutput = issueViewResult.stdout || '';
  const parsed = JSON.parse(viewOutput);
  issueBody = parsed.body || '';
} catch (err) {
  console.error(`Erro ao parsear resposta de 'gh issue view': ${err.message}`);
  process.exit(1);
}

// Verificar se o corpo contém a seção obrigatória
// Aceita tanto a versão com acentos quanto a versão ASCII
const temCriterio = /##\s+Criter[íi]o de pronto [\(\^]*falsific[áa]vel[\)\^]*/.test(issueBody);
if (!temCriterio) {
  console.error(`RECUSADO: a Issue #${n} nao tem a secao "Critério de pronto (falsificável)"`);
  process.exit(2);
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
  const commentResult = executar('gh', ['issue', 'comment', n, '--body-file', tmpFile], {
    stdio: ['pipe', 'pipe', 'pipe']
  });

  if (commentResult.status !== 0) {
    const saida = commentResult.stdout || commentResult.stderr || '';
    console.error(saida);
    process.exit(1);
  }

  // Se comment foi 0, fechar a Issue
  const closeResult = executar('gh', ['issue', 'close', n], {
    stdio: ['pipe', 'pipe', 'pipe']
  });

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
