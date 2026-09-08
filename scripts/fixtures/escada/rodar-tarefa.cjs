#!/usr/bin/env node
/**
 * Roda uma tarefa contra um CLI e retorna o código gerado.
 *
 * Uso:
 *   node scripts/fixtures/escada/rodar-tarefa.cjs <tarefa> <cli-cmd> [com-escada]
 */

const fs = require('fs');
const path = require('path');

// Descobrir raiz do projeto (onde estou no worktree)
const projectRoot = path.resolve(__dirname, '../../..');

// Require a partir da raiz
const rodarCli = require(path.join(projectRoot, 'hooks/lib/cli-externo.cjs')).rodarCli;
const extrairEscada = require(path.join(projectRoot, 'hooks/lib/escada.cjs')).extrairEscada;

const tarefa = process.argv[2];
const cliCmd = process.argv[3];
const comEscada = process.argv[4] === 'true';

const promptFile = path.join(__dirname, `${tarefa}.txt`);

if (!fs.existsSync(promptFile)) {
  console.error(`ERRO: ${promptFile} não existe`);
  process.exit(1);
}

let entrada = fs.readFileSync(promptFile, 'utf8');

if (comEscada) {
  try {
    const skillText = fs.readFileSync(path.join(projectRoot, 'skills/modo-dev/SKILL.md'), 'utf8');
    const escada = extrairEscada(skillText);
    if (escada) {
      entrada = entrada + '\n---\n' + escada;
    }
  } catch (e) {
    // Ignorar
  }
}

try {
  const resultado = rodarCli({
    cmd: cliCmd,
    entrada,
    timeoutMs: 30000
  });

  console.log(resultado.stdout || '');
  process.exit(0);
} catch (e) {
  console.error(`ERRO ao rodar tarefa: ${e.message}`);
  process.exit(1);
}
