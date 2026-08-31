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
const FIM_PROJETO = "<!-- rainforest-mind:projeto:fim -->";

// Importar funções compartilhadas
const { corpo, raizDeDados: raizDeDadosShared, AGENTES: AGENTES_SHARED, lerProjetoMd } =
  require("../hooks/lib/ponte-corpo.cjs");

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

// Usar AGENTES do módulo compartilhado
const AGENTES = AGENTES_SHARED;

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

// raizDeDados() foi movida para o módulo compartilhado, chamar de lá
function raizDeDados() {
  return raizDeDadosShared(CODIGO_ROOT);
}

/**
 * Varredura pura do repositório alvo — detecta stack, comandos, layout.
 * Retorna objeto JSON. Não escreve nada em disco.
 */
function varrerRepositorio(alvo) {
  const resultado = {
    stack: "desconhecida",
    scripts: [],
    workflows: [],
    layout: [],
  };

  // Detecta stack Node
  const packageJsonPath = path.join(alvo, "package.json");
  let packageJson = null;
  try {
    const conteudo = fs.readFileSync(packageJsonPath, "utf8");
    packageJson = JSON.parse(conteudo);
    resultado.stack = "node";
    // Coleta scripts.test e scripts.build
    if (packageJson.scripts) {
      if (packageJson.scripts.test) {
        resultado.scripts.push({
          tipo: "test",
          comando: packageJson.scripts.test,
        });
      }
      if (packageJson.scripts.build) {
        resultado.scripts.push({
          tipo: "build",
          comando: packageJson.scripts.build,
        });
      }
    }
  } catch {
    // Tenta detectar Python
    const requirementsTxt = path.join(alvo, "requirements.txt");
    const pyprojectToml = path.join(alvo, "pyproject.toml");
    try {
      fs.statSync(requirementsTxt);
      resultado.stack = "python";
    } catch {
      try {
        fs.statSync(pyprojectToml);
        resultado.stack = "python";
      } catch {
        // Tenta detectar Go
        const goMod = path.join(alvo, "go.mod");
        try {
          fs.statSync(goMod);
          resultado.stack = "go";
        } catch {
          // stack permanece "desconhecida"
        }
      }
    }
  }

  // Coleta workflows de .github/workflows/*.yml
  const workflowsDir = path.join(alvo, ".github", "workflows");
  try {
    const files = fs.readdirSync(workflowsDir);
    for (const file of files) {
      if (file.endsWith(".yml") || file.endsWith(".yaml")) {
        resultado.workflows.push(file.replace(/\.(yml|yaml)$/, ""));
      }
    }
  } catch {
    // Diretório não existe ou não pode ser lido
  }

  // Coleta layout de 1º nível (ignora .git, node_modules e docs — artefato gerado)
  try {
    const entries = fs.readdirSync(alvo, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory() && entry.name !== ".git" && entry.name !== "node_modules" && entry.name !== "docs") {
        resultado.layout.push(entry.name);
      }
    }
    resultado.layout.sort();
  } catch {
    // Diretório não pode ser lido
  }

  return resultado;
}

/**
 * Grava docs/rainforest/projeto.md atomicamente a partir das respostas de entrevista.
 * Lê arquivo JSON com 4 chaves: pronto, nao_toca, convencao, revisao.
 * Chama varrerRepositorio() para obter os fatos (stack, comandos, layout).
 * Gera markdown combinando fatos + respostas.
 * Se aplicar=true, escreve atomicamente (tmp + rename) em alvo/docs/rainforest/projeto.md.
 * Se aplicar=false, retorna o conteúdo gerado (stdout, sem gravar).
 * Retorna {gravado, bytes, markdown} para relato.
 */
function gravarProjetoMd(alvo, respostasArquivo, aplicar) {
  // Lê e valida JSON de respostas
  let respostas;
  try {
    const conteudo = fs.readFileSync(respostasArquivo, "utf8");
    respostas = JSON.parse(conteudo);
  } catch (e) {
    erro(`nao consegui ler ou parsear --respostas '${respostasArquivo}': ${e.message}`);
  }

  const chavesPrecisas = ["pronto", "nao_toca", "convencao", "revisao"];
  for (const chave of chavesPrecisas) {
    if (!(chave in respostas)) {
      erro(`--respostas ausente chave obrigatoria: ${chave}`);
    }
  }

  // Sanitiza respostas: remove marcadores perigosos que causariam truncamento
  respostas = sanitizarRespostas(respostas);

  // Varredura pura (fatos: stack, comandos, layout)
  const fatos = varrerRepositorio(alvo);

  // Gera markdown combinando fatos + respostas
  const markdown = gerarProjetoMarkdown(fatos, respostas);

  // Determina caminho de saída (atomicamente)
  const dirProjeto = path.join(alvo, "docs", "rainforest");
  const arquivoFinal = path.join(dirProjeto, "projeto.md");
  const arquivoTmp = arquivoFinal + ".tmp";

  if (!aplicar) {
    // Ensaio: apenas retorna o conteúdo
    return { gravado: false, bytes: Buffer.byteLength(markdown, "utf8"), markdown };
  }

  // Grava atomicamente: tmp + rename
  try {
    fs.mkdirSync(dirProjeto, { recursive: true });
    fs.writeFileSync(arquivoTmp, markdown, "utf8");
    fs.renameSync(arquivoTmp, arquivoFinal);
    return { gravado: true, bytes: Buffer.byteLength(markdown, "utf8"), markdown };
  } catch (e) {
    erro(`erro ao gravar projeto.md atomicamente: ${e.message}`);
  }
}

/**
 * Sanitiza respostas: remove marcadores rainforest-mind:projeto que causariam truncamento.
 * Busca por <!-- rainforest-mind:projeto:(inicio|fim) --> e remove, tolerando espaçamento.
 */
function sanitizarRespostas(respostas) {
  const padraoMarcador = /<!--\s*rainforest-mind:projeto:(inicio|fim)\s*-->/gi;
  const sanitizadas = {};
  for (const chave in respostas) {
    if (typeof respostas[chave] === "string") {
      sanitizadas[chave] = respostas[chave].replace(padraoMarcador, "");
    } else {
      sanitizadas[chave] = respostas[chave];
    }
  }
  return sanitizadas;
}

/**
 * Gera o conteúdo markdown de projeto.md a partir dos fatos da varredura + respostas.
 * Formato: título, seção fatos, seção respostas. Legível, estável para hash.
 */
function gerarProjetoMarkdown(fatos, respostas) {
  const marcadorInicio = "<!-- rainforest-mind:projeto:inicio -->";
  const marcadorFim = "<!-- rainforest-mind:projeto:fim -->";

  // Formata os fatos da varredura
  const fatosText = [
    `### Stack`,
    `${fatos.stack}`,
    ``,
    `### Comandos de teste/build`,
    fatos.scripts.length > 0
      ? fatos.scripts.map((s) => `- **${s.tipo}**: \`${s.comando}\``).join("\n")
      : "(nenhum script encontrado)",
    ``,
    `### Layout (diretórios de 1º nível)`,
    fatos.layout.length > 0
      ? fatos.layout.map((d) => `- ${d}`).join("\n")
      : "(nenhum diretório relevante)",
  ].join("\n");

  // Formata as respostas
  const respostasText = [
    `### O que é "pronto" aqui`,
    respostas.pronto || "(não respondido)",
    ``,
    `### O que não se toca`,
    respostas.nao_toca || "(não respondido)",
    ``,
    `### Convenção não escrita`,
    respostas.convencao || "(não respondido)",
    ``,
    `### Política de revisão`,
    respostas.revisao || "(não respondido)",
  ].join("\n");

  return [
    marcadorInicio,
    `# Bloco do projeto`,
    ``,
    `## Fatos da varredura`,
    ``,
    fatosText,
    ``,
    `## Respostas da entrevista`,
    ``,
    respostasText,
    marcadorFim,
  ].join("\n");
}


function escrever(alvoArquivo, blocoNovo, aplicar, hash, alvo) {
  const inicio = inicioComHash(hash);
  const marcado = `${inicio}\n${blocoNovo.trim()}\n${FIM}\n`;

  // Adiciona bloco de projeto após o FIM, se existir
  const blocoProjetoComHash = lerProjetoMd(alvo, true);
  const marcadoComProjeto = blocoProjetoComHash ? `${marcado}\n${blocoProjetoComHash}\n` : marcado;

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
    saida = marcadoComProjeto;
    acao = "cria";
  } else if (temMarcadorAtual && anterior.includes(FIM)) {
    // Encontra o inicio do bloco, seja com ou sem hash
    const inicioIdx = anterior.indexOf("<!-- rainforest-mind:inicio");
    const antes = anterior.slice(0, inicioIdx);
    // Remove o antigo bloco de projeto também se existir
    let depois = anterior.slice(anterior.indexOf(FIM) + FIM.length).replace(/^\n+/, "");
    if (depois.includes(FIM_PROJETO)) {
      const idxFimProj = depois.indexOf(FIM_PROJETO);
      depois = depois.slice(idxFimProj + FIM_PROJETO.length).replace(/^\n+/, "");
    }
    saida = `${antes}${marcadoComProjeto}${depois ? `${depois}` : ""}`;
    acao = "substitui o bloco gerado";
  } else {
    // Arquivo escrito a mao por outra pessoa. Nunca sobrescrever: o bloco entra no
    // fim e o que era dela continua intacto, byte a byte.
    saida = `${anterior.replace(/\n*$/, "")}\n\n${marcadoComProjeto}`;
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

  // Roteamento: --entrevistar --varredura (sem mais bandeiras)
  if (tem("entrevistar") && tem("varredura")) {
    const resultado = varrerRepositorio(alvo);
    console.log(JSON.stringify(resultado, null, 2));
    return 0;
  }

  // Roteamento: --entrevistar --gravar (grava projeto.md atomicamente)
  if (tem("entrevistar") && tem("gravar")) {
    const respostasArquivo = arg("respostas");
    if (!respostasArquivo) erro("--entrevistar --gravar precisa de --respostas <arquivo>");

    const aplicar = tem("aplicar");
    const r = gravarProjetoMd(alvo, respostasArquivo, aplicar);

    if (!aplicar) {
      // Ensaio: imprime markdown no stdout
      console.log(r.markdown);
      return 0;
    }

    // Com --aplicar: relata e retorna 0
    console.log(`projeto.md: ${r.gravado ? "gravado" : "nao gravado"} — ${r.bytes} B`);
    return 0;
  }

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
    const r = escrever(destino, corpo(agente, nucleo, dados, alvo), aplicar, hash, alvo);
    console.log(`  ${agente.arquivo}: ${r.acao} — ${r.bytes} B ${r.gravado ? "GRAVADO" : "(ensaio)"}`);
    console.log(`    ${destino}`);
  }
  if (!aplicar) console.log("\n--aplicar ausente: ensaio, nada gravado.");
  return 0;
}

process.exitCode = main();
