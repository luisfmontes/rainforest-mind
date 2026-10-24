#!/usr/bin/env node
// @categoria: sensor
// rainforest-gate: dados-de-exemplo — tokens FALSOS (prefixo falso-); nenhum valor real.
//
// Servidor de teste da conta (scripts/testa-conta.sh). Responde /api/oauth/profile,
// /api/oauth/usage e /v1/oauth/token com as fixtures mascaradas desta pasta (profile.json,
// usage.json).
//
// Entradas por ambiente, nenhum token neste arquivo:
//   RFM_CONTA_SERVIDOR_MAPA      JSON do caso:
//     tokens   { <token de acesso>: info }; token fora do mapa, ou com `venceu: true`, leva 401
//              (é o que um token de acesso vencido recebe do servidor de verdade).
//              info = { email, uuid, uso, ... }. `uso` é 'team' (semana em 97%) ou 'pessoal'.
//              Opcionais por token: uso5 / uso7 (utilização das duas janelas), reset5 / reset7
//              (resets_at ISO das duas janelas; padrão: daqui a 2 dias) e perfilStatus (HTTP
//              que /api/oauth/profile devolve no lugar da resposta normal).
//     refresh  { <refresh token>: { de, semGiro? } }: o refresh token vale uma vez. A renovação
//              devolve um token de acesso novo com a identidade do token `de`, e (salvo `semGiro`)
//              um refresh token novo, que também vale uma vez; o antigo passa a dar 400.
//     renovacaoStatus   se existir, /v1/oauth/token responde esse HTTP sem renovar nada.
//   RFM_CONTA_SERVIDOR_CONTROLE  enquanto este arquivo existir, /api/oauth/usage segura a
//                                resposta (a bateria usa para segurar a primeira rodada até a
//                                segunda terminar, e apaga o arquivo para soltá-la); teto de 20 s.
//   RFM_CONTA_SERVIDOR_CONTAGEM  se existir, cada POST em /v1/oauth/token acrescenta uma linha a
//                                este arquivo (a bateria conta as renovações que o vigia pediu).
'use strict';

const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

const perfil = JSON.parse(fs.readFileSync(path.join(__dirname, 'profile.json'), 'utf8'));
const usoBase = JSON.parse(fs.readFileSync(path.join(__dirname, 'usage.json'), 'utf8'));
const mapa = JSON.parse(fs.readFileSync(process.env.RFM_CONTA_SERVIDOR_MAPA, 'utf8'));
const CONTROLE = process.env.RFM_CONTA_SERVIDOR_CONTROLE;
const CONTAGEM = process.env.RFM_CONTA_SERVIDOR_CONTAGEM;
const SEGURAR_MAX_MS = 20 * 1000;
// client_id público do CLI: a renovação que não o manda é recusada.
const CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
const VIDA_NOVA_S = 8 * 3600;

mapa.refresh = mapa.refresh || {};
const usados = new Set();
let giros = 0;

function usoDe(info) {
  const u = JSON.parse(JSON.stringify(usoBase));
  const amanha = new Date(Date.now() + 2 * 24 * 3600 * 1000).toISOString();
  u.five_hour.resets_at = info.reset5 || amanha;
  // reset7: null explícito simula a janela sem resets_at (a API devolve null).
  u.seven_day.resets_at = info.reset7 === null ? null : info.reset7 || amanha;
  if (info.uso === 'team') u.seven_day.utilization = 97;
  if (typeof info.uso5 === 'number') u.five_hour.utilization = info.uso5;
  if (typeof info.uso7 === 'number') u.seven_day.utilization = info.uso7;
  return u;
}

function identidade(req) {
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
  const info = m && mapa.tokens[m[1]];
  return info && !info.venceu ? info : null;
}

function enviar(res, status, obj) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
}

// Segura a resposta enquanto o arquivo de controle existir (ou até o teto), depois responde.
function segurarEResponder(responder) {
  const limite = Date.now() + SEGURAR_MAX_MS;
  const tique = () => {
    if (CONTROLE && fs.existsSync(CONTROLE) && Date.now() < limite) setTimeout(tique, 50);
    else responder();
  };
  tique();
}

function renovar(req, res) {
  if (CONTAGEM) fs.appendFileSync(CONTAGEM, 'POST /v1/oauth/token\n');
  let corpo = '';
  req.on('data', (d) => { corpo += d; });
  req.on('end', () => {
    if (mapa.renovacaoStatus) return enviar(res, mapa.renovacaoStatus, {});
    let b;
    try {
      b = JSON.parse(corpo);
    } catch {
      return enviar(res, 400, { error: 'invalid_request' });
    }
    const reg = mapa.refresh[b.refresh_token];
    const pedidoOk = req.headers['content-type'] === 'application/json'
      && b.grant_type === 'refresh_token' && b.client_id === CLIENT_ID && typeof b.scope === 'string';
    if (!pedidoOk || !reg || usados.has(b.refresh_token)) return enviar(res, 400, { error: 'invalid_grant' });
    usados.add(b.refresh_token);
    giros += 1;
    const novoAcesso = `falso-renovado-acesso-${giros}`;
    const origem = mapa.tokens[reg.de] || {};
    mapa.tokens[novoAcesso] = { ...origem, venceu: false };
    const resp = { expires_in: VIDA_NOVA_S, scope: b.scope };
    resp.access_token = novoAcesso;
    if (!reg.semGiro) {
      const novoRefresh = `falso-renovado-refresh-${giros}`;
      mapa.refresh[novoRefresh] = { de: novoAcesso, semGiro: false };
      resp.refresh_token = novoRefresh;
    } else {
      mapa.refresh[b.refresh_token] = { de: novoAcesso, semGiro: true };
      usados.delete(b.refresh_token);
    }
    return enviar(res, 200, resp);
  });
}

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/v1/oauth/token') return renovar(req, res);
  const id = identidade(req);
  if (!id) return enviar(res, 401, {});
  if (req.url === '/api/oauth/profile') {
    if (id.perfilStatus) return enviar(res, id.perfilStatus, {});
    const p = JSON.parse(JSON.stringify(perfil));
    p.account.email = id.email;
    p.account.uuid = id.uuid;
    return enviar(res, 200, p);
  }
  if (req.url === '/api/oauth/usage') {
    const responder = () => enviar(res, 200, usoDe(id));
    if (CONTROLE && fs.existsSync(CONTROLE)) segurarEResponder(responder);
    else responder();
    return undefined;
  }
  return enviar(res, 404, {});
});

server.listen(0, '127.0.0.1', () => {
  process.stdout.write(server.address().port + '\n');
});
