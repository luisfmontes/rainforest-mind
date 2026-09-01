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

// Lógica oficial de fechamento e de próximo estágio: vem do `estado.cjs`, que é
// o dono dela.
//
// Até 2026-09-01 este `require` existia, o comentário dizia exatamente isto — e
// o resultado era guardado numa variável que NINGUÉM lia. As funções abaixo eram
// reimplementação local, idêntica por coincidência. A rodada 4 da revisão pegou:
// código morto ao lado de um comentário que promete o contrário, e a promessa
// era falsa. O custo não é o byte: é o dia em que o grafo ganhar um estágio no
// `estado.cjs` e o resolver de estágio ativo não ficar sabendo — em silêncio, e
// com `null` significando "sem estágio ativo", que a portaria trata como negar.
//
// Agora o import é de verdade, e as definições locais ficam SÓ como fallback
// para o caso de o `estado.cjs` não estar alcançável (este arquivo é lib de
// hook, e hook roda de cwd que não controlamos).
let estadoOficial = null;
try {
  estadoOficial = require('../../scripts/estado.cjs');
} catch (_) {
  try {
    estadoOficial = require('../scripts/estado.cjs');
  } catch (_2) {
    estadoOficial = null; // usa o fallback local abaixo
  }
}

// ============================================================================
// FALLBACK da lógica de estado.cjs — usado só se o require acima falhar
// ============================================================================

const DECISAO = {
  arqueologia: ['pendente', 'ok', 'dispensada'],
  design: ['pendente', 'aprovado'],
  plano: ['pendente', 'ok'],
};
const EXECUCAO = ['executar', 'revisar', 'verificar', 'fechar'];
const FECHA_TAMBEM = { arqueologia: ['ok', 'dispensada'] };
const FECHADO = { design: 'aprovado', plano: 'ok' };

function estaFechadoLocal(estagio, bloco) {
  if (!bloco || typeof bloco !== 'object') return false;
  if (FECHA_TAMBEM[estagio]) return FECHA_TAMBEM[estagio].includes(bloco.status);
  return bloco.status === (FECHADO[estagio] || 'ok');
}

function proximoLocal(estado) {
  // `arqueologia` fica FORA desta lista — se entrasse, todo projeto sem mapa
  // ficaria eternamente com "proximo: arqueologia"
  for (const e of ['design', 'plano', ...EXECUCAO]) {
    if (!estaFechadoLocal(e, estado[e])) return e;
  }
  return null;
}

/* O oficial vence; o local só entra se o `estado.cjs` não carregou. */
function proximo(estado) {
  if (estadoOficial && typeof estadoOficial.proximo === 'function') {
    return estadoOficial.proximo(estado);
  }
  return proximoLocal(estado);
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

    // ...e sem o prefixo de numeracao de fluxo (`fluxo-<N>-`), que a convencao
    // `<data>-<branch>` da regra 11 nao previa mas o repo passou a usar: o
    // estado do fluxo 9 se chama `fluxo-9-portaria` e a branch dele e
    // `fluxo/portaria`. Sem esta segunda forma, `resolver` devolvia `null` na
    // branch real — medido em 2026-09-01 — e a portaria, que e fail-closed,
    // negaria TODO despacho justamente no repositorio que a implementa.
    //
    // Ambiguidade continua negando: se `portaria.json` e `fluxo-9-portaria.json`
    // existirem os dois com estagio aberto, os dois viram candidato e o
    // `candidatos.length !== 1` la embaixo devolve `null`, como antes.
    const slugSemNumeroDeFluxo = slugSemData.replace(/^fluxo-\d+-/, '');

    // Verificar se alguma das duas formas do slug casa com a branch
    if (slugSemData !== branchBase && slugSemNumeroDeFluxo !== branchBase) continue;

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
