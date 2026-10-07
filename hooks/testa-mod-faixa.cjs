#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da biblioteca de largura (hooks/faixa-puro.mjs): `largura`, `cortar` e `semControle`.
// Uso: node hooks/testa-mod-faixa.cjs
//
// O que a faixa de foco fazia (extrairQs, montarLinhas, assinatura, escondida) saiu com a barra
// de sessao (D2, D9); a barra e provada por hooks/testa-mod-painel.cjs e por
// hooks/mod-painel.test.tsx. Aqui ficam so as tres funcoes que o painel ainda importa.

const path = require("node:path");
const { pathToFileURL } = require("node:url");

const SRC = path.resolve(__dirname, "..");
const MJS = pathToFileURL(path.join(SRC, "hooks", "faixa-puro.mjs")).href;

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);
const afirma = (cond, msg) => { if (!cond) throw new Error(msg); };
const igual = (a, b, msg) => {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}\n  obtido:   ${x}\n  esperado: ${y}`);
};

let _mod;
const modulo = async () => (_mod ??= await import(MJS));

caso("o modulo exporta so largura, cortar e semControle", async () => {
  const m = await modulo();
  igual(Object.keys(m).sort(), ["cortar", "largura", "semControle"], "exports de faixa-puro.mjs");
});

caso("largura: emoji e CJK valem 2, combinante e variacao 0", async () => {
  const { largura } = await modulo();
  igual(largura("abc"), 3, "ascii");
  igual(largura("🚀"), 2, "emoji");
  igual(largura("漢字"), 4, "cjk");
  igual(largura("é"), 1, "combinante");
  igual(largura("⚠️"), 2, "emoji com variacao");
  igual(largura("Expiração"), 9, "acento composto");
  igual(largura("⏰"), 2, "o relogio da barra");
  igual(largura(undefined), 0, "ausente");
});

caso("corte com reticencias respeita emoji de 2 celulas", async () => {
  const { cortar, largura } = await modulo();
  const texto = "🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀";
  for (const cols of [1, 2, 3, 8, 9, 10, 11, 40]) {
    const c = cortar(texto, cols);
    afirma(largura(c) <= cols, `cols=${cols} largura=${largura(c)} ${c}`);
  }
  const c = cortar(texto, 12);
  afirma(c.endsWith("…"), `devia terminar em reticencias: ${c}`);
  igual(cortar("curto", 40), "curto", "o que cabe nao muda");
  igual(cortar("qualquer", 0), "", "sem coluna nenhuma, vazio");
});

caso("controle ESC, C1 e bidi nao chegam crus ao terminal", async () => {
  const { semControle } = await modulo();
  const esc = String.fromCharCode(27), csi = String.fromCharCode(0x9b), rlo = String.fromCharCode(0x202e);
  const txt = semControle(`T${esc}[2J${csi}31m${rlo}x${String.fromCharCode(7)}fim`);
  for (const c of [esc, csi, rlo, String.fromCharCode(7)]) {
    afirma(!txt.includes(c), `controle U+${c.codePointAt(0).toString(16)} cru: ${JSON.stringify(txt)}`);
  }
  afirma(txt.startsWith("T") && txt.endsWith("fim"), `texto visivel sumiu: ${JSON.stringify(txt)}`);
});

caso("invisiveis LRM/RLM, ALM, separadores, zero-width, U+2060-2069 e BOM viram espaco", async () => {
  const { semControle } = await modulo();
  const invisibles = [
    String.fromCodePoint(0x200b), // Zero-Width Space
    String.fromCodePoint(0x200c), // Zero-Width Non-Joiner
    String.fromCodePoint(0x200d), // Zero-Width Joiner
    String.fromCodePoint(0x200e), // Left-to-Right Mark
    String.fromCodePoint(0x200f), // Right-to-Left Mark
    String.fromCodePoint(0x061c), // Arabic Letter Mark
    String.fromCodePoint(0x2028), // Line Separator
    String.fromCodePoint(0x2029), // Paragraph Separator
    String.fromCodePoint(0x2060), // Word Joiner
    String.fromCodePoint(0x2064), // Invisible Plus
    String.fromCodePoint(0x2065), // Invisible Separator
    String.fromCodePoint(0x2066), // Left-to-Right Isolate
    String.fromCodePoint(0x2069), // Pop Directional Isolate
    String.fromCodePoint(0xfeff), // Zero-Width No-Break Space (BOM)
  ];
  const txt = semControle("nome" + invisibles.join("") + "fim");
  for (const inv of invisibles) {
    afirma(!txt.includes(inv), `invisivel U+${inv.codePointAt(0).toString(16).toUpperCase()} cru: ${JSON.stringify(txt)}`);
  }
  afirma(txt.startsWith("nome") && txt.endsWith("fim"), `texto visivel sumiu: ${JSON.stringify(txt)}`);
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
