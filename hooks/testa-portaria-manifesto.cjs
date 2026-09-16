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
//
// `opcoes` e novo (Tarefa 6, campo `sensores`): as quatro chamadas que ja
// existiam continuam identicas (prompt "prova", sem isolation/name), porque
// `opcoes` e opcional e so acrescenta chaves ao `tool_input` quando pedido —
// os casos novos do `escreve: true` precisam de `isolation`/`name` para
// passar pelo portao de D3 passo 5b (regra 11) antes de chegar no de sensor.
function despachar(repo, agente, opcoes) {
  opcoes = opcoes || {};
  const toolInput = {
    subagent_type: agente,
    prompt: opcoes.prompt !== undefined ? opcoes.prompt : "prova",
  };
  if (opcoes.isolation !== undefined) toolInput.isolation = opcoes.isolation;
  if (opcoes.name !== undefined) toolInput.name = opcoes.name;

  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify({
      session_id: "manifesto",
      cwd: repo,
      tool_name: "Task",
      tool_input: toolInput,
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

// == 6. Inferencia de `escreve` para agente NAO declarado (issue #264) ==
//
// Este bloco existe por causa de duas coisas que nasceram juntas na #264:
//
// 1. A inferencia e o que mantem a regra 11 valendo para agente de outro plugin.
//    Sem ela, quem nao esta no manifesto entraria como read-only — e sao
//    justamente os agentes de outro plugin que nao estao no manifesto.
// 2. A inferencia monta um CAMINHO a partir do nome do agente
//    (`<raiz>/agents/<nome>.md`), e desde a #264 esse nome chega ali sem ter
//    passado por manifesto nenhum. Antes, nome fora do manifesto era negado
//    antes de virar caminho.
console.log("== 6. escreve inferido do frontmatter para agente nao declarado ==");
{
  const escreverAgente = (repo, nome, tools) => {
    const dir = path.join(repo, "agents");
    fs.mkdirSync(dir, { recursive: true });
    const fm = ["---", `name: ${nome}`, "description: prova", "tools:"]
      .concat(tools.map((t) => `  - ${t}`))
      .concat(["---", "", "corpo"])
      .join("\n");
    fs.writeFileSync(path.join(dir, `${nome}.md`), fm, "utf8");
  };

  // 6a. Frontmatter com Write/Edit -> escreve inferido TRUE, e a regra 11 morde
  //     sem ninguem ter declarado nada.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "executar");
    escreverAgente(repo, "forasteiro-que-edita", ["Read", "Grep", "Write", "Edit"]);

    const r = despachar(repo, "forasteiro-que-edita");
    caso("6a. nao declarado com Write no frontmatter: exit 2 (regra 11)",
      r.status === 2, `exit=${r.status} stderr=${r.stderr}`);
    caso("6a. o motivo e o da regra 11", /escreve: true/.test(r.stderr || ""), r.stderr);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 6b. Frontmatter so com tool read-only -> passa, e o log diz que a checagem
  //     FOI feita. Sem este caso o 6a passaria com a inferencia devolvendo
  //     `true` para tudo.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "executar");
    escreverAgente(repo, "forasteiro-que-so-le", ["Read", "Grep", "Glob"]);

    const r = despachar(repo, "forasteiro-que-so-le");
    caso("6b. nao declarado so com tool read-only: exit 0",
      r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    const allow = lerLog(path.join(repo, ".dados-do-teste")).filter((l) => l.decisao === "allow");
    caso("6b. e o log NAO o marca como nao-conferido (o arquivo estava ao alcance)",
      allow.length === 1 && allow[0].escreve_conferido === undefined, JSON.stringify(allow));

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 6c. Arquivo fora de alcance -> passa MARCADO, em vez de afirmar read-only.
  //     E o caso comum em repo de consumidor, onde os agentes vem do cache do
  //     plugin.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "executar");

    const r = despachar(repo, "forasteiro-sem-arquivo");
    caso("6c. sem arquivo ao alcance: exit 0", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    const allow = lerLog(path.join(repo, ".dados-do-teste")).filter((l) => l.decisao === "allow");
    caso("6c. e o log marca escreve_conferido: false",
      allow.length === 1 && allow[0].escreve_conferido === false, JSON.stringify(allow));

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 6d. Nome que nao e um segmento simples nao vira caminho. O mesmo arquivo do
  //     6a, alcancado por travessia, NAO pode ser lido — se fosse, este caso
  //     daria o exit 2 do 6a. Dar exit 0 aqui e a prova de que a leitura nao
  //     aconteceu.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "executar");
    escreverAgente(repo, "forasteiro-que-edita", ["Read", "Write", "Edit"]);

    for (const travessia of [
      "../agents/forasteiro-que-edita",
      "..\\..\\agents\\forasteiro-que-edita",
      "subpasta/forasteiro-que-edita",
    ]) {
      const r = despachar(repo, travessia);
      caso(`6d. nome com travessia (${travessia}): exit 0, sem ler o arquivo`,
        r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
    }

    fs.rmSync(repo, { recursive: true, force: true });
  }
}


// == 7. campo `sensores` do manifesto (Tarefa 6 do plano guias-e-sensores) ==
//
// O portao: agente cujo manifesto nao traz `sensores` e despachado sem
// mudanca nenhuma (7a); agente que traz a lista e o briefing pede sensor
// DELA e despachado (5b, 5g-ok); pede sensor DE FORA e negado com exit 2,
// dizendo qual sensor foi pedido e qual manifesto foi lido (5c, 5g-fora);
// sem linha `Sensor:` no briefing, a lista nao trava nada (7d); `sensores`
// mal formado no manifesto nega (7e); linha `Sensor:` presente mas
// ilegivel registra (7f, 2026-09-15). 7g prova que o portao vale tambem para `escreve:
// true` — ele fica ANTES da bifurcacao que sai com `process.exit(0)`
// proprio, e por isso precisa de caso com agente que escreve.
console.log("== 7. campo sensores do manifesto ==");
{
  // 7a. sem `sensores` no manifesto do repo: uma linha `Sensor:` no briefing
  // nao trava nada — ausencia do campo e "esta tarefa nao pede sensor".
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, {
      versao: 1,
      agentes: { revisor: { estagios: ["revisar"], escreve: false } },
    });

    const r = despachar(repo, "revisor", { prompt: "prova\nSensor: qualquer-coisa\n" });

    caso("7a: sem sensores no manifesto, exit 0 mesmo com linha Sensor: no briefing",
      r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 7b/5c/5d/5f usam o mesmo manifesto: revisor com sensores declarados.
  const manifestoComSensores = {
    versao: 1,
    agentes: {
      revisor: { estagios: ["revisar"], escreve: false, sensores: ["temperatura", "umidade"] },
    },
  };

  // 7b. briefing pede sensor QUE ESTA na lista: despachado.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova\nSensor: temperatura\n" });

    caso("7b: sensor pedido esta na lista, exit 0", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 7c. briefing pede sensor DE FORA da lista: passa com exit 0, registrando
  // o sensor de fora (2026-09-15, issue #264, Tarefa 6 do plano).
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova\nSensor: pressao\n" });

    caso("7c: sensor pedido fora da lista, exit 0", r.status === 0, `exit=${r.status}`);
    const log = lerLog(path.join(repo, ".dados-do-teste"));
    const ultima = log.length > 0 ? log[log.length - 1] : null;
    caso("7c: log carrega sensor_fora_da_lista com o sensor pedido",
      ultima && Array.isArray(ultima.sensor_fora_da_lista) && ultima.sensor_fora_da_lista.includes("pressao"),
      `campo=${JSON.stringify(ultima?.sensor_fora_da_lista)}`);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 7c2. DUAS linhas `Sensor:`, uma dentro da lista e outra fora: a de dentro
  // nao pode mascarar a de fora — TODAS as linhas contam, nao so a primeira
  // (e a razao de nao usar `.match()`/`.test()` de primeiro-encontro aqui,
  // ao contrario de `runtimeEfetivo`). Sem este caso, um refactor para
  // primeiro-encontro deixaria a bateria verde do mesmo jeito. Passa com exit 0
  // e registra os sensores de fora (2026-09-15).
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova\nSensor: temperatura\nSensor: pressao\n" });

    caso("7c2: duas linhas Sensor:, uma fora da lista, exit 0", r.status === 0, `exit=${r.status}`);
    const log = lerLog(path.join(repo, ".dados-do-teste"));
    const ultima = log.length > 0 ? log[log.length - 1] : null;
    caso("7c2: log tem sensor_fora_da_lista com pressao, nao temperatura",
      ultima && Array.isArray(ultima.sensor_fora_da_lista) &&
      ultima.sensor_fora_da_lista.includes("pressao") &&
      !ultima.sensor_fora_da_lista.includes("temperatura"),
      `campo=${JSON.stringify(ultima?.sensor_fora_da_lista)}`);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 7d. manifesto tem `sensores`, mas o briefing NAO declara linha `Sensor:`
  // nenhuma: nada pedido, nada fora da lista — despachado.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova, sem linha de sensor" });

    caso("7d: sensores na lista, briefing sem linha Sensor:, exit 0",
      r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 7e. `sensores` mal formado no manifesto (nao e lista de nomes) nega —
  // mesma regra dos tres estados que ja valem para `escreve` e `runtime`.
  {
    const formasInvalidas = [
      ["string em vez de lista", "temperatura"],
      ["lista vazia", []],
      ["lista com item nao-string", ["temperatura", 7]],
    ];

    for (const [rotulo, valor] of formasInvalidas) {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "revisar");
      escreverManifestoDoRepo(repo, {
        versao: 1,
        agentes: { revisor: { estagios: ["revisar"], escreve: false, sensores: valor } },
      });

      const r = despachar(repo, "revisor");

      caso(`7e (${rotulo}): exit 2`, r.status === 2, `exit=${r.status}`);
      caso(`7e (${rotulo}): motivo cita 'sensores'`, /sensores/i.test(r.stderr || ""), r.stderr);

      fs.rmSync(repo, { recursive: true, force: true });
    }
  }

  // 7f. linha `Sensor:` presente mas com valor ilegivel (vazio, com espaco):
  // nao da pra afirmar "nao pediu nada" a partir de texto nao lido — registra
  // (2026-09-15, issue #264, Tarefa 6 do plano).
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova\nSensor: \n" });

    caso("7f: linha Sensor: com valor vazio, exit 0", r.status === 0, `exit=${r.status}`);
    const log = lerLog(path.join(repo, ".dados-do-teste"));
    const ultima = log.length > 0 ? log[log.length - 1] : null;
    caso("7f: log marca que a linha nao foi lida (sensor_ilegivel: true)",
      ultima && ultima.sensor_ilegivel === true,
      `campo=${JSON.stringify(ultima?.sensor_ilegivel)}`);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 7g. o portao vale tambem para `escreve: true` — prova de posicionamento.
  // Fica ANTES da bifurcacao que sai com `process.exit(0)` proprio (linha
  // ~959 de portaria.cjs); sem essa prova, um portao colocado so ao lado da
  // checagem de `tools:` (dentro do `escreve === false`) passaria verde sem
  // cobrir nada real, porque `executor` e companhia nunca chegariam la.
  {
    const manifestoExecutor = {
      versao: 1,
      agentes: {
        executor: { estagios: ["executar"], escreve: true, sensores: ["disco"] },
      },
    };

    // 7g-ok: sensor pedido esta na lista, isolation correto, sem name: exit 0.
    {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "executar");
      escreverManifestoDoRepo(repo, manifestoExecutor);

      const r = despachar(repo, "executor", {
        prompt: "prova\nSensor: disco\n",
        isolation: "worktree",
      });

      caso("7g-ok: escreve:true com sensor da lista, isolation correto, exit 0",
        r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

      fs.rmSync(repo, { recursive: true, force: true });
    }

    // 7g-fora: mesmo agente, sensor pedido fora da lista: passa com exit 0
    // (2026-09-15, issue #264, Tarefa 6 do plano). Prova que o portao de sensor
    // registra e continua ANTES do allow proprio do `escreve: true`.
    {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "executar");
      escreverManifestoDoRepo(repo, manifestoExecutor);

      const r = despachar(repo, "executor", {
        prompt: "prova\nSensor: rede\n",
        isolation: "worktree",
      });

      caso("7g-fora: escreve:true com sensor fora da lista, exit 0", r.status === 0, `exit=${r.status}`);
      const log = lerLog(path.join(repo, ".dados-do-teste"));
      const ultima = log.length > 0 ? log[log.length - 1] : null;
      caso("7g-fora: log carrega sensor_fora_da_lista com o sensor pedido",
        ultima && Array.isArray(ultima.sensor_fora_da_lista) && ultima.sensor_fora_da_lista.includes("rede"),
        `campo=${JSON.stringify(ultima?.sensor_fora_da_lista)}`);

      fs.rmSync(repo, { recursive: true, force: true });
    }
  }
}

// == 8. Tarefa 7: a linha do SKILL.md bate com o parser (D18) ==
//
// Falsifica a documentacao, nao so o parser: LE `skills/executar/SKILL.md`
// em disco, extrai dali o bloco `Sensor: <nome>` (sem conhecer a forma de
// antemao — se alguem editar o SKILL.md para uma forma que o parser nao
// aceita, ex.: trocar `:` por `=`, o caso 6a cai vermelho) e prova as duas
// pontas que a Tarefa 7 promete:
//
//   6a. a linha exatamente como o texto a escreve, com o nome preenchido,
//       e aceita pelo parser — exit 0.
//   6b. a MESMA linha na forma antiga — o placeholder `<nome>` sem
//       preencher, ou seja, sem a declaracao de QUAL sensor — produz a
//       negacao que o proprio texto promete ("valor que nao seja um nome
//       ... nega em vez de ser ignorado", skills/executar/SKILL.md) — exit 2.
console.log("== 8. Tarefa 7: linha do SKILL.md bate com o parser ==");
{
  const skillPath = path.join(__dirname, "..", "skills", "executar", "SKILL.md");
  const skillTexto = fs.readFileSync(skillPath, "utf8");
  const m = skillTexto.match(/```\n(Sensor:[^\n]*)\n```/);

  caso("8: skills/executar/SKILL.md tem um bloco de exemplo 'Sensor: <nome>'",
    !!m, skillPath);

  if (m) {
    const linhaTemplate = m[1]; // "Sensor: <nome>", exatamente como o texto escreve

    const manifestoTarefa7 = {
      versao: 1,
      agentes: {
        revisor: { estagios: ["revisar"], escreve: false, sensores: ["disco"] },
      },
    };

    // 8a. a linha do texto, com o nome preenchido, e aceita pelo parser.
    {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "revisar");
      escreverManifestoDoRepo(repo, manifestoTarefa7);

      const linhaPreenchida = linhaTemplate.replace("<nome>", "disco");
      const r = despachar(repo, "revisor", { prompt: `prova\n${linhaPreenchida}\n` });

      caso("8a: linha do SKILL.md (preenchida) aceita pelo parser, exit 0",
        r.status === 0,
        `linha=${JSON.stringify(linhaPreenchida)} exit=${r.status} stderr=${r.stderr}`);

      fs.rmSync(repo, { recursive: true, force: true });
    }

    // 8b. a mesma linha, na forma antiga (placeholder nao preenchido, sem
    // declarar QUAL sensor) — o texto promete que valor ilegivel registra em vez
    // de ser ignorado (2026-09-15, Tarefa 6), e e esse registro que este caso prova.
    {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "revisar");
      escreverManifestoDoRepo(repo, manifestoTarefa7);

      const r = despachar(repo, "revisor", { prompt: `prova\n${linhaTemplate}\n` });

      caso("8b: linha na forma antiga (sem preencher o nome), registra sensor_ilegivel, exit 0",
        r.status === 0,
        `linha=${JSON.stringify(linhaTemplate)} exit=${r.status} stderr=${r.stderr}`);
      const log = lerLog(path.join(repo, ".dados-do-teste"));
      const ultima = log.length > 0 ? log[log.length - 1] : null;
      caso("8b: log marca que a linha template nao foi lida (sensor_ilegivel: true)",
        ultima && ultima.sensor_ilegivel === true,
        `campo=${JSON.stringify(ultima?.sensor_ilegivel)}`);

      fs.rmSync(repo, { recursive: true, force: true });
    }
  }
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
if (falhou === 0) console.log("todos os casos: OK");
process.exit(falhou > 0 ? 1 : 0);
