#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da logica pura do painel do mod (hooks/painel-puro.mjs).
// Uso: node hooks/testa-mod-painel.cjs
//
// Dados: o `usage` do 1o turno de um transcript real desta maquina (modelo claude-opus-5-5,
// 2 + 45815 + 30782 = 76599 tokens de contexto, cache de 1 h) e a linha do relogio vinda do
// relogio-puro.mjs REAL (nenhuma copia). Nenhum caso afirma sobre o texto do fonte.
//
// A mutacao (`restanteMs > 0` -> `restanteMs >= 0` em cacheDe) e rodada por
// `scripts/conferir-mutacao.cjs`; o caso "cache frio quando o TTL acabou no instante exato
// e quando nada foi medido" precisa ficar vermelho.

const path = require("node:path");
const { pathToFileURL } = require("node:url");

const SRC = path.resolve(__dirname, "..");
const PAINEL = pathToFileURL(path.join(SRC, "hooks", "painel-puro.mjs")).href;
const RELOGIO = pathToFileURL(path.join(SRC, "hooks", "relogio-puro.mjs")).href;
const FAIXA = pathToFileURL(path.join(SRC, "hooks", "faixa-puro.mjs")).href;

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);
const afirma = (cond, msg) => { if (!cond) throw new Error(msg); };
const igual = (a, b, msg) => {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}\n  obtido:   ${x}\n  esperado: ${y}`);
};

const importar = (u) => import(u);

const MIN = 60000;
const CTX = 76599; // 2 + 45815 + 30782 do usage real
const HORA = 3600000;
// 7 de outubro de 2026, 20h40 locais; a jornada de 552 min vira "9h12".
const AGORA_RELOGIO = new Date(2026, 9, 7, 20, 40).getTime();

async function linhaDoRelogio() {
  const r = await importar(RELOGIO);
  const av = r.avaliarRelogio({
    jornada: { efetiva_min: 552, ultimo_ms: AGORA_RELOGIO },
    sessoes: null,
    agora: AGORA_RELOGIO,
  });
  return r.linhaRelogio(av);
}

const STATS = {
  trabalhando: true,
  tokens: 2 + 45815 + 30782 + 273,
  custoUsd: 0.42,
  ctxPct: 38,
  ctxTokens: CTX,
  modelo: "claude-opus-5-5",
  ttlMs: HORA,
  ultimaRequisicaoMs: 1000000,
  agora: 1600000,
  deixado: 0,
  carimbos: [1599000, 1560000, 1500000],
  subagentes: 1,
  turnos: 4,
  erros: 0,
};

caso("a linha do relogio real e a esperada", async () => {
  igual(await linhaDoRelogio(), "⏰ jornada 9h12 · 20h40", "linhaRelogio(552 min as 20h40)");
});

caso("cache quente com o usage real: 3000000 ms, reenvio $0.02 e $0.61 se esfriar", async () => {
  const m = await importar(PAINEL);
  const c = m.cacheDe({ modelo: "claude-opus-5-5", ctxTokens: CTX, ultimaRequisicaoMs: 1000000, agora: 1600000, ttlMs: HORA });
  igual([c.quente, c.restanteMs, m.dinheiro(c.custoQuente), m.dinheiro(c.custoFrio)], [true, 3000000, "$0.02", "$0.61"], "cacheDe");
});

caso("cache frio quando o TTL acabou no instante exato e quando nada foi medido", async () => {
  const m = await importar(PAINEL);
  const exato = m.cacheDe({ modelo: "claude-opus-5-5", ctxTokens: CTX, ultimaRequisicaoMs: 1000000, agora: 1000000 + HORA, ttlMs: HORA });
  igual([exato.quente, exato.restanteMs], [false, 0], "no instante exato em que o TTL acaba");
  const nada = m.cacheDe({ modelo: "claude-opus-5-5", ctxTokens: CTX, ultimaRequisicaoMs: 0, agora: 1600000, ttlMs: HORA });
  igual([nada.quente, nada.restanteMs], [false, 0], "nada medido (ultimaRequisicaoMs 0)");
  const um = m.cacheDe({ modelo: "claude-opus-5-5", ctxTokens: CTX, ultimaRequisicaoMs: 1000000, agora: 1000000 + HORA - 1, ttlMs: HORA });
  igual([um.quente, um.restanteMs], [true, 1], "1 ms antes de acabar ainda e quente");
});

caso("cache de 5 min escreve a 1,25x e o de 1 h a 2x", async () => {
  const m = await importar(PAINEL);
  const base = { modelo: "claude-opus-5-5", ctxTokens: 1000000, ultimaRequisicaoMs: 1, agora: 2 };
  igual(m.dinheiro(m.cacheDe({ ...base, ttlMs: 5 * MIN }).custoFrio), "$5.00", "5 min: 1M * US$ 4 * 1,25");
  igual(m.dinheiro(m.cacheDe({ ...base, ttlMs: HORA }).custoFrio), "$8.00", "1 h: 1M * US$ 4 * 2");
  igual(m.dinheiro(m.cacheDe({ ...base, ttlMs: 5 * MIN }).custoQuente), "$0.20", "leitura: 1M * US$ 4 * 5%");
});

caso("preco: a primeira linha que casa vence (fable-5-1 antes de fable, opus-5-5 antes de opus)", async () => {
  const m = await importar(PAINEL);
  const c = (modelo) => { const p = m.precoDe(modelo); return p && [p.entrada, p.leitura]; };
  igual(c("claude-fable-5-1"), [10, 0.025], "fable-5-1");
  igual(c("claude-fable-5"), [10, 0.1], "fable");
  igual(c("claude-opus-5-5"), [4, 0.05], "opus-5-5");
  igual(c("claude-opus-4-1"), [5, 0.1], "opus");
  igual(c("claude-sonnet-5"), [2, 0.1], "sonnet-5");
  igual(c("claude-sonnet-4-5"), [3, 0.1], "sonnet");
  igual(c("claude-haiku-4-5"), [1, 0.1], "haiku");
});

caso("modelo desconhecido ou contexto nao medido: sem preco, sem inventar", async () => {
  const m = await importar(PAINEL);
  const a = m.cacheDe({ modelo: "modelo-de-outra-casa", ctxTokens: CTX, ultimaRequisicaoMs: 1, agora: 2, ttlMs: HORA });
  igual([a.custoQuente, a.custoFrio], [null, null], "modelo desconhecido");
  const b = m.cacheDe({ modelo: "claude-opus-5-5", ctxTokens: null, ultimaRequisicaoMs: 1, agora: 2, ttlMs: HORA });
  igual([b.custoQuente, b.custoFrio], [null, null], "contexto nao medido");
  const c = m.cacheDe({ modelo: null, ctxTokens: CTX, ultimaRequisicaoMs: 1, agora: 2, ttlMs: HORA });
  igual([c.custoQuente, c.custoFrio], [null, null], "modelo nulo");
});

caso("fatias: 7 celulas entre 50/30/20 em [4,2,1] e a soma e sempre a largura pedida", async () => {
  const m = await importar(PAINEL);
  const lista = [{ nome: "a", tokens: 50 }, { nome: "b", tokens: 30 }, { nome: "c", tokens: 20 }];
  igual(m.fatias(lista, 7), [4, 2, 1], "maior resto");
  for (let w = 0; w <= 40; w++) {
    const f = m.fatias(lista, w);
    igual(f.reduce((s, n) => s + n, 0), w, "soma com largura " + w);
  }
  igual(m.fatias([{ nome: "x", tokens: 0 }, { nome: "y", tokens: 0 }], 9), [0, 0], "tudo zero nao divide por zero");
  igual(m.fatias([{ nome: "x", tokens: 1 }, { nome: "y", tokens: 1 }, { nome: "z", tokens: 1 }], 10).reduce((s, n) => s + n, 0), 10, "empate soma a largura");
});

caso("dinheiro: <$0.01, $1.23 e --", async () => {
  const m = await importar(PAINEL);
  igual([m.dinheiro(0.004), m.dinheiro(1.234), m.dinheiro(null), m.dinheiro(0), m.dinheiro(undefined)], ["<$0.01", "$1.23", "--", "$0.00", "--"], "dinheiro");
});

caso("compacto: 999, 76.9K e 1.20M", async () => {
  const m = await importar(PAINEL);
  igual([m.compacto(999), m.compacto(76872), m.compacto(1000), m.compacto(1200000)], ["999", "76.9K", "1.0K", "1.20M"], "compacto");
});

caso("ritmo por minuto conta so carimbos de ate 60 s", async () => {
  const m = await importar(PAINEL);
  const agora = 1000000;
  igual(m.ritmoPorMinuto([agora - 1000, agora - 60000, agora - 60001, agora - 300000], agora), 2, "60000 entra, 60001 nao");
  igual(m.ritmoPorMinuto([], agora), 0, "sem carimbos");
  igual(m.ritmoPorMinuto(undefined, agora), 0, "carimbos ausentes");
});

caso("restante mostra minutos e segundos que faltam", async () => {
  const m = await importar(PAINEL);
  igual([m.restante(3000000), m.restante(61000), m.restante(1), m.restante(0), m.restante(-5)], ["50:00", "1:01", "0:01", "0:00", "0:00"], "restante");
});

caso("o ⏰ conta 2 celulas", async () => {
  const f = await importar(FAIXA);
  igual(f.largura("⏰"), 2, "largura de ⏰");
  const linha = await linhaDoRelogio();
  igual(f.largura(linha), Array.from(linha).length + 1, "linha do relogio: 1 celula por caractere mais 1 do ⏰");
});

caso("200 colunas: todas as figuras cabem, com o relogio real na ultima", async () => {
  const m = await importar(PAINEL);
  const linha = await linhaDoRelogio();
  const figuras = m.figurasDaBarra(STATS, linha, 200);
  igual(figuras.map((f) => f.id), ["estado", "tokens", "custo", "contexto", "cache", "ritmo", "subagentes", "turnos", "erros", "relogio"], "figuras a 200 colunas");
  const rel = figuras.find((f) => f.id === "relogio");
  igual(rel.texto, "⏰ jornada 9h12 · 20h40", "texto do relogio");
  const soma = figuras.reduce((s, f) => s + f.largura, 0) + 2 * (figuras.length - 1);
  afirma(soma <= 200, "soma " + soma + " passa de 200");
});

caso("200 colunas: o que a pessoa le para decidir (estado, tokens, custo, contexto %, cache, relogio) esta na barra", async () => {
  const m = await importar(PAINEL);
  const texto = m.figurasDaBarra(STATS, await linhaDoRelogio(), 200).map((f) => f.texto).join("\n");
  for (const trecho of ["● trabalhando", "Tokens 76.9K", "Custo $0.42", "38%", "Cache ● quente 50:00", "reenvio $0.02 ($0.61 se esfriar)", "⏰ jornada 9h12 · 20h40"]) {
    afirma(texto.includes(trecho), "faltou na barra: " + trecho + "\n" + texto);
  }
});

caso("cache frio na barra mostra o reenvio frio", async () => {
  const m = await importar(PAINEL);
  const f = m.figurasDaBarra({ ...STATS, ultimaRequisicaoMs: 0, trabalhando: false }, null, 200);
  const cache = f.find((x) => x.id === "cache");
  igual(cache.texto, "Cache ○ frio · reenvio $0.61", "cache frio");
  igual(f[0].texto, "○ pronto", "estado pronto");
  afirma(!f.some((x) => x.id === "relogio"), "sem relogio nao ha figura relogio");
});

caso("40 colunas: a soma cabe e o relogio e a ultima a cair", async () => {
  const m = await importar(PAINEL);
  const linha = await linhaDoRelogio();
  const figuras = m.figurasDaBarra(STATS, linha, 40);
  const soma = figuras.reduce((s, f) => s + f.largura, 0) + 2 * (figuras.length - 1);
  afirma(soma <= 40, "soma " + soma + " passa de 40");
  afirma(figuras.some((f) => f.id === "estado"), "estado caiu");
  afirma(figuras.some((f) => f.id === "relogio"), "o relogio caiu antes das demais: " + figuras.map((f) => f.id));
  afirma(figuras.length < 10, "a 40 colunas algo tinha de cair");
});

caso("cada coluna a menos derruba figuras da direita e o relogio so cai depois de todas as outras", async () => {
  const m = await importar(PAINEL);
  const linha = await linhaDoRelogio();
  let tinhaRelogio = true;
  for (let cols = 200; cols >= 12; cols--) {
    const figuras = m.figurasDaBarra(STATS, linha, cols);
    const soma = figuras.reduce((s, f) => s + f.largura, 0) + 2 * Math.max(0, figuras.length - 1);
    afirma(soma <= cols, "soma " + soma + " passa de " + cols);
    const temRelogio = figuras.some((f) => f.id === "relogio");
    if (!temRelogio) {
      // sem relogio, so o estado (e no maximo mais nada) pode restar
      afirma(figuras.every((f) => f.id === "estado"), "relogio caiu com outras figuras vivas em " + cols + ": " + figuras.map((f) => f.id));
    }
    afirma(!(temRelogio && !tinhaRelogio), "relogio voltou ao estreitar");
    tinhaRelogio = temRelogio;
  }
});

caso("coluna absurdamente estreita corta o estado em vez de estourar", async () => {
  const m = await importar(PAINEL);
  const figuras = m.figurasDaBarra(STATS, "⏰ jornada 9h12 · 20h40", 5);
  afirma(figuras.length >= 1, "sem nenhuma figura");
  afirma(figuras.reduce((s, f) => s + f.largura, 0) <= 5, "estourou 5 colunas");
});

caso("semControle no nome de subagente: ESC e override bidi nunca chegam crus", async () => {
  const m = await importar(PAINEL);
  const nome = "revisor\u001b[31m vermelho‮ invertido\u0007";
  const r = m.rotuloSubagente(nome);
  afirma(!/[\u0000-\u001f\u007f-\u009f‪-‮]/.test(r), "sobrou controle em " + JSON.stringify(r));
  afirma(r.startsWith("revisor"), "perdeu o nome: " + r);
  const f = await importar(FAIXA);
  afirma(f.largura(m.rotuloSubagente("x".repeat(80))) <= 24, "nome longo nao foi cortado");
  igual(m.rotuloSubagente(undefined), "", "nome ausente");
});

caso("o texto da barra tambem passa por semControle", async () => {
  const m = await importar(PAINEL);
  const figuras = m.figurasDaBarra(STATS, "⏰ \u001b[2Jjornada", 200);
  afirma(figuras.every((f) => !/[\u0000-\u001f]/.test(f.texto)), "controle na barra: " + JSON.stringify(figuras.map((f) => f.texto)));
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
  console.log(`== resultado: ${ok} ok, ${falhou} falha(s), 0 skipped ==`);
  process.exit(falhou === 0 ? 0 : 1);
})();
