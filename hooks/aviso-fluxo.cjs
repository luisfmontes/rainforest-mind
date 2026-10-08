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
 * O repositório é o do ARQUIVO editado, não o do cwd da sessão (emenda 1 do plano, D1/D9):
 * sessão no checkout principal editando um worktree de fluxo aberto passa.
 *
 * Extensões de código (comparadas em minúsculas): .js .cjs .mjs .ts .tsx .jsx .py .sh .ps1 .psm1 .prw .prx .tlpp .ch .go .rs .java .cs .rb .php .sql .c .h .cpp .bat .cmd
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { caminhoExecutavel } = require(path.join(__dirname, 'lib', 'resolver-executavel.cjs'));
const { resolver } = require('./lib/estagio-ativo.cjs');
const { leveDaBranch, protheusAberto } = require('./lib/caminho-leve.cjs');

// Caminho absoluto do estado.cjs do plugin, com barras normais: o comando da mensagem
// roda em bash e em PowerShell sem escapar contrabarra.
const SCRIPT_ESTADO = path.resolve(__dirname, '..', 'scripts', 'estado.cjs').split(path.sep).join('/');

const EXTENSOES_CODIGO = new Set([
  '.js', '.cjs', '.mjs', '.ts', '.tsx', '.jsx',
  '.py', '.sh', '.ps1', '.psm1', '.prw', '.prx', '.tlpp', '.ch',
  '.go', '.rs', '.java', '.cs', '.rb', '.php', '.sql',
  '.c', '.h', '.cpp', '.bat', '.cmd'
]);

// Primeiro diretório que existe, subindo a partir de `p` (o próprio `p` se já for diretório).
// Arquivo novo, ou em diretório ainda inexistente, cai no pai: o repositório do arquivo é
// achado por ele.
function diretorioExistente(p) {
  let atual = p;
  for (;;) {
    try {
      if (fs.statSync(atual).isDirectory()) return atual;
    } catch {}
    const pai = path.dirname(atual);
    if (pai === atual) return atual;
    atual = pai;
  }
}

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

// Branch padrão do repositório do arquivo: origin/HEAD, e main/master sempre. É o mesmo critério
// que o `leve` do scripts/estado.cjs aplica (branchPadrao + ['main','master'], D7): se o gate
// oferecesse o leve onde o estado recusa, a mensagem levaria a um beco. Cópia local porque o
// estado.cjs é script com efeito ao ser carregado e não exporta o helper.
function ehBranchPadraoDoRepo(gitTop, branch) {
  if (!branch) return false;
  if (branch === 'main' || branch === 'master') return true;
  try {
    const ref = execFileSync(caminhoExecutavel('git'), ['-C', gitTop, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return ref.replace(/^origin\//, '') === branch;
  } catch {
    return false;
  }
}

// Caminho com barras normais, para colar em comando que roda em bash e em PowerShell.
function barras(p) {
  return p.split(path.sep).join('/');
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
    // Protheus: o predicado por arquivo (campo `branch`, senão mtime < 24 h) mora em caminho-leve.cjs (D10)
    return protheusAberto({ gitTop, branch: branchAtual(gitTop) });
  }
  return false;
}

// HEAD destacado: não há branch para o `leve` (o estado.cjs recusa), então a única saída é trocar.
function mensagemHeadDestacado(trilho) {
  const abrir = trilho === 'rainforest' ? '/rainforest-mind:brainstorm' : '/protheus:trabalhar';
  return [
    `BLOQUEADO: este repositório tem fluxo ${trilho} e a sessão está em HEAD destacado (sem branch). Edição de código sem branch não passa.`,
    `Saída: troque para uma branch e abra o fluxo nela: \`git switch -c fluxo/<nome>\`, depois ${abrir}.`,
  ].join('\n');
}

// `ofereceLeve` false só no rainforest na branch padrão: lá o `leve` é recusado (D7), então a
// saída é o worktree. O `--repo` aponta o repositório do arquivo (emenda 2, #430).
function mensagemBloqueio(trilho, branch, ofereceLeve, gitTop) {
  const iniciar = `node ${SCRIPT_ESTADO} iniciar --slug <slug>`;
  const leve = `node ${SCRIPT_ESTADO} leve --motivo "<por quê>" --repo "${barras(gitTop)}"`;
  if (trilho === 'rainforest') {
    if (!ofereceLeve) {
      return [
        `BLOQUEADO: este repositório tem fluxo rainforest e nenhum está aberto na branch '${branch}', que é a branch padrão. Edição de código direto nela não passa.`,
        `Saída: trabalhe num worktree e abra o fluxo nele: \`git worktree add .claude/worktrees/<nome> -b fluxo/<nome>\`, entre no worktree e rode /rainforest-mind:brainstorm (roda \`${iniciar}\`).`,
      ].join('\n');
    }
    return [
      `BLOQUEADO: este repositório tem fluxo rainforest e nenhum está aberto na branch '${branch}'. Edição de código sem fluxo não passa.`,
      `Saída 1, abrir o fluxo: /rainforest-mind:brainstorm (roda \`${iniciar}\`).`,
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
  const ext = path.extname(filePath).toLowerCase();
  if (!EXTENSOES_CODIGO.has(ext)) {
    process.exit(0);
  }

  // Critério 4: repositório git do ARQUIVO (não do cwd): emenda 1 do plano, D1
  if (!ev.cwd) process.exit(0);
  const gitTop = toplevel(diretorioExistente(path.resolve(ev.cwd, filePath)));
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

  // HEAD destacado: sem branch não há fluxo nem `leve` possível (o estado.cjs recusa).
  const branch = branchAtual(gitTop);
  const headDestacado = branch === 'HEAD';

  // Critério 8: a branch tem o caminho leve declarado (D6, D7)
  if (!headDestacado && branch && leveDaBranch({ gitTop, branch })) {
    process.exit(0);
  }

  // Bloqueio (D7, D9): o leve só é oferecido onde o estado.cjs o aceita.
  const ehBranchPadrao = ehBranchPadraoDoRepo(gitTop, branch);
  const ofereceLeve = !headDestacado && !(trilho === 'rainforest' && ehBranchPadrao);
  const texto = headDestacado
    ? mensagemHeadDestacado(trilho)
    : mensagemBloqueio(trilho, branch || 'desconhecida', ofereceLeve, gitTop);

  // fs.writeSync garante que a mensagem sai antes do exit.
  fs.writeSync(2, texto + '\n');
  process.exit(2); // bloqueio-fluxo
}

main();
