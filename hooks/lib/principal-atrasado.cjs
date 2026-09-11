// Aviso de principal atrasado e worktrees já integradas.
//
// Sessão isolada em worktree não pode atualizar o checkout principal. Este módulo
// exporta uma função que detecta quando o principal está atrás de origin/main e
// quando worktrees linkadas têm branches já contidas em origin/main — ambos os
// casos em que a abertura pode avisar e sugerir ação.
//
// Estratégia: sem fetch (hook de abertura não vai à rede), só refs locais.

const { execFileSync } = require('child_process');
const path = require('path');

// `git worktree list --porcelain` sempre imprime `/` nos caminhos, mesmo no
// Windows; `path.dirname`/`path.resolve` do módulo `path` (win32) devolvem `\`.
// Sem normalizar, `wtPath === principal` nunca bate no Windows e o próprio
// checkout principal (sem worktree nenhum linkado) aparece na própria lista
// como "já em origin/main" apontando pra si mesmo — bug real, achado pela
// bateria (caso "principal em dia" devolvia uma linha em vez de []).
function normalizarCaminho(p) {
  return p.replace(/\\/g, '/').replace(/\/+$/, '');
}

/**
 * Resolve o checkout principal a partir de cwd.
 *
 * Tenta `git rev-parse --git-common-dir` primeiro (aponta para `.git` do repositório
 * compartilhado). Se falhar, tenta `git worktree list --porcelain` que lista o
 * principal como primeira entrada.
 *
 * @param {string} cwd diretório da worktree ou repo
 * @returns {string|null} caminho do checkout principal, ou null se não conseguir resolver
 */
function resolverPrincipal(cwd) {
  try {
    const gitCommonDir = execFileSync('git', ['rev-parse', '--git-common-dir'], {
      cwd,
      encoding: 'utf8',
      timeout: 3000,
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();

    // gitCommonDir é um caminho relativo ou absoluto até .git
    // Para uma worktree, aponta para .git compartilhado do principal
    // Precisamos subir para o checkout principal
    const absPath = path.isAbsolute(gitCommonDir) ? gitCommonDir : path.resolve(cwd, gitCommonDir);
    const principalDir = path.dirname(absPath);
    return principalDir;
  } catch {
    // Fallback: tentar git worktree list --porcelain
    try {
      const output = execFileSync('git', ['worktree', 'list', '--porcelain'], {
        cwd,
        encoding: 'utf8',
        timeout: 3000,
        stdio: ['ignore', 'pipe', 'ignore'],
      });

      const linhas = output.split('\n').filter((l) => l.trim());
      // Primeira linha é worktree /path [extra info]
      if (linhas.length > 0) {
        const match = linhas[0].match(/^worktree\s+(.+?)(?:\s|$)/);
        if (match) {
          return match[1];
        }
      }
    } catch {
      // sem suporte a worktree ou erro
    }
  }

  return null;
}

/**
 * Aviso de principal e worktrees.
 *
 * Detecta:
 * 1. Quando o principal está `N commit(s) atrás de origin/main`
 * 2. Quando worktrees linkadas têm branches já contidas em `origin/main`
 *
 * @param {Object} o objeto de opções
 * @param {string} o.cwd diretório a partir do qual resolver o principal
 * @returns {string[]} array de strings (linhas) ou [] se tudo em dia
 */
function linhas({ cwd }) {
  const resultado = [];

  if (!cwd) return resultado;

  try {
    const principal = resolverPrincipal(cwd);
    if (!principal) return resultado;

    // Contar commits atrás de origin/main (sem fetch)
    let atras = 0;
    try {
      const countOutput = execFileSync('git', ['rev-list', '--count', 'HEAD..origin/main'], {
        cwd: principal,
        encoding: 'utf8',
        timeout: 3000,
        stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();

      atras = parseInt(countOutput, 10) || 0;
    } catch {
      // sem origin/main ou erro, continua
    }

    // Crítico: exatamente este if (atras > 0), sem variações
    if (atras > 0) {
      resultado.push(`${atras} commit(s) atrás de origin/main`);
      resultado.push(`git -C ${principal} pull --ff-only`);
    }

    // Listar worktrees linkadas cuja branch está em origin/main
    try {
      const worktreesOutput = execFileSync('git', ['worktree', 'list', '--porcelain'], {
        cwd: principal,
        encoding: 'utf8',
        timeout: 3000,
        stdio: ['ignore', 'pipe', 'ignore'],
      });

      const wtLinhas = worktreesOutput.split('\n').filter((l) => l.trim());

      for (const linha of wtLinhas) {
        // Formato: "worktree /path" ou "worktree /path (detached)"
        const match = linha.match(/^worktree\s+(.+?)(?:\s|$)/);
        if (!match) continue;

        const wtPath = match[1].trim();
        // Excluir o principal (já processado acima) — comparação normalizada,
        // ver normalizarCaminho() no topo do arquivo.
        if (normalizarCaminho(wtPath) === normalizarCaminho(principal)) continue;

        // Pegar a branch da worktree
        let branch;
        try {
          branch = execFileSync('git', ['symbolic-ref', '--short', 'HEAD'], {
            cwd: wtPath,
            encoding: 'utf8',
            timeout: 3000,
            stdio: ['ignore', 'pipe', 'ignore'],
          }).trim();
        } catch {
          // detached HEAD, skip
          continue;
        }

        if (!branch) continue;

        // Verificar se branch é ancestral de origin/main
        let estaEmMain = false;
        try {
          execFileSync('git', ['merge-base', '--is-ancestor', branch, 'origin/main'], {
            cwd: principal,
            timeout: 3000,
            stdio: ['ignore', 'ignore', 'ignore'],
          });
          estaEmMain = true;
        } catch {
          // exit code ≠ 0, branch não está em origin/main
        }

        if (estaEmMain) {
          resultado.push(`${wtPath} já em origin/main`);
        }
      }
    } catch {
      // erro ao listar worktrees, continua
    }
  } catch {
    // erro geral, retorna vazio
  }

  return resultado;
}

module.exports = {
  linhas,
};
