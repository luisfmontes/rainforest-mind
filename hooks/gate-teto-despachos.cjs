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
 * `liberar-teto` (tarefa 4). Teto efetivo (tarefa 7): o declarado no cabeçalho do plano
 * (`teto-despachos: N`, D9; 40 sem a linha) mais 10 por liberação gravada no estado (D13).
 * Cabeçalho ou liberação ilegível NEGA (D12).
 */

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { caminhoExecutavel } = require(path.join(__dirname, "lib", "resolver-executavel.cjs"));
const { comTrava } = require(path.join(__dirname, "lib", "trava-jsonl.cjs"));
const { lerTetoDeclarado } = require(path.join(__dirname, "lib", "teto-despachos.cjs"));
const { caminhoDoc } = require(path.join(__dirname, "lib", "pastas-docs.cjs"));

const TETO_PADRAO = 40;
const DESPACHOS_POR_LIBERACAO = 10;
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

// Teto do fluxo: { teto } ou { erro }. Falha de leitura nunca vira o teto padrão (D12).
function tetoDoFluxo(raiz, slug) {
  const relPlano = caminhoDoc("planos", slug, { raiz });
  const plano = path.join(raiz, relPlano);
  let declarado = TETO_PADRAO;
  let st = null;
  try {
    st = fs.statSync(plano);
  } catch (err) {
    if (!err || err.code !== "ENOENT") return { erro: `o plano ${plano} nao pode ser examinado (${err && err.code})` };
  }
  if (st) {
    let texto;
    try {
      if (!st.isFile()) throw new Error("nao e um arquivo");
      texto = fs.readFileSync(plano, "utf8");
    } catch (err) {
      return { erro: `o plano ${plano} existe mas nao e um arquivo legivel (${err && err.message})` };
    }
    const lido = lerTetoDeclarado(texto, TETO_PADRAO);
    if (lido.erro) return { erro: `plano ${plano}: ${lido.erro}` };
    declarado = lido.teto;
  }

  const arquivoEstado = path.join(raiz, "docs", "rainforest", "estado", `${slug}.json`);
  let liberacoes = [];
  try {
    const estado = JSON.parse(fs.readFileSync(arquivoEstado, "utf8"));
    const bloco = estado && typeof estado === "object" ? estado.teto_despachos : undefined;
    if (bloco !== undefined && bloco !== null) {
      if (typeof bloco !== "object" || Array.isArray(bloco)) throw new Error("teto_despachos nao e objeto");
      if (bloco.liberacoes !== undefined) {
        if (!Array.isArray(bloco.liberacoes)) throw new Error("liberacoes nao e lista");
        const ruim = bloco.liberacoes.findIndex(
          (l) => !l || typeof l !== "object" || typeof l.motivo !== "string" || !l.motivo.trim()
        );
        if (ruim !== -1) throw new Error(`liberacao ${ruim} sem motivo`);
        liberacoes = bloco.liberacoes;
      }
    }
  } catch (err) {
    return { erro: `as liberacoes do teto em ${arquivoEstado} estao ilegiveis (${err && err.message}); nada foi liberado` };
  }

  const teto = declarado + DESPACHOS_POR_LIBERACAO * liberacoes.length;
  return { teto, declarado, liberacoes: liberacoes.length };
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
  const decidido = tetoDoFluxo(raiz, slug);
  if (decidido.erro) {
    negar(`o teto do fluxo ${slug} esta ilegivel e o despacho foi NEGADO. ${decidido.erro}. Nada foi contado.`);
  }
  const teto = decidido.teto;
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
        ? ` Para destravar, com a palavra do usuario: declarar \`teto-despachos: N\` no cabecalho do plano, ou node scripts/estado.cjs liberar-teto --slug ${slug} --motivo "<motivo>" (+${DESPACHOS_POR_LIBERACAO}).`
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
