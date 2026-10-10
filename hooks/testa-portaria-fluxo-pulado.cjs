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

function despachar(repo, cwd, subagente, opcoes = {}, hook = HOOK) {
  const toolInput = { subagent_type: subagente, prompt: "Tarefa de teste do fluxo pulado." };
  if (!opcoes.semIsolation) toolInput.isolation = "worktree";
  const payload = {
    session_id: "sessao-fluxo-pulado",
    cwd,
    hook_event_name: "PreToolUse",
    tool_name: "Agent",
    tool_input: toolInput,
  };
  return spawnSync(process.execPath, [hook], {
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

// Copia o plugin (hooks/, scripts/ e .rainforest/, sem as baterias testa-*) para `destino`.
// O hook e o estado.cjs copiados carregam os `require` relativos do plugin inteiro, e a
// portaria le o manifesto padrao em `.rainforest/agentes.padrao.json` da raiz do plugin.
function copiarPlugin(destino) {
  const raizPlugin = path.join(__dirname, "..");
  for (const sub of ["hooks", "scripts", ".rainforest"]) {
    fs.cpSync(path.join(raizPlugin, sub), path.join(destino, sub), {
      recursive: true,
      filter: (origem) => !path.basename(origem).startsWith("testa-"),
    });
  }
}

// Comandos impressos no formato com aspas: "<node>" "<estado.cjs>" <resto>. As duas
// partes entre aspas são o que o detector e o agente leem; o teste confere as duas.
const RE_LEVE = /"([^"]+)" "([^"]*estado\.cjs)" (leve --motivo "[^"]*" --repo "[^"]*")/;
const RE_INICIAR = /"([^"]+)" "([^"]*estado\.cjs)" iniciar --slug/;
function noExecPath(p) {
  return p === process.execPath.split(path.sep).join("/");
}
// Quebra o comando em argumentos respeitando aspas, para rodar sem shell.
function argumentosDoComando(texto) {
  return [...texto.matchAll(/"([^"]*)"|(\S+)/g)].map((m) => (m[1] !== undefined ? m[1] : m[2]));
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
    /scripts[\\/]estado\.cjs" leve --motivo/.test(r.stderr || ""), r.stderr);
  caso("A1 stderr traz a dica do prefixo & para PowerShell (Issue #442)",
    /em PowerShell, prefixe `& `/.test(r.stderr || ""), r.stderr);
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
    /protheus/.test(antigo.stderr || "") && /scripts[\\/]estado\.cjs" leve --motivo/.test(antigo.stderr || ""),
    antigo.stderr);

  const leve = estado(repo, repo.main, ["leve", "--motivo", "hotfix mecanico de teste"]);
  caso("F3 estado.cjs leve grava o registro no trilho protheus",
    leve.status === 0, `exit=${leve.status} stdout=${leve.stdout} stderr=${leve.stderr}`);

  const comLeve = despachar(repo, repo.main, "rainforest-mind:executor");
  caso("F3 com leve na branch, executor no protheus com gates antigo passa: exit 0",
    comLeve.status === 0, `exit=${comLeve.status} stderr=${comLeve.stderr}`);

  descartar(repo);
}

// == G. trilho protheus: o campo `branch` do .gates.json decide (D10) ==
console.log("== G. trilho protheus: campo branch do .gates.json ==");
{
  const repo = novoRepo();
  const plans = path.join(repo.main, "docs", "plans");
  fs.mkdirSync(plans, { recursive: true });
  const gates = path.join(plans, "2026-10-08-teste.gates.json");
  const mtime = (horas) => (Date.now() - horas * 3600 * 1000) / 1000;
  const gravar = (texto, horas) => {
    fs.writeFileSync(gates, texto, "utf8");
    fs.utimesSync(gates, mtime(horas), mtime(horas));
  };

  gravar(JSON.stringify({ branch: "outra-branch", gates: [] }), 0);
  const outra = despachar(repo, repo.main, "rainforest-mind:executor");
  caso("G1 gates de outra branch com mtime de agora: executor sai 2",
    outra.status === 2, `exit=${outra.status} stderr=${outra.stderr}`);

  gravar(JSON.stringify({ branch: "main", gates: [] }), 72);
  const igual = despachar(repo, repo.main, "rainforest-mind:executor");
  caso("G2 gates com a branch atual e mtime de 3 dias: executor passa: exit 0",
    igual.status === 0, `exit=${igual.status} stderr=${igual.stderr}`);

  gravar("{ isto nao e json", 0);
  const ilegivel = despachar(repo, repo.main, "rainforest-mind:executor");
  caso("G3 gates ilegivel com mtime de agora e ignorado: executor sai 2, sem queda do hook",
    ilegivel.status === 2, `exit=${ilegivel.status} stderr=${ilegivel.stderr}`);

  descartar(repo);
}

// Leva o fluxo ate o estagio `ate` pelo scripts/estado.cjs real. design aprovado e
// plano ok; para chegar a revisar, `exigir executar` (arma a catraca) e executar ok
// com `mutacao`; para verificar, revisar ok; para fechar, verificar ok com comando e
// saida. Devolve null quando chegou, ou a saida do passo que recusou.
const ORDEM_FLUXO = ["design", "plano", "executar", "revisar", "verificar", "fechar"];
function fluxoAberto(repo, wt, ate) {
  const passos = [
    ["iniciar", "--slug", SLUG, "--titulo", "teste"],
    ["marcar", "--slug", SLUG, "--estagio", "design", "--status", "aprovado"],
    ["marcar", "--slug", SLUG, "--estagio", "plano", "--status", "ok"],
  ];
  const idx = ORDEM_FLUXO.indexOf(ate);
  if (idx >= ORDEM_FLUXO.indexOf("revisar")) {
    passos.push(["exigir", "--slug", SLUG, "--estagio", "executar"]);
    passos.push(["marcar", "--slug", SLUG, "--estagio", "executar", "--status", "ok", "--json",
      JSON.stringify({ comando: "node hooks/testa-portaria-fluxo-pulado.cjs", saida: "ok: 1 falhou: 0",
        mutacao: [{ tarefa: 1, resultado: "vermelho", fixture: "caso-de-teste" }] })]);
  }
  if (idx >= ORDEM_FLUXO.indexOf("verificar")) {
    passos.push(["marcar", "--slug", SLUG, "--estagio", "revisar", "--status", "ok"]);
  }
  if (idx >= ORDEM_FLUXO.indexOf("fechar")) {
    // O `verificar` exige comando que cite uma peca de sensor do repositorio (D3, D6 do estado).
    passos.push(["marcar", "--slug", SLUG, "--estagio", "verificar", "--status", "ok", "--json",
      JSON.stringify({ comando: "node scripts/conferir-categoria.cjs", saida: "ok: 1 falhou: 0" })]);
  }
  for (const passo of passos) {
    const r = estado(repo, wt, passo);
    if (r.status !== 0) return `${passo.join(" ")}: exit=${r.status} stderr=${r.stderr}`;
  }
  return null;
}

// == G. estagios do manifesto: tester em revisar, documentador em fechar ==
console.log("== G. estagios do manifesto: tester em revisar, documentador em fechar ==");
{
  const repo = novoRepo();
  const wt = comWorktree(repo);

  const erro = fluxoAberto(repo, wt, "revisar");
  caso("G0 fluxo levado a revisar pelo estado.cjs real",
    erro === null, erro);
  const prox = estado(repo, wt, ["proximo", "--slug", SLUG]);
  caso("G0 estagio aberto apos executar ok e revisar",
    /revisar/.test(prox.stdout || ""), `exit=${prox.status} stdout=${prox.stdout} stderr=${prox.stderr}`);

  const tester = despachar(repo, wt, "rainforest-mind:tester");
  caso("tester despacha com fluxo em revisar (mutacao do revisar): exit 0",
    tester.status === 0, `exit=${tester.status} stderr=${tester.stderr}`);
  caso("tester despacha com fluxo em revisar (mutacao do revisar): grava allow no log",
    ultimaDecisao(repo) && ultimaDecisao(repo).decisao === "allow", JSON.stringify(ultimaDecisao(repo)));

  const exec = despachar(repo, wt, "rainforest-mind:executor");
  caso("executor em revisar sai 2",
    exec.status === 2, `exit=${exec.status} stderr=${exec.stderr}`);
  caso("executor em revisar: stderr diz o estagio aberto revisar",
    /estagio aberto: revisar/.test(exec.stderr || ""), exec.stderr);

  descartar(repo);
}

// == H. estagios do manifesto: documentador em fechar ==
console.log("== H. documentador em fechar ==");
{
  const repo = novoRepo();
  const wt = comWorktree(repo);

  const erro = fluxoAberto(repo, wt, "fechar");
  caso("H0 fluxo levado a fechar pelo estado.cjs real",
    erro === null, erro);
  const prox = estado(repo, wt, ["proximo", "--slug", SLUG]);
  caso("H0 estagio aberto apos verificar ok e fechar",
    /fechar/.test(prox.stdout || ""), `exit=${prox.status} stdout=${prox.stdout} stderr=${prox.stderr}`);

  const doc = despachar(repo, wt, "rainforest-mind:documentador");
  caso("documentador despacha com fluxo em fechar: exit 0",
    doc.status === 0, `exit=${doc.status} stderr=${doc.stderr}`);

  const exec = despachar(repo, wt, "rainforest-mind:executor");
  caso("executor em fechar sai 2",
    exec.status === 2, `exit=${exec.status} stderr=${exec.stderr}`);
  caso("executor em fechar: stderr diz o estagio aberto fechar",
    /estagio aberto: fechar/.test(exec.stderr || ""), exec.stderr);

  descartar(repo);
}

// == I. mensagem de bloqueio: HEAD destacado e branch padrao ==
console.log("== I. mensagem de bloqueio no HEAD destacado e na branch padrao ==");
{
  const repo = novoRepo();
  const wt = comWorktree(repo);
  git(wt, ["checkout", "-q", "--detach"]);

  const r = despachar(repo, wt, "rainforest-mind:executor");
  caso("I1 HEAD destacado: executor sem fluxo sai 2",
    r.status === 2, `exit=${r.status} stderr=${r.stderr}`);
  caso("I1 HEAD destacado: a saida 2 manda trocar para uma branch (git switch -c)",
    /saida 2: HEAD destacado.*git switch -c fluxo\//.test(r.stderr || ""), r.stderr);
  caso("I1 HEAD destacado: nao oferece o leve",
    !/leve --motivo/.test(r.stderr || ""), r.stderr);

  descartar(repo);
}
{
  const repo = novoRepo();
  fs.mkdirSync(path.join(repo.main, "docs", "rainforest", "estado"), { recursive: true });

  const r = despachar(repo, repo.main, "rainforest-mind:executor");
  caso("I2 branch padrao (main) de repo rainforest: executor sem fluxo sai 2",
    r.status === 2, `exit=${r.status} stderr=${r.stderr}`);
  caso("I2 branch padrao: a saida 2 manda despachar de dentro do worktree do fluxo",
    /saida 2: 'main' e a branch padrao.*despache de dentro do worktree do fluxo/.test(r.stderr || ""), r.stderr);
  caso("I2 branch padrao: diz que o leve e recusado nela pela regra 11",
    /leve e recusado nela \(regra 11\)/.test(r.stderr || ""), r.stderr);

  descartar(repo);
}

// == J. leve impresso pela portaria roda de outro cwd e libera o despacho ==
console.log("== J. leve impresso pela portaria roda de outro cwd ==");
{
  const repo = novoRepo();
  const wt = comWorktree(repo);

  const bloq = despachar(repo, wt, "rainforest-mind:executor");
  caso("J0 sem fluxo e sem leve, executor sai 2",
    bloq.status === 2, `exit=${bloq.status} stderr=${bloq.stderr}`);
  const leveImpresso = RE_LEVE.exec(bloq.stderr || "");
  const iniciarImpresso = RE_INICIAR.exec(bloq.stderr || "");
  caso("J1 o leve impresso traz node e estado.cjs absolutos, entre aspas, e --repo com a raiz",
    leveImpresso !== null && noExecPath(leveImpresso[1]) && path.isAbsolute(leveImpresso[2]) && /--repo "/.test(leveImpresso[3]), bloq.stderr);
  caso("J2 nenhuma contrabarra no comando leve nem no iniciar impressos",
    leveImpresso !== null && iniciarImpresso !== null
      && !leveImpresso[0].includes("\\") && !iniciarImpresso[0].includes("\\"), bloq.stderr);
  caso("J3 o iniciar impresso usa o node e o estado.cjs absolutos, entre aspas",
    iniciarImpresso !== null && noExecPath(iniciarImpresso[1]) && path.isAbsolute(iniciarImpresso[2]), bloq.stderr);

  // Roda o leve IMPRESSO, de verdade: sem shell, a partir de um cwd fora do repositorio.
  // Sem o leve impresso no formato certo nao ha o que rodar: J4/J5 caem vermelhos, sem derrubar a bateria.
  const args = leveImpresso === null ? [] : argumentosDoComando(leveImpresso[3]);
  const leve = leveImpresso === null ? { status: null, stdout: "", stderr: "leve nao impresso" } : spawnSync(leveImpresso[1], [leveImpresso[2], ...args], {
    cwd: repo.dados,
    encoding: "utf8",
    env: ambiente(repo, wt),
    timeout: TIMEOUT_MS,
  });
  caso("J4 o leve impresso, rodado de outro cwd, grava o registro: exit 0",
    leve.status === 0, `exit=${leve.status} stdout=${leve.stdout} stderr=${leve.stderr}`);

  const depois = despachar(repo, wt, "rainforest-mind:executor");
  caso("J5 com o leve impresso rodado, o despacho seguinte do executor passa: exit 0",
    depois.status === 0, `exit=${depois.status} stderr=${depois.stderr}`);
  descartar(repo);
}

// == K. plugin copiado em pasta com espaco: o leve impresso roda e libera o despacho ==
console.log("== K. plugin copiado em pasta com espaco ==");
{
  const repo = novoRepo();
  const wt = comWorktree(repo);
  const copia = path.join(repo.sbx, "plug in");
  fs.mkdirSync(copia);
  copiarPlugin(copia);
  const hookCopia = path.join(copia, "hooks", "portaria.cjs");

  const bloq = despachar(repo, wt, "rainforest-mind:executor", {}, hookCopia);
  const leveImpresso = RE_LEVE.exec(bloq.stderr || "");
  const args = leveImpresso === null ? [] : argumentosDoComando(leveImpresso[3]);
  const leve = leveImpresso === null ? { status: null, stdout: "", stderr: "leve nao impresso" } : spawnSync(leveImpresso[1], [leveImpresso[2], ...args], {
    cwd: repo.dados,
    encoding: "utf8",
    env: ambiente(repo, wt),
    timeout: TIMEOUT_MS,
  });
  const depois = despachar(repo, wt, "rainforest-mind:executor", {}, hookCopia);
  caso("plugin em pasta com espaco: o leve impresso pela portaria roda e libera o despacho",
    copia.includes(" ") && bloq.status === 2 && leveImpresso !== null && leveImpresso[2].includes(" ")
      && leve.status === 0 && depois.status === 0,
    `copia=${copia} bloq=${bloq.status} stderr=${bloq.stderr} leve=${leve.status} ${leve.stderr} depois=${depois.status} ${depois.stderr}`);

  descartar(repo);
}

// == L. Issue #447: branch com o slug inteiro (com data) nao casa, e a recusa diz por que ==
console.log("== L. branch que nao casa com o slug: a recusa nomeia branch, esperado e abertos ==");
{
  const repo = novoRepo();
  const wt = path.join(repo.sbx, "wt-l");
  git(repo.main, ["worktree", "add", "-q", "-b", "fluxo/2026-10-08-glossario-compartilhado", wt]);
  fs.mkdirSync(path.join(wt, "docs", "rainforest", "estado"), { recursive: true });

  const ini = estado(repo, wt, ["iniciar", "--slug", "2026-10-08-glossario-compartilhado", "--titulo", "glossario"]);
  const ini2 = estado(repo, wt, ["iniciar", "--slug", "2026-10-01-outro-trabalho", "--titulo", "outro"]);
  caso("L0 dois fluxos abertos gravados pelo estado.cjs real",
    ini.status === 0 && ini2.status === 0, `ini=${ini.status} ${ini.stderr} ini2=${ini2.status} ${ini2.stderr}`);

  const bloq = despachar(repo, wt, "rainforest-mind:executor");
  const err = bloq.stderr || "";
  caso("L1 executor sai 2 (fora-de-fluxo)",
    bloq.status === 2 && /estagio aberto: fora-de-fluxo/.test(err), `exit=${bloq.status} stderr=${err}`);
  caso("L2 stderr nomeia a branch lida",
    err.includes("branch lida: 'fluxo/2026-10-08-glossario-compartilhado'"), err);
  caso("L3 stderr nomeia o nome esperado (fluxo/<slug sem data>)",
    err.includes("espera fluxo/glossario-compartilhado"), err);
  caso("L4 stderr lista o slug aberto mais perto primeiro",
    /Abertos mais perto: 2026-10-08-glossario-compartilhado \(espera fluxo\/glossario-compartilhado\), 2026-10-01-outro-trabalho/.test(err), err);

  // Contraprova: sem fluxo aberto nenhum, a mensagem nao ganha a linha de diagnostico.
  const repo2 = novoRepo();
  const wt2 = comWorktree(repo2);
  const sem = despachar(repo2, wt2, "rainforest-mind:executor");
  caso("L5 sem fluxo aberto, a recusa nao traz 'branch lida'",
    sem.status === 2 && !(sem.stderr || "").includes("branch lida"), `exit=${sem.status} stderr=${sem.stderr}`);

  descartar(repo);
  descartar(repo2);
}

console.log("");
console.log(`ok: ${ok}   falhou: ${falhou}   skipped: 0`);
process.exit(falhou > 0 ? 1 : 0);
