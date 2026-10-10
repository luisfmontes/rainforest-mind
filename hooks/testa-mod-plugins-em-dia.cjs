#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da logica pura do plugins-em-dia (hooks/plugins-em-dia-puro.mjs).
// Uso: node hooks/testa-mod-plugins-em-dia.cjs
//
// Dados: duas formas de installed_plugins.json (versao 2), com a forma real de cada entrada
// e os caminhos trocados por <home>/... . Nenhum caso afirma sobre o texto do fonte.
//
// A mutacao do filtro de alvos (`.some(i => i.scope === 'user')` -> `.length > 0`) e rodada
// por `scripts/conferir-mutacao.cjs`; o caso "plugin instalado so no escopo local fica fora"
// precisa ficar vermelho.

const path = require("node:path");
const { pathToFileURL } = require("node:url");

const PURO = pathToFileURL(path.join(__dirname, "plugins-em-dia-puro.mjs")).href;
const importar = (u) => import(u);

const RAIZ = "rainforest-mind@rainforest-mind";
const TRAB = "plugin-trabalho@mkt-trabalho";

// Forma real do installed_plugins.json: plugins: { "nome@mkt": [ { scope, version, installPath, ... } ] }.
const FIX = {
  version: 2,
  plugins: {
    [RAIZ]: [
      {
        scope: "user",
        installPath: "<home>/plugins/cache/rainforest-mind/rainforest-mind/1.53.0",
        version: "1.53.0",
        installedAt: "2026-08-08T15:56:01.994Z",
        lastUpdated: "2026-10-09T13:47:15.749Z",
        gitCommitSha: "658b2c8a3eca0c22d4b9f55198172a7c13c26d9f",
      },
    ],
    [TRAB]: [
      {
        scope: "local",
        projectPath: "<home>/trabalho/projeto",
        installPath: "<home>/plugins/cache/mkt-trabalho/plugin-trabalho/1.58.0",
        version: "1.58.0",
        installedAt: "2026-08-10T10:14:02.878Z",
        lastUpdated: "2026-10-08T14:06:37.238Z",
        gitCommitSha: "a497eeffbfafca4b8b4262611e5cc400a5d57d3f",
      },
      {
        scope: "user",
        installPath: "<home>/plugins/cache/mkt-trabalho/plugin-trabalho/1.59.0",
        version: "1.59.0",
        installedAt: "2026-08-22T09:09:39.861Z",
        lastUpdated: "2026-10-08T14:06:23.684Z",
        gitCommitSha: "a497eeffbfafca4b8b4262611e5cc400a5d57d3f",
      },
    ],
  },
};

// Variante: o plugin de trabalho so tem a entrada local.
const FIX_SO_LOCAL = {
  version: 2,
  plugins: {
    [RAIZ]: FIX.plugins[RAIZ],
    [TRAB]: FIX.plugins[TRAB].filter((i) => i.scope === "local"),
  },
};

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);
const afirma = (cond, msg) => { if (!cond) throw new Error(msg); };
const igual = (a, b, msg) => {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${msg}\n  obtido:   ${x}\n  esperado: ${y}`);
};

caso("constantes: lista padrao, periodo de 3 h e intervalo minimo de 30 min", async () => {
  const P = await importar(PURO);
  igual(P.LISTA_PADRAO, [RAIZ], "LISTA_PADRAO");
  igual(P.PERIODO_MS, 10800000, "PERIODO_MS");
  igual(P.INTERVALO_MINIMO_MS, 1800000, "INTERVALO_MINIMO_MS");
});

caso("alvos: plugin com entrada user entra, mantendo a ordem da lista", async () => {
  const P = await importar(PURO);
  igual(P.alvos(FIX, [RAIZ, TRAB]), [RAIZ, TRAB], "ordem da lista");
  igual(P.alvos(FIX, [TRAB, RAIZ]), [TRAB, RAIZ], "ordem invertida");
});

caso("plugin instalado so no escopo local fica fora", async () => {
  const P = await importar(PURO);
  igual(P.alvos(FIX_SO_LOCAL, [RAIZ, TRAB]), [RAIZ], "so o user entra");
});

caso("id ausente do registro fica fora sem erro", async () => {
  const P = await importar(PURO);
  igual(P.alvos(FIX, ["nao-existe@outro"]), [], "id fora do registro");
});

caso("versoes: pega a versao da entrada user, nao a local", async () => {
  const P = await importar(PURO);
  igual(P.versoes(FIX, [RAIZ, TRAB]), { [RAIZ]: "1.53.0", [TRAB]: "1.59.0" }, "versoes com local e user");
});

caso("versoes: id sem entrada user fica fora do mapa", async () => {
  const P = await importar(PURO);
  igual(P.versoes(FIX_SO_LOCAL, [RAIZ, TRAB]), { [RAIZ]: "1.53.0" }, "versoes so com local");
});

caso("marketplaces: cada um uma vez, na ordem dos alvos", async () => {
  const P = await importar(PURO);
  igual(P.marketplaces([RAIZ, TRAB, "outro@mkt-trabalho"]), ["rainforest-mind", "mkt-trabalho"], "dedupe por mercado");
});

caso("subiram: so o que mudou, como nome antes -> depois", async () => {
  const P = await importar(PURO);
  igual(
    P.subiram({ [RAIZ]: "1.53.0", [TRAB]: "1.59.0" }, { [RAIZ]: "1.54.0", [TRAB]: "1.59.0" }),
    ["rainforest-mind 1.53.0 -> 1.54.0"],
    "so o que subiu",
  );
  igual(P.subiram({ [RAIZ]: "1.53.0" }, { [RAIZ]: "1.53.0" }), [], "nada mudou");
});

caso("podeRodar: no limite de 30 min roda; 1 ms antes nao; forcado sempre roda", async () => {
  const P = await importar(PURO);
  igual(P.podeRodar(0, 1800000, false), true, "exatamente 30 min");
  igual(P.podeRodar(0, 1799999, false), false, "1 ms antes dos 30 min");
  igual(P.podeRodar(1000, 1001, true), true, "forcado logo depois");
});

caso("acaoAposSubir: sem subida nada; com subida recarrega se seguro, senao avisa", async () => {
  const P = await importar(PURO);
  igual(P.acaoAposSubir([], true), "nada", "sem subida, seguro");
  igual(P.acaoAposSubir([], false), "nada", "sem subida, inseguro");
  igual(P.acaoAposSubir(["rainforest-mind 1.53.0 -> 1.54.0"], true), "recarregar", "subiu, seguro");
  igual(P.acaoAposSubir(["rainforest-mind 1.53.0 -> 1.54.0"], false), "avisar", "subiu, inseguro");
});

caso("comandos: marketplace update por mercado primeiro, depois plugin update por alvo", async () => {
  const P = await importar(PURO);
  igual(P.comandos([RAIZ, TRAB]), [
    ["plugin", "marketplace", "update", "rainforest-mind"],
    ["plugin", "marketplace", "update", "mkt-trabalho"],
    ["plugin", "update", RAIZ, "--scope", "user"],
    ["plugin", "update", TRAB, "--scope", "user"],
  ], "ordem dos comandos");
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
      console.log(`        ${String((e && e.message) || e).split("\n").join("\n        ")}`);
    }
  }
  console.log(`${ok} ok, ${falhou} falha(s), 0 skipped`);
  process.exit(falhou === 0 ? 0 : 1);
})();
