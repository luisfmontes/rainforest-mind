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

// == 2. Repo COM manifesto proprio: SUBSTITUI o padrao por inteiro ==
console.log("== 2. manifesto do repo substitui o padrao, nao soma ==");
{
  const repo = caixa();
  iniciarGit(repo, "fluxo/teste");
  criarEstadoAtivo(repo, "teste", "revisar");
  // Declara SO o executor. Se houvesse merge, o `revisor` voltaria pelo padrao.
  escreverManifestoDoRepo(repo, {
    versao: 1,
    agentes: { executor: { estagios: ["executar"], escreve: true } },
  });

  const r = despachar(repo, "revisor");

  caso("exit 2 (2 e o unico codigo que barra)", r.status === 2, `exit=${r.status}`);
  caso("nega com 'nao consta no manifesto'",
    /n[aã]o consta no manifesto/.test(r.stderr || ""), r.stderr);
  caso("e o stderr aponta o manifesto DO REPO, nao o padrao",
    /manifesto deste reposit[oó]rio/.test(r.stderr || "")
      && !/agentes\.padrao\.json/.test(r.stderr || ""), r.stderr);

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

// == 5. campo `sensores` do manifesto (Tarefa 6 do plano guias-e-sensores) ==
//
// O portao: agente cujo manifesto nao traz `sensores` e despachado sem
// mudanca nenhuma (5a); agente que traz a lista e o briefing pede sensor
// DELA e despachado (5b, 5g-ok); pede sensor DE FORA e negado com exit 2,
// dizendo qual sensor foi pedido e qual manifesto foi lido (5c, 5g-fora);
// sem linha `Sensor:` no briefing, a lista nao trava nada (5d); `sensores`
// mal formado no manifesto nega (5e); linha `Sensor:` presente mas
// ilegivel nega (5f). 5g prova que o portao vale tambem para `escreve:
// true` — ele fica ANTES da bifurcacao que sai com `process.exit(0)`
// proprio, e por isso precisa de caso com agente que escreve.
console.log("== 5. campo sensores do manifesto ==");
{
  // 5a. sem `sensores` no manifesto do repo: uma linha `Sensor:` no briefing
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

    caso("5a: sem sensores no manifesto, exit 0 mesmo com linha Sensor: no briefing",
      r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 5b/5c/5d/5f usam o mesmo manifesto: revisor com sensores declarados.
  const manifestoComSensores = {
    versao: 1,
    agentes: {
      revisor: { estagios: ["revisar"], escreve: false, sensores: ["temperatura", "umidade"] },
    },
  };

  // 5b. briefing pede sensor QUE ESTA na lista: despachado.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova\nSensor: temperatura\n" });

    caso("5b: sensor pedido esta na lista, exit 0", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 5c. briefing pede sensor DE FORA da lista: nega com exit 2, dizendo o
  // sensor pedido e o manifesto lido.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    const manifestoPath = escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova\nSensor: pressao\n" });

    caso("5c: sensor pedido fora da lista, exit 2", r.status === 2, `exit=${r.status}`);
    caso("5c: stderr nomeia o sensor pedido ('pressao')", /pressao/.test(r.stderr || ""), r.stderr);
    caso("5c: stderr nomeia o manifesto lido",
      (r.stderr || "").includes(manifestoPath), r.stderr);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 5c2. DUAS linhas `Sensor:`, uma dentro da lista e outra fora: a de dentro
  // nao pode mascarar a de fora — TODAS as linhas contam, nao so a primeira
  // (e a razao de nao usar `.match()`/`.test()` de primeiro-encontro aqui,
  // ao contrario de `runtimeEfetivo`). Sem este caso, um refactor para
  // primeiro-encontro deixaria a bateria verde do mesmo jeito.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova\nSensor: temperatura\nSensor: pressao\n" });

    caso("5c2: duas linhas Sensor:, uma fora da lista, exit 2", r.status === 2, `exit=${r.status}`);
    caso("5c2: stderr nomeia a que ficou de fora ('pressao')", /pressao/.test(r.stderr || ""), r.stderr);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 5d. manifesto tem `sensores`, mas o briefing NAO declara linha `Sensor:`
  // nenhuma: nada pedido, nada fora da lista — despachado.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova, sem linha de sensor" });

    caso("5d: sensores na lista, briefing sem linha Sensor:, exit 0",
      r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 5e. `sensores` mal formado no manifesto (nao e lista de nomes) nega —
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

      caso(`5e (${rotulo}): exit 2`, r.status === 2, `exit=${r.status}`);
      caso(`5e (${rotulo}): motivo cita 'sensores'`, /sensores/i.test(r.stderr || ""), r.stderr);

      fs.rmSync(repo, { recursive: true, force: true });
    }
  }

  // 5f. linha `Sensor:` presente mas com valor ilegivel (vazio, com espaco):
  // nao da pra afirmar "nao pediu nada" a partir de texto nao lido — nega.
  {
    const repo = caixa();
    iniciarGit(repo, "fluxo/teste");
    criarEstadoAtivo(repo, "teste", "revisar");
    escreverManifestoDoRepo(repo, manifestoComSensores);

    const r = despachar(repo, "revisor", { prompt: "prova\nSensor: \n" });

    caso("5f: linha Sensor: com valor vazio, exit 2", r.status === 2, `exit=${r.status}`);
    caso("5f: motivo diz que o formato nao foi lido", /nao le|não lê/i.test(r.stderr || ""), r.stderr);

    fs.rmSync(repo, { recursive: true, force: true });
  }

  // 5g. o portao vale tambem para `escreve: true` — prova de posicionamento.
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

    // 5g-ok: sensor pedido esta na lista, isolation correto, sem name: exit 0.
    {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "executar");
      escreverManifestoDoRepo(repo, manifestoExecutor);

      const r = despachar(repo, "executor", {
        prompt: "prova\nSensor: disco\n",
        isolation: "worktree",
      });

      caso("5g-ok: escreve:true com sensor da lista, isolation correto, exit 0",
        r.status === 0, `exit=${r.status} stderr=${r.stderr}`);

      fs.rmSync(repo, { recursive: true, force: true });
    }

    // 5g-fora: mesmo agente, sensor pedido fora da lista: exit 2 — prova que
    // o portao de sensor barra ANTES do allow proprio do `escreve: true`.
    {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "executar");
      const manifestoPath = escreverManifestoDoRepo(repo, manifestoExecutor);

      const r = despachar(repo, "executor", {
        prompt: "prova\nSensor: rede\n",
        isolation: "worktree",
      });

      caso("5g-fora: escreve:true com sensor fora da lista, exit 2", r.status === 2, `exit=${r.status}`);
      caso("5g-fora: stderr nomeia o sensor pedido ('rede')", /rede/.test(r.stderr || ""), r.stderr);
      caso("5g-fora: stderr nomeia o manifesto lido",
        (r.stderr || "").includes(manifestoPath), r.stderr);

      fs.rmSync(repo, { recursive: true, force: true });
    }
  }
}

// == 6. Tarefa 7: a linha do SKILL.md bate com o parser (D18) ==
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
console.log("== 6. Tarefa 7: linha do SKILL.md bate com o parser ==");
{
  const skillPath = path.join(__dirname, "..", "skills", "executar", "SKILL.md");
  const skillTexto = fs.readFileSync(skillPath, "utf8");
  const m = skillTexto.match(/```\n(Sensor:[^\n]*)\n```/);

  caso("6: skills/executar/SKILL.md tem um bloco de exemplo 'Sensor: <nome>'",
    !!m, skillPath);

  if (m) {
    const linhaTemplate = m[1]; // "Sensor: <nome>", exatamente como o texto escreve

    const manifestoTarefa7 = {
      versao: 1,
      agentes: {
        revisor: { estagios: ["revisar"], escreve: false, sensores: ["disco"] },
      },
    };

    // 6a. a linha do texto, com o nome preenchido, e aceita pelo parser.
    {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "revisar");
      escreverManifestoDoRepo(repo, manifestoTarefa7);

      const linhaPreenchida = linhaTemplate.replace("<nome>", "disco");
      const r = despachar(repo, "revisor", { prompt: `prova\n${linhaPreenchida}\n` });

      caso("6a: linha do SKILL.md (preenchida) aceita pelo parser, exit 0",
        r.status === 0,
        `linha=${JSON.stringify(linhaPreenchida)} exit=${r.status} stderr=${r.stderr}`);

      fs.rmSync(repo, { recursive: true, force: true });
    }

    // 6b. a mesma linha, na forma antiga (placeholder nao preenchido, sem
    // declarar QUAL sensor) — o texto promete que valor ilegivel nega em vez
    // de ser ignorado, e e essa negacao que este caso prova.
    {
      const repo = caixa();
      iniciarGit(repo, "fluxo/teste");
      criarEstadoAtivo(repo, "teste", "revisar");
      escreverManifestoDoRepo(repo, manifestoTarefa7);

      const r = despachar(repo, "revisor", { prompt: `prova\n${linhaTemplate}\n` });

      caso("6b: linha na forma antiga (sem preencher o nome), a negacao que o texto promete, exit 2",
        r.status === 2,
        `linha=${JSON.stringify(linhaTemplate)} exit=${r.status} stderr=${r.stderr}`);

      fs.rmSync(repo, { recursive: true, force: true });
    }
  }
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);
if (falhou === 0) console.log("todos os casos: OK");
process.exit(falhou > 0 ? 1 : 0);
