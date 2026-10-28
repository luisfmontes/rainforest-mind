#!/usr/bin/env node
"use strict";
/* Bateria da portaria com o cwd da sessao fora de repo git (Issue #565, D1 e D4 do
 * design docs/rainforest/design/2026-10-21-portaria-aviso-bash.md).
 *
 * O que ela protege: fora de repo, o harness recusa `isolation: "worktree"`, e o agente
 * que escreve so passa quando o briefing traz `Worktree: <caminho absoluto>` de um
 * worktree LINKADO, conferido pela portaria. Qualquer outra forma continua negada, e com
 * o cwd dentro de repo nada muda.
 *
 * Cada caso roda o `portaria.cjs` como PROCESSO REAL, com o payload que o harness manda
 * no PreToolUse de `Agent`. O fluxo e aberto pelo `scripts/estado.cjs` real. Isolamento
 * (regra 15): repositorios git reais num mkdtemp, `RFM_ROOT` dentro dele, apagado ao fim.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "portaria.cjs");
const ESTADO = path.join(__dirname, "..", "scripts", "estado.cjs");
const SLUG = "2026-10-21-teste";
const TIMEOUT_MS = 60000;

let ok = 0;
let falhou = 0;

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok    ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 600)}` : ""}`);
  }
}

function git(cwd, args) {
  const r = spawnSync("git", args, { cwd, encoding: "utf8", timeout: TIMEOUT_MS });
  if (r.status !== 0) throw new Error(`git ${args.join(" ")} falhou: ${r.stderr}`);
  return r.stdout;
}

const sbx = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "portaria-fora-")));
const main = path.join(sbx, "main");
const dados = path.join(sbx, "dados");
const fora = path.join(sbx, "fora");
for (const d of [main, dados, fora]) fs.mkdirSync(d);
git(main, ["init", "-q"]);
git(main, ["symbolic-ref", "HEAD", "refs/heads/main"]);
git(main, ["config", "user.email", "t@t"]);
git(main, ["config", "user.name", "Test"]);
fs.writeFileSync(path.join(main, "README"), "test\n", "utf8");
git(main, ["add", "."]);
git(main, ["commit", "-q", "-m", "initial"]);
const wt = path.join(sbx, "wt");
git(main, ["worktree", "add", "-q", "-b", "fluxo/teste", wt]);
fs.mkdirSync(path.join(wt, "docs", "rainforest", "estado"), { recursive: true });
fs.mkdirSync(path.join(wt, "sub"));

function ambiente(cwd, estadoRoot) {
  const env = { ...process.env, CLAUDE_PROJECT_DIR: cwd, RFM_ROOT: dados };
  if (estadoRoot) env.RFM_ESTADO_ROOT = estadoRoot;
  else delete env.RFM_ESTADO_ROOT;
  delete env.RAINFOREST_GATE_OFF;
  return env;
}

function estado(args) {
  return spawnSync(process.execPath, [ESTADO, ...args], {
    cwd: wt, encoding: "utf8", env: ambiente(wt, wt), timeout: TIMEOUT_MS,
  });
}

function despachar(cwd, prompt, opcoes = {}) {
  const toolInput = { subagent_type: opcoes.agente || "rainforest-mind:executor", prompt };
  if (opcoes.isolation) toolInput.isolation = opcoes.isolation;
  if (opcoes.name) toolInput.name = opcoes.name;
  const payload = { session_id: "sessao-fora", cwd, hook_event_name: "PreToolUse", tool_name: "Agent", tool_input: toolInput };
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload), encoding: "utf8", env: ambiente(cwd, null), timeout: TIMEOUT_MS,
  });
}

const barras = (p) => p.split(path.sep).join("/");
const briefing = (dir) => `Tarefa de teste.\nWorktree: ${dir}\nCritério: nenhum.`;

console.log("== preparo ==");
caso("P0 a pasta 'fora' nao esta em repo git",
  spawnSync("git", ["-C", fora, "rev-parse", "--git-dir"], { encoding: "utf8" }).status !== 0);
for (const [a, b] of [["iniciar", ["--slug", SLUG, "--titulo", "teste"]], ["marcar", ["--slug", SLUG, "--estagio", "design", "--status", "aprovado"]], ["marcar", ["--slug", SLUG, "--estagio", "plano", "--status", "ok"]]]) {
  const r = estado([a, ...b]);
  caso(`P1 estado.cjs ${a} ${b[3] || ""} grava o fluxo real`, r.status === 0, `exit=${r.status} ${r.stdout} ${r.stderr}`);
}

console.log("== A. fora de repo, worktree linkado declarado ==");
{
  const r = despachar(fora, briefing(barras(wt)));
  caso("A1 executor sem isolation, Worktree: linkado com fluxo em executar: exit 0",
    r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  const r2 = despachar(fora, briefing(wt));
  caso("A2 o mesmo com contrabarras do Windows: exit 0", r2.status === 0, `exit=${r2.status} stderr=${r2.stderr}`);
  const r3 = despachar(fora, briefing(barras(wt)), { agente: "rainforest-mind:arqueologo" });
  caso("A3 o estagio continua valendo pela raiz do worktree: arqueologo (so design) sai 2",
    r3.status === 2 && /executar/.test(r3.stderr || ""), `exit=${r3.status} stderr=${r3.stderr}`);
}

console.log("== B. contornos que continuam negados ==");
{
  const semLinha = despachar(fora, "Tarefa de teste sem a linha.");
  caso("B1 fora de repo sem Worktree:: sai 2 pela regra 11",
    semLinha.status === 2 && /regra 11/.test(semLinha.stderr || ""), `exit=${semLinha.status} stderr=${semLinha.stderr}`);
  caso("B1 a negacao fora de repo aponta a saida (linha Worktree:, #565)",
    /Worktree: <caminho absoluto>/.test(semLinha.stderr || ""), semLinha.stderr);
  const principal = despachar(fora, briefing(barras(main)));
  caso("B2 Worktree: apontando o checkout principal (nao linkado): sai 2",
    principal.status === 2 && /regra 11/.test(principal.stderr || ""), `exit=${principal.status} stderr=${principal.stderr}`);
  const sub = despachar(fora, briefing(barras(path.join(wt, "sub"))));
  caso("B3 Worktree: apontando um subdiretorio do worktree: sai 2",
    sub.status === 2 && /regra 11/.test(sub.stderr || ""), `exit=${sub.status} stderr=${sub.stderr}`);
  const inexistente = despachar(fora, briefing(barras(path.join(sbx, "nao-existe"))));
  caso("B4 Worktree: apontando pasta que nao existe: sai 2",
    inexistente.status === 2 && /regra 11/.test(inexistente.stderr || ""), `exit=${inexistente.status} stderr=${inexistente.stderr}`);
  const relativo = despachar(fora, "Tarefa.\nWorktree: wt\n");
  caso("B5 Worktree: com caminho relativo: sai 2", relativo.status === 2 && /regra 11/.test(relativo.stderr || ""), `exit=${relativo.status} stderr=${relativo.stderr}`);
  const emProsa = despachar(fora, `Use o worktree. Worktree: ${barras(wt)} no meio da frase.`);
  caso("B6 Worktree: no meio da frase, nao em linha isolada: sai 2",
    emProsa.status === 2 && /regra 11/.test(emProsa.stderr || ""), `exit=${emProsa.status} stderr=${emProsa.stderr}`);
  const nomeado = despachar(fora, briefing(barras(wt)), { name: "ajudante" });
  caso("B7 Worktree: valido mas agente nomeado: sai 2 pela regra 10",
    nomeado.status === 2 && /nunca e nomeado/.test(nomeado.stderr || ""), `exit=${nomeado.status} stderr=${nomeado.stderr}`);
}

console.log("== C. cwd dentro de repo: nada muda ==");
{
  const dentro = despachar(wt, briefing(barras(wt)));
  caso("C1 cwd no worktree, sem isolation, mesmo com Worktree:: sai 2 pela regra 11",
    dentro.status === 2 && /regra 11/.test(dentro.stderr || ""), `exit=${dentro.status} stderr=${dentro.stderr}`);
  caso("C1 dentro de repo a negacao nao oferece a linha Worktree:",
    !/Worktree: <caminho absoluto>/.test(dentro.stderr || ""), dentro.stderr);
  const comIsolation = despachar(wt, "Tarefa.", { isolation: "worktree" });
  caso("C2 cwd no worktree com isolation e fluxo em executar: exit 0",
    comIsolation.status === 0, `exit=${comIsolation.status} stderr=${comIsolation.stderr}`);
}

console.log("== D. branch de tarefa fluxo/<slug>-t<n> fora de repo (#613, #610) ==");
{
  // Cada tarefa paralela ganha worktree próprio, na branch `fluxo/<slug sem a data>-t<n>`.
  // O estado é copiado para o worktree: resolver lê `docs/rainforest/estado` do cwd declarado.
  const estadoDoFluxo = path.join(wt, "docs", "rainforest", "estado", `${SLUG}.json`);
  const comEstado = (dir) => {
    fs.mkdirSync(path.join(dir, "docs", "rainforest", "estado"), { recursive: true });
    fs.copyFileSync(estadoDoFluxo, path.join(dir, "docs", "rainforest", "estado", `${SLUG}.json`));
  };
  const wtT1 = path.join(sbx, "wt-tarefa1");
  git(main, ["worktree", "add", "-q", "-b", "fluxo/teste-t1", wtT1]);
  comEstado(wtT1);
  const t1 = despachar(fora, briefing(barras(wtT1)));
  caso("D1 fora de repo, worktree em fluxo/teste-t1 com fluxo em executar: exit 0",
    t1.status === 0, `exit=${t1.status} stderr=${t1.stderr}`);
  const wtOutro = path.join(sbx, "wt-outro");
  git(main, ["worktree", "add", "-q", "-b", "fluxo/outro-t1", wtOutro]);
  comEstado(wtOutro);
  const outro = despachar(fora, briefing(barras(wtOutro)));
  caso("D2 fora de repo, worktree em fluxo/outro-t1 (fluxo que nao existe): exit 2",
    outro.status === 2, `exit=${outro.status} stderr=${outro.stderr}`);
  caso("D2 a negacao cita a forma fluxo/<slug sem a data>-t<n> (#613)",
    (outro.stderr || "").includes("fluxo/<slug sem a data>-t<n>"), outro.stderr);
  caso("D2 a negacao cita o fluxo esperado como fluxo/teste-t<n>",
    (outro.stderr || "").includes("fluxo/teste-t<n>"), outro.stderr);
}

fs.rmSync(sbx, { recursive: true, force: true });
console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou === 0 ? 0 : 1);
