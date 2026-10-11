#!/usr/bin/env node
// @categoria: sensor
/**
 * Roda a bateria do critério de uma tarefa com UMA nova tentativa (D4, D8).
 *
 * A repetição mora em script, nunca em prosa: retry instruído numa skill deixa a
 * janela redigir o próprio veredito, que é o que a catraca existe para impedir.
 * Repete só o que falhou, uma vez: exit 0 de primeira passa direto; exit ≠ 0
 * numérico roda de novo; verde na segunda = FLAKE (passa, e grava o flake no
 * estado do fluxo); vermelho nas duas = vermelho de verdade.
 *
 * Nunca repete o que o acaso não produz: estouro de tempo, morte por sinal,
 * comando que não executa (126, 127, ENOENT).
 *
 * Reaproveita `rodaBateria` da catraca (stdin fechado, teto de tempo, bash do Git).
 *
 * Uso: node scripts/rodar-gate.cjs --comando '<bateria>' [--raiz <pasta>]
 *        [--timeout <ms>] [--slug <slug> --tarefa <n>]
 *
 * exit: 0 verde (de primeira ou só na nova tentativa) | 2 vermelho nas duas
 *       rodadas | 1 uso, ou rodada sem veredito (estouro de tempo, sinal) |
 *       69 o comando não executa (ambiente, não conteúdo)
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { rodaBateria, gravarFlake } = require(path.join(__dirname, 'conferir-mutacao.cjs'));

const TIMEOUT_PADRAO = 300000; // 5 min, o mesmo da catraca

function erroUso(msg) {
  console.error(`erro: ${msg}`);
  console.error("uso: node scripts/rodar-gate.cjs --comando '<bateria>' [--raiz <pasta>] [--timeout <ms>] [--slug <slug> --tarefa <n>]");
  process.exit(1);
}

function ler(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1) return null;
  if (i + 1 >= process.argv.length) erroUso(`--${nome} veio sem valor`);
  return process.argv[i + 1];
}

function cauda(res, n) {
  const linhas = `${res.r.stdout || ''}${res.r.stderr || ''}`.split('\n').filter((l) => l.trim() !== '');
  return linhas.slice(-n).join('\n');
}

function mostra(res, rotulo) {
  console.log(`--- ${rotulo}: exit ${res.r.status} em ${res.duracao} ms ---`);
  const c = cauda(res, 20);
  if (c) console.log(c);
}

// Rodada sem exit numérico: não é vermelho, não é verde, e não se repete.
function semVeredito(res, rotulo) {
  if (res.r.error && res.r.error.code !== 'ETIMEDOUT') {
    process.stderr.write(`nao-verificavel: o comando nao executa — ${res.r.error.message}\n`);
    process.exit(69);
  }
  if (res.r.error) {
    console.error(`SEM VEREDITO: ${rotulo} estourou o teto de tempo (${res.r.error.message}).`);
    process.exit(1);
  }
  if (res.r.status === null) {
    console.error(`SEM VEREDITO: ${rotulo} morta pelo sinal ${res.r.signal}, sem exit code.`);
    process.exit(1);
  }
  if (res.r.status === 126 || res.r.status === 127) {
    process.stderr.write(`nao-verificavel: o comando nao executa — exit ${res.r.status}\n`);
    process.exit(69);
  }
}

function main() {
  const comando = ler('comando');
  const raiz = ler('raiz') || process.cwd();
  const slug = ler('slug');
  const tarefa = ler('tarefa');
  if (comando === null) erroUso('falta --comando');
  if (comando.trim() === '') erroUso('--comando vazio');
  if ((slug === null) !== (tarefa === null)) erroUso('--slug e --tarefa vão juntos: os dois ou nenhum');
  const timeout = Number(ler('timeout') ?? TIMEOUT_PADRAO);
  if (!Number.isFinite(timeout) || timeout <= 0) erroUso('--timeout precisa ser um número de ms positivo');
  if (!fs.existsSync(raiz) || !fs.statSync(raiz).isDirectory()) erroUso(`--raiz não é uma pasta: ${raiz}`);

  const primeira = rodaBateria(comando, raiz, timeout, 'criterio');
  semVeredito(primeira, 'a 1a rodada');
  mostra(primeira, 'criterio (1a rodada)');

  const repetir = !primeira.r.error && primeira.r.status !== null && primeira.r.status !== 0;
  if (!repetir) process.exit(0);

  const nova = rodaBateria(comando, raiz, timeout, 'criterio (nova tentativa)');
  semVeredito(nova, 'a nova tentativa');
  mostra(nova, 'criterio (nova tentativa)');

  if (nova.r.status === 0) {
    console.log(`FLAKE: passou so na nova tentativa (1a rodada exit ${primeira.r.status}, nova tentativa exit 0)`);
    gravarFlake(slug, tarefa, `criterio: ${comando}`, raiz);
    process.exit(0);
  }
  console.error(`VERMELHO: a 1a rodada saiu ${primeira.r.status} e a nova tentativa saiu ${nova.r.status}.`);
  process.exit(2);
}

main();
