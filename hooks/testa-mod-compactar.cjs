#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da logica pura da compactacao automatica (hooks/compactar-puro.mjs).
// Uso: node hooks/testa-mod-compactar.cjs
//
// Estado entre chamadas: a sequencia de ticks passa armado/avisado de uma decisao para a
// seguinte, como o mod faz. Nenhum caso le o texto do fonte.
//
// A mutacao (`if (agenteRodando)` -> `if (false)` em decidir) e rodada por
// `scripts/conferir-mutacao.cjs`; o caso "agente rodando avisa uma vez e nao compacta"
// precisa ficar vermelho.

const path = require("node:path");
const { pathToFileURL } = require("node:url");

const SRC = path.resolve(__dirname, "..");
const COMPACTAR = pathToFileURL(path.join(SRC, "hooks", "compactar-puro.mjs")).href;

let m; // modulo carregado no inicio da execucao

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);
const afirma = (cond, msg) => { if (!cond) throw new Error(msg); };
const igual = (a, b, msg) => {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(msg + "\n  obtido:   " + x + "\n  esperado: " + y);
};

// base de um tick ligado, armado e sem agente
const LIGADO = { limiar: 60, armado: true, agenteRodando: false, ligado: true, avisado: false };

// ------------------------------------------------------------------ constantes
caso("LIMIAR_PADRAO e 60", () => {
  igual(m.LIMIAR_PADRAO, 60, "limiar padrao");
});

// ------------------------------------------------------------------ ligado
caso("ligado falso: nada, e o estado volta intacto", () => {
  const r = m.decidir({ ...LIGADO, ligado: false, percent: 80, armado: true, avisado: false });
  igual(r, { acao: "nada", armado: true, avisado: false }, "desligado");
  const r2 = m.decidir({ ...LIGADO, ligado: false, percent: 80, armado: false, avisado: true });
  igual(r2, { acao: "nada", armado: false, avisado: true }, "desligado preserva estado");
});

// ------------------------------------------------------------------ percent
caso("percent nao numerico: nada, sem mudar estado", () => {
  igual(m.decidir({ ...LIGADO, percent: undefined, armado: false, avisado: true }),
    { acao: "nada", armado: false, avisado: true }, "undefined");
  igual(m.decidir({ ...LIGADO, percent: "80", armado: true, avisado: false }),
    { acao: "nada", armado: true, avisado: false }, "string");
  igual(m.decidir({ ...LIGADO, percent: NaN, armado: true, avisado: false }),
    { acao: "nada", armado: true, avisado: false }, "NaN");
});

// ------------------------------------------------------------------ rearme
caso("percent abaixo do limiar: nada e rearma (armado true, avisado false)", () => {
  igual(m.decidir({ ...LIGADO, percent: 59, armado: false, avisado: true }),
    { acao: "nada", armado: true, avisado: false }, "abaixo rearma");
});

caso("percent exatamente no limiar nao rearma: nao e abaixo", () => {
  igual(m.decidir({ ...LIGADO, percent: 60, armado: false, avisado: false }),
    { acao: "nada", armado: false, avisado: false }, "no limiar nao rearma");
});

// ------------------------------------------------------------------ desarmado
caso("desarmado acima do limiar: nada, estado intacto", () => {
  igual(m.decidir({ ...LIGADO, percent: 70, armado: false, avisado: true }),
    { acao: "nada", armado: false, avisado: true }, "desarmado");
});

// ------------------------------------------------------------------ agente
caso("agente rodando avisa uma vez e nao compacta", () => {
  const r1 = m.decidir({ ...LIGADO, percent: 70, agenteRodando: true });
  igual(r1, { acao: "avisar", armado: true, avisado: true }, "1a chamada avisa");
  const r2 = m.decidir({ ...LIGADO, percent: 71, agenteRodando: true, armado: r1.armado, avisado: r1.avisado });
  igual(r2, { acao: "nada", armado: true, avisado: true }, "2a chamada nao avisa de novo");
  afirma(r2.armado === true, "armado deve seguir true com agente rodando");
  afirma(r2.acao !== "compactar", "nao pode compactar com agente rodando");
});

caso("agente rodando sem aviso previo: avisa e fica armado", () => {
  const r = m.decidir({ ...LIGADO, percent: 65, agenteRodando: true, avisado: false });
  igual(r, { acao: "avisar", armado: true, avisado: true }, "avisar");
});

caso("agente termina com uso ainda acima: compacta", () => {
  const r1 = m.decidir({ ...LIGADO, percent: 70, agenteRodando: true });
  const r2 = m.decidir({ ...LIGADO, percent: 75, agenteRodando: false, armado: r1.armado, avisado: r1.avisado });
  igual(r2, { acao: "compactar", armado: false, avisado: true }, "compacta ao sair do agente");
});

// ------------------------------------------------------------------ compactar
caso("armado, acima do limiar, sem agente: compactar e desarma", () => {
  igual(m.decidir({ ...LIGADO, percent: 61 }),
    { acao: "compactar", armado: false, avisado: false }, "compactar");
});

// ------------------------------------------------------------------ sequencias
caso("sequencia 30 -> 61 -> 61 -> 20 -> 65 compacta uma vez por subida", () => {
  let armado = true;
  let avisado = false;
  const acoes = [];
  for (const percent of [30, 61, 61, 20, 65]) {
    const r = m.decidir({ ...LIGADO, percent, armado, avisado });
    acoes.push(r.acao);
    armado = r.armado;
    avisado = r.avisado;
  }
  igual(acoes, ["nada", "compactar", "nada", "nada", "compactar"], "acoes da sequencia");
  igual(acoes.filter((a) => a === "compactar").length, 2, "exatamente 2 compactar");
});

// ------------------------------------------------------------------ textos
caso("textoAviso com agente rodando: texto do aviso com o percentual arredondado", () => {
  igual(m.textoAviso(72.4, true),
    "contexto em 72%: agente rodando, compacto quando ele voltar (ou faça a passagem)", "texto com agente");
});

caso("textoAviso sem agente: compactado em N% arredondado", () => {
  igual(m.textoAviso(72.6, false), "compactado em 73%", "texto sem agente");
});

// ------------------------------------------------------------------ execucao
(async () => {
  m = await import(COMPACTAR);
  let ok = 0;
  let falhou = 0;
  for (const [nome, fn] of casos) {
    try {
      await fn();
      ok += 1;
      console.log("  ok    " + nome);
    } catch (e) {
      falhou += 1;
      console.log("  FALHA " + nome);
      console.log("        " + String((e && e.message) || e).split("\n").join("\n        "));
    }
  }
  console.log(ok + " ok, " + falhou + " falha(s), 0 skipped");
  process.exit(falhou === 0 ? 0 : 1);
})();
