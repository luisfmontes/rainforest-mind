#!/usr/bin/env node
// @categoria: guia
/**
 * Bloqueio de edição de código sem fluxo e sem caminho leve (#430).
 *
 * Bloqueia (exit 2, mensagem em stderr) o Edit/Write/MultiEdit de arquivo de código
 * fora de docs/ quando o repositório tem fluxo (rainforest ou protheus), nenhum está
 * aberto e a branch não tem o registro `leve` (`estado.cjs leve --motivo`). Repete a
 * cada edição: não há memória por sessão (D8 do design 2026-10-08-fluxo-pulado-bloqueio).
 *
 * A mensagem nomeia as duas saídas com comando pronto (D9): abrir o fluxo, ou o caminho
 * leve declarado. Chave `aviso-fluxo` do config desliga tudo (D4). Subagente (agent_id)
 * não é barrado aqui: quem barra o despacho de agente que edita é a portaria.
 *
 * Extensões de código: .js .cjs .mjs .ts .tsx .jsx .py .sh .ps1 .psm1 .prw .prx .tlpp .ch .go .rs .java .cs .rb .php .sql
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { caminhoExecutavel } = require(path.join(__dirname, 'lib', 'resolver-executavel.cjs'));
const { resolver } = require('./lib/estagio-ativo.cjs');
const { leveDaBranch } = require('./lib/caminho-leve.cjs');

// Caminho absoluto do estado.cjs do plugin, com barras normais: o comando da mensagem
// roda em bash e em PowerShell sem escapar contrabarra.
const SCRIPT_ESTADO = path.resolve(__dirname, '..', 'scripts', 'estado.cjs').split(path.sep).join('/');

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

function branchAtual(gitTop) {
  try {
    return execFileSync(caminhoExecutavel('git'), ['-C', gitTop, 'rev-parse', '--abbrev-ref', 'HEAD'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim() || null;
  } catch {
    return null;
  }
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

function mensagemBloqueio(trilho, branch) {
  const leve = `node ${SCRIPT_ESTADO} leve --motivo "<por quê>"`;
  if (trilho === 'rainforest') {
    return [
      `BLOQUEADO: este repositório tem fluxo rainforest e nenhum está aberto na branch '${branch}'. Edição de código sem fluxo não passa.`,
      `Saída 1, abrir o fluxo: /rainforest-mind:brainstorm (roda \`node ${SCRIPT_ESTADO} iniciar --slug <slug>\`).`,
      `Saída 2, caminho leve declarado para hotfix mecânico: \`${leve}\``,
    ].join('\n');
  }
  return [
    `BLOQUEADO: este repositório tem fluxo protheus e nenhum está aberto na branch '${branch}'. Edição de código sem fluxo não passa.`,
    `Saída 1, abrir o fluxo: /protheus:trabalhar.`,
    `Saída 2, caminho leve declarado para hotfix mecânico: \`${leve}\``,
  ].join('\n');
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0); // payload ilegível — não impacta a sessão
  }
  if (!ev || typeof ev !== 'object') process.exit(0);

  // Critério 1: sem agent_id (subagentes são barrados pela portaria, não aqui)
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

  // Critério 6: config permite a trava (chave `aviso-fluxo`, padrão ligada)
  try {
    if (!require('./lib/config.cjs').ligado('aviso-fluxo', { projeto: gitTop })) {
      process.exit(0);
    }
  } catch {}

  // Critério 7: há fluxo aberto na branch
  if (fluXoAberto(gitTop, trilho)) {
    process.exit(0);
  }

  // Critério 8: a branch tem o caminho leve declarado (D6, D7)
  const branch = branchAtual(gitTop);
  if (branch && leveDaBranch({ gitTop, branch })) {
    process.exit(0);
  }

  // Bloqueio: fs.writeSync garante que a mensagem sai antes do exit.
  fs.writeSync(2, mensagemBloqueio(trilho, branch || 'desconhecida') + '\n');
  process.exit(2); // bloqueio-fluxo
}

main();
