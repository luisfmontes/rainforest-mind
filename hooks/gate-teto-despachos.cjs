#!/usr/bin/env node
// @categoria: guia
"use strict";
/* Teto de despachos por fluxo (Tarefa 2 do plano flaky-teto, D5, D9-D12, D15-D17).
 * Protege contra: fluxo gastar despacho de agente sem fim (conta todo despacho do fluxo ativo)
 * Não protege contra: agente despachado fora de fluxo (fora de fluxo passa sem contar; é da portaria)
 *
 * PreToolUse de `Task|Agent`, separado da portaria: a portaria só registra desde a #264
 * e não volta a barrar. Este hook decide só sobre contagem; não lê o prompt do despacho.
 *
 * Exit 0: admitido (e contado) ou fora de fluxo.
 * Exit 2: negado, motivo no stderr. Nunca exit 1: exit 1 num PreToolUse não barra.
 *
 * O contador mora fora do repo, em `<dados>/fluxos/<slug>/despachos.json` (D11),
 * lido e gravado dentro de `comTrava`. Contador ilegível NEGA (D12): ilegível lido
 * como zero zeraria o teto em silêncio. Despacho que a portaria nega também conta (D17).
 *
 * Sem toggle e sem variável de escape (D15): a única porta acima do teto é o
 * `liberar-teto` (tarefa 4). A leitura do teto declarado no plano é da tarefa 7.
 */

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { caminhoExecutavel } = require(path.join(__dirname, "lib", "resolver-executavel.cjs"));
const { comTrava } = require(path.join(__dirname, "lib", "trava-jsonl.cjs"));

const TETO_PADRAO = 40;
const ESPERA_TRAVA_SEG = 10;

function dizer(texto) {
  try {
    fs.writeSync(2, texto);
  } catch {
    /* stderr fechado: o exit code ainda decide */
  }
}

function negar(texto) {
  dizer(`teto de despachos: ${texto}\n`);
  process.exit(2);
}

function raizDoProjeto(payload) {
  const caminho = (payload && payload.cwd) || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  try {
    return execFileSync(caminhoExecutavel("git"), ["-C", caminho, "rev-parse", "--show-toplevel"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return caminho;
  }
}

function raizDeDados(raiz) {
  try {
    const { resolverRaiz } = require(path.join(__dirname, "lib", "raiz.cjs"));
    const r = resolverRaiz({ cwd: raiz });
    if (r && r.raiz) return r.raiz;
  } catch {
    /* resolvedor quebrado: cai no padrão do projeto */
  }
  return path.join(raiz, ".rainforest");
}

function lerPayload() {
  let bruto;
  try {
    bruto = fs.readFileSync(0, "utf8");
  } catch {
    process.exit(0); // stdin ilegível: libera, como a portaria
  }
  if (!bruto.trim()) process.exit(0);
  try {
    return JSON.parse(bruto);
  } catch {
    process.exit(0);
  }
}

function main() {
  const payload = lerPayload();
  if (!payload || typeof payload !== "object") process.exit(0);
  if (payload.tool_name !== "Agent" && payload.tool_name !== "Task") process.exit(0);

  const raiz = raizDoProjeto(payload);

  // Resolver que estoura ANTES de achar o fluxo passa com aviso (a portaria já nega
  // esse caso); depois de achar o fluxo, qualquer falha nega.
  let fluxo;
  try {
    fluxo = require(path.join(__dirname, "lib", "estagio-ativo.cjs")).resolver({ cwd: raiz });
  } catch (err) {
    dizer(`teto de despachos: aviso, nao consegui resolver o fluxo (${err && err.message ? err.message : err}); despacho passou sem contar\n`);
    process.exit(0);
  }
  if (!fluxo || !fluxo.slug) process.exit(0);

  const slug = fluxo.slug;
  const daJanela = !Object.prototype.hasOwnProperty.call(payload, "agent_id");
  const teto = TETO_PADRAO;
  const dir = path.join(raizDeDados(raiz), "fluxos", slug);
  const arquivo = path.join(dir, "despachos.json");
  fs.mkdirSync(dir, { recursive: true });

  // A decisão sai da trava como texto: `process.exit` dentro dela deixaria o lock no chão.
  const motivo = comTrava(path.join(dir, ".despachos.lock"), () => {
    let obj = { total: 0 }; // arquivo ausente = primeiro despacho do fluxo; arquivo presente e ruim NAO e zero
    if (fs.existsSync(arquivo)) {
      const bruto = fs.readFileSync(arquivo, "utf8");
      try {
        obj = JSON.parse(bruto);
      } catch {
        obj = null;
      }
      if (obj === null || typeof obj !== "object" || Array.isArray(obj)) obj = {};
    }
    const total = Number.isSafeInteger(obj.total) && obj.total >= 0 ? obj.total : null;

    if (total === null) {
      return (
        `o contador de despachos do fluxo ${slug} esta ilegivel (${arquivo}) e o despacho foi NEGADO. ` +
          `Contador ilegivel nao e lido como zero: isso zeraria o teto em silencio. Nada foi reescrito.`
      );
    }
    if (total >= teto) {
      const saida = daJanela
        ? ` Para liberar mais 10 despachos, com a palavra do usuario: node scripts/estado.cjs liberar-teto --slug ${slug} --motivo "<motivo>"`
        : " A decisao de liberar mais despachos e do usuario, na janela principal; pare e reporte.";
      return `o fluxo ${slug} ja admitiu ${total} despachos, o teto e ${teto}, e este despacho foi NEGADO.${saida}`;
    }

    const tmp = `${arquivo}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, `${JSON.stringify({ total: total + 1 })}\n`, "utf8");
    fs.renameSync(tmp, arquivo);
    return null;
  }, ESPERA_TRAVA_SEG);
  if (motivo) negar(motivo);
}

if (require.main === module) {
  // Falha interna NEGA com exit 2 (exit 1 não barra). Rede síncrona e de promessas.
  const negarPorFalhaInterna = (origem, err) => {
    dizer(
      `teto de despachos: falha interna (${origem}), e por isso o despacho foi NEGADO — ${
        err && err.message ? err.message : String(err)
      }\n`
    );
    process.exit(2);
  };
  process.on("uncaughtException", (err) => negarPorFalhaInterna("excecao nao capturada", err));
  process.on("unhandledRejection", (err) => negarPorFalhaInterna("promise rejeitada", err));
  try {
    main();
  } catch (err) {
    negarPorFalhaInterna("main", err);
  }
}
