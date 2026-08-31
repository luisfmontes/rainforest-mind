// Módulo de dados da poda: resolve caminhos de armazenamento via cadeia de raiz.
//
// Por que existe: o design pede um `docs/rainforest/poda.json` para configurar
// porta e limiares, mas (1) a única config real desta fase é a porta (defalt
// 4141, env var RFM_PODA_PORTA), e (2) docs/rainforest/ é a árvore VERSIONADA
// — ler config ali é confundir estado versionado com estado de processo.
//
// Este módulo resolve caminhos de arquivo usando a mesma cadeia de raiz já
// implementada em raiz.cjs — não com path relativo, nunca com `.rainforest/poda/`
// cravado a partir do cwd.

const fs = require('fs');
const path = require('path');

/**
 * Resolve a raiz de dados da poda, reaproveitando a cadeia de raiz.cjs.
 *
 * @param {object} [o]
 * @param {object} [o.env]      default: process.env
 * @param {string} [o.cwd]      default: CLAUDE_PROJECT_DIR ou cwd
 * @param {string} [o.plugin]   default: duas pastas acima deste arquivo
 * @returns {string|null}       caminho para .rainforest/poda, ou null se raiz não resolvida
 */
function raizPoda(o = {}) {
  const env = o.env || process.env;
  const resolverRaiz = require('./raiz.cjs').resolverRaiz;
  const resultado = resolverRaiz({
    env,
    cwd: o.cwd,
    plugin: o.plugin,
  });

  if (!resultado.raiz) {
    return null;
  }

  return path.join(resultado.raiz, 'poda');
}

/**
 * Caminho do arquivo de métricas em JSONL.
 *
 * @param {object} [o]  mesmo contrato de raizPoda
 * @returns {string|null}
 */
function caminhoMetricas(o = {}) {
  const raiz = raizPoda(o);
  if (!raiz) return null;
  return path.join(raiz, 'metricas.jsonl');
}

/**
 * Caminho do arquivo de contexto em JSON (contrato com o fluxo 8).
 *
 * @param {object} [o]  mesmo contrato de raizPoda
 * @returns {string|null}
 */
function caminhoContexto(o = {}) {
  const raiz = raizPoda(o);
  if (!raiz) return null;
  return path.join(raiz, 'contexto.json');
}

/**
 * Caminho do arquivo de PID e porta do processo.
 *
 * @param {object} [o]  mesmo contrato de raizPoda
 * @returns {string|null}
 */
function caminhoPid(o = {}) {
  const raiz = raizPoda(o);
  if (!raiz) return null;
  return path.join(raiz, 'poda.pid');
}

/**
 * Porta padrão do proxy, com suporte a env var RFM_PODA_PORTA.
 *
 * RFM_PODA_PORTA deve ser numérica, entre 1 e 65535. Valores fora da faixa
 * retornam o padrão 4141 com um aviso, nunca falham.
 *
 * @param {object} [o]
 * @param {object} [o.env]      default: process.env
 * @returns {number}            porta (4141 ou override válido)
 */
function portaPadrao(o = {}) {
  const env = o.env || process.env;
  const PADRAO = 4141;

  if (!env.RFM_PODA_PORTA) {
    return PADRAO;
  }

  const valor = Number.parseInt(env.RFM_PODA_PORTA, 10);
  if (!Number.isInteger(valor) || valor < 1 || valor > 65535) {
    console.warn(
      `aviso: RFM_PODA_PORTA="${env.RFM_PODA_PORTA}" não é numérico ou está fora de 1-65535, usando ${PADRAO}`
    );
    return PADRAO;
  }

  return valor;
}

module.exports = {
  raizPoda,
  caminhoMetricas,
  caminhoContexto,
  caminhoPid,
  portaPadrao,
};
