#!/usr/bin/env node
"use strict";
/* Bateria da barreira de fluxo pulado na portaria (Issue #430, D3, D4 e D5 do
 * design docs/rainforest/design/2026-10-08-fluxo-pulado-bloqueio.md; tarefa 3 do
 * plano homonimo).
 *
 * O que ela protege: agente que ESCREVE (`escreve: true` no manifesto) nao roda
 * fora do estagio que declara, salvo com `leve` na branch. Cada caso roda o hook
 * `portaria.cjs` como PROCESSO REAL, com o payload que o harness manda no stdin
 * do PreToolUse para `Agent` — `session_id`, `cwd`, `hook_event_name`,
 * `tool_name` e `tool_input` com `subagent_type`, `prompt` e `isolation`, nada a
 * mais. O estado do fluxo e gravado pelo `scripts/estado.cjs` real (`iniciar`,
 * `marcar`, `leve`), nunca escrito a mao.
 *
 * Isolamento (regra 15): cada caso cria repositorios git REAIS num mkdtemp,
 * com `RFM_ROOT` apontando para dentro dele, e apaga tudo ao final. Nenhum
 * caminho desta maquina entra aqui; o e-mail de `git config` e de teste.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha. Placar: ok, falhou, skipped (0).
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "portaria.cjs");
const ESTADO = path.join(__dirname, "..", "scripts", "estado.cjs");
const SLUG = "2026-10-08-teste";
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

// Repositorio com `main` como padrao e um commit inicial. Dados do rainforest
// num diretorio proprio do sandbox, para a config e o log nao tocarem a maquina.
function novoRepo() {
  const sbx = fs.mkdtempSync(path.join(os.tmpdir(), "fluxo-pulado-"));
  const main = path.join(sbx, "main");
  const dados = path.join(sbx, "dados");
  fs.mkdirSync(main);
  fs.mkdirSync(dados);
  git(main, ["init", "-q"]);
  git(main, ["symbolic-ref", "HEAD", "refs/heads/main"]);
  git(main, ["config", "user.email", "t@t"]);
  git(main, ["config", "user.name", "Test"]);
  fs.writeFileSync(path.join(main, "README"), "test\n", "utf8");
  git(main, ["add", "."]);
  git(main, ["commit", "-q", "-m", "initial"]);
  return { sbx, main, dados };
}

// Worktree na branch do fluxo. Trabalho do fluxo roda aqui (regra 11), e o
// `iniciar` do estado.cjs so recusa o checkout principal fora da padrao.
function comWorktree(repo) {
  const wt = path.join(repo.sbx, "wt");
  git(repo.main, ["worktree", "add", "-q", "-b", "fluxo/teste", wt]);
  fs.mkdirSync(path.join(wt, "docs", "rainforest", "estado"), { recursive: true });
  return wt;
}

function ambiente(repo, cwd) {
  const env = { ...process.env, CLAUDE_PROJECT_DIR: cwd, RFM_ROOT: repo.dados, RFM_ESTADO_ROOT: cwd };
  delete env.RAINFOREST_GATE_OFF;
  return env;
}

function estado(repo, cwd, args) {
  return spawnSync(process.execPath, [ESTADO, ...args], {
    cwd,
    encoding: "utf8",
    env: ambiente(repo, cwd),
    timeout: TIMEOUT_MS,
  });
}

function despachar(repo, cwd, subagente, opcoes = {}) {
  const toolInput = { subagent_type: subagente, prompt: "Tarefa de teste do fluxo pulado." };
  if (!opcoes.semIsolation) toolInput.isolation = "worktree";
  const payload = {
    session_id: "sessao-fluxo-pulado",
    cwd,
    hook_event_name: "PreToolUse",
    tool_name: "Agent",
    tool_input: toolInput,
  };
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload),
    encoding: "utf8",
    env: ambiente(repo, cwd),
    timeout: TIMEOUT_MS,
  });
}

function ultimaDecisao(repo) {
  const p = path.join(repo.dados, "portaria", "despachos.jsonl");
  if (!fs.existsSync(p)) return null;
  const linhas = fs.readFileSync(p, "utf8").split("\n").filter((l) => l.trim() !== "");
  return linhas.length ? JSON.parse(linhas[linhas.length - 1]) : null;
}

function descartar(repo) {
  fs.rmSync(repo.sbx, { recursive: true, force: true });
}

// == A. rainforest com trilho, sem fluxo e sem leve ==
console.log("== A. rainforest sem fluxo aberto e sem leve ==");
{
  const repo = novoRepo();
  const wt = comWorktree(repo);

  const r = despachar(repo, wt, "rainforest-mind:executor");
  caso("A1 executor (com prefixo) sem fluxo sai 2",
    r.status === 2, `exit=${r.status} stderr=${r.stderr}`);
  caso("A1 stderr nomeia o agente executor",
    /executor/.test(r.stderr || ""), r.stderr);
  caso("A1 stderr nomeia o estagio exigido (executar)",
    /exige executar/.test(r.stderr || ""), r.stderr);
  caso("A1 stderr traz a saida do caminho leve (estado.cjs leve --motivo)",
    /scripts[\\/]estado\.cjs leve --motivo/.test(r.stderr || ""), r.stderr);
  caso("A1 stderr traz a saida de abrir o fluxo",
    /brainstorm|estado\.cjs iniciar/.test(r.stderr || ""), r.stderr);
  caso("A1 a negacao entra no log como deny",
    ultimaDecisao(repo) && ultimaDecisao(repo).decisao === "deny", JSON.stringify(ultimaDecisao(repo)));

  const contorno = despachar(repo, wt, "executor");
  caso("A2 contorno: subagent_type sem prefixo (executor) tambem sai 2",
    contorno.status === 2, `exit=${contorno.status} stderr=${contorno.stderr}`);

  const revisor = despachar(repo, wt, "rainforest-mind:revisor");
  caso("A3 revisor (escreve: false) passa sem fluxo: exit 0",
    revisor.status === 0, `exit=${revisor.status} stderr=${revisor.stderr}`);
  caso("A3 o despacho que passa grava allow no log",
    ultimaDecisao(repo) && ultimaDecisao(repo).decisao === "allow", JSON.stringify(ultimaDecisao(repo)));

  const planejador = despachar(repo, wt, "rainforest-mind:planejador");
  caso("A4 planejador (escreve: false) passa sem fluxo: exit 0",
    planejador.status === 0, `exit=${planejador.status} stderr=${planejador.stderr}`);

  const naoDeclarado = despachar(repo, wt, "outro-plugin:agente-solto");
  caso("A5 agente nao declarado no manifesto passa sem fluxo: exit 0",
    naoDeclarado.status === 0, `exit=${naoDeclarado.status} stderr=${naoDeclarado.stderr}`);

  const semIsolation = despachar(repo, wt, "rainforest-mind:executor", { semIsolation: true });
  caso("A6 executor sem isolation sai pela regra 11, nao pela barreira de fluxo",
    semIsolation.status === 2 && /regra 11/.test(semIsolation.stderr || "") && !/exige executar/.test(semIsolation.stderr || ""),
    `exit=${semIsolation.status} stderr=${semIsolation.stderr}`);

  descartar(repo);
}

// == B. rainforest com fluxo aberto: o estagio aberto decide ==
console.log("== B. rainforest com fluxo aberto: o estagio aberto decide ==");
{
  const repo = novoRepo();
  const wt = comWorktree(repo);

  const ini = estado(repo, wt, ["iniciar", "--slug", SLUG, "--titulo", "teste"]);
  caso("B0 estado.cjs iniciar grava o fluxo real",
    ini.status === 0, `exit=${ini.status} stdout=${ini.stdout} stderr=${ini.stderr}`);

  const prox1 = estado(repo, wt, ["proximo", "--slug", SLUG]);
  caso("B0 estagio aberto apos iniciar e design",
    /design/.test(prox1.stdout || ""), `exit=${prox1.status} stdout=${prox1.stdout} stderr=${prox1.stderr}`);

  const exec1 = despachar(repo, wt, "rainforest-mind:executor");
  caso("B1 fluxo em design: executor sai 2",
    exec1.status === 2, `exit=${exec1.status} stderr=${exec1.stderr}`);
  caso("B1 fluxo em design: stderr diz o estagio aberto design",
    /estagio aberto: design/.test(exec1.stderr || ""), exec1.stderr);

  const arq1 = despachar(repo, wt, "rainforest-mind:arqueologo");
  caso("B2 fluxo em design: arqueologo (estagios: design) passa: exit 0",
    arq1.status === 0, `exit=${arq1.status} stderr=${arq1.stderr}`);

  const marcaDesign = estado(repo, wt, ["marcar", "--slug", SLUG, "--estagio", "design", "--status", "aprovado"]);
  caso("B3 marcar design aprovado grava pelo estado.cjs real",
    marcaDesign.status === 0, `exit=${marcaDesign.status} stdout=${marcaDesign.stdout} stderr=${marcaDesign.stderr}`);

  const prox2 = estado(repo, wt, ["proximo", "--slug", SLUG]);
  caso("B3 estagio aberto apos design aprovado e plano",
    /plano/.test(prox2.stdout || ""), `exit=${prox2.status} stdout=${prox2.stdout}`);

  const exec2 = despachar(repo, wt, "rainforest-mind:executor");
  caso("B4 fluxo em plano: executor sai 2",
    exec2.status === 2, `exit=${exec2.status} stderr=${exec2.stderr}`);

  const plan = despachar(repo, wt, "rainforest-mind:planejador");
  caso("B5 fluxo em plano: planejador (escreve: false) passa: exit 0",
    plan.status === 0, `exit=${plan.status} stderr=${plan.stderr}`);

  const marcaPlano = estado(repo, wt, ["marcar", "--slug", SLUG, "--estagio", "plano", "--status", "ok"]);
  caso("B6 marcar plano ok grava pelo estado.cjs real",
    marcaPlano.status === 0, `exit=${marcaPlano.status} stdout=${marcaPlano.stdout} stderr=${marcaPlano.stderr}`);

  const prox3 = estado(repo, wt, ["proximo", "--slug", SLUG]);
  caso("B6 estagio aberto apos plano ok e executar",
    /executar/.test(prox3.stdout || ""), `exit=${prox3.status} stdout=${prox3.stdout}`);

  const exec3 = despachar(repo, wt, "rainforest-mind:executor");
  caso("B7 fluxo em executar: executor passa: exit 0",
    exec3.status === 0, `exit=${exec3.status} stderr=${exec3.stderr}`);
  caso("B7 o despacho que passa grava allow no log",
    ultimaDecisao(repo) && ultimaDecisao(repo).decisao === "allow", JSON.stringify(ultimaDecisao(repo)));

  const arq2 = despachar(repo, wt, "rainforest-mind:arqueologo");
  caso("B8 fluxo em executar: arqueologo (estagios: design) sai 2",
    arq2.status === 2, `exit=${arq2.status} stderr=${arq2.stderr}`);

  descartar(repo);
}

// == C. leve gravado pelo estado.cjs real libera o executor sem fluxo ==
console.log("== C. leve na branch libera o executor sem fluxo ==");
{
  const repo = novoRepo();
  const wt = comWorktree(repo);

  const antes = despachar(repo, wt, "rainforest-mind:executor");
  caso("C0 sem leve, executor sem fluxo sai 2",
    antes.status === 2, `exit=${antes.status} stderr=${antes.stderr}`);

  const leve = estado(repo, wt, ["leve", "--motivo", "hotfix mecanico de teste"]);
  caso("C1 estado.cjs leve grava o registro",
    leve.status === 0, `exit=${leve.status} stdout=${leve.stdout} stderr=${leve.stderr}`);

  const depois = despachar(repo, wt, "rainforest-mind:executor");
  caso("C2 com leve na branch, executor sem fluxo passa: exit 0",
    depois.status === 0, `exit=${depois.status} stderr=${depois.stderr}`);
  caso("C2 o despacho que passa grava allow no log",
    ultimaDecisao(repo) && ultimaDecisao(repo).decisao === "allow", JSON.stringify(ultimaDecisao(repo)));

  descartar(repo);
}

// == D. chave aviso-fluxo desligada no projeto ==
console.log("== D. chave aviso-fluxo desligada no projeto ==");
{
  const repo = novoRepo();
  const wt = comWorktree(repo);

  const ligado = despachar(repo, wt, "rainforest-mind:executor");
  caso("D0 com a chave ligada (padrao), executor sem fluxo sai 2",
    ligado.status === 2, `exit=${ligado.status} stderr=${ligado.stderr}`);

  // A config do projeto mora na raiz PRINCIPAL (raizDoPrincipal em hooks/lib/config.cjs),
  // compartilhada pelos worktrees: a chave vai no checkout principal, nao no worktree.
  fs.mkdirSync(path.join(repo.main, ".rainforest"), { recursive: true });
  fs.writeFileSync(path.join(repo.main, ".rainforest", "config.json"), JSON.stringify({ "aviso-fluxo": false }) + "\n", "utf8");

  const desligado = despachar(repo, wt, "rainforest-mind:executor");
  caso("D1 com aviso-fluxo desligado no projeto, executor sem fluxo passa: exit 0",
    desligado.status === 0, `exit=${desligado.status} stderr=${desligado.stderr}`);

  descartar(repo);
}

// == E. repositorio sem trilho de fluxo nenhum ==
console.log("== E. repositorio sem trilho de fluxo ==");
{
  const repo = novoRepo();

  const r = despachar(repo, repo.main, "rainforest-mind:executor");
  caso("E1 sem docs/rainforest/estado nem docs/plans, executor passa: exit 0",
    r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  caso("E1 o despacho que passa grava allow no log",
    ultimaDecisao(repo) && ultimaDecisao(repo).decisao === "allow", JSON.stringify(ultimaDecisao(repo)));

  descartar(repo);
}

// == F. trilho protheus: .gates.json recente libera, antigo nao ==
console.log("== F. trilho protheus: .gates.json recente libera ==");
{
  const repo = novoRepo();
  const plans = path.join(repo.main, "docs", "plans");
  fs.mkdirSync(plans, { recursive: true });
  const gates = path.join(plans, "2026-10-08-teste.gates.json");
  fs.writeFileSync(gates, "{}\n", "utf8");

  const recente = despachar(repo, repo.main, "rainforest-mind:executor");
  caso("F1 protheus com .gates.json recente: executor passa: exit 0",
    recente.status === 0, `exit=${recente.status} stderr=${recente.stderr}`);

  const umaSemanaAtras = (Date.now() - 2 * 24 * 3600 * 1000) / 1000;
  fs.utimesSync(gates, umaSemanaAtras, umaSemanaAtras);

  const antigo = despachar(repo, repo.main, "rainforest-mind:executor");
  caso("F2 protheus com .gates.json de ha 2 dias: executor sai 2",
    antigo.status === 2, `exit=${antigo.status} stderr=${antigo.stderr}`);
  caso("F2 stderr traz as saidas do fluxo protheus e do caminho leve",
    /protheus/.test(antigo.stderr || "") && /scripts[\\/]estado\.cjs leve --motivo/.test(antigo.stderr || ""),
    antigo.stderr);

  const leve = estado(repo, repo.main, ["leve", "--motivo", "hotfix mecanico de teste"]);
  caso("F3 estado.cjs leve grava o registro no trilho protheus",
    leve.status === 0, `exit=${leve.status} stdout=${leve.stdout} stderr=${leve.stderr}`);

  const comLeve = despachar(repo, repo.main, "rainforest-mind:executor");
  caso("F3 com leve na branch, executor no protheus com gates antigo passa: exit 0",
    comLeve.status === 0, `exit=${comLeve.status} stderr=${comLeve.stderr}`);

  descartar(repo);
}

console.log("");
console.log(`ok: ${ok}   falhou: ${falhou}   skipped: 0`);
process.exit(falhou > 0 ? 1 : 0);
