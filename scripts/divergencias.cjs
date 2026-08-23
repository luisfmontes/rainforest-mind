#!/usr/bin/env node
"use strict";
/* Registrador de rodadas da skill `divergir` — mesmo desenho de scripts/ideias.cjs,
 * aplicado a divergencias.jsonl. Ver ideias.cjs para o porque de cada garantia; aqui
 * so o resumo:
 *   1. Trava de arquivo entre sessoes paralelas
 *   2. Releitura do arquivo VIVO no instante da escrita
 *   3. Backup antes de qualquer escrita (inclusive quando o arquivo ainda nao existe)
 *   4. Escrita em temporario + rename atomico
 *   5. Newline final garantido, LF sempre
 *   6. Contagem conferida por operacao
 *   7. Linhas nao-alvo conferidas byte a byte apos a escrita
 *   8. Data carimbada aqui, do relogio local (nunca UTC, nunca do input)
 *
 * Por que existe: a SKILL.md do `divergir` define o proprio teste de falsificacao —
 * "rode em 3 decisoes reais e guarde a escolha; se a escolha final for sempre a que
 * voce faria sem divergir, a skill nao paga o custo e sai." Ate aqui nada guardava
 * nada, entao esse teste nunca pode rodar de verdade. Este script guarda.
 */

const fs = require("fs");
const path = require("path");

// Mesma cadeia de resolucao de raiz que o ideias.cjs usa (hooks/lib/raiz.cjs):
// RFM_ROOT > <projeto>/.rainforest > ~/.rainforest > raiz do plugin. O arquivo
// vive AO LADO do ideias.jsonl e do FOCO.md, na mesma pasta de dados — sem
// variavel de ambiente propria. Se a lib nao estiver junto (script copiado
// sozinho para uma caixa de areia, por exemplo), cai no comportamento antigo —
// a pasta acima do script.
const RAIZ = (() => {
  const local = path.resolve(__dirname, "..");
  try {
    const { resolverRaiz } = require("../hooks/lib/raiz.cjs");
    return resolverRaiz({ plugin: local }).raiz || local;
  } catch {
    return local;
  }
})();
const ALVO = path.join(RAIZ, "divergencias.jsonl");
const DIR_BACKUP = path.join(RAIZ, ".divergencias-backups");
const TRAVA = path.join(RAIZ, ".divergencias.lock");

// Campos que o `abrir` exige na entrada — o que o critico da fase 2 do grafo
// devolve, mais o enunciado que deu origem a rodada e o id da linha.
const CAMPOS_OBRIGATORIOS_ABRIR = ["id", "enunciado", "shortlist", "escolha_nao_obvia", "refutacao"];
// Campos que so o script carimba — quem manda pela entrada esta tentando
// forjar o que e do proprio registrador (mesmo motivo do ideias.cjs).
const CAMPOS_PROIBIDOS_NO_INPUT_ABRIR = [
  "status", "aberta_em", "fechada_em", "escolha", "bate_com_a_primeira_ideia",
];
const RE_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const ORDEM_CANONICA = [
  "id", "enunciado", "shortlist", "escolha_nao_obvia", "refutacao",
  "status", "aberta_em", "fechada_em", "escolha", "bate_com_a_primeira_ideia",
];

class Erro extends Error {}

// --------------------------------------------------------------------------
// data — sempre local, nunca UTC
// --------------------------------------------------------------------------

function pad(n, len = 2) {
  return String(n).padStart(len, "0");
}

function hoje() {
  // Data do relogio LOCAL. Nunca toISOString() (UTC) — mesmo cuidado do
  // ideias.cjs, pelo mesmo motivo (incidente 2026-08-08).
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
  // Ao contrario do ideias.jsonl (semeado vazio pelo `setup.cjs`), este
  // arquivo ainda nao tem porta de instalacao — a primeira rodada de
  // `abrir` e quem o cria. Arquivo ausente conta como zero linhas, nao erro.
  if (!fs.existsSync(ALVO)) {
    return [];
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
  fs.mkdirSync(RAIZ, { recursive: true });
  fs.mkdirSync(DIR_BACKUP, { recursive: true });
  const existiaAntes = fs.existsSync(ALVO);
  const carimbo = carimboAgora();
  const backup = path.join(DIR_BACKUP, `divergencias-${carimbo}.jsonl`);
  if (fs.existsSync(backup)) {
    throw new Erro(`backup ${path.basename(backup)} ja existe — abortando antes de escrever`);
  }
  if (existiaAntes) {
    fs.copyFileSync(ALVO, backup);
  } else {
    // Primeira escrita: nao ha arquivo para copiar. O backup vazio e so o
    // registro de que a linha de base era "nao existe" — se a gravacao for
    // revertida, o arquivo tem que voltar a nao existir, nao a ficar vazio.
    fs.writeFileSync(backup, "", "utf8");
  }

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
    if (existiaAntes) {
      fs.copyFileSync(backup, ALVO);
    } else {
      try {
        fs.unlinkSync(ALVO);
      } catch (e) {
        /* ja sumiu */
      }
    }
    throw new Erro(`${rotulo} REVERTIDO — ${problemas.join("; ")}`);
  }
  console.log(`  ${rotulo}: ok`);
}

// --------------------------------------------------------------------------
// entrada
// --------------------------------------------------------------------------

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

function validarEntradaAbrir(obj) {
  if (typeof obj !== "object" || obj === null || Array.isArray(obj)) {
    throw new Erro("o JSON da entrada precisa ser um objeto");
  }
  const proibidos = CAMPOS_PROIBIDOS_NO_INPUT_ABRIR.filter((c) =>
    Object.prototype.hasOwnProperty.call(obj, c)
  );
  if (proibidos.length) {
    throw new Erro(
      `campo(s) ${proibidos.join(", ")} nao vem da entrada de abrir — quem carimba/fecha ` +
        "e o script, no momento certo. Remova e rode de novo."
    );
  }
  const faltando = CAMPOS_OBRIGATORIOS_ABRIR.filter((c) => !obj[c]);
  if (faltando.length) {
    throw new Erro(`campo(s) obrigatorio(s) faltando ou vazio(s): ${faltando.join(", ")}`);
  }
  if (!RE_ID.test(obj.id)) {
    throw new Erro(`id '${obj.id}' nao e kebab-case ([a-z0-9] separado por hifen)`);
  }
}

// --------------------------------------------------------------------------
// comandos
// --------------------------------------------------------------------------

function cmdAbrir(_args) {
  const novo = lerStdin();
  validarEntradaAbrir(novo);
  comTrava(() => {
    const antes = lerVivo();
    if (parseLinhas(antes).some((o) => o.id === novo.id)) {
      throw new Erro(`ja existe rodada com id '${novo.id}' — escolha outro`);
    }
    novo.status = "aberta";
    novo.aberta_em = hoje();
    const depois = antes.concat([serializar(novo)]);
    console.log(`abrindo '${novo.id}'`);
    gravar(antes, depois, new Set([antes.length]), "abrir");
  });
}

function cmdFechar(args) {
  const entrada = lerStdin();
  if (typeof entrada !== "object" || entrada === null || Array.isArray(entrada)) {
    throw new Erro("o JSON da entrada precisa ser um objeto");
  }
  if (typeof entrada.escolha !== "string" || !entrada.escolha.trim()) {
    throw new Erro(
      'fechar exige {"escolha": "..."} na entrada — a escolha que o usuario de fato fez'
    );
  }
  if (typeof entrada.bate_com_a_primeira_ideia !== "boolean") {
    throw new Erro(
      'fechar exige {"bate_com_a_primeira_ideia": true|false} na entrada'
    );
  }
  comTrava(() => {
    const antes = lerVivo();
    const i = indicePorId(antes, args.id);
    const obj = JSON.parse(antes[i]);
    if (obj.status === "fechado") {
      throw new Erro(`'${args.id}' ja esta fechado em ${obj.fechada_em}`);
    }
    Object.assign(obj, entrada);
    obj.status = "fechado";
    obj.fechada_em = hoje();
    const depois = antes.slice();
    depois[i] = serializar(obj);
    console.log(`fechando '${args.id}' (linha ${i + 1})`);
    gravar(antes, depois, new Set([i]), "fechar");
  });
}

// --------------------------------------------------------------------------
// argumentos de linha de comando
// --------------------------------------------------------------------------

const SUBCOMANDOS = {
  abrir: { requerId: false, fn: cmdAbrir },
  fechar: { requerId: true, fn: cmdFechar },
};

function erroArgs(msg) {
  process.stderr.write(`divergencias.cjs: erro: ${msg}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  if (argv.length === 0) {
    erroArgs("subcomando obrigatorio (" + Object.keys(SUBCOMANDOS).join("|") + ")");
  }
  const cmd = argv[0];
  const spec = SUBCOMANDOS[cmd];
  if (!spec) erroArgs(`subcomando desconhecido: ${cmd}`);

  const args = { cmd, id: null };
  let i = 1;
  while (i < argv.length) {
    const tok = argv[i];
    if (tok === "--id") {
      const val = argv[i + 1];
      if (val === undefined) erroArgs("--id exige valor");
      args.id = val;
      i += 2;
      continue;
    }
    erroArgs(`argumento inesperado: ${tok}`);
  }
  if (spec.requerId && !args.id) erroArgs("opcao obrigatoria faltando: --id");

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
