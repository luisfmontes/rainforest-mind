/**
 * Transporte de CLI externo — spawn com stdin, timeout, e extração de JSON
 *
 * Fatos pagos:
 * - Stdin explícito evita quebra com aspas/quebras de linha no cmd.exe
 * - stdin fechado após escrita evita travamento conhecido do codex exec
 * - windowsVerbatimArguments obrigatório no Windows
 * - timeout obrigatório — sem teto abre pendência
 *
 * Exporta:
 * - rodarCli({ cmd, entrada, timeoutMs, env }) → { status, stdout, stderr }
 * - extrairJson(stdout) → objeto ou null
 */

const { spawnSync } = require('child_process');

/**
 * Executa comando externo com stdin e timeout.
 *
 * @param {Object} opts - Opções
 * @param {string} opts.cmd - Comando a executar (ex: 'codex exec -s read-only')
 * @param {string} opts.entrada - Conteúdo para stdin
 * @param {number} opts.timeoutMs - Timeout em ms (obrigatório — sem ele a função recusa)
 * @param {Object} [opts.env] - Variáveis de ambiente (default: process.env)
 * @returns {Object} { status, stdout, stderr }
 * @throws se timeoutMs não for fornecido
 */
function rodarCli(opts) {
  const { cmd, entrada, timeoutMs, env } = opts;

  if (typeof timeoutMs !== 'number' || timeoutMs <= 0) {
    throw new Error('rodarCli: timeoutMs obrigatório e deve ser > 0');
  }

  const isWindows = process.platform === 'win32';
  const spawnArgs = isWindows
    ? ['cmd.exe', ['/d', '/s', '/c', `"${cmd}"`]]
    : ['sh', ['-c', cmd]];

  const resultado = spawnSync(spawnArgs[0], spawnArgs[1], {
    encoding: 'utf8',
    input: entrada,
    env: env || process.env,
    windowsVerbatimArguments: isWindows,
    timeout: timeoutMs,
  });

  return {
    status: resultado.status,
    stdout: resultado.stdout || '',
    stderr: resultado.stderr || '',
  };
}

/**
 * Extrai JSON do stdout de um CLI externo.
 * Tenta três abordagens em cascata:
 * 1. Regex com cerca: ```json ... ``` (CLI output com markdown)
 * 2. Regex simples: {...} (JSON com object literal)
 * 3. Fallback: stdout cru (JSON puro sem marcação — arrays top-level, etc)
 *
 * Caso de uso do fallback: alguns CLIs retornam JSON puro sem markdown,
 * incluindo arrays top-level ([...]) que não casam com as regex anteriores.
 * Exemplo: CLI que emite "[1,2,3]" direto sem cerca ou wrapper de objeto.
 *
 * @param {string} stdout - Conteúdo para buscar JSON
 * @returns {Object|null} Objeto parseado ou null se não conseguir
 */
function extrairJson(stdout) {
  try {
    // Primeira regex: ```json ... ```
    let match = stdout.match(/```json\s*([\s\S]*?)\s*```/);
    // Segunda regex: {...}
    if (!match) {
      match = stdout.match(/({[\s\S]*})/);
    }

    // Fallback: tenta stdout cru se nenhuma regex casou
    // Rescata CLIs que retornam JSON puro (arrays top-level, etc)
    const json = match ? match[1] : stdout;
    return JSON.parse(json);
  } catch (e) {
    return null;
  }
}

module.exports = { rodarCli, extrairJson };
