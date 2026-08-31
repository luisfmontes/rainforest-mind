#!/usr/bin/env node
"use strict";
/* Bateria da catraca da Tarefa 2 do fluxo 9 (portaria, modo captura).
 *
 * Mede UMA coisa: a idempotência da gravação (D7 — primeira captura vence).
 * Duas execuções do hook com payloads JSON distintos no stdin: a primeira
 * grava a amostra, a segunda NÃO sobrescreve. Mais dois casos de borda:
 * stdin vazio e payload ilegível não viram amostra.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha (com contagem no fim).
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "portaria.cjs");

let ok = 0;
let falhou = 0;

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe ? ` — ${detalhe}` : ""}`);
  }
}

function rodaHook(raiz, stdin) {
  return spawnSync(process.execPath, [HOOK], {
    input: stdin,
    env: { ...process.env, CLAUDE_PROJECT_DIR: raiz },
    encoding: "utf8",
  });
}

function caixa() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "portaria-captura-"));
}

// == 1. primeira execução grava a amostra ==
console.log("== 1. primeira execucao grava a amostra ==");
{
  const raiz = caixa();
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  const r = rodaHook(raiz, JSON.stringify({ tool_name: "Task", tool_input: { subagent_type: "PRIMEIRO" } }));
  caso("exit 0", r.status === 0, `exit=${r.status}`);
  caso("amostra.json existe", fs.existsSync(amostra));
  let lido = null;
  try { lido = JSON.parse(fs.readFileSync(amostra, "utf8")); } catch {}
  caso("amostra e JSON valido com o payload da 1a execucao",
    lido && lido.tool_input && lido.tool_input.subagent_type === "PRIMEIRO");
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 2. segunda execução NÃO sobrescreve (primeira captura vence, D7) ==
console.log("== 2. segunda execucao NAO sobrescreve ==");
{
  const raiz = caixa();
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  rodaHook(raiz, JSON.stringify({ tool_name: "Task", tool_input: { subagent_type: "PRIMEIRO" } }));
  const r2 = rodaHook(raiz, JSON.stringify({ tool_name: "Task", tool_input: { subagent_type: "SEGUNDO" } }));
  caso("exit 0 na segunda execucao", r2.status === 0, `exit=${r2.status}`);
  let lido = null;
  try { lido = JSON.parse(fs.readFileSync(amostra, "utf8")); } catch {}
  caso("amostra continua com o payload da PRIMEIRA execucao",
    lido && lido.tool_input && lido.tool_input.subagent_type === "PRIMEIRO",
    lido && lido.tool_input ? `veio ${lido.tool_input.subagent_type}` : "amostra ilegivel");
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 3. stdin vazio nao vira amostra ==
console.log("== 3. stdin vazio nao vira amostra ==");
{
  const raiz = caixa();
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  const r = rodaHook(raiz, "");
  caso("exit 0", r.status === 0, `exit=${r.status}`);
  caso("amostra.json NAO existe", !fs.existsSync(amostra));
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 4. payload ilegivel nao vira amostra ==
console.log("== 4. payload ilegivel nao vira amostra ==");
{
  const raiz = caixa();
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  const r = rodaHook(raiz, "{isso nao e json");
  caso("exit 0", r.status === 0, `exit=${r.status}`);
  caso("amostra.json NAO existe", !fs.existsSync(amostra));
  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou > 0 ? 1 : 0);
