#!/usr/bin/env node
"use strict";
/* Porta única do ledger ferramentas.jsonl — escrita segura de um catálogo
 * de ferramentas descobertas. Nenhuma escrita sem trava; leitura sempre do
 * disco; backup antes de qualquer alteração; contagem e validação ao fim.
 *
 * Garantias preservadas do ideias.cjs:
 *   1. Trava de arquivo (ferramentas.lock)
 *   2. Releitura do arquivo VIVO no instante da escrita
 *   3. Backup antes de qualquer escrita
 *   4. Escrita em temporário + rename atomico
 *   5. Newline final garantido, LF sempre
 *   6. Contagem conferida por operacao
 *   7. Linhas nao-alvo conferidas byte a byte apos a escrita
 *   8. Data carimbada aqui, do relogio local (nunca UTC)
 *
 * Decisões do design:
 *   D2 — Sem campo de negativa. Ausência lê-se como desconhecido, nunca ausente.
 *   D5 — Entrada: nome + receita + descoberta + data.
 *   D11 — Receita entra só pelo comando explícito.
 *   D13 — Uma linha por ferramenta, reescrita (não append).
 */

const fs = require("fs");
const path = require("path");

// Raiz segue a mesma cadeia do ideias.cjs
const RAIZ = (() => {
  const local = path.resolve(__dirname, "..");
  try {
    const { resolverRaiz } = require("../hooks/lib/raiz.cjs");
    const r = resolverRaiz({ plugin: local });
    return r.raiz || local;
  } catch {
    return local;
  }
})();

const ALVO = path.join(RAIZ, "ferramentas.jsonl");
const DIR_BACKUP = path.join(RAIZ, ".ferramentas-backups");
const TRAVA = path.join(RAIZ, ".ferramentas.lock");

// Campos proibidos na entrada (D2 — sem negativa)
const CAMPOS_PROIBIDOS = [
  "ausente", "faltando", "encontrado", "status", "nao_encontrado",
  "nao-encontrado", "existe", "presente", "disponivel"
];

class Erro extends Error {
  constructor(message) {
    super(message);
    this.name = "Erro";
  }
}

// --------- Utilidades de data ---------
function pad(n, len = 2) {
  return String(n).padStart(len, "0");
}

function hoje() {
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

// --------- Trava e leitura ---------
function sleepSync(ms) {
  const fim = Date.now() + ms;
  while (Date.now() < fim) {
    // spin
  }
}

function comTrava(fn) {
  const maxTentativas = 20;
  for (let i = 0; i < maxTentativas; i++) {
    try {
      fs.writeFileSync(TRAVA, String(process.pid), { flag: "wx" });
      break;
    } catch {
      if (i === maxTentativas - 1) {
        throw new Erro(`nao consegui trava apos ${maxTentativas} tentativas`);
      }
      sleepSync(50 + Math.random() * 50);
    }
  }
  try {
    return fn();
  } finally {
    try {
      fs.unlinkSync(TRAVA);
    } catch {
      // trava de outro processo?
    }
  }
}

function lerVivo() {
  try {
    const conteudo = fs.readFileSync(ALVO, "utf8");
    return conteudo.split("\n").filter((l) => l.trim().length > 0);
  } catch (e) {
    if (e.code === "ENOENT") {
      return [];
    }
    throw new Erro(`erro ao ler ${ALVO}: ${e.message}`);
  }
}

function parseLinhas(linhas) {
  const objs = [];
  for (let i = 0; i < linhas.length; i++) {
    try {
      objs.push(JSON.parse(linhas[i]));
    } catch (e) {
      throw new Erro(`linha ${i + 1} nao e JSON valido: ${e.message}`);
    }
  }
  return objs;
}

// --------- Validação ---------
function validarEntrada(obj) {
  if (typeof obj !== "object" || obj === null || Array.isArray(obj)) {
    throw new Erro("a entrada precisa ser um objeto");
  }

  // D2 — Detectar campos de negativa
  const proibidos = CAMPOS_PROIBIDOS.filter((c) =>
    Object.prototype.hasOwnProperty.call(obj, c)
  );
  if (proibidos.length) {
    throw new Erro(
      `campo(s) de negativa nao sao permitidos: ${proibidos.join(", ")}`
    );
  }

  if (!obj.nome || typeof obj.nome !== "string") {
    throw new Erro("campo 'nome' obrigatorio e deve ser string");
  }
  // A `receita` e OPCIONAL, e isso e decisao, nao folga.
  //
  // A D5 diz que a entrada util e nome + receita + como descoberto + data, e a
  // D11 diz que o hook de consulta grava SEM receita — inferir a invocacao a
  // partir de uma sonda e adivinhacao. Com o campo obrigatorio, as duas nao
  // cabem juntas, e a saida que sobra e a pior: em 2026-08-25 o hook foi
  // forcado a inventar uma, e gravou a saida crua do `where` — dois caminhos
  // concatenados num campo so, com um CR no meio. Receita inventada custa
  // mais que receita ausente.
  //
  // Entrada sem receita e fato positivo legitimo: "existe, achado assim, nesta
  // data". A receita entra depois, pelo `registrar` explicito, quando alguem
  // souber a invocacao de verdade. O que continua proibido e mentir sobre ela.
  if (obj.receita !== undefined && typeof obj.receita !== "string") {
    throw new Erro("campo 'receita', quando presente, deve ser string");
  }
  if (typeof obj.receita === "string" && /[\r\n]/.test(obj.receita)) {
    throw new Erro("campo 'receita' nao pode ter quebra de linha — saida crua de comando nao e receita");
  }
  if (!obj.descoberto || typeof obj.descoberto !== "string") {
    throw new Erro("campo 'descoberto' obrigatorio e deve ser string");
  }
}

function serializar(obj) {
  const ordenado = { nome: obj.nome };
  if (obj.receita !== undefined) ordenado.receita = obj.receita;
  ordenado.descoberto = obj.descoberto;
  ordenado.data = obj.data;
  const linha = JSON.stringify(ordenado);
  JSON.parse(linha); // validar JSON
  return linha;
}

// --------- Gravação verificada ---------
function gravar(linhasAntes, linhasDepois, rotulo) {
  fs.mkdirSync(DIR_BACKUP, { recursive: true });
  const carimbo = carimboAgora();
  const backup = path.join(DIR_BACKUP, `ferramentas-${carimbo}.jsonl`);

  if (fs.existsSync(backup)) {
    throw new Erro(`backup ${path.basename(backup)} ja existe`);
  }

  if (fs.existsSync(ALVO)) {
    fs.copyFileSync(ALVO, backup);
  }

  const tmp = ALVO.replace(/\.jsonl$/, ".jsonl.tmp");
  fs.writeFileSync(tmp, linhasDepois.join("\n") + "\n", "utf8");
  fs.renameSync(tmp, ALVO);

  // Prova, relendo do disco
  const relidas = lerVivo();
  const problemas = [];

  if (relidas.length !== linhasDepois.length) {
    problemas.push(
      `contagem no disco ${relidas.length} != esperada ${linhasDepois.length}`
    );
  }

  try {
    parseLinhas(relidas);
  } catch (e) {
    problemas.push(e.message);
  }

  console.log(`  contagem: ${linhasAntes.length} -> ${relidas.length}`);
  console.log(
    `  todas as ${relidas.length} linhas sao JSON valido: ${
      problemas.length === 0 ? "sim" : "NAO"
    }`
  );
  console.log(`  backup: ${path.relative(RAIZ, backup)}`);

  if (problemas.length) {
    if (fs.existsSync(ALVO) && fs.existsSync(backup)) {
      fs.copyFileSync(backup, ALVO);
    }
    throw new Erro(`${rotulo} REVERTIDO — ${problemas.join("; ")}`);
  }

  console.log(`  ${rotulo}: ok`);
}

// --------- Entrada JSON de stdin ---------
function lerStdin() {
  let bruto;
  try {
    bruto = fs.readFileSync(0, "utf8").trim();
  } catch (e) {
    bruto = "";
  }
  if (!bruto) {
    throw new Erro("nada na entrada padrao — mande o JSON por stdin");
  }
  try {
    return JSON.parse(bruto);
  } catch (e) {
    throw new Erro(`entrada nao e JSON valido: ${e.message}`);
  }
}

// --------- Comandos ---------
function cmdRegistrar(args) {
  let entrada;

  // Se --json foi passado, ler JSON de stdin (para teste com campo de negativa)
  if (args.json) {
    entrada = lerStdin();
    entrada.data = entrada.data || hoje();
  } else {
    if (!args.nome || !args.descoberto) {
      throw new Erro(
        "registrar exige: node scripts/ferramentas.cjs registrar <nome> [receita] <descoberta>"
      );
    }
    entrada = { nome: args.nome, descoberto: args.descoberto, data: hoje() };
    if (args.receita) entrada.receita = args.receita;
  }

  validarEntrada(entrada);

  comTrava(() => {
    const antes = lerVivo();
    const objs = parseLinhas(antes);

    // D13 — Se já existe, reescrever (não append)
    let indice = objs.findIndex((o) => o.nome === entrada.nome);
    let isNova = indice === -1;

    const depois = antes.slice();
    const linha = serializar(entrada);

    if (isNova) {
      depois.push(linha);
      indice = depois.length - 1;
    } else {
      depois[indice] = linha;
    }

    console.log(
      `${isNova ? "registrando" : "atualizando"} '${entrada.nome}'`
    );
    gravar(antes, depois, "registrar");
  });
}

function cmdConsultar(args) {
  if (!args.nome) {
    throw new Erro(
      "consultar exige: node scripts/ferramentas.cjs consultar <nome>"
    );
  }

  const linhas = lerVivo();
  const objs = parseLinhas(linhas);
  const encontrado = objs.find((o) => o.nome === args.nome);

  if (!encontrado) {
    // D2 — Nunca menciona "ausente", sempre "desconhecido"
    console.log("desconhecido");
    process.exit(0);
  }

  // Sem receita, a entrada ainda e um fato: existe e foi achado. Dizer isso e
  // diferente de dizer "desconhecido" — e quem le precisa distinguir os dois.
  console.log(encontrado.receita || `conhecido, sem receita (descoberto: ${encontrado.descoberto})`);
  process.exit(0);
}

// --------- Parser de argumentos ---------
function parseArgs(argv) {
  if (argv.length === 0) {
    throw new Erro("subcomando obrigatorio (registrar|consultar)");
  }

  const cmd = argv[0];
  const args = { cmd, json: false };
  let i = 1;

  // Verificar flags globais
  while (i < argv.length && argv[i].startsWith("--")) {
    if (argv[i] === "--json") {
      args.json = true;
      i++;
    } else {
      break;
    }
  }

  if (cmd === "registrar") {
    if (!args.json) {
      // A `receita` e opcional (D5), entao a forma posicional e ambigua por
      // contagem: com 2 argumentos, o segundo e `descoberto`, nao `receita`.
      // Antes desta correcao o parser cravava `receita = argv[i+1]` sempre, e
      // `registrar <nome> <descoberto>` recusava com "descoberto obrigatorio" —
      // mensagem que aponta o campo errado e manda o usuario procurar onde nao
      // esta. Achado da revisao de 2026-08-25.
      const posicionais = argv.slice(i).filter((a) => !a.startsWith("--"));
      args.nome = posicionais[0];
      if (posicionais.length >= 3) {
        args.receita = posicionais[1];
        args.descoberto = posicionais[2];
      } else {
        args.descoberto = posicionais[1];
      }
    }
  } else if (cmd === "consultar") {
    args.nome = argv[i];
  } else {
    throw new Erro(`subcomando desconhecido: ${cmd}`);
  }

  return args;
}

// --------- Main ---------
function main() {
  const args = parseArgs(process.argv.slice(2));

  try {
    if (args.cmd === "registrar") {
      cmdRegistrar(args);
    } else if (args.cmd === "consultar") {
      cmdConsultar(args);
    }
  } catch (e) {
    if (e instanceof Erro) {
      process.stderr.write(`erro: ${e.message}\n`);
      process.exit(2);
    }
    throw e;
  }

  process.exit(0);
}

main();
