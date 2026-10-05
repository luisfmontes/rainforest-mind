#!/usr/bin/env node
// Reparte a lista de baterias (stdin, uma por linha) em N shards equilibrados
// por tempo e imprime as do shard i, na ordem original da lista.
// Uso: node scripts/repartir-baterias.cjs --shard i/n [--pesos <json>] < lista
// Pesos: segundos por bateria em scripts/tempos-baterias.json (medidos no log
// de um run verde do CI). Bateria sem peso entra com a mediana dos pesos.
// Deterministico: mesma lista + mesmos pesos => mesma reparticao (Issue #377).
'use strict';
const fs = require('fs');
const path = require('path');

function falha(msg) {
  process.stderr.write(`FALHA ${msg}\n`);
  process.exit(1);
}

const args = process.argv.slice(2);
let shard = null;
let pesosPath = path.join(__dirname, 'tempos-baterias.json');
for (let k = 0; k < args.length; k++) {
  if (args[k] === '--shard') shard = args[++k];
  else if (args[k] === '--pesos') pesosPath = args[++k];
  else falha(`opcao desconhecida: ${args[k]}`);
}
const m = /^(\d+)\/(\d+)$/.exec(shard || '');
if (!m) falha('--shard exige i/n (ex.: 1/2)');
const i = Number(m[1]);
const n = Number(m[2]);
if (n < 1 || i < 1 || i > n) falha(`--shard ${shard} fora da faixa 1..n`);

let pesos;
try {
  pesos = JSON.parse(fs.readFileSync(pesosPath, 'utf8'));
} catch (e) {
  falha(`nao li os pesos em ${pesosPath}: ${e.message}`);
}

const lista = fs.readFileSync(0, 'utf8').split('\n').map((l) => l.replace(/\r$/, '')).filter(Boolean);

const conhecidos = Object.values(pesos).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
const mediana = conhecidos.length
  ? (conhecidos[(conhecidos.length - 1) >> 1] + conhecidos[conhecidos.length >> 1]) / 2
  : 1;
const pesoDe = (b) => (Number.isFinite(pesos[b]) ? pesos[b] : mediana);

const ordem = [...lista].sort((a, b) => pesoDe(b) - pesoDe(a) || (a < b ? -1 : a > b ? 1 : 0));
const cargas = new Array(n).fill(0);
const destino = new Map();
for (const b of ordem) {
  const alvo = cargas.indexOf(Math.min(...cargas));
  cargas[alvo] += pesoDe(b);
  destino.set(b, alvo + 1);
}

for (const b of lista) if (destino.get(b) === i) console.log(b);
