#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da logica pura da faixa de foco (hooks/faixa-puro.mjs).
// Uso: node hooks/testa-mod-faixa.cjs
//
// Texto e dados REAIS: as Qs saem de linhas do README.md e do skills/brainstorm/SKILL.md
// de verdade; os dados saem de `scripts/faixa-dados.cjs` rodado sobre um repo temporario
// (nunca sobre o ~/.rainforest vivo: HOME, USERPROFILE e RFM_ROOT apontam para caixas).
//
// A mutacao (`return oculto !== null && oculto === assinatura;` -> `return false;` no
// .mjs) e rodada por `scripts/conferir-mutacao.cjs`; o caso "esconder vale ate a
// assinatura mudar" precisa ficar vermelho.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");
const { pathToFileURL } = require("node:url");

const SRC = path.resolve(__dirname, "..");
const MJS = pathToFileURL(path.join(SRC, "hooks", "faixa-puro.mjs")).href;
const SCRIPT = path.join(SRC, "scripts", "faixa-dados.cjs");

const caixas = [];
function caixa(prefixo) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), prefixo));
  caixas.push(d);
  return d;
}
function limpar() {
  for (const d of caixas) {
    try { fs.rmSync(d, { recursive: true, force: true }); } catch { /* melhor esforco */ }
  }
}

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);
const afirma = (cond, msg) => { if (!cond) throw new Error(msg); };
const igual = (a, b, msg) => {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}\n  obtido:   ${x}\n  esperado: ${y}`);
};

let _mod;
const modulo = async () => (_mod ??= await import(MJS));

function linhasDe(arquivo, de, ate) {
  const l = fs.readFileSync(path.join(SRC, arquivo), "utf8").split(/\r?\n/);
  return l.slice(de - 1, ate).join("\n");
}

// Dados reais: repo temporario + script da tarefa 1.
let _dados;
function dadosReais() {
  if (_dados) return _dados;
  const repo = caixa("faixa-repo-");
  const home = caixa("faixa-home-");
  const raiz = caixa("faixa-raiz-");
  execFileSync("git", ["init", "-q", repo], { stdio: "ignore" });
  fs.mkdirSync(path.join(repo, "docs", "rainforest", "estado"), { recursive: true });
  const estado = {
    slug: "2026-10-03-faixa-teste", titulo: "Faixa de teste", criado_em: "2026-10-03",
    design: { status: "aprovado" }, plano: { status: "ok" },
    executar: { status: "parcial", tarefas_ok: 1, tarefas: 3, em_voo: [{ agente: "agente-a" }] },
  };
  fs.writeFileSync(path.join(repo, "docs", "rainforest", "estado", "2026-10-03-faixa-teste.json"), JSON.stringify(estado));
  fs.writeFileSync(path.join(raiz, "FOCO.md"), "# Foco\n\n## Ativo\n\n**🚀 Lancar faixa**\nresto\n\n## Concluido\n");
  const env = { ...process.env, HOME: home, USERPROFILE: home, RFM_ROOT: raiz };
  delete env.CLAUDE_PROJECT_DIR;
  const r = spawnSync("node", [SCRIPT, "--cwd", repo], { env, encoding: "utf8" });
  if (r.status !== 0) throw new Error(`faixa-dados.cjs saiu ${r.status}: ${r.stderr}`);
  _dados = JSON.parse(r.stdout);
  return _dados;
}

// ------------------------------------------------------------------ extrairQs
caso("README real, linhas 49 a 52: Q1 e Q2 com titulo", async () => {
  const { extrairQs } = await modulo();
  igual(extrairQs(linhasDe("README.md", 49, 52)),
    [{ n: 1, titulo: "Onde o token vive" }, { n: 2, titulo: "Expiração" }], "Qs do README");
});

caso("SKILL.md:22 real, fora de cerca e em blockquote: Q1", async () => {
  const { extrairQs } = await modulo();
  const linha = linhasDe("skills/brainstorm/SKILL.md", 22, 22);
  afirma(linha.includes("❓ **Q1 —"), `a linha 22 mudou: ${linha}`);
  igual(extrairQs(linha), [{ n: 1, titulo: "<título curto>" }], "sem prefixo");
  igual(extrairQs("> " + linha), [{ n: 1, titulo: "<título curto>" }], "com `> `");
});

caso("a mesma linha dentro de cerca de codigo vira []", async () => {
  const { extrairQs } = await modulo();
  const linha = linhasDe("skills/brainstorm/SKILL.md", 22, 22);
  igual(extrairQs("```\n" + linha + "\n```"), [], "cerca");
  igual(extrairQs("> ```\n> " + linha + "\n> ```"), [], "cerca em blockquote");
  igual(extrairQs("```\n" + linha + "\n```\n**Q2.** depois da cerca").map(q => q.n), [2], "volta depois de fechar");
});

caso("forma **Q1.** texto", async () => {
  const { extrairQs } = await modulo();
  igual(extrairQs("antes\n**Q1.** Qual banco usar?\nfim"), [{ n: 1, titulo: "Qual banco usar?" }], "forma curta");
});

caso("numero repetido conta uma vez, fica a primeira", async () => {
  const { extrairQs } = await modulo();
  igual(extrairQs("**Q1.** primeira\n❓ **Q1 — segunda**: x\n**Q2.** outra"),
    [{ n: 1, titulo: "primeira" }, { n: 2, titulo: "outra" }], "repetida");
});

caso("texto sem Q ou nao-string devolve []", async () => {
  const { extrairQs } = await modulo();
  igual(extrairQs("so prosa"), [], "prosa");
  igual(extrairQs(null), [], "null");
});

// ------------------------------------------------------------------ largura
caso("largura: emoji e CJK valem 2, combinante e variacao 0", async () => {
  const { largura } = await modulo();
  igual(largura("abc"), 3, "ascii");
  igual(largura("🚀"), 2, "emoji");
  igual(largura("漢字"), 4, "cjk");
  igual(largura("é"), 1, "combinante");
  igual(largura("⚠️"), 2, "emoji com variacao");
  igual(largura("Expiração"), 9, "acento composto");
});

// ------------------------------------------------------------------ linhas
caso("dados reais: <= 3 linhas, <= 40 celulas, slug sem data, etapa, progresso, cada Q", async () => {
  const { montarLinhas, largura } = await modulo();
  const dados = dadosReais();
  const qs = [{ n: 1, titulo: "🔑 Token" }, { n: 2, titulo: "Prazo" }];
  const linhas = montarLinhas(dados, qs, 40, 3);
  afirma(linhas.length >= 1 && linhas.length <= 3, `linhas: ${linhas.length}`);
  for (const l of linhas) afirma(largura(l) <= 40, `larga demais (${largura(l)}): ${l}`);
  const fluxo = linhas.find(l => l.startsWith("fluxo "));
  afirma(fluxo, `sem linha do fluxo: ${JSON.stringify(linhas)}`);
  afirma(fluxo.includes("faixa-teste") && !fluxo.includes("2026-10-03"), `slug: ${fluxo}`);
  afirma(fluxo.includes("executar") && fluxo.includes("1/3"), `etapa/progresso: ${fluxo}`);
  const q = linhas.find(l => l.startsWith("Q "));
  afirma(q, `sem linha Q: ${JSON.stringify(linhas)}`);
  for (const parte of ["Q 2 aberta(s)", "Q1", "🔑 Token", "Q2", "Prazo"]) {
    afirma(q.includes(parte), `a linha Q perdeu "${parte}": ${q}`);
  }
  const foco = linhas.find(l => l.startsWith("foco  "));
  afirma(foco && foco.includes("🚀 Lancar faixa"), `foco: ${foco}`);
});

caso("corte com reticencias respeita emoji de 2 celulas", async () => {
  const { montarLinhas, largura } = await modulo();
  const dados = { foco: "🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀", fluxos: [{ slug: "x", etapa: "design" }] };
  for (const cols of [8, 9, 10, 11, 40]) {
    for (const l of montarLinhas(dados, [], cols, 3)) afirma(largura(l) <= cols, `cols=${cols} largura=${largura(l)} ${l}`);
  }
  const l = montarLinhas(dados, [], 12, 3)[0];
  afirma(l.endsWith("…"), `devia terminar em reticencias: ${l}`);
});

caso("campos extras prazo, jornada e versao nunca aparecem", async () => {
  const { montarLinhas } = await modulo();
  const dados = {
    foco: "Foco", prazo: "2026-12-31", jornada: "jornada-secreta", versao: "9.9.9",
    fluxos: [{ slug: "2026-10-03-a", etapa: "plano", prazo: "PRAZOX", jornada: "JORNADAX", versao: "VERSAOX" }],
  };
  const txt = montarLinhas(dados, [{ n: 1, titulo: "t" }], 80, 3).join("\n");
  for (const proibido of ["2026-12-31", "jornada", "9.9.9", "PRAZOX", "JORNADAX", "VERSAOX"]) {
    afirma(!txt.includes(proibido), `vazou "${proibido}": ${txt}`);
  }
});

caso("controle ESC, C1 e bidi nao chegam crus ao terminal", async () => {
  const { montarLinhas } = await modulo();
  const esc = String.fromCharCode(27), csi = String.fromCharCode(0x9b), rlo = String.fromCharCode(0x202e);
  const dados = { foco: `F${esc}]0;titulo${String.fromCharCode(7)}`, fluxos: [{ slug: "s", etapa: `plano${esc}[2J` }] };
  const txt = montarLinhas(dados, [{ n: 1, titulo: `T${csi}31m${rlo}x` }], 80, 3).join("\n");
  for (const c of [esc, csi, rlo, String.fromCharCode(7)]) {
    afirma(!txt.includes(c), `controle U+${c.codePointAt(0).toString(16)} cru: ${JSON.stringify(txt)}`);
  }
  afirma(txt.includes("Q1 T") && txt.includes("fluxo s: plano"), `texto visivel sumiu: ${JSON.stringify(txt)}`);
});

caso("sem fluxo e sem Q devolve [], mesmo com foco; dados null tambem", async () => {
  const { montarLinhas } = await modulo();
  igual(montarLinhas({ foco: "so foco", fluxos: [] }, [], 40, 3), [], "foco sozinho");
  igual(montarLinhas(null, [], 40, 3), [], "null");
  igual(montarLinhas(undefined, undefined, 40, 3), [], "undefined");
});

caso("so Q (sem fluxo, dados null) acende com uma linha", async () => {
  const { montarLinhas } = await modulo();
  igual(montarLinhas(null, [{ n: 3, titulo: "Algo" }], 40, 3), ["Q 1 aberta(s): Q3 Algo"], "so Q");
});

caso("+k conta os outros fluxos; progresso so com os dois numeros", async () => {
  const { montarLinhas } = await modulo();
  const dados = { foco: null, fluxos: [
    { slug: "2026-10-03-a", etapa: "executar", tarefas_ok: 2, tarefas: 5, em_voo: ["x", "y"] },
    { slug: "b", etapa: "plano" }, { slug: "c", etapa: "design" },
  ] };
  igual(montarLinhas(dados, [], 80, 3), ["fluxo a: executar 2/5 | 2 em voo | +2"], "+2");
  igual(montarLinhas({ fluxos: [{ slug: "d", etapa: "plano", tarefas_ok: null, tarefas: 4 }] }, [], 80, 3),
    ["fluxo d: plano"], "sem progresso");
});

caso("maxLinhas 1 e 2: prioridade Q, fluxo, foco; exibicao foco, fluxo, Q", async () => {
  const { montarLinhas } = await modulo();
  const dados = { foco: "F", fluxos: [{ slug: "s", etapa: "plano" }] };
  const qs = [{ n: 1, titulo: "T" }];
  igual(montarLinhas(dados, qs, 80, 3), ["foco  F", "fluxo s: plano", "Q 1 aberta(s): Q1 T"], "tres");
  igual(montarLinhas(dados, qs, 80, 2), ["fluxo s: plano", "Q 1 aberta(s): Q1 T"], "duas: some o foco");
  igual(montarLinhas(dados, qs, 80, 1), ["Q 1 aberta(s): Q1 T"], "uma: fica a Q");
  igual(montarLinhas(dados, [], 80, 1), ["fluxo s: plano"], "uma sem Q: fica o fluxo");
  igual(montarLinhas(dados, qs, 80, 9).length, 3, "teto de MAX_LINHAS");
});

caso("MAX_LINHAS vale 3 e MARCADORES_Q tem as duas formas", async () => {
  const { MAX_LINHAS, MARCADORES_Q } = await modulo();
  igual(MAX_LINHAS, 3, "MAX_LINHAS");
  igual(MARCADORES_Q.length, 2, "duas formas");
});

// ------------------------------------------------------------------ assinatura
caso("assinatura muda com nova Q, nova etapa, slug e agente novo; nao com tarefas_ok", async () => {
  const { assinatura } = await modulo();
  const base = () => ({ fluxos: [{ slug: "s", etapa: "executar", tarefas_ok: 1, tarefas: 3, em_voo: ["a"] }] });
  const qs = [{ n: 1, titulo: "T" }];
  const s0 = assinatura(base(), qs);
  afirma(assinatura(base(), [...qs, { n: 2, titulo: "U" }]) !== s0, "nova Q (n)");
  afirma(assinatura(base(), [{ n: 1, titulo: "T2" }]) !== s0, "Q com titulo novo");
  const e = base(); e.fluxos[0].etapa = "revisar";
  afirma(assinatura(e, qs) !== s0, "nova etapa");
  const sl = base(); sl.fluxos[0].slug = "outro";
  afirma(assinatura(sl, qs) !== s0, "novo slug");
  const v = base(); v.fluxos[0].em_voo = ["a", "b"];
  afirma(assinatura(v, qs) !== s0, "agente novo em voo");
  const ok = base(); ok.fluxos[0].tarefas_ok = 2;
  afirma(assinatura(ok, qs) === s0, "tarefas_ok nao pode mudar a assinatura");
  afirma(assinatura(base(), qs) === s0, "estavel entre chamadas");
});

caso("esconder vale ate a assinatura mudar", async () => {
  const { escondida, assinatura } = await modulo();
  const sig = assinatura({ fluxos: [{ slug: "s", etapa: "plano" }] }, [{ n: 1, titulo: "T" }]);
  const outra = assinatura({ fluxos: [{ slug: "s", etapa: "executar" }] }, [{ n: 1, titulo: "T" }]);
  igual(escondida(sig, sig), true, "mesma assinatura esconde");
  igual(escondida(sig, outra), false, "assinatura mudou, volta a mostrar");
  igual(escondida(null, sig), false, "nunca escondeu");
});

// ------------------------------------------------------------------ execucao
(async () => {
  let ok = 0;
  let falhou = 0;
  for (const [nome, fn] of casos) {
    try {
      await fn();
      ok += 1;
      console.log(`  ok    ${nome}`);
    } catch (e) {
      falhou += 1;
      console.log(`  FALHA ${nome}`);
      console.log(`        ${String(e && e.message || e).split("\n").join("\n        ")}`);
    }
  }
  limpar();
  console.log(`== resultado: ${ok} ok, ${falhou} falha(s), 0 skipped ==`);
  process.exit(falhou === 0 ? 0 : 1);
})();
