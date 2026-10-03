#!/usr/bin/env node
"use strict";
/* Sugere a ordem das regras cuja elaboracao vai inteira no system prompt.
 *
 * Uso:
 *   node scripts/sugerir-elaboracoes.cjs [caminho/ideias.jsonl]
 *   node scripts/sugerir-elaboracoes.cjs --help
 *
 * Sem argumento, le o ideias.jsonl da raiz de dados (mesma resolucao de
 * scripts/ideias.cjs). Conta, nas linhas "tipo":"observacao", quantas observacoes
 * citam cada regra (1 a 17, padrao `regra[s]? ?N`, uma vez por observacao) e
 * imprime da mais citada a menos, marcando as que ja estao em
 * hooks/abertura-mod.json.
 *
 * SOMENTE LEITURA: so sugere. A lista fica fixa em abertura-mod.json (mudar o
 * prompt e decisao humana); quem decide aplica a mao. Nunca e chamado por hook.
 */

const fs = require("fs");
const path = require("path");

const PLUGIN = path.resolve(__dirname, "..");
const CONFIG = path.join(PLUGIN, "hooks", "abertura-mod.json");
// \b antes e depois: "regra 1" nao conta dentro de "regra 16" nem de "regra 18".
const PADRAO = /\bregras? ?(1[0-7]|[1-9])\b/gi;

function raizDeDados() {
  try {
    const { resolverRaiz } = require("../hooks/lib/raiz.cjs");
    return resolverRaiz({ plugin: PLUGIN }).raiz || PLUGIN;
  } catch {
    return PLUGIN;
  }
}

function textoDe(obj) {
  return Object.values(obj).filter((v) => typeof v === "string").join("\n");
}

function main() {
  const arg = process.argv[2];
  if (arg === "--help" || arg === "-h") {
    const cab = fs.readFileSync(__filename, "utf8").split("\n").slice(4, 16);
    console.log(cab.map((l) => l.replace(/^ ?\* ?/, "")).join("\n"));
    return 0;
  }
  const alvo = arg || path.join(raizDeDados(), "ideias.jsonl");
  let cru;
  try {
    cru = fs.readFileSync(alvo, "utf8");
  } catch (e) {
    console.error(`nao consegui ler ${alvo}: ${e.message}`);
    return 1;
  }
  const noPrompt = new Set(JSON.parse(fs.readFileSync(CONFIG, "utf8")).elaboracoes);

  const contagem = new Map();
  let observacoes = 0;
  let invalidas = 0;
  for (const linha of cru.split("\n")) {
    if (!linha.trim()) continue;
    let obj;
    try {
      obj = JSON.parse(linha);
    } catch {
      invalidas++;
      continue;
    }
    if (!obj || obj.tipo !== "observacao") continue;
    observacoes++;
    const citadas = new Set([...textoDe(obj).matchAll(PADRAO)].map((m) => Number(m[1])));
    for (const n of citadas) contagem.set(n, (contagem.get(n) || 0) + 1);
  }

  console.log(`fonte: ${alvo}`);
  console.log(`observacoes: ${observacoes}`);
  if (invalidas) console.log(`AVISO: ${invalidas} linha(s) com JSON invalido ignorada(s)`);
  const ordem = [...contagem.entries()]
    .sort((a, b) => b[1] - a[1] || a[0] - b[0]);
  for (const [n, c] of ordem) {
    console.log(`regra ${n}: ${c}${noPrompt.has(n) ? "  [ja em abertura-mod.json]" : ""}`);
  }
  console.log(`atual em abertura-mod.json: [${[...noPrompt].join(", ")}] (so sugestao; nada foi alterado)`);
  return 0;
}

process.exit(main());
