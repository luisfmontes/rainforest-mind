#!/usr/bin/env node
"use strict";
/* scripts/jornada.cjs — port de scripts/jornada.py, sem dependencia externa
 * (so biblioteca padrao do Node). Mesma interface de linha de comando, mesmo
 * comportamento, mesmos numeros do original em Python.
 *
 * Uso:
 *     node scripts/jornada.cjs                          # hoje, todas as janelas
 *     node scripts/jornada.cjs --dia 2026-08-09
 *     node scripts/jornada.cjs --transcript <arquivo.jsonl>
 *     node scripts/jornada.cjs --corte 90               # outro limiar de lacuna
 *     node scripts/jornada.cjs --sem-descarte           # MUTACAO: nao descarta lacuna
 *
 * POR QUE ESTE SCRIPT EXISTE
 * --------------------------
 * A regra 8 (guarda-corpo de jornada) mede a jornada efetiva pelo intervalo entre
 * mensagens HUMANAS consecutivas do Luis: cada prompt dele prova que ele estava
 * ali naquele instante. Lacuna acima do corte e pausa, nao trabalho, e sai da
 * conta. O script original (jornada.py) ficava preso a Python, que nao esta mais
 * no caminho de execucao de nada neste plugin desde que o ideias.py foi portado
 * para .cjs — este port fecha essa dependencia.
 *
 * DUAS ARMADILHAS, as duas medidas no repo em 2026-08-09 (ver jornada.py)
 * -------------------------------------------------------------------------
 * 1. `type == "user"` NAO significa mensagem humana. Num transcript medido, de
 *    377 entradas "user" so 42 eram do Luis — as outras eram `toolUseResult`,
 *    mais `isMeta` e `isCompactSummary`. O filtro e obrigatorio; sem ele o
 *    script mede o ritmo das FERRAMENTAS.
 *
 * 2. Os carimbos do transcript sao UTC (terminam em Z), e a regra decide por
 *    hora LOCAL. A conversao acontece uma vez, na entrada (mensagensHumanas),
 *    e o resto do script so ve hora local.
 *
 * CORTE_PADRAO_MIN = 55 (revisado em 2026-08-11, era 75): 75 ficava acima do
 * ritmo normal de trabalho (p95 = 49,8 min) mas engolia um almoco de 1h inteiro
 * como se fosse jornada — 55 continua acima do p95 e fica abaixo de um almoco.
 * Ver scripts/jornada.py para a medicao completa que embasa o numero.
 */

const fs = require("fs");
const os = require("os");
const path = require("path");

const CORTE_PADRAO_MIN = 55;

// --------------------------------------------------------------------------
// transcripts disponiveis
// --------------------------------------------------------------------------

function transcriptsDisponiveis() {
  const base = process.env.USERPROFILE || os.homedir();
  const achados = [];
  for (const configDir of [".claude-personal", ".claude"]) {
    const projectsDir = path.join(base, configDir, "projects");
    let entradas;
    try {
      entradas = fs.readdirSync(projectsDir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entrada of entradas) {
      if (!entrada.isDirectory()) continue;
      const subPath = path.join(projectsDir, entrada.name);
      let arquivos;
      try {
        arquivos = fs.readdirSync(subPath);
      } catch {
        continue;
      }
      for (const arquivo of arquivos) {
        if (arquivo.endsWith(".jsonl")) achados.push(path.join(subPath, arquivo));
      }
    }
  }
  return achados;
}

// --------------------------------------------------------------------------
// mensagens humanas — carimbos do Luis, em hora LOCAL, ordenados
// --------------------------------------------------------------------------

function mensagensHumanas(caminho) {
  // Descarta retorno de ferramenta (`toolUseResult`), meta e resumo de
  // compactacao — os tres chegam como type "user" e nao provam presenca
  // humana nenhuma.
  let conteudo;
  try {
    conteudo = fs.readFileSync(caminho, "utf-8");
  } catch {
    return [];
  }
  const carimbos = [];
  for (const linha of conteudo.split("\n")) {
    if (!linha.trim()) continue;
    let d;
    try {
      d = JSON.parse(linha);
    } catch {
      continue;
    }
    if (!d || typeof d !== "object" || Array.isArray(d)) continue;
    if (d.type !== "user") continue;
    if (Object.prototype.hasOwnProperty.call(d, "toolUseResult") || d.isMeta || d.isCompactSummary) {
      continue;
    }
    const ts = d.timestamp;
    if (!ts) continue;
    const utc = new Date(ts);
    if (Number.isNaN(utc.getTime())) continue;
    carimbos.push([utc, caminho]);
  }
  return carimbos;
}

// --------------------------------------------------------------------------
// formatacao
// --------------------------------------------------------------------------

function pad2(n) {
  return String(n).padStart(2, "0");
}

function hoje() {
  const d = new Date();
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function diaLocal(d) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function hhmmRelogio(d) {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

// isoformat local, no mesmo formato de datetime.isoformat() do Python:
// omite a fracao de segundo quando ela e zero, senao imprime 6 digitos.
function isoformatLocal(d) {
  const y = d.getFullYear();
  const mo = pad2(d.getMonth() + 1);
  const da = pad2(d.getDate());
  const h = pad2(d.getHours());
  const mi = pad2(d.getMinutes());
  const s = pad2(d.getSeconds());
  const ms = d.getMilliseconds();
  const offMin = -d.getTimezoneOffset(); // minutos a leste de UTC
  const sinal = offMin >= 0 ? "+" : "-";
  const absOff = Math.abs(offMin);
  const offH = pad2(Math.floor(absOff / 60));
  const offM = pad2(absOff % 60);
  const frac = ms === 0 ? "" : `.${String(ms).padStart(3, "0")}000`;
  return `${y}-${mo}-${da}T${h}:${mi}:${s}${frac}${sinal}${offH}:${offM}`;
}

function hhmm(minutos) {
  const total = Math.round(minutos);
  const h = Math.floor(total / 60);
  const m = total % 60;
  return h ? `${h}h${pad2(m)}` : `${m} min`;
}

// --------------------------------------------------------------------------
// medicao
// --------------------------------------------------------------------------

// Devolve {efetiva, bruto, descartadas, primeiro, ultimo}.
function medir(carimbos, corteMin, descartar) {
  if (carimbos.length < 2) {
    return {
      efetiva: 0.0,
      bruto: 0.0,
      descartadas: [],
      primeiro: carimbos.length ? carimbos[0][0] : null,
      ultimo: null,
    };
  }
  const momentos = carimbos.map((c) => c[0]);
  let efetiva = 0.0;
  const descartadas = [];
  for (let i = 0; i < momentos.length - 1; i++) {
    const a = momentos[i];
    const b = momentos[i + 1];
    const gap = (b.getTime() - a.getTime()) / 1000 / 60;
    if (descartar && gap > corteMin) {
      descartadas.push([a, b, gap]);
    } else {
      efetiva += gap;
    }
  }
  const bruto = (momentos[momentos.length - 1].getTime() - momentos[0].getTime()) / 1000 / 60;
  return { efetiva, bruto, descartadas, primeiro: momentos[0], ultimo: momentos[momentos.length - 1] };
}

// --------------------------------------------------------------------------
// linha de comando
// --------------------------------------------------------------------------

function parseArgs(argv) {
  const args = {
    dia: null,
    transcript: null,
    corte: CORTE_PADRAO_MIN,
    semDescarte: false,
    json: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const tok = argv[i];
    const [flag, inlineValor] = tok.includes("=") && tok.startsWith("--")
      ? [tok.slice(0, tok.indexOf("=")), tok.slice(tok.indexOf("=") + 1)]
      : [tok, undefined];
    const proximo = () => (inlineValor !== undefined ? inlineValor : argv[++i]);
    switch (flag) {
      case "--dia":
        args.dia = proximo();
        break;
      case "--transcript":
        args.transcript = proximo();
        break;
      case "--corte":
        args.corte = parseFloat(proximo());
        break;
      case "--sem-descarte":
        args.semDescarte = true;
        break;
      case "--json":
        args.json = true;
        break;
      default:
        process.stderr.write(`argumento desconhecido: ${tok}\n`);
        process.exit(2);
    }
  }
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  let carimbos;
  let escopo;
  if (args.transcript) {
    carimbos = mensagensHumanas(args.transcript);
    escopo = path.basename(args.transcript);
  } else {
    const dia = args.dia || hoje();
    carimbos = [];
    for (const t of transcriptsDisponiveis()) {
      for (const c of mensagensHumanas(t)) {
        if (diaLocal(c[0]) === dia) carimbos.push(c);
      }
    }
    escopo = `dia ${dia}, todas as janelas`;
  }

  carimbos.sort((a, b) => a[0].getTime() - b[0].getTime());

  if (carimbos.length === 0) {
    if (args.json) {
      console.log(JSON.stringify({ escopo, mensagens: 0, erro: "nenhuma mensagem humana encontrada" }));
    } else {
      console.log(
        `${escopo}: nenhuma mensagem humana encontrada.\n` +
          "Sem medicao, a regra 8 PERGUNTA — nunca afirma jornada por outro sinal."
      );
    }
    return 2;
  }

  const { efetiva, bruto, descartadas, primeiro, ultimo } = medir(
    carimbos,
    args.corte,
    !args.semDescarte
  );

  if (args.json) {
    console.log(
      JSON.stringify({
        escopo,
        mensagens: carimbos.length,
        efetiva_min: Math.round(efetiva * 10) / 10,
        bruto_min: Math.round(bruto * 10) / 10,
        primeiro: isoformatLocal(primeiro),
        ultimo: isoformatLocal(ultimo),
        corte_min: args.corte,
        descartadas: descartadas.map(([a, b, g]) => ({
          de: isoformatLocal(a),
          ate: isoformatLocal(b),
          min: Math.round(g * 10) / 10,
        })),
      })
    );
    return 0;
  }

  console.log(`escopo ................. ${escopo}`);
  console.log(`mensagens do Luis ...... ${carimbos.length}`);
  console.log(`primeiro sinal humano .. ${hhmmRelogio(primeiro)} (local)`);
  console.log(`ultimo sinal humano .... ${hhmmRelogio(ultimo)} (local)`);
  console.log(`intervalo bruto ........ ${hhmm(bruto)}  <- ponta a ponta, NAO e jornada`);
  if (args.semDescarte) {
    console.log(`JORNADA (SEM DESCARTE) . ${hhmm(efetiva)}  <- MUTACAO ativa, numero invalido`);
  } else {
    console.log(`JORNADA EFETIVA ........ ${hhmm(efetiva)}`);
  }
  if (descartadas.length) {
    console.log(`\nlacunas descartadas (> ${Math.trunc(args.corte)} min): ${descartadas.length}`);
    for (const [a, b, g] of descartadas) {
      console.log(`  ${hhmmRelogio(a)} -> ${hhmmRelogio(b)}   ${hhmm(g)}`);
    }
  } else if (!args.semDescarte) {
    console.log(`\nnenhuma lacuna acima de ${Math.trunc(args.corte)} min.`);
  }
  return 0;
}

if (require.main === module) {
  process.exit(main());
}

module.exports = { transcriptsDisponiveis, mensagensHumanas, medir, hhmm, isoformatLocal, CORTE_PADRAO_MIN };
