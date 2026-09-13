#!/usr/bin/env node
/**
 * Executa os hooks de SessionStart e exporta variáveis bash com os resultados.
 *
 * Uso no bash:
 *   source <(node scripts/exporta-hooks-sessao-start.cjs <raiz>)
 *
 * Resultado: variáveis bash como:
 *   OUT_1, EXIT_1, ERR_1 para o primeiro hook
 *   OUT_2, EXIT_2, ERR_2 para o segundo, etc.
 *   HOOKS_COUNT com o total de hooks rodados
 *
 * Variável de ambiente RFM_HOOKS_JSON:
 *   Se definida, especifica o caminho do arquivo hooks.json a usar.
 *   Se não definida, usa o caminho relativo padrão: ../hooks/hooks.json
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function lerHooksJson() {
  const hooksJsonPath = process.env.RFM_HOOKS_JSON || path.join(__dirname, '..', 'hooks', 'hooks.json');
  if (!fs.existsSync(hooksJsonPath)) {
    console.error(`hooks.json não encontrado: ${hooksJsonPath}`);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(hooksJsonPath, 'utf8'));
}

function expandirComando(cmd) {
  const pluginRoot = path.resolve(__dirname, '..');
  return cmd.replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, pluginRoot);
}

function escaparBash(str) {
  // Escapar string para bash: envolver em single quotes e escapar single quotes
  return "'" + str.replace(/'/g, "'\\''") + "'";
}

function main() {
  const raiz = process.argv[2];
  if (!raiz) {
    console.error('Uso: node scripts/exporta-hooks-sessao-start.cjs <raiz>');
    process.exit(1);
  }

  try {
    const hooksJson = lerHooksJson();
    const sessionStartHooks = hooksJson.hooks.SessionStart || [];

    if (sessionStartHooks.length === 0) {
      console.error('Nenhum hook de SessionStart encontrado em hooks.json');
      process.exit(1);
    }

    let hookIndex = 0;
    const outputs = [];

    // SessionStart é array de grupos de hooks
    for (const grupo of sessionStartHooks) {
      if (grupo.hooks && Array.isArray(grupo.hooks)) {
        for (const hook of grupo.hooks) {
          if (hook.type !== 'command') {
            continue;
          }

          hookIndex++;
          const cmd = expandirComando(hook.command);
          const timeout = (hook.timeout || 5) * 1000;

          let stdout = '';
          let stderr = '';
          let exitCode = 1;

          try {
            const proc = spawnSync('bash', ['-c', cmd], {
              encoding: 'utf8',
              timeout: timeout,
              stdio: ['ignore', 'pipe', 'pipe'],
              env: { ...process.env, RFM_ROOT: raiz }
            });

            stdout = proc.stdout || '';
            stderr = proc.stderr || '';

            if (proc.status === null) {
              // Processo foi morto pelo timeout do spawnSync
              exitCode = 124;
              stderr = `timeout: hook nao respondeu em ${timeout} ms` + (stderr ? '\n' + stderr : '');
            } else {
              exitCode = proc.status;
            }
          } catch (e) {
            stderr = e.message;
            exitCode = 1;
          }

          outputs.push({
            index: hookIndex,
            cmd: hook.command,
            stdout,
            stderr,
            exitCode
          });
        }
      }
    }

    // Exportar como variáveis bash
    for (const out of outputs) {
      const idx = out.index;
      console.log(`OUT_${idx}=${escaparBash(out.stdout)}`);
      console.log(`ERR_${idx}=${escaparBash(out.stderr)}`);
      console.log(`EXIT_${idx}=${out.exitCode}`);
    }
    console.log(`HOOKS_COUNT=${hookIndex}`);
  } catch (e) {
    console.error(`ERRO: ${e.message}`);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = { lerHooksJson };
