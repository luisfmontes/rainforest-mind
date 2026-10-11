#!/usr/bin/env node
// @categoria: bateria
// rainforest-gate: dados-de-exemplo — tokens FALSOS (falsa-, falso-); nenhum valor real.
//
// Bateria do servidor da conta (scripts/lib/conta-api.cjs): identidade e uso com cache.
// Uso: node scripts/testa-conta-api.cjs
//
// Servidor local (http.createServer, porta 0) servindo as fixtures mascaradas de
// scripts/fixtures/conta/. Conta as requisições por rota. O tempo entra pelo `agora`
// injetado: nada dorme. A pasta de dados é mkdtemp, nunca a pasta real.
// A mutação de `scripts/conferir-mutacao.cjs` é a linha do 429 em uso(); o caso
// "depois de um 429 a segunda chamada não chega ao servidor" precisa ficar vermelho.

const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const API = require(path.join(__dirname, 'lib', 'conta-api.cjs'));

const FIX = path.join(__dirname, 'fixtures', 'conta');
const fixPerfil = JSON.parse(fs.readFileSync(path.join(FIX, 'profile.json'), 'utf8'));
const fixUso = JSON.parse(fs.readFileSync(path.join(FIX, 'usage.json'), 'utf8'));

const MIN = 60 * 1000;
const T0 = 1000000000000;
const BETA = 'oauth-2025-04-20';
const credFalsa = 'falsa-para-teste';
const credDono = 'falsa-para-dono';

function usoAlto() {
  const c = JSON.parse(JSON.stringify(fixUso));
  c.five_hour.utilization = 90;
  return c;
}

function enviar(res, status, obj) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
}

// Servidor local com contagem por rota. `modo` '429' faz o servidor responder 429 ao uso.
function comServidor(fn, usoServidor = fixUso) {
  return new Promise((resolve, reject) => {
    const est = {
      perfilReqs: 0, usoReqs: 0, modo: 'ok', usoDados: usoServidor, betaOk: null, autOk: null,
      tokenReqs: 0, tokenCorpo: null, tokenTipo: null, tokenStatus: 200, tokenResposta: null,
    };
    const srv = http.createServer((req, res) => {
      if (req.method === 'POST' && req.url === '/v1/oauth/token') {
        est.tokenReqs++;
        est.tokenTipo = req.headers['content-type'];
        let corpo = '';
        req.on('data', (d) => { corpo += d; });
        req.on('end', () => {
          est.tokenCorpo = JSON.parse(corpo);
          enviar(res, est.tokenStatus, est.tokenResposta || {});
        });
        return undefined;
      }
      if (req.url === '/api/oauth/profile') {
        est.perfilReqs++;
        return enviar(res, 200, fixPerfil);
      }
      if (req.url === '/api/oauth/usage') {
        est.usoReqs++;
        est.betaOk = req.headers['anthropic-beta'] === BETA;
        est.autOk = /^Bearer \S/.test(req.headers.authorization || '');
        if (est.modo === '429') return enviar(res, 429, { error: 'rate_limited' });
        return enviar(res, 200, est.usoDados);
      }
      return enviar(res, 404, {});
    });
    srv.listen(0, '127.0.0.1', async () => {
      const antes = { t: process.env.RFM_TEST, a: process.env.RFM_CONTA_API };
      const dados = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-conta-api-'));
      process.env.RFM_TEST = '1';
      process.env.RFM_CONTA_API = 'http://127.0.0.1:' + srv.address().port;
      const limpa = () => new Promise((fechou) => {
        if (antes.t === undefined) delete process.env.RFM_TEST; else process.env.RFM_TEST = antes.t;
        if (antes.a === undefined) delete process.env.RFM_CONTA_API; else process.env.RFM_CONTA_API = antes.a;
        srv.closeAllConnections();
        srv.close(() => {
          fs.rmSync(dados, { recursive: true, force: true });
          fechou();
        });
      });
      try {
        const r = await fn({ est, dados });
        await limpa();
        resolve(r);
      } catch (e) {
        await limpa();
        reject(e);
      }
    });
  });
}

const casos = [];
const caso = (nome, fn) => casos.push({ nome, fn });

caso('(a) duas chamadas a uso com 3 min de diferença → 1 requisição', () =>
  comServidor(async ({ est, dados }) => {
    const a = await API.uso('pessoal', credFalsa, { dados, agora: T0 });
    const b = await API.uso('pessoal', credFalsa, { dados, agora: T0 + 3 * MIN });
    const reqs = est.usoReqs;
    const cache = fs.readFileSync(path.join(dados, 'contas', 'uso-cache.json'), 'utf8');
    const ok = reqs === 1 && b.de === 'cache' && b.idadeMs === 3 * MIN
      && a.de === 'servidor' && est.betaOk === true && est.autOk === true
      && !cache.includes(credFalsa);
    return { ok, reqs, linha: 'de2=' + b.de + ' idadeMs=' + b.idadeMs + ' beta=' + est.betaOk + ' credNoCache=' + cache.includes(credFalsa) };
  }));

caso('(b) última leitura em 85+ e 2 min de diferença → 2 requisições', () =>
  comServidor(async ({ est, dados }) => {
    await API.uso('pessoal', credFalsa, { dados, agora: T0 });
    const b = await API.uso('pessoal', credFalsa, { dados, agora: T0 + 2 * MIN });
    const reqs = est.usoReqs;
    const ok = reqs === 2 && b.de === 'servidor';
    return { ok, reqs, linha: 'de2=' + b.de };
  }, usoAlto()));

caso('depois de um 429 a segunda chamada não chega ao servidor', () =>
  comServidor(async ({ est, dados }) => {
    const a = await API.uso('pessoal', credFalsa, { dados, agora: T0 });
    est.modo = '429';
    const b = await API.uso('pessoal', credFalsa, { dados, agora: T0 + 5 * MIN });
    const reqsAposB = est.usoReqs;
    const c = await API.uso('pessoal', credFalsa, { dados, agora: T0 + 6 * MIN });
    const reqsAposC = est.usoReqs;
    const ok = reqsAposB === 2 && b.de === 'espera' && b.idadeMs === 5 * MIN
      && reqsAposC === 2 && c.de === 'espera' && c.idadeMs === 6 * MIN
      && JSON.stringify(c.dados) === JSON.stringify(a.dados);
    return { ok, reqs: reqsAposC, linha: 'reqs apos 429=' + reqsAposB + ' apos 2a=' + reqsAposC + ' idadeMs=' + c.idadeMs };
  }));

caso('(e) passada a espera de 3 min, a chamada volta ao servidor', () =>
  comServidor(async ({ est, dados }) => {
    await API.uso('pessoal', credFalsa, { dados, agora: T0 });
    est.modo = '429';
    await API.uso('pessoal', credFalsa, { dados, agora: T0 + 5 * MIN });
    est.modo = 'ok';
    const d = await API.uso('pessoal', credFalsa, { dados, agora: T0 + 9 * MIN });
    const reqs = est.usoReqs;
    const ok = reqs === 3 && d.de === 'servidor';
    return { ok, reqs, linha: 'de=' + d.de };
  }));

caso('(d) dono devolve x@exemplo.invalid', () =>
  comServidor(async ({ est }) => {
    const d1 = await API.dono(credDono);
    const d2 = await API.dono(credDono);
    const reqs = est.perfilReqs;
    const ok = d1.email === 'x@exemplo.invalid' && d2.email === 'x@exemplo.invalid' && reqs === 1;
    return { ok, reqs, linha: 'email=' + d1.email + ' perfilReqs=' + reqs };
  }));

caso('(f) sem RFM_TEST=1 a base fica na Anthropic, RFM_CONTA_API é ignorada', async () => {
  const antes = { t: process.env.RFM_TEST, a: process.env.RFM_CONTA_API };
  process.env.RFM_CONTA_API = 'http://127.0.0.1:9';
  delete process.env.RFM_TEST;
  const semFlag = API.base();
  process.env.RFM_TEST = '1';
  const comFlag = API.base();
  if (antes.t === undefined) delete process.env.RFM_TEST; else process.env.RFM_TEST = antes.t;
  if (antes.a === undefined) delete process.env.RFM_CONTA_API; else process.env.RFM_CONTA_API = antes.a;
  const ok = semFlag === 'https://api.anthropic.com' && comFlag === 'http://127.0.0.1:9';
  return { ok, reqs: 0, linha: 'semFlag=' + semFlag + ' comFlag=' + comFlag };
});

// Login falso no formato do claudeAiOauth.
function loginFalso() {
  return {
    accessToken: 'falso-acesso-velho',
    refreshToken: 'falso-giro-velho',
    expiresAt: 1,
    scopes: ['user:inference', 'user:profile'],
    subscriptionType: 'max',
  };
}

caso('(g) renovar manda o POST JSON do CLI e devolve o login girado', () =>
  comServidor(async ({ est }) => {
    est.tokenResposta = { access_token: 'falso-acesso-novo', refresh_token: 'falso-giro-novo', expires_in: 28800, scope: 'user:inference user:profile' };
    const novo = await API.renovar(loginFalso(), { agora: T0 });
    const b = est.tokenCorpo;
    const ok = est.tokenReqs === 1 && est.tokenTipo === 'application/json'
      && b.grant_type === 'refresh_token' && b.refresh_token === 'falso-giro-velho'
      && b.client_id === '9d1c250a-e61b-44d9-88ed-5944d1962f5e' && b.scope === 'user:inference user:profile'
      && novo.accessToken === 'falso-acesso-novo' && novo.refreshToken === 'falso-giro-novo'
      && novo.expiresAt === T0 + 28800 * 1000 && novo.subscriptionType === 'max'
      && JSON.stringify(novo.scopes) === JSON.stringify(loginFalso().scopes);
    return { ok, reqs: est.tokenReqs, linha: 'tipo=' + est.tokenTipo + ' expiresAt-T0=' + (novo.expiresAt - T0) };
  }));

caso('(h) renovar sem refresh token na resposta mantém o atual', () =>
  comServidor(async ({ est }) => {
    est.tokenResposta = { access_token: 'falso-acesso-novo', expires_in: 3600 };
    const novo = await API.renovar(loginFalso(), { agora: T0 });
    const ok = novo.refreshToken === 'falso-giro-velho' && novo.accessToken === 'falso-acesso-novo' && novo.expiresAt === T0 + 3600 * 1000;
    return { ok, reqs: est.tokenReqs, linha: 'refreshIgual=' + (novo.refreshToken === 'falso-giro-velho') };
  }));

caso('(i) renovar com HTTP 500 lança sem a credencial na mensagem', () =>
  comServidor(async ({ est }) => {
    est.tokenStatus = 500;
    let msg = null;
    try {
      await API.renovar(loginFalso(), { agora: T0 });
    } catch (e) {
      msg = e.message;
    }
    const ok = msg === 'token HTTP 500' && !msg.includes('falso-');
    return { ok, reqs: est.tokenReqs, linha: 'erro=' + msg };
  }));

caso('(j) todo fetch (perfil, uso, token) leva timeout por signal', () =>
  comServidor(async ({ dados }) => {
    const original = global.fetch;
    const sinais = [];
    global.fetch = (url, init = {}) => {
      sinais.push(init.signal instanceof AbortSignal);
      return original(url, init);
    };
    try {
      await API.dono('falso-para-sinal');
      await API.uso('pessoal', credFalsa, { dados, agora: T0 });
      await API.renovar(loginFalso(), { agora: T0 }).catch(() => {});
    } finally {
      global.fetch = original;
    }
    const ok = sinais.length === 3 && sinais.every(Boolean) && API.TIMEOUT_MS === 30000;
    return { ok, reqs: sinais.length, linha: 'sinais=' + sinais.join(',') };
  }));

// Servidor que aceita a conexão e nunca responde. O (j) só confere que o signal está ANEXADO; aqui o
// signal tem de ABORTAR de verdade, nas três chamadas (perfil, uso, token). O prazo real é 30 s: a
// bateria troca AbortSignal.timeout por um de 300 ms (só dentro deste caso) e confere que o valor
// pedido pelo código de produção é o TIMEOUT_MS. Se algum fetch não levasse o signal, a chamada
// penduraria e a guarda de 5 s a marcaria como "pendurou".
caso('(m) servidor mudo: dono, uso e renovar abortam pelo timeout, e o prazo pedido é o TIMEOUT_MS', async () => {
  const mudo = http.createServer(() => {});
  const porta = await new Promise((pronto) => mudo.listen(0, '127.0.0.1', () => pronto(mudo.address().port)));
  const dados = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-conta-api-mudo-'));
  const antes = { t: process.env.RFM_TEST, a: process.env.RFM_CONTA_API, timeout: AbortSignal.timeout };
  process.env.RFM_TEST = '1';
  process.env.RFM_CONTA_API = 'http://127.0.0.1:' + porta;
  const pedidos = [];
  AbortSignal.timeout = (ms) => { pedidos.push(ms); return antes.timeout.call(AbortSignal, 300); };
  const medir = async (fn) => {
    const t0 = Date.now();
    let limite;
    const guarda = new Promise((resolve) => { limite = setTimeout(() => resolve('pendurou'), 5000); });
    const r = await Promise.race([fn().then(() => 'respondeu', (e) => e.name), guarda]);
    clearTimeout(limite);
    return { r, ms: Date.now() - t0 };
  };
  let medidas;
  try {
    medidas = [
      await medir(() => API.dono('falso-para-mudo')),
      await medir(() => API.uso('pessoal', credFalsa, { dados, agora: T0 })),
      await medir(() => API.renovar(loginFalso(), { agora: T0 })),
    ];
  } finally {
    AbortSignal.timeout = antes.timeout;
    if (antes.t === undefined) delete process.env.RFM_TEST; else process.env.RFM_TEST = antes.t;
    if (antes.a === undefined) delete process.env.RFM_CONTA_API; else process.env.RFM_CONTA_API = antes.a;
    mudo.closeAllConnections();
    await new Promise((fechou) => mudo.close(fechou));
    fs.rmSync(dados, { recursive: true, force: true });
  }
  const ok = medidas.every((m) => (m.r === 'TimeoutError' || m.r === 'AbortError') && m.ms < 4000)
    && pedidos.length === 3 && pedidos.every((ms) => ms === API.TIMEOUT_MS);
  return { ok, reqs: pedidos.length, linha: medidas.map((m) => m.r + '@' + m.ms + 'ms').join(' ') + ' pedido=' + pedidos.join(',') };
});

caso('(l) o endpoint de token real é o platform.claude.com; em bateria vale RFM_CONTA_API', async () => {
  const antes = { t: process.env.RFM_TEST, a: process.env.RFM_CONTA_API };
  process.env.RFM_CONTA_API = 'http://127.0.0.1:9';
  delete process.env.RFM_TEST;
  const semFlag = API.baseToken();
  process.env.RFM_TEST = '1';
  const comFlag = API.baseToken();
  if (antes.t === undefined) delete process.env.RFM_TEST; else process.env.RFM_TEST = antes.t;
  if (antes.a === undefined) delete process.env.RFM_CONTA_API; else process.env.RFM_CONTA_API = antes.a;
  const ok = semFlag === 'https://platform.claude.com' && comFlag === 'http://127.0.0.1:9';
  return { ok, reqs: 0, linha: 'semFlag=' + semFlag + ' comFlag=' + comFlag };
});

(async () => {
  let ok = 0;
  let falha = 0;
  for (const c of casos) {
    let r;
    try {
      r = await c.fn();
    } catch (e) {
      r = { ok: false, reqs: 'n/a', linha: 'erro: ' + e.message };
    }
    const cont = 'requisicoes=' + r.reqs + ' ' + r.linha;
    if (r.ok) {
      ok++;
      console.log('ok     ' + c.nome + ' [' + cont + ']');
    } else {
      falha++;
      console.log('FALHA  ' + c.nome + ' [' + cont + ']');
    }
  }
  console.log(ok + ' ok, ' + falha + ' falha(s)');
  process.exitCode = falha === 0 ? 0 : 1;
})();
