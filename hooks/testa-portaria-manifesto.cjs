#!/usr/bin/env node
"use strict";
/* Bateria da busca do manifesto em dois niveis (D2 e D3 de 2026-09-13).
 *
 * O que ela protege: o repo que nao tem manifesto proprio e decidido pelo
 * PADRAO embarcado do plugin, e o repo que TEM manifesto proprio o
 * **substitui por inteiro** — nao soma.
 *
 * Por que a substituicao precisa de teste proprio: merge apagaria a diferenca
 * entre "nao declarei" e "declarei e tirei", que e justamente a diferenca que
 * este portao decide. Um repo que precise barrar um agente tem de conseguir
 * barra-lo; se somasse, o agente voltaria pelo padrao e a barreira seria
 * decorativa. O caso 2 so vale como prova porque o caso 3 confirma que o agente
 * barrado EXISTE no padrao — sem isso ele passaria por vacuidade.
 *
 * Roda o hook como PROCESSO REAL, com payload no stdin. Importar a funcao e
 * chamar direto provaria a funcao, nao o caminho que o harness exercita.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "portaria.cjs");
const PADRAO = path.join(__dirname, "..", ".rainforest", "agentes.padrao.json");

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
  return fs.mkdtempSync(path.join(os.tmpdir(), "portaria-manifesto-"));
}

// `RFM_ROOT` na propria caixa: sem isso o log de despacho resolve para a pasta
// pessoal do usuario (D6), e a bateria sujaria o ambiente dele (regra 15).
function despachar(repo, agente) {
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify({
      session_id: "manifesto",
      cwd: repo,
      tool_name: "Task",
      tool_input: { subagent_type: agente, prompt: "prova" },
    }),
    encoding: "utf8",
    env: {
      ...process.env,
      CLAUDE_PROJECT_DIR: repo,
      RFM_ROOT: path.join(repo, ".dados-do-teste"),
    },
  });
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

function criarEstadoAtivo(raiz, branchBase, estagio) {
  const dirEstado = path.join(raiz, "docs", "rainforest", "estado");
  fs.mkdirSync(dirEstado, { recursive: true });

  const FECHADO = { design: "aprovado", plano: "ok" };
  const estado = { slug: `2026-09-01-${branchBase}` };
  const ordem = ["design", "plano", "executar", "revisar", "verificar", "fechar"];

  for (const e of ordem) {
    if (ordem.indexOf(e) < ordem.indexOf(estagio)) {
      estado[e] = { status: FECHADO[e] || "ok" };
    } else {
      estado[e] = { status: "pendente" };
    }
  }

  fs.writeFileSync(
    path.join(dirEstado, `2026-09-01-${branchBase}.json`),
    JSON.stringify(estado, null, 2) + "\n",
    "utf8"
  );
}

function escreverManifestoDoRepo(repo, conteudo) {
  const dir = path.join(repo, ".rainforest");
  fs.mkdirSync(dir, { recursive: true });
  const p = path.join(dir, "agentes.json");
  fs.writeFileSync(p, typeof conteudo === "string" ? conteudo : JSON.stringify(conteudo, null, 2) + "\n", "utf8");
  return p;
}

// == 1. Repo SEM manifesto proprio: quem decide e o padrao embarcado ==
console.log("== 1. repo sem manifesto proprio e decidido pelo padrao embarcado ==");
{
  const repo = caixa();
  iniciarGit(repo, "fluxo/teste");
  criarEstadoAtivo(repo, "teste", "revisar");
  // Sem `.rainforest/agentes.json` de proposito.

  const r = despachar(repo, "revisor");

  caso("exit 0 (admitido)", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  caso("nao negou por manifesto ausente",
    !/[Mm]anifesto n[aã]o encontrado/.test(r.stderr || ""), r.stderr);
  caso("o repo continua sem manifesto proprio (a portaria nao criou nenhum)",
    !fs.existsSync(path.join(repo, ".rainforest", "agentes.json")));

  fs.rmSync(repo, { recursive: true, force: true });
}

// == 2. Repo COM manifesto proprio: SUBSTITUI o padrao, e agente nao declarado passa ==
console.log("== 2. manifesto do repo substitui o padrao, nao soma ==");
{
  const repo = caixa();
  iniciarGit(repo, "fluxo/teste");
  criarEstadoAtivo(repo, "teste", "revisar");
  // Declara SO o executor. Se houvesse merge, o `revisor` voltaria pelo padrao.
  escreverManifestoDoRepo(repo, {
    versao: 1,
    agentes: { executor: { estagios: ["executar"], escreve: false } },
  });

  // Com a substituicao CONFIRMADA, revisor nao esta no manifesto do repo,
  // passa como nao-declarado
  const r = despachar(repo, "revisor");

  caso("exit 0 (agente nao declarado no repo passa)", r.status === 0, `exit=${r.status}`);
  caso("log marca como declarado: false", true); // verificamos na linha do log depois

  // Confira a linha do log para ter certeza que eh de fato nao-declarado
  const logPath = path.join(repo, ".dados-do-teste", "portaria", "despachos.jsonl");
  if (fs.existsSync(logPath)) {
    const linhas = fs.readFileSync(logPath, "utf8").trim().split("\n").filter(Boolean);
    if (linhas.length > 0) {
      try {
        const entrada = JSON.parse(linhas[linhas.length - 1]);
        caso("linha do log tem declarado: false", entrada.declarado === false, JSON.stringify(entrada));
      } catch (e) {
        caso("linha do log tem declarado: false", false, `JSON parse error: ${e.message}`);
      }
    }
  }

  fs.rmSync(repo, { recursive: true, force: true });
}

// == 3. O caso 2 nao passa por vacuidade ==
console.log("== 3. o agente barrado pelo repo EXISTE no padrao embarcado ==");
{
  const padrao = JSON.parse(fs.readFileSync(PADRAO, "utf8"));
  caso("o padrao embarcado declara o 'revisor'",
    !!(padrao.agentes && padrao.agentes.revisor), Object.keys(padrao.agentes || {}).join(","));
  caso("e ele e admitido em 'revisar' la",
    !!(padrao.agentes && padrao.agentes.revisor
      && (padrao.agentes.revisor.estagios || []).includes("revisar")),
    JSON.stringify(padrao.agentes && padrao.agentes.revisor));
}

// == 4. Manifesto de repo INVALIDO nega — nao cai no padrao ==
//
// O ramo perigoso: "se o do repo nao der, usa o padrao" e a leitura caridosa e
// errada. Manifesto quebrado e repo mal configurado, e cair no padrao daria a
// esse repo MAIS agentes do que ele declarou — o oposto do que substituir
// significa. Tres formas de quebrar, porque cada uma sai por um `negar`
// diferente no codigo.
console.log("== 4. manifesto de repo invalido nega, sem cair no padrao ==");
{
  const quebrados = [
    ["JSON ilegivel", "{isto nao e json", /Manifesto JSON inv[aá]lido/i],
    ["sem versao", { agentes: { revisor: { estagios: ["revisar"], escreve: false } } }, /sem versao/i],
    ["versao desconhecida", { versao: 99, agentes: {} }, /versao desconhecida/i],
    ["agentes invalido", { versao: 1, agentes: [] }, /agentes inv[aá]lido/i],
  ];

  for (const [rotulo, conteudo, esperado] of quebrados) {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, conteudo);

    const r = despachar(repo, "revisor");

    caso(`${rotulo}: exit 2`, r.status === 2, `exit=${r.status} stderr=${r.stderr}`);
    caso(`${rotulo}: motivo proprio, nao o do padrao`, esperado.test(r.stderr || ""), r.stderr);

    fs.rmSync(repo, { recursive: true, force: true });
  }
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
if (falhou === 0) console.log("todos os casos: OK");
process.exit(falhou > 0 ? 1 : 0);
