#!/usr/bin/env node
"use strict";
/* Bateria do núcleo da Tarefa 3 do fluxo 9 (portaria).
 *
 * Testa decisões 1–7 de D3: manifesto ausente/inválido, agente não declarado,
 * estágio fora da lista, ausência de estágio ativo, normalização de prefixo,
 * e aprovação com gravação de log.
 *
 * Chama o hook como PROCESSO REAL via spawnSync, assere sobre exit code,
 * stderr e conteúdo de arquivo. Sandbox com git init + estado.
 *
 * Exit 0 = tudo passou; exit 1+ = alguma falha.
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
  return fs.mkdtempSync(path.join(os.tmpdir(), "portaria-nucleo-"));
}

function criarEstadoAtivo(raiz, branchBase, estagio) {
  // Cria docs/rainforest/estado/<data>-<branchBase>.json com estágio aberto
  // O resolver() casa branch 'fluxo/teste' com arquivo cujo slug pós-data seja 'teste'
  const dirEstado = path.join(raiz, "docs", "rainforest", "estado");
  fs.mkdirSync(dirEstado, { recursive: true });

  // Mapa de status fechado por estágio (copiado de estagio-ativo.cjs)
  const FECHADO = { design: "aprovado", plano: "ok" };

  const estado = {
    slug: `2026-09-01-${branchBase}`,
  };

  // Cria toda a cascata de estágios, fechando os que vêm antes do desejado
  const ordem = ["design", "plano", "executar", "revisar", "verificar", "fechar"];

  for (const e of ordem) {
    if (e === estagio) {
      // Estágio ativo = pendente
      estado[e] = { status: "pendente" };
    } else if (ordem.indexOf(e) < ordem.indexOf(estagio)) {
      // Estágio antes do desejado = fechado
      estado[e] = { status: FECHADO[e] || "ok" };
    } else {
      // Estágio depois do desejado = pendente
      estado[e] = { status: "pendente" };
    }
  }

  const estadoPath = path.join(dirEstado, `2026-09-01-${branchBase}.json`);
  fs.writeFileSync(estadoPath, JSON.stringify(estado, null, 2) + "\n", "utf8");
}

function criarManifesto(raiz, manifesto) {
  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  const path_ = path.join(dir, "agentes.json");
  fs.writeFileSync(path_, JSON.stringify(manifesto, null, 2) + "\n", "utf8");
}

function iniciarGit(raiz, branch) {
  // Inicializa git com pelo menos um commit para que HEAD exista
  spawnSync("git", ["init"], { cwd: raiz });
  spawnSync("git", ["config", "user.email", "<email>"], { cwd: raiz });
  spawnSync("git", ["config", "user.name", "Test"], { cwd: raiz });
  fs.writeFileSync(path.join(raiz, "README"), "test", "utf8");
  spawnSync("git", ["add", "."], { cwd: raiz });
  spawnSync("git", ["commit", "-m", "initial"], { cwd: raiz });
  spawnSync("git", ["checkout", "-b", branch], { cwd: raiz });
}

// == 1. Agente não declarado → exit 2, nome no stderr ==
console.log("== 1. agente nao declarado ==");
{
  const raiz = caixa();

  // Setup: inicializa git e cria estado
  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  // Manifesto sem o agente 'executar'
  criarManifesto(raiz, {
    revisor: { estagios: ["revisar"], escreve: false },
  });

  const payload = {
    session_id: "teste-1",
    tool_input: { subagent_type: "executar" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita o agente", r.stderr.includes("executar"), `stderr: ${r.stderr}`);
  caso(
    "stderr menciona manifesto",
    r.stderr.includes("manifesto"),
    `stderr: ${r.stderr}`
  );

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 2. Agente declarado, estágio errado → exit 2, estágios no stderr ==
console.log("== 2. agente declarado, estagio errado ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "executar"); // Stage ativo = executar

  criarManifesto(raiz, {
    revisor: { estagios: ["revisar", "verificar"], escreve: false }, // Só revisar/verificar permitido
  });

  const payload = {
    session_id: "teste-2",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita estágio atual", r.stderr.includes("executar"), `stderr: ${r.stderr}`);
  caso("stderr cita estágios permitidos", r.stderr.includes("revisar"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 3. Agente declarado, estágio certo → exit 0 + log ==
console.log("== 3. agente declarado, estagio certo ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  criarManifesto(raiz, {
    revisor: { estagios: ["revisar"], escreve: false },
  });

  const sessaoId = "teste-3-sessao-xyz";
  const payload = {
    session_id: sessaoId,
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 0", r.status === 0, `exit=${r.status}`);

  const logPath = path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
  const logExists = fs.existsSync(logPath);
  caso("despachos.jsonl existe", logExists);

  if (logExists) {
    const linhas = fs
      .readFileSync(logPath, "utf8")
      .trim()
      .split("\n");

    const ultima = linhas[linhas.length - 1];
    let entrada = null;
    try {
      entrada = JSON.parse(ultima);
    } catch {}

    caso("linha é JSON válido", entrada !== null, ultima);
    if (entrada) {
      caso("decisao = 'allow'", entrada.decisao === "allow", entrada.decisao);
      caso("agente = 'revisor'", entrada.agente === "revisor", entrada.agente);
      caso("estagio = 'revisar'", entrada.estagio === "revisar", entrada.estagio);
      caso("sessao correto", entrada.sessao === sessaoId, entrada.sessao);
      caso("ts em ISO-8601", /^\d{4}-\d{2}-\d{2}T/.test(entrada.ts), entrada.ts);
      caso("sem motivo em 'allow'", !entrada.motivo);
    }
  }

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 4. Manifesto ausente → exit 2 (fail-closed) ==
console.log("== 4. manifesto ausente ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  // Não cria manifesto

  const payload = {
    session_id: "teste-4",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr não vazio", r.stderr.length > 0, `"${r.stderr}"`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 5. Manifesto JSON inválido → exit 2 (fail-closed) ==
console.log("== 5. manifesto JSON invalido ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  const dir = path.join(raiz, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "agentes.json"), "{isso nao e json", "utf8");

  const payload = {
    session_id: "teste-5",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr não vazio", r.stderr.length > 0, `"${r.stderr}"`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 6. Normalização de prefixo rainforest-mind: ==
console.log("== 6. normalizacao de prefixo ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  criarManifesto(raiz, {
    revisor: { estagios: ["revisar"], escreve: false },
  });

  const payload = {
    session_id: "teste-6",
    tool_input: { subagent_type: "rainforest-mind:revisor" }, // Com prefixo
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 0 (prefixo foi removido)", r.status === 0, `exit=${r.status}`);

  const logPath = path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
  if (fs.existsSync(logPath)) {
    const linha = fs.readFileSync(logPath, "utf8").trim();
    let entrada = null;
    try {
      entrada = JSON.parse(linha);
    } catch {}
    caso("agente no log é 'revisor' (sem prefixo)", entrada && entrada.agente === "revisor", entrada && entrada.agente);
  } else {
    caso("agente no log é 'revisor' (sem prefixo)", false, "log não criado");
  }

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 7. Sem estágio ativo → exit 2 ==
console.log("== 7. sem estagio ativo ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/outro"); // Branch = fluxo/outro
  criarEstadoAtivo(raiz, "teste", "revisar"); // Estado para fluxo-teste (não casa)

  criarManifesto(raiz, {
    revisor: { estagios: ["revisar"], escreve: false },
  });

  const payload = {
    session_id: "teste-7",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr contém 'estágio ativo'", r.stderr.includes("estágio ativo"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == 8. Log append-only (não reescreve) ==
console.log("== 8. log append-only ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");

  criarManifesto(raiz, {
    revisor: { estagios: ["revisar"], escreve: false },
  });

  const payload = {
    session_id: "teste-8",
    tool_input: { subagent_type: "revisor" },
  };

  // Primeira execução
  rodaHook(raiz, JSON.stringify(payload));

  // Segunda execução
  const r2 = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 0 na segunda execução", r2.status === 0, `exit=${r2.status}`);

  const logPath = path.join(raiz, ".rainforest", "portaria", "despachos.jsonl");
  if (fs.existsSync(logPath)) {
    const linhas = fs
      .readFileSync(logPath, "utf8")
      .trim()
      .split("\n")
      .filter(l => l.trim());

    caso("log tem duas linhas", linhas.length === 2, `tem ${linhas.length}`);

    let ambas = true;
    for (const linha of linhas) {
      try {
        JSON.parse(linha);
      } catch {
        ambas = false;
        break;
      }
    }
    caso("ambas as linhas são JSON válidas", ambas);
  } else {
    caso("log tem duas linhas", false, "log não criado");
  }

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);

if (falhou > 0) {
  process.exit(1);
} else {
  console.log("todos os casos: OK");
  process.exit(0);
}
