#!/usr/bin/env node
/**
 * Transferência de sessão Claude Code para Codex CLI.
 *
 * Lê transcript de Claude Code (JSONL), coleta as últimas n mensagens user/assistant,
 * monta um prompt para `codex exec --json`, extrai thread_id do primeiro evento
 * `thread.started`, e devolve a saída + instrução de retomada `codex resume <thread_id>`.
 *
 * Recusa com exit 3 se a chave `transfer-codex` não está ligada (opt-in, D8).
 * Recusa com exit 2 se o caminho não está dentro de ~/.claude/projects (salvo com RFM_HOME).
 * Timeout default 540000ms. Suporta RFM_TEST=1 + CODEX_CMD para dublê de teste.
 *
 * Uso: node transferir-para-codex.cjs [--source <arquivo.jsonl>] [--ultimas <n>] [--cwd <dir>] [--timeout-ms <n>] [--help]
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { rodarCli } = require('../hooks/lib/cli-externo.cjs');

/**
 * Processa argumentos CLI.
 * @returns {object|null}
 */
const FLAGS_ACEITAS = new Set(['source', 'ultimas', 'cwd', 'timeout-ms']);

function processarArgs() {
  const args = process.argv.slice(2);
  const opts = {};

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--help') {
      return { help: true };
    }
    if (arg.startsWith('--')) {
      const key = arg.substring(2);
      if (!FLAGS_ACEITAS.has(key)) {
        console.error(`flag desconhecida: ${arg}`);
        process.exit(1);
      }
      const valor = args[i + 1];
      if (valor === undefined || valor.startsWith('--')) {
        console.error(`erro: ${arg} exige um valor`);
        process.exit(1);
      }
      opts[key] = valor;
      i++;
    } else {
      console.error(`flag desconhecida: ${arg}`);
      process.exit(1);
    }
  }

  return opts;
}

/**
 * Resolve o caminho do transcript.
 * @returns {string} caminho absoluto
 */
function resolverTranscript(opts) {
  let transcriptPath = opts.source || process.env.RAINFOREST_TRANSCRIPT_PATH;

  if (!transcriptPath) {
    console.error('erro: --source ou RAINFOREST_TRANSCRIPT_PATH obrigatório');
    process.exit(1);
  }

  return path.resolve(transcriptPath);
}

/**
 * Valida que o caminho está dentro de ~/.claude/projects.
 * Permite override de home com RFM_HOME (para testes).
 * @param {string} transcriptPath caminho absoluto resolvido
 */
function validarCaminhoTranscript(transcriptPath) {
  const home = process.env.RFM_TEST === '1' && process.env.RFM_HOME
    ? process.env.RFM_HOME
    : os.homedir();

  const claudeProjectsDir = path.resolve(home, '.claude', 'projects');
  const normalizado = path.resolve(transcriptPath);

  // Verifica se está dentro de .claude/projects
  if (!normalizado.startsWith(claudeProjectsDir + path.sep) && normalizado !== claudeProjectsDir) {
    console.error(`erro: transcript deve estar dentro de ${claudeProjectsDir}`);
    process.exit(2);
  }
}

/**
 * Lê JSONL e coleta últimas n mensagens user/assistant com texto.
 * @param {string} transcriptPath
 * @param {number} ultimas quantidade de mensagens a coletar
 * @returns {Array} array de mensagens com { type, text }
 */
function coletarMensagens(transcriptPath, ultimas) {
  if (!fs.existsSync(transcriptPath)) {
    console.error(`erro: arquivo não existe: ${transcriptPath}`);
    process.exit(1);
  }

  let conteudo;
  try {
    conteudo = fs.readFileSync(transcriptPath, 'utf8');
  } catch (e) {
    console.error(`erro: não consegui ler transcript: ${e.message}`);
    process.exit(1);
  }

  const linhas = conteudo.trim().split('\n');
  const mensagens = [];

  for (const linha of linhas) {
    if (!linha.trim()) continue;

    let evento;
    try {
      evento = JSON.parse(linha);
    } catch {
      // Ignora linha inválida
      continue;
    }

    if (!evento.type) continue;

    // Shape esperado: {"type":"user"|"assistant","message":{"role":"...","content":[{"type":"text","text":"..."}]}}
    // ou {"type":"user"|"assistant","message":{"role":"...","content":"..."}} para strings diretas
    if ((evento.type === 'user' || evento.type === 'assistant') && evento.message) {
      const msg = evento.message;
      if (!msg.content) continue;

      let texto = null;

      // Se content é array
      if (Array.isArray(msg.content)) {
        for (const item of msg.content) {
          if (item.type === 'text' && item.text) {
            texto = item.text;
            break;
          }
        }
      }
      // Se content é string direto
      else if (typeof msg.content === 'string') {
        texto = msg.content;
      }

      if (texto) {
        mensagens.push({
          type: evento.type === 'user' ? 'user' : 'assistant',
          text: texto,
        });
      }
    }
  }

  // Retorna as últimas n
  return mensagens.slice(-ultimas);
}

/**
 * Monta prompt com cabeçalho em pt-BR e blocos ## <role>.
 * @param {Array} mensagens array de { type, text }
 * @returns {string}
 */
function montarPrompt(mensagens) {
  let prompt = 'Esta é a continuação de uma sessão anterior do Claude Code. Segue o histórico de mensagens:\n\n';

  for (const msg of mensagens) {
    const role = msg.type === 'user' ? 'Usuário' : 'Assistente';
    prompt += `## ${role}\n\n${msg.text}\n\n`;
  }

  return prompt;
}

/**
 * Extrai thread_id do primeiro evento thread.started.
 * @param {string} stdout saída JSONL do Codex
 * @returns {string|null} thread_id ou null
 */
function extrairThreadId(stdout) {
  const linhas = stdout.split('\n');
  for (const linha of linhas) {
    if (!linha.trim()) continue;
    try {
      const evento = JSON.parse(linha);
      if (evento.type === 'thread.started' && evento.thread_id) {
        return evento.thread_id;
      }
    } catch {
      // Ignora linha inválida (lixo no stdout)
    }
  }
  return null;
}

/**
 * Extrai mensagens de agent_message e texto final do stdout JSONL.
 * @param {string} stdout saída JSONL do Codex
 * @returns {string} texto concatenado
 */
function extrairMensagensAgente(stdout) {
  const linhas = stdout.split('\n');
  const textos = [];

  for (const linha of linhas) {
    if (!linha.trim()) continue;
    try {
      const evento = JSON.parse(linha);
      if (evento.type === 'item.completed' && evento.item && evento.item.type === 'agent_message' && evento.item.text) {
        textos.push(evento.item.text);
      }
    } catch {
      // Ignora lixo
    }
  }

  return textos.join('\n');
}

/**
 * Main.
 */
async function main() {
  const opts = processarArgs();

  if (opts.help) {
    console.log(`
Transfere sessão Claude Code para Codex CLI.

Uso:
  node transferir-para-codex.cjs \\
    [--source <arquivo.jsonl>] \\
    [--ultimas <n>] \\
    [--cwd <dir>] \\
    [--timeout-ms <ms>] \\
    [--help]

Opcionais:
  --source <arquivo>        Caminho do transcript (ou RAINFOREST_TRANSCRIPT_PATH)
  --ultimas <n>             Quantidade de mensagens (default: 20)
  --cwd <dir>               Diretório de trabalho (default: cwd)
  --timeout-ms <ms>         Timeout em ms (default: 540000)
  --help                    Esta ajuda
    `);
    process.exit(0);
  }

  const transcriptPath = resolverTranscript(opts);
  validarCaminhoTranscript(transcriptPath);

  const ultimas = opts.ultimas ? parseInt(opts.ultimas, 10) : 20;
  if (!Number.isFinite(ultimas) || ultimas <= 0) {
    console.error('erro: --ultimas deve ser um número positivo');
    process.exit(1);
  }

  const cwd = opts.cwd || process.cwd();
  if (!fs.existsSync(cwd)) {
    console.error(`erro: diretório não existe: ${cwd}`);
    process.exit(1);
  }

  // Opt-in (D8): a chave `transfer-codex` é o portão do recurso, e o portão
  // mora AQUI, no script que manda texto de sessão para fora — não só no hook
  // de abertura, que apenas grava o caminho do transcript. Config ilegível
  // conta como desligada: sair dado da máquina por engano é o erro caro.
  let transferLigado = false;
  try {
    const { resolverConfig } = require('../hooks/lib/config.cjs');
    transferLigado = resolverConfig({ projeto: cwd }).valores['transfer-codex'] === true;
  } catch {
    transferLigado = false;
  }
  if (!transferLigado) {
    console.error('recusado: a chave transfer-codex está desligada (opt-in). Ligue com: node scripts/setup.cjs --ligar transfer-codex');
    process.exit(3);
  }

  const timeoutMs = opts['timeout-ms'] ? parseInt(opts['timeout-ms'], 10) : 540000;
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    console.error('erro: --timeout-ms deve ser um número positivo');
    process.exit(1);
  }

  // Coleta mensagens
  const mensagens = coletarMensagens(transcriptPath, ultimas);
  const prompt = montarPrompt(mensagens);

  // Monta comando
  let cmd = `codex exec --json --skip-git-repo-check -s read-only -C "${cwd}"`;

  // Suporte para RFM_TEST
  let env = process.env;
  let cmdReal = cmd;
  if (process.env.RFM_TEST === '1' && process.env.CODEX_CMD) {
    cmd = process.env.CODEX_CMD;
    env = { ...process.env, DESPACHAR_CODEX_CMD_REAL: cmdReal };
  }

  // Executa
  const resultado = rodarCli({ cmd, entrada: prompt, timeoutMs, env });

  // Trata resultado
  if (resultado.status === null) {
    // Timeout
    console.error(`timeout apos ${timeoutMs} ms`);
    process.exit(124);
  }

  if (resultado.status !== 0) {
    // Erro do Codex
    if (resultado.stderr) {
      console.error(resultado.stderr);
    }
    process.exit(resultado.status || 1);
  }

  // Sucesso: extrai thread_id
  const threadId = extrairThreadId(resultado.stdout);
  if (!threadId) {
    console.error('erro: nao achei thread.started na saida');
    process.exit(1);
  }

  // Imprime mensagens de agent_message se houver
  const mensagensAgente = extrairMensagensAgente(resultado.stdout);
  if (mensagensAgente) {
    console.log(mensagensAgente);
  }

  // Última linha: instrução de retomada
  console.log(`codex resume ${threadId}`);
  process.exit(0);
}

main().catch(e => {
  console.error(`erro: ${e.message}`);
  process.exit(1);
});
