#!/usr/bin/env node
"use strict";
/* Ponte para outro agente — gera o CLAUDE.md (Claude Code SEM o plugin), o
 * AGENTS.md (Codex) ou o GEMINI.md (Gemini CLI) a partir da MESMA fonte que o hook
 * de abertura injeta no Claude Code.
 *
 * QUEM ESCOLHE O ALVO E O /setup, nao este comando: as chaves `ponte-*` dizem o que
 * esta maquina usa, e sao elas que valem sem `--agente`. A divisao tem razao — qual
 * agente o usuario usa e CONFIGURACAO; qual repositorio recebe o arquivo NAO e, e
 * continua sendo alvo explicito com ensaio, porque o gerado vai ser commitado no
 * repo de outra pessoa.
 *
 * POR QUE GERADO, E NUNCA ESCRITO A MAO. As regras moram em
 * `skills/rainforest-mind/SKILL.md`. Um AGENTS.md escrito a mao seria uma segunda
 * cópia das regras, mantida em sincronia por disciplina — e existe um incidente
 * datado exatamente disso na maquina do dono deste plugin: duas CLAUDE.md de
 * escopo usuario, uma por config dir, sincronizadas a mao. Em 2026-08-10 uma foi
 * editada, a outra divergiu em silencio, e metade do setup passou a valer o
 * contrario da outra metade. Regra duplicada nao fica errada com aviso: fica
 * errada calada. Aqui a duplicata e DERIVADA, e o comando que a gera esta escrito
 * dentro dela.
 *
 * O QUE ATRAVESSA E O QUE NAO. Isto e a parte honesta da ponte, e ela vai dentro
 * do arquivo gerado tambem — prometer a trava que nao existe seria pior que nao
 * ter ponte:
 *
 *   atravessa (e MECANISMO, porque e comando de shell com exit code):
 *     scripts/estado.cjs exigir ......... o gate do fluxo, exit 2
 *     scripts/conferir-entrega.cjs ...... a checagem da regra 12, exit 1
 *     scripts/conferir-publicacao.cjs .... anonimizacao antes de publicar, exit 2
 *     scripts/ideias.cjs ................ porta unica de escrita do ideias.jsonl
 *     scripts/foco.cjs / saude.cjs / semear.cjs / limpar-branches.cjs
 *
 *   NAO atravessa (e API do Claude Code, e nao tem equivalente):
 *     hooks/gate-worktree.cjs e gate-staging-total.cjs (PreToolUse)
 *     a injecao de SessionStart (o arquivo gerado e o substituto dela)
 *     os slash commands e os subagentes nomeados
 *
 * Uso:
 *   node scripts/ponte.cjs --alvo <dir>                    # ensaio: mostra e nao grava
 *   node scripts/ponte.cjs --alvo <dir> --aplicar
 *   node scripts/ponte.cjs --alvo <dir> --agente codex --aplicar
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const CODIGO_ROOT = path.resolve(__dirname, "..");
const CAMINHO_SKILL = path.join(CODIGO_ROOT, "skills", "rainforest-mind", "SKILL.md");

const FIM = "<!-- rainforest-mind:fim -->";

/** Hash curto (16 primeiros caracteres) do SKILL.md para deteccao de edicao manual. */
function hashSkillMd() {
  try {
    const conteudo = fs.readFileSync(CAMINHO_SKILL, "utf8");
    return crypto.createHash("sha256").update(conteudo).digest("hex").slice(0, 16);
  } catch {
    return null;
  }
}

function inicioComHash(hash) {
  if (!hash) return "<!-- rainforest-mind:inicio — GERADO por scripts/ponte.cjs, nao edite a mao -->";
  return `<!-- rainforest-mind:inicio — GERADO por scripts/ponte.cjs, nao edite a mao — hash:${hash} -->`;
}

const AGENTES = {
  // `claude` e o terceiro alvo, e nao e redundante: quem usa Claude Code SEM o
  // plugin instalado nao tem regra nenhuma. E o caminho de quem vai receber o
  // convite antes de instalar, e o unico caminho num repo compartilhado onde nao da
  // para exigir plugin de ninguem.
  claude: {
    arquivo: "CLAUDE.md",
    nome: "Claude Code (sem o plugin)",
    comoLe: "O Claude Code le o `CLAUDE.md` da raiz do repositorio em toda sessao.",
    semTrava:
      "As duas travas do rainforest-mind (agente fora de worktree isolado, `git add -A`) " +
      "sao hooks `PreToolUse` do PLUGIN. Este arquivo entrega as regras, nao os hooks: " +
      "sem o plugin instalado elas sao combinado, nao trava. Quem quiser as travas " +
      "instala o plugin — ai este arquivo fica redundante e pode sair.",
  },
  codex: {
    arquivo: "AGENTS.md",
    nome: "Codex",
    comoLe: "O Codex le o `AGENTS.md` da raiz do repositorio em toda sessao.",
    semTrava:
      "Duas travas do rainforest-mind rodam fora do modelo no Claude Code, como hook " +
      "com exit code: a que barra agente editando fora de worktree isolado, e a que " +
      "barra `git add -A`. Elas usam o `PreToolUse`, que **nao existe** neste host. " +
      "Aqui elas sao texto — ou seja, argumentaveis. Trate-as como combinado.",
  },
  gemini: {
    arquivo: "GEMINI.md",
    nome: "Gemini CLI",
    comoLe: "O Gemini CLI le o `GEMINI.md` da raiz do repositorio em toda sessao.",
    semTrava:
      "Duas travas do rainforest-mind rodam fora do modelo no Claude Code, como hook " +
      "com exit code: a que barra agente editando fora de worktree isolado, e a que " +
      "barra `git add -A`. Elas usam o `PreToolUse`, que **nao existe** neste host. " +
      "Aqui elas sao texto — ou seja, argumentaveis. Trate-as como combinado.",
  },
};

/**
 * Quais alvos este install DECLAROU no `/setup` (chaves `ponte-*`).
 *
 * O default do comando saiu de "todos" para "o que o usuario ligou": gerar arquivo
 * em repositorio de terceiro nunca e padrao, e "nada declarado" nao pode virar
 * "gera os tres". `--agente` continua valendo como escolha pontual.
 */
function declarados() {
  let valores;
  try {
    valores = require("../hooks/lib/config.cjs").resolverConfig().valores;
  } catch {
    return [];
  }
  return Object.keys(AGENTES).filter((k) => valores[`ponte-${k}`] === true);
}

function arg(nome, argv = process.argv) {
  const i = argv.indexOf(`--${nome}`);
  return i >= 0 ? argv[i + 1] || null : null;
}
const tem = (nome, argv = process.argv) => argv.includes(`--${nome}`);

function erro(msg) {
  process.stderr.write(`ponte.cjs: erro: ${msg}\n`);
  process.exit(1);
}

/** O nucleo das regras, da mesma fonte e pelo mesmo caminho do hook de abertura. */
function nucleoDasRegras() {
  let lib;
  try {
    lib = require("../hooks/lib/contexto-sessao.cjs");
  } catch (e) {
    erro(`nao consegui carregar hooks/lib/contexto-sessao.cjs: ${e.message}`);
  }
  let skill;
  try {
    skill = fs.readFileSync(CAMINHO_SKILL, "utf8");
  } catch {
    erro(`nao consegui ler ${CAMINHO_SKILL} — a ponte nao inventa regra`);
  }
  const nucleo = lib.extrairNucleo(lib.filtrarRegras(skill)).trim();
  // Degradacao BARULHENTA, igual a do hook: ponte com meia regra parece completa,
  // e o dev do outro lado nao tem como saber que faltou.
  if (nucleo.length < lib.TETOS.REGRAS_MIN_CHARS) {
    erro(
      `so extrai ${nucleo.length} caracteres de regra (piso ${lib.TETOS.REGRAS_MIN_CHARS}) — ` +
        "SKILL.md truncado ou heading renomeado. Nao vou gerar ponte pela metade."
    );
  }
  return nucleo;
}

function raizDeDados() {
  try {
    return require("../hooks/lib/raiz.cjs").resolverRaiz({ plugin: CODIGO_ROOT }).raiz || null;
  } catch {
    return null;
  }
}

function corpo(agente, nucleo, dados) {
  const cli = [
    ["`node <plugin>/scripts/estado.cjs exigir --slug <slug> --estagio <e>`", "gate do fluxo — **exit 2** quando o estagio anterior nao fechou"],
    ["`node <plugin>/scripts/conferir-entrega.cjs --worktree <wt> --base <hash>`", "a checagem da regra 12 sobre entrega de agente — **exit 1** se reprovar"],
    ["`node <plugin>/scripts/conferir-publicacao.cjs <arquivo>`", "**exit 2** se o texto tem telefone, e-mail, caminho de home ou credencial"],
    // Sem `|` dentro do code span: em tabela markdown ele quebra a celula.
    ["`node <plugin>/scripts/ideias.cjs plantar, colher, listar, conferir`", "porta unica de escrita do `ideias.jsonl` (trava, backup, atomico, conferido)"],
    ["`node <plugin>/scripts/foco.cjs caminho, rotacionar`", "onde mora o foco, e o teto do bloco de avancos"],
    ["`node <plugin>/scripts/saude.cjs`", "o que os checadores oficiais nao sabem"],
    ["`node <plugin>/scripts/semear.cjs --projeto <slug>`", "o historico deste projeto: observacoes, ideias abertas, relatorios"],
  ]
    .map(([c, p]) => `| ${c} | ${p} |`)
    .join("\n");

  return `# rainforest-mind — ponte para o ${agente.nome}

${agente.comoLe} Este bloco e **gerado**: as regras moram em
\`skills/rainforest-mind/SKILL.md\`, no plugin, e chegam aqui por
\`node <plugin>/scripts/ponte.cjs --alvo . --agente ${Object.keys(AGENTES).find((k) => AGENTES[k] === agente)} --aplicar\`.
Editar este bloco a mao cria uma segunda versao das regras que divergem em
silencio — foi o que aconteceu com duas CLAUDE.md sincronizadas a mao em
2026-08-10. Mude o SKILL.md e gere de novo.

## O que NAO vale aqui, e voce precisa saber antes de confiar

${agente.semTrava}

O que continua sendo mecanismo, porque e comando com exit code, esta na tabela
abaixo. Chame de verdade: **relato de que rodou nao e evidencia de que rodou.**

| Comando | O que ele garante |
|---|---|
${cli}

\`<plugin>\` e a pasta do rainforest-mind nesta maquina. Sua pasta de dados
(FOCO.md, ideias.jsonl, projetos.json) **nao se chumba aqui**: descubra com
\`node <plugin>/scripts/ideias.cjs conferir\`, que imprime o caminho resolvido${dados ? "" : ", e monte com `node <plugin>/scripts/setup.cjs --criar` se ainda nao existir"}.
Caminho de home dentro de arquivo versionado vaza a maquina de quem gerou — e este
arquivo nasce para ser commitado no repo de outra pessoa.

## As regras

O que segue e o **nucleo** de cada regra. Regra marcada com \`↳\` tem elaboracao
que nao esta aqui — criterio fino, comando exato, incidente datado —, e ela mora
em \`skills/rainforest-mind/references/regra-<n>.md\` (onde \`<n>\` e o numero da regra). Antes de aplicar uma regra marcada, **leia esse arquivo**.

${nucleo}
`;
}

function escrever(alvoArquivo, blocoNovo, aplicar, hash) {
  const inicio = inicioComHash(hash);
  const marcado = `${inicio}\n${blocoNovo.trim()}\n${FIM}\n`;
  let anterior = null;
  try {
    anterior = fs.readFileSync(alvoArquivo, "utf8");
  } catch {
    anterior = null;
  }

  // Para substituicao de bloco existente, procura tanto a forma com hash quanto sem.
  const temMarcadorAtual = anterior && (anterior.includes(inicio) || anterior.includes("<!-- rainforest-mind:inicio"));

  let saida;
  let acao;
  if (anterior === null) {
    saida = marcado;
    acao = "cria";
  } else if (temMarcadorAtual && anterior.includes(FIM)) {
    // Encontra o inicio do bloco, seja com ou sem hash
    const inicioIdx = anterior.indexOf("<!-- rainforest-mind:inicio");
    const antes = anterior.slice(0, inicioIdx);
    const depois = anterior.slice(anterior.indexOf(FIM) + FIM.length).replace(/^\n+/, "");
    saida = `${antes}${marcado}${depois ? `\n${depois}` : ""}`;
    acao = "substitui o bloco gerado";
  } else {
    // Arquivo escrito a mao por outra pessoa. Nunca sobrescrever: o bloco entra no
    // fim e o que era dela continua intacto, byte a byte.
    saida = `${anterior.replace(/\n*$/, "")}\n\n${marcado}`;
    acao = "ACRESCENTA no fim (o arquivo ja existia sem marcador — nada dele foi apagado)";
  }

  if (!aplicar) return { acao, bytes: Buffer.byteLength(saida, "utf8"), gravado: false };
  fs.writeFileSync(alvoArquivo, saida, "utf8");
  return { acao, bytes: Buffer.byteLength(saida, "utf8"), gravado: true };
}

function main() {
  const alvo = arg("alvo");
  if (!alvo) erro("diga --alvo <dir> (a raiz do repositorio que vai receber a ponte)");
  let stat;
  try {
    stat = fs.statSync(alvo);
  } catch {
    erro(`--alvo '${alvo}' nao existe`);
  }
  if (!stat.isDirectory()) erro(`--alvo '${alvo}' nao e diretorio`);

  // Sem `--agente`, valem os alvos DECLARADOS no /setup. `todos` continua existindo
  // como escolha explicita — o que saiu foi o "todos" como PADRAO: gerar arquivo em
  // repositorio de terceiro nao e coisa que se faz por omissao.
  const pedido = arg("agente");
  let chaves;
  if (pedido && pedido.toLowerCase() === "todos") {
    chaves = Object.keys(AGENTES);
  } else if (pedido) {
    chaves = [pedido.toLowerCase()];
  } else {
    chaves = declarados();
    if (!chaves.length) {
      erro(
        "nenhum alvo declarado nesta configuracao. Ligue no setup o que voce usa:\n" +
          Object.keys(AGENTES)
            .map((k) => `    node scripts/setup.cjs --ligar ponte-${k}   (${AGENTES[k].arquivo})`)
            .join("\n") +
          "\n  ou escolha pontualmente: --agente " +
          `${Object.keys(AGENTES).join("|")}|todos`
      );
    }
    console.log(`alvos declarados no setup: ${chaves.join(", ")}`);
  }
  for (const k of chaves) {
    if (!AGENTES[k]) erro(`--agente '${k}' desconhecido — use ${Object.keys(AGENTES).join(", ")} ou todos`);
  }

  const aplicar = tem("aplicar");
  const nucleo = nucleoDasRegras();
  const dados = raizDeDados();
  const hash = hashSkillMd();

  console.log(`fonte das regras: ${path.relative(CODIGO_ROOT, CAMINHO_SKILL)} (nucleo com ${Buffer.byteLength(nucleo, "utf8")} B)${hash ? ` — hash ${hash}` : ""}`);
  for (const k of chaves) {
    const agente = AGENTES[k];
    const destino = path.join(alvo, agente.arquivo);
    const r = escrever(destino, corpo(agente, nucleo, dados), aplicar, hash);
    console.log(`  ${agente.arquivo}: ${r.acao} — ${r.bytes} B ${r.gravado ? "GRAVADO" : "(ensaio)"}`);
    console.log(`    ${destino}`);
  }
  if (!aplicar) console.log("\n--aplicar ausente: ensaio, nada gravado.");
  return 0;
}

process.exitCode = main();
