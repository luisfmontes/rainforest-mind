#!/usr/bin/env node
/**
 * Dublê Node para Codex — simula exec com stdin/stdout controlado.
 *
 * Variáveis de ambiente:
 * - DUBLE_MODO: "ok" (exit 0), "falha" (exit 1 + stderr), "dorme" (dorme 5s), "transfer" (emite thread.started + agent_message),
 *   "parecer" (grava DUBLE_PARECER no arquivo -o do comando real — costura com o gate de Stop),
 *   "semcota" (stderr e exit 1 do codex exec real sem cota, medido em 2026-09-08),
 *   "semcota-json" (a mesma falha como eventos JSONL no stdout, para o --json do transferir)
 * - DUBLE_PARECER: texto do parecer no modo "parecer" (default "ALLOW: ok")
 * - DUBLE_STDIN_OUT: arquivo onde escrever o stdin recebido
 * - DUBLE_CMD_OUT: arquivo onde escrever o comando (env.DESPACHAR_CODEX_CMD_REAL)
 * - DUBLE_SAIDA: arquivo onde escrever "RESPOSTA DO DUBLE"
 *
 * Uso: node codex-duble.cjs (lê stdin inteiro, grava onde pedido, sai 0/1)
 */

const fs = require('fs');

async function main() {
  const modo = process.env.DUBLE_MODO || 'ok';
  const stdinOut = process.env.DUBLE_STDIN_OUT;
  const cmdOut = process.env.DUBLE_CMD_OUT;
  const saidaArquivo = process.env.DUBLE_SAIDA;

  // Lê stdin inteiro
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  const stdin = Buffer.concat(chunks).toString('utf8');

  // Grava stdin se pedido
  if (stdinOut) {
    try {
      fs.writeFileSync(stdinOut, stdin, 'utf8');
    } catch (e) {
      console.error(`erro ao gravar stdin: ${e.message}`);
    }
  }

  // Grava comando montado se pedido
  if (cmdOut) {
    const cmd = process.env.DESPACHAR_CODEX_CMD_REAL || '';
    try {
      fs.writeFileSync(cmdOut, cmd, 'utf8');
    } catch (e) {
      console.error(`erro ao gravar cmd: ${e.message}`);
    }
  }

  // Controla modo
  if (modo === 'dorme') {
    // Dorme 5 segundos antes de sair
    await new Promise(r => setTimeout(r, 5000));
  }

  // Modo transfer: emite eventos JSONL
  if (modo === 'transfer') {
    // Emite thread.started
    console.log(JSON.stringify({
      type: 'thread.started',
      thread_id: 'abc-123',
    }));
    // Emite item.completed com agent_message
    console.log(JSON.stringify({
      type: 'item.completed',
      item: {
        type: 'agent_message',
        text: 'ok, continuo daqui',
      },
    }));
    // Emite turn.completed
    console.log(JSON.stringify({
      type: 'turn.completed',
    }));
  }

  // Modo parecer: escreve DUBLE_PARECER (default "ALLOW: ok") no arquivo -o que o
  // despachar-codex.cjs montou — o caminho vem de DESPACHAR_CODEX_CMD_REAL, porque
  // quem chamou o despacho (o gate de Stop, por exemplo) nao conhece esse arquivo.
  // E o que permite testar a costura hook -> despachar-codex -> codex sem codex.
  if (modo === 'parecer') {
    const parecer = process.env.DUBLE_PARECER || 'ALLOW: ok';
    const cmdReal = process.env.DESPACHAR_CODEX_CMD_REAL || '';
    const m = cmdReal.match(/ -o "([^"]+)"/);
    if (m) {
      try { fs.writeFileSync(m[1], parecer + '\n', 'utf8'); } catch (e) { console.error(`erro ao gravar parecer: ${e.message}`); }
    }
    console.log(parecer);
  }

  // Grava saída
  if (saidaArquivo) {
    try {
      fs.writeFileSync(saidaArquivo, 'RESPOSTA DO DUBLE', 'utf8');
    } catch (e) {
      console.error(`erro ao gravar saida: ${e.message}`);
    }
  }

  // Modo semcota: o que o codex exec REAL fez em 2026-09-08 com o limite de
  // 5 h estourado — banner no stderr, a mensagem de cota duas vezes, exit 1,
  // nenhum arquivo -o. Texto literal da medição.
  const MSG_COTA = "You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 5:41 PM.";
  if (modo === 'semcota') {
    console.error('OpenAI Codex v0.151.0\n--------\nworkdir: (duble)\nmodel: gpt-5.6-sol\nprovider: openai\napproval: never\nsandbox: read-only\n--------\nuser\n(briefing)\n');
    console.error(`ERROR: ${MSG_COTA}`);
    console.error(`ERROR: ${MSG_COTA}`);
    process.exit(1);
  }

  // Modo semcota-json: a mesma falha vista pelo `codex exec --json` (o que o
  // transferir-para-codex.cjs usa) — eventos no stdout, mensagem no evento error.
  if (modo === 'semcota-json') {
    console.log(JSON.stringify({ type: 'thread.started', thread_id: 'sem-cota-000' }));
    console.log(JSON.stringify({ type: 'turn.started' }));
    console.log(JSON.stringify({ type: 'error', message: MSG_COTA }));
    console.log(JSON.stringify({ type: 'turn.failed', error: { message: MSG_COTA } }));
    process.exit(1);
  }

  // Sai com status apropriado
  if (modo === 'falha') {
    console.error('erro simulado');
    process.exit(1);
  }

  process.exit(0);
}

main().catch(e => {
  console.error(`erro: ${e.message}`);
  process.exit(1);
});
