#!/usr/bin/env node
"use strict";
/* Bateria do teto de despachos (Tarefa 2 do plano flaky-teto, D5, D9-D12, D15-D17).
 *
 * O que ela protege: o hook conta todo despacho do fluxo ativo, nega a partir do
 * 41o com exit 2, e NUNCA le contador ruim como zero (o defeito do `ceiling-check.sh`
 * do plugin de origem, que zerava o teto em silencio).
 *
 * Entrada: os payloads REAIS capturados ao vivo (`hooks/fixtures/portaria-folha/`),
 * trocando so `cwd`. Nenhum campo inventado. O hook roda como PROCESSO REAL com o
 * payload no stdin, como o harness faz; importar funcao provaria a funcao, nao o
 * caminho que o harness exercita.
 *
 * Isolamento: cada caso cria um repo git PROPRIO num mkdtemp, com `RFM_ROOT` dentro
 * dele. Nunca escreve no repo do plugin nem em `~/.rainforest`. O estado do fluxo
 * nasce de `estado.cjs iniciar` de verdade.
 *
 * Saida final: `ok: N   falhou: M`. Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const { spawn, spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "gate-teto-despachos.cjs");
const ESTADO = path.join(__dirname, "..", "scripts", "estado.cjs");
const FIXTURE_JANELA = path.join(__dirname, "fixtures", "portaria-folha", "payload-da-janela.json");
const FIXTURE_SUBAGENTE = path.join(__dirname, "fixtures", "portaria-folha", "payload-de-subagente.json");
const SLUG = "2026-10-10-x";

let ok = 0;
let falhou = 0;
const caixas = [];

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 500)}` : ""}`);
  }
}

function git(repo, ...args) {
  return spawnSync("git", args, { cwd: repo, encoding: "utf8" });
}

function dadosDe(repo) {
  return path.join(repo, ".dados-do-teste");
}

function envDe(repo, extra) {
  return { ...process.env, CLAUDE_PROJECT_DIR: repo, RFM_ROOT: dadosDe(repo), ...(extra || {}) };
}

/* Repo-caixa na branch `fluxo/<nome>` com o estado aberto `<slug>.json` criado por
 * `estado.cjs iniciar` (estagio `design` aberto). `opcoes.semEstado`: nao cria. */
function caixa(opcoes = {}) {
  const nome = opcoes.nome || "x";
  const slug = opcoes.slug || SLUG;
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "teto-despachos-"));
  caixas.push(repo);
  git(repo, "init", "-q", "-b", "main");
  git(repo, "config", "user.email", "teste@teste");
  git(repo, "config", "user.name", "Teste");
  fs.writeFileSync(path.join(repo, "README"), "teste\n", "utf8");
  git(repo, "add", "README");
  git(repo, "commit", "-q", "-m", "inicial");
  if (!opcoes.semEstado) {
    const r = spawnSync(process.execPath, [ESTADO, "iniciar", "--slug", slug], {
      cwd: repo,
      encoding: "utf8",
      env: { ...envDe(repo), RFM_ESTADO_ROOT: repo },
    });
    if (r.status !== 0) throw new Error(`estado.cjs iniciar falhou: ${r.stdout}${r.stderr}`);
  }
  git(repo, "checkout", "-q", "-b", `fluxo/${nome}`);
  return repo;
}

function arquivoEstado(repo, slug = SLUG) {
  return path.join(repo, "docs", "rainforest", "estado", `${slug}.json`);
}

function editarEstado(repo, fn, slug = SLUG) {
  const p = arquivoEstado(repo, slug);
  const e = JSON.parse(fs.readFileSync(p, "utf8"));
  fn(e);
  fs.writeFileSync(p, `${JSON.stringify(e, null, 2)}\n`, "utf8");
}

function payload(fixture, repo, trocas) {
  const p = JSON.parse(fs.readFileSync(fixture, "utf8"));
  p.cwd = repo;
  return Object.assign(p, trocas || {});
}

function rodar(repo, p, extraEnv, entradaBruta) {
  return spawnSync(process.execPath, [HOOK], {
    input: entradaBruta !== undefined ? entradaBruta : JSON.stringify(p),
    encoding: "utf8",
    env: envDe(repo, extraEnv),
  });
}

function janela(repo, trocas) {
  return payload(FIXTURE_JANELA, repo, trocas);
}

function arquivoContador(repo, slug = SLUG) {
  return path.join(dadosDe(repo), "fluxos", slug, "despachos.json");
}

function contador(repo, slug = SLUG) {
  const p = arquivoContador(repo, slug);
  if (!fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, "utf8")).total;
}

function semarContador(repo, conteudo, slug = SLUG) {
  const p = arquivoContador(repo, slug);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, conteudo, "utf8");
}

function naoCriouPasta(repo) {
  return !fs.existsSync(path.join(dadosDe(repo), "fluxos"));
}

function rodarAssincrono(repo, p) {
  return new Promise((resolve) => {
    const filho = spawn(process.execPath, [HOOK], { env: envDe(repo), stdio: ["pipe", "pipe", "pipe"] });
    let err = "";
    filho.stderr.on("data", (d) => (err += d));
    filho.on("close", (status) => resolve({ status, stderr: err }));
    filho.stdin.end(JSON.stringify(p));
  });
}

/* Detalhe de um lote de processos: os que sairam != 0 com indice, exit e stderr
 * aparado; depois a lista de exits. Sem falha, devolve so a lista de exits (o de hoje). */
function detalheDosProcessos(rs) {
  const sts = rs.map((r) => r.status).join(",");
  const falhas = rs
    .map((r, i) => ({ r, i }))
    .filter(({ r }) => r.status !== 0)
    .map(({ r, i }) => `[processo ${i}] exit=${r.status} stderr=${String(r.stderr).trim().slice(0, 200)}`);
  return falhas.length ? `${falhas.join(" | ")} | exits=${sts}` : sts;
}

async function main() {
  // == 1. 40 admitidos, o 41o nega ==
  console.log("== 1. ate a 40a sai 0 e conta; a 41a sai 2 citando slug, teto e contador ==");
  {
    const repo = caixa();
    let todosZero = true;
    let contagemCerta = true;
    let detalheFalha = "";
    for (let n = 1; n <= 40; n++) {
      const r = rodar(repo, janela(repo));
      if (r.status !== 0) {
        todosZero = false;
        detalheFalha = `chamada ${n}: exit=${r.status} ${r.stderr}`;
        break;
      }
      if (contador(repo) !== n) {
        contagemCerta = false;
        detalheFalha = `chamada ${n}: total=${contador(repo)}`;
        break;
      }
    }
    caso("as 40 primeiras chamadas saem 0", todosZero, detalheFalha);
    caso("cada chamada deixa despachos.json com total igual ao numero da chamada", contagemCerta, detalheFalha);
    const r41 = rodar(repo, janela(repo));
    caso("a 41a chamada sai 2 (nunca 1)", r41.status === 2, `exit=${r41.status} ${r41.stderr}`);
    caso("a 41a cita o slug", r41.stderr.includes(SLUG), r41.stderr);
    caso("a 41a cita o teto 40", /\b40\b/.test(r41.stderr), r41.stderr);
    caso("a 41a cita o contador (ja admitiu 40)", /admitiu 40\b/.test(r41.stderr), r41.stderr);
    caso("o total continua 40 depois da negacao", contador(repo) === 40, `total=${contador(repo)}`);
    caso("a negacao dada a janela cita liberar-teto", r41.stderr.includes("liberar-teto"), r41.stderr);
  }

  // == 2. estagio executar aberto tambem conta ==
  console.log("== 2. conta com executar aberto ==");
  {
    const repo = caixa();
    editarEstado(repo, (e) => {
      e.design.status = "aprovado";
      e.plano.status = "ok";
    });
    const r = rodar(repo, janela(repo));
    caso("com design e plano fechados (executar aberto) a chamada sai 0", r.status === 0, `exit=${r.status} ${r.stderr}`);
    caso("com executar aberto o total vira 1", contador(repo) === 1, `total=${contador(repo)}`);
  }

  // == 3. passa sem contar e sem criar a pasta fluxos/ ==
  console.log("== 3. fora de fluxo passa sem contar e sem criar fluxos/ ==");
  {
    const repo = caixa();
    git(repo, "checkout", "-q", "-b", "outra-coisa");
    const r = rodar(repo, janela(repo));
    caso("branch sem fluxo passa (exit 0)", r.status === 0, `exit=${r.status} ${r.stderr}`);
    caso("branch sem fluxo nao cria fluxos/", naoCriouPasta(repo));
  }
  {
    const repo = caixa({ semEstado: true });
    const r = rodar(repo, janela(repo));
    caso("repo sem docs/rainforest/estado/ passa (exit 0)", r.status === 0, `exit=${r.status} ${r.stderr}`);
    caso("repo sem docs/rainforest/estado/ nao cria fluxos/", naoCriouPasta(repo));
  }
  {
    const repo = caixa();
    fs.copyFileSync(arquivoEstado(repo), arquivoEstado(repo, "2026-10-11-x"));
    const r = rodar(repo, janela(repo));
    caso("dois estados abertos que casam com a mesma branch passam (exit 0)", r.status === 0, `exit=${r.status} ${r.stderr}`);
    caso("dois estados abertos que casam com a mesma branch nao criam fluxos/", naoCriouPasta(repo));
  }
  {
    const repo = caixa();
    editarEstado(repo, (e) => {
      e.design.status = "aprovado";
      for (const est of ["plano", "executar", "revisar", "verificar", "fechar"]) e[est].status = "ok";
    });
    const r = rodar(repo, janela(repo));
    caso("fluxo com todos os estagios fechados passa (exit 0)", r.status === 0, `exit=${r.status} ${r.stderr}`);
    caso("fluxo com todos os estagios fechados nao cria fluxos/", naoCriouPasta(repo));
  }
  {
    const repo = caixa();
    const r = rodar(repo, janela(repo, { tool_name: "Bash" }));
    caso("tool_name Bash passa (exit 0)", r.status === 0, `exit=${r.status} ${r.stderr}`);
    caso("tool_name Bash nao cria fluxos/", naoCriouPasta(repo));
  }
  {
    const repo = caixa();
    const r1 = rodar(repo, null, {}, "");
    caso("stdin vazio passa (exit 0)", r1.status === 0, `exit=${r1.status} ${r1.stderr}`);
    const r2 = rodar(repo, null, {}, "{isto nao e json");
    caso("stdin com JSON invalido passa (exit 0)", r2.status === 0, `exit=${r2.status} ${r2.stderr}`);
    caso("stdin vazio e JSON invalido nao criam fluxos/", naoCriouPasta(repo));
  }

  // == 4. contadores separados por slug ==
  console.log("== 4. dois repos com slugs diferentes mantem contadores separados ==");
  {
    const a = caixa({ nome: "x", slug: "2026-10-10-x" });
    const b = caixa({ nome: "y", slug: "2026-10-10-y" });
    const dados = dadosDe(a);
    const env = { RFM_ROOT: dados };
    rodar(a, janela(a), env);
    rodar(a, janela(a), env);
    rodar(b, janela(b), env);
    const lido = (slug) => JSON.parse(fs.readFileSync(path.join(dados, "fluxos", slug, "despachos.json"), "utf8")).total;
    caso("o slug x tem total 2", lido("2026-10-10-x") === 2);
    caso("o slug y tem total 1 (raiz de dados dividida, slug diferente)", lido("2026-10-10-y") === 1);
  }

  // == 5. subagente (agent_id) conta igual; so a janela ve liberar-teto ==
  console.log("== 5. payload de subagente conta igual e nao recebe o comando liberar-teto ==");
  {
    const repo = caixa();
    const r = rodar(repo, payload(FIXTURE_SUBAGENTE, repo));
    caso("payload de subagente (agent_id) sai 0 e conta", r.status === 0 && contador(repo) === 1, `exit=${r.status} total=${contador(repo)} ${r.stderr}`);
    semarContador(repo, '{"total":40}\n');
    const rs = rodar(repo, payload(FIXTURE_SUBAGENTE, repo));
    caso("subagente no teto sai 2", rs.status === 2, `exit=${rs.status} ${rs.stderr}`);
    caso("a negacao dada ao subagente nao cita liberar-teto", !rs.stderr.includes("liberar-teto"), rs.stderr);
    caso("a negacao dada ao subagente ainda cita o slug", rs.stderr.includes(SLUG), rs.stderr);
    const rj = rodar(repo, janela(repo));
    caso("a negacao dada a janela cita liberar-teto", rj.status === 2 && rj.stderr.includes("liberar-teto"), `exit=${rj.status} ${rj.stderr}`);
  }

  // == 6. contador ilegivel nega, sem reescrever ==
  console.log("== 6. contador com total invalido nega com exit 2 e nao reescreve ==");
  const ruins = ["", "{", "[]", "null", "{}", '{"total":"7"}', '{"total":-1}', '{"total":1.5}', '{"total":1e400}'];
  for (const conteudo of ruins) {
    const repo = caixa();
    semarContador(repo, conteudo);
    const r = rodar(repo, janela(repo));
    const intacto = fs.readFileSync(arquivoContador(repo), "utf8") === conteudo;
    caso(`contador com total invalido nega: ${JSON.stringify(conteudo)} sai 2 (nunca 1)`, r.status === 2, `exit=${r.status} ${r.stderr}`);
    caso(`contador com total invalido nega: ${JSON.stringify(conteudo)} nao reescreve o arquivo`, intacto);
    caso(`contador com total invalido nega: ${JSON.stringify(conteudo)} cita o slug`, r.stderr.includes(SLUG), r.stderr);
  }
  {
    const repo = caixa();
    fs.writeFileSync(dadosDe(repo), "isto e um arquivo, nao uma pasta\n", "utf8");
    const r = rodar(repo, janela(repo));
    caso("RFM_ROOT apontando para um arquivo nega com exit 2 (nunca 1)", r.status === 2, `exit=${r.status} ${r.stderr}`);
  }

  // == 7. concorrencia ==
  console.log("== 7. 12 processos juntos ==");
  {
    const repo = caixa();
    const rs = await Promise.all(Array.from({ length: 12 }, () => rodarAssincrono(repo, janela(repo))));
    caso("12 processos lancados juntos saem todos 0", rs.every((r) => r.status === 0), detalheDosProcessos(rs));
    caso("12 processos lancados juntos terminam com total 12", contador(repo) === 12, `total=${contador(repo)}`);
  }
  {
    const repo = caixa();
    semarContador(repo, '{"total":36}\n');
    const rs = await Promise.all(Array.from({ length: 12 }, () => rodarAssincrono(repo, janela(repo))));
    const zero = rs.filter((r) => r.status === 0).length;
    const dois = rs.filter((r) => r.status === 2).length;
    caso("com o contador em 36, exatamente 4 dos 12 saem 0", zero === 4, detalheDosProcessos(rs));
    caso("com o contador em 36, exatamente 8 dos 12 saem 2", dois === 8, detalheDosProcessos(rs));
    caso("com o contador em 36, o total termina em 40", contador(repo) === 40, `total=${contador(repo)}`);
  }

  // == 8. sem escape (D15) ==
  console.log("== 8. sem escape: RAINFOREST_GATE_OFF e a chave teto-despachos desligada nao abrem a 41a ==");
  {
    const repo = caixa();
    semarContador(repo, '{"total":40}\n');
    fs.mkdirSync(path.join(repo, ".rainforest"), { recursive: true });
    fs.writeFileSync(path.join(repo, ".rainforest", "config.json"), '{"teto-despachos": false}\n', "utf8");
    fs.writeFileSync(path.join(dadosDe(repo), "config.json"), '{"teto-despachos": false}\n', "utf8");
    const r = rodar(repo, janela(repo), { RAINFOREST_GATE_OFF: "1" });
    caso("sem escape: com RAINFOREST_GATE_OFF=1 e a chave teto-despachos desligada, a 41a sai 2", r.status === 2, `exit=${r.status} ${r.stderr}`);
    caso("sem escape: o total continua 40", contador(repo) === 40, `total=${contador(repo)}`);
  }

  // == 9. agente fora do manifesto conta (D17) ==
  console.log("== 9. agente fora do manifesto conta ==");
  {
    const manifesto = fs.readFileSync(path.join(__dirname, "..", ".rainforest", "agentes.padrao.json"), "utf8");
    const fora = "agente-que-nao-esta-no-manifesto";
    caso("controle: o subagent_type do caso nao esta no manifesto padrao", !manifesto.includes(fora));
    const repo = caixa();
    const p = janela(repo);
    p.tool_input = { ...p.tool_input, subagent_type: fora };
    const r = rodar(repo, p);
    caso("agente fora do manifesto conta: sai 0", r.status === 0, `exit=${r.status} ${r.stderr}`);
    caso("agente fora do manifesto conta: total vira 1", contador(repo) === 1, `total=${contador(repo)}`);
  }

  // == 10. trava ocupada por mais de 10 s nega ==
  console.log("== 10. trava ocupada por mais de 10 s nega ==");
  {
    const repo = caixa();
    const dir = path.dirname(arquivoContador(repo));
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, ".despachos.lock"), `${process.pid} ${new Date().toISOString()}\n`, "utf8");
    const t0 = Date.now();
    const r = rodar(repo, janela(repo));
    const seg = (Date.now() - t0) / 1000;
    caso("trava ocupada por dono vivo nega com exit 2 (nunca 1)", r.status === 2, `exit=${r.status} ${r.stderr}`);
    caso("trava ocupada espera ao menos 10 s antes de negar", seg >= 9.5, `esperou ${seg}s`);
    caso("trava ocupada nao conta o despacho", contador(repo) === null, `total=${contador(repo)}`);
  }

  // == 11. registro no hooks.json ==
  console.log("== 11. hooks.json registra o hook uma vez, no grupo Task|Agent da portaria ==");
  {
    const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, "hooks.json"), "utf8"));
    const grupos = cfg.hooks.PreToolUse;
    const usa = (g, nome) => g.hooks.some((h) => String(h.command).includes(nome));
    const comTeto = grupos.filter((g) => usa(g, "gate-teto-despachos.cjs"));
    const total = grupos.flatMap((g) => g.hooks).filter((h) => String(h.command).includes("gate-teto-despachos.cjs")).length;
    caso("hooks.json registra o hook uma vez", total === 1, `registros=${total}`);
    caso("o registro esta no grupo de matcher Task|Agent", comTeto.length === 1 && comTeto[0].matcher === "Task|Agent");
    caso("o grupo do registro e o da portaria.cjs", comTeto.length === 1 && usa(comTeto[0], "portaria.cjs"));
  }

  // == 13. negacao do teto proporcional: conta cumulativa e tarefas do plano (D5, #612) ==
  console.log("== 13. plano de 43 tarefas: a negacao diz conta cumulativa e tarefas do plano: 43 ==");
  {
    const repo = caixa();
    fs.mkdirSync(path.join(repo, "docs", "rainforest", "planos"), { recursive: true });
    const tarefas = Array.from({ length: 43 }, (_, i) => `### ${i + 1}. tarefa sintetica ${i + 1} [tipo: implementar]\n\ncorpo\n`);
    fs.writeFileSync(
      path.join(repo, "docs", "rainforest", "planos", `${SLUG}.md`),
      ["# Plano sintetico", "", "## Tarefas", "", ...tarefas].join("\n"),
      "utf8"
    );
    semarContador(repo, '{"total":65}\n');
    const r66 = rodar(repo, janela(repo));
    caso("plano de 43 tarefas: a 66a nega com exit 2", r66.status === 2, `exit=${r66.status} ${r66.stderr}`);
    caso("negacao diz conta cumulativa", r66.stderr.includes("conta cumulativa"), r66.stderr);
    caso("negacao diz tarefas do plano: 43", r66.stderr.includes("tarefas do plano: 43"), r66.stderr);
    caso("negacao mostra o teto 65", /o teto e 65 /.test(r66.stderr), r66.stderr);
    caso("total continua 65 depois da negacao", contador(repo) === 65, `total=${contador(repo)}`);
  }

  // == 13b. leitor de tarefas ilegivel: nega com exit 2, nunca cai no teto 40 (D12, achado 3 da revisao 1) ==
  console.log("== 13b. leitor de tarefas ilegivel: nega com exit 2 e nao admite, nunca vira o teto 40 ==");
  {
    const repo = caixa();
    fs.mkdirSync(path.join(repo, "docs", "rainforest", "planos"), { recursive: true });
    const tarefas = Array.from({ length: 3 }, (_, i) => `### ${i + 1}. tarefa sintetica ${i + 1} [tipo: implementar]\n\ncorpo\n`);
    fs.writeFileSync(
      path.join(repo, "docs", "rainforest", "planos", `${SLUG}.md`),
      ["# Plano sintetico", "", "## Tarefas", "", ...tarefas].join("\n"),
      "utf8"
    );
    // Copia de hooks/ e scripts/ com o leitor quebrado: o require de scripts/conferir-fluxo.cjs lanca.
    // O plano tem 3 tarefas, entao o hook precisa ler o leitor; se caisse no teto 40, a chamada sairia 0.
    const sbx = fs.mkdtempSync(path.join(os.tmpdir(), "teto-leitor-ruim-"));
    caixas.push(sbx);
    fs.cpSync(__dirname, path.join(sbx, "hooks"), { recursive: true });
    fs.cpSync(path.join(__dirname, "..", "scripts"), path.join(sbx, "scripts"), { recursive: true });
    fs.writeFileSync(
      path.join(sbx, "scripts", "conferir-fluxo.cjs"),
      'throw new Error("leitor de tarefas ilegivel de proposito");\n',
      "utf8"
    );
    const r = spawnSync(process.execPath, [path.join(sbx, "hooks", "gate-teto-despachos.cjs")], {
      input: JSON.stringify(janela(repo)),
      encoding: "utf8",
      env: envDe(repo),
    });
    caso("leitor ilegivel: a janela sai 2 (nunca 0 pelo teto 40)", r.status === 2, `exit=${r.status} ${r.stderr}`);
    caso("leitor ilegivel: a negacao diz nada foi admitido", (r.stderr || "").includes("nada foi admitido"), r.stderr);
    caso("leitor ilegivel: a negacao nao cita o teto 40", !/o teto e 40\b/.test(r.stderr || ""), r.stderr);
    caso("leitor ilegivel: nenhum despacho foi contado", contador(repo) === null, `total=${contador(repo)}`);
  }

  // == 12. sem raiz de dados, o contador cai no repo e precisa sair do git status ==
  console.log("== 12. sem RFM_ROOT e sem raiz de dados, o contador fica fora do git status ==");
  {
    const repo = caixa();
    fs.copyFileSync(path.join(__dirname, "..", ".gitignore"), path.join(repo, ".gitignore"));
    git(repo, "add", ".gitignore");
    git(repo, "commit", "-q", "-m", "gitignore do repo");
    // HOME vazio e sem RFM_ROOT: nenhum nivel da cadeia de raiz acha dados.
    const casa = fs.mkdtempSync(path.join(os.tmpdir(), "teto-casa-"));
    caixas.push(casa);
    const env = { ...process.env, CLAUDE_PROJECT_DIR: repo, HOME: casa, USERPROFILE: casa, CLAUDE_CONFIG_DIR: casa };
    delete env.RFM_ROOT;
    const r = spawnSync(process.execPath, [HOOK], { input: JSON.stringify(janela(repo)), encoding: "utf8", env });
    caso("sem raiz de dados o hook conta e sai 0", r.status === 0, `exit=${r.status} ${r.stderr}`);
    // Precondicao: o contador caiu no fallback DENTRO do repo, nao no plugin nem na casa.
    const dentro = path.join(repo, ".rainforest", "fluxos", SLUG, "despachos.json");
    caso("precondicao: o contador foi para <repo>/.rainforest/fluxos", fs.existsSync(dentro), `nao existe ${dentro}`);
    const sujo = git(repo, "status", "--porcelain", "-uall").stdout.split("\n").filter((l) => l.includes(".rainforest/fluxos/"));
    caso("git status --porcelain -uall nao lista .rainforest/fluxos/", sujo.length === 0, sujo.join(" | "));
    const ign = git(repo, "check-ignore", "-q", `.rainforest/fluxos/${SLUG}/despachos.json`);
    caso("git check-ignore -q do contador sai 0", ign.status === 0, `exit=${ign.status}`);
  }

  for (const repo of caixas) fs.rmSync(repo, { recursive: true, force: true });
  console.log(`\nok: ${ok}   falhou: ${falhou}`);
  process.exit(falhou === 0 ? 0 : 1);
}

main().catch((err) => {
  console.log(`ERRO na bateria: ${err && err.stack ? err.stack : err}`);
  for (const repo of caixas) fs.rmSync(repo, { recursive: true, force: true });
  process.exit(1);
});
