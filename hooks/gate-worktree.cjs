#!/usr/bin/env node
/**
 * PreToolUse — barra subagente que escreve fora de worktree isolado.
 *
 * O P2 do relatorio de 2026-08-08
 * (relatorios/2026-08-08-executor-reincidencia-isolamento.md):
 *
 *   "Enquanto o veredito de uma checagem for redigido pelo mesmo agente que
 *    ela deveria travar, ela nao trava nada. Exit code nao se argumenta."
 *
 * Naquele dia a regra 20-26 do executor.md estava escrita, sem ambiguidade, no
 * system prompt do agente E repetida no briefing. Ele rodou a verificacao,
 * recebeu o diretorio principal — a condicao de parada —, transcreveu a
 * condicao corretamente e escreveu um OK do lado. Texto nao alcanca esse modo
 * de falha, porque o texto ja estava la e foi lido.
 *
 * Isto e a mesma regra, com exit 2 no lugar do pedido.
 *
 * Por que da pra fazer: hooks rodam DENTRO do subagente. Da doc oficial —
 * "When a subagent calls a tool, tool events such as PreToolUse and PostToolUse
 * fire the same configured hooks as in the main conversation, and the input
 * carries the agent_id and agent_type". Entao nao e preciso interceptar o
 * despacho do Task: intercepta-se a escrita, ja sabendo quem esta escrevendo.
 *
 * ESCOPO, de proposito estreito:
 *   - so age quando ha `agent_id` — a janela principal nunca e barrada;
 *   - escrita de arquivo (Write/Edit/MultiEdit/NotebookEdit) para dentro de
 *     repo git que NAO e worktree linkado;
 *   - Bash: so a lista curta de comandos que mexem no estado do repo
 *     (stash, checkout, switch, reset, merge, rebase, commit, clean) — foi
 *     `git stash`/`pop` que moveu o HEAD do Luis na falha N1. Leitura passa.
 *   - fora de repo git (scratchpad, temp) passa sempre.
 *
 * Saidas de emergencia, as duas nomeadas na mensagem de bloqueio:
 *   - env RAINFOREST_GATE_OFF=1  → desliga na sessao inteira;
 *   - arquivo .rainforest-gate-off na raiz do repo → desliga naquele repo.
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const FERRAMENTAS_DE_ESCRITA = new Set(["Write", "Edit", "MultiEdit", "NotebookEdit"]);
// Subcomandos de git que mexem no estado do checkout. `git stash`/`pop` foi a falha N1.
const GIT_QUE_MEXE = /\bgit\b[^\n;&|]*?\b(stash|checkout|switch|reset|merge|rebase|commit|clean|cherry-pick|revert)\b/;

function git(dir, args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

/**
 * null = nao e repo git (livre) | {toplevel, ehWorktree}
 *
 * Quando o git nao responde, o gate LIBERA — trava de seguranca nao pode
 * derrubar o trabalho por ambiente quebrado. Mas libera FALANDO: em
 * 2026-08-09 a bateria passou verde por engano porque o teste mandava
 * caminho `/tmp/...` do Git Bash, que o Node no Windows nao resolve; o git
 * falhava, o gate liberava calado e parecia funcionar. Trava que falha em
 * silencio e o mesmo defeito que ela existe pra consertar.
 */
function estadoDoRepo(dir) {
  const gitDir = git(dir, ["rev-parse", "--git-dir"]);
  if (gitDir === null) {
    if (git(dir, ["--version"]) === null && git(process.cwd(), ["--version"]) === null) {
      process.stderr.write(
        `[gate-worktree] git nao respondeu para '${dir}' — gate INATIVO nesta chamada.\n`
      );
    }
    return null;
  }
  return {
    toplevel: git(dir, ["rev-parse", "--show-toplevel"]) || dir,
    ehWorktree: gitDir.replace(/\\/g, "/").includes("/worktrees/"),
  };
}

function dirDe(alvo) {
  try {
    return fs.existsSync(alvo) && fs.statSync(alvo).isDirectory() ? alvo : path.dirname(alvo);
  } catch {
    return path.dirname(alvo);
  }
}

function bloqueia(motivo, toplevel, agente) {
  process.stderr.write(
    `BLOQUEADO pelo gate de worktree do rainforest-mind.\n\n` +
    `${motivo}\n` +
    `Repo: ${toplevel}\n` +
    `Agente: ${agente}\n\n` +
    `Este e o diretorio de trabalho do Luis, nao um worktree isolado. A regra 11 manda\n` +
    `subagente que edita arquivos trabalhar em worktree proprio, para o trabalho poder ser\n` +
    `descartado sem tocar no estado dele. Em 2026-08-08 um agente escreveu aqui duas vezes,\n` +
    `trocou a branch do Luis e moveu o HEAD dele com stash/pop.\n\n` +
    `PARE e reporte isto para a janela principal — nao contorne, nao escreva em outro lugar\n` +
    `"por enquanto". Quem decide seguir sem isolamento e a janela principal, e tem duas saidas:\n` +
    `  - RAINFOREST_GATE_OFF=1 no ambiente da sessao (desliga na sessao inteira);\n` +
    `  - arquivo .rainforest-gate-off na raiz do repo (desliga so naquele repo).\n`
  );
  process.exit(2);
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0); // payload ilegivel nunca trava o trabalho do Luis
  }

  // A janela principal e livre: o gate existe para quem foi despachado.
  if (!ev.agent_id) process.exit(0);
  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  const entrada = ev.tool_input || {};
  const nome = ev.tool_name;
  let alvo = null;
  let motivo = null;

  if (FERRAMENTAS_DE_ESCRITA.has(nome)) {
    alvo = entrada.file_path || entrada.notebook_path || null;
    motivo = `Escrita (${nome}) em ${alvo}`;
  } else if (nome === "Bash" && typeof entrada.command === "string") {
    const m = entrada.command.match(GIT_QUE_MEXE);
    if (!m) process.exit(0);
    alvo = ev.cwd || process.cwd();
    motivo = `Comando que mexe no estado do repo: git ${m[1]}`;
  }

  if (!alvo) process.exit(0);

  const estado = estadoDoRepo(dirDe(alvo));
  if (!estado) process.exit(0);          // fora de repo git: livre
  if (estado.ehWorktree) process.exit(0); // worktree linkado: era pra ser isso mesmo

  if (fs.existsSync(path.join(estado.toplevel, ".rainforest-gate-off"))) process.exit(0);

  bloqueia(motivo, estado.toplevel, `${ev.agent_type || "?"} (${ev.agent_id})`);
}

main();
