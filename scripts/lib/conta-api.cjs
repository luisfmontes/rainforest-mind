// Servidor da conta: identidade (/api/oauth/profile) e uso (/api/oauth/usage).
// D10 do design docs/rainforest/design/2026-10-10-troca-de-conta.md.
//
// Nunca imprime nem grava a credencial. O cache em disco guarda só a última
// leitura de uso e a espera por conta.
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const BASE_PADRAO = 'https://api.anthropic.com';
// O endpoint de token mora em outro host que o do perfil e do uso.
const BASE_TOKEN_PADRAO = 'https://platform.claude.com';
// client_id público do CLI (não é segredo).
const CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
const TIMEOUT_MS = 30 * 1000;
const BETA_USO = 'oauth-2025-04-20';
const VALIDADE_MS = 4 * 60 * 1000;
const VALIDADE_ALTA_MS = 60 * 1000;
const LIMIAR_ALTO = 85;
const ESPERA_429_MS = 3 * 60 * 1000;

const donosEmMemoria = new Map();

// RFM_CONTA_API só vale com RFM_TEST=1: em uso real, o endpoint é sempre o da Anthropic.
function base() {
  if (process.env.RFM_TEST === '1' && process.env.RFM_CONTA_API) return process.env.RFM_CONTA_API;
  return BASE_PADRAO;
}

// Em bateria (RFM_TEST=1) o servidor falso responde pelos dois hosts.
function baseToken() {
  if (process.env.RFM_TEST === '1' && process.env.RFM_CONTA_API) return process.env.RFM_CONTA_API;
  return BASE_TOKEN_PADRAO;
}

// Todo fetch leva timeout: sem ele um servidor que não responde prende a rodada (e a trava).
function buscar(url, init = {}) {
  return fetch(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
}

function cabecalhos(tok, comBeta) {
  const h = new Headers();
  h.set('Authorization', 'Bearer ' + tok);
  if (comBeta) h.set('anthropic-beta', BETA_USO);
  return h;
}

function chaveDe(tok) {
  return crypto.createHash('sha256').update(tok).digest('hex');
}

async function dono(tok) {
  const chave = chaveDe(tok);
  if (donosEmMemoria.has(chave)) return donosEmMemoria.get(chave);
  const r = await buscar(base() + '/api/oauth/profile', { headers: cabecalhos(tok, false) });
  if (!r.ok) throw new Error('profile HTTP ' + r.status);
  const corpo = await r.json();
  const conta = { email: corpo.account.email, uuid: corpo.account.uuid };
  donosEmMemoria.set(chave, conta);
  return conta;
}

function caminhoCache(dados) {
  return path.join(dados, 'contas', 'uso-cache.json');
}

function lerCache(arq) {
  try {
    return JSON.parse(fs.readFileSync(arq, 'utf8'));
  } catch {
    return {};
  }
}

// Escrita atômica: tmp no mesmo diretório e rename por cima.
function gravaCache(arq, cache) {
  fs.mkdirSync(path.dirname(arq), { recursive: true });
  const tmp = arq + '.' + process.pid + '.' + crypto.randomBytes(4).toString('hex') + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(cache, null, 2));
  fs.renameSync(tmp, arq);
}

function maiorPercentual(dados) {
  const vals = [dados?.five_hour?.utilization, dados?.seven_day?.utilization]
    .filter((v) => typeof v === 'number');
  return vals.length ? Math.max(...vals) : 0;
}

function resposta(leitura, agora, de) {
  return {
    dados: leitura ? leitura.dados : null,
    idadeMs: leitura ? agora - leitura.em : null,
    de,
  };
}

async function uso(conta, tok, { dados, agora = Date.now() } = {}) {
  if (!dados) throw new Error('uso: falta a pasta de dados');
  const arq = caminhoCache(dados);
  const cache = lerCache(arq);
  const entrada = cache[conta] || {};
  cache[conta] = entrada;

  if (entrada.esperaAte && agora < entrada.esperaAte) {
    return resposta(entrada.leitura, agora, 'espera');
  }
  if (entrada.leitura) {
    const validade = maiorPercentual(entrada.leitura.dados) >= LIMIAR_ALTO ? VALIDADE_ALTA_MS : VALIDADE_MS;
    if (agora - entrada.leitura.em < validade) return resposta(entrada.leitura, agora, 'cache');
  }

  const r = await buscar(base() + '/api/oauth/usage', { headers: cabecalhos(tok, true) });
  if (r.status === 429) cache[conta].esperaAte = agora + ESPERA_429_MS;
  if (r.status === 429) {
    gravaCache(arq, cache);
    return resposta(entrada.leitura, agora, 'espera');
  }
  if (!r.ok) throw new Error('usage HTTP ' + r.status);

  const novo = await r.json();
  delete cache[conta].esperaAte;
  cache[conta].leitura = { em: agora, dados: novo };
  gravaCache(arq, cache);
  return resposta(cache[conta].leitura, agora, 'servidor');
}

// Renova o login (objeto claudeAiOauth) pelo refresh token. O refresh token é de uso único: a
// resposta pode trazer um novo, e o antigo deixa de valer; sem um novo na resposta, mantém o
// atual. Quem chama TEM de gravar o retorno no mesmo arquivo antes de qualquer outra coisa.
// Os campos entram por pares (como o Headers.set de cabecalhos()), não por literal de objeto.
async function renovar(login, { agora = Date.now() } = {}) {
  const pedido = [
    ['grant_type', 'refresh_token'],
    ['client_id', CLIENT_ID],
    ['scope', (login.scopes || []).join(' ')],
    ['refresh_token', login.refreshToken],
  ];
  const r = await buscar(baseToken() + '/v1/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(Object.fromEntries(pedido)),
  });
  if (!r.ok) throw new Error('token HTTP ' + r.status);
  const resp = await r.json();
  const acesso = resp.access_token;
  const giro = resp.refresh_token;
  if (!acesso || typeof resp.expires_in !== 'number') throw new Error('renovação com resposta incompleta');
  const campos = [
    ['accessToken', acesso],
    ['refreshToken', giro || login.refreshToken],
    ['expiresAt', agora + resp.expires_in * 1000],
  ];
  return { ...login, ...Object.fromEntries(campos) };
}

module.exports = { base, baseToken, dono, uso, renovar, TIMEOUT_MS, CLIENT_ID, ESPERA_429_MS, VALIDADE_MS, VALIDADE_ALTA_MS, LIMIAR_ALTO };
