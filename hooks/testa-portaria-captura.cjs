#!/usr/bin/env node
"use strict";
/* Bateria da catraca da Tarefa 2 do fluxo 9 (portaria, modo captura + nucleo).
 *
 * Testava: idempotencia da gravacao (D7 — primeira captura vence).
 * Agora testa TAMBÉM a captura dentro do nucleo de decisao (Tarefa 3).
 * Ajustada (Tarefa 3 justificativa): o hook transformou de "captura-only" para
 * "nucleo de decisao + captura mantida". Testes 1-2 agora configuram manifesto+estagio
 * para que a hook possa tomar decisao (success path). Testes 3-4 verificam que
 * payloads invalidos nao capturam e agora exitem 2 (fail-closed), nao 0.
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

function iniciarGit(raiz, branch) {
  spawnSync("git", ["init"], { cwd: raiz });
  spawnSync("git", ["config", "user.email", "<email>"], { cwd: raiz });
  spawnSync("git", ["config", "user.name", "Test"], { cwd: raiz });
  fs.writeFileSync(path.join(raiz, "README"), "test", "utf8");
  spawnSync("git", ["add", "."], { cwd: raiz });
  spawnSync("git", ["commit", "-m", "initial"], { cwd: raiz });
  spawnSync("git", ["checkout", "-b", branch], { cwd: raiz });
}

function criarEstado(raiz, branchBase, estagio) {
  const dirEstado = path.join(raiz, "docs", "rainforest", "estado");
  fs.mkdirSync(dirEstado, { recursive: true });

  const FECHADO = { design: "aprovado", plano: "ok" };
  const estado = { slug: `2026-09-01-${branchBase}` };
  const ordem = ["design", "plano", "executar", "revisar", "verificar", "fechar"];

  for (const e of ordem) {
    if (e === estagio) {
      estado[e] = { status: "pendente" };
    } else if (ordem.indexOf(e) < ordem.indexOf(estagio)) {
      estado[e] = { status: FECHADO[e] || "ok" };
    } else {
      estado[e] = { status: "pendente" };
    }
  }

  const estadoPath = path.join(dirEstado, `2026-09-01-${branchBase}.json`);
  fs.writeFileSync(estadoPath, JSON.stringify(estado, null, 2) + "\n", "utf8");
}

function criarManifesto(raiz, manifesto) {
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  const manifestoPath = path.join(dir, "agentes.json");
  fs.writeFileSync(manifestoPath, JSON.stringify(manifesto, null, 2) + "\n", "utf8");
}

// == 1. primeira execucao grava a amostra ==
console.log("== 1. primeira execucao grava a amostra ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstado(raiz, "teste", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: {
      leitor: { estagios: ["revisar"], escreve: false },
    },
  });

  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  const r = rodaHook(raiz, JSON.stringify({ session_id: "s1", tool_input: { subagent_type: "leitor" } }));
  caso("exit 0", r.status === 0, `exit=${r.status}`);
  caso("amostra.json existe", fs.existsSync(amostra));
  let lido = null;
  try { lido = JSON.parse(fs.readFileSync(amostra, "utf8")); } catch {}
  caso("amostra e JSON valido com session_id da 1a execucao",
    lido && lido.session_id === "s1", lido && lido.session_id ? `session_id=${lido.session_id}` : "ilegivel");
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 2. segunda execucao NAO sobrescreve (primeira captura vence, D7) ==
console.log("== 2. segunda execucao NAO sobrescreve ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstado(raiz, "teste", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: {
      leitor: { estagios: ["revisar"], escreve: false },
    },
  });

  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  rodaHook(raiz, JSON.stringify({ session_id: "s1", tool_input: { subagent_type: "leitor" } }));
  const r2 = rodaHook(raiz, JSON.stringify({ session_id: "s2", tool_input: { subagent_type: "leitor" } }));
  caso("exit 0 na segunda execucao", r2.status === 0, `exit=${r2.status}`);
  let lido = null;
  try { lido = JSON.parse(fs.readFileSync(amostra, "utf8")); } catch {}
  caso("amostra continua com session_id da PRIMEIRA execucao (s1)",
    lido && lido.session_id === "s1",
    lido && lido.session_id ? `veio ${lido.session_id}` : "amostra ilegivel");
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 3. stdin vazio nao vira amostra (agora exit 2: fail-closed) ==
console.log("== 3. stdin vazio nao vira amostra ==");
{
  const raiz = caixa();
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  const r = rodaHook(raiz, "");
  caso("exit 2 (fail-closed)", r.status === 2, `exit=${r.status}`);
  caso("amostra.json NAO existe", !fs.existsSync(amostra));
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 4. payload ilegivel nao vira amostra (agora exit 2: fail-closed) ==
console.log("== 4. payload ilegivel nao vira amostra ==");
{
  const raiz = caixa();
  const amostra = path.join(raiz, ".rainforest", "portaria", "amostra.json");
  const r = rodaHook(raiz, "{isso nao e json");
  caso("exit 2 (fail-closed)", r.status === 2, `exit=${r.status}`);
  caso("amostra.json NAO existe", !fs.existsSync(amostra));
  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou > 0 ? 1 : 0);
