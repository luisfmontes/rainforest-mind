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
 * Os casos concorrentes usam child_process.spawn (e nao spawnSync): spawnSync bloqueia
 * o event loop e nao deixaria provar que o `marcar` pausado ainda estava no meio da
 * pausa quando os outros processos gravaram.
 *
 * Saida: `ok    <caso>` / `FALHOU <caso>` e, por ultimo, `N ok, M falha(s), K skipped`.
 * Exit 1 se houver falha.
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn, spawnSync } = require("child_process");

const ESTADO = path.join(__dirname, "estado.cjs");
const SLUG = "2026-10-15-trava-teste";

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

function rodarAsync(raiz, argv, extra) {
  return new Promise((resolve) => {
    const filho = spawn(process.execPath, [ESTADO, ...argv], {
      cwd: raiz,
      env: ambiente(raiz, extra),
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    filho.stdout.on("data", (d) => (stdout += d));
    filho.stderr.on("data", (d) => (stderr += d));
    filho.on("close", (status) => resolve({ status, stdout, stderr }));
  });
}

function pastaEstado(raiz) {
  return path.join(raiz, "docs", "rainforest", "estado");
}

function lerFluxo(raiz) {
  return JSON.parse(fs.readFileSync(path.join(pastaEstado(raiz), `${SLUG}.json`), "utf8"));
}

function locks(raiz) {
  return fs.readdirSync(pastaEstado(raiz)).filter((n) => n.endsWith(".lock"));
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

const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const PAUSA_MS = "1500";

async function casoA() {
  const nome = "(a) marcar pausado nao apaga decidir nem pendencia gravados durante a pausa";
  const raiz = caixa();
  try {
    let terminou = false;
    const marcar = rodarAsync(
      raiz,
      ["marcar", "--slug", SLUG, "--estagio", "arqueologia", "--status", "dispensada"],
      { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS }
    ).then((r) => {
      terminou = true;
      return r;
    });
    await pausa(300);
    const decidir = await rodarAsync(raiz, [
      "decidir", "--slug", SLUG, "--pergunta", "usar trava unica", "--escolha", "sim", "--porque", "um lock so",
    ]);
    const pendencia = await rodarAsync(raiz, ["pendencia", "--slug", SLUG, "--texto", "rodar bateria X"]);
    if (terminou) {
      caso(nome, false, "o marcar terminou antes dos outros dois gravarem: a pausa nao cobriu a corrida");
      return;
    }
    const m = await marcar;
    if (decidir.status !== 0 || pendencia.status !== 0 || m.status !== 0) {
      caso(nome, false, `exit decidir=${decidir.status} pendencia=${pendencia.status} marcar=${m.status}`);
      return;
    }
    const e = lerFluxo(raiz);
    const decididos = Array.isArray(e.decididos) ? e.decididos : [];
    const pendentes = (e.design && e.design.pendentes) || [];
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
    const fechar = rodarAsync(
      raiz,
      ["marcar", "--slug", SLUG, "--estagio", "arqueologia", "--status", "dispensada"],
      { RFM_ESTADO_PAUSA_GRAVAR_MS: PAUSA_MS }
    );
    await pausa(300);
    const decidir = await rodarAsync(raiz, [
      "decidir", "--slug", SLUG, "--pergunta", "campo do outro", "--escolha", "x", "--porque", "so do outro processo",
    ]);
    const m = await fechar;
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
  const nome = "(d) nenhum .veredito/.flake/.decidir.lock; .<slug>.lock some ao fim; trava do fluxo segura";
  const raiz = caixa();
  try {
    const comandos = [
      ["decidir", "--slug", SLUG, "--pergunta", "p1", "--escolha", "e1", "--porque", "x1"],
      ["registrar-flake", "--slug", SLUG, "--tarefa", "1", "--gate", "gate-x"],
      ["pendencia", "--slug", SLUG, "--texto", "pend"],
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

    // Trava do fluxo e a mesma que ele segura: lock vivo (PID deste processo) bloqueia o decidir.
    fs.writeFileSync(path.join(pastaEstado(raiz), `.${SLUG}.lock`), `${process.pid} ${new Date().toISOString()}\n`);
    const travado = rodar(raiz, ["decidir", "--slug", SLUG, "--pergunta", "p2", "--escolha", "e2", "--porque", "x2"]);
    const nomeTravado = `(d) decidir respeita .${SLUG}.lock (pid vivo): recusa com trava ocupada`;
    caso(
      nomeTravado,
      travado.status !== 0 && /outra sessao esta escrevendo/.test(travado.stderr) && (lerFluxo(raiz).decididos || []).length === 1,
      `exit=${travado.status} stderr=${travado.stderr.trim()}`
    );
    fs.unlinkSync(path.join(pastaEstado(raiz), `.${SLUG}.lock`));
  } finally {
    apagar(raiz);
  }
}

function casoE() {
  const nome = "(e) .<slug>.lock com PID morto nao impede o decidir de gravar";
  const raiz = caixa();
  try {
    fs.writeFileSync(path.join(pastaEstado(raiz), `.${SLUG}.lock`), `999999 ${new Date().toISOString()}\n`);
    const r = rodar(raiz, ["decidir", "--slug", SLUG, "--pergunta", "depois do dono morto", "--escolha", "sim", "--porque", "pid morto"]);
    const decididos = (lerFluxo(raiz).decididos || []).map((d) => d.pergunta);
    caso(
      nome,
      r.status === 0 && decididos.includes("depois do dono morto") && locks(raiz).length === 0,
      `exit=${r.status} decididos=${JSON.stringify(decididos)} locks=${JSON.stringify(locks(raiz))} stderr=${r.stderr.trim()}`
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
  console.log(`${ok} ok, ${falha} falha(s), ${skipped} skipped`);
  process.exit(falha ? 1 : 0);
})();
