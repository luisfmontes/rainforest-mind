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
const { Transform } = require('stream');
const { spawn } = require('child_process');

const { caminhoPid, portaPadrao, caminhoMetricas, caminhoContexto } = require('../hooks/lib/poda-dados.cjs');
const { resolverConfig } = require('../hooks/lib/config.cjs');
const { estagioAtivo } = require('../hooks/lib/poda-estagio.cjs');

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
 * Extrai o último uso (usage) de uma cópia do stream SSE.
 * Retorna um Transform stream que passa os dados intactos e acumula o usage.
 */
function criarExtractorUsage() {
  let ultimoUsage = null;
  let buffer = '';

  // O evento `message_start` real da Anthropic aninha o usage inicial em
  // `message.usage` (input_tokens, cache_read_input_tokens,
  // cache_creation_input_tokens, e um output_tokens ainda parcial). O
  // `message_delta` manda um `usage` NO TOPO do evento, tipicamente só com o
  // `output_tokens` final. Os dois precisam ser MESCLADOS — sobrescrever com
  // o último `usage` visto (como uma versão anterior fazia) perde
  // input_tokens/cache_* inteiros assim que o message_delta chega, porque o
  // objeto dele não tem essas chaves.
  function processarLinha(linha) {
    if (!linha.startsWith('data: ')) return;
    try {
      const json = JSON.parse(linha.substring(6));
      const usageAninhado = json.message && json.message.usage;
      const usageTopo = json.usage;
      if (usageAninhado || usageTopo) {
        ultimoUsage = Object.assign({}, ultimoUsage, usageAninhado, usageTopo);
      }
    } catch {
      // linha não é JSON válido, ignora
    }
  }

  return {
    stream: new Transform({
      transform(chunk, encoding, callback) {
        buffer += chunk.toString('utf8');

        // Processa linhas completas do SSE
        const linhas = buffer.split('\n');
        buffer = linhas.pop(); // Última linha incompleta fica no buffer

        for (const linha of linhas) {
          processarLinha(linha);
        }

        // Passa o chunk intacto
        callback(null, chunk);
      },
      flush(callback) {
        // Processa última linha do buffer se houver
        processarLinha(buffer);
        callback();
      },
    }),
    getUsage: () => ultimoUsage,
  };
}

/**
 * Grava uma métrica em metricas.jsonl (atômico).
 */
function gravarMetrica(metrica, cwd, env) {
  try {
    const config = resolverConfig({ env, projeto: cwd });
    if (!config.valores.poda) {
      return; // chave desligada
    }

    const caminhoArq = caminhoMetricas({ env, cwd });
    if (!caminhoArq) return;

    fs.mkdirSync(path.dirname(caminhoArq), { recursive: true });
    fs.appendFileSync(caminhoArq, JSON.stringify(metrica) + '\n', 'utf8');
  } catch {
    // falha silenciosa: métrica perdida, proxy continua
  }
}

/**
 * Atualiza contexto.json atomicamente (.tmp + rename).
 */
function atualizarContexto(contexto, cwd, env) {
  try {
    const config = resolverConfig({ env, projeto: cwd });
    if (!config.valores.poda) {
      return; // chave desligada
    }

    const caminhoArq = caminhoContexto({ env, cwd });
    if (!caminhoArq) return;

    fs.mkdirSync(path.dirname(caminhoArq), { recursive: true });
    const tmp = `${caminhoArq}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(contexto, null, 2) + '\n', 'utf8');
    fs.renameSync(tmp, caminhoArq);
  } catch {
    // falha silenciosa: contexto perdido, proxy continua
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

  // Resolve o cwd para localizar arquivos de dados
  const cwd = env.CLAUDE_PROJECT_DIR || process.cwd();

  // Resolve estágio UMA VEZ na partida
  let estagioRaiz = null;
  try {
    const info = estagioAtivo({ cwd, env });
    estagioRaiz = info ? info.estagio : null;
  } catch {
    estagioRaiz = null;
  }

  // Conta total de requisições
  let contadorRequisicoes = 0;

  const server = http.createServer((req, res) => {
    contadorRequisicoes++;

    // Marca o início da requisição
    const inicioRequisicao = Date.now();

    // Resolve URL do upstream
    const upstreamUrl = `${upstream}${req.url}`;

    // Opções de requisição ao upstream
    const opcoes = {
      method: req.method,
      headers: req.headers,
      timeout: 30000,
    };

    // Acumula o corpo da requisição para contar mensagens e bytes
    let corpoRequisicao = Buffer.alloc(0);
    let mensagensRequisicao = 0;

    // Faz requisição ao upstream
    const proxyReq = moduloUpstream.request(upstreamUrl, opcoes, (upstreamRes) => {
      // Copia status e headers da resposta
      res.writeHead(upstreamRes.statusCode, upstreamRes.headers);

      // Cria o extrator de usage
      const extractorUsage = criarExtractorUsage();

      // Repassa corpo por stream (sem bufferizar) via extrator
      upstreamRes
        .pipe(extractorUsage.stream)
        .pipe(res);

      // Quando a resposta termina, grava métricas
      res.on('finish', () => {
        const duracao = Date.now() - inicioRequisicao;
        const usage = extractorUsage.getUsage();

        // Grava métrica
        const metrica = {
          timestamp: new Date().toISOString(),
          estagio: estagioRaiz,
          mensagens: mensagensRequisicao,
          bytes_corpo: corpoRequisicao.length,
          duracao_ms: duracao,
          usage: usage || {
            input_tokens: 0,
            output_tokens: 0,
            cache_read_input_tokens: 0,
            cache_creation_input_tokens: 0,
          },
        };

        gravarMetrica(metrica, cwd, env);

        // Atualiza contexto
        const contexto = {
          atualizadoEm: new Date().toISOString(),
          estagio: estagioRaiz,
          usage: metrica.usage,
          requisicoes: contadorRequisicoes,
        };

        atualizarContexto(contexto, cwd, env);
      });
    });

    // Trata erros na requisição ao upstream
    proxyReq.on('error', (e) => {
      console.error(`erro ao conectar ao upstream: ${e.message}`);
      if (!res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'text/plain' });
      }
      res.end('Bad Gateway\n');
    });

    // Acumula o corpo da requisição e repassa
    req.on('data', (chunk) => {
      corpoRequisicao = Buffer.concat([corpoRequisicao, chunk]);
      proxyReq.write(chunk);
    });

    req.on('end', () => {
      // Tenta contar mensagens do body (heurística: procura por "content" array)
      try {
        const bodyStr = corpoRequisicao.toString('utf8');
        const bodyJson = JSON.parse(bodyStr);
        if (Array.isArray(bodyJson.messages)) {
          // Cada objeto mensagem tem um array "content" com blocos
          mensagensRequisicao = bodyJson.messages.length;
        }
      } catch {
        // Body não é JSON ou não tem estrutura esperada, não conta
      }

      proxyReq.end();
    });

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
