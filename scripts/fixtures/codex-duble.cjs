#!/usr/bin/env node
/**
 * Dublê Node para Codex — simula exec com stdin/stdout controlado.
 *
 * Variáveis de ambiente:
 * - DUBLE_MODO: "ok" (exit 0), "falha" (exit 1 + stderr), "dorme" (dorme 5s), "transfer" (emite thread.started + agent_message),
 *   "parecer" (grava DUBLE_PARECER no arquivo -o do comando real — costura com o gate de Stop)
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
