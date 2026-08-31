#!/usr/bin/env node
/**
 * Resolve o estágio ativo na partida do processo de poda, a partir da branch git.
 *
 * Reaproveita a heurística de `scripts/saude.cjs:155-166` (checarFluxo):
 * extrai o slug do arquivo de estado e remove a data, depois compara com a branch
 * git atual. Exatamente um match → {slug, estagio}; zero, ambíguo, ou sem git → null.
 *
 * Uso:
 *   const {estagioAtivo} = require('./poda-estagio.cjs');
 *   const r = estagioAtivo({cwd, env}); // devolve {slug, estagio} ou null
 *
 * CLI (para depuração):
 *   node hooks/lib/poda-estagio.cjs [--cwd /caminho] [--projeto /outro]
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// Localiza arquivos de estado no projeto (mesmo padrão de estado.cjs)
function resolverRaizEstado(cwd, env) {
  const raiz = env?.RFM_ESTADO_ROOT || env?.CLAUDE_PROJECT_DIR || cwd;
  return path.join(raiz, 'docs', 'rainforest', 'estado');
}

// Executa git e devolve resultado
function rodarGit(args, cwd) {
  const r = spawnSync('git', args, {
    cwd,
    encoding: 'utf8',
  });
  return {
    status: r.status,
    out: r.stdout || '',
  };
}

// Lê trabalhos abertos (aqueles com próximo estágio pendente)
function lerTrabalhosAbertos(dirEstado) {
  if (!fs.existsSync(dirEstado)) return [];

  const arquivos = fs.readdirSync(dirEstado).filter((f) => f.endsWith('.json'));
  const abertos = [];

  for (const f of arquivos) {
    try {
      const estado = JSON.parse(fs.readFileSync(path.join(dirEstado, f), 'utf8'));
      // Um trabalho está "aberto" se tem algum estágio pendente
      // (não completou toda a cadeia até fechar)
      const temPendente = ['arqueologia', 'design', 'plano', 'executar', 'revisar', 'verificar', 'fechar'].some(
        (e) => estado[e] && estado[e].status === 'pendente'
      );
      if (temPendente) {
        abertos.push({
          slug: estado.slug,
          estado,
        });
      }
    } catch {
      // arquivo inválido, ignora
    }
  }

  return abertos;
}

// Extrai o próximo estágio de um arquivo de estado
// (mesma lógica que estado.cjs usa)
function proximoEstagio(estado) {
  const ordem = ['arqueologia', 'design', 'plano', 'executar', 'revisar', 'verificar', 'fechar'];
  for (const e of ordem) {
    if (!estado[e] || estado[e].status === 'pendente') {
      return e;
    }
  }
  return null; // completado
}

/**
 * Resolve o estágio ativo na partida do proxy poda.
 *
 * @param {object} o
 * @param {string} [o.cwd] default: process.cwd()
 * @param {object} [o.env] default: process.env
 * @returns {{slug: string, estagio: string} | null}
 */
function estagioAtivo(o = {}) {
  const cwd = o.cwd || process.cwd();
  const env = o.env || process.env;

  // Resolve a raiz de estado (diretório do projeto)
  const dirEstado = resolverRaizEstado(cwd, env);

  // Lê trabalhos abertos
  const abertos = lerTrabalhosAbertos(dirEstado);
  if (!abertos.length) return null;

  // Resolve a branch git atual
  const gitResult = rodarGit(['rev-parse', '--abbrev-ref', 'HEAD'], cwd);
  const branch = gitResult.status === 0 ? gitResult.out.trim() : '';
  if (!branch || branch === 'HEAD') return null; // detached ou erro

  // Procura trabalhos cujo slug (sem data) bate com a branch
  // Heurística: `<data>-<nome da branch>` → remove `<data>-` e compara
  const matches = abertos.filter((t) => {
    const slugSemData = t.slug.replace(/^\d{4}-\d{2}-\d{2}-/, '');
    return slugSemData === branch;
  });

  // Exatamente um match → retorna o estágio ativo
  if (matches.length === 1) {
    const estagio = proximoEstagio(matches[0].estado);
    return estagio
      ? {
          slug: matches[0].slug,
          estagio,
        }
      : null;
  }

  // Zero ou ambíguo → não adivinha
  return null;
}

// CLI para depuração
if (require.main === module) {
  const args = process.argv.slice(2);
  const o = {};

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--cwd') {
      o.cwd = args[++i];
    } else if (args[i] === '--projeto') {
      o.cwd = args[++i];
    }
  }

  const r = estagioAtivo(o);
  if (r) {
    console.log(JSON.stringify(r));
  } else {
    console.log('null');
  }
}

module.exports = { estagioAtivo, proximoEstagio, lerTrabalhosAbertos };
