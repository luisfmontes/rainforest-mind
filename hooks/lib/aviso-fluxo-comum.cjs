// @categoria: guia
/**
 * Helpers comuns aos dois avisos de codigo sem fluxo: o PreToolUse de Edit/Write
 * (`aviso-fluxo.cjs`, #430) e o PostToolUse de Bash/PowerShell
 * (`aviso-fluxo-shell.cjs`, #564). Sairam do `aviso-fluxo.cjs` sem mudar o texto das
 * mensagens: os dois hooks dizem a mesma coisa com o mesmo comando colavel.
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { caminhoExecutavel } = require(path.join(__dirname, 'resolver-executavel.cjs'));
const { resolver } = require('./estagio-ativo.cjs');
const { protheusAberto } = require('./caminho-leve.cjs');

// Caminho absoluto do estado.cjs do plugin, com barras normais: o comando da mensagem
// cola em bash sem escapar contrabarra. Em PowerShell, linha que começa por string entre
// aspas só roda com `& ` na frente, e não há forma única para os dois shells (`&` à frente
// é erro em bash): a mensagem leva a dica (Issue #442).
const SCRIPT_ESTADO = path.resolve(__dirname, '..', '..', 'scripts', 'estado.cjs').split(path.sep).join('/');
// O node vai pelo caminho do processo, entre aspas (#430, emenda 4): nome nu resolve pela
// busca do SO, e caminho com espaço quebra sem aspas.
const NODE_BARRAS = process.execPath.split(path.sep).join('/');
const DICA_POWERSHELL = 'Em PowerShell, prefixe `& ` ao comando.';

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

// Caminho com barras normais, para colar em comando sem escapar contrabarra (em PowerShell,
// com `& ` na frente: DICA_POWERSHELL).
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
  // Issue #474: aspas SIMPLES, literais no bash e no PowerShell (ver hooks/lib/comando-colavel.cjs).
  const { seguro: colavel, aspas } = require('./comando-colavel.cjs');
  const repoBarras = barras(gitTop);
  const podeColar = colavel(NODE_BARRAS, SCRIPT_ESTADO, repoBarras);
  const semComando = `(caminho com aspa simples ou caractere de controle: rode o estado.cjs de ${JSON.stringify(SCRIPT_ESTADO)} com o node de ${JSON.stringify(NODE_BARRAS)})`;
  const iniciar = podeColar ? `${aspas(NODE_BARRAS)} ${aspas(SCRIPT_ESTADO)} iniciar --slug <slug>` : `${semComando} iniciar --slug <slug>`;
  const leve = podeColar
    ? `${aspas(NODE_BARRAS)} ${aspas(SCRIPT_ESTADO)} leve --motivo '<por quê>' --repo ${aspas(repoBarras)}`
    : `${semComando} leve --motivo '<por quê>' --repo ${JSON.stringify(repoBarras)}`;
  if (trilho === 'rainforest') {
    if (!ofereceLeve) {
      return [
        `BLOQUEADO: este repositório tem fluxo rainforest e nenhum está aberto na branch '${branch}', que é a branch padrão. Edição de código direto nela não passa.`,
        `Saída: trabalhe num worktree e abra o fluxo nele: \`git worktree add .claude/worktrees/<nome> -b fluxo/<nome>\`, entre no worktree e rode /rainforest-mind:brainstorm (roda \`${iniciar}\`).`,
        DICA_POWERSHELL,
      ].join('\n');
    }
    return [
      `BLOQUEADO: este repositório tem fluxo rainforest e nenhum está aberto na branch '${branch}'. Edição de código sem fluxo não passa.`,
      `Saída 1, abrir o fluxo: /rainforest-mind:brainstorm (roda \`${iniciar}\`).`,
      `Saída 2, caminho leve declarado para hotfix mecânico: \`${leve}\``,
      DICA_POWERSHELL,
    ].join('\n');
  }
  return [
    `BLOQUEADO: este repositório tem fluxo protheus e nenhum está aberto na branch '${branch}'. Edição de código sem fluxo não passa.`,
    `Saída 1, abrir o fluxo: /protheus:trabalhar.`,
    `Saída 2, caminho leve declarado para hotfix mecânico: \`${leve}\``,
    DICA_POWERSHELL,
  ].join('\n');
}

module.exports = {
  SCRIPT_ESTADO, NODE_BARRAS, DICA_POWERSHELL, EXTENSOES_CODIGO,
  diretorioExistente, toplevel, branchAtual, ehBranchPadraoDoRepo, barras,
  detectarTrilho, fluXoAberto, mensagemHeadDestacado, mensagemBloqueio,
};
