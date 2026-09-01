#!/usr/bin/env node
"use strict";
/* Portaria — NÚCLEO DE DECISÃO (Tarefas 2 e 3 do fluxo 9, D1–D7).
 *
 * Registrado como PreToolUse em `.claude/settings.json` com matcher de
 * despacho de subagente. Aqui é implementada a decisão fail-closed sobre
 * admissão de subagente via `.rainforest/agentes.json` (manifesto) + estágio
 * ativo (sem exceder estagios permitidos + escreve).
 *
 * Exit 0: aprovado, linha de log anexada.
 * Exit 2: negado, motivo no stderr (fail-closed — sempre com motivo não-vazio).
 *
 * Modo captura (D7) mantido: primeira amostra em `.rainforest/portaria/amostra.json`.
 */

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

/**
 * Resolve a raiz do projeto seguindo precedência rigorosa:
 * 1. payload.cwd (cwd da sessão que despachou — fonte da verdade)
 * 2. process.env.CLAUDE_PROJECT_DIR
 * 3. process.cwd() (último recurso)
 *
 * O valor escolhido é normalizado para o toplevel do git (`git rev-parse --show-toplevel`)
 * porque payload.cwd pode ser um subdiretório do projeto. Se git falhar (não é repositório),
 * o caminho é usado como veio.
 *
 * Sobre a subida silenciosa do `git -C`, que a revisão levantou (rodada 2, AVISO):
 * `git -C <dir>` num diretório SEM `.git` próprio, mas aninhado em algum
 * repositório, devolve o toplevel do repositório de fora com exit 0 — o
 * `try/catch` só cobre "não há `.git` em lugar nenhum acima". A elaboração da
 * regra 11 documenta essa armadilha, e aqui ela é o comportamento QUERIDO, não
 * o acidente: `payload.cwd` é o cwd da sessão, então o repositório que o
 * envolve É o projeto em que aquela sessão está trabalhando, e é o manifesto
 * dele que deve valer. Subir é o que faz `payload.cwd` num subdiretório
 * (`<worktree>/hooks`) resolver para a raiz do worktree.
 *
 * O caso que sobraria — `payload.cwd` cair dentro de um repositório NÃO
 * relacionado que por coincidência tenha `.rainforest/agentes.json` e um fluxo
 * aberto cujo slug case com a branch de lá — não foi construído de forma
 * realista na revisão, e o caminho de falha é seguro: sem manifesto naquela
 * raiz, a decisão é "manifesto ausente", que nega. Fica registrado aqui em vez
 * de virar máquina nova, porque máquina para caso não demonstrado é código que
 * ninguém sabe se funciona.
 */
function raizDoProjeto(payload) {
  let caminho;
  if (payload && payload.cwd) {
    caminho = payload.cwd;
  } else if (process.env.CLAUDE_PROJECT_DIR) {
    caminho = process.env.CLAUDE_PROJECT_DIR;
  } else {
    caminho = process.cwd();
  }
  try {
    const toplevel = execFileSync("git", ["-C", caminho, "rev-parse", "--show-toplevel"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return toplevel;
  } catch {
    return caminho;
  }
}

function negar(motivo) {
  if (motivo) {
    process.stderr.write(motivo);
    if (!motivo.endsWith('\n')) process.stderr.write('\n');
  }
  process.exit(2);
}

function normalizarNomeAgente(nome) {
  if (!nome || typeof nome !== "string") return null;
  // Remove prefixo tipo 'rainforest-mind:' se existir
  if (nome.includes(":")) {
    return nome.split(":").pop();
  }
  return nome;
}

/* Lê `tools:` do frontmatter do agente e devolve TRES estados, nao dois.
 *
 * A versao anterior devolvia uma lista, e lista vazia servia para duas coisas
 * incompativeis: "o agente nao declara tools" e "declara, mas eu nao entendi o
 * formato". Os dois caiam no mesmo `if (tools.length > 0)` do chamador, que
 * PULA a checagem — ou seja, formato que o parser nao entendia virava
 * liberacao. Foi o critico da rodada 2 da revisao, reproduzido em sandbox:
 * duas declaracoes YAML equivalentes, uma com hifen indentado e outra com o
 * hifen na mesma coluna da chave (as duas validas), davam deny e ALLOW.
 *
 *   { declarado: false, tools: null }  -> nao ha chave `tools:`; pula a
 *                                        checagem, que e o que D3 passo 6 manda
 *                                        para agente sem declaracao.
 *   { declarado: true,  tools: [...] } -> entendi; confere contra a allowlist.
 *   { declarado: true,  tools: null }  -> ha `tools:` e eu NAO consegui ler.
 *                                        NEGA. Nao ha terceira opcao honesta:
 *                                        nao da para afirmar que um agente e
 *                                        read-only a partir de um texto que
 *                                        nao foi lido.
 *
 * Formatos aceitos: inline com virgula (`tools: Read, Grep, Glob`) e lista de
 * bloco YAML com ou sem indentacao. Quem escrever `tools: *` ou qualquer coisa
 * que nao seja lista de nomes cai no terceiro estado, e nega — que e o certo:
 * `*` e todas as ferramentas.
 *
 * A DETECCAO DA CHAVE NAO E BUSCA LITERAL, e a razao e o historico: a rodada 2
 * reprovou por indentacao (`- Nome` sem espaco antes do hifen), e a rodada 3
 * reprovou o conserto dela por espacamento — `tools :`, com espaco antes dos
 * dois-pontos, e YAML valido (`yaml.safe_load("tools :\n- Write\n")` devolve
 * `{'tools': ['Write']}`) e o regex `/^tools:/` nao casava, entao a chave
 * PRESENTE caia no estado "nao declarado" e a checagem era pulada. Duas rodadas
 * na mesma funcao, o mesmo furo por portas diferentes.
 *
 * Perseguir variante de YAML com regex literal e jogo perdido, entao aqui a
 * frontmatter e varrida por CHAVE DE TOPO — `<nome>` seguido de espacos
 * opcionais, dois-pontos, e o resto da linha —, e `tools` e escolhida pelo
 * nome. Qualquer espacamento em volta dos dois-pontos passa a ser irrelevante
 * por construcao, e nao por mais um caso previsto. `\r` de arquivo em CRLF cai
 * fora antes da comparacao.
 */
const RE_CHAVE_DE_TOPO = /^([A-Za-z0-9_-]+)[ \t]*:[ \t]*(.*)$/;

function parseToolsDoFrontmatter(frontmatter) {
  // `\r` some para que arquivo em CRLF nao mude o resultado.
  const linhas = String(frontmatter).split("\n").map((l) => l.replace(/\r$/, ""));

  let iChave = -1;
  let inline = "";
  for (let i = 0; i < linhas.length; i++) {
    const m = linhas[i].match(RE_CHAVE_DE_TOPO);
    if (m && m[1] === "tools") {
      iChave = i;
      inline = m[2].trim();
      break;
    }
  }

  if (iChave === -1) return { declarado: false, tools: null };

  // Nome de tool e identificador: letra, digito, `_` ou `-`. `*`, `all`, chave
  // de YAML de fluxo — nada disso e lista de nomes, e cai no terceiro estado.
  const soNomes = (lista) =>
    lista.length > 0 && lista.every((t) => /^[A-Za-z0-9_-]+$/.test(t));

  // Valor na MESMA linha da chave: lista inline separada por virgula.
  if (inline && !inline.startsWith("-")) {
    const tools = inline.split(",").map((t) => t.trim()).filter(Boolean);
    return { declarado: true, tools: soNomes(tools) ? tools : null };
  }

  // Lista de bloco: as linhas SEGUINTES, com indentacao ou sem.
  const tools = [];
  for (let i = iChave + 1; i < linhas.length; i++) {
    const linha = linhas[i];
    if (!linha.trim()) continue; // linha vazia dentro do bloco
    const item = linha.match(/^[ \t]*-[ \t]*(.+?)[ \t]*$/);
    if (item) {
      tools.push(item[1].replace(/^["']|["']$/g, ""));
      continue;
    }
    break; // primeira linha que nao e item encerra o bloco (outra chave, etc.)
  }

  // Chave presente e ZERO item lido — terceiro estado, nega. Este ramo ficou
  // sem teste na rodada 3 (a mutacao para `declarado: false` deixava a bateria
  // VERDE), e agora tem: caso 12 de testa-portaria-tools-bloco.cjs.
  return { declarado: true, tools: soNomes(tools) ? tools : null };
}

function validarToolsAowlist(tools) {
  const allowlist = ["Read", "Grep", "Glob"];
  for (const tool of tools) {
    if (!allowlist.includes(tool)) {
      return tool;
    }
  }
  return null;
}

function obterDefinicaoAgente(raiz, nomeAgente, agentesDir) {
  // Se agentesDir for passado, usa-o diretamente
  if (agentesDir) {
    const caminho = path.join(agentesDir, `${nomeAgente}.md`);
    if (fs.existsSync(caminho)) {
      try {
        return fs.readFileSync(caminho, "utf8");
      } catch {
        return null;
      }
    }
    return null;
  }

  // Caso padrão: tenta `.claude/agents/<nome>.md` primeiro, depois `agents/<nome>.md`
  const caminhos = [
    path.join(raiz, ".claude", "agents", `${nomeAgente}.md`),
    path.join(raiz, "agents", `${nomeAgente}.md`),
  ];

  for (const caminho of caminhos) {
    if (fs.existsSync(caminho)) {
      try {
        return fs.readFileSync(caminho, "utf8");
      } catch {
        // Arquivo ilegível — passa para o próximo
      }
    }
  }

  return null; // Arquivo não encontrado
}

function gravarAmostra(raiz, payload) {
  // Captura primeira amostra apenas (D7)
  const dir = path.join(raiz, ".rainforest", "portaria");
  const amostraPath = path.join(dir, "amostra.json");

  if (!fs.existsSync(amostraPath)) {
    try {
      fs.mkdirSync(dir, { recursive: true });
      const tmp = amostraPath + ".tmp";
      fs.writeFileSync(tmp, JSON.stringify(payload, null, 2) + "\n", "utf8");
      fs.renameSync(tmp, amostraPath);
    } catch {
      // Falha de gravacao nao pode travar a sessao do usuario.
    }
  }
}

function gravarDespacho(raiz, decisao, agente, estagio, sessao, motivo) {
  // Append-only log de despachos (D4)
  const dir = path.join(raiz, ".rainforest", "portaria");
  const logPath = path.join(dir, "despachos.jsonl");

  try {
    fs.mkdirSync(dir, { recursive: true });

    const entrada = {
      ts: new Date().toISOString(),
      agente,
      estagio,
      decisao,
      sessao,
    };

    if (motivo) {
      entrada.motivo = motivo;
    }

    const linha = JSON.stringify(entrada) + "\n";
    fs.appendFileSync(logPath, linha, "utf8");
  } catch {
    // Falha de gravacao nao pode travar a sessao do usuario.
  }
}

function main() {
  // Ler payload do stdin
  let bruto = "";
  try {
    bruto = fs.readFileSync(0, "utf8");
  } catch {
    // Stdin ilegível: libera sem log. A política é a mesma dos quatro gates irmãos.
    process.exit(0);
  }

  if (!bruto.trim()) {
    // Payload vazio: libera sem log.
    process.exit(0);
  }

  let payload;
  try {
    payload = JSON.parse(bruto);
  } catch {
    // Payload JSON inválido: libera sem log.
    process.exit(0);
  }

  // Agora temos payload válido — resolver a raiz DO PROJETO
  const raiz = raizDoProjeto(payload);

  // Extrai nome do agente (com normalização)
  const nomeAgenteBruto = payload.tool_input && payload.tool_input.subagent_type;
  if (!nomeAgenteBruto) {
    negar("Campo tool_input.subagent_type ausente no payload");
  }

  // Grava amostra (primeira captura vence) — SÓ após validar que subagent_type existe
  gravarAmostra(raiz, payload);

  const nomeAgente = normalizarNomeAgente(nomeAgenteBruto);
  if (!nomeAgente) {
    negar("Nome do agente inválido");
  }

  const sessao = payload.session_id || "desconhecida";

  // Carrega manifesto (D3 passo 2: ausente ou inválido → nega)
  const manifestoPath = path.join(raiz, ".rainforest", "agentes.json");
  let manifesto;

  if (!fs.existsSync(manifestoPath)) {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, "manifesto ausente");
    negar(`Manifesto não encontrado em ${manifestoPath}`);
  }

  try {
    const brutoManifesto = fs.readFileSync(manifestoPath, "utf8");
    manifesto = JSON.parse(brutoManifesto);
  } catch {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, "manifesto JSON inválido");
    negar("Manifesto JSON inválido");
  }

  // D3 passo 2b: validar versao e agentes (schema D2)
  if (manifesto.versao === undefined || manifesto.versao === null) {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, "manifesto sem versao");
    negar("Manifesto sem versao");
  }

  if (manifesto.versao !== 1) {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, `manifesto com versao desconhecida: ${manifesto.versao}`);
    negar(`Manifesto com versao desconhecida: ${manifesto.versao}`);
  }

  if (typeof manifesto.agentes !== "object" || manifesto.agentes === null || Array.isArray(manifesto.agentes)) {
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, "manifesto.agentes invalido");
    negar("Manifesto.agentes inválido");
  }

  // D3 passo 3: agente não declarado → nega
  if (!manifesto.agentes[nomeAgente]) {
    const motivo = `agente '${nomeAgente}' não consta no manifesto`;
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, motivo);
    negar(motivo);
  }

  const agentConfig = manifesto.agentes[nomeAgente];

  // D3 passo 4: sem estágio ativo → nega
  const estReader = require("./lib/estagio-ativo.cjs");
  const estResult = estReader.resolver({ cwd: raiz });

  if (!estResult) {
    const motivo = "sem estágio ativo — abra um fluxo";
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, motivo);
    negar(motivo);
  }

  const { estagio: estagioAtivo } = estResult;

  // D3 passo 5: estágio fora da lista permitida → nega
  if (!agentConfig.estagios || !Array.isArray(agentConfig.estagios)) {
    const motivo = `Configuração inválida do agente '${nomeAgente}' no manifesto`;
    gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
    negar(motivo);
  }

  if (!agentConfig.estagios.includes(estagioAtivo)) {
    const permitidos = agentConfig.estagios.join(", ");
    const motivo = `estágio '${estagioAtivo}' não permitido para '${nomeAgente}' (permitidos: ${permitidos})`;
    gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
    negar(motivo);
  }

  // D3 passo 6: escreve: false com tools fora de allowlist → nega
  if (agentConfig.escreve === false) {
    const def = obterDefinicaoAgente(raiz, nomeAgente);

    if (def) {
      // Parse frontmatter para extrair tools (se declaradas)
      const fmMatch = def.match(/^---\n([\s\S]*?)\n---/);
      if (fmMatch) {
        const frontmatter = fmMatch[1];
        const { declarado, tools } = parseToolsDoFrontmatter(frontmatter);

        if (declarado && tools === null) {
          // Declara `tools:` e o formato nao foi lido. Nao da para afirmar
          // read-only a partir de texto nao lido — nega, e diz o que fazer.
          const motivo =
            `agente '${nomeAgente}' com escreve:false declara 'tools:' em formato que a portaria nao le` +
            ` — use lista de nomes (inline com virgula, ou um '- Nome' por linha)`;
          gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
          negar(motivo);
        }

        if (declarado && tools) {
          const toolInvalido = validarToolsAowlist(tools);
          if (toolInvalido) {
            const motivo = `agente '${nomeAgente}' com escreve:false declara tool fora da allowlist: ${toolInvalido}`;
            gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
            negar(motivo);
          }
        }
      }
    }
    // Se arquivo não encontrado, não falha — pula a checagem (D3 passo 6)
  }

  // Passou tudo → aprova (D3 passo 7)
  gravarDespacho(raiz, "allow", nomeAgente, estagioAtivo, sessao);
  process.exit(0);
}

function executarLint(manifestoPath, agentesDir) {
  let estadoModule;
  try {
    estadoModule = require("../scripts/estado.cjs");
  } catch (err) {
    console.error(`erro: não consegui carregar estado.cjs: ${err.message}`);
    process.exit(1);
  }

  const { PRE_REQUISITOS } = estadoModule;
  const estadioValidos = new Set(
    Object.keys(PRE_REQUISITOS).filter(e => e !== "limpar")
  );

  let erros = 0;
  let avisos = 0;

  // Carregar e validar manifesto
  let manifesto;
  if (!fs.existsSync(manifestoPath)) {
    console.error(`erro: manifesto não encontrado em ${manifestoPath}`);
    erros++;
  } else {
    try {
      const conteudo = fs.readFileSync(manifestoPath, "utf8");
      manifesto = JSON.parse(conteudo);

      // Checagem 5: validar schema D2
      if (manifesto.versao === undefined || manifesto.versao === null) {
        console.error("erro: manifesto sem versao");
        erros++;
      } else if (manifesto.versao !== 1) {
        console.error(`erro: manifesto com versao desconhecida: ${manifesto.versao}`);
        erros++;
      } else if (typeof manifesto.agentes !== "object" || manifesto.agentes === null || Array.isArray(manifesto.agentes)) {
        console.error("erro: manifesto.agentes invalido");
        erros++;
      }
    } catch (err) {
      console.error("erro: manifesto JSON inválido");
      erros++;
      manifesto = null;
    }
  }

  if (!manifesto) {
    if (erros > 0) {
      process.exit(1);
    }
    return;
  }

  const agentes = manifesto.agentes || {};
  const nomesDeclArados = Object.keys(agentes);

  // Listar arquivos em agentes-dir
  let agentesEmDisco = [];
  if (fs.existsSync(agentesDir)) {
    agentesEmDisco = fs
      .readdirSync(agentesDir)
      .filter(f => f.endsWith(".md"))
      .map(f => f.replace(/\.md$/, ""));
  }

  const agentesEmDiscoSet = new Set(agentesEmDisco);

  // Checagem 1: agente no manifesto sem arquivo correspondente
  for (const nome of nomesDeclArados) {
    if (!agentesEmDiscoSet.has(nome)) {
      console.error(`erro: agente '${nome}' declarado no manifesto mas sem arquivo em ${agentesDir}/${nome}.md`);
      erros++;
    }

    // Checagem 4: estágios desconhecidos
    const config = agentes[nome];
    if (config && Array.isArray(config.estagios)) {
      for (const est of config.estagios) {
        if (!estadioValidos.has(est)) {
          console.error(`erro: agente '${nome}' declara estágio desconhecido: '${est}'`);
          erros++;
        }
      }
    }

    // Checagem 3: escreve: false mas tool de escrita no frontmatter
    if (config && config.escreve === false) {
      const def = obterDefinicaoAgente(raizDoProjeto(), nome, agentesDir);
      if (def) {
        const fmMatch = def.match(/^---\n([\s\S]*?)\n---/);
        if (fmMatch) {
          const frontmatter = fmMatch[1];
          const { declarado, tools } = parseToolsDoFrontmatter(frontmatter);
          if (declarado && tools === null) {
            console.error(
              `erro: agente '${nome}' com escreve:false declara 'tools:' em formato que a portaria nao le` +
              ` — use lista de nomes (inline com virgula, ou um '- Nome' por linha)`
            );
            erros++;
          } else if (declarado && tools) {
            const toolInvalido = validarToolsAowlist(tools);
            if (toolInvalido) {
              console.error(`erro: agente '${nome}' com escreve:false declara tool fora da allowlist: ${toolInvalido}`);
              erros++;
            }
          }
        }
      }
    }
  }

  // Checagem 2: arquivo em agentes-dir sem entrada no manifesto (órfão)
  for (const nome of agentesEmDisco) {
    if (!nomesDeclArados.includes(nome)) {
      console.warn(`aviso: agente '${nome}' em ${agentesDir} mas não declarado no manifesto (órfão)`);
      avisos++;
    }
  }

  if (erros > 0) {
    process.exit(1);
  }
  // Avisos não mudam exit code
}

if (require.main === module) {
  if (process.argv[2] === "--lint") {
    let manifestoPath = ".rainforest/agentes.json";
    let agentesDir = "agents";

    for (let i = 3; i < process.argv.length; i++) {
      if (process.argv[i] === "--manifesto" && i + 1 < process.argv.length) {
        manifestoPath = process.argv[i + 1];
        i++;
      } else if (process.argv[i] === "--agentes-dir" && i + 1 < process.argv.length) {
        agentesDir = process.argv[i + 1];
        i++;
      }
    }

    const raiz = raizDoProjeto();
    // Se o caminho for absoluto, usa como está; se for relativo, usa raiz
    const manifestoCompleto = path.isAbsolute(manifestoPath) ? manifestoPath : path.join(raiz, manifestoPath);
    const agentesCompleto = path.isAbsolute(agentesDir) ? agentesDir : path.join(raiz, agentesDir);
    executarLint(manifestoCompleto, agentesCompleto);
  } else {
    main();
  }
}
