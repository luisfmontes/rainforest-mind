#!/usr/bin/env node
"use strict";
/* Bateria da regra de folha na portaria (D4, D5, D6 do design
 * 2026-09-24-revisor-folha.md, Tarefas 2 e 3 do plano homonimo).
 *
 * O que ela protege: `agent_id` no payload do `PreToolUse` so aparece quando
 * a chamada de `Agent` sai de DENTRO de outro subagente (confirmado ao vivo
 * na tarefa 1, `docs/rainforest/pesquisas/2026-09-24-revisor-folha-payload.md`)
 * — a portaria nega esse despacho, porque agente despachado e FOLHA e nao
 * despacha agente (regra 10). O payload da JANELA (sem `agent_id`) tem de
 * seguir exatamente como hoje, e o toggle `agente-folha` tem de desligar a
 * regra por projeto sem release nova (mesma forma do `contrato-veredito`).
 *
 * Usa os payloads REAIS capturados na tarefa 1 (`hooks/fixtures/
 * portaria-folha/*.json`), ajustando so `cwd` para apontar para a caixa de
 * areia — nenhuma chave nova e inventada.
 *
 * Roda o hook como PROCESSO REAL, com payload no stdin — igual as baterias
 * vizinhas (`hooks/testa-portaria-manifesto.cjs` e companhia). Importar a
 * funcao e chamar direto provaria a funcao, nao o caminho que o harness
 * exercita.
 *
 * Isolamento (regra 15): cada caso cria um repositorio git PROPRIO num
 * `mkdtemp`, com `CLAUDE_PROJECT_DIR` e `RFM_ROOT` apontando para dentro
 * dele — nunca escreve no repo deste plugin nem em `~/.rainforest` real.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "portaria.cjs");
const FIXTURE_SUBAGENTE = path.join(__dirname, "fixtures", "portaria-folha", "payload-de-subagente.json");
const FIXTURE_JANELA = path.join(__dirname, "fixtures", "portaria-folha", "payload-da-janela.json");

let ok = 0;
let falhou = 0;

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 500)}` : ""}`);
  }
}

function caixa() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "portaria-folha-"));
}

function iniciarGit(raiz) {
  spawnSync("git", ["init"], { cwd: raiz });
  spawnSync("git", ["config", "user.email", "<email>"], { cwd: raiz });
  spawnSync("git", ["config", "user.name", "Test"], { cwd: raiz });
  fs.writeFileSync(path.join(raiz, "README"), "test", "utf8");
  spawnSync("git", ["add", "."], { cwd: raiz });
  spawnSync("git", ["commit", "-m", "initial"], { cwd: raiz });
}

function lerLog(dadosDir) {
  const p = path.join(dadosDir, "portaria", "despachos.jsonl");
  if (!fs.existsSync(p)) return [];
  return fs
    .readFileSync(p, "utf8")
    .split("\n")
    .filter((l) => l.trim() !== "")
    .map((l) => JSON.parse(l));
}

// So `cwd` e ajustado, para a caixa resolver como raiz do projeto (a mesma
// precedencia de `raizDoProjeto()`: `payload.cwd` primeiro). Nenhuma outra
// chave do payload real e tocada.
function despacharFixture(fixturePath, repo, trocas) {
  const payload = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  payload.cwd = repo;
  Object.assign(payload, trocas || {});
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload),
    encoding: "utf8",
    env: {
      ...process.env,
      CLAUDE_PROJECT_DIR: repo,
      RFM_ROOT: path.join(repo, ".dados-do-teste"),
    },
  });
}

// == 1. payload de subagente (agent_id presente) e negado ==
console.log("== payload de subagente (agent_id presente) e negado ==");
{
  const repo = caixa();
  iniciarGit(repo);

  const r = despacharFixture(FIXTURE_SUBAGENTE, repo);

  caso("payload de subagente (agent_id presente) e negado: exit 2",
    r.status === 2, `exit=${r.status} stderr=${r.stderr}`);
  caso("payload de subagente (agent_id presente) e negado: mensagem cita o agent_type 'despachante'",
    /despachante/.test(r.stderr || ""), r.stderr);
  caso("payload de subagente (agent_id presente) e negado: mensagem cita 'folha'",
    /folha/i.test(r.stderr || ""), r.stderr);

  const log = lerLog(path.join(repo, ".dados-do-teste"));
  const ultima = log.length > 0 ? log[log.length - 1] : null;
  caso("payload de subagente (agent_id presente) e negado: linha deny no log da caixa",
    ultima && ultima.decisao === "deny", JSON.stringify(ultima));

  fs.rmSync(repo, { recursive: true, force: true });
}

// == 2. payload da janela (sem agent_id) segue o caminho de hoje ==
console.log("== payload da janela (sem agent_id) segue o caminho de hoje ==");
{
  const repo = caixa();
  iniciarGit(repo);

  const r = despacharFixture(FIXTURE_JANELA, repo);

  // "Caminho de hoje" para este subagent_type (nao declarado no manifesto):
  // exit 0, sem passar pela regra de folha — confirmado por medicao direta
  // do hook ANTES desta tarefa mexer nele (baseline).
  caso("payload da janela (sem agent_id) segue o caminho de hoje: exit 0, igual ao baseline",
    r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  caso("payload da janela (sem agent_id) segue o caminho de hoje: nao negado pela regra de folha",
    !/folha/i.test(r.stderr || ""), r.stderr);

  fs.rmSync(repo, { recursive: true, force: true });
}

// == 1b. agent_id presente mas falsy ("", 0, false, null) tambem e negado ==
// Achado da revisao de 2026-09-24: a condicao por truthiness deixava passar
// `agent_id: ""`. A chave so existe dentro de subagente (pesquisa da tarefa 1),
// entao PRESENCA basta para negar — valor estranho e duvida, e duvida fecha.
console.log("== agent_id presente mas falsy tambem e negado ==");
for (const valor of ["", 0, false, null]) {
  const repo = caixa();
  iniciarGit(repo);
  const r = despacharFixture(FIXTURE_SUBAGENTE, repo, { agent_id: valor });
  caso(`agent_id presente mas falsy (${JSON.stringify(valor)}) e negado pela regra de folha`,
    r.status === 2 && /folha/i.test(r.stderr || ""), `exit=${r.status} stderr=${r.stderr}`);
  fs.rmSync(repo, { recursive: true, force: true });
}

// == 3. agente-folha desligado no .rainforest/config.json do projeto libera o payload de subagente ==
console.log("== agente-folha desligado no .rainforest/config.json do projeto libera o payload de subagente ==");
{
  const repo = caixa();
  iniciarGit(repo);
  fs.mkdirSync(path.join(repo, ".rainforest"), { recursive: true });
  fs.writeFileSync(
    path.join(repo, ".rainforest", "config.json"),
    JSON.stringify({ "agente-folha": false }, null, 2) + "\n",
    "utf8"
  );

  const r = despacharFixture(FIXTURE_SUBAGENTE, repo);

  caso("agente-folha desligado no .rainforest/config.json do projeto libera o payload de subagente: nao negado pela regra de folha",
    !/folha/i.test(r.stderr || ""), r.stderr);
  caso("agente-folha desligado no .rainforest/config.json do projeto libera o payload de subagente: exit 0",
    r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

  fs.rmSync(repo, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
if (falhou === 0) console.log("todos os casos: OK");
process.exit(falhou > 0 ? 1 : 0);
