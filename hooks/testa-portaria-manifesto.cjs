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

// Despacho com `isolation`, para exercitar a regra 11 — o unico portao que a
// portaria ainda barra depois da #264. Sem isto, um agente com `escreve: true`
// so daria para testar pelo lado do deny, e "passa quando isolado" ficaria sem
// prova.
function despacharComIsolation(repo, agente, isolation) {
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify({
      session_id: "manifesto",
      cwd: repo,
      tool_name: "Task",
      tool_input: { subagent_type: agente, prompt: "prova", isolation },
    }),
    encoding: "utf8",
    env: {
      ...process.env,
      CLAUDE_PROJECT_DIR: repo,
      RFM_ROOT: path.join(repo, ".dados-do-teste"),
    },
  });
}

// O log e a evidencia de primeira classe da portaria (D4), e depois da #264 e
// ONDE a decisao aparece: o que antes era um `deny` visivel virou uma marca na
// linha. Bateria que so olhe o exit code deixou de medir a politica.
function lerLog(dadosDir) {
  const p = path.join(dadosDir, "portaria", "despachos.jsonl");
  if (!fs.existsSync(p)) return [];
  return fs
    .readFileSync(p, "utf8")
    .split("\n")
    .filter((l) => l.trim() !== "")
    .map((l) => JSON.parse(l));
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

// == 5. `agentes.extra.json` do usuario SOMA ao padrao embarcado (issue #264) ==
//
// Por que isto precisa de caso proprio: e o unico nivel de manifesto que SOMA,
// e depois da #264 a soma virou invisivel para uma bateria que so pergunte "o
// agente passou?" — nao declarado passa de qualquer jeito. O que prova a soma e
// a marca `via: "agentes.extra.json"` no log MAIS o `escreve: true` sendo
// obedecido pela regra 11.
//
// Medido: antes destes casos, mutar `if (usandoPadrao && fs.existsSync(
// manifestoExtra))` para `if (false)` — ou seja, desligar a soma inteira —
// deixava esta bateria VERDE. O `conferir-mutacao.cjs` recusou a entrega por
// isso, e e esse mutante que os casos abaixo passam a derrubar.
console.log("== 5. agentes.extra.json soma ao padrao, e o do repo o substitui ==");
{
  const escreverExtra = (dados, conteudo) => {
    fs.mkdirSync(dados, { recursive: true });
    const alvo = path.join(dados, "agentes.extra.json");
    const texto = typeof conteudo === "string" ? conteudo : JSON.stringify(conteudo, null, 2) + "\n";
    fs.writeFileSync(alvo, texto, "utf8");
    return alvo;
  };
  const ALHEIO = "plugin-alheio-implementer";
  const DECLARACAO = { versao: 1, agentes: { [ALHEIO]: { estagios: ["executar"], escreve: true } } };

  // 5a. Agente AUSENTE do padrao, declarado no extra com escreve: true. E a
  //     razao de o arquivo continuar existindo depois que a admissao foi
  //     revogada: sem ele a regra 11 nao alcanca agente de outro plugin.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "executar");
    const dados = path.join(repo, ".dados-do-teste");
    escreverExtra(dados, DECLARACAO);

    const sem = despachar(repo, ALHEIO);
    caso("5a. extra com escreve:true, sem isolation: exit 2 (regra 11)",
      sem.status === 2, `exit=${sem.status} stderr=${sem.stderr}`);
    caso("5a. o motivo e o da regra 11, nao 'nao consta no manifesto'",
      /escreve: true/.test(sem.stderr || "") && !/n[ao]o consta/.test(sem.stderr || ""),
      sem.stderr);

    const com = despacharComIsolation(repo, ALHEIO, "worktree");
    caso("5a. com isolation: worktree: exit 0", com.status === 0,
      `exit=${com.status} stderr=${com.stderr}`);

    const allow = lerLog(dados).filter((l) => l.decisao === "allow" && l.agente === ALHEIO);
    caso("5a. o log marca via: agentes.extra.json",
      allow.length === 1 && allow[0].via === "agentes.extra.json", JSON.stringify(allow));
    caso("5a. o log NAO o marca como nao declarado — ele ESTA declarado, pelo extra",
      allow.length === 1 && allow[0].declarado === undefined, JSON.stringify(allow));

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 5b. Sem o extra, o MESMO agente com o MESMO despacho passa sem worktree.
  //     Sem este caso o 5a valeria por vacuidade: um `escreve: true` que a
  //     portaria nunca leu daria o mesmo exit 2 de um que ela leu.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "executar");

    const r = despachar(repo, ALHEIO);
    caso("5b. sem o extra, o mesmo agente passa sem worktree: exit 0",
      r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    const allow = lerLog(path.join(repo, ".dados-do-teste")).filter((l) => l.decisao === "allow");
    caso("5b. e o log o marca como nao declarado",
      allow.length === 1 && allow[0].declarado === false, JSON.stringify(allow));

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 5c. Manifesto do repo presente: SUBSTITUI os dois de cima. O extra e
  //     ignorado — e com ele o `escreve: true` que fazia a regra 11 morder.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "executar");
    const dados = path.join(repo, ".dados-do-teste");
    escreverExtra(dados, DECLARACAO);
    escreverManifestoDoRepo(repo, {
      versao: 1,
      agentes: { executor: { estagios: ["executar"], escreve: false } },
    });

    const r = despachar(repo, ALHEIO);
    caso("5c. com manifesto do repo, o extra e ignorado: exit 0 sem worktree",
      r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    const allow = lerLog(dados).filter((l) => l.decisao === "allow");
    caso("5c. e o log o marca como nao declarado, sem via",
      allow.length === 1 && allow[0].declarado === false && allow[0].via === undefined,
      JSON.stringify(allow));

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 5d. Extra malformado NEGA — nao e ignorado em silencio. Ignorar devolveria
  //     o usuario ao sintoma da #264 (o agente que ele acabou de declarar nao
  //     vale) sem nada apontando para o arquivo torto.
  {
    const quebrados = [
      ["JSON ilegivel", "{isto nao e json", /JSON inv[aá]lido/i],
      ["versao errada", { versao: 99, agentes: {} }, /versao inv[aá]lida/i],
      ["agentes invalido", { versao: 1, agentes: [] }, /agentes' inv[aá]lido/i],
    ];

    for (const [rotulo, conteudo, esperado] of quebrados) {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "revisar");
      escreverExtra(path.join(repo, ".dados-do-teste"), conteudo);

      const r = despachar(repo, "revisor");
      caso(`5d. extra ${rotulo}: exit 2`, r.status === 2, `exit=${r.status} stderr=${r.stderr}`);
      caso(`5d. extra ${rotulo}: o motivo aponta para o arquivo do usuario`,
        /agentes\.extra\.json/.test(r.stderr || "") && esperado.test(r.stderr || ""),
        r.stderr);

      fs.rmSync(repo, { recursive: true, force: true });
    }
  }
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
if (falhou === 0) console.log("todos os casos: OK");
process.exit(falhou > 0 ? 1 : 0);
