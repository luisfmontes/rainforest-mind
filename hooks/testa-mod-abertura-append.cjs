#!/usr/bin/env node
// @categoria: bateria
//
// Bateria do caminho do append do mod da abertura (conta com `cc-plugin-sec-default`, que
// barra `prompt.compose` e `classic.SessionStart`): hooks/register.ts liga
// engine.create, session.start, session.end, prompt.submit e session.compact, e a logica
// mora em hooks/abertura-mod-puro.mjs. Uso: node hooks/testa-mod-abertura-append.cjs
//
// Como a bateria vizinha (testa-mod-abertura.cjs): carrega o register.ts REAL com um `$`
// falso, e `process.run` EXECUTA os geradores de verdade sobre fixture em diretorio
// temporario. Nenhum caso afirma sobre o texto do fonte, so sobre as chamadas feitas ao
// `$` falso (`session.append`, `session.messages`).
//
// A mutacao (`temMarca` -> `return false;` e `barraCompose` -> `return false;` no .mjs)
// e rodada por `scripts/conferir-mutacao.cjs`: o caso b e o caso a precisam ficar vermelhos.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFile, execFileSync } = require("node:child_process");
const { pathToFileURL } = require("node:url");

const SRC = path.resolve(__dirname, "..");
const MJS = pathToFileURL(path.join(SRC, "hooks", "abertura-mod-puro.mjs")).href;
const REGISTER = pathToFileURL(path.join(SRC, "hooks", "register.ts")).href;

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
function afirma(cond, msg) {
  if (!cond) throw new Error(msg);
}
function igual(a, b, msg) {
  if (a !== b) throw new Error(`${msg}\n        esperado: ${JSON.stringify(b)}\n        veio    : ${JSON.stringify(a)}`);
}

// ------------------------------------------------------------------- fixtures
const BASE = caixa("rfm-mod-append-");
const DADOS = path.join(BASE, "dados");
const PROJ = path.join(BASE, "rainforest-mind");
const CFG = path.join(BASE, "cfg");
for (const d of [DADOS, PROJ, CFG]) fs.mkdirSync(d, { recursive: true });
execFileSync("git", ["init", "-q", PROJ]);

{
  const L = ["# Foco", "", "## Ativo", "", "**Foco de fixture** `[trabalho]` — declarado 2026-08-06.",
    "Ociosidade maxima: 15 min.", "Criterio de pronto: a fixture exercita o mod.", "", "Avanços:"];
  for (let i = 1; i <= 3; i++) L.push(`- 2026-09-0${i} (fixture): **avanco ${i}.**`);
  L.push("", "## Compromissos com prazo", "", "- **Entrega de fixture ate 2026-12-31** — compromisso residente.", "");
  fs.writeFileSync(path.join(DADOS, "FOCO.md"), L.join("\r\n") + "\r\n");
}

function envBase() {
  return {
    ...process.env,
    WHATSAPP_API_BASE_URL: "",
    RFM_ROOT: DADOS,
    CLAUDE_PROJECT_DIR: PROJ,
    CLAUDE_CONFIG_DIR: CFG,
    RFM_SETTINGS_PATH: path.join(CFG, "settings.json"),
  };
}

function montarBancoDeMemoria() {
  const env = { ...process.env, RFM_ROOT: DADOS };
  execFileSync(process.execPath, [path.join(SRC, "scripts", "memoria.cjs"), "iniciar"], { env, stdio: "ignore" });
  const { DatabaseSync } = require("node:sqlite");
  const { chaveHarness } = require(path.join(SRC, "scripts", "memoria.cjs"));
  const db = new DatabaseSync(path.join(DADOS, "rainforest.db"));
  const ins = db.prepare("INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)");
  for (let i = 1; i <= 14; i++) {
    const dia = String(10 + i).padStart(2, "0");
    ins.run(chaveHarness(PROJ), `## Obs ${i}\n\nSubtitulo da observacao ${i}\n\n### Detalhe\n\ncorpo`, `2026-09-${dia}T10:00:00Z`, `sessao:teste:offset:${i}`);
  }
  db.close();
}
montarBancoDeMemoria();

function executar(argv, init) {
  return new Promise((resolve) => {
    execFile(argv[0], argv.slice(1), {
      cwd: init.cwd,
      env: { ...envBase(), ...(init.env || {}) },
      timeout: init.timeoutMs,
      maxBuffer: 16 * 1024 * 1024,
      encoding: "utf8",
    }, (erro, stdout, stderr) => {
      resolve({
        exitCode: erro ? (typeof erro.code === "number" ? erro.code : 1) : 0,
        stdout: stdout || "",
        stderr: stderr || "",
        isStdoutTruncated: false,
        isStderrTruncated: false,
      });
    });
  });
}
const cache = new Map();
async function runReal(argv, init) {
  const chave = argv.join(" ");
  if (!cache.has(chave)) cache.set(chave, await executar(argv, init));
  return cache.get(chave);
}

// `$` falso: guarda toda chamada a session.append / session.messages / process.run.
function criar$({ mensagens = [], append } = {}) {
  const t = { appends: [], leituras: 0, rodadas: 0 };
  return {
    t,
    plugin: { name: "rainforest-mind", root: SRC.replace(/\\/g, "/") },
    session: {
      cwd: async () => PROJ,
      messages: async () => { t.leituras += 1; return typeof mensagens === "function" ? mensagens() : mensagens; },
      append: async (args) => {
        t.appends.push(args);
        if (append) return append(args);
        return { uuid: "u", message: args.message };
      },
    },
    process: { run: async (argv, init) => { t.rodadas += 1; return runReal(argv, init); } },
  };
}

// register.ts de verdade ligado a um `on` falso que guarda o hook de cada evento.
async function modulo() {
  const { register } = await import(REGISTER);
  const { MARCA } = await import(MJS);
  const novo = () => {
    const hooks = new Map();
    register((evento, ...resto) => { hooks.set(evento, resto[resto.length - 1]); });
    const chama = (evento) => ($, e, next) => hooks.get(evento)($, e, next);
    return {
      engineCreate: chama("engine.create"),
      sessionStart: chama("session.start"),
      sessionEnd: chama("session.end"),
      promptSubmit: chama("prompt.submit"),
      sessionCompact: chama("session.compact"),
      promptCompose: chama("prompt.compose"),
    };
  };
  return { novo, MARCA };
}

const COM_SEC = ["cc-plugin-sec-default", "rainforest-mind", "cc-plugin-agents-md", "cc-plugin-telemetry", "cc-plugin-you-should-know"];
const SEM_SEC = ["rainforest-mind", "cc-plugin-agents-md", "cc-plugin-telemetry"];
const passa = (valor) => async () => valor;

async function ligar(mod, plugins) {
  const r = await mod.engineCreate({}, { plugins }, async (e) => ({ eco: e }));
  afirma(r && r.eco && r.eco.plugins === plugins, "engine.create nao devolveu next(e) intacto");
}

// Texto que o prompt.compose entregaria nesta mesma fixture.
async function textoDoCompose(novo) {
  const m = novo();
  const r = await m.promptCompose(criar$(), { traits: [] }, async () => ({ sections: [] }));
  const s = r.sections.find((x) => x.id === "rainforest-mind:abertura");
  afirma(s && s.text, "compose nao entregou a secao (fixture quebrada)");
  return s.text;
}

// ------------------------------------------------------------------ casos
const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);

caso("conta com sec-default anexa uma vez no session.start", async () => {
  const { novo, MARCA } = await modulo();
  const mod = novo();
  const $ = criar$();
  await ligar(mod, COM_SEC);
  const r = await mod.sessionStart($, { source: "startup" }, async (e) => ({ eco: e }));
  afirma(r && r.eco && r.eco.source === "startup", "session.start nao devolveu next(e)");
  igual($.t.appends.length, 1, "numero de appends");
  const a = $.t.appends[0];
  igual(JSON.stringify(Object.keys(a)), JSON.stringify(["message"]), "so `message` no append");
  igual(a.message.type, "user", "type");
  igual(a.message.content.length, 1, "um bloco");
  igual(a.message.content[0].type, "text", "bloco de texto");
  const texto = a.message.content[0].text;
  const esperado = await textoDoCompose(novo);
  afirma(esperado.length > 0, "texto do compose vazio");
  igual(texto, `${MARCA}\n${esperado}`, "texto do append = MARCA + texto do compose");
  igual($.t.rodadas, 2, "geradores rodaram uma vez (foco + memoria)");
});

caso("resume com a marca no transcript nao anexa de novo", async () => {
  const { novo, MARCA } = await modulo();
  const mod = novo();
  const $ = criar$({ mensagens: [
    { role: "user", text: "oi", toolUses: [] },
    { role: "user", text: `${MARCA}\nabertura de antes`, toolUses: [] },
  ] });
  await ligar(mod, COM_SEC);
  await mod.sessionStart($, { source: "resume" }, passa({}));
  igual($.t.appends.length, 0, "appends");
  afirma($.t.leituras >= 1, "o transcript nao foi lido");
});

caso("clear anexa uma vez no primeiro prompt.submit", async () => {
  const { novo } = await modulo();
  const mod = novo();
  const $ = criar$();
  await ligar(mod, COM_SEC);
  await mod.sessionEnd($, { reason: "clear" }, passa({}));
  igual($.t.appends.length, 0, "session.end nao anexa");
  const e1 = { prompt: "um" };
  const r1 = await mod.promptSubmit($, e1, async (e) => ({ eco: e }));
  igual($.t.appends.length, 1, "appends depois do 1o submit");
  afirma(r1.eco === e1, "1o submit nao devolveu next(e) intacto");
  const e2 = { prompt: "dois" };
  const r2 = await mod.promptSubmit($, e2, async (e) => ({ eco: e }));
  igual($.t.appends.length, 1, "appends depois do 2o submit");
  afirma(r2.eco === e2, "2o submit nao devolveu next(e) intacto");
});

caso("compact sem a marca reanexa", async () => {
  const { novo } = await modulo();
  const mod = novo();
  const $ = criar$();
  await ligar(mod, COM_SEC);
  const r = { messages: [{ role: "user", text: "resumo da conversa", toolUses: [] }] };
  const saiu = await mod.sessionCompact($, { trigger: "manual", messages: [] }, passa(r));
  igual($.t.appends.length, 1, "appends");
  afirma(saiu === r, "session.compact nao devolveu o resultado de next(e) intacto");
});

caso("compact com a marca nao reanexa", async () => {
  const { novo, MARCA } = await modulo();
  const mod = novo();
  const $ = criar$();
  await ligar(mod, COM_SEC);
  const r = { messages: [
    { role: "user", text: "resumo", toolUses: [] },
    { role: "user", content: [{ type: "text", text: `${MARCA}\nabertura` }], text: "", toolUses: [] },
  ] };
  const saiu = await mod.sessionCompact($, { trigger: "auto", messages: [] }, passa(r));
  igual($.t.appends.length, 0, "appends");
  afirma(saiu === r, "session.compact nao devolveu o resultado de next(e) intacto");
});

caso("conta sem sec-default nao anexa nem le messages", async () => {
  const { novo } = await modulo();
  const mod = novo();
  const $ = criar$();
  await ligar(mod, SEM_SEC);
  await mod.sessionStart($, { source: "startup" }, passa({}));
  await mod.sessionEnd($, { reason: "clear" }, passa({}));
  await mod.promptSubmit($, { prompt: "um" }, passa({}));
  await mod.sessionCompact($, { trigger: "manual", messages: [] }, passa({ messages: [{ role: "user", text: "x", toolUses: [] }] }));
  igual($.t.appends.length, 0, "appends");
  igual($.t.leituras, 0, "chamadas a messages()");
  igual($.t.rodadas, 0, "geradores nao devem rodar");
});

caso("append que lanca nao quebra o session.start", async () => {
  const { novo } = await modulo();
  const mod = novo();
  const $ = criar$({ append: () => { throw new Error("append recusado"); } });
  await ligar(mod, COM_SEC);
  const e = { source: "startup" };
  const r = await mod.sessionStart($, e, async (x) => ({ eco: x }));
  igual($.t.appends.length, 1, "o append foi tentado");
  afirma(r && r.eco === e, "session.start nao devolveu o resultado de next(e)");
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
  limpar();
  console.log(`== resultado: ${ok} ok, ${falhou} falha(s), 0 skipped ==`);
  process.exit(falhou === 0 ? 0 : 1);
})();
