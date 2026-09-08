#!/usr/bin/env node
/**
 * Dublê Node para Codex — simula exec com stdin/stdout controlado.
 *
 * Variáveis de ambiente:
 * - DUBLE_MODO: "ok" (exit 0), "falha" (exit 1 + stderr), "dorme" (dorme 5s)
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
