#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da logica pura do relogio do mod (hooks/relogio-puro.mjs).
// Uso: node hooks/testa-mod-relogio.cjs
//
// Dados REAIS: as janelas saem de `scripts/relogio-sessoes.cjs` rodado sobre uma raiz
// temporaria (HOME, USERPROFILE e RFM_ROOT em caixas; nunca o ~/.rainforest vivo) e a
// jornada sai de `scripts/jornada.cjs --json --transcript <arquivo SINTETICO de formato
// real>`. Nenhum transcript real e lido ou copiado; as caixas sao apagadas ao fim.
//
// A mutacao (`agora - ultimo_ms <= JANELA_MSG_MIN * 60000` -> `... > ...` no .mjs) e
// rodada por `scripts/conferir-mutacao.cjs`; o caso "depois das 19h sem mensagem nos
// ultimos 30 min nao acende" precisa ficar vermelho.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { pathToFileURL } = require("node:url");

const SRC = path.resolve(__dirname, "..");
const MJS_CAMINHO = path.join(SRC, "hooks", "relogio-puro.mjs");
const MJS = pathToFileURL(MJS_CAMINHO).href;
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

let _mod;
const modulo = async () => (_mod ??= await import(MJS));

function envLimpo(extra) {
  const env = { ...process.env, ...extra };
  delete env.FORCE_COLOR;
  delete env.CLAUDE_PROJECT_DIR;
  return env;
}

// ---- dados reais: janelas (relogio-sessoes.cjs sobre raiz temporaria) --------
// `janelasMin`: [[cwd, minutosParado]]; `foco`: texto do FOCO.md ou null.
function sessoesReais(janelasMin, foco) {
  const home = caixa("relogio-home-");
  const raiz = caixa("relogio-raiz-");
  const t = Date.now();
  const s = {};
  janelasMin.forEach(([cwd, min], i) => {
    s["sessao-" + i] = { cwd, prompt_ts: t - (min + 5) * 60000, stop_ts: t - min * 60000 };
  });
  fs.writeFileSync(path.join(raiz, "sessoes.json"), JSON.stringify(s));
  if (foco !== null) fs.writeFileSync(path.join(raiz, "FOCO.md"), foco);
  const r = spawnSync(process.execPath, [SCRIPT_SESSOES, "--cwd", raiz, "--sessao", "eu"], {
    env: envLimpo({ HOME: home, USERPROFILE: home, RFM_ROOT: raiz }),
    encoding: "utf8",
  });
  afirma(r.status === 0, "relogio-sessoes.cjs saiu " + r.status + ": " + r.stderr);
  return JSON.parse(r.stdout);
}

// ---- dados reais: jornada (jornada.cjs --json sobre transcript sintetico) ----
// `n` intervalos de `gap` min terminando em `ultimo` (Date local): efetiva = n * gap
// (gap abaixo do corte de 55 min). Formato real: `type: user`, timestamp UTC com Z.
function jornadaReal(n, gap, ultimo) {
  const dir = caixa("relogio-transcript-");
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

const em = (h, m, dia = 3) => new Date(2026, 9, dia, h, m).getTime();
const MIN = 60000;

// ------------------------------------------------------------------ jornada
caso("jornada acende: 552 min as 20h40 com mensagem as 20h30", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const jornada = jornadaReal(12, 46, new Date(em(20, 30)));
  igual(jornada.efetiva_min, 552, "jornada.cjs mediu outra coisa");
  const r = avaliarRelogio({ jornada, sessoes: null, agora: em(20, 40) });
  igual(linhaRelogio(r), "⏰ jornada 9h12 · 20h40", "linha");
});

caso("8h59 as 14h nao acende", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const jornada = jornadaReal(11, 49, new Date(em(13, 55)));
  igual(jornada.efetiva_min, 539, "jornada.cjs mediu outra coisa");
  const r = avaliarRelogio({ jornada, sessoes: null, agora: em(14, 0) });
  igual(r.jornada, null, "jornada");
  igual(linhaRelogio(r), null, "linha");
});

caso("exatamente 540 min as 14h nao acende (o limite e estrito)", async () => {
  const { avaliarRelogio } = await modulo();
  const r = avaliarRelogio({ jornada: { efetiva_min: 540, ultimo_ms: em(13, 55) }, sessoes: null, agora: em(14, 0) });
  igual(r.jornada, null, "jornada");
});

caso("depois das 19h sem mensagem nos ultimos 30 min nao acende", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const jornada = jornadaReal(10, 48, new Date(em(19, 29)));
  igual(jornada.efetiva_min, 480, "jornada.cjs mediu outra coisa");
  const r = avaliarRelogio({ jornada, sessoes: null, agora: em(20, 0) });
  igual(r.jornada, null, "jornada (ultima mensagem ha 31 min)");
  igual(linhaRelogio(r), null, "linha");
});

caso("depois das 19h com mensagem ha exatamente 30 min acende (<=)", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const r = avaliarRelogio({ jornada: { efetiva_min: 480, ultimo_ms: em(19, 30) }, sessoes: null, agora: em(20, 0) });
  igual(linhaRelogio(r), "⏰ jornada 8h00 · 20h00", "linha");
});

caso("madrugada: acesa as 3h com mensagem ha 5 min (decisao B)", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const jornada = jornadaReal(10, 48, new Date(em(2, 55, 4)));
  const r = avaliarRelogio({ jornada, sessoes: null, agora: em(3, 0, 4) });
  igual(linhaRelogio(r), "⏰ jornada 8h00 · 3h00", "linha");
});

caso("madrugada sem mensagem recente nao acende", async () => {
  const { avaliarRelogio } = await modulo();
  const r = avaliarRelogio({ jornada: { efetiva_min: 480, ultimo_ms: em(2, 0, 4) }, sessoes: null, agora: em(3, 0, 4) });
  igual(r.jornada, null, "jornada");
});

caso("fronteiras do horario: 5h00 e 18h59 nao acendem, 19h00 e 4h59 acendem", async () => {
  const { avaliarRelogio } = await modulo();
  const acende = (h, m) => avaliarRelogio({ jornada: { efetiva_min: 300, ultimo_ms: em(h, m) }, sessoes: null, agora: em(h, m) }).jornada !== null;
  igual([acende(5, 0), acende(18, 59), acende(19, 0), acende(4, 59)], [false, false, true, true], "fronteiras");
});

// ------------------------------------------------------------------ parada
caso("parada: janela ha 32 min com Ociosidade maxima: 30 min, junto da jornada", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const sessoes = sessoesReais([["C:\\Projetos\\mod-faixa-foco", 32]], "# Foco\n\nOciosidade máxima: 30 min\n");
  igual(sessoes.ociosidade_min, 30, "ociosidade_min");
  const jornada = jornadaReal(12, 46, new Date(em(20, 30)));
  const agora = Date.now();
  const r = avaliarRelogio({ jornada: { ...jornada, ultimo_ms: agora - 5 * MIN }, sessoes, agora });
  const hora = r.jornada.hora;
  igual(linhaRelogio(r), "⏰ jornada 9h12 · " + hora + " | mod-faixa-foco parada há 32 min", "linha");
});

caso("so a parada: linha sem jornada", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const sessoes = sessoesReais([["C:/Projetos/mod-faixa-foco", 32]], "# Foco\n\nOciosidade máxima: 30 min\n");
  const r = avaliarRelogio({ jornada: null, sessoes, agora: Date.now() });
  igual(linhaRelogio(r), "⏰ mod-faixa-foco parada há 32 min", "linha");
});

caso("duas acima do limite: a mais antiga nomeada, 2h48 e (+1)", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const sessoes = sessoesReais([["C:\\p\\recente", 100], ["C:\\p\\antiga", 168]], null);
  igual(sessoes.ociosidade_min, 45, "ociosidade_min padrao");
  const r = avaliarRelogio({ jornada: null, sessoes, agora: Date.now() });
  igual(linhaRelogio(r), "⏰ antiga parada há 2h48 (+1)", "linha");
  igual(r.parada.outras, 1, "outras");
});

caso("so uma das duas passa do limite: sem (+k)", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const sessoes = sessoesReais([["C:\\p\\antiga", 60], ["C:\\p\\fresca", 10]], null);
  const r = avaliarRelogio({ jornada: null, sessoes, agora: Date.now() });
  igual(linhaRelogio(r), "⏰ antiga parada há 1h00", "linha");
});

caso("janela exatamente no limite nao acende", async () => {
  const { avaliarRelogio, linhaRelogio } = await modulo();
  const agora = em(14, 0);
  const sessoes = { ociosidade_min: 30, janelas: [{ cwd: "C:\\p\\x", desde: agora - 30 * MIN }] };
  const r = avaliarRelogio({ jornada: null, sessoes, agora });
  igual(r.parada, null, "parada");
  igual(linhaRelogio(r), null, "linha");
  const um = avaliarRelogio({ jornada: null, sessoes: { ...sessoes, janelas: [{ cwd: "C:\\p\\x", desde: agora - 30 * MIN - 1 }] }, agora });
  afirma(um.parada !== null, "um ms acima do limite devia acender");
});

caso("sem dados: sem linha, sem assinatura, sem nota", async () => {
  const { avaliarRelogio, linhaRelogio, assinaturaRelogio, notaJornada } = await modulo();
  const r = avaliarRelogio({ jornada: null, sessoes: null, agora: em(14, 0) });
  igual([r.jornada, r.parada, linhaRelogio(r), assinaturaRelogio(r), notaJornada(r)], [null, null, null, "", null], "vazio");
});

caso("pasta: ultimo segmento, com barra invertida, barra normal e barra final", async () => {
  const { avaliarRelogio } = await modulo();
  const agora = em(14, 0);
  const pasta = (cwd) => avaliarRelogio({ jornada: null, sessoes: { ociosidade_min: 1, janelas: [{ cwd, desde: agora - 10 * MIN }] }, agora }).parada.pasta;
  igual([
    pasta("C:\\Projetos\\rainforest-mind"),
    pasta("C:/Projetos/rainforest-mind"),
    pasta("C:\\Projetos\\rainforest-mind\\"),
    pasta("C:/Projetos/rainforest-mind/"),
  ], ["rainforest-mind", "rainforest-mind", "rainforest-mind", "rainforest-mind"], "pasta");
});

// ------------------------------------------------------------------ assinatura
caso("assinatura igual com 32 e 33 min", async () => {
  const { avaliarRelogio, assinaturaRelogio } = await modulo();
  const sig = (min) => assinaturaRelogio(avaliarRelogio({
    jornada: { efetiva_min: 552, ultimo_ms: em(20, 30) },
    sessoes: { ociosidade_min: 30, janelas: [{ cwd: "C:\\p\\a", desde: em(20, 40) - min * MIN }] },
    agora: em(20, 40),
  }));
  igual(sig(32), sig(33), "assinatura");
  afirma(!/32|33/.test(sig(32).replace(/^j:\d{4}-\d{2}-\d{2}/, "")), "a assinatura carrega minutos: " + sig(32));
});

caso("assinatura muda quando outra pasta vira a mais parada", async () => {
  const { avaliarRelogio, assinaturaRelogio } = await modulo();
  const agora = em(20, 40);
  const sig = (janelas) => assinaturaRelogio(avaliarRelogio({ jornada: null, sessoes: { ociosidade_min: 30, janelas }, agora }));
  const a = { cwd: "C:\\p\\a", desde: agora - 90 * MIN };
  const b = { cwd: "C:\\p\\b", desde: agora - 40 * MIN };
  afirma(sig([a, b]) !== sig([b]), "a mais parada deixou de ser a, a assinatura devia mudar");
});

caso("assinatura muda quando uma nova janela cruza o limite", async () => {
  const { avaliarRelogio, assinaturaRelogio } = await modulo();
  const agora = em(20, 40);
  const sig = (janelas) => assinaturaRelogio(avaliarRelogio({ jornada: null, sessoes: { ociosidade_min: 30, janelas }, agora }));
  const a = { cwd: "C:\\p\\a", desde: agora - 90 * MIN };
  const ainda = { cwd: "C:\\p\\b", desde: agora - 20 * MIN };
  const cruzou = { cwd: "C:\\p\\b", desde: agora - 31 * MIN };
  igual(sig([a, ainda]), sig([a]), "janela abaixo do limite nao muda nada");
  afirma(sig([a, cruzou]) !== sig([a]), "janela que cruzou o limite devia mudar a assinatura");
});

caso("assinatura: j:<dia> muda no dia seguinte, e so o dia", async () => {
  const { avaliarRelogio, assinaturaRelogio } = await modulo();
  const sig = (dia) => assinaturaRelogio(avaliarRelogio({
    jornada: { efetiva_min: 600, ultimo_ms: em(20, 30, dia) },
    sessoes: null,
    agora: em(20, 40, dia),
  }));
  igual(sig(3), "j:2026-10-03", "dia 3");
  igual(sig(4), "j:2026-10-04", "dia 4");
});

caso("assinatura junta os dois trechos so quando existem", async () => {
  const { avaliarRelogio, assinaturaRelogio } = await modulo();
  const agora = em(20, 40);
  const r = avaliarRelogio({
    jornada: { efetiva_min: 552, ultimo_ms: em(20, 30) },
    sessoes: { ociosidade_min: 30, janelas: [{ cwd: "C:\\p\\a", desde: agora - 90 * MIN }] },
    agora,
  });
  igual(assinaturaRelogio(r), "j:2026-10-03|p:C:\\p\\a:1", "assinatura");
});

// ------------------------------------------------------------------ nota
caso("notaJornada cita a jornada, a hora e a regra 8", async () => {
  const { avaliarRelogio, notaJornada } = await modulo();
  const r = avaliarRelogio({ jornada: { efetiva_min: 552, ultimo_ms: em(20, 30) }, sessoes: null, agora: em(20, 40) });
  const nota = notaJornada(r);
  afirma(typeof nota === "string", "nota nao e texto");
  for (const trecho of ["9h12", "20h40", "regra 8"]) afirma(nota.includes(trecho), "a nota nao cita " + trecho + ": " + nota);
});

caso("notaJornada so existe com a jornada acesa", async () => {
  const { avaliarRelogio, notaJornada } = await modulo();
  const soParada = avaliarRelogio({
    jornada: null,
    sessoes: { ociosidade_min: 30, janelas: [{ cwd: "C:\\p\\a", desde: em(14, 0) - 90 * MIN }] },
    agora: em(14, 0),
  });
  igual(notaJornada(soParada), null, "so a parada nao gera nota");
});

// ------------------------------------------------------------------ formatacao
caso("hhmm bate com o hhmm exportado por scripts/jornada.cjs (0, 59, 60, 61, 552, 1439)", async () => {
  const { hhmm } = await modulo();
  const { hhmm: hhmmJornada } = require(SCRIPT_JORNADA);
  afirma(typeof hhmmJornada === "function", "jornada.cjs nao exporta hhmm");
  for (const n of [0, 59, 60, 61, 552, 1439]) igual(hhmm(n), hhmmJornada(n), "hhmm(" + n + ")");
  igual([hhmm(552), hhmm(59), hhmm(168)], ["9h12", "59 min", "2h48"], "formas esperadas");
});

caso("horaLocal e diaLocal usam o relogio local, sem zero a esquerda na hora", async () => {
  const { horaLocal, diaLocal } = await modulo();
  igual([horaLocal(em(20, 41)), horaLocal(em(3, 5)), diaLocal(em(23, 59, 3))], ["20h41", "3h05", "2026-10-03"], "formatos");
});

caso("o .mjs e puro: sem require, node:, process., Date.now nem o objeto do engine", async () => {
  const fonte = fs.readFileSync(MJS_CAMINHO, "utf8");
  const proibidos = [/require\(/, /from 'node:/, /from "node:/, /process\./, /Date\.now/, /\$\./, /\$\{/];
  for (const re of proibidos) afirma(!re.test(fonte), "hooks/relogio-puro.mjs tem " + re);
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
