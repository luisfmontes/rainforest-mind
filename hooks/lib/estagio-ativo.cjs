#!/usr/bin/env node
/**
 * Resolvedor de estágio ativo por branch
 *
 * Retorna o estágio ativo (próximo não-fechado) do fluxo cuja branch atual
 * casa com o slug do arquivo de estado, sem precisar da slug explícita.
 *
 * Padrão copiado de scripts/saude.cjs:138-162 — remove o prefixo de data
 * (`^\d{4}-\d{2}-\d{2}-`) e compara com a branch. A convenção vem de
 * skills/rainforest-mind/references/regra-11.md:32.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Imports dos exports do estado.cjs para usar a lógica oficial
// de fechamento e determinação de próximo estágio.
let estado_exports;
try {
  estado_exports = require('../scripts/estado.cjs');
} catch (_) {
  // Se não conseguir carregar, tenta um nível acima
  try {
    estado_exports = require('./scripts/estado.cjs');
  } catch (_2) {
    // fallback: vamos definir as funções aqui
  }
}

// ============================================================================
// IMPORTS/Fallbacks da lógica de estado.cjs
// ============================================================================

const DECISAO = {
  arqueologia: ['pendente', 'ok', 'dispensada'],
  design: ['pendente', 'aprovado'],
  plano: ['pendente', 'ok'],
};
const EXECUCAO = ['executar', 'revisar', 'verificar', 'fechar'];
const FECHA_TAMBEM = { arqueologia: ['ok', 'dispensada'] };
const FECHADO = { design: 'aprovado', plano: 'ok' };

function estaFechado(estagio, bloco) {
  if (!bloco || typeof bloco !== 'object') return false;
  if (FECHA_TAMBEM[estagio]) return FECHA_TAMBEM[estagio].includes(bloco.status);
  return bloco.status === (FECHADO[estagio] || 'ok');
}

function proximo(estado) {
  // `arqueologia` fica FORA desta lista — se entrasse, todo projeto sem mapa
  // ficaria eternamente com "proximo: arqueologia"
  for (const e of ['design', 'plano', ...EXECUCAO]) {
    if (!estaFechado(e, estado[e])) return e;
  }
  return null;
}

// ============================================================================
// RESOLVER
// ============================================================================

function resolver({ cwd }) {
  // cwd deve ser a raiz de um repositório git
  if (!cwd || typeof cwd !== 'string') return null;

  // 1. Obter branch atual
  let branch;
  try {
    branch = execSync('git rev-parse --abbrev-ref HEAD', {
      cwd,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
  } catch (_) {
    // Não é repositório git ou git falhou
    return null;
  }

  if (!branch || branch === 'HEAD') {
    return null; // Não há branch clara
  }

  // 2. Remover prefixos tipo 'fluxo/' (convenção de branch)
  // A branch pode ser 'fluxo/memoria-e-dados' ou 'memoria-e-dados'
  const branchBase = branch.replace(/^.*?\//, '');

  // 3. Ler arquivos de estado de `docs/rainforest/estado/`
  const dirEstado = path.join(cwd, 'docs', 'rainforest', 'estado');
  let arquivos;
  try {
    if (!fs.existsSync(dirEstado)) return null;
    arquivos = fs.readdirSync(dirEstado).filter((f) => f.endsWith('.json'));
  } catch (_) {
    return null;
  }

  if (!arquivos.length) return null;

  // 4. Encontrar candidatos: arquivos cujo slug (pós-data) casa com a branch
  // e que têm estágio aberto
  const candidatos = [];

  for (const arquivo of arquivos) {
    const slug = arquivo.replace(/\.json$/, '');
    let estado;

    // Ler o JSON
    try {
      const conteudo = fs.readFileSync(path.join(dirEstado, arquivo), 'utf8');
      estado = JSON.parse(conteudo);
    } catch (_) {
      // JSON inválido ou arquivo ilegível — não conta como candidato
      continue;
    }

    if (!estado || typeof estado !== 'object') continue;

    // Extrair o slug sem o prefixo de data (`^\d{4}-\d{2}-\d{2}-`)
    // Padrão: 2026-08-17-memoria-e-dados-do-rainforest
    const slugSemData = slug.replace(/^\d{4}-\d{2}-\d{2}-/, '');

    // Verificar se o slug pós-data casa com a branch
    if (slugSemData !== branchBase) continue;

    // Verificar se há estágio aberto (próximo !== null)
    const prox = proximo(estado);
    if (prox === null) {
      // Fluxo completo — não é candidato
      continue;
    }

    // É candidato!
    candidatos.push({ slug, estado, estagio: prox });
  }

  // 5. Retornar resultado
  // Ambiguidade nega — a condição tem que existir literal como `candidatos.length !== 1`
  if (candidatos.length !== 1) {
    return null;
  }

  const { slug, estagio } = candidatos[0];
  return { slug, estagio };
}

module.exports = { resolver };
