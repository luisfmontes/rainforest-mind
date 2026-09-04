#!/usr/bin/env node
"use strict";
/* Bateria de diagnóstico da Tarefa 3 do fluxo 9 (portaria).
 *
 * Testa as mensagens de negação enriquecidas com diagnóstico:
 * (a) negação por manifesto ausente cita a raiz lida
 * (b) cita a branch atual
 * (c) com outro worktree do mesmo repo em fluxo aberto, cita slug e estágio dele
 * (d) sem outro worktree em fluxo aberto, não inventa nenhum
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

// `realpathSync` de propósito: no runner do CI o `os.tmpdir()` do Windows vem
// em forma curta 8.3 (o nome de usuário aparece truncado com `~1`), e a
// portaria imprime o caminho que o Node RESOLVE, por extenso — sem normalizar
// aqui, o `stderr.includes(raiz)` falhava só no CI (verde na máquina do dono,
// vermelho lá, 2026-09-04). Normalizar na origem vale para todos os casos.
function caixa() {
  return fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "portaria-diag-")));
}

function criarEstadoAtivo(raiz, branchBase, estagio) {
  const dirEstado = path.join(raiz, "docs", "rainforest", "estado");
  fs.mkdirSync(dirEstado, { recursive: true });

  const FECHADO = { design: "aprovado", plano: "ok" };
  const estado = {
    slug: `2026-09-01-${branchBase}`,
  };

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
  const path_ = path.join(dir, "agentes.json");
  fs.writeFileSync(path_, JSON.stringify(manifesto, null, 2) + "\n", "utf8");
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

function manifestoD2(agentes) {
  return {
    versao: 1,
    agentes: agentes,
  };
}

// == (a) Negação por manifesto ausente cita a raiz lida ==
console.log("== (a) negação manifesto ausente cita raiz lida ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/teste");
  criarEstadoAtivo(raiz, "teste", "revisar");
  // Não cria manifesto

  const payload = {
    session_id: "diag-a",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita raiz lida", r.stderr.includes(raiz), `stderr: ${r.stderr}`);
  caso("stderr inclui 'raiz lida:'", r.stderr.includes("raiz lida:"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (b) Negação cita a branch atual ==
console.log("== (b) negação cita branch atual ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/memoria");
  criarEstadoAtivo(raiz, "memoria", "revisar");
  // Não cria manifesto

  const payload = {
    session_id: "diag-b",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr cita branch fluxo/memoria", r.stderr.includes("fluxo/memoria"), `stderr: ${r.stderr}`);
  caso("stderr inclui 'branch:'", r.stderr.includes("branch:"), `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

// == (c) Com outro worktree em fluxo aberto, cita slug e estágio ==
console.log("== (c) outro worktree em fluxo aberto é mencionado ==");
{
  const raizPrincipal = caixa();
  const raizWorktree = caixa();

  // Setup: dois repositórios separados simulando dois worktrees
  // Vamos usar um truque: criar os dois em um mesmo repo

  // Cria um repo principal
  iniciarGit(raizPrincipal, "main");

  // Cria um "worktree" (na verdade um segundo repo, mas conseguimos o efeito)
  // Para simular melhor, vamos aproveitar que git worktree list funciona em um repo
  // Cria um worktree real
  const dirWorktrees = path.join(raizPrincipal, ".git", "worktrees");
  fs.mkdirSync(dirWorktrees, { recursive: true });

  // Na verdade, vamos fazer mais simples: colocamos ambos em um mesmo repo com git worktree add
  spawnSync("git", ["worktree", "add", raizWorktree, "-b", "fluxo/outro"], { cwd: raizPrincipal });

  // Cria estado no worktree
  criarEstadoAtivo(raizWorktree, "outro", "plano");

  // Cria estado no principal (fechado)
  criarEstadoAtivo(raizPrincipal, "principal", "fechar");

  // Não cria manifesto no principal (isso vai causar negação)
  // Mas cria em outro para que ele apareça na lista de "em fluxo aberto"

  const payload = {
    session_id: "diag-c",
    cwd: raizPrincipal,
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raizPrincipal, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  caso("stderr menciona fluxo aberto", r.stderr.includes("fluxo aberto"), `stderr: ${r.stderr}`);
  caso("stderr cita 'slug'", r.stderr.includes("slug"), `stderr: ${r.stderr}`);
  // O outro worktree foi criado com estágio "plano" aberto — a mensagem tem
  // de citar esse estágio real (lido do lado do outro worktree), nunca "?"
  // (que seria o efeito do bug: ler o estado do worktree atual, onde o
  // arquivo daquele slug não existe).
  caso("stderr cita 'estágio: plano' (estágio real do outro worktree)", r.stderr.includes("estágio: plano"), `stderr: ${r.stderr}`);
  caso("stderr não cita 'estágio: ?' (não devolve '?' para o outro worktree)", !r.stderr.includes("estágio: ?"), `stderr: ${r.stderr}`);

  // Limpeza
  try {
    spawnSync("git", ["worktree", "remove", raizWorktree], { cwd: raizPrincipal });
  } catch {}
  fs.rmSync(raizPrincipal, { recursive: true, force: true });
  if (fs.existsSync(raizWorktree)) {
    fs.rmSync(raizWorktree, { recursive: true, force: true });
  }
}

// == (d) Sem outro worktree em fluxo aberto, não menciona slug ==
console.log("== (d) sem fluxo aberto, nao menciona slug ==");
{
  const raiz = caixa();

  iniciarGit(raiz, "fluxo/isolado");
  criarEstadoAtivo(raiz, "isolado", "revisar");
  // Não cria manifesto e não cria nenhum outro worktree

  const payload = {
    session_id: "diag-d",
    tool_input: { subagent_type: "revisor" },
  };

  const r = rodaHook(raiz, JSON.stringify(payload));

  caso("exit 2", r.status === 2, `exit=${r.status}`);
  // A palavra "slug" não deve aparecer quando não há outros worktrees
  const temSlugAcidentralmente = r.stderr.includes("slug") && r.stderr.includes("outros worktrees");
  caso("stderr não menciona 'slug' (sem outros worktrees)", !temSlugAcidentralmente, `stderr: ${r.stderr}`);

  fs.rmSync(raiz, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);

if (falhou > 0) {
  process.exit(1);
} else {
  console.log("todos os casos: OK");
  process.exit(0);
}
