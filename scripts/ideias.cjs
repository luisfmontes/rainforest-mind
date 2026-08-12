#!/usr/bin/env node
"use strict";
/* Port de scripts/ideias.py — escrita segura no ideias.jsonl, sem dependencia
 * externa (so biblioteca padrao do Node). Mesma interface de linha de comando,
 * mesmo comportamento, mesmos codigos de saida do original em Python.
 *
 * As oito garantias do original (ver scripts/ideias.py para o porque de cada
 * uma) sao preservadas aqui:
 *   1. Trava de arquivo (mesmo nome .ideias.lock do Python, coexistem)
 *   2. Releitura do arquivo VIVO no instante da escrita
 *   3. Backup antes de qualquer escrita
 *   4. Escrita em temporario + rename atomico
 *   5. Newline final garantido, LF sempre
 *   6. Contagem conferida por operacao
 *   7. Linhas nao-alvo conferidas byte a byte apos a escrita
 *   8. Data carimbada aqui, do relogio local (nunca UTC, nunca do input)
 */

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

// A raiz sai da mesma cadeia de 5 niveis que o hook usa (hooks/lib/raiz.cjs):
// RFM_ROOT > <projeto>/.rainforest > <config>/rainforest > plugin > legado. E o que
// permite um repo ter as proprias ideias sem env var nenhuma. Se a lib nao estiver
// junto (script copiado sozinho para uma caixa de areia, por exemplo), cai no
// comportamento antigo — a pasta acima do script.
const RAIZ = (() => {
  const local = path.resolve(__dirname, "..");
  try {
    const { resolverRaiz } = require("../hooks/lib/raiz.cjs");
    return resolverRaiz({ plugin: local }).raiz || local;
  } catch {
    return local;
  }
})();
const ALVO = path.join(RAIZ, "ideias.jsonl");
const ALVO_NOME = path.basename(ALVO);
const DIR_BACKUP = path.join(RAIZ, ".ideias-backups");
const TRAVA = path.join(RAIZ, ".ideias.lock"); // mesmo nome que o Python usa

// `gancho` e obrigatorio so aqui, no .cjs — regra 6 da skill exige que toda
// ideia plantada leve o gatilho concreto de retorno, e ate aqui isso vivia sem
// validacao dentro da prosa do `ao_colher`. O ideias.py fica congelado no
// contrato antigo de proposito (ele so existe para provar as oito garantias do
// port); o gancho e recurso novo, so do .cjs.
const CAMPOS_OBRIGATORIOS = ["id", "titulo", "descricao", "contexto", "projeto", "gancho"];
const CAMPOS_PROIBIDOS_NO_INPUT = [
  "status", "plantada_em", "colhida_em", "unificada_em", "unificada_em_id",
  "colheita_iniciada_em",
];
const STATUS_CONHECIDOS = ["plantada", "em-colheita", "colhida", "unificada"];
// Ideia ABERTA e a que ainda espera voltar — e so dela o `gancho` (gatilho de
// retorno, regra 6) faz sentido. Colhida ja voltou; unificada virou outra.
const ABERTAS = new Set(["plantada", "em-colheita"]);
const TIPOS_CONHECIDOS = ["ideia", "observacao"];
const ORDEM_CANONICA = [
  "id", "titulo", "descricao", "contexto", "projeto", "projeto_nota", "ao_colher", "tipo",
  "status", "plantada_em", "colheita_iniciada_em", "andamento",
  "colhida_em", "resultado", "unificada_em", "unificada_em_id", "absorveu",
];
const RE_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

class Erro extends Error {}

// --------------------------------------------------------------------------
// vocabulario de projeto — slug fechado, caminho FORA do dado
// --------------------------------------------------------------------------
// O `projeto` era texto livre e guardava caminho absoluto do Windows dentro de
// string JSON. A barra invertida seguida de `r` e escape de carriage return: o
// shell comeu o caminho e `C:\Projetos\rainforest-mind` virou `C:\Projetos` + CR
// + `ainforest-mind` em QUATRO registros. Junto disso, 22 valores distintos para
// 7 projetos reais (`rainforest-mind` escrito de quatro jeitos) tornavam o campo
// inagrupavel — o `semear.cjs` precisou de comparacao difusa para nao perder dois
// tercos do historico.
//
// A correcao mata a CLASSE, nao as 4 ocorrencias: o campo passa a ser slug de
// vocabulario fechado (kebab-case, sem barra, sem espaco — nada que um escape
// possa comer), e o caminho sai do dado para o `projetos.json` da pasta de dados.
// Aviso em prosa nao segura esquema ruim: o SKILL.md do /ideia ja alertava sobre o
// shell comer barra, e quebrou 4 vezes mesmo assim.
const ARQ_PROJETOS = path.join(RAIZ, "projetos.json");

function lerProjetos() {
  // Sem arquivo, devolve null — e QUEM CHAMA decide o que fazer com a ausencia.
  // Devolver {} aqui faria "vocabulario vazio" e "vocabulario inexistente"
  // parecerem a mesma coisa, e a primeira recusaria tudo numa instalacao nova.
  let bruto;
  try {
    bruto = fs.readFileSync(ARQ_PROJETOS, "utf8");
  } catch {
    return null;
  }
  let mapa;
  try {
    mapa = JSON.parse(bruto);
  } catch (e) {
    throw new Erro(`${ARQ_PROJETOS} nao e JSON valido: ${e.message}`);
  }
  if (typeof mapa !== "object" || mapa === null || Array.isArray(mapa)) {
    throw new Erro(`${ARQ_PROJETOS} precisa ser um objeto {slug: {...}}`);
  }
  for (const [slug, v] of Object.entries(mapa)) {
    if (!RE_ID.test(slug)) {
      throw new Erro(`slug '${slug}' em projetos.json nao e kebab-case`);
    }
    if (typeof v !== "object" || v === null || Array.isArray(v)) {
      throw new Erro(`projeto '${slug}' precisa ser um objeto {caminho, apelidos}`);
    }
  }
  return mapa;
}

function gravarProjetos(mapa) {
  const ordenado = {};
  for (const k of Object.keys(mapa).sort()) ordenado[k] = mapa[k];
  const tmp = `${ARQ_PROJETOS}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(ordenado, null, 2) + "\n", "utf8");
  fs.renameSync(tmp, ARQ_PROJETOS); // atomico, como o jsonl
}

function apelidosDe(mapa, slug) {
  const v = mapa[slug] || {};
  return Array.isArray(v.apelidos) ? v.apelidos.filter((a) => typeof a === "string" && a) : [];
}

function normalizarProsa(s) {
  return String(s === null || s === undefined ? "" : s)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-");
}

function posicaoDoTermo(prosaNorm, termo) {
  // Posicao do termo respeitando fronteira de hifen: `solta` nao casa dentro de
  // `consoltado`. Devolve -1 quando nao ha ocorrencia com fronteira.
  const t = normalizarProsa(termo).replace(/^-|-$/g, "");
  if (!t) return -1;
  let de = 0;
  for (;;) {
    const i = prosaNorm.indexOf(t, de);
    if (i < 0) return -1;
    const antesOk = i === 0 || prosaNorm[i - 1] === "-";
    const fim = i + t.length;
    const depoisOk = fim === prosaNorm.length || prosaNorm[fim] === "-";
    if (antesOk && depoisOk) return i;
    de = i + 1;
  }
}

function resolverSlug(prosa, mapa) {
  // Quem aparece PRIMEIRO na string ganha: o projeto e nomeado no comeco e o
  // resto do texto e detalhe ("rainforest-mind (...); observado em whatsapp-mcp"
  // e uma ideia do rainforest). Empate de posicao entre slugs diferentes e
  // ambiguidade declarada, nao desempate por chute.
  const norm = normalizarProsa(prosa);
  let melhor = null;
  let ambiguo = false;
  for (const slug of Object.keys(mapa)) {
    let pos = -1;
    for (const termo of [slug, ...apelidosDe(mapa, slug)]) {
      const p = posicaoDoTermo(norm, termo);
      if (p >= 0 && (pos < 0 || p < pos)) pos = p;
    }
    if (pos < 0) continue;
    if (melhor === null || pos < melhor.pos) {
      melhor = { slug, pos };
      ambiguo = false;
    } else if (pos === melhor.pos && melhor.slug !== slug) {
      ambiguo = true;
    }
  }
  if (!melhor || ambiguo) return null;
  return melhor.slug;
}

function semControle(s) {
  // CR, LF e TAB dentro do valor sao o rastro do bug: morrem aqui.
  return String(s === null || s === undefined ? "" : s).replace(/[\r\n\t]+/g, " ");
}

function tirarCaminhos(prosa) {
  // Remove SO o parenteses que e caminho inteiro (`(C:\Projetos\x)`, `(~/y)`) —
  // regra estreita de proposito. Prosa raramente comeca com letra + dois-pontos,
  // e apagar por heuristica larga perderia informacao real (branch, porta, fork).
  return semControle(prosa)
    .replace(/\(\s*(?:[A-Za-z]:|~[\\/]|\/)[^;()]*\)/g, "")
    .replace(/\s{2,}/g, " ")
    .replace(/\s+([;,])/g, "$1") // o `;` que sobrou solto depois do parenteses sair
    .trim()
    .replace(/^[\s;,\u2014-]+|[\s;,\u2014-]+$/g, "")
    .trim();
}

function soCaminho(s) {
  // Valor que e SO caminho, sem nome de projeto em volta. Vira nota nenhuma: o
  // caminho passa a morar no projetos.json, e e esse o ponto da mudanca.
  return /^\s*(?:[A-Za-z]:|~[\\/]|\/)[^;]*$/.test(semControle(s));
}

function notaDeProjeto(prosa, slug, mapa) {
  // Nota so existe quando a prosa carrega algo que o slug e o caminho NAO dizem
  // (branch, porta, fork, "observado em outro repo"). Nada de inventar campo para
  // guardar o que ja esta no vocabulario.
  if (soCaminho(prosa)) return null;
  const limpa = tirarCaminhos(prosa);
  let resto = normalizarProsa(limpa);
  for (const termo of [slug, ...apelidosDe(mapa, slug)]) {
    const t = normalizarProsa(termo).replace(/^-|-$/g, "");
    if (t) resto = resto.split(t).join("-");
  }
  const sobrou = resto.replace(/-+/g, "");
  if (sobrou.length < 3) return null;
  return limpa || null;
}

function avisoSemVocabulario() {
  process.stderr.write(
    "aviso: sem projetos.json na pasta de dados — o campo 'projeto' entrou SEM validacao " +
      "de vocabulario. Registre os slugs: node scripts/ideias.cjs projetos --registrar <slug>\n"
  );
}

function validarProjeto(valor) {
  const mapa = lerProjetos();
  if (mapa === null) {
    // Rule of the house: regra que o ambiente impede se ANUNCIA (uma linha, com o
    // efeito pratico), nunca degrada em silencio. Instalacao nova nao tem
    // vocabulario, e recusar tudo travaria o primeiro `plantar` do usuario.
    avisoSemVocabulario();
    return;
  }
  const slugs = Object.keys(mapa);
  if (slugs.includes(valor)) return;
  const sugerido = resolverSlug(valor, mapa);
  throw new Erro(
    `projeto '${semControle(valor)}' nao e slug conhecido.` +
      (sugerido ? ` Quis dizer '${sugerido}'?` : "") +
      `\n  registrados: ${slugs.sort().join(", ") || "(nenhum)"}` +
      `\n  se o projeto e novo: node scripts/ideias.cjs projetos --registrar <slug> --caminho <dir>`
  );
}

// --------------------------------------------------------------------------
// data — sempre local, nunca UTC
// --------------------------------------------------------------------------

function pad(n, len = 2) {
  return String(n).padStart(len, "0");
}

function hoje() {
  // Data do relogio LOCAL. Nunca toISOString() (UTC): depois das 21h em
  // Brasilia o UTC ja virou o dia seguinte e o carimbo sairia no futuro
  // (incidente 2026-08-08).
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function carimboAgora() {
  const d = new Date();
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}-` +
    `${pad(d.getMilliseconds(), 3)}`
  );
}

function parseISODate(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s));
  if (!m) return null;
  const y = +m[1], mo = +m[2], da = +m[3];
  const t = Date.UTC(y, mo - 1, da);
  const check = new Date(t);
  if (
    check.getUTCFullYear() !== y ||
    check.getUTCMonth() !== mo - 1 ||
    check.getUTCDate() !== da
  ) {
    return null;
  }
  return t;
}

// --------------------------------------------------------------------------
// sleep sincrono (para o poll da trava, sem bloquear em callback)
// --------------------------------------------------------------------------

function sleepSync(ms) {
  const sab = new SharedArrayBuffer(4);
  const ia = new Int32Array(sab);
  Atomics.wait(ia, 0, 0, ms);
}

// --------------------------------------------------------------------------
// trava e leitura
// --------------------------------------------------------------------------

class Trava {
  // Trava de arquivo entre sessoes paralelas. Stale acima de 120s e quebrada.
  constructor(caminho, esperaSeg = 10.0) {
    this.caminho = caminho;
    this.esperaSeg = esperaSeg;
    this.fd = null;
  }

  entrar() {
    const limite = Date.now() + this.esperaSeg * 1000;
    for (;;) {
      try {
        this.fd = fs.openSync(this.caminho, "wx");
        fs.writeSync(this.fd, `${process.pid} ${new Date().toISOString()}\n`);
        return this;
      } catch (e) {
        if (e.code !== "EEXIST") throw e;
        let idadeSeg;
        try {
          idadeSeg = (Date.now() - fs.statSync(this.caminho).mtimeMs) / 1000;
        } catch (e2) {
          // trava sumiu entre o EEXIST e o stat — tenta de novo
          continue;
        }
        if (idadeSeg > 120) {
          process.stderr.write(
            `aviso: trava com ${idadeSeg.toFixed(0)}s (orfa) — quebrando\n`
          );
          try {
            fs.unlinkSync(this.caminho);
          } catch (e3) {
            /* ja sumiu, segue */
          }
          continue;
        }
        if (Date.now() > limite) {
          throw new Erro(
            `outra sessao esta escrevendo (trava em ${this.caminho} ha ${idadeSeg.toFixed(0)}s). ` +
              "Tente de novo em instantes."
          );
        }
        sleepSync(200);
      }
    }
  }

  sair() {
    if (this.fd !== null) {
      fs.closeSync(this.fd);
      this.fd = null;
    }
    try {
      fs.unlinkSync(this.caminho);
    } catch (e) {
      /* ja sumiu, tudo bem */
    }
  }
}

function comTrava(fn) {
  const trava = new Trava(TRAVA);
  trava.entrar();
  try {
    return fn();
  } finally {
    trava.sair();
  }
}

function lerVivo() {
  // Le o arquivo VIVO agora. Nunca reaproveitar leitura de antes da operacao.
  if (!fs.existsSync(ALVO)) {
    throw new Erro(`nao achei ${ALVO}`);
  }
  const bruto = fs.readFileSync(ALVO, "utf8");
  return bruto.split("\n").filter((l) => l.trim().length > 0);
}

function parseLinhas(linhas) {
  const saida = [];
  linhas.forEach((l, idx) => {
    try {
      saida.push(JSON.parse(l));
    } catch (e) {
      throw new Erro(`linha ${idx + 1} nao e JSON valido: ${e.message}`);
    }
  });
  return saida;
}

function indicePorId(linhas, alvoId) {
  const objs = parseLinhas(linhas);
  for (let i = 0; i < objs.length; i++) {
    if (objs[i] && objs[i].id === alvoId) return i;
  }
  throw new Erro(`id '${alvoId}' nao existe no arquivo`);
}

function serializar(obj) {
  // Uma linha, campos na ordem canonica, acento literal (o arquivo e UTF-8).
  const ordenado = {};
  for (const k of ORDEM_CANONICA) {
    if (Object.prototype.hasOwnProperty.call(obj, k)) ordenado[k] = obj[k];
  }
  for (const k of Object.keys(obj)) {
    if (!Object.prototype.hasOwnProperty.call(ordenado, k)) ordenado[k] = obj[k];
  }
  const linha = JSON.stringify(ordenado);
  JSON.parse(linha); // nunca gravar o que nao volta
  return linha;
}

// --------------------------------------------------------------------------
// gravacao verificada — o coracao
// --------------------------------------------------------------------------

function gravar(linhasAntes, linhasDepois, alvos, rotulo) {
  // `alvos` (Set<number>) sao os indices que PODEM ter mudado. Todo o resto e
  // conferido byte a byte: contagem igual convive com a linha errada
  // sobrescrita, entao contagem sozinha nao prova nada.
  fs.mkdirSync(DIR_BACKUP, { recursive: true });
  const carimbo = carimboAgora();
  const backup = path.join(DIR_BACKUP, `ideias-${carimbo}.jsonl`);
  if (fs.existsSync(backup)) {
    throw new Erro(`backup ${path.basename(backup)} ja existe — abortando antes de escrever`);
  }
  fs.copyFileSync(ALVO, backup);

  const tmp = ALVO.replace(/\.jsonl$/, ".jsonl.tmp");
  fs.writeFileSync(tmp, linhasDepois.join("\n") + "\n", "utf8"); // newline final garantido, LF puro
  fs.renameSync(tmp, ALVO); // atomico

  // --- prova, lendo do disco ---
  const relidas = lerVivo();
  const problemas = [];

  if (relidas.length !== linhasDepois.length) {
    problemas.push(`contagem no disco ${relidas.length} != esperada ${linhasDepois.length}`);
  }

  let intocadas = 0;
  const limite = Math.min(linhasAntes.length, relidas.length);
  for (let i = 0; i < limite; i++) {
    if (alvos.has(i)) continue;
    if (linhasAntes[i] === relidas[i]) {
      intocadas += 1;
    } else {
      problemas.push(`linha ${i + 1} mudou e nao devia`);
    }
  }

  try {
    parseLinhas(relidas);
  } catch (e) {
    problemas.push(e.message);
  }

  const naoAlvo =
    linhasAntes.length - [...alvos].filter((i) => i < linhasAntes.length).length;
  console.log(`  contagem: ${linhasAntes.length} -> ${relidas.length}`);
  console.log(`  todas as ${relidas.length} linhas sao JSON valido: ${problemas.length === 0 ? "sim" : "NAO"}`);
  console.log(`  linhas nao-alvo identicas byte a byte: ${intocadas}/${naoAlvo}`);
  console.log(`  backup: ${path.relative(RAIZ, backup)}`);

  if (problemas.length) {
    fs.copyFileSync(backup, ALVO);
    throw new Erro(`${rotulo} REVERTIDO — ${problemas.join("; ")}`);
  }
  console.log(`  ${rotulo}: ok`);
}

function validarEntrada(obj, exigirObrigatorios = true) {
  if (typeof obj !== "object" || obj === null || Array.isArray(obj)) {
    throw new Erro("o JSON da entrada precisa ser um objeto");
  }
  const proibidos = CAMPOS_PROIBIDOS_NO_INPUT.filter((c) =>
    Object.prototype.hasOwnProperty.call(obj, c)
  );
  if (proibidos.length) {
    throw new Erro(
      `campo(s) ${proibidos.join(", ")} nao vem da entrada — quem carimba e o script, ` +
        "do relogio local. Remova e rode de novo."
    );
  }
  if (exigirObrigatorios) {
    const faltando = CAMPOS_OBRIGATORIOS.filter((c) => !obj[c]);
    if (faltando.length) {
      throw new Erro(`campo(s) obrigatorio(s) faltando ou vazio(s): ${faltando.join(", ")}`);
    }
  }
  if (Object.prototype.hasOwnProperty.call(obj, "id") && !RE_ID.test(obj.id)) {
    throw new Erro(`id '${obj.id}' nao e kebab-case ([a-z0-9] separado por hifen)`);
  }
  if (
    Object.prototype.hasOwnProperty.call(obj, "tipo") &&
    !TIPOS_CONHECIDOS.includes(obj.tipo)
  ) {
    throw new Erro(`tipo '${obj.tipo}' desconhecido — use ${TIPOS_CONHECIDOS.join(" ou ")}`);
  }
  if (obj.projeto) validarProjeto(obj.projeto);
}

function lerStdin() {
  let bruto;
  try {
    bruto = fs.readFileSync(0, "utf8").trim();
  } catch (e) {
    bruto = "";
  }
  if (!bruto) {
    throw new Erro("nada na entrada padrao — mande o JSON por stdin (< arquivo.json)");
  }
  try {
    return JSON.parse(bruto);
  } catch (e) {
    throw new Erro(`entrada nao e JSON valido: ${e.message}`);
  }
}

// --------------------------------------------------------------------------
// comandos
// --------------------------------------------------------------------------

function cmdPlantar(_args) {
  const novo = lerStdin();
  validarEntrada(novo);
  comTrava(() => {
    const antes = lerVivo();
    if (parseLinhas(antes).some((o) => o.id === novo.id)) {
      throw new Erro(`ja existe ideia com id '${novo.id}' — escolha outro`);
    }
    novo.status = "plantada";
    novo.plantada_em = hoje();
    if (!Object.prototype.hasOwnProperty.call(novo, "ao_colher")) novo.ao_colher = null;
    const depois = antes.concat([serializar(novo)]);
    console.log(`plantando '${novo.id}'`);
    gravar(antes, depois, new Set([antes.length]), "plantar");
  });
}

function cmdColher(args) {
  const entrada = lerStdin();
  validarEntrada(entrada, false);
  if (!entrada.resultado) {
    throw new Erro('colher exige {"resultado": "..."} na entrada — o que de fato foi entregue');
  }
  comTrava(() => {
    const antes = lerVivo();
    const i = indicePorId(antes, args.id);
    const obj = JSON.parse(antes[i]);
    if (obj.status === "colhida") {
      throw new Erro(`'${args.id}' ja esta colhida em ${obj.colhida_em}`);
    }
    for (const [k, v] of Object.entries(entrada)) {
      if (k !== "resultado") obj[k] = v;
    }
    obj.status = "colhida";
    obj.colhida_em = hoje();
    obj.resultado = entrada.resultado;
    const depois = antes.slice();
    depois[i] = serializar(obj);
    console.log(`colhendo '${args.id}' (linha ${i + 1})`);
    gravar(antes, depois, new Set([i]), "colher");
  });
}

function cmdEditar(args) {
  const entrada = lerStdin();
  validarEntrada(entrada, false);
  if (Object.prototype.hasOwnProperty.call(entrada, "id") && entrada.id !== args.id) {
    throw new Erro("editar nao troca id — o id e a identidade da ideia, nao um campo");
  }
  const mudaveis = {};
  for (const [k, v] of Object.entries(entrada)) {
    if (k !== "id") mudaveis[k] = v;
  }
  if (Object.keys(mudaveis).length === 0) {
    throw new Erro("nada para editar — mande no JSON so os campos que mudam");
  }
  comTrava(() => {
    const antes = lerVivo();
    const i = indicePorId(antes, args.id);
    const obj = JSON.parse(antes[i]);
    if (obj.status === "colhida" || obj.status === "unificada") {
      throw new Erro(`'${args.id}' esta '${obj.status}' — o que ja fechou nao se reescreve`);
    }
    Object.assign(obj, mudaveis);
    obj.editada_em = hoje();
    const depois = antes.slice();
    depois[i] = serializar(obj);
    console.log(`editando '${args.id}' (linha ${i + 1}): ${Object.keys(mudaveis).sort().join(", ")}`);
    gravar(antes, depois, new Set([i]), "editar");
  });
}

function cmdIniciar(args) {
  comTrava(() => {
    const antes = lerVivo();
    const i = indicePorId(antes, args.id);
    const obj = JSON.parse(antes[i]);
    if (obj.status !== "plantada") {
      throw new Erro(`'${args.id}' esta '${obj.status}', so 'plantada' vira 'em-colheita'`);
    }
    obj.status = "em-colheita";
    obj.colheita_iniciada_em = hoje();
    if (args.andamento) obj.andamento = args.andamento;
    const depois = antes.slice();
    depois[i] = serializar(obj);
    console.log(`iniciando colheita de '${args.id}' (linha ${i + 1})`);
    gravar(antes, depois, new Set([i]), "iniciar");
  });
}

function cmdUnificar(args) {
  const fundida = lerStdin();
  validarEntrada(fundida);
  if (args.manter === args.absorver) {
    throw new Erro("--manter e --absorver precisam ser ideias diferentes");
  }
  comTrava(() => {
    const antes = lerVivo();
    const iManter = indicePorId(antes, args.manter);
    const iAbsorver = indicePorId(antes, args.absorver);
    const sobrevivente = JSON.parse(antes[iManter]);
    const absorvida = JSON.parse(antes[iAbsorver]);
    if (absorvida.status === "colhida" || absorvida.status === "unificada") {
      throw new Erro(`'${args.absorver}' esta '${absorvida.status}' — nao se absorve`);
    }

    Object.assign(sobrevivente, fundida);
    sobrevivente.status = sobrevivente.status || "plantada";
    if (!sobrevivente.plantada_em) sobrevivente.plantada_em = hoje();
    const absorvidas = Array.isArray(sobrevivente.absorveu) ? sobrevivente.absorveu.slice() : [];
    if (!absorvidas.includes(args.absorver)) absorvidas.push(args.absorver);
    sobrevivente.absorveu = absorvidas;

    absorvida.status = "unificada";
    absorvida.unificada_em = hoje();
    absorvida.unificada_em_id = sobrevivente.id;

    const depois = antes.slice();
    depois[iManter] = serializar(sobrevivente);
    depois[iAbsorver] = serializar(absorvida);
    console.log(
      `unificando '${args.absorver}' (linha ${iAbsorver + 1}) ` +
        `em '${sobrevivente.id}' (linha ${iManter + 1})`
    );
    gravar(antes, depois, new Set([iManter, iAbsorver]), "unificar");
  });
}

function dataDoGit(alvoId) {
  // Data do commit mais antigo que introduziu este id no jsonl, ou null.
  let r;
  try {
    r = spawnSync(
      "git",
      ["log", "--reverse", "--format=%ad", "--date=short", "-S", `"${alvoId}"`, "--", ALVO_NOME],
      { cwd: RAIZ, encoding: "utf8", timeout: 30000 }
    );
  } catch (e) {
    return null;
  }
  if (!r || r.error || r.status !== 0) return null;
  const linhas = (r.stdout || "")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
  return linhas.length ? linhas[0] : null;
}

function diagnosticar(obj) {
  // Campos de estado ausentes e de onde sairia o valor. So olha o que FALTA.
  const faltando = {};
  if (!STATUS_CONHECIDOS.includes(obj.status)) {
    if (obj.unificada_em) {
      faltando.status = "unificada";
    } else if (obj.colhida_em || obj.resultado) {
      faltando.status = "colhida";
    } else if (obj.colheita_iniciada_em) {
      faltando.status = "em-colheita";
    } else {
      faltando.status = "plantada";
    }
  }
  if (!obj.plantada_em) {
    faltando.plantada_em = "<git>";
  }
  if (!obj.gancho) {
    faltando.gancho = "<manual>";
  }
  return faltando;
}

function cmdReparar(args) {
  if (!args.id && !args.todas) {
    throw new Erro("diga --id <id> ou --todas (com --conferir, nada e gravado)");
  }
  if (args.plantada_em) {
    if (!args.id) {
      throw new Erro("--plantada-em so vale com --id, uma linha por vez");
    }
    if (!parseISODate(args.plantada_em)) {
      throw new Erro(`--plantada-em '${args.plantada_em}' nao e data ISO (AAAA-MM-DD)`);
    }
    if (args.plantada_em > hoje()) {
      throw new Erro(`--plantada-em ${args.plantada_em} esta no futuro`);
    }
  }
  if (args.gancho && !args.id) {
    throw new Erro("--gancho so vale com --id, uma linha por vez");
  }

  comTrava(() => {
    const antes = lerVivo();
    const objs = parseLinhas(antes);
    const indices = args.id
      ? [indicePorId(antes, args.id)]
      : objs.map((o, i) => [i, o]).filter(([, o]) => Object.keys(diagnosticar(o)).length > 0).map(([i]) => i);
    if (indices.length === 0) {
      console.log("nada a reparar — nenhuma linha com campo de estado ausente.");
      return;
    }

    const depois = antes.slice();
    const alvos = new Set();
    const pendentesData = new Set();
    const pendentesGancho = new Set();
    for (const i of indices) {
      const obj = JSON.parse(antes[i]);
      const faltando = diagnosticar(obj);
      if (Object.keys(faltando).length === 0) {
        console.log(`linha ${i + 1} (${obj.id}): nada ausente — nao mexo.`);
        continue;
      }
      const resolvido = {};
      let pulaLinha = false;
      for (const [campo, valor] of Object.entries(faltando)) {
        let origem;
        if (valor !== "<git>" && valor !== "<manual>") {
          resolvido[campo] = valor;
          origem = "inferido do proprio registro";
        } else if (valor === "<manual>") {
          if (args.gancho) {
            resolvido[campo] = args.gancho;
            origem = "informado na linha de comando";
          } else if (args.conferir) {
            pendentesGancho.add(obj.id);
            console.log(
              `  ${obj.id}.${campo} = ?  (sem gancho — precisa de --gancho "<texto>")`
            );
            continue;
          } else {
            throw new Erro(
              `'${obj.id}': falta gancho e nenhum foi informado — passe --gancho "<texto>" ` +
                "com o gatilho de retorno real (evento, data ou condicao)."
            );
          }
        } else if (args.plantada_em) {
          resolvido[campo] = args.plantada_em;
          origem = "informado na linha de comando";
        } else {
          const d = dataDoGit(obj.id);
          if (d) {
            resolvido[campo] = d;
            origem = "data do commit que introduziu a linha";
          } else if (args.conferir) {
            pendentesData.add(obj.id);
            console.log(
              `  ${obj.id}.${campo} = ?  (o git nao sabe — precisa de --plantada-em AAAA-MM-DD)`
            );
            continue;
          } else {
            throw new Erro(
              `'${obj.id}': o git nao sabe quando esta linha entrou ` +
                `(ainda nao commitada?). Nao vou carimbar hoje numa linha que nao ` +
                `nasceu hoje — passe --plantada-em AAAA-MM-DD com a data real.`
            );
          }
        }
        console.log(`  ${obj.id}.${campo} = ${resolvido[campo]}  (${origem})`);
      }
      if (args.conferir) continue;
      Object.assign(obj, resolvido);
      obj.reparada_em = hoje();
      obj.reparo = Object.keys(resolvido).sort();
      depois[i] = serializar(obj);
      alvos.add(i);
    }

    if (args.conferir) {
      console.log(`\n--conferir: ${indices.length} linha(s) acima, nada gravado.`);
      if (pendentesData.size) {
        console.log(
          `${pendentesData.size} sem data no git — o reparo real vai recusar ` +
            `ate receber --plantada-em: ${[...pendentesData].sort().join(", ")}`
        );
      }
      if (pendentesGancho.size) {
        console.log(
          `${pendentesGancho.size} sem gancho — o reparo real vai recusar ` +
            `ate receber --gancho "<texto>": ${[...pendentesGancho].sort().join(", ")}`
        );
      }
      return;
    }
    if (alvos.size === 0) return;
    console.log(`reparando ${alvos.size} linha(s)`);
    gravar(antes, depois, alvos, "reparar");
  });
}

function cmdProjetos(args) {
  if (!args.registrar) {
    const mapa = lerProjetos();
    if (mapa === null) {
      console.log(`sem vocabulario: ${ARQ_PROJETOS} nao existe.`);
      console.log("  crie o primeiro: node scripts/ideias.cjs projetos --registrar <slug> --caminho <dir>");
      return;
    }
    const slugs = Object.keys(mapa).sort();
    console.log(`${slugs.length} projeto(s) em ${path.relative(RAIZ, ARQ_PROJETOS)}\n`);
    for (const s of slugs) {
      const ap = apelidosDe(mapa, s);
      console.log(`- ${s}`);
      console.log(`  caminho: ${mapa[s].caminho || "(nenhum — projeto sem pasta propria)"}`);
      if (ap.length) console.log(`  apelidos: ${ap.join(", ")}`);
    }
    return;
  }
  if (!RE_ID.test(args.registrar)) {
    throw new Erro(
      `slug '${args.registrar}' nao e kebab-case ([a-z0-9] separado por hifen). ` +
        "O slug e fechado justamente para nao caber barra nem espaco — foi barra dentro " +
        "de string JSON que corrompeu 4 registros."
    );
  }
  const mapa = lerProjetos() || {};
  const novo = !Object.prototype.hasOwnProperty.call(mapa, args.registrar);
  const atual = mapa[args.registrar] || {};
  const apelidos = new Set(apelidosDe(mapa, args.registrar));
  if (args.apelido) {
    for (const a of String(args.apelido).split(",").map((x) => x.trim()).filter(Boolean)) {
      apelidos.add(a);
    }
  }
  mapa[args.registrar] = {
    caminho: args.caminho !== null && args.caminho !== undefined ? args.caminho : (atual.caminho || null),
    apelidos: [...apelidos].sort(),
  };
  gravarProjetos(mapa);
  console.log(`${novo ? "registrado" : "atualizado"} '${args.registrar}'`);
  console.log(`  caminho: ${mapa[args.registrar].caminho || "(nenhum)"}`);
  console.log(`  apelidos: ${mapa[args.registrar].apelidos.join(", ") || "(nenhum)"}`);
  console.log(`  arquivo: ${ARQ_PROJETOS}`);
}

function cmdNormalizarProjetos(args) {
  // Migracao da prosa para slug. ENSAIO por padrao: `--aplicar` e que grava, como
  // no `foco.cjs rotacionar`. Linha que o vocabulario nao resolve NAO e chutada —
  // ela para a migracao e sobe para o usuario decidir (--mapear id=slug), porque
  // adivinhar projeto errado enterra a ideia num lugar onde ninguem vai procurar.
  const mapa = lerProjetos();
  if (mapa === null) {
    throw new Erro(
      "sem projetos.json — nao ha vocabulario para normalizar contra. " +
        "Registre os slugs primeiro: node scripts/ideias.cjs projetos --registrar <slug>"
    );
  }
  const forcado = {};
  if (args.mapear) {
    for (const par of String(args.mapear).split(",").map((x) => x.trim()).filter(Boolean)) {
      const i = par.indexOf("=");
      if (i < 0) throw new Erro(`--mapear espera 'id=slug' (veio '${par}')`);
      const id = par.slice(0, i).trim();
      const slug = par.slice(i + 1).trim();
      if (!Object.prototype.hasOwnProperty.call(mapa, slug)) {
        throw new Erro(`--mapear ${id}=${slug}: '${slug}' nao esta no projetos.json`);
      }
      forcado[id] = slug;
    }
  }

  comTrava(() => {
    const antes = lerVivo();
    const objs = parseLinhas(antes);
    const depois = antes.slice();
    const alvos = new Set();
    const pendentes = [];
    let jaOk = 0;

    objs.forEach((o, i) => {
      const prosa = o.projeto;
      if (prosa && Object.prototype.hasOwnProperty.call(mapa, prosa)) {
        jaOk += 1;
        return;
      }
      const slug = forcado[o.id] || resolverSlug(prosa, mapa);
      if (!slug) {
        pendentes.push({ linha: i + 1, id: o.id, prosa: semControle(prosa) });
        return;
      }
      const nota = notaDeProjeto(prosa, slug, mapa);
      const obj = JSON.parse(antes[i]);
      obj.projeto = slug;
      if (nota) obj.projeto_nota = nota;
      else delete obj.projeto_nota;
      const linha = serializar(obj);
      if (linha === antes[i]) {
        jaOk += 1;
        return;
      }
      depois[i] = linha;
      alvos.add(i);
      const origem = forcado[o.id] ? " (mapeado na linha de comando)" : "";
      console.log(`linha ${i + 1} (${o.id}): '${semControle(prosa)}' -> ${slug}${origem}`);
      if (nota) console.log(`  projeto_nota: ${nota}`);
    });

    console.log(
      `\n${alvos.size} linha(s) a normalizar, ${jaOk} ja em slug, ${pendentes.length} sem resolucao`
    );
    if (pendentes.length) {
      console.log("\nsem resolucao no vocabulario (nada foi gravado por causa destas):");
      for (const p of pendentes) console.log(`  linha ${p.linha} (${p.id}): '${p.prosa}'`);
      console.log(
        "\n  resolva de um destes dois jeitos:\n" +
          "    node scripts/ideias.cjs projetos --registrar <slug> --apelido '<termo da prosa>'\n" +
          `    node scripts/ideias.cjs normalizar-projetos --mapear ${pendentes[0].id}=<slug> --aplicar`
      );
      throw new Erro(
        `${pendentes.length} linha(s) sem slug resolvido — migracao parcial esconderia o resto`
      );
    }
    if (!args.aplicar) {
      console.log("\n--aplicar ausente: ensaio, nada gravado.");
      return;
    }
    if (alvos.size === 0) {
      console.log("nada a normalizar — todo projeto ja e slug do vocabulario.");
      return;
    }
    gravar(antes, depois, alvos, "normalizar-projetos");
  });
}

function cmdListar(args) {
  const objs = parseLinhas(lerVivo());
  const hjStr = hoje();
  const hjTs = parseISODate(hjStr);
  const alvoStatus = args.status;
  let itens = objs.filter((o) => alvoStatus === "todos" || o.status === alvoStatus);
  if (args.tipo !== "todos") {
    itens = itens.filter((o) => (o.tipo || "ideia") === args.tipo);
  }
  // Filtro por projeto: e o que o campo em prosa nao permitia. Compara por
  // igualdade de slug, e recusa slug que nao existe em vez de devolver lista
  // vazia — lista vazia por erro de digitacao parece "nao ha nada aqui".
  if (args.projeto) {
    const mapa = lerProjetos();
    if (mapa !== null && !Object.prototype.hasOwnProperty.call(mapa, args.projeto)) {
      throw new Erro(
        `projeto '${args.projeto}' nao esta no vocabulario — registrados: ` +
          `${Object.keys(mapa).sort().join(", ") || "(nenhum)"}`
      );
    }
    itens = itens.filter((o) => o.projeto === args.projeto);
  }

  function idade(o) {
    const ts = parseISODate(o.plantada_em);
    if (ts === null) return null;
    return Math.round((hjTs - ts) / 86400000);
  }

  itens = itens.slice().sort((a, b) => {
    const pa = a.plantada_em || "";
    const pb = b.plantada_em || "";
    if (pa < pb) return 1;
    if (pa > pb) return -1;
    return 0;
  });
  const rotuloTipo = args.tipo === "todos" ? "" : ` (${args.tipo})`;
  console.log(`${itens.length} ${alvoStatus}${rotuloTipo}\n`);
  for (const o of itens) {
    const d = idade(o);
    let quando = d === null ? "data invalida" : d === 0 ? "hoje" : `ha ${d} dia${d !== 1 ? "s" : ""}`;
    if (d !== null && d < 0) {
      quando = `DATA NO FUTURO (${o.plantada_em})`;
    }
    console.log(`- ${o.titulo}`);
    console.log(`  ${o.id} | ${quando} | ${o.projeto}`);
  }
  const total = objs.length;
  const colhidas = objs.filter((o) => o.status === "colhida").length;
  console.log(`\n${total} no total, ${colhidas} colhidas.`);
  if (!args.projeto) {
    // Agrupar era impossivel com o campo em prosa (22 valores para 7 projetos).
    // Com slug, sai de graca — e e o que mostra onde a divida esta concentrada.
    const porProjeto = {};
    for (const o of itens) {
      const p = o.projeto || "(sem projeto)";
      porProjeto[p] = (porProjeto[p] || 0) + 1;
    }
    const linhas = Object.keys(porProjeto)
      .sort((a, b) => porProjeto[b] - porProjeto[a] || (a < b ? -1 : 1))
      .map((p) => `${p}: ${porProjeto[p]}`);
    if (linhas.length) console.log(`por projeto — ${linhas.join(", ")}`);
  }
}

function cmdConferir(_args) {
  const linhas = lerVivo();
  const objs = parseLinhas(linhas);
  const hjStr = hoje();
  const problemas = [];
  const vistos = {};
  const mapaProjetos = lerProjetos();
  objs.forEach((o, idx) => {
    const i = idx + 1;
    const ident = o.id;
    if (!ident) {
      problemas.push(`linha ${i}: sem id`);
    } else if (!RE_ID.test(ident)) {
      problemas.push(`linha ${i}: id '${ident}' nao e kebab-case`);
    } else if (Object.prototype.hasOwnProperty.call(vistos, ident)) {
      problemas.push(`linha ${i}: id '${ident}' repetido (ja na linha ${vistos[ident]})`);
    } else {
      vistos[ident] = i;
    }
    if (!STATUS_CONHECIDOS.includes(o.status)) {
      problemas.push(`linha ${i}: status '${o.status}' desconhecido`);
    }
    if (o.tipo !== undefined && o.tipo !== null && !TIPOS_CONHECIDOS.includes(o.tipo)) {
      problemas.push(`linha ${i}: tipo '${o.tipo}' desconhecido`);
    }
    for (const campo of ["plantada_em", "colhida_em", "unificada_em", "colheita_iniciada_em"]) {
      const v = o[campo];
      if (!v) continue;
      if (!parseISODate(v)) {
        problemas.push(`linha ${i} (${ident}): ${campo}='${v}' nao e data ISO`);
      } else if (v > hjStr) {
        problemas.push(`linha ${i} (${ident}): ${campo}=${v} esta NO FUTURO (hoje e ${hjStr})`);
      }
    }
    if (o.status === "colhida" && !o.resultado) {
      problemas.push(`linha ${i} (${ident}): colhida sem resultado`);
    }
    for (const campo of CAMPOS_OBRIGATORIOS) {
      // O gancho e gatilho de RETORNO: ideia ja colhida voltou, e cobrar gatilho de
      // quem chegou e ruido que ensina a ignorar o conferir. So as abertas contam.
      if (campo === "gancho" && !ABERTAS.has(o.status)) continue;
      if (!o[campo]) {
        problemas.push(`linha ${i} (${ident}): campo obrigatorio '${campo}' vazio`);
      }
    }
    // Caractere de controle no `projeto` e a assinatura do bug de escape: e por
    // aqui que `C:\Projetos\rainforest-mind` virou `C:\Projetos` + CR + `ainforest`.
    // Vale para toda linha, inclusive colhida, porque e corrupcao e nao pendencia.
    if (o.projeto && /[\r\n\t]/.test(o.projeto)) {
      problemas.push(
        `linha ${i} (${ident}): projeto tem caractere de controle (CR/LF/TAB) — ` +
          "rastro de caminho comido por escape"
      );
    } else if (o.projeto && mapaProjetos !== null &&
               !Object.prototype.hasOwnProperty.call(mapaProjetos, o.projeto)) {
      problemas.push(
        `linha ${i} (${ident}): projeto '${o.projeto}' fora do vocabulario — ` +
          "rode: node scripts/ideias.cjs normalizar-projetos"
      );
    }
  });

  console.log(`arquivo: ${ALVO}`);
  console.log(`${objs.length} linhas, ${Object.keys(vistos).length} ids unicos`);
  for (const s of STATUS_CONHECIDOS) {
    console.log(`  ${s}: ${objs.filter((o) => o.status === s).length}`);
  }
  if (problemas.length) {
    console.log(`\n${problemas.length} problema(s):`);
    for (const p of problemas) console.log(`  - ${p}`);
    throw new Erro("conferencia falhou");
  }
  console.log("\nsem problemas.");
}

// --------------------------------------------------------------------------
// argumentos de linha de comando (equivalente minimo ao argparse)
// --------------------------------------------------------------------------

const SUBCOMANDOS = {
  plantar: { options: {}, fn: cmdPlantar },
  colher: { options: { id: { required: true } }, fn: cmdColher },
  editar: { options: { id: { required: true } }, fn: cmdEditar },
  iniciar: {
    options: { id: { required: true }, andamento: { required: false } },
    fn: cmdIniciar,
  },
  unificar: {
    options: { manter: { required: true }, absorver: { required: true } },
    fn: cmdUnificar,
  },
  reparar: {
    options: {
      id: { required: false },
      todas: { flag: true },
      conferir: { flag: true },
      "plantada-em": { required: false, dest: "plantada_em" },
      gancho: { required: false },
    },
    fn: cmdReparar,
  },
  listar: {
    options: {
      status: { required: false, default: "plantada", choices: [...STATUS_CONHECIDOS, "todos"] },
      tipo: { required: false, default: "ideia", choices: [...TIPOS_CONHECIDOS, "todos"] },
      projeto: { required: false },
    },
    fn: cmdListar,
  },
  conferir: { options: {}, fn: cmdConferir },
  projetos: {
    options: {
      registrar: { required: false },
      caminho: { required: false },
      apelido: { required: false },
    },
    fn: cmdProjetos,
  },
  "normalizar-projetos": {
    options: {
      aplicar: { flag: true },
      mapear: { required: false },
    },
    fn: cmdNormalizarProjetos,
  },
};

function erroArgs(msg) {
  process.stderr.write(`ideias.cjs: erro: ${msg}\n`);
  process.exit(2);
}

function destDe(chave, o) {
  return o.dest || chave.replace(/-/g, "_");
}

function parseArgs(argv) {
  if (argv.length === 0) {
    erroArgs(
      "subcomando obrigatorio (" + Object.keys(SUBCOMANDOS).join("|") + ")"
    );
  }
  const cmd = argv[0];
  const spec = SUBCOMANDOS[cmd];
  if (!spec) erroArgs(`subcomando desconhecido: ${cmd}`);

  const args = { cmd };
  for (const [chave, o] of Object.entries(spec.options)) {
    const dest = destDe(chave, o);
    if (o.flag) args[dest] = false;
    else if (Object.prototype.hasOwnProperty.call(o, "default")) args[dest] = o.default;
    else args[dest] = null;
  }

  let i = 1;
  while (i < argv.length) {
    const tok = argv[i];
    if (!tok.startsWith("--")) erroArgs(`argumento inesperado: ${tok}`);
    const chave = tok.slice(2);
    const o = spec.options[chave];
    if (!o) erroArgs(`opcao desconhecida: ${tok}`);
    const dest = destDe(chave, o);
    if (o.flag) {
      args[dest] = true;
      i += 1;
      continue;
    }
    const val = argv[i + 1];
    if (val === undefined) erroArgs(`opcao ${tok} exige valor`);
    if (o.choices && !o.choices.includes(val)) {
      erroArgs(`valor invalido para ${tok}: ${val} (use ${o.choices.join("|")})`);
    }
    args[dest] = val;
    i += 2;
  }

  for (const [chave, o] of Object.entries(spec.options)) {
    const dest = destDe(chave, o);
    if (o.required && !args[dest]) erroArgs(`opcao obrigatoria faltando: --${chave}`);
  }

  args._fn = spec.fn;
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  try {
    args._fn(args);
  } catch (e) {
    if (e instanceof Erro) {
      process.stderr.write(`erro: ${e.message}\n`);
      return 1;
    }
    throw e;
  }
  return 0;
}

process.exitCode = main();
