#!/usr/bin/env node
"use strict";
/**
 * Teste para AVISO 4: parser de tools em lista de bloco YAML.
 * Valida que tools em lista de bloco são parseadas corretamente.
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
  return fs.mkdtempSync(path.join(os.tmpdir(), "portaria-tools-"));
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

function criarAgente(raiz, nome, frontmatter) {
  const dir = path.join(raiz, "agents");
  fs.mkdirSync(dir, { recursive: true });
  const agentePath = path.join(dir, `${nome}.md`);
  fs.writeFileSync(agentePath, `---\n${frontmatter}\n---\n# ${nome}\n`, "utf8");
}

// == 1. tools em lista de bloco com Read/Grep/Glob → aprova ==
console.log("== 1. tools lista de bloco (Read/Grep/Glob) → aprova ==");
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
  criarAgente(raiz, "leitor", `tools:
  - Read
  - Grep`);

  const payload = {
    session_id: "s1",
    tool_input: { subagent_type: "leitor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));
  caso("exit 0 (aprovado)", r.status === 0, `exit=${r.status}`);
  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 2. tools em lista de bloco com Write (fora da allowlist) → nega ==
console.log("== 2. tools lista de bloco com Write → nega ==");
{
  const raiz = caixa();
  iniciarGit(raiz, "fluxo/teste");
  criarEstado(raiz, "teste", "revisar");
  criarManifesto(raiz, {
    versao: 1,
    agentes: {
      escritor: { estagios: ["revisar"], escreve: false },
    },
  });
  criarAgente(raiz, "escritor", `tools:
  - Read
  - Write`);

  const payload = {
    session_id: "s2",
    tool_input: { subagent_type: "escritor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));
  caso("exit 2 (negado)", r.status === 2, `exit=${r.status}`);
  caso("stderr menciona Write", r.stderr.includes("Write"), `stderr: ${r.stderr}`);
  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou > 0 ? 1 : 0);
