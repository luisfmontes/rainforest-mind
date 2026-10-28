#!/bin/bash
# Bateria da recusa de `teto-despachos:` ilegivel na `cobertura` (Tarefa 12 do plano flaky-teto, D14).
# Uso: bash scripts/testa-cobertura-teto.sh
#
# O que protege: a `cobertura` do conferir-fluxo.cjs recusa (exit 2) o plano cujo cabecalho
# `teto-despachos:` o hook gate-teto-despachos.cjs negaria, e aceita o que o hook admite. Os dois
# chamam o mesmo `lerTetoDeclarado`; o caso de paridade roda o hook de verdade (processo, com o
# payload real da janela, so `cwd` trocado) e a cobertura sobre o MESMO texto de plano.
# Fixture: design e plano REAIS do trabalho flaky-teto num repo-caixa, so o cabecalho varia.
# Nenhum caso le o texto do fonte. Saida final: `ok: N   falhou: M`.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RAIZ_DO_PLUGIN="$RAIZ"
command -v cygpath >/dev/null 2>&1 && export RAIZ_DO_PLUGIN="$(cygpath -m "$RAIZ")"

node - <<'FIM_DO_NODE'
"use strict";
const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const RAIZ = process.env.RAIZ_DO_PLUGIN;
const CHECADOR = path.join(RAIZ, "scripts", "conferir-fluxo.cjs");
const ESTADO = path.join(RAIZ, "scripts", "estado.cjs");
const HOOK = path.join(RAIZ, "hooks", "gate-teto-despachos.cjs");
const FIXTURE_JANELA = path.join(RAIZ, "hooks", "fixtures", "portaria-folha", "payload-da-janela.json");
const DESIGN_REAL = path.join(RAIZ, "docs", "rainforest", "design", "2026-10-10-flaky-teto.md");
const PLANO_REAL = path.join(RAIZ, "docs", "rainforest", "planos", "2026-10-10-flaky-teto.md");
const SLUG = "2026-10-10-x";

let ok = 0;
let falhou = 0;
const caixas = [];

function caso(nome, cond, detalhe) {
  if (cond) { ok++; console.log(`  ok   ${nome}`); }
  else { falhou++; console.log(`  FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 600)}` : ""}`); }
}

function git(repo, ...args) { return spawnSync("git", args, { cwd: repo, encoding: "utf8" }); }
const dadosDe = (repo) => path.join(repo, ".dados-do-teste");
const envDe = (repo) => ({ ...process.env, CLAUDE_PROJECT_DIR: repo, RFM_ROOT: dadosDe(repo), RFM_ESTADO_ROOT: repo });

function caixa() {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cobertura-teto-"));
  caixas.push(repo);
  git(repo, "init", "-q", "-b", "main");
  git(repo, "config", "user.email", "teste@teste");
  git(repo, "config", "user.name", "Teste");
  fs.writeFileSync(path.join(repo, "README"), "teste\n", "utf8");
  git(repo, "add", "README");
  git(repo, "commit", "-q", "-m", "inicial");
  const r = spawnSync(process.execPath, [ESTADO, "iniciar", "--slug", SLUG], { cwd: repo, encoding: "utf8", env: envDe(repo) });
  if (r.status !== 0) throw new Error(`estado.cjs iniciar falhou: ${r.stdout}${r.stderr}`);
  git(repo, "checkout", "-q", "-b", "fluxo/x");
  fs.mkdirSync(path.join(repo, "docs", "rainforest", "design"), { recursive: true });
  fs.mkdirSync(path.join(repo, "docs", "rainforest", "planos"), { recursive: true });
  fs.copyFileSync(DESIGN_REAL, path.join(repo, "docs", "rainforest", "design", `${SLUG}.md`));
  return repo;
}

const arquivoPlano = (repo) => path.join(repo, "docs", "rainforest", "planos", `${SLUG}.md`);

// `cabecalho`: linha(s) entre o titulo e o primeiro `## `; `rodape`: texto depois do primeiro `## `.
function gravarPlano(repo, cabecalho, rodape) {
  const linhas = fs.readFileSync(PLANO_REAL, "utf8").split(/\r?\n/);
  const i = linhas.findIndex((l) => l.startsWith("# "));
  const extra = cabecalho === undefined ? [] : Array.isArray(cabecalho) ? cabecalho : [cabecalho];
  let texto = [...linhas.slice(0, i + 1), ...extra, ...linhas.slice(i + 1)].join("\n");
  if (rodape) texto += `\n${rodape}\n`;
  fs.writeFileSync(arquivoPlano(repo), texto, "utf8");
}

function cobertura(repo) {
  return spawnSync(process.execPath, [CHECADOR, "cobertura", "--slug", SLUG], { cwd: repo, encoding: "utf8", env: envDe(repo) });
}

function hook(repo) {
  const p = JSON.parse(fs.readFileSync(FIXTURE_JANELA, "utf8"));
  p.cwd = repo;
  return spawnSync(process.execPath, [HOOK], { input: JSON.stringify(p), encoding: "utf8", env: envDe(repo) });
}

const recusa = (r, texto) => r.status === 2 && r.stderr.includes("teto-despachos") && r.stderr.includes(arquivoPlanoCitado) && r.stderr.includes(texto);
let arquivoPlanoCitado = "";

const RUINS = [
  ["abc", "teto-despachos: abc", "abc"],
  ["0", "teto-despachos: 0", "0"],
  ["-1", "teto-despachos: -1", "-1"],
  ["1.5", "teto-despachos: 1.5", "1.5"],
  ["10000", "teto-despachos: 10000", "10000"],
];

try {
  console.log("== recusa na cobertura (exit 2, citando o texto lido e o caminho do plano) ==");
  for (const [rotulo, linha, lido] of RUINS) {
    const repo = caixa();
    gravarPlano(repo, linha);
    arquivoPlanoCitado = arquivoPlano(repo);
    const r = cobertura(repo);
    caso(`teto-despachos: ${rotulo} recusa na cobertura`, recusa(r, JSON.stringify(lido)), `exit=${r.status} stderr=${r.stderr}`);
  }
  {
    const repo = caixa();
    gravarPlano(repo, "teto-despachos:");
    arquivoPlanoCitado = arquivoPlano(repo);
    const r = cobertura(repo);
    caso("teto-despachos: valor vazio recusa na cobertura", recusa(r, '""'), `exit=${r.status} stderr=${r.stderr}`);
  }
  {
    const repo = caixa();
    gravarPlano(repo, ["teto-despachos: 5", "teto-despachos: 7"]);
    arquivoPlanoCitado = arquivoPlano(repo);
    const r = cobertura(repo);
    caso("duas linhas teto-despachos: recusam na cobertura", recusa(r, "2 linhas"), `exit=${r.status} stderr=${r.stderr}`);
  }

  console.log("== aviso: declarado menor que as tarefas do plano, sem mudar o exit (D5, #612) ==");
  // Plano real (12 tarefas) + 31 cabecalhos = 43 tarefas. Os extras nao tem atende/mutacao, entao a
  // cobertura recusa os dois casos; o que se prova e o aviso e o exit igual nas duas variantes.
  const TAREFAS_EXTRAS = Array.from({ length: 31 }, (_, i) => `### ${13 + i}. tarefa sintetica ${13 + i} [tipo: implementar]`).join("\n");
  {
    const repo = caixa();
    gravarPlano(repo, "teto-despachos: 30", TAREFAS_EXTRAS);
    arquivoPlanoCitado = arquivoPlano(repo);
    const c30 = cobertura(repo);
    caso("43 tarefas com teto-despachos: 30: a cobertura imprime o aviso com 30 e 43", c30.stdout.includes("aviso: teto-despachos: 30 declarado e menor que as 43 tarefas"), `stdout=${c30.stdout} stderr=${c30.stderr}`);
    const repo70 = caixa();
    gravarPlano(repo70, "teto-despachos: 70", TAREFAS_EXTRAS);
    const c70 = cobertura(repo70);
    caso("43 tarefas com teto-despachos: 70: sem aviso", !c70.stdout.includes("aviso:"), `stdout=${c70.stdout}`);
    caso("o aviso nao muda o exit da cobertura (30 e 70 saem igual)", c30.status === c70.status, `30: exit=${c30.status} | 70: exit=${c70.status}`);
  }

  console.log("== aceita na cobertura (exit 0) ==");
  {
    const repo = caixa();
    gravarPlano(repo);
    const r = cobertura(repo);
    caso("sem a linha teto-despachos: aceita", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  }
  {
    const repo = caixa();
    gravarPlano(repo, "teto-despachos: 5");
    const r = cobertura(repo);
    caso("teto-despachos: 5 aceita", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  }
  {
    const repo = caixa();
    gravarPlano(repo, undefined, "teto-despachos: abc");
    const r = cobertura(repo);
    caso("linha teto-despachos: depois do primeiro ## e ignorada", r.status === 0, `exit=${r.status} stderr=${r.stderr}`);
  }

  console.log("== paridade: mesmo texto de plano, mesma resposta no hook e na cobertura ==");
  const TEXTOS = [
    ["sem a linha", undefined, undefined],
    ["5", "teto-despachos: 5", undefined],
    ["abc", "teto-despachos: abc", undefined],
    ["0", "teto-despachos: 0", undefined],
    ["-1", "teto-despachos: -1", undefined],
    ["1.5", "teto-despachos: 1.5", undefined],
    ["10000", "teto-despachos: 10000", undefined],
    ["vazio", "teto-despachos:", undefined],
    ["duas linhas", ["teto-despachos: 5", "teto-despachos: 7"], undefined],
    ["depois do ##", undefined, "teto-despachos: abc"],
  ];
  for (const [rotulo, cab, rod] of TEXTOS) {
    const repo = caixa();
    gravarPlano(repo, cab, rod);
    const c = cobertura(repo);
    const h = hook(repo);
    const cobRecusa = c.status === 2;
    const hookNega = h.status === 2;
    caso(`mesmo texto, mesma resposta no hook e na cobertura: ${rotulo}`, cobRecusa === hookNega && [0, 2].includes(c.status) && [0, 2].includes(h.status),
      `cobertura exit=${c.status} ${c.stderr} | hook exit=${h.status} ${h.stderr}`);
  }
} finally {
  for (const d of caixas) { try { fs.rmSync(d, { recursive: true, force: true }); } catch { /* ignora */ } }
}

console.log(`ok: ${ok}   falhou: ${falhou}`);
process.exit(falhou === 0 ? 0 : 1);
FIM_DO_NODE
