#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da logica pura do mapa da sessao (hooks/mapa-puro.mjs).
// Uso: node hooks/testa-mod-mapa.cjs
// Chamadas no formato do `tool.call` do engine: `tool` mais os argumentos ao lado.

const path = require("node:path");
const { pathToFileURL } = require("node:url");

const MJS = pathToFileURL(path.resolve(__dirname, "mapa-puro.mjs")).href;
const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);
const afirma = (c, m) => { if (!c) throw new Error(m); };
const igual = (a, b, m) => {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error(`${m}\n  obtido:   ${x}\n  esperado: ${y}`);
};
let _m;
const mod = async () => (_m ??= await import(MJS));

caso("ler nao entra em arquivos escritos: Read e Bash devolvem nulo", async () => {
  const m = await mod();
  igual(m.escritaDe({ tool: "Read", file_path: "hooks/mod.tsx" }), null, "Read");
  igual(m.escritaDe({ tool: "Bash", command: "echo oi > x.txt" }), null, "Bash");
  const r = m.registrar(m.mapaVazio(), { tool: "Read", file_path: "hooks/mod.tsx" });
  igual(r.mapa.arquivos, [], "Read nao registra");
  igual(r.novo, false, "Read nao e novo");
});
caso("Write e Edit devolvem file_path", async () => {
  const m = await mod();
  igual(m.escritaDe({ tool: "Write", file_path: "hooks/mod.tsx", content: "x" }), "hooks/mod.tsx", "Write");
  igual(m.escritaDe({ tool: "Edit", file_path: "a/b.js", old_string: "a", new_string: "b" }), "a/b.js", "Edit");
});
caso("NotebookEdit devolve notebook_path", async () => {
  const m = await mod();
  igual(m.escritaDe({ tool: "NotebookEdit", notebook_path: "n/a.ipynb" }), "n/a.ipynb", "NotebookEdit");
  igual(m.escritaDe({ tool: "NotebookEdit", file_path: "n/a.ipynb" }), null, "sem notebook_path");
});
caso("servidorDe acha o servico MCP e devolve nulo para ferramenta nativa", async () => {
  const m = await mod();
  igual(m.servidorDe("mcp__claude_ai_Claude_Docs__guide"), "claude_ai_Claude_Docs", "mcp");
  igual(m.servidorDe("Bash"), null, "Bash");
});
caso("arquivo repetido conta uma vez e devolve novo false na 2a escrita", async () => {
  const m = await mod();
  const e = { tool: "Edit", file_path: "scripts/estado.cjs" };
  const a = m.registrar(m.mapaVazio(), e);
  igual(a.novo, true, "1a");
  const b = m.registrar(a.mapa, e);
  igual(b.novo, false, "2a");
  igual(b.mapa.arquivos.length, 1, "uma entrada");
});
caso("skill pelo campo skill, uma vez so", async () => {
  const m = await mod();
  const a = m.registrar(m.mapaVazio(), { tool: "Skill", skill: "plano" });
  igual(a.mapa.skills, ["plano"], "skill");
  igual(a.novo, true, "novo");
  igual(m.registrar(a.mapa, { tool: "Skill", skill: "plano" }).novo, false, "repetida");
});
caso("servico MCP entra em servicos", async () => {
  const m = await mod();
  const a = m.registrar(m.mapaVazio(), { tool: "mcp__claude_ai_Claude_Docs__guide" });
  igual(a.mapa.servicos, ["claude_ai_Claude_Docs"], "servico");
});
caso("subagente pelo description do agent.spawn", async () => {
  const m = await mod();
  const a = m.registrar(m.mapaVazio(), { agente: true, description: "revisar o diff" });
  igual(a.mapa.subagentes, ["revisar o diff"], "subagente");
  igual(a.novo, true, "novo");
});
caso("teto por categoria", async () => {
  const m = await mod();
  let mapa = m.mapaVazio();
  for (let i = 0; i < m.TETO + 10; i++) {
    mapa = m.registrar(mapa, { tool: "Write", file_path: `f${i}.txt` }).mapa;
    mapa = m.registrar(mapa, { tool: "Skill", skill: `s${i}` }).mapa;
    mapa = m.registrar(mapa, { agente: true, description: `a${i}` }).mapa;
    mapa = m.registrar(mapa, { tool: `mcp__srv${i}__x` }).mapa;
  }
  for (const k of ["arquivos", "skills", "servicos", "subagentes"]) igual(mapa[k].length, m.TETO, k);
  igual(mapa.arquivos[0].caminho, "f10.txt", "sai o mais antigo");
});
caso("desvio marcado nao se perde: reescrita, teto e novo registro", async () => {
  const m = await mod();
  let mapa = m.registrar(m.mapaVazio(), { tool: "Edit", file_path: "fora.js" }).mapa;
  mapa = m.registrar(mapa, { desvio: true, caminho: "fora.js" }).mapa;
  mapa = m.registrar(mapa, { tool: "Edit", file_path: "fora.js" }).mapa;
  igual(mapa.arquivos[0].desvio, true, "reescrita mantem");
  for (let i = 0; i < m.TETO + 5; i++) mapa = m.registrar(mapa, { tool: "Write", file_path: `f${i}.txt` }).mapa;
  const fora = mapa.arquivos.find(a => a.caminho === "fora.js");
  afirma(fora && fora.desvio === true, "teto expulsou o desvio");
  igual(mapa.arquivos.length, m.TETO, "teto");
});
caso("caminho com caractere de controle limpo", async () => {
  const m = await mod();
  const esc = String.fromCharCode(27);
  const c = m.escritaDe({ tool: "Write", file_path: `a${esc}[31mb\n.txt` });
  afirma(!/[\u0000-\u001f]/.test(c), "controle sobrou");
  afirma(c.includes("b") && c.includes(".txt"), "texto util sumiu");
  igual(m.semControle(`x${esc}y`), "x y", "semControle");
});

caso("trocarCaminho: absoluto vira relativo no mesmo lugar, e funde com o relativo que ja existe (#421)", async () => {
  const m = await mod();
  let mapa = m.registrar(m.mapaVazio(), { tool: "Write", file_path: "/p/a.cjs" }).mapa;
  mapa = m.registrar(mapa, { desvio: true, caminho: "b.cjs" }).mapa;
  igual(m.trocarCaminho(mapa, "/p/a.cjs", "a.cjs").arquivos, [{ caminho: "a.cjs", desvio: false }, { caminho: "b.cjs", desvio: true }], "renomeia");
  igual(m.trocarCaminho(mapa, "/p/a.cjs", "b.cjs").arquivos, [{ caminho: "b.cjs", desvio: true }], "funde sem perder o vermelho");
  igual(m.trocarCaminho(mapa, "/p/nada.cjs", "x").arquivos, mapa.arquivos, "sem a origem nada muda");
});

(async () => {
  let ok = 0, falhou = 0;
  for (const [nome, fn] of casos) {
    try { await fn(); ok++; console.log(`  ok    ${nome}`); }
    catch (e) { falhou++; console.log(`  FALHA ${nome}\n        ${String(e && e.message || e).split("\n").join("\n        ")}`); }
  }
  console.log(`== resultado: ${ok} ok, ${falhou} falha(s), 0 skipped ==`);
  process.exit(falhou === 0 ? 0 : 1);
})();
