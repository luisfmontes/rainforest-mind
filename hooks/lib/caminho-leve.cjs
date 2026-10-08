#!/usr/bin/env node
/**
 * Caminho leve: o leitor compartilhado do registro `leve` (D6, D7 do design
 * docs/rainforest/design/2026-10-08-fluxo-pulado-bloqueio.md).
 *
 * `scripts/estado.cjs leve --motivo "<por quê>"` grava o registro; este módulo o lê.
 * Os dois lados usam o mesmo casamento de branch, o mesmo predicado de "só leve" e o
 * mesmo mapa do trilho protheus, por isso moram aqui — uma cópia só.
 *
 * Onde o registro mora (D6):
 *   - trilho rainforest: no arquivo de estado versionado da branch,
 *     docs/rainforest/estado/*.json, no campo `leve`;
 *   - trilho protheus: no mapa `rainforest-leve.json` sob o git-common-dir
 *     (branch -> registro), fora da árvore de trabalho.
 *
 * Falha fecha: erro de leitura devolve null, ou seja, a branch não ganha o leve.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { caminhoExecutavel } = require('./resolver-executavel.cjs');

// Estágios que fazem um arquivo de estado ser fluxo. Espelha os de scripts/estado.cjs;
// a bateria confere a divergência com um `novo()` real.
const CHAVES_DO_FLUXO = ['arqueologia', 'design', 'plano', 'executar', 'revisar', 'verificar', 'fechar'];

/** Arquivo só com `leve` não é fluxo: nenhum bloco de estágio existe nele. */
function soLeve(estado) {
  if (!estado || typeof estado !== 'object' || estado.leve === undefined) return false;
  return !CHAVES_DO_FLUXO.some((k) => estado[k] !== undefined);
}

/** O mesmo casamento do `resolver` de hooks/lib/estagio-ativo.cjs: slug sem a data e
 *  sem o `fluxo-N-` casa com a branch sem o prefixo até a primeira barra. */
function casaComBranch(slug, branchBase) {
  const semData = slug.replace(/^\d{4}-\d{2}-\d{2}-/, '');
  return semData === branchBase || semData.replace(/^fluxo-\d+-/, '') === branchBase;
}

/** Registro válido: motivo texto e não vazio. Motivo vazio gravado à mão não libera a branch. */
function leveValido(registro) {
  return registro && typeof registro.motivo === 'string' && registro.motivo.trim() !== '' ? registro : null;
}

/** Mapa do trilho protheus no git-common-dir (compartilhado entre worktrees). null se não é repo. */
function caminhoMapaProtheus(cwd) {
  const r = spawnSync(caminhoExecutavel('git'), ['rev-parse', '--git-common-dir'], {
    cwd,
    encoding: 'utf8',
    stdio: 'pipe',
  });
  if (r.status !== 0) return null;
  return path.resolve(cwd, r.stdout.trim(), 'rainforest-leve.json');
}

function lerLeveRainforest(gitTop, branchBase) {
  const dir = path.join(gitTop, 'docs', 'rainforest', 'estado');
  if (!fs.existsSync(dir)) return null;
  let arquivos;
  try {
    arquivos = fs.readdirSync(dir).filter((f) => f.endsWith('.json'));
  } catch (_) {
    return null;
  }
  for (const arquivo of arquivos) {
    if (!casaComBranch(arquivo.replace(/\.json$/, ''), branchBase)) continue;
    let estado;
    try {
      estado = JSON.parse(fs.readFileSync(path.join(dir, arquivo), 'utf8'));
    } catch (_) {
      continue; // JSON ilegível não carrega leve
    }
    const leve = leveValido(estado && estado.leve);
    if (leve) return leve;
  }
  return null;
}

function lerLeveProtheus(gitTop, branch) {
  const arq = caminhoMapaProtheus(gitTop);
  if (!arq || !fs.existsSync(arq)) return null;
  let mapa;
  try {
    mapa = JSON.parse(fs.readFileSync(arq, 'utf8'));
  } catch (_) {
    return null;
  }
  if (!mapa || typeof mapa !== 'object' || Array.isArray(mapa)) return null;
  return leveValido(mapa[branch]);
}

/** Registro `leve` da branch, ou null. Lê os dois trilhos; o primeiro válido vale. */
function leveDaBranch({ gitTop, branch }) {
  if (!gitTop || !branch) return null;
  const branchBase = branch.replace(/^.*?\//, '');
  return lerLeveRainforest(gitTop, branchBase) || lerLeveProtheus(gitTop, branch);
}

const UM_DIA_MS = 24 * 3600 * 1000;

/** Um `.gates.json` decide sozinho se a branch está num fluxo protheus aberto (D10). Campo
 *  `branch` no topo: decide pela igualdade com a branch atual, sem olhar o mtime. Sem o campo:
 *  cai na regra antiga, mtime de menos de 24 h. */
function gateAbreFluxo(dados, { branch, mtimeMs, agora }) {
  if (typeof dados.branch === 'string') return dados.branch === branch;
  return agora - mtimeMs < UM_DIA_MS;
}

/** Trilho protheus com fluxo aberto na `branch`: algum `docs/plans/*.gates.json` decide aberto.
 *  Arquivo ilegível (ou JSON que não é objeto) é ignorado, não derruba a leitura. */
function protheusAberto({ gitTop, branch, agora = Date.now() }) {
  const dirPlans = path.join(gitTop, 'docs', 'plans');
  let arquivos;
  try {
    arquivos = fs.readdirSync(dirPlans);
  } catch (_) {
    return false;
  }
  for (const f of arquivos) {
    if (!f.endsWith('.gates.json')) continue;
    const arq = path.join(dirPlans, f);
    let dados;
    let mtimeMs;
    try {
      dados = JSON.parse(fs.readFileSync(arq, 'utf8'));
      mtimeMs = fs.statSync(arq).mtimeMs;
    } catch (_) {
      continue;
    }
    if (!dados || typeof dados !== 'object') continue;
    if (gateAbreFluxo(dados, { branch, mtimeMs, agora })) return true;
  }
  return false;
}

module.exports = { leveDaBranch, leveValido, casaComBranch, soLeve, caminhoMapaProtheus, protheusAberto };
