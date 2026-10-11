#!/usr/bin/env node
/**
 * Despachante de /transferir: leva a sessão para o Codex CLI.
 *
 * Sem argumento ou com qualquer argumento → node scripts/transferir-para-codex.cjs (Codex).
 * Primeiro argumento 'claude' → recusa com exit 2: a troca de conta da pasta é do /conta.
 *
 * Repassa exit code do filho. Filho deve estar ao lado do script (same directory).
 *
 * Suporte para testes: RFM_TEST=1 + RFM_TRANSFERIR_CODEX.
 *
 * Uso: node transferir.cjs [--ultimas <n>] [...]
 */

const { spawnSync } = require('child_process');
const path = require('path');

const MSG_SAIU = 'o /transferir claude saiu: use /conta para trocar a conta da pasta';

/**
 * Encerra com código e mensagem no stderr.
 */
function sair(codigo, mensagem) {
  console.error(mensagem);
  process.exit(codigo);
}

/**
 * Main.
 */
function main() {
  const argv = process.argv.slice(2);
  const scriptDir = path.dirname(__filename);

  // Alvo de mutação: esta linha recusa o destino claude
  const paraClaude = argv[0] === 'claude';
  if (paraClaude) return sair(2, MSG_SAIU);

  // Resolve caminho do script filho
  let scriptPath = path.join(scriptDir, 'transferir-para-codex.cjs');

  // Suporte para testes: override com env var (só com RFM_TEST=1)
  if (process.env.RFM_TEST === '1' && process.env.RFM_TRANSFERIR_CODEX) {
    scriptPath = process.env.RFM_TRANSFERIR_CODEX;
  }

  // Executa filho com stdio herdado
  const resultado = spawnSync(process.execPath, [scriptPath, ...argv], {
    stdio: 'inherit',
    cwd: process.cwd(),
  });

  // Repassar exit code do filho. status null = o filho nao terminou por conta
  // propria (morto por sinal, ou nem subiu): isso nunca e sucesso.
  if (resultado.status === null) {
    const motivo = resultado.error ? resultado.error.message : `sinal ${resultado.signal}`;
    console.error(`erro: o script de transferencia nao terminou (${motivo})`);
    process.exit(1);
  }
  process.exit(resultado.status);
}

main();
