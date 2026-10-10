#!/usr/bin/env node
// @categoria: bateria
//
// Bateria do mod da abertura (hooks/abertura-mod-puro.mjs, ligado por hooks/register.ts).
// Uso: node hooks/testa-mod-abertura.cjs
//
// O mod nao roda em Node: o engine o carrega num ambiente sem Node. Esta bateria importa
// o .mjs puro e injeta um `$` falso cujo `process.run` EXECUTA DE VERDADE os dois
// geradores (`foco-session-start.cjs --destino mod` e `memoria-session-start.cjs
// --destino mod`) sobre dados de FIXTURE em diretorio temporario (FOCO.md CRLF e banco
// de memoria com 14 observacoes), nunca sobre o ~/.rainforest vivo: ele muda todo dia e
// uma bateria que depende dele passa e falha sem que ninguem a toque.
//
// O que precisa provar:
//   1. register.ts liga exatamente session.end, prompt.compose e classic.SessionStart;
//   2. a secao e UMA, `{ id: 'rainforest-mind:abertura', scope: 'session' }`, no fim de
//      `sections`, com o additionalContext do foco + o da memoria (sem systemMessage);
//   3. montada uma vez: 3 composes seguidos chamam `$.process.run` so 2 vezes;
//   4. `session.end` com reason 'clear' ou 'resume' remonta; outro reason nao;
//   5. `classic.SessionStart` remove so as entradas dos dois hooks da abertura, em tres
//      cenarios reais (memoria normal, so aviso, foco so com ponteiro) mais o fallback de
//      regras ausentes, e mantem a do codex-transfer-session-start.cjs;
//   6. sec-default: nenhum append, nenhum handler de engine.create/session.start/prompt.submit/session.compact;
//   7. gerador com exit != 0, JSON invalido ou timeout devolve `next(e)` intacto e nao
//      remove nada, tambem quando o SessionStart chega ANTES do primeiro compose.
//
// A mutacao (`if (memo) return memo;` -> `if (false) return memo;` no .mjs) e rodada por
// `scripts/conferir-mutacao.cjs`; o caso "tres composes, um unico par de
// $.process.run" precisa ficar vermelho.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFile } = require("node:child_process");
const { pathToFileURL } = require("node:url");

const SRC = path.resolve(__dirname, "..");
const MJS = pathToFileURL(path.join(SRC, "hooks", "abertura-mod-puro.mjs")).href;

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
const BASE = caixa("rfm-mod-abertura-");
const DADOS = path.join(BASE, "dados");
const DADOS_SEM_FOCO = path.join(BASE, "dados-sem-foco");
const PROJ = path.join(BASE, "rainforest-mind");
const CFG = path.join(BASE, "cfg");
for (const d of [DADOS, DADOS_SEM_FOCO, PROJ, CFG]) fs.mkdirSync(d, { recursive: true });
require("node:child_process").execFileSync("git", ["init", "-q", PROJ]);

{
  const L = ["# Foco", "", "## Ativo", "", "**Foco de fixture** `[trabalho]` — declarado 2026-08-06.",
    "Ociosidade maxima: 15 min.", "Criterio de pronto: a fixture exercita o mod.", "", "Avanços:"];
  for (let i = 1; i <= 3; i++) L.push(`- 2026-09-0${i} (fixture): **avanco ${i}.**`);
  L.push("", "## Compromissos com prazo", "", "- **Entrega de fixture ate 2026-12-31** — compromisso residente.", "");
  fs.writeFileSync(path.join(DADOS, "FOCO.md"), L.join("\r\n") + "\r\n");
}

function envBase(raiz) {
  return {
    ...process.env,
    WHATSAPP_API_BASE_URL: "",
    RFM_ROOT: raiz,
    CLAUDE_PROJECT_DIR: PROJ,
    CLAUDE_CONFIG_DIR: CFG,
    RFM_SETTINGS_PATH: path.join(CFG, "settings.json"),
  };
}

// Banco de memoria com 14 observacoes vivas, sob a chave EXATA que o harness usaria.
function montarBancoDeMemoria() {
  const env = { ...process.env, RFM_ROOT: DADOS };
  require("node:child_process").execFileSync(process.execPath, [path.join(SRC, "scripts", "memoria.cjs"), "iniciar"], { env, stdio: "ignore" });
  const { DatabaseSync } = require("node:sqlite");
  const { slugDoCaminho } = require(path.join(SRC, "scripts", "lib", "projeto-canonico.cjs"));
  const db = new DatabaseSync(path.join(DADOS, "rainforest.db"));
  const ins = db.prepare("INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)");
  for (let i = 1; i <= 14; i++) {
    const dia = String(10 + i).padStart(2, "0");
    ins.run(slugDoCaminho(PROJ),`## Obs ${i}\n\nSubtitulo da observacao ${i}\n\n### Detalhe\n\ncorpo`, `2026-09-${dia}T10:00:00Z`, `sessao:teste:offset:${i}`);
  }
  db.close();
}
montarBancoDeMemoria();

// ------------------------------------------------------ execucao real, em cache
function executar(argv, init, raiz) {
  return new Promise((resolve) => {
    execFile(argv[0], argv.slice(1), {
      cwd: init.cwd,
      env: { ...envBase(raiz), ...(init.env || {}) },
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
async function executarComCache(argv, init, raiz) {
  const chave = `${raiz}|${argv.join(" ")}`;
  if (!cache.has(chave)) cache.set(chave, await executar(argv, init, raiz));
  return cache.get(chave);
}

// `$` falso: so o que o mod toca. `run` decide a resposta de cada chamada.
function criar$(run) {
  const chamadas = [];
  return {
    chamadas,
    plugin: { name: "rainforest-mind", root: SRC.replace(/\\/g, "/") },
    session: { cwd: async () => PROJ },
    env: { get: async (nome) => process.env[nome] },
    process: {
      run: async (argv, init) => {
        chamadas.push({ argv, init });
        return run(argv, init);
      },
    },
  };
}
const runReal = (argv, init) => executarComCache(argv, init, DADOS);

const proximo = (sections) => async () => ({ sections });
const SECOES_DO_ENGINE = [
  { id: "intro", text: "intro", scope: "shared" },
  { id: "tone", text: "tone", scope: "shared" },
  { id: "memoria-do-usuario", text: "s", scope: "session" },
];

function geradorDoArgv(argv) {
  return argv.find((a) => /(foco|memoria)-session-start\.cjs$/.test(a)) || "";
}
function additional(r) {
  return JSON.parse(r.stdout).hookSpecificOutput.additionalContext;
}

// Entradas que os hooks ATUAIS (sem a flag) emitem no SessionStart, para o filtro.
async function entradaFocoAtual(raiz) {
  const r = await executarComCache(["node", path.join(SRC, "hooks", "foco-session-start.cjs")], { cwd: PROJ, timeoutMs: 60000 }, raiz);
  igual(r.exitCode, 0, `foco atual saiu ${r.exitCode}: ${r.stderr}`);
  return additional(r);
}
async function entradaMemoriaAtual() {
  const r = await executarComCache(["node", path.join(SRC, "hooks", "memoria-session-start.cjs")], { cwd: PROJ, timeoutMs: 60000 }, DADOS);
  igual(r.exitCode, 0, `memoria atual saiu ${r.exitCode}: ${r.stderr}`);
  return additional(r);
}
// O codex-transfer-session-start.cjs so grava variaveis no CLAUDE_ENV_FILE; este texto e
// o representante de "entrada que NAO e da abertura" (nao comeca por nenhum prefixo).
const ENTRADA_CODEX = "RAINFOREST_TRANSCRIPT_PATH=/tmp/t.jsonl\nRAINFOREST_SESSION_ID=abc";

// Carrega o register.ts DE VERDADE (o Node 24 remove os tipos ao importar .ts) e o liga a
// um `on` falso que guarda o hook de cada evento: a bateria exercita a fiacao real, nao
// uma copia dela. Cada `criarAbertura()` chama `register` de novo, ou seja, um mod novo
// com o estado (a promessa memoizada) zerado.
const REGISTER = pathToFileURL(path.join(SRC, "hooks", "register.ts")).href;
async function modulo() {
  const { register } = await import(REGISTER);
  const { ehEntradaDaAbertura } = await import(MJS);
  const criarAbertura = () => {
    const hooks = new Map();
    const eventos = [];
    register((evento, ...resto) => {
      eventos.push(evento);
      hooks.set(evento, resto[resto.length - 1]);
    });
    return {
      eventos,
      sessionEnd: ($, e, next) => hooks.get("session.end")($, e, next),
      promptCompose: ($, e, next) => hooks.get("prompt.compose")($, e, next),
      sessionStart: ($, e, next) => hooks.get("classic.SessionStart")($, e, next),
    };
  };
  return { criarAbertura, ehEntradaDaAbertura };
}

// ------------------------------------------------------------------ runner
const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);

caso("register.ts registra exatamente session.end, prompt.compose e classic.SessionStart", async () => {
  const fonte = fs.readFileSync(path.join(SRC, "hooks", "register.ts"), "utf8");
  const { criarAbertura } = await modulo();
  igual(JSON.stringify(criarAbertura().eventos), JSON.stringify(["session.end", "prompt.compose", "classic.SessionStart"]), "eventos que register() liga");
  afirma(/from '\.\/abertura-mod-puro\.mjs'/.test(fonte), "register.ts precisa importar o .mjs por import estatico");
  const semComentarios = (t) => t.split("\n").filter((l) => !/^\s*(\/\/|\/\*|\*)/.test(l)).join("\n");
  afirma(!/\bimport\(/.test(semComentarios(fonte)) && !/\bimport\(/.test(semComentarios(fs.readFileSync(path.join(SRC, "hooks", "abertura-mod-puro.mjs"), "utf8"))),
    "modulo de mod com import() dinamico nao carrega");
});

caso("sec-default: nenhum append (conta que barra o compose nao recebe a abertura por outro canal)", async () => {
  const { register } = await import(REGISTER);
  const hooks = new Map();
  register((evento, ...resto) => { hooks.set(evento, resto[resto.length - 1]); });
  for (const ev of ["engine.create", "session.start", "prompt.submit", "session.compact"]) {
    afirma(!hooks.has(ev), `register.ts ainda registra handler para ${ev}`);
  }
  const $ = criar$(runReal);
  let appends = 0;
  $.session.append = async () => { appends++; return {}; };
  $.session.messages = async () => [];
  const passa = async (e) => e;
  const dispara = async (ev, e) => { if (hooks.has(ev)) await hooks.get(ev)($, e, passa); };
  await dispara("engine.create", { plugins: ["cc-plugin-sec-default"] });
  await dispara("session.start", { source: "startup" });
  await dispara("prompt.submit", { text: "oi" });
  await dispara("session.end", { reason: "clear" });
  await dispara("prompt.submit", { text: "oi de novo" });
  await dispara("session.compact", {});
  await dispara("prompt.submit", { text: "depois do compact" });
  igual(appends, 0, "chamadas a session.append");
});

caso("o canario saiu: register.ts nao le RFM_CANARIO_MOD", async () => {
  const fonte = fs.readFileSync(path.join(SRC, "hooks", "register.ts"), "utf8");
  afirma(!/CANARIO/.test(fonte), "canario ainda em register.ts");
});

caso("geradores chamados por argv com --destino mod, cwd e CLAUDE_PROJECT_DIR da sessao, timeout 60000", async () => {
  const { criarAbertura } = await modulo();
  const $ = criar$(runReal);
  await criarAbertura().promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  const geradores = $.chamadas.filter((c) => geradorDoArgv(c.argv));
  igual(geradores.length, 2, "numero de chamadas de gerador");
  const scripts = geradores.map((c) => path.basename(geradorDoArgv(c.argv)));
  igual(JSON.stringify(scripts), JSON.stringify(["foco-session-start.cjs", "memoria-session-start.cjs"]), "ordem dos geradores");
  for (const c of geradores) {
    // #480: o node vai por caminho absoluto, achado pelo localizador, nunca pelo nome.
    afirma(path.isAbsolute(c.argv[0]) && path.basename(c.argv[0]).toLowerCase().startsWith("node"), `executavel nao absoluto: ${c.argv[0]}`);
    igual(c.argv.slice(-2).join(" "), "--destino mod", "flag do destino");
    igual(c.init.cwd, SRC.replace(/\\/g, "/"), "cwd");
    igual(c.init.env.CLAUDE_PROJECT_DIR, PROJ, "CLAUDE_PROJECT_DIR");
    igual(c.init.timeoutMs, 60000, "timeout");
    afirma(geradorDoArgv(c.argv).startsWith(SRC.replace(/\\/g, "/") + "/hooks/"), `script fora da raiz do plugin: ${geradorDoArgv(c.argv)}`);
  }
});

caso("localizador do node: roda na pasta do plugin, e sem node achado nenhum gerador roda", async () => {
  const { criarAbertura } = await modulo();
  const $ = criar$(runReal);
  await criarAbertura().promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  const loc = $.chamadas.filter((c) => !geradorDoArgv(c.argv));
  afirma(loc.length > 0, "nenhum localizador rodou");
  for (const c of loc) igual(c.init.cwd, SRC.replace(/\\/g, "/"), "cwd do localizador");
  const semNode = criar$((argv, init) => (geradorDoArgv(argv) ? runReal(argv, init) : Promise.resolve({ exitCode: 1, stdout: "", stderr: "", isStdoutTruncated: false, isStderrTruncated: false })));
  const r = await criarAbertura().promptCompose(semNode, { traits: [] }, proximo(SECOES_DO_ENGINE));
  igual(semNode.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 0, "geradores rodados sem node");
  igual(JSON.stringify(r.sections), JSON.stringify(SECOES_DO_ENGINE), "secoes intactas");
});

caso("uma unica secao rainforest-mind:abertura, scope session, no fim de sections", async () => {
  const { criarAbertura } = await modulo();
  const $ = criar$(runReal);
  const r = await criarAbertura().promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  igual(r.sections.length, SECOES_DO_ENGINE.length + 1, "uma secao a mais");
  igual(JSON.stringify(r.sections.slice(0, 3)), JSON.stringify(SECOES_DO_ENGINE), "secoes do engine intactas e na frente");
  const s = r.sections[r.sections.length - 1];
  igual(s.id, "rainforest-mind:abertura", "id");
  igual(s.scope, "session", "scope");
  igual(Object.keys(s).sort().join(","), "id,scope,text", "campos da secao");
});

caso("texto da secao = additionalContext do foco + o da memoria, sem systemMessage", async () => {
  const { criarAbertura } = await modulo();
  const $ = criar$(runReal);
  const r = await criarAbertura().promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  const texto = r.sections[r.sections.length - 1].text;
  const foco = await executarComCache(["node", path.join(SRC, "hooks", "foco-session-start.cjs"), "--destino", "mod"], { cwd: PROJ, timeoutMs: 60000 }, DADOS);
  const mem = await executarComCache(["node", path.join(SRC, "hooks", "memoria-session-start.cjs"), "--destino", "mod"], { cwd: PROJ, timeoutMs: 60000 }, DADOS);
  const jf = JSON.parse(foco.stdout), jm = JSON.parse(mem.stdout);
  afirma(jf.systemMessage && jm.systemMessage, "fixture deveria gerar systemMessage nos dois (senao o caso nao prova nada)");
  igual(texto, [jf.hookSpecificOutput.additionalContext.trim(), jm.hookSpecificOutput.additionalContext.trim()].join("\n\n"), "texto da secao");
  afirma(texto.startsWith("RAINFOREST MIND ATIVO"), "foco primeiro");
  afirma(texto.indexOf("## Memória (corpus residentes)") > texto.indexOf("RAINFOREST MIND ATIVO"), "memoria depois do foco");
  afirma(!texto.includes(jf.systemMessage), "systemMessage do foco vazou para a secao");
  afirma(!texto.includes(jm.systemMessage.split("\n")[0]), "systemMessage da memoria vazou para a secao");
  afirma(/Elaboração inteira das regras 16, 12, 11, 17/.test(texto), "regras inteiras ausentes (o gerador nao rodou com --destino mod?)");
});

caso("tres composes, um unico par de $.process.run", async () => {
  const { criarAbertura } = await modulo();
  const $ = criar$(runReal);
  const abertura = criarAbertura();
  for (let i = 0; i < 3; i++) await abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  igual($.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 2, "3 composes seguidos devem chamar $.process.run so 2 vezes");
});

caso("compose e SessionStart simultaneos compartilham a mesma montagem", async () => {
  const { criarAbertura } = await modulo();
  const $ = criar$(runReal);
  const abertura = criarAbertura();
  const entradas = [await entradaFocoAtual(DADOS), await entradaMemoriaAtual()];
  await Promise.all([
    abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE)),
    abertura.sessionStart($, { source: "startup" }, async () => ({ additionalContext: entradas })),
  ]);
  igual($.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 2, "montagem unica");
});

caso("session.end com reason clear remonta: o proximo compose roda os geradores de novo", async () => {
  const { criarAbertura } = await modulo();
  const $ = criar$(runReal);
  const abertura = criarAbertura();
  await abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  igual($.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 2, "antes do clear");
  let passou = 0;
  const r = await abertura.sessionEnd($, { reason: "clear" }, async (e) => { passou++; return { ok: e.reason }; });
  igual(passou, 1, "next(e) chamado uma vez");
  igual(r.ok, "clear", "resultado de next repassado");
  const depois = await abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  igual($.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 4, "depois do clear remonta");
  igual(depois.sections.filter((s) => s.id === "rainforest-mind:abertura").length, 1, "ainda uma secao so");
});

caso("session.end com outro reason nao remonta", async () => {
  const { criarAbertura } = await modulo();
  const $ = criar$(runReal);
  const abertura = criarAbertura();
  await abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  await abertura.sessionEnd($, { reason: "other" }, async () => ({}));
  await abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  igual($.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 2, "reason other nao deve remontar");
});

caso("session.end com resume remonta", async () => {
  const { criarAbertura } = await modulo();
  const $ = criar$(runReal);
  const abertura = criarAbertura();
  await abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  igual($.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 2, "antes do resume");
  await abertura.sessionEnd($, { reason: "resume" }, async () => ({}));
  const depois = await abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  igual($.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 4, "depois do resume remonta (novo par de $.process.run)");
  igual(depois.sections.filter((s) => s.id === "rainforest-mind:abertura").length, 1, "ainda uma secao so");
});

caso("classic.SessionStart remove so as entradas dos dois hooks e mantem a do codex-transfer", async () => {
  const { criarAbertura } = await modulo();
  const abertura = criarAbertura();
  const foco = await entradaFocoAtual(DADOS);
  const mem = await entradaMemoriaAtual();
  afirma(foco.startsWith("RAINFOREST MIND ATIVO"), `entrada real do foco comeca por outra coisa: ${foco.slice(0, 40)}`);
  afirma(mem.startsWith("## Memória (corpus residentes)"), `entrada real da memoria comeca por outra coisa: ${mem.slice(0, 40)}`);
  const outra = "contexto de outro plugin";
  const entrada = { additionalContext: [foco, ENTRADA_CODEX, mem, outra], sessionTitle: "t" };
  const r = await abertura.sessionStart(criar$(runReal), { source: "startup" }, async () => entrada);
  igual(JSON.stringify(r.additionalContext), JSON.stringify([ENTRADA_CODEX, outra]), "entradas que restam");
  igual(r.sessionTitle, "t", "demais campos do resultado intactos");
});

// Tres cenarios reais do filtro. O reconhecimento por prefixo e a parte fragil do mod: se
// um texto de abertura mudar e o prefixo nao, a abertura chega duas vezes.
const CENARIOS = [
  ["memoria normal (hook real, 14 observacoes)", () => entradaMemoriaAtual(), "## Memória (corpus residentes)"],
  ["memoria so com aviso de pipeline e de manutencao (montarMemoria real, sem observacoes)", async () => {
    const m = require(path.join(SRC, "hooks", "lib", "memoria-sessao.cjs"));
    return m.montarMemoria({ observacoes: [], avisos: [m.avisoDePipeline(60), m.avisoDeManutencaoFalhou(5)] });
  }, "⚠️ Captura da memória parada"],
  ["memoria com aviso de manutencao antes do corpus (montarMemoria real)", async () => {
    const m = require(path.join(SRC, "hooks", "lib", "memoria-sessao.cjs"));
    return m.montarMemoria({ observacoes: [{ id: 1, projeto: "p", conteudo: "c", criada_em: "2026-09-01T10:00:00" }], avisos: [m.avisoDeManutencaoFalhou(5)] });
  }, "⚠️ Manutenção da memória falhou"],
  ["memoria acima do orcamento (montarMemoria real, teto minusculo)", async () => {
    const m = require(path.join(SRC, "hooks", "lib", "memoria-sessao.cjs"));
    const obs = Array.from({ length: 20 }, (_, i) => ({ id: i, projeto: "p" + i, conteudo: "Conteudo comprido ".repeat(10), criada_em: "2026-09-01T10:" + String(i).padStart(2, "0") + ":00" }));
    return m.montarMemoria({ observacoes: obs, tetoBytes: 600 });
  }, "⚠️ Memória acima do orçamento"],
  ["foco so com ponteiro (hook real, sem FOCO.md)", () => entradaFocoAtual(DADOS_SEM_FOCO), "RAINFOREST MIND ATIVO"],
  ["foco com FOCO.md (hook real)", () => entradaFocoAtual(DADOS), "RAINFOREST MIND ATIVO"],
];
for (const [nome, obter, prefixo] of CENARIOS) {
  caso(`filtro reconhece a entrada real: ${nome}`, async () => {
    const { criarAbertura, ehEntradaDaAbertura } = await modulo();
    const entrada = await obter();
    afirma(entrada.startsWith(prefixo), `a saida real comeca por ${JSON.stringify(entrada.slice(0, 50))}, nao por ${prefixo}`);
    afirma(ehEntradaDaAbertura(entrada), "ehEntradaDaAbertura nao reconheceu a saida real");
    const r = await criarAbertura().sessionStart(criar$(runReal), { source: "startup" },
      async () => ({ additionalContext: [entrada, ENTRADA_CODEX] }));
    igual(JSON.stringify(r.additionalContext), JSON.stringify([ENTRADA_CODEX]), "so a do codex deve ficar");
  });
}

caso("foco sem as regras (fallback FALHA AO CARREGAR AS REGRAS, hook real sem skills/) e reconhecido", async () => {
  // Copia do plugin SEM a pasta skills: o foco nao acha o SKILL.md e emite o fallback.
  const copia = caixa("rfm-mod-sem-skills-");
  fs.cpSync(path.join(SRC, "hooks"), path.join(copia, "hooks"), { recursive: true });
  fs.cpSync(path.join(SRC, "scripts"), path.join(copia, "scripts"), { recursive: true });
  const r = await executar(["node", path.join(copia, "hooks", "foco-session-start.cjs")], { cwd: PROJ, timeoutMs: 60000 }, DADOS);
  igual(r.exitCode, 0, `foco da copia saiu ${r.exitCode}: ${r.stderr.slice(0, 200)}`);
  const entrada = additional(r);
  const { ehEntradaDaAbertura } = await modulo();
  afirma(entrada.includes("FALHA AO CARREGAR AS REGRAS"), `fixture nao produziu o fallback; comeca por ${JSON.stringify(entrada.slice(0, 80))}`);
  afirma(ehEntradaDaAbertura(entrada), `fallback nao reconhecido: ${JSON.stringify(entrada.slice(0, 80))}`);
});

// Estouro do teto: o texto do aviso sai de `travarOrcamento` DE VERDADE (a mesma funcao
// que o hook do foco chama), nao e digitado aqui. Payload acima de 8.100 B comecando como
// o do foco; o aviso fica no topo e "RAINFOREST MIND ATIVO" so vem depois.
caso("foco acima do orcamento (travarOrcamento real, aviso no topo) e removido do SessionStart", async () => {
  const { travarOrcamento, TETOS } = require(path.join(SRC, "hooks", "lib", "contexto-sessao.cjs"));
  const bruto = "RAINFOREST MIND ATIVO\n" + "linha de regra de fixture\n".repeat(400);
  afirma(Buffer.byteLength(bruto, "utf8") > TETOS.ORCAMENTO_BYTES, "fixture nao estoura o teto");
  const entrada = travarOrcamento(bruto);
  afirma(entrada.startsWith("⚠️ **INJEÇÃO ACIMA DO ORÇAMENTO"), `travarOrcamento nao produziu o aviso no topo: ${JSON.stringify(entrada.slice(0, 60))}`);
  afirma(entrada.includes("RAINFOREST MIND ATIVO"), "a copia cortada deveria conter o foco");
  const { criarAbertura, ehEntradaDaAbertura } = await modulo();
  afirma(ehEntradaDaAbertura(entrada), "ehEntradaDaAbertura nao reconheceu a entrada em estouro");
  const abertura = criarAbertura();
  const $ = criar$(runReal);
  await abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  const r = await abertura.sessionStart($, { source: "startup" }, async () => ({ additionalContext: [entrada, ENTRADA_CODEX] }));
  igual(JSON.stringify(r.additionalContext), JSON.stringify([ENTRADA_CODEX]), "so a do codex deve ficar");
});

caso("texto que nao e da abertura nao e reconhecido", async () => {
  const { ehEntradaDaAbertura } = await modulo();
  for (const t of [ENTRADA_CODEX, "", "Memória sem cabecalho", "## Memória", undefined, null, 42]) {
    afirma(!ehEntradaDaAbertura(t), `reconheceu indevidamente ${JSON.stringify(t)}`);
  }
});

// ---- falha aberta
const FALHAS = [
  ["gerador do foco sai com exit != 0", (argv, init) => /foco-session/.test(geradorDoArgv(argv))
    ? { exitCode: 1, stdout: "", stderr: "recusado", isStdoutTruncated: false } : runReal(argv, init)],
  ["gerador da memoria sai com exit != 0", (argv, init) => /memoria-session/.test(geradorDoArgv(argv))
    ? { exitCode: 3, stdout: "", stderr: "recusado", isStdoutTruncated: false } : runReal(argv, init)],
  ["JSON invalido", (argv, init) => /foco-session/.test(geradorDoArgv(argv))
    ? { exitCode: 0, stdout: "{nao e json", stderr: "", isStdoutTruncated: false } : runReal(argv, init)],
  ["JSON sem hookSpecificOutput.additionalContext", (argv, init) => /memoria-session/.test(geradorDoArgv(argv))
    ? { exitCode: 0, stdout: JSON.stringify({ systemMessage: "x" }), stderr: "", isStdoutTruncated: false } : runReal(argv, init)],
  ["timeout (process.run rejeita)", (argv, init) => /memoria-session/.test(geradorDoArgv(argv))
    ? Promise.reject(new Error("timed out after 60000ms")) : runReal(argv, init)],
  ["saida truncada", (argv, init) => /foco-session/.test(geradorDoArgv(argv))
    ? { exitCode: 0, stdout: '{"hookSpecificOutput":{"additionalContext":"x', stderr: "", isStdoutTruncated: true } : runReal(argv, init)],
];
for (const [nome, run] of FALHAS) {
  caso(`falha aberta (${nome}): compose devolve next(e) intacto e SessionStart nao remove nada`, async () => {
    const { criarAbertura } = await modulo();
    const foco = await entradaFocoAtual(DADOS);
    const mem = await entradaMemoriaAtual();
    // Ordem 1: compose primeiro.
    {
      const abertura = criarAbertura();
      const original = { sections: SECOES_DO_ENGINE.slice() };
      const r = await abertura.promptCompose(criar$(run), { traits: [] }, async () => original);
      afirma(r === original, "compose nao devolveu o mesmo objeto de next(e)");
      igual(r.sections.length, SECOES_DO_ENGINE.length, "secao acrescentada apesar da falha");
      const entradaSS = { additionalContext: [foco, ENTRADA_CODEX, mem] };
      const rs = await abertura.sessionStart(criar$(run), { source: "startup" }, async () => entradaSS);
      afirma(rs === entradaSS, "SessionStart nao devolveu o mesmo objeto de next(e)");
      igual(rs.additionalContext.length, 3, "entradas removidas apesar da falha");
    }
    // Ordem 2: o SessionStart chega ANTES do primeiro compose.
    {
      const abertura = criarAbertura();
      const $ = criar$(run);
      const entradaSS = { additionalContext: [foco, ENTRADA_CODEX, mem] };
      const rs = await abertura.sessionStart($, { source: "startup" }, async () => entradaSS);
      afirma(rs === entradaSS, "SessionStart (antes do compose) nao devolveu o mesmo objeto");
      igual(rs.additionalContext.length, 3, "SessionStart antes do compose removeu entradas apesar da falha");
      const original = { sections: SECOES_DO_ENGINE.slice() };
      const r = await abertura.promptCompose($, { traits: [] }, async () => original);
      afirma(r === original, "compose depois do SessionStart falho nao devolveu next(e) intacto");
    }
  });
}

caso("SessionStart ANTES do primeiro compose: espera a montagem, remove, e o compose depois reaproveita", async () => {
  const { criarAbertura } = await modulo();
  const abertura = criarAbertura();
  const $ = criar$(runReal);
  const foco = await entradaFocoAtual(DADOS);
  const mem = await entradaMemoriaAtual();
  const rs = await abertura.sessionStart($, { source: "startup" }, async () => ({ additionalContext: [foco, ENTRADA_CODEX, mem] }));
  igual(JSON.stringify(rs.additionalContext), JSON.stringify([ENTRADA_CODEX]), "entradas que restam");
  igual($.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 2, "montou no SessionStart");
  const r = await abertura.promptCompose($, { traits: [] }, proximo(SECOES_DO_ENGINE));
  igual($.chamadas.filter((c) => geradorDoArgv(c.argv)).length, 2, "o compose reaproveitou a montagem");
  igual(r.sections[r.sections.length - 1].id, "rainforest-mind:abertura", "secao presente");
});

caso("classic.SessionStart sem additionalContext (nenhum hook emitiu) passa intacto", async () => {
  const { criarAbertura } = await modulo();
  const entrada = { sessionTitle: "so titulo" };
  const r = await criarAbertura().sessionStart(criar$(runReal), { source: "startup" }, async () => entrada);
  afirma(r === entrada, "devia devolver o mesmo objeto");
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
