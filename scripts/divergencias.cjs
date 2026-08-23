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
// devolve, mais o enunciado que deu origem a rodada e o id da linha. Dobra
// como ALLOWLIST tambem: o `abrir` nao tem campo opcional nenhum, entao todo
// nome fora desta lista e recusado (achado do `revisar`: sem isto, `origem` e
// `critico_viu_ancoragem` — que nao existem em schema nenhum — foram
// aceitos e gravados numa rodada real, so porque a denylist abaixo nao os
// citava por nome).
// D11: duas medidas de ancoragem, dois nomes. `critico_bateu_na_primeira_da_rodada`
// vem do critico (mede se ELE convergiu para a primeira ideia da rodada) e e
// exigido aqui, junto com `ideias` (as ideias cruas da fase 1) — sem elas uma
// linha fechada nao e auditavel depois. `bate_com_a_primeira_ideia` continua
// sendo so do `fechar`: mede se a escolha do USUARIO bate com o que ancorava
// a conversa, e so o usuario sabe qual era.
const CAMPOS_OBRIGATORIOS_ABRIR = [
  "id", "enunciado", "shortlist", "escolha_nao_obvia", "refutacao",
  "critico_bateu_na_primeira_da_rodada", "ideias",
];
// Campos que so o script carimba — quem manda pela entrada esta tentando
// forjar o que e do proprio registrador (mesmo motivo do ideias.cjs). Fica
// como mensagem de erro mais especifica; quem cair fora dela E fora da
// allowlist acima cai no erro generico de "campo nao aceito".
const CAMPOS_PROIBIDOS_NO_INPUT_ABRIR = [
  "status", "aberta_em", "fechada_em", "escolha", "bate_com_a_primeira_ideia",
];
// Allowlist da entrada do `fechar` — o achado do `revisar` que abriu a tarefa
// 7: sem isto, `Object.assign(obj, entrada)` deixava qualquer campo da
// entrada (inclusive `id` e `shortlist`, que sao do `abrir`) sobrescrever a
// linha existente em silencio. So estes dois sao aceitos.
const CAMPOS_PERMITIDOS_FECHAR = ["escolha", "bate_com_a_primeira_ideia"];
// Campos que so `fechar` grava, alem dos que `abrir` ja exige (acima). D12:
// o `fechar` passa a validar o REGISTRO COMPLETO depois da fusao, nao so o
// diff que chegou pela entrada — sem isto, uma linha anterior a D11 (sem
// `ideias`, sem `critico_bateu_na_primeira_da_rodada`, carregando o nome
// improvisado `critico_viu_ancoragem`) fechava do mesmo jeito, exit 0, sem o
// lastro que a D4 existe para garantir. Achado do segundo `revisar`.
const CAMPOS_OBRIGATORIOS_FECHADO = [
  "status", "aberta_em", "fechada_em", "escolha", "bate_com_a_primeira_ideia",
];
// D12: `origem` entra no schema do registro COMPLETO como campo OPCIONAL —
// proveniencia auditavel (de que rodada do grafo a linha veio), nao
// descartada so para satisfazer um schema mais estreito. Continua PROIBIDO
// na entrada de `abrir` (CAMPOS_OBRIGATORIOS_ABRIR nao o lista, e a allowlist
// generica de `validarEntradaAbrir` rejeita qualquer campo fora dela) — isto
// e so sobre o que o registro gravado pode conter.
const CAMPOS_OPCIONAIS_REGISTRO = ["origem"];
const CAMPOS_VALIDOS_REGISTRO = new Set([
  ...CAMPOS_OBRIGATORIOS_ABRIR,
  ...CAMPOS_OBRIGATORIOS_FECHADO,
  ...CAMPOS_OPCIONAIS_REGISTRO,
]);
// Allowlist da entrada do `reparar` (tarefa 10) — o que uma linha legada
// (anterior a D11) pode estar sem: as `ideias` cruas (nunca persistidas antes
// da D11, e sem elas uma linha fechada nao e auditavel) e o booleano do
// critico. So estes dois; ver cmdReparar para o porque do segundo so ser
// usado quando NAO ha `critico_viu_ancoragem` para renomear.
const CAMPOS_PERMITIDOS_REPARAR = ["ideias", "critico_bateu_na_primeira_da_rodada"];
const RE_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

// Trava de arquivo e rotina de leitura (sleepSync, Trava, comTrava, lerVivo,
// parseLinhas, indicePorId) saem daqui — eram copia quase byte a byte com
// scripts/ideias.cjs, e carregavam os mesmos dois defeitos (issue de
// 2026-08-23). Ver hooks/lib/trava-jsonl.cjs para o porque de cada um.
const TravaJsonl = require("../hooks/lib/trava-jsonl.cjs");
const { Erro, comTrava: comTravaComum, lerVivo: lerVivoComum, parseLinhas: parseLinhasComum, indicePorId: indicePorIdComum } = TravaJsonl;
const ORDEM_CANONICA = [
  "id", "enunciado", "shortlist", "escolha_nao_obvia", "refutacao",
  "critico_bateu_na_primeira_da_rodada", "ideias", "origem",
  "status", "aberta_em", "fechada_em", "escolha", "bate_com_a_primeira_ideia",
];

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
// trava e leitura — implementadas em hooks/lib/trava-jsonl.cjs (comum com o
// ideias.cjs). Aqui so wrappers que ja amarram TRAVA e ALVO, para nao mudar
// a assinatura que o resto deste arquivo chama.
// --------------------------------------------------------------------------

function comTrava(fn) {
  return comTravaComum(TRAVA, fn);
}

function lerVivo() {
  // Ao contrario do ideias.jsonl (semeado vazio pelo `setup.cjs`), este
  // arquivo ainda nao tem porta de instalacao — a primeira rodada de
  // `abrir` e quem o cria. Arquivo ausente conta como zero linhas, nao erro.
  return lerVivoComum(ALVO, { exigeExistir: false });
}

function parseLinhas(linhas) {
  return parseLinhasComum(linhas, ALVO);
}

function indicePorId(linhas, alvoId) {
  return indicePorIdComum(linhas, alvoId, ALVO);
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

const CAMPOS_BOOLEANOS = ["critico_bateu_na_primeira_da_rodada", "bate_com_a_primeira_ideia"];

function camposObrigatoriosAusentes(obj, campos) {
  // Mesmo crivo em dois lugares agora (validarEntradaAbrir e
  // validarRegistroFechado): os dois booleanos de ancoragem (D11) e `ideias`
  // (array nao vazio) nao passam no crivo generico `!obj[c]` — `false` e
  // falsy mas e resposta valida (foi exatamente isto que fez `fechar` com
  // `bate_com_a_primeira_ideia:false` ser lido como "ausente" na primeira
  // versao desta funcao), e `[]` e truthy mas nao e lista de ideias de
  // verdade. Extraido para as chamadas nunca divergirem (foi exatamente uma
  // divergencia de nome que motivou a D11).
  return campos.filter((c) => {
    if (CAMPOS_BOOLEANOS.includes(c)) return typeof obj[c] !== "boolean";
    if (c === "ideias") return !Array.isArray(obj[c]) || obj[c].length === 0;
    return !obj[c];
  });
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
  const naoPermitidos = Object.keys(obj).filter(
    (c) => !CAMPOS_OBRIGATORIOS_ABRIR.includes(c)
  );
  if (naoPermitidos.length) {
    throw new Erro(
      `campo(s) ${naoPermitidos.join(", ")} nao e(sao) aceito(s) na entrada de abrir — ` +
        `so ${CAMPOS_OBRIGATORIOS_ABRIR.join(", ")} sao permitidos.`
    );
  }
  const faltando = camposObrigatoriosAusentes(obj, CAMPOS_OBRIGATORIOS_ABRIR);
  if (faltando.length) {
    throw new Erro(`campo(s) obrigatorio(s) faltando ou vazio(s): ${faltando.join(", ")}`);
  }
  if (!RE_ID.test(obj.id)) {
    throw new Erro(`id '${obj.id}' nao e kebab-case ([a-z0-9] separado por hifen)`);
  }
}

// D12 (tarefa 9) — o `fechar` valida o REGISTRO COMPLETO depois da fusao, nao
// so o diff que a entrada trouxe. Ate aqui `cmdFechar` lia a linha existente
// com JSON.parse sem conferir nada, e `serializar` tinha um lace de passagem
// livre que gravava qualquer campo ja presente no objeto — uma linha anterior
// a D11 (sem `ideias`, sem `critico_bateu_na_primeira_da_rodada`, carregando
// `critico_viu_ancoragem`) fechava do mesmo jeito, exit 0, sem o lastro que a
// D4 existe para garantir. Chamada em cmdFechar DEPOIS da fusao e ANTES de
// `gravar` — se lancar, a linha nunca chega a ser reescrita.
function validarRegistroFechado(obj) {
  const problemas = [];
  const foraDoSchema = Object.keys(obj).filter((k) => !CAMPOS_VALIDOS_REGISTRO.has(k));
  if (foraDoSchema.length) {
    problemas.push(`campo(s) fora do schema: ${foraDoSchema.join(", ")}`);
  }
  const faltando = camposObrigatoriosAusentes(
    obj,
    CAMPOS_OBRIGATORIOS_ABRIR.concat(CAMPOS_OBRIGATORIOS_FECHADO)
  );
  if (faltando.length) {
    problemas.push(`campo(s) obrigatorio(s) ausente(s) ou invalido(s): ${faltando.join(", ")}`);
  }
  if (problemas.length) {
    throw new Erro(
      `'${obj.id}' nao fecha — registro nao passa no schema completo: ${problemas.join("; ")}. ` +
        "Rode 'node scripts/divergencias.cjs reparar --id <id>' para trazer a linha ao schema " +
        "corrente antes de fechar."
    );
  }
}

// Allowlist da entrada do `reparar` (tarefa 10) — mesma disciplina do abrir/
// fechar: so os dois campos que uma linha legada pode estar sem.
function validarEntradaReparar(entrada) {
  if (typeof entrada !== "object" || entrada === null || Array.isArray(entrada)) {
    throw new Erro("o JSON da entrada precisa ser um objeto");
  }
  const naoPermitidos = Object.keys(entrada).filter(
    (c) => !CAMPOS_PERMITIDOS_REPARAR.includes(c)
  );
  if (naoPermitidos.length) {
    throw new Erro(
      `campo(s) ${naoPermitidos.join(", ")} nao e(sao) aceito(s) na entrada de reparar — ` +
        `so ${CAMPOS_PERMITIDOS_REPARAR.join(", ")} sao permitidos.`
    );
  }
  if (!Array.isArray(entrada.ideias) || entrada.ideias.length === 0) {
    throw new Erro('reparar exige {"ideias": [...]} nao vazio na entrada');
  }
  if (typeof entrada.critico_bateu_na_primeira_da_rodada !== "boolean") {
    throw new Erro(
      'reparar exige {"critico_bateu_na_primeira_da_rodada": true|false} na entrada'
    );
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
  const naoPermitidos = Object.keys(entrada).filter(
    (c) => !CAMPOS_PERMITIDOS_FECHAR.includes(c)
  );
  if (naoPermitidos.length) {
    throw new Erro(
      `campo(s) ${naoPermitidos.join(", ")} nao e(sao) aceito(s) na entrada de fechar — ` +
        `so ${CAMPOS_PERMITIDOS_FECHAR.join(", ")} sao permitidos. Quem sobrescreve id, ` +
        "shortlist e o resto da rodada e o `abrir`, nao o `fechar`."
    );
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
    validarRegistroFechado(obj);
    const depois = antes.slice();
    depois[i] = serializar(obj);
    console.log(`fechando '${args.id}' (linha ${i + 1})`);
    gravar(antes, depois, new Set([i]), "fechar");
  });
}

// Tarefa 10 (D12) — subcomando de reparo para linha legada. Com o `fechar`
// estrito da tarefa 9, uma linha anterior a D11 fica IMPOSSIVEL de fechar —
// e escrita a mao no .jsonl e proibida neste repo desde os dois appends
// quebrados de 2026-08-08. `reparar` recebe por stdin o que uma linha legada
// nao tem como recuperar sozinha (`ideias`, nunca persistidas antes da D11) e
// migra o campo cujo nome so estava errado.
//
// Nome escolhido: `reparar`, o mesmo do irmao `ideias.cjs` — mesma operacao
// (trazer uma linha antiga ao schema corrente), mesmo verbo.
function cmdReparar(args) {
  const entrada = lerStdin();
  validarEntradaReparar(entrada);
  comTrava(() => {
    const antes = lerVivo();
    const i = indicePorId(antes, args.id);
    const obj = JSON.parse(antes[i]);

    if (!Array.isArray(obj.ideias) || obj.ideias.length === 0) {
      obj.ideias = entrada.ideias;
    }

    // D11/D12: `critico_viu_ancoragem` foi nome improvisado ANTES da D11 —
    // mesmo dado, nome errado, nao um campo a perder. RENOMEAR preserva o
    // VALOR ORIGINAL; nunca descartar o campo velho e criar o novo com um
    // valor vindo de outro lugar (isso apagaria o dado real e o trocaria por
    // um palpite). O booleano da entrada so e usado quando a linha NAO tem
    // nem o nome velho nem o novo — aí nao ha historico nenhum a preservar.
    if (Object.prototype.hasOwnProperty.call(obj, "critico_viu_ancoragem")) {
      // MESMA GUARDA da migracao de `ideias` logo acima, e ela faltava aqui:
      // o nome velho so vence quando o novo ainda NAO tem valor valido. Sem
      // isso, uma linha que carregasse os dois nomes perderia o dado bom para
      // o residual — reproduzido na terceira revisao, com `true` correto sendo
      // sobrescrito por um `false` que so restou de uma migracao pela metade.
      // O `delete` fica fora do `if`: o campo velho sai sempre, tendo vencido
      // ou nao, porque ele nao existe no schema corrente de jeito nenhum.
      if (typeof obj.critico_bateu_na_primeira_da_rodada !== "boolean") {
        obj.critico_bateu_na_primeira_da_rodada = obj.critico_viu_ancoragem;
      }
      delete obj.critico_viu_ancoragem;
    } else if (typeof obj.critico_bateu_na_primeira_da_rodada !== "boolean") {
      obj.critico_bateu_na_primeira_da_rodada = entrada.critico_bateu_na_primeira_da_rodada;
    }

    // O reparo promete trazer a linha ao schema CORRENTE — confere antes de
    // gravar, para nunca escrever uma linha que o proprio reparo deixou pela
    // metade (mesmo schema que validarRegistroFechado usa para a linha
    // completa, exceto pelos campos que so `fechar` grava).
    const foraDoSchema = Object.keys(obj).filter((k) => !CAMPOS_VALIDOS_REGISTRO.has(k));
    if (foraDoSchema.length) {
      throw new Erro(`reparo nao cobriu tudo — ainda fora do schema: ${foraDoSchema.join(", ")}`);
    }
    const faltando = camposObrigatoriosAusentes(obj, CAMPOS_OBRIGATORIOS_ABRIR);
    if (faltando.length) {
      throw new Erro(
        `reparo nao cobriu tudo — ainda ausente(s) ou invalido(s): ${faltando.join(", ")}`
      );
    }

    const depois = antes.slice();
    depois[i] = serializar(obj);
    console.log(`reparando '${args.id}' (linha ${i + 1})`);
    gravar(antes, depois, new Set([i]), "reparar");
  });
}

// --------------------------------------------------------------------------
// argumentos de linha de comando
// --------------------------------------------------------------------------

const SUBCOMANDOS = {
  abrir: { requerId: false, fn: cmdAbrir },
  fechar: { requerId: true, fn: cmdFechar },
  reparar: { requerId: true, fn: cmdReparar },
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
