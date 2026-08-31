#!/usr/bin/env node
/**
 * Proxy passthrough + ciclo de vida: iniciar/parar/status
 *
 * Proxy HTTP escutando SÓ em 127.0.0.1, repassando requisições e respostas
 * byte a byte para o upstream (default https://api.anthropic.com).
 *
 * Uso:
 *   node scripts/poda.cjs iniciar [--porta N]
 *   node scripts/poda.cjs parar
 *   node scripts/poda.cjs status
 */

'use strict';

const http = require('http');
const https = require('https');
const net = require('net');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const { caminhoPid, portaPadrao } = require('../hooks/lib/poda-dados.cjs');

/**
 * Lê o pidfile e devolve {pid, porta, iniciadoEm} ou null.
 */
function lerPidfile(caminhoArq) {
  try {
    const conteudo = fs.readFileSync(caminhoArq, 'utf8');
    return JSON.parse(conteudo);
  } catch {
    return null;
  }
}

/**
 * Grava o pidfile atomicamente (via .tmp + rename).
 */
function gravarPidfile(caminhoArq, dados) {
  fs.mkdirSync(path.dirname(caminhoArq), { recursive: true });
  const tmp = `${caminhoArq}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(dados, null, 2) + '\n', 'utf8');
  fs.renameSync(tmp, caminhoArq);
}

/**
 * Apaga o pidfile.
 */
function apagarPidfile(caminhoArq) {
  try {
    fs.unlinkSync(caminhoArq);
  } catch {
    // já não existe
  }
}

/**
 * Testa se a porta responde com uma requisição real.
 */
function testarPorta(porta, callback) {
  const socket = net.createConnection({ host: '127.0.0.1', port: porta });
  let respondeu = false;

  socket.setTimeout(2000);

  socket.on('connect', () => {
    respondeu = true;
    socket.destroy();
    callback(true);
  });

  socket.on('timeout', () => {
    socket.destroy();
    if (!respondeu) callback(false);
  });

  socket.on('error', () => {
    if (!respondeu) callback(false);
  });
}

/**
 * Comando: iniciar [--porta N]
 * Destacha o processo servidor.
 */
function comandoIniciar(argv, env) {
  let porta = portaPadrao({ env });

  // Parse --porta
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--porta' && i + 1 < argv.length) {
      const valor = Number.parseInt(argv[i + 1], 10);
      if (Number.isInteger(valor) && valor >= 1 && valor <= 65535) {
        porta = valor;
      }
    }
  }

  const caminhoArq = caminhoPid({ env });
  if (!caminhoArq) {
    console.error('erro: nao consegui resolver raiz de dados da poda');
    process.exit(1);
  }

  // Cria diretório
  fs.mkdirSync(path.dirname(caminhoArq), { recursive: true });

  // Verifica se já há processo rodando
  const pidfileExistente = lerPidfile(caminhoArq);
  if (pidfileExistente) {
    console.error(`aviso: pidfile já existe (${caminhoArq})`);
    console.error('  rode "parar" antes de iniciar novamente, ou exclua o pidfile manualmente');
    process.exit(1);
  }

  // Inicia servidor em background (via spawn + detach)
  const servidorArq = path.join(__dirname, 'poda.cjs');
  const logFile = path.join(path.dirname(caminhoArq), 'poda.log');

  const filho = spawn('node', [servidorArq, '_servidor-interno', `--porta=${porta}`], {
    detached: true,
    stdio: ['ignore', 'ignore', 'ignore'],
    env: {
      ...env,
      RFM_PODA_PORTA: String(porta),
      RFM_PODA_UPSTREAM: env.RFM_PODA_UPSTREAM || 'https://api.anthropic.com',
    },
  });

  // Desatacha do processo pai
  filho.unref();

  // Grava pidfile com pid do filho (node process)
  gravarPidfile(caminhoArq, {
    pid: filho.pid,
    porta,
    iniciadoEm: new Date().toISOString(),
  });

  console.log(`poda iniciada: PID ${filho.pid}, porta ${porta}`);
}

/**
 * Comando: parar
 * Mata o processo e apaga o pidfile.
 */
function comandoParar(env) {
  const caminhoArq = caminhoPid({ env });
  if (!caminhoArq) {
    console.error('erro: nao consegui resolver raiz de dados da poda');
    process.exit(1);
  }

  const pidfile = lerPidfile(caminhoArq);
  if (!pidfile) {
    console.log('aviso: poda nao esta rodando (pidfile nao encontrado)');
    process.exit(0);
  }

  try {
    process.kill(pidfile.pid, 'SIGTERM');
    // Aguarda um pouco para o processo morrer
    setTimeout(() => {
      apagarPidfile(caminhoArq);
      console.log(`poda parada (PID ${pidfile.pid})`);
    }, 500);
  } catch (e) {
    console.error(`erro ao matar PID ${pidfile.pid}: ${e.message}`);
    apagarPidfile(caminhoArq);
    process.exit(1);
  }
}

/**
 * Comando: status
 * Lê pidfile e testa se porta responde.
 */
function comandoStatus(env) {
  const caminhoArq = caminhoPid({ env });
  if (!caminhoArq) {
    console.error('erro: nao consegui resolver raiz de dados da poda');
    process.exit(1);
  }

  const pidfile = lerPidfile(caminhoArq);
  if (!pidfile) {
    console.log('poda nao esta rodando');
    process.exit(1);
  }

  console.log(`verificando porta ${pidfile.porta}...`);

  testarPorta(pidfile.porta, (respondeu) => {
    if (respondeu) {
      console.log(`ok: porta ${pidfile.porta} responde (PID ${pidfile.pid})`);
      process.exit(0);
    } else {
      console.log(`erro: porta ${pidfile.porta} nao responde (pidfile aponta PID ${pidfile.pid})`);
      process.exit(1);
    }
  });
}

/**
 * Servidor interno (destacado): proxy passthrough
 */
function servidorInterno(porta, env) {
  const upstream = env.RFM_PODA_UPSTREAM || 'https://api.anthropic.com';
  const isHttps = upstream.startsWith('https');
  const moduloUpstream = isHttps ? https : http;

  const server = http.createServer((req, res) => {
    // Resolve URL do upstream
    const upstreamUrl = `${upstream}${req.url}`;

    // Opções de requisição ao upstream
    const opcoes = {
      method: req.method,
      headers: req.headers,
      timeout: 30000,
    };

    // Faz requisição ao upstream
    const proxyReq = moduloUpstream.request(upstreamUrl, opcoes, (upstreamRes) => {
      // Copia status e headers da resposta
      res.writeHead(upstreamRes.statusCode, upstreamRes.headers);

      // Repassa corpo por stream (sem bufferizar)
      upstreamRes.pipe(res);
    });

    // Trata erros na requisição ao upstream
    proxyReq.on('error', (e) => {
      console.error(`erro ao conectar ao upstream: ${e.message}`);
      if (!res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'text/plain' });
      }
      res.end('Bad Gateway\n');
    });

    // Repassa o corpo da requisição
    req.pipe(proxyReq);

    // Trata erro no pipe
    req.on('error', (e) => {
      console.error(`erro ao receber requisicao: ${e.message}`);
      proxyReq.abort();
    });
  });

  server.on('error', (e) => {
    console.error(`erro do servidor: ${e.message}`);
    process.exit(1);
  });

  // Escuta APENAS em 127.0.0.1
  server.listen(porta, '127.0.0.1', () => {
    const msg = `proxy escutando em 127.0.0.1:${porta}`;
    console.log(msg);
    // Log também em stderr para captura pelo arquivo de log
    console.error(`[proxy] ${msg}`);
  });

  // Graceful shutdown
  process.on('SIGTERM', () => {
    console.log('recebido SIGTERM, encerrando...');
    server.close(() => {
      process.exit(0);
    });
  });
}

// Main
const comando = process.argv[2];

if (comando === '_servidor-interno') {
  // Modo interno: servidor destacado
  const portaStr = process.argv[3] || '--porta=4141';
  const porta = Number.parseInt(portaStr.split('=')[1], 10);
  servidorInterno(porta, process.env);
} else if (comando === 'iniciar') {
  comandoIniciar(process.argv.slice(3), process.env);
} else if (comando === 'parar') {
  comandoParar(process.env);
} else if (comando === 'status') {
  comandoStatus(process.env);
} else {
  console.error('uso: poda.cjs <iniciar|parar|status> [opcoes]');
  process.exit(1);
}
