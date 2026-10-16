#!/usr/bin/env node
"use strict";
/* Bateria da trava unica por fluxo e da mescla por campo do scripts/estado.cjs (#545,
 * tarefa 1 do plano docs/rainforest/planos/2026-10-15-estado-trava-unica.md).
 *
 * Uso: node scripts/testa-estado-trava.cjs
 *
 * Cada caso cria um RFM_ESTADO_ROOT temporario, roda o estado.cjs real (o deste
 * repositorio, por caminho relativo a este arquivo) com processos de verdade e apaga
 * a pasta no fim. Conferido pelo JSON gravado e pelo exit, nunca pelo texto do fonte.
 *
 * Pausa sem chute: quando RFM_ESTADO_PAUSA_GRAVAR_MS esta definida, o comando escreve
 * `pausa-gravar: <slug>` em stderr logo depois de LER o estado e so entao dorme. A
 * bateria espera essa linha antes de disparar os concorrentes: a leitura ja aconteceu,
 * nao ha corrida de 300 ms para perder num runner lento.
 *
 * Os casos concorrentes usam child_process.spawn (e nao spawnSync): spawnSync bloqueia
 * o event loop e nao deixaria observar um processo no meio da pausa.
 *
 * Saida: `ok    <caso>` / `FALHOU <caso>` e, por ultimo, `N ok, M falha(s), K skipped`.
 * Exit 1 se houver falha.
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn, spawnSync } = require("child_process");

const REPO = path.join(__dirname, "..");
const ESTADO = path.join(__dirname, "estado.cjs");
const SLUG = "2026-10-15-trava-teste";
const PAUSA_MS = "3000";
const MARCA_PAUSA = "pausa-gravar:";
const LOCK_FLUXO = `.${SLUG}.lock`;
const LOCKS_ANTIGOS = [`.${SLUG}.veredito.lock`, `.${SLUG}.flake.lock`, `.${SLUG}.decidir.lock`];

let ok = 0;
let falha = 0;
const skipped = 0;

function caso(nome, passou, detalhe) {
  if (passou) {
    ok++;
    console.log(`ok    ${nome}`);
  } else {
    falha++;
    console.log(`FALHOU ${nome}`);
    if (detalhe) console.log(`        ${detalhe}`);
  }
}

function ambiente(raiz, extra) {
  const env = { ...process.env, RFM_ESTADO_ROOT: raiz };
  delete env.RFM_ESTADO_PAUSA_GRAVAR_MS;
  return { ...env, ...(extra || {}) };
}

function rodar(raiz, argv, extra) {
  return spawnSync(process.execPath, [ESTADO, ...argv], {
    cwd: raiz,
    env: ambiente(raiz, extra),
    encoding: "utf8",
    timeout: 60000,
    windowsHide: true,
  });
}

// Processo assincrono com dois sinais: `marcou` resolve true quando o processo escreve
// a linha de pausa (ja leu o estado) e false se terminar sem pausar; `fim` resolve com
// o exit e a saida. Quem chama espera `marcou` antes de disparar os concorrentes.
function rodarPausado(raiz, argv, extra) {
  let marcar;
  const marcou = new Promise((r) => (marcar = r));
  const fim = new Promise((resolve) => {
    const filho = spawn(process.execPath, [ESTADO, ...argv], {
      cwd: raiz,
      env: ambiente(raiz, extra),
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    filho.stdout.on("data", (d) => (stdout += d));
    filho.stderr.on("data", (d) => {
      stderr += d;
      if (stderr.includes(MARCA_PAUSA)) marcar(true);
    });
    filho.on("close", (status) => {
      marcar(false);
      resolve({ status, stdout, stderr });
    });
  });
  return { marcou, fim };
}

function rodarAsync(raiz, argv, extra) {
  return rodarPausado(raiz, argv, extra).fim;
}

function pastaEstado(raiz) {
  return path.join(raiz, "docs", "rainforest", "estado");
}

function lerFluxo(raiz) {
  return JSON.parse(fs.readFileSync(path.join(pastaEstado(raiz), `${SLUG}.json`), "utf8"));
}

function textoFluxo(raiz) {
  return fs.readFileSync(path.join(pastaEstado(raiz), `${SLUG}.json`), "utf8");
}

function locks(raiz) {
  try {
    return fs.readdirSync(pastaEstado(raiz)).filter((n) => n.endsWith(".lock"));
  } catch (e) {
    return [];
  }
}

function pendentesDoDesign(e) {
  return (e.design && Array.isArray(e.design.pendentes) ? e.design.pendentes : []);
}

function caixa() {
  const raiz = fs.mkdtempSync(path.join(os.tmpdir(), "estado-trava-"));
  const iniciado = rodar(raiz, ["iniciar", "--slug", SLUG]);
  if (iniciado.status !== 0) throw new Error(`iniciar falhou: ${iniciado.stderr}`);
  return raiz;
}

function apagar(raiz) {
  try {
    fs.rmSync(raiz, { recursive: true, force: true });
  } catch (e) {
    /* pasta travada pelo SO: o tmp do sistema limpa depois */
  }
}

const recusouPorTrava = (r) => r.status !== 0 && /outra sessao esta escrevendo/.test(r.stderr);

async function casoA() {
  const nome = "(a) marcar pausado nao apaga decidir nem pendencia gravados durante a pausa";
  const raiz = caixa();
  try {
    const marcar = rodarPausado(
      raiz,
      ["marcar", "--slug", SLUG, "--estagio", "arqueologia", "--status", "dispensada"],
      { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS }
    );
    if (!(await marcar.marcou)) {
      caso(nome, false, "o marcar nao pausou: a costura nao foi alcancada");
      await marcar.fim;
      return;
    }
    let terminou = false;
    marcar.fim.then(() => (terminou = true));
    const decidir = await rodarAsync(raiz, [
      "decidir", "--slug", SLUG, "--pergunta", "usar trava unica", "--escolha", "sim", "--porque", "um lock so",
    ]);
    const pendencia = await rodarAsync(raiz, ["pendencia", "--slug", SLUG, "--texto", "rodar bateria X"]);
    if (terminou) {
      caso(nome, false, "o marcar terminou antes dos outros dois gravarem: a pausa nao cobriu a corrida");
      return;
    }
    const m = await marcar.fim;
    if (decidir.status !== 0 || pendencia.status !== 0 || m.status !== 0) {
      caso(nome, false, `exit decidir=${decidir.status} pendencia=${pendencia.status} marcar=${m.status}`);
      return;
    }
    const e = lerFluxo(raiz);
    const decididos = Array.isArray(e.decididos) ? e.decididos : [];
    const pendentes = pendentesDoDesign(e);
    caso(
      nome,
      e.arqueologia.status === "dispensada" &&
        decididos.length === 1 &&
        decididos[0].pergunta === "usar trava unica" &&
        pendentes.includes("rodar bateria X"),
      `arqueologia.status=${e.arqueologia.status} decididos=${decididos.length} design.pendentes=${JSON.stringify(pendentes)}`
    );
  } finally {
    apagar(raiz);
  }
}

async function casoB() {
  const nome = "(b) dois decidir concorrentes sem pausa deixam os dois itens em decididos";
  const raiz = caixa();
  try {
    const [a, b] = await Promise.all([
      rodarAsync(raiz, ["decidir", "--slug", SLUG, "--pergunta", "pergunta A", "--escolha", "a", "--porque", "porque A"]),
      rodarAsync(raiz, ["decidir", "--slug", SLUG, "--pergunta", "pergunta B", "--escolha", "b", "--porque", "porque B"]),
    ]);
    if (a.status !== 0 || b.status !== 0) {
      caso(nome, false, `exit A=${a.status} B=${b.status}\n${a.stderr}${b.stderr}`);
      return;
    }
    const perguntas = (lerFluxo(raiz).decididos || []).map((d) => d.pergunta).sort();
    caso(nome, JSON.stringify(perguntas) === JSON.stringify(["pergunta A", "pergunta B"]), `decididos=${JSON.stringify(perguntas)}`);
  } finally {
    apagar(raiz);
  }
}

async function casoC() {
  const nome = "(c) campo removido pelo comando continua removido; campo so do outro processo continua la";
  const raiz = caixa();
  try {
    const pre = rodar(raiz, [
      "marcar", "--slug", SLUG, "--estagio", "arqueologia", "--status", "pendente",
      "--json", JSON.stringify({ em_voo: [{ tarefa: "3 painel" }] }),
    ]);
    if (pre.status !== 0 || !("em_voo" in lerFluxo(raiz).arqueologia)) {
      caso(nome, false, `pre-condicao: em_voo nao gravado (exit ${pre.status}): ${pre.stderr}`);
      return;
    }
    const fechar = rodarPausado(
      raiz,
      ["marcar", "--slug", SLUG, "--estagio", "arqueologia", "--status", "dispensada"],
      { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS }
    );
    if (!(await fechar.marcou)) {
      caso(nome, false, "o marcar nao pausou");
      await fechar.fim;
      return;
    }
    const decidir = await rodarAsync(raiz, [
      "decidir", "--slug", SLUG, "--pergunta", "campo do outro", "--escolha", "x", "--porque", "so do outro processo",
    ]);
    const m = await fechar.fim;
    if (decidir.status !== 0 || m.status !== 0) {
      caso(nome, false, `exit decidir=${decidir.status} marcar=${m.status}\n${decidir.stderr}${m.stderr}`);
      return;
    }
    const e = lerFluxo(raiz);
    const decididos = Array.isArray(e.decididos) ? e.decididos : [];
    caso(
      nome,
      !("em_voo" in e.arqueologia) && decididos.some((d) => d.pergunta === "campo do outro"),
      `arqueologia=${JSON.stringify(e.arqueologia)} decididos=${decididos.length}`
    );
  } finally {
    apagar(raiz);
  }
}

function casoD() {
  const nome = "(d) sequencia de comandos nao deixa .veredito/.flake/.decidir.lock nem .<slug>.lock no disco";
  const raiz = caixa();
  try {
    const comandos = [
      ["decidir", "--slug", SLUG, "--pergunta", "p1", "--escolha", "e1", "--porque", "x1"],
      ["registrar-flake", "--slug", SLUG, "--tarefa", "1", "--gate", "gate-x"],
      ["pendencia", "--slug", SLUG, "--texto", "pend"],
      ["liberar-teto", "--slug", SLUG, "--motivo", "teto"],
      ["marcar", "--slug", SLUG, "--estagio", "arqueologia", "--status", "dispensada"],
    ];
    const sobras = [];
    let algumErro = null;
    for (const argv of comandos) {
      const r = rodar(raiz, argv);
      if (r.status !== 0 && !algumErro) algumErro = `${argv[0]} exit ${r.status}: ${r.stderr}`;
      sobras.push(...locks(raiz));
    }
    caso(nome, algumErro === null && sobras.length === 0, algumErro || `locks restantes: ${JSON.stringify(sobras)}`);
  } finally {
    apagar(raiz);
  }
}

function casoE() {
  const nome = "(e) .<slug>.lock com PID morto nao impede o decidir de gravar";
  const raiz = caixa();
  try {
    // PID garantidamente morto: o do `node -e ""` que acabou de terminar.
    const morto = spawnSync(process.execPath, ["-e", ""], { windowsHide: true });
    const pidMorto = morto.pid;
    let aindaVivo = true;
    try {
      process.kill(pidMorto, 0);
    } catch (e) {
      aindaVivo = e.code !== "ESRCH";
    }
    if (aindaVivo) {
      caso(nome, false, `o pid ${pidMorto} ainda existe: nao da para provar o dono morto`);
      return;
    }
    fs.writeFileSync(path.join(pastaEstado(raiz), LOCK_FLUXO), `${pidMorto} ${new Date().toISOString()}\n`);
    const r = rodar(raiz, ["decidir", "--slug", SLUG, "--pergunta", "depois do dono morto", "--escolha", "sim", "--porque", "pid morto"]);
    const decididos = (lerFluxo(raiz).decididos || []).map((d) => d.pergunta);
    caso(
      nome,
      r.status === 0 && decididos.includes("depois do dono morto") && locks(raiz).length === 0,
      `pid=${pidMorto} exit=${r.status} decididos=${JSON.stringify(decididos)} locks=${JSON.stringify(locks(raiz))} stderr=${r.stderr.trim()}`
    );
  } finally {
    apagar(raiz);
  }
}

async function casoF() {
  const nome = "(f) dois pendencia concorrentes (o primeiro pausado) deixam as duas pendencias";
  const raiz = caixa();
  try {
    const a = rodarPausado(raiz, ["pendencia", "--slug", SLUG, "--texto", "X do A"], { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS });
    if (!(await a.marcou)) {
      caso(nome, false, "o primeiro pendencia nao pausou");
      await a.fim;
      return;
    }
    const b = rodarAsync(raiz, ["pendencia", "--slug", SLUG, "--texto", "X do B"]);
    const [ra, rb] = [await a.fim, await b];
    const pendentes = pendentesDoDesign(lerFluxo(raiz));
    caso(
      nome,
      ra.status === 0 && rb.status === 0 && pendentes.includes("X do A") && pendentes.includes("X do B"),
      `exit A=${ra.status} B=${rb.status} design.pendentes=${JSON.stringify(pendentes)} ${ra.stderr}${rb.stderr}`
    );
  } finally {
    apagar(raiz);
  }
}

async function casoF2() {
  const nome = "(f) dois liberar-teto concorrentes (o primeiro pausado) deixam os dois motivos";
  const raiz = caixa();
  try {
    const a = rodarPausado(raiz, ["liberar-teto", "--slug", SLUG, "--motivo", "motivo A"], { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS });
    if (!(await a.marcou)) {
      caso(nome, false, "o primeiro liberar-teto nao pausou");
      await a.fim;
      return;
    }
    const b = rodarAsync(raiz, ["liberar-teto", "--slug", SLUG, "--motivo", "motivo B"]);
    const [ra, rb] = [await a.fim, await b];
    const motivos = ((lerFluxo(raiz).teto_despachos || {}).liberacoes || []).map((l) => l.motivo).sort();
    caso(
      nome,
      ra.status === 0 && rb.status === 0 && JSON.stringify(motivos) === JSON.stringify(["motivo A", "motivo B"]),
      `exit A=${ra.status} B=${rb.status} motivos=${JSON.stringify(motivos)}`
    );
  } finally {
    apagar(raiz);
  }
}

async function casoG() {
  const nome = "(g) .<slug>.lock de PID vivo: marcar e pendencia esperam e recusam sem gravar";
  const raiz = caixa();
  try {
    const lockPath = path.join(pastaEstado(raiz), LOCK_FLUXO);
    // A bateria segura a trava com o PID dela mesma: vivo de verdade, sem sair enquanto
    // os dois comandos esperam os 10 s da trava.
    fs.writeFileSync(lockPath, `${process.pid} ${new Date().toISOString()}\n`);
    const antes = textoFluxo(raiz);
    const [m, p] = await Promise.all([
      rodarAsync(raiz, ["marcar", "--slug", SLUG, "--estagio", "arqueologia", "--status", "dispensada"]),
      rodarAsync(raiz, ["pendencia", "--slug", SLUG, "--texto", "nao deve entrar"]),
    ]);
    const travaIntacta = fs.existsSync(lockPath);
    const depois = textoFluxo(raiz);
    if (fs.existsSync(lockPath)) fs.unlinkSync(lockPath);
    caso(
      nome,
      recusouPorTrava(m) && recusouPorTrava(p) && depois === antes && travaIntacta,
      `marcar exit=${m.status} stderr=${m.stderr.trim()} | pendencia exit=${p.status} stderr=${p.stderr.trim()} | gravou=${depois !== antes} trava=${travaIntacta}`
    );
  } finally {
    apagar(raiz);
  }
}

async function casoH() {
  const nome = "(h) marcar pausado e pendencia no MESMO estagio terminam com o status e a pendencia no mesmo bloco";
  const raiz = caixa();
  try {
    const marcar = rodarPausado(
      raiz,
      ["marcar", "--slug", SLUG, "--estagio", "design", "--status", "aprovado"],
      { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS }
    );
    if (!(await marcar.marcou)) {
      caso(nome, false, "o marcar nao pausou");
      await marcar.fim;
      return;
    }
    const pendencia = await rodarAsync(raiz, ["pendencia", "--slug", SLUG, "--texto", "pendura no design"]);
    const m = await marcar.fim;
    const bloco = lerFluxo(raiz).design || {};
    caso(
      nome,
      m.status === 0 && pendencia.status === 0 && bloco.status === "aprovado" &&
        JSON.stringify(bloco.pendentes) === JSON.stringify(["pendura no design"]),
      `marcar=${m.status} pendencia=${pendencia.status} design=${JSON.stringify(bloco)} ${m.stderr}${pendencia.stderr}`
    );
  } finally {
    apagar(raiz);
  }
}

async function casoI() {
  const nome = "(i) com decidir pausado segurando a trava, a pasta tem .<slug>.lock e nunca .veredito/.flake/.decidir.lock";
  const raiz = caixa();
  try {
    const decidir = rodarPausado(
      raiz,
      ["decidir", "--slug", SLUG, "--pergunta", "p-i", "--escolha", "e", "--porque", "x"],
      { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS }
    );
    if (!(await decidir.marcou)) {
      caso(nome, false, "o decidir nao pausou");
      await decidir.fim;
      return;
    }
    const aoPausar = locks(raiz);
    const vistos = new Set();
    const amostra = setInterval(() => {
      for (const n of locks(raiz)) vistos.add(n);
    }, 20);
    const registrar = rodarAsync(
      raiz,
      ["registrar-flake", "--slug", SLUG, "--tarefa", "1", "--gate", "g"],
      { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS }
    );
    const marcar = rodarAsync(
      raiz,
      ["marcar", "--slug", SLUG, "--estagio", "arqueologia", "--status", "dispensada"],
      { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS }
    );
    const [d, r, m] = [await decidir.fim, await registrar, await marcar];
    clearInterval(amostra);
    const legados = LOCKS_ANTIGOS.filter((n) => vistos.has(n));
    caso(
      nome,
      aoPausar.includes(LOCK_FLUXO) && legados.length === 0 && d.status === 0 && r.status === 0 && m.status === 0,
      `ao pausar=${JSON.stringify(aoPausar)} vistos=${JSON.stringify([...vistos])} legados=${JSON.stringify(legados)} exit decidir=${d.status} registrar=${r.status} marcar=${m.status}`
    );
  } finally {
    apagar(raiz);
  }
}

function casoJ() {
  const nome = "(j) D6: git check-ignore lista .x.lock e x.json.tmp em docs/rainforest/estado";
  const alvo = ["docs/rainforest/estado/.x.lock", "docs/rainforest/estado/x.json.tmp"];
  const r = spawnSync("git", ["check-ignore", ...alvo], { cwd: REPO, encoding: "utf8", windowsHide: true, timeout: 30000 });
  const listados = (r.stdout || "").split("\n").map((s) => s.trim()).filter(Boolean).sort();
  caso(
    nome,
    r.status === 0 && JSON.stringify(listados) === JSON.stringify([...alvo].sort()),
    `exit=${r.status} stdout=${JSON.stringify(r.stdout)} stderr=${(r.stderr || "").trim()}`
  );
}

async function casoK() {
  const nome = "(k) process.exit dentro da trava (destinar recusado) solta .<slug>.lock; a chamada seguinte nao avisa trava orfa";
  const raiz = caixa();
  try {
    const recusa = rodar(raiz, ["destinar", "--slug", SLUG, "--estagio", "design", "--json", '{"destinos":[]}']);
    const soltou = locks(raiz).length === 0;
    const seguinte = rodar(raiz, ["pendencia", "--slug", SLUG, "--texto", "depois da recusa"]);
    const pendentes = pendentesDoDesign(lerFluxo(raiz));
    caso(
      nome,
      recusa.status === 2 && soltou && seguinte.status === 0 && !/trava orfa/.test(seguinte.stderr) &&
        pendentes.includes("depois da recusa"),
      `destinar exit=${recusa.status} soltou=${soltou} pendencia exit=${seguinte.status} stderr=${seguinte.stderr.trim()} pendentes=${JSON.stringify(pendentes)}`
    );
  } finally {
    apagar(raiz);
  }
}

async function casoL() {
  const nome = "(l) marcar que fecha o estagio recusa (exit 2) se outro processo gravou pendencia durante a validacao, e nada some";
  const raiz = caixa();
  try {
    const desc = (p) => JSON.stringify({ destinos: [{ pendente: p, destino: "descartada", motivo: "teste" }] });
    const pre1 = rodar(raiz, ["pendencia", "--slug", SLUG, "--texto", "A"]);
    const pre2 = rodar(raiz, ["destinar", "--slug", SLUG, "--estagio", "design", "--json", desc("A")]);
    if (pre1.status !== 0 || pre2.status !== 0) {
      caso(nome, false, `pre-condicao: pendencia=${pre1.status} destinar=${pre2.status} ${pre1.stderr}${pre2.stderr}`);
      return;
    }
    const marcar = rodarPausado(
      raiz,
      ["marcar", "--slug", SLUG, "--estagio", "design", "--status", "aprovado"],
      { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS }
    );
    if (!(await marcar.marcou)) {
      caso(nome, false, "o marcar nao pausou");
      await marcar.fim;
      return;
    }
    const b = await rodarAsync(raiz, ["pendencia", "--slug", SLUG, "--texto", "B"]);
    const m = await marcar.fim;
    const bloco = lerFluxo(raiz).design || {};
    caso(
      nome,
      b.status === 0 && m.status === 2 && /RECUSADO: outro processo gravou/.test(m.stderr) &&
        bloco.status !== "aprovado" && JSON.stringify(bloco.pendentes) === JSON.stringify(["B"]),
      `marcar=${m.status} pendencia=${b.status} design=${JSON.stringify(bloco)} ${m.stderr}`
    );
  } finally {
    apagar(raiz);
  }
}

async function casoM() {
  const nome = "(m) dois destinar concorrentes (o primeiro pausado) deixam os dois destinos";
  const raiz = caixa();
  try {
    const desc = (p) => JSON.stringify({ destinos: [{ pendente: p, destino: "descartada", motivo: "teste" }] });
    for (const p of ["P1", "P2"]) rodar(raiz, ["pendencia", "--slug", SLUG, "--texto", p]);
    const a = rodarPausado(raiz, ["destinar", "--slug", SLUG, "--estagio", "design", "--json", desc("P1")], { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS });
    if (!(await a.marcou)) {
      caso(nome, false, "o primeiro destinar nao pausou");
      await a.fim;
      return;
    }
    const b = rodarAsync(raiz, ["destinar", "--slug", SLUG, "--estagio", "design", "--json", desc("P2")]);
    const [ra, rb] = [await a.fim, await b];
    const bloco = lerFluxo(raiz).design || {};
    const destinados = (bloco.destinos || []).map((d) => d.pendente).sort();
    caso(
      nome,
      ra.status === 0 && rb.status === 0 && JSON.stringify(destinados) === JSON.stringify(["P1", "P2"]) &&
        (bloco.pendentes || []).length === 0,
      `exit A=${ra.status} B=${rb.status} design=${JSON.stringify(bloco)} ${ra.stderr}${rb.stderr}`
    );
  } finally {
    apagar(raiz);
  }
}

(async () => {
  await casoA();
  await casoB();
  await casoC();
  casoD();
  casoE();
  await casoF();
  await casoF2();
  await casoG();
  await casoH();
  await casoI();
  casoJ();
  await casoK();
  await casoL();
  await casoM();
  console.log(`${ok} ok, ${falha} falha(s), ${skipped} skipped`);
  process.exit(falha ? 1 : 0);
})();
