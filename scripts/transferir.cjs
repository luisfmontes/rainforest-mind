#!/usr/bin/env node
/**
 * Despachante de /transferir: decide entre Claude Code e Codex por destino.
 *
 * Sem argumento ou outro argumento → node scripts/transferir-para-codex.cjs (Codex).
 * Primeiro argumento 'claude' → node scripts/transferir-entre-contas.cjs com resto dos args.
 *
 * Repassam exit code do filho. Filhos devem estar ao lado do script (same directory).
 *
 * Suporte para testes: RFM_TEST=1 + RFM_TRANSFERIR_CLAUDE / RFM_TRANSFERIR_CODEX.
 *
 * Uso: node transferir.cjs [claude [--para trabalho|pessoal] [--forcar]] | [--ultimas <n>] [...]
 */

const { spawnSync } = require('child_process');
const path = require('path');

/**
 * Main.
 */
function main() {
  const argv = process.argv.slice(2);
  const scriptDir = path.dirname(__filename);

  // Alvo de mutação: esta linha decide o destino
  const paraClaude = argv[0] === 'claude';

  let childScript;
  let childArgs;

  if (paraClaude) {
    // Primeiro argumento é 'claude' → transferir-entre-contas.cjs recebe o resto
    childScript = 'transferir-entre-contas.cjs';
    childArgs = argv.slice(1);
  } else {
    // Qualquer outro caso (sem argumento, outro argumento) → transferir-para-codex.cjs
    childScript = 'transferir-para-codex.cjs';
    childArgs = argv;
  }

  // Resolve caminho do script filho
  let scriptPath = path.join(scriptDir, childScript);

  // Suporte para testes: override com env var (só com RFM_TEST=1)
  if (process.env.RFM_TEST === '1') {
    if (paraClaude && process.env.RFM_TRANSFERIR_CLAUDE) {
      scriptPath = process.env.RFM_TRANSFERIR_CLAUDE;
    } else if (!paraClaude && process.env.RFM_TRANSFERIR_CODEX) {
      scriptPath = process.env.RFM_TRANSFERIR_CODEX;
    }
  }

  // Executa filho com stdio herdado
  const resultado = spawnSync('node', [scriptPath, ...childArgs], {
    stdio: 'inherit',
    cwd: process.cwd(),
  });

  // Repassar exit code do filho
  process.exit(resultado.status || 0);
}

main();
