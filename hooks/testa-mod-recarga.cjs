#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da logica pura do marcador de recarga (hooks/recarga-puro.mjs).
// Uso: node hooks/testa-mod-recarga.cjs
//
// A mutacao do "ja tratado" (`m.at <= tratadoEm` -> `if (false)`) e rodada por
// `scripts/conferir-mutacao.cjs`; o caso "o mesmo marcador age uma vez so" precisa ficar
// vermelho.

const path = require("node:path");
const { pathToFileURL } = require("node:url");

const PURO = pathToFileURL(path.join(__dirname, "recarga-puro.mjs")).href;
const importar = (u) => import(u);

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);
const igual = (veio, esperado, rotulo) => {
  if (veio !== esperado) throw new Error(`${rotulo}\n        esperado: ${JSON.stringify(esperado)}\n        veio    : ${JSON.stringify(veio)}`);
};

let m;

caso("caminho do marcador: CLAUDE_CONFIG_DIR, e HOME/.claude sem ele", () => {
  igual(m.caminhoMarcador({ CLAUDE_CONFIG_DIR: "<home>/.claude-personal", HOME: "<home>" }),
    "<home>/.claude-personal/plugins/data/rainforest-mind-rainforest-mind/recarga-pedida.json", "com config dir");
  igual(m.caminhoMarcador({ HOME: "<home>" }),
    "<home>/.claude/plugins/data/rainforest-mind-rainforest-mind/recarga-pedida.json", "sem config dir");
});

caso("texto e leitura fazem ida e volta", () => {
  igual(JSON.stringify(m.lerMarcador(m.textoMarcador(1700000000000))), JSON.stringify({ at: 1700000000000 }), "ida e volta");
});

caso("leitura recusa ausente, quebrado, outra versao e at nao numerico", () => {
  for (const t of [undefined, null, "", "{", "null", '{"v":2,"at":5}', '{"v":1,"at":"5"}', '{"v":1}', '{"v":1,"at":null}']) {
    igual(m.lerMarcador(t), null, `texto ${JSON.stringify(t)}`);
  }
});

caso("marcador depois do carregamento age; antes ou igual nao", () => {
  igual(m.deveRecarregar({ marcador: m.textoMarcador(200), carregadoEm: 100, tratadoEm: null }), 200, "depois");
  igual(m.deveRecarregar({ marcador: m.textoMarcador(100), carregadoEm: 100, tratadoEm: null }), null, "igual");
  igual(m.deveRecarregar({ marcador: m.textoMarcador(50), carregadoEm: 100, tratadoEm: null }), null, "antes");
});

caso("o mesmo marcador age uma vez so", () => {
  const marcador = m.textoMarcador(200);
  const primeiro = m.deveRecarregar({ marcador, carregadoEm: 100, tratadoEm: null });
  igual(primeiro, 200, "primeira leitura");
  igual(m.deveRecarregar({ marcador, carregadoEm: 100, tratadoEm: primeiro }), null, "segunda leitura do mesmo marcador");
  igual(m.deveRecarregar({ marcador: m.textoMarcador(300), carregadoEm: 100, tratadoEm: primeiro }), 300, "marcador mais novo age de novo");
});

caso("marcador ilegivel nao age", () => {
  igual(m.deveRecarregar({ marcador: "lixo", carregadoEm: 0, tratadoEm: null }), null, "lixo");
  igual(m.deveRecarregar({ marcador: undefined, carregadoEm: 0, tratadoEm: null }), null, "ausente");
});

// ------------------------------------------------------------------ execucao
(async () => {
  m = await importar(PURO);
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
      console.log(`        ${String((e && e.message) || e).split("\n").join("\n        ")}`);
    }
  }
  console.log(`${ok} ok, ${falhou} falha(s), 0 skipped`);
  process.exit(falhou === 0 ? 0 : 1);
})();
