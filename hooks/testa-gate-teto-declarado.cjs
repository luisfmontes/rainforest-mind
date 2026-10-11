#!/usr/bin/env node
"use strict";
/* Bateria do teto declarado no plano e das liberacoes (Tarefa 7 do plano flaky-teto, D9, D12, D13).
 *
 * O que ela protege: o teto do hook vale o `teto-despachos: N` do cabecalho do plano (40 sem a
 * linha) mais 10 por `liberar-teto` do PROPRIO fluxo, e cabecalho ou liberacao ilegivel NEGA em
 * vez de cair no teto padrao.
 *
 * Entrada: o payload REAL `hooks/fixtures/portaria-folha/payload-da-janela.json` com so `cwd`
 * trocado, e o plano REAL do repo (`docs/rainforest/planos/2026-10-10-flaky-teto.md`) copiado para
 * `docs/rainforest/planos/<slug>.md` do repo-caixa, so com o cabecalho variando. As liberacoes
 * nascem de `estado.cjs liberar-teto` de verdade. O hook roda como PROCESSO, como o harness faz.
 * O contador de despachos e semeado direto no arquivo `despachos.json` (o estado real do hook)
 * para nao lancar 60 processos por caso. Nenhum caso le o texto do fonte do hook.
 *
 * Saida final: `ok: N   falhou: M`. Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "gate-teto-despachos.cjs");
const ESTADO = path.join(__dirname, "..", "scripts", "estado.cjs");
const LEITOR = path.join(__dirname, "lib", "teto-despachos.cjs");
const FIXTURE_JANELA = path.join(__dirname, "fixtures", "portaria-folha", "payload-da-janela.json");
const PLANO_REAL = path.join(__dirname, "..", "docs", "rainforest", "planos", "2026-10-10-flaky-teto.md");
const SLUG = "2026-10-10-x";
const OUTRO_SLUG = "2026-10-10-outro";

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

function envDe(repo) {
  return { ...process.env, CLAUDE_PROJECT_DIR: repo, RFM_ROOT: dadosDe(repo) };
}

function iniciar(repo, slug) {
  const r = spawnSync(process.execPath, [ESTADO, "iniciar", "--slug", slug], {
    cwd: repo,
    encoding: "utf8",
    env: { ...envDe(repo), RFM_ESTADO_ROOT: repo },
  });
  if (r.status !== 0) throw new Error(`estado.cjs iniciar falhou: ${r.stdout}${r.stderr}`);
}

/* Repo-caixa na branch `fluxo/x` com o estado aberto `<SLUG>.json` criado por `estado.cjs iniciar`. */
function caixa(slugsExtras = []) {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "teto-declarado-"));
  caixas.push(repo);
  git(repo, "init", "-q", "-b", "main");
  git(repo, "config", "user.email", "teste@teste");
  git(repo, "config", "user.name", "Teste");
  fs.writeFileSync(path.join(repo, "README"), "teste\n", "utf8");
  git(repo, "add", "README");
  git(repo, "commit", "-q", "-m", "inicial");
  iniciar(repo, SLUG);
  for (const s of slugsExtras) iniciar(repo, s);
  git(repo, "checkout", "-q", "-b", "fluxo/x");
  return repo;
}

function arquivoPlano(repo, slug = SLUG) {
  return path.join(repo, "docs", "rainforest", "planos", `${slug}.md`);
}

/* Plano REAL do repo no lugar do plano do fluxo; `linhaCabecalho` entra entre o titulo e o
 * primeiro `## `. `rodape`: texto acrescentado depois do primeiro `## ` (ja na parte do corpo). */
function gravarPlano(repo, linhaCabecalho, rodape) {
  const real = fs.readFileSync(PLANO_REAL, "utf8");
  const linhas = real.split(/\r?\n/);
  const iTitulo = linhas.findIndex((l) => l.startsWith("# "));
  if (iTitulo === -1) throw new Error("plano real sem titulo");
  const antes = linhas.slice(0, iTitulo + 1);
  const depois = linhas.slice(iTitulo + 1);
  const extra = linhaCabecalho === undefined ? [] : Array.isArray(linhaCabecalho) ? linhaCabecalho : [linhaCabecalho];
  let texto = [...antes, ...extra, ...depois].join("\n");
  if (rodape) texto += `\n${rodape}\n`;
  fs.mkdirSync(path.dirname(arquivoPlano(repo)), { recursive: true });
  fs.writeFileSync(arquivoPlano(repo), texto, "utf8");
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

function janela(repo) {
  const p = JSON.parse(fs.readFileSync(FIXTURE_JANELA, "utf8"));
  p.cwd = repo;
  return p;
}

function rodar(repo) {
  return spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(janela(repo)),
    encoding: "utf8",
    env: envDe(repo),
  });
}

function arquivoContador(repo) {
  return path.join(dadosDe(repo), "fluxos", SLUG, "despachos.json");
}

function contador(repo) {
  const p = arquivoContador(repo);
  if (!fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, "utf8")).total;
}

function semarContador(repo, total) {
  const p = arquivoContador(repo);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, `${JSON.stringify({ total })}\n`, "utf8");
}

function liberarTeto(repo, slug, motivo) {
  return spawnSync(process.execPath, [ESTADO, "liberar-teto", "--slug", slug, "--motivo", motivo], {
    cwd: repo,
    encoding: "utf8",
    env: { ...envDe(repo), RFM_ESTADO_ROOT: repo },
  });
}

/* Com o contador em `antes`, a chamada seguinte passa e a outra, em seguida, nega. */
function passaDepoisNega(repo, antes) {
  semarContador(repo, antes);
  const a = rodar(repo);
  const b = rodar(repo);
  return { a, b, total: contador(repo) };
}

const sep = path.sep;

function main() {
  // == 1. sem plano o teto e 40 ==
  console.log("== 1. sem plano o teto e 40 (a 40a passa, a 41a nega) ==");
  {
    const repo = caixa();
    const { a, b, total } = passaDepoisNega(repo, 39);
    caso("sem plano a 40a chamada sai 0", a.status === 0, `exit=${a.status} ${a.stderr}`);
    caso("sem plano a 41a chamada sai 2", b.status === 2, `exit=${b.status} ${b.stderr}`);
    caso("sem plano o total para em 40", total === 40, `total=${total}`);
  }

  // == 2. plano sem a linha: tambem 40 ==
  console.log("== 2. plano real sem a linha teto-despachos: o teto segue 40 ==");
  {
    const repo = caixa();
    gravarPlano(repo);
    const { a, b } = passaDepoisNega(repo, 39);
    caso("plano sem a linha: a 40a passa", a.status === 0, `exit=${a.status} ${a.stderr}`);
    caso("plano sem a linha: a 41a nega", b.status === 2, `exit=${b.status} ${b.stderr}`);
  }

  // == 3. teto-despachos: 5 ==
  console.log("== 3. teto-despachos: 5 entre o titulo e o primeiro ## ==");
  {
    const repo = caixa();
    gravarPlano(repo, "teto-despachos: 5");
    let saidas = [];
    for (let n = 1; n <= 6; n++) saidas.push(rodar(repo));
    caso("a 1a a 5a chamadas saem 0", saidas.slice(0, 5).every((r) => r.status === 0), saidas.map((r) => r.status).join(","));
    caso("a 6a chamada sai 2", saidas[5].status === 2, `exit=${saidas[5].status} ${saidas[5].stderr}`);
    caso("a negacao cita o teto 5 e o contador 5", /teto e 5\b/.test(saidas[5].stderr) && /admitiu 5\b/.test(saidas[5].stderr), saidas[5].stderr);
    caso("o total fica em 5", contador(repo) === 5, `total=${contador(repo)}`);
  }

  // == 4. cabecalho ilegivel nega, mesmo com o contador em zero ==
  console.log("== 4. cabecalho ilegivel: exit 2 citando o caminho do plano e o texto lido ==");
  const ruins = [
    ["abc", "teto-despachos: abc", "abc"],
    ["0", "teto-despachos: 0", "0"],
    ["-1", "teto-despachos: -1", "-1"],
    ["1.5", "teto-despachos: 1.5", "1.5"],
    ["5 despachos", "teto-despachos: 5 despachos", "5 despachos"],
    ["10000", "teto-despachos: 10000", "10000"],
    ["vazio", "teto-despachos:", ""],
    ["duas linhas", ["teto-despachos: 5", "teto-despachos: 6"], "teto-despachos: 6"],
  ];
  for (const [rotulo, linhas, lido] of ruins) {
    const repo = caixa();
    gravarPlano(repo, linhas);
    const r = rodar(repo);
    caso(`teto-despachos ${rotulo}: sai 2 (nunca 1)`, r.status === 2, `exit=${r.status} ${r.stderr}`);
    caso(
      `teto-despachos ${rotulo}: cita o caminho do plano`,
      r.stderr.includes(`planos${sep}${SLUG}.md`),
      r.stderr
    );
    caso(`teto-despachos ${rotulo}: cita o texto lido`, r.stderr.includes(JSON.stringify(lido)) || r.stderr.includes(lido), r.stderr);
    caso(`teto-despachos ${rotulo}: nao conta o despacho (contador em zero)`, contador(repo) === null, `total=${contador(repo)}`);
  }

  // == 5. a linha depois do primeiro ## e ignorada ==
  console.log("== 5. a mesma linha depois do primeiro ## e ignorada (teto 40) ==");
  {
    const repo = caixa();
    gravarPlano(repo, undefined, "teto-despachos: 5\nteto-despachos: abc");
    const { a, b } = passaDepoisNega(repo, 39);
    caso("linha depois do primeiro ##: a 40a passa", a.status === 0, `exit=${a.status} ${a.stderr}`);
    caso("linha depois do primeiro ##: a 41a nega", b.status === 2, `exit=${b.status} ${b.stderr}`);
    const repo2 = caixa();
    gravarPlano(repo2, undefined, "teto-despachos: 5");
    semarContador(repo2, 5);
    const r = rodar(repo2);
    caso("linha valida depois do primeiro ## nao baixa o teto (6a passa)", r.status === 0, `exit=${r.status} ${r.stderr}`);
  }

  // == 6. plano que existe e nao e arquivo legivel ==
  console.log("== 6. plano que existe mas nao e arquivo legivel nega ==");
  {
    const repo = caixa();
    fs.mkdirSync(arquivoPlano(repo), { recursive: true }); // uma PASTA no lugar do arquivo
    const r = rodar(repo);
    caso("plano que e pasta: sai 2", r.status === 2, `exit=${r.status} ${r.stderr}`);
    caso("plano que e pasta: cita o caminho do plano", r.stderr.includes(`planos${sep}${SLUG}.md`), r.stderr);
    caso("plano que e pasta: nao conta o despacho", contador(repo) === null, `total=${contador(repo)}`);
  }

  // == 7. liberar-teto ==
  console.log("== 7. liberar-teto soma 10 e a segunda soma mais 10 ==");
  {
    const repo = caixa();
    const l1 = liberarTeto(repo, SLUG, "Luis: fluxo grande, segue");
    caso("liberar-teto grava a 1a liberacao (exit 0)", l1.status === 0, `exit=${l1.status} ${l1.stderr}`);
    const p1 = passaDepoisNega(repo, 49);
    caso("depois de uma liberacao a 50a passa", p1.a.status === 0, `exit=${p1.a.status} ${p1.a.stderr}`);
    caso("depois de uma liberacao a 51a nega", p1.b.status === 2, `exit=${p1.b.status} ${p1.b.stderr}`);
    caso("depois de uma liberacao o total para em 50", p1.total === 50, `total=${p1.total}`);
    const l2 = liberarTeto(repo, SLUG, "Luis: mais uma volta");
    caso("liberar-teto grava a 2a liberacao (exit 0)", l2.status === 0, `exit=${l2.status} ${l2.stderr}`);
    const p2 = passaDepoisNega(repo, 59);
    caso("depois de duas liberacoes a 60a passa", p2.a.status === 0, `exit=${p2.a.status} ${p2.a.stderr}`);
    caso("depois de duas liberacoes a 61a nega", p2.b.status === 2, `exit=${p2.b.status} ${p2.b.stderr}`);
    caso("depois de duas liberacoes o total para em 60", p2.total === 60, `total=${p2.total}`);
  }

  // == 8. teto declarado + liberacao ==
  console.log("== 8. teto declarado 5 e uma liberacao: 15 ==");
  {
    const repo = caixa();
    gravarPlano(repo, "teto-despachos: 5");
    liberarTeto(repo, SLUG, "Luis: segue");
    const { a, b } = passaDepoisNega(repo, 14);
    caso("declarado 5 + 1 liberacao: a 15a passa", a.status === 0, `exit=${a.status} ${a.stderr}`);
    caso("declarado 5 + 1 liberacao: a 16a nega", b.status === 2, `exit=${b.status} ${b.stderr}`);
  }

  // == 9. liberacao de outro slug ==
  console.log("== 9. a liberacao de outro slug nao vale para este ==");
  {
    const repo = caixa([OUTRO_SLUG]);
    const l = liberarTeto(repo, OUTRO_SLUG, "Luis: so para o outro");
    caso("a liberacao do outro slug foi gravada", l.status === 0, `exit=${l.status} ${l.stderr}`);
    const { a, b } = passaDepoisNega(repo, 39);
    caso("com liberacao so do outro slug a 40a passa", a.status === 0, `exit=${a.status} ${a.stderr}`);
    caso("com liberacao so do outro slug a 41a nega", b.status === 2, `exit=${b.status} ${b.stderr}`);
  }

  // == 10. liberacoes malformadas ==
  console.log("== 10. teto_despachos.liberacoes malformado nega com exit 2 ==");
  const malformados = [
    ['"x"', "x"],
    ["[{}]", [{}]],
    ['[{"motivo":""}]', [{ motivo: "" }]],
    ["[{motivo:\"   \"}]", [{ motivo: "   " }]],
    ["[null]", [null]],
    ["objeto", { motivo: "a" }],
  ];
  for (const [rotulo, valor] of malformados) {
    const repo = caixa();
    editarEstado(repo, (e) => {
      e.teto_despachos = { liberacoes: valor };
    });
    const r = rodar(repo);
    caso(`liberacoes ${rotulo}: sai 2 (nunca 1)`, r.status === 2, `exit=${r.status} ${r.stderr}`);
    caso(`liberacoes ${rotulo}: nao conta o despacho`, contador(repo) === null, `total=${contador(repo)}`);
  }
  {
    const repo = caixa();
    editarEstado(repo, (e) => {
      e.teto_despachos = "x";
    });
    const r = rodar(repo);
    caso("teto_despachos que nao e objeto: sai 2", r.status === 2, `exit=${r.status} ${r.stderr}`);
  }

  // == 11. o leitor sem disco ==
  console.log("== 11. lerTetoDeclarado: mesma resposta para o mesmo texto, sem ler disco ==");
  {
    const { lerTetoDeclarado } = require(LEITOR);
    const t = (s) => lerTetoDeclarado(s);
    caso("sem a linha devolve { teto: 40 }", t("# Plano\n\n## A\n").teto === 40);
    caso("com CRLF le teto-despachos: 7", t("# Plano\r\nteto-despachos: 7\r\n\r\n## A\r\n").teto === 7);
    caso("valor ilegivel devolve { erro } sem teto", Boolean(t("# P\nteto-despachos: abc\n").erro) && t("# P\nteto-despachos: abc\n").teto === undefined);
    caso("texto que nao e string devolve { erro }", Boolean(lerTetoDeclarado(undefined).erro));
  }

  for (const repo of caixas) fs.rmSync(repo, { recursive: true, force: true });
  console.log(`\nok: ${ok}   falhou: ${falhou}`);
  process.exit(falhou === 0 ? 0 : 1);
}

try {
  main();
} catch (err) {
  console.log(`ERRO na bateria: ${err && err.stack ? err.stack : err}`);
  for (const repo of caixas) fs.rmSync(repo, { recursive: true, force: true });
  process.exit(1);
}
