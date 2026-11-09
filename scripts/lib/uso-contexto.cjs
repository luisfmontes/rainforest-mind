'use strict';
/**
 * Uso de contexto da sessão, lido do transcript, e o aviso de contexto alto
 * (design docs/rainforest/design/2026-11-09-aviso-contexto-alto.md).
 *
 * O transcript não traz o tamanho da janela, por isso o limiar é em tokens.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

// O registro mais recente fica no fim, e o arquivo inteiro passa de dezenas de MB.
const CAUDA_BYTES = 1024 * 1024;

function acharTranscrito(env) {
  const id = env.CLAUDE_CODE_SESSION_ID;
  if (!id || !/^[\w-]+$/.test(id)) return null;
  const projetos = path.join(env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'), 'projects');
  if (!fs.existsSync(projetos)) return null;
  // A pasta vem do cwd em que a sessão nasceu, que quem roda em worktree não conhece.
  for (const pasta of fs.readdirSync(projetos)) {
    const arquivo = path.join(projetos, pasta, `${id}.jsonl`);
    if (fs.existsSync(arquivo)) return arquivo;
  }
  return null;
}

function lerCauda(arquivo) {
  const fd = fs.openSync(arquivo, 'r');
  try {
    const { size } = fs.fstatSync(fd);
    const tamanho = Math.min(size, CAUDA_BYTES);
    const buffer = Buffer.alloc(tamanho);
    fs.readSync(fd, buffer, 0, tamanho, size - tamanho);
    return buffer.toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
}

/** Tokens do prompt na última mensagem da janela principal, ou null se não há medida. */
function usoDoTranscrito(env = process.env) {
  const arquivo = acharTranscrito(env);
  if (!arquivo) return null;
  const linhas = lerCauda(arquivo).split('\n');
  for (let i = linhas.length - 1; i >= 0; i -= 1) {
    let registro;
    try {
      registro = JSON.parse(linhas[i]);
    } catch {
      continue; // primeira linha cortada pela cauda, ou última ainda sendo escrita
    }
    const u = registro && registro.type === 'assistant' && !registro.isSidechain
      && registro.message && registro.message.usage;
    if (!u) continue;
    const total = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
    if (total > 0) return total; // zero é mensagem <synthetic>, sem chamada ao modelo
  }
  return null;
}

/** A linha de aviso quando o uso alcançou o limiar; null abaixo dele ou com limiar 0. */
function avisoDeContexto(limiar, estagio, env = process.env) {
  if (!limiar) return null;
  const uso = usoDoTranscrito(env);
  if (uso === null || uso < limiar) return null;
  const mil = (n) => Math.round(n / 1000);
  return `aviso: contexto em ${mil(uso)} mil tokens (limiar ${mil(limiar)} mil). `
    + `Antes de abrir '${estagio}', registre o estado e considere /compact ou uma sessão nova.`;
}

module.exports = { usoDoTranscrito, avisoDeContexto };
