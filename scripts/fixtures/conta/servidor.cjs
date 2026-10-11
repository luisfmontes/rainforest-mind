#!/usr/bin/env node
// @categoria: sensor
//
// Servidor de teste da conta (scripts/testa-conta.sh). Responde /api/oauth/profile e
// /api/oauth/usage com as fixtures mascaradas desta pasta (profile.json, usage.json).
//
// Entradas por ambiente, nenhum token neste arquivo:
//   RFM_CONTA_SERVIDOR_MAPA      JSON { tokens: { <token>: { email, uuid, uso } } }; token fora
//                                do mapa leva 401. `uso` é 'team' (semana em 97%) ou 'pessoal'.
//   RFM_CONTA_SERVIDOR_CONTROLE  enquanto este arquivo existir, /api/oauth/usage segura a
//                                resposta por 2 s (a bateria usa para segurar a primeira rodada).
'use strict';

const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

const perfil = JSON.parse(fs.readFileSync(path.join(__dirname, 'profile.json'), 'utf8'));
const usoBase = JSON.parse(fs.readFileSync(path.join(__dirname, 'usage.json'), 'utf8'));
const mapa = JSON.parse(fs.readFileSync(process.env.RFM_CONTA_SERVIDOR_MAPA, 'utf8'));
const CONTROLE = process.env.RFM_CONTA_SERVIDOR_CONTROLE;

function usoDe(kind) {
  const u = JSON.parse(JSON.stringify(usoBase));
  const amanha = new Date(Date.now() + 2 * 24 * 3600 * 1000).toISOString();
  u.five_hour.resets_at = amanha;
  u.seven_day.resets_at = amanha;
  if (kind === 'team') u.seven_day.utilization = 97;
  return u;
}

function identidade(req) {
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
  return m && mapa.tokens[m[1]] ? mapa.tokens[m[1]] : null;
}

const server = http.createServer((req, res) => {
  const id = identidade(req);
  if (!id) {
    res.writeHead(401, { 'content-type': 'application/json' });
    res.end('{}');
    return;
  }
  const json = (obj) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(obj));
  };
  if (req.url === '/api/oauth/profile') {
    const p = JSON.parse(JSON.stringify(perfil));
    p.account.email = id.email;
    p.account.uuid = id.uuid;
    json(p);
    return;
  }
  if (req.url === '/api/oauth/usage') {
    const responder = () => json(usoDe(id.uso));
    if (CONTROLE && fs.existsSync(CONTROLE)) setTimeout(responder, 2000);
    else responder();
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end('{}');
});

server.listen(0, '127.0.0.1', () => {
  process.stdout.write(server.address().port + '\n');
});
