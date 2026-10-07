#!/usr/bin/env node
/**
 * Helpers para trabalhar com as duas contas do Claude Code.
 *
 * Exporta funções puras com home injetável:
 * - contaAtual(env, home) → 'trabalho' | 'pessoal' | null
 * - outraConta(conta) → 'trabalho' | 'pessoal' | null
 * - dirConta(conta, home) → caminho absoluto da conta ou null
 * - dentroDeProjetos(caminho, home) → boolean
 *
 * Home é injetável para testes: RFM_HOME se RFM_TEST=1, senão os.homedir().
 * CLAUDE_CONFIG_DIR (vazio ou <home>/.claude = trabalho; <home>/.claude-personal = pessoal).
 * Normaliza separador e caixa no Windows para comparação.
 */

const os = require('os');
const path = require('path');

/**
 * Resolve o home directory.
 * RFM_HOME se RFM_TEST=1, senão os.homedir().
 * @param {object} env variáveis de ambiente
 * @returns {string} caminho absoluto do home
 */
function homeDoUsuario(env) {
  return env.RFM_TEST === '1' && env.RFM_HOME
    ? env.RFM_HOME
    : os.homedir();
}

/**
 * Normaliza caminho para comparação: resolve, lowercase no Windows.
 * @param {string} p
 * @returns {string} caminho normalizado
 */
function normalizarCaminho(p) {
  const resolved = path.resolve(p);
  return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
}

/**
 * Pastas de conta — constante alvo de mutação (tarefa 2).
 */
const PASTAS_DE_CONTA = ['.claude', '.claude-personal'];

/**
 * Determina a conta atual a partir de CLAUDE_CONFIG_DIR.
 * Vazio ou <home>/.claude → 'trabalho'
 * <home>/.claude-personal → 'pessoal'
 * Outro → null
 * @param {object} env variáveis de ambiente
 * @param {string} home diretório home
 * @returns {'trabalho'|'pessoal'|null}
 */
function contaAtual(env, home) {
  const configDir = env.CLAUDE_CONFIG_DIR || '';
  const homeNorm = normalizarCaminho(home);

  if (!configDir) {
    // Vazio → padrão é trabalho
    return 'trabalho';
  }

  const configNorm = normalizarCaminho(configDir);
  const trabalhoDirNorm = normalizarCaminho(path.join(home, '.claude'));
  const pessoalDirNorm = normalizarCaminho(path.join(home, '.claude-personal'));

  if (configNorm === trabalhoDirNorm) {
    return 'trabalho';
  }
  if (configNorm === pessoalDirNorm) {
    return 'pessoal';
  }

  // Outra pasta → null
  return null;
}

/**
 * Retorna a outra conta.
 * @param {'trabalho'|'pessoal'} conta
 * @returns {'trabalho'|'pessoal'|null}
 */
function outraConta(conta) {
  if (conta === 'trabalho') return 'pessoal';
  if (conta === 'pessoal') return 'trabalho';
  return null;
}

/**
 * Retorna o diretório de uma conta.
 * @param {'trabalho'|'pessoal'} conta
 * @param {string} home diretório home
 * @returns {string|null} caminho absoluto ou null se conta inválida
 */
function dirConta(conta, home) {
  if (conta === 'trabalho') {
    return path.resolve(home, '.claude');
  }
  if (conta === 'pessoal') {
    return path.resolve(home, '.claude-personal');
  }
  return null;
}

/**
 * Verifica se um caminho resolvido está dentro de <home>/.claude/projects
 * ou <home>/.claude-personal/projects.
 * @param {string} caminho
 * @param {string} home diretório home
 * @returns {boolean}
 */
function dentroDeProjetos(caminho, home) {
  const caminhoNorm = normalizarCaminho(caminho);
  const homeNorm = normalizarCaminho(home);

  for (const pastaDeContaRel of PASTAS_DE_CONTA) {
    const projectsDir = path.resolve(home, pastaDeContaRel, 'projects');
    const projectsDirNorm = normalizarCaminho(projectsDir);

    // Verifica se caminhoNorm está dentro de projectsDirNorm
    if (caminhoNorm.startsWith(projectsDirNorm + path.sep) ||
        caminhoNorm === projectsDirNorm) {
      return true;
    }
  }

  return false;
}

module.exports = {
  homeDoUsuario,
  contaAtual,
  outraConta,
  dirConta,
  dentroDeProjetos,
  PASTAS_DE_CONTA,
};
