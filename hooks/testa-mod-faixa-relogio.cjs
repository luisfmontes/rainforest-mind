#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da linha do relogio dentro da faixa (hooks/faixa-puro.mjs + hooks/relogio-puro.mjs).
// Uso: node hooks/testa-mod-faixa-relogio.cjs
//
// Dados REAIS: a linha sai de `linhaRelogio` sobre a saida real de
// `scripts/relogio-sessoes.cjs` e de `scripts/jornada.cjs --json --transcript <arquivo
// SINTETICO de formato real>`; os dados da faixa saem de `scripts/faixa-dados.cjs` sobre
// um repo temporario. HOME, USERPROFILE e RFM_ROOT apontam para caixas (nunca o
// ~/.rainforest vivo); as caixas sao apagadas ao fim.
//
// A mutacao (no array `prioridade` do .mjs, o relogio passa para depois do foco) e rodada
// por `scripts/conferir-mutacao.cjs`; o caso "com 2 linhas disponiveis ficam a Q e o
// relogio" precisa ficar vermelho.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");
const { pathToFileURL } = require("node:url");

const SRC = path.resolve(__dirname, "..");
const FAIXA = pathToFileURL(path.join(SRC, "hooks", "faixa-puro.mjs")).href;
const RELOGIO = pathToFileURL(path.join(SRC, "hooks", "relogio-puro.mjs")).href;
const SCRIPT_FAIXA = path.join(SRC, "scripts", "faixa-dados.cjs");
const SCRIPT_SESSOES = path.join(SRC, "scripts", "relogio-sessoes.cjs");
const SCRIPT_JORNADA = path.join(SRC, "scripts", "jornada.cjs");

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

let _faixa, _relogio;
const faixa = async () => (_faixa ??= await import(FAIXA));
const relogio = async () => (_relogio ??= await import(RELOGIO));

function envLimpo(extra) {
  const env = { ...process.env, ...extra };
  delete env.FORCE_COLOR;
  delete env.CLAUDE_PROJECT_DIR;
  return env;
}

// Dados reais da faixa: repo temporario + scripts/faixa-dados.cjs.
let _dados;
function dadosReais() {
  if (_dados) return _dados;
  const repo = caixa("faixa-relogio-repo-");
  const home = caixa("faixa-relogio-home-");
  const raiz = caixa("faixa-relogio-raiz-");
  execFileSync("git", ["init", "-q", repo], { stdio: "ignore" });
  fs.mkdirSync(path.join(repo, "docs", "rainforest", "estado"), { recursive: true });
  const estado = {
    slug: "2026-10-03-faixa-teste", titulo: "Faixa de teste", criado_em: "2026-10-03",
    design: { status: "aprovado" }, plano: { status: "ok" },
    executar: { status: "parcial", tarefas_ok: 1, tarefas: 3, em_voo: [{ agente: "agente-a" }] },
  };
  fs.writeFileSync(path.join(repo, "docs", "rainforest", "estado", "2026-10-03-faixa-teste.json"), JSON.stringify(estado));
  fs.writeFileSync(path.join(raiz, "FOCO.md"), "# Foco\n\n## Ativo\n\n**🚀 Lancar faixa**\nresto\n\n## Concluido\n");
  const r = spawnSync(process.execPath, [SCRIPT_FAIXA, "--cwd", repo], {
    env: envLimpo({ HOME: home, USERPROFILE: home, RFM_ROOT: raiz }),
    encoding: "utf8",
  });
  if (r.status !== 0) throw new Error(`faixa-dados.cjs saiu ${r.status}: ${r.stderr}`);
  _dados = JSON.parse(r.stdout);
  return _dados;
}

// Janelas reais: relogio-sessoes.cjs sobre raiz temporaria. [[cwd, minutosParado]]
function sessoesReais(janelasMin, ociosidade) {
  const home = caixa("faixa-relogio-home-");
  const raiz = caixa("faixa-relogio-raiz-");
  const t = Date.now();
  const s = {};
  janelasMin.forEach(([cwd, min], i) => {
    s["sessao-" + i] = { cwd, prompt_ts: t - (min + 5) * 60000, stop_ts: t - min * 60000 };
  });
  fs.writeFileSync(path.join(raiz, "sessoes.json"), JSON.stringify(s));
  fs.writeFileSync(path.join(raiz, "FOCO.md"), `# Foco\n\nOciosidade máxima: ${ociosidade} min\n`);
  const r = spawnSync(process.execPath, [SCRIPT_SESSOES, "--cwd", raiz, "--sessao", "eu"], {
    env: envLimpo({ HOME: home, USERPROFILE: home, RFM_ROOT: raiz }),
    encoding: "utf8",
  });
  afirma(r.status === 0, "relogio-sessoes.cjs saiu " + r.status + ": " + r.stderr);
  return JSON.parse(r.stdout);
}

// Jornada real: jornada.cjs --json sobre transcript sintetico (n intervalos de `gap` min
// terminando em `ultimo`: efetiva = n * gap).
function jornadaReal(n, gap, ultimo) {
  const dir = caixa("faixa-relogio-transcript-");
  const f = path.join(dir, "sintetico.jsonl");
  const linhas = [];
  for (let i = n; i >= 0; i--) {
    const d = new Date(ultimo.getTime() - i * gap * 60000);
    linhas.push(JSON.stringify({ type: "user", timestamp: d.toISOString(), message: { role: "user" } }));
  }
  fs.writeFileSync(f, linhas.join("\n") + "\n");
  const r = spawnSync(process.execPath, [SCRIPT_JORNADA, "--json", "--transcript", f], {
    env: envLimpo({ HOME: dir, USERPROFILE: dir }),
    encoding: "utf8",
  });
  afirma(r.status === 0, "jornada.cjs saiu " + r.status + ": " + r.stdout + r.stderr);
  const j = JSON.parse(r.stdout);
  return { efetiva_min: j.efetiva_min, ultimo_ms: Date.parse(j.ultimo) };
}

// Linha REAL do relogio: jornada 9h12 e uma janela parada ha 32 min (limite 30 min).
async function linhaReal() {
  const { avaliarRelogio, linhaRelogio } = await relogio();
  const jornada = jornadaReal(12, 46, new Date(Date.now() - 5 * 60000));
  const sessoes = sessoesReais([["C:/Projetos/mod-faixa-foco", 32]], 30);
  const agora = Date.now() + 1000; // depois de gravar as janelas: 32 min cheios, nunca 31
  const r = avaliarRelogio({ jornada, sessoes, agora });
  const linha = linhaRelogio(r);
  afirma(typeof linha === "string", "linhaRelogio devolveu " + JSON.stringify(linha));
  return { r, linha };
}

const QS = [{ n: 1, titulo: "🔑 Token" }, { n: 2, titulo: "Prazo" }];

// ------------------------------------------------------------------ constante
caso("MAX_LINHAS vale 4", async () => {
  const { MAX_LINHAS } = await faixa();
  igual(MAX_LINHAS, 4, "MAX_LINHAS");
});

// ------------------------------------------------------------------ ordem e prioridade
caso("com espaco: 4 linhas na ordem foco, fluxo, relogio, Q, nenhuma acima de 80 celulas", async () => {
  const { montarLinhas, largura } = await faixa();
  const { linha } = await linhaReal();
  igual(linha.startsWith("⏰ jornada 9h12 · ") && linha.endsWith(" | mod-faixa-foco parada há 32 min"), true, "linha real: " + linha);
  const linhas = montarLinhas(dadosReais(), QS, 80, 4, linha);
  igual(linhas.length, 4, "quatro linhas: " + JSON.stringify(linhas));
  afirma(linhas[0].startsWith("foco  "), "1a nao e o foco: " + linhas[0]);
  afirma(linhas[1].startsWith("fluxo "), "2a nao e o fluxo: " + linhas[1]);
  igual(linhas[2], linha, "3a nao e o relogio");
  afirma(linhas[3].startsWith("Q 2 aberta(s)"), "4a nao e a Q: " + linhas[3]);
  for (const l of linhas) afirma(largura(l) <= 80, `larga demais (${largura(l)}): ${l}`);
});

caso("com 3 linhas disponiveis cai o foco", async () => {
  const { montarLinhas } = await faixa();
  const { linha } = await linhaReal();
  const linhas = montarLinhas(dadosReais(), QS, 80, 3, linha);
  igual(linhas.length, 3, "tres");
  afirma(linhas[0].startsWith("fluxo ") && linhas[1] === linha && linhas[2].startsWith("Q "), JSON.stringify(linhas));
});

caso("com 2 linhas disponiveis ficam a Q e o relogio", async () => {
  const { montarLinhas } = await faixa();
  const { linha } = await linhaReal();
  const linhas = montarLinhas(dadosReais(), QS, 80, 2, linha);
  igual(linhas.length, 2, "duas");
  igual(linhas[0], linha, "primeiro o relogio");
  afirma(linhas[1].startsWith("Q 2 aberta(s)"), "depois a Q: " + linhas[1]);
});

caso("com 1 linha disponivel fica so a Q", async () => {
  const { montarLinhas } = await faixa();
  const { linha } = await linhaReal();
  const linhas = montarLinhas(dadosReais(), QS, 80, 1, linha);
  igual(linhas.length, 1, "uma");
  afirma(linhas[0].startsWith("Q 2 aberta(s)"), "so a Q: " + linhas[0]);
});

caso("com relogio e sem fluxo nem Q: foco e relogio (o relogio acende a faixa)", async () => {
  const { montarLinhas } = await faixa();
  const { linha } = await linhaReal();
  igual(montarLinhas({ foco: "F", fluxos: [] }, [], 80, 4, linha), ["foco  F", linha], "foco e relogio");
  igual(montarLinhas({ foco: null, fluxos: [] }, [], 80, 4, linha), [linha], "so o relogio");
  igual(montarLinhas({ foco: "F", fluxos: [] }, [], 80, 4, null), [], "sem relogio, so foco: nao acende");
});

// ------------------------------------------------------------------ sem relogio = base
caso("sem relogio (omitido, null ou string vazia) devolve exatamente o da base", async () => {
  const { montarLinhas } = await faixa();
  const dados = { foco: "F", fluxos: [{ slug: "s", etapa: "plano" }] };
  const qs = [{ n: 1, titulo: "T" }];
  const base = ["foco  F", "fluxo s: plano", "Q 1 aberta(s): Q1 T"];
  igual(montarLinhas(dados, qs, 80, 3), base, "omitido");
  igual(montarLinhas(dados, qs, 80, 4, null), base, "null");
  igual(montarLinhas(dados, qs, 80, 4, ""), base, "vazio");
  igual(montarLinhas(dados, qs, 80, 9).length, 3, "sem relogio o teto pratico segue 3");
});

// ------------------------------------------------------------------ largura e controle
caso("a linha do relogio passa por cortar e por semControle", async () => {
  const { montarLinhas, largura } = await faixa();
  const { avaliarRelogio, linhaRelogio } = await relogio();
  const agora = Date.now();
  const sessoes = {
    ociosidade_min: 30,
    janelas: [{ cwd: "C:/x/pasta-" + "longa".repeat(20) + "\u001b[31m\u202e", desde: agora - 40 * 60000 }],
  };
  const linha = linhaRelogio(avaliarRelogio({ jornada: null, sessoes, agora }));
  afirma(/[\u001b\u202e]/.test(linha), "a linha de entrada devia trazer ESC e bidi: " + JSON.stringify(linha));
  const linhas = montarLinhas({ foco: null, fluxos: [] }, [], 40, 4, linha);
  igual(linhas.length, 1, "uma linha");
  afirma(largura(linhas[0]) <= 40, `larga demais (${largura(linhas[0])}): ${linhas[0]}`);
  afirma(linhas[0].endsWith("…"), "devia cortar com reticencias: " + linhas[0]);
  afirma(!/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/.test(linhas[0]), "controle chegou cru: " + JSON.stringify(linhas[0]));
  const curta = montarLinhas({ foco: null, fluxos: [] }, [], 200, 4, "⏰ a\u001b[0mb\u202ec");
  igual(curta, ["⏰ a [0mb c"], "controles viram espaco");
});

// ------------------------------------------------------------------ assinatura
caso("assinatura sem terceiro argumento (ou vazio) e igual a da base; com o relogio muda com o dia", async () => {
  const { assinatura } = await faixa();
  const { avaliarRelogio, assinaturaRelogio } = await relogio();
  const dados = { foco: "F", fluxos: [{ slug: "s", etapa: "plano" }] };
  const qs = [{ n: 1, titulo: "T" }];
  const base = '[[[1,"T"]],"s","plano",[]]';
  igual(assinatura(dados, qs), base, "sem terceiro argumento");
  igual(assinatura(dados, qs, ""), base, "vazio");
  igual(assinatura(dados, qs, undefined), base, "undefined");
  const jornada = { efetiva_min: 552, ultimo_ms: new Date(2026, 9, 3, 20, 30).getTime() };
  const hoje = assinaturaRelogio(avaliarRelogio({ jornada, sessoes: null, agora: new Date(2026, 9, 3, 20, 40).getTime() }));
  const amanha = assinaturaRelogio(avaliarRelogio({ jornada, sessoes: null, agora: new Date(2026, 9, 4, 3, 0).getTime() }));
  igual(hoje, "j:2026-10-03", "assinatura real do relogio");
  const a = assinatura(dados, qs, hoje);
  afirma(a !== base, "com relogio devia diferir da base");
  afirma(a !== assinatura(dados, qs, amanha), "outro dia devia mudar a assinatura");
  igual(a, assinatura(dados, qs, hoje), "estavel para o mesmo dia");
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
