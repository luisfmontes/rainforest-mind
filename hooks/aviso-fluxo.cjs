#!/usr/bin/env node
// @categoria: guia
/**
 * Aviso de fluxo no primeiro Edit de código da sessão.
 *
 * Dispara uma única vez por sessão quando há um fluxo aberto (rainforest ou
 * protheus) no repositório e o usuário edita um arquivo de código, alertando
 * que precisa abrir ou pular o fluxo.
 *
 * Não bloqueia (exit 0 sempre). Memória por sessão em <git-dir>/rainforest-aviso-fluxo.json,
 * com teto de 50 sessões (molde de gate-agente-em-voo).
 *
 * Extensões de código: .js .cjs .mjs .ts .tsx .jsx .py .sh .ps1 .psm1 .prw .prx .tlpp .ch .go .rs .java .cs .rb .php .sql
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { caminhoExecutavel } = require(path.join(__dirname, 'lib', 'resolver-executavel.cjs'));
const { resolver } = require('./lib/estagio-ativo.cjs');

const EXTENSOES_CODIGO = new Set([
  '.js', '.cjs', '.mjs', '.ts', '.tsx', '.jsx',
  '.py', '.sh', '.ps1', '.psm1', '.prw', '.prx', '.tlpp', '.ch',
  '.go', '.rs', '.java', '.cs', '.rb', '.php', '.sql'
]);

function toplevel(cwd) {
  try {
    return execFileSync(caminhoExecutavel('git'), ['-C', cwd, 'rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim() || null;
  } catch {
    return null;
  }
}

function gitDir(gitTop) {
  try {
    const saida = execFileSync(caminhoExecutavel('git'), ['-C', gitTop, 'rev-parse', '--git-dir'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    if (!saida) return null;
    return path.isAbsolute(saida) ? saida : path.resolve(gitTop, saida);
  } catch {
    return null;
  }
}

function leAviso(caminho) {
  try {
    return JSON.parse(fs.readFileSync(caminho, 'utf8'));
  } catch {
    return null;
  }
}

function sessaoJaAvisada(memoria, sessionId) {
  if (!sessionId) return false;
  if (!memoria || typeof memoria !== 'object' || !memoria.sessoes) return false;
  return sessionId in memoria.sessoes;
}

const MAX_SESSOES_LEMBRADAS = 50;

function gravaAviso(caminho, memoria, sessionId) {
  try {
    const sessoes = memoria && typeof memoria === 'object' && memoria.sessoes && typeof memoria.sessoes === 'object'
      ? { ...memoria.sessoes }
      : {};
    sessoes[sessionId] = new Date().toISOString();
    const recentes = Object.entries(sessoes)
      .sort((a, b) => {
        const timeA = new Date(a[1]).getTime() || 0;
        const timeB = new Date(b[1]).getTime() || 0;
        return timeB - timeA;
      })
      .slice(0, MAX_SESSOES_LEMBRADAS);
    fs.writeFileSync(caminho, JSON.stringify({ sessoes: Object.fromEntries(recentes) }, null, 2) + '\n');
  } catch {}
}

function detectarTrilho(gitTop) {
  // Rainforest: docs/rainforest/estado/ existe
  const dirEstado = path.join(gitTop, 'docs', 'rainforest', 'estado');
  if (fs.existsSync(dirEstado)) {
    return 'rainforest';
  }

  // Protheus: algum docs/plans/*.gates.json existe
  const dirPlans = path.join(gitTop, 'docs', 'plans');
  try {
    if (fs.existsSync(dirPlans)) {
      const arquivos = fs.readdirSync(dirPlans);
      if (arquivos.some(f => f.endsWith('.gates.json'))) {
        return 'protheus';
      }
    }
  } catch {}

  return null;
}

function fluXoAberto(gitTop, trilho) {
  if (trilho === 'rainforest') {
    // Rainforest: usar resolver (null = nenhum aberto)
    const ativo = resolver({ cwd: gitTop });
    return ativo !== null;
  } else if (trilho === 'protheus') {
    // Protheus: qualquer .gates.json com mtime < 24h significa aberto
    const dirPlans = path.join(gitTop, 'docs', 'plans');
    try {
      const arquivos = fs.readdirSync(dirPlans);
      const agora = Date.now();
      const umDiaEm_ms = 24 * 3600 * 1000;
      for (const f of arquivos) {
        if (f.endsWith('.gates.json')) {
          const pCompleto = path.join(dirPlans, f);
          const stats = fs.statSync(pCompleto);
          if (agora - stats.mtimeMs < umDiaEm_ms) {
            return true;
          }
        }
      }
    } catch {}
  }
  return false;
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0); // payload ilegível — não impacta a sessão
  }

  // Critério 1: sem agent_id (subagentes não recebem aviso)
  if (typeof ev.agent_id === 'string' && ev.agent_id) {
    process.exit(0);
  }

  // Critério 2: arquivo com extensão de código
  if (!ev.tool_input || typeof ev.tool_input !== 'object' || !ev.tool_input.file_path) {
    process.exit(0);
  }
  const filePath = ev.tool_input.file_path;
  const ext = path.extname(filePath);
  if (!EXTENSOES_CODIGO.has(ext)) {
    process.exit(0);
  }

  // Critério 4: repositório git
  if (!ev.cwd) process.exit(0);
  const gitTop = toplevel(ev.cwd);
  if (!gitTop) process.exit(0);

  // Critério 3: arquivo não sob docs/
  // Caminho real dos dois lados: no Windows o temp pode vir em nome curto 8.3
  // (`RUNNER~1`) e o git devolve o longo, e o `relative` subia com `..`.
  const real = (p) => {
    try { return fs.realpathSync.native(p); } catch { /* arquivo novo: sobe ao pai */ }
    try { return path.join(fs.realpathSync.native(path.dirname(p)), path.basename(p)); } catch { return p; }
  };
  const normalize = (p) => p.split(/[\\/]/).join('/');
  const relPath = normalize(path.relative(real(gitTop), real(path.resolve(ev.cwd, filePath))));
  const partes = relPath.split('/');
  if (partes[0] === 'docs') {
    process.exit(0);
  }

  // Critério 5: repositório com fluxo (rainforest ou protheus)
  const trilho = detectarTrilho(gitTop);
  if (!trilho) {
    process.exit(0);
  }

  // Critério 6: config permite aviso
  try {
    if (!require('./lib/config.cjs').ligado('aviso-fluxo', { projeto: gitTop })) {
      process.exit(0);
    }
  } catch {}

  // Critério 7: não há fluxo aberto (se houver fluxo aberto, silencia)
  if (fluXoAberto(gitTop, trilho)) {
    process.exit(0);
  }

  // Critério 8: primeira edição da sessão (memória)
  let sessionId = typeof ev.session_id === 'string' && ev.session_id ? ev.session_id : null;
  let caminhoAviso = null;
  let memoria = null;

  if (sessionId) {
    const gd = gitDir(gitTop);
    if (gd) {
      caminhoAviso = path.join(gd, 'rainforest-aviso-fluxo.json');
      memoria = leAviso(caminhoAviso);
      if (sessaoJaAvisada(memoria, sessionId)) process.exit(0);
    }
  }

  // Montar mensagem de aviso
  let aviso = '';
  if (trilho === 'rainforest') {
    aviso = 'Este repositório tem fluxo rainforest e nenhum está aberto nesta sessão. Abra o fluxo (`/rainforest-mind:brainstorm`, que roda `node scripts/estado.cjs iniciar --slug <slug>`) ou diga ao usuário que pula, e por quê.';
  } else if (trilho === 'protheus') {
    aviso = 'Este repositório tem fluxo protheus e nenhum está aberto nesta sessão. Abra o fluxo com `/protheus:trabalhar` ou diga ao usuário que pula, e por quê.';
  }

  // Truncar em 400 B
  if (aviso.length > 400) {
    aviso = aviso.substring(0, 400);
  }

  // Gravar memória antes de emitir (para que erro de escrita não mude stdout)
  if (sessionId && caminhoAviso) {
    gravaAviso(caminhoAviso, memoria, sessionId);
  }

  // Emitir aviso
  const saida = {
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      additionalContext: aviso,
    },
  };

  console.log(JSON.stringify(saida));
  process.exit(0);
}

main();
