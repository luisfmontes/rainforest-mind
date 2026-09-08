#!/usr/bin/env node
/**
 * Hook SessionStart: injeta variáveis de ambiente para transferência de sessão.
 *
 * Se `transfer-codex` está ligado, grava RAINFOREST_TRANSCRIPT_PATH e
 * RAINFOREST_SESSION_ID no arquivo apontado por CLAUDE_ENV_FILE (append).
 * Sem o arquivo de saída, sai 0 silencioso.
 * Qualquer exceção sai 0 — SessionStart não pode derrubar a sessão.
 */

const fs = require('fs');
const path = require('path');
const { resolverConfig } = require('./lib/config.cjs');

function lerEvento() {
  try {
    const input = fs.readFileSync(0, 'utf8');
    return JSON.parse(input);
  } catch {
    return {};
  }
}

function main() {
  try {
    const evento = lerEvento();
    const { session_id, transcript_path } = evento;

    // Verifica se transfer-codex está ligado
    const config = resolverConfig();
    const estaLigado = config.valores['transfer-codex'] === true;

    if (!estaLigado) {
      process.exit(0);
    }

    // Verifica se CLAUDE_ENV_FILE foi fornecido
    const envFile = process.env.CLAUDE_ENV_FILE;
    if (!envFile) {
      process.exit(0);
    }

    // Valida que temos os dados necessários
    if (!session_id || !transcript_path) {
      process.exit(0);
    }

    // Append das variáveis no arquivo
    const linhas = [
      `RAINFOREST_TRANSCRIPT_PATH=${transcript_path}`,
      `RAINFOREST_SESSION_ID=${session_id}`,
    ];

    try {
      fs.appendFileSync(envFile, linhas.join('\n') + '\n', 'utf8');
    } catch {
      // Falha ao escrever, mas não bloqueia a sessão
      process.exit(0);
    }

    process.exit(0);
  } catch {
    // Qualquer exceção sai 0
    process.exit(0);
  }
}

main();
