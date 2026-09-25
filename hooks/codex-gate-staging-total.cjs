#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const MOTIVO_FALHA_SEGURA =
  'Falha interna do gate de staging; comando recusado por seguranca.';

function negar(motivo) {
  process.stdout.write(`${JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: motivo,
    },
  })}\n`);
}

function main() {
  let payload;
  try {
    payload = fs.readFileSync(0);
    JSON.parse(payload.toString('utf8'));
  } catch {
    negar(MOTIVO_FALHA_SEGURA);
    return;
  }

  let resultado;
  try {
    resultado = spawnSync(process.execPath, [path.join(__dirname, 'gate-staging-total.cjs')], {
      cwd: process.cwd(),
      env: process.env,
      input: payload,
      encoding: 'utf8',
      shell: false,
    });
  } catch {
    negar(MOTIVO_FALHA_SEGURA);
    return;
  }

  if (!resultado.error && resultado.status === 0) return;

  const motivo = typeof resultado.stderr === 'string' ? resultado.stderr.trim() : '';
  if (!resultado.error && resultado.status === 2 && motivo !== '') {
    negar(motivo);
    return;
  }

  negar(MOTIVO_FALHA_SEGURA);
}

main();
