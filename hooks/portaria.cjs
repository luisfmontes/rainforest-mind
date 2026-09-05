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

function obterBranch(raiz) {
  try {
    const branch = execFileSync("git", ["-C", raiz, "rev-parse", "--abbrev-ref", "HEAD"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return branch || null;
  } catch {
    return null;
  }
}

function primeiroEstagioAberto(estado) {
  const ordem = ["design", "plano", "executar", "revisar", "verificar", "fechar"];
  for (const est of ordem) {
    if (estado[est] && estado[est].status && estado[est].status !== "ok" && estado[est].status !== "aprovado") {
      return est;
    }
  }
  return null;
}

function obterOutrosWorktreesComFluxoAberto(raiz) {
  try {
    const saida = execFileSync("git", ["-C", raiz, "worktree", "list", "--porcelain"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const linhas = saida.trim().split("\n").filter(Boolean);
    const worktrees = [];

    for (const linha of linhas) {
      // Formato: "worktree /caminho"
      const m = linha.match(/^worktree\s+(.+)$/);
      if (!m) continue;

      const caminhoWorktree = m[1].trim();

      // Verifica se não é o mesmo diretório (normaliza para comparação)
      const raizNorm = path.normalize(raiz);
      const wtNorm = path.normalize(caminhoWorktree);
      if (raizNorm === wtNorm) {
        continue; // É o mesmo — pula
      }

      // Tenta ler o estado para este worktree
      const dirEstado = path.join(caminhoWorktree, "docs", "rainforest", "estado");
      if (fs.existsSync(dirEstado)) {
        try {
          const arquivos = fs.readdirSync(dirEstado).filter(f => f.endsWith(".json"));
          for (const arquivo of arquivos) {
            try {
              const conteudo = fs.readFileSync(path.join(dirEstado, arquivo), "utf8");
              const estado = JSON.parse(conteudo);
              if (estado && typeof estado === "object" && estado.slug) {
                // Verifica se tem fluxo aberto (algum estágio não fechado) —
                // e já guarda qual, reaproveitando este parse (evita reabrir
                // o JSON depois, no worktree errado ou no certo).
                const estagioAberto = primeiroEstagioAberto(estado);
                if (estagioAberto) {
                  worktrees.push({ slug: estado.slug, arquivo, caminho: caminhoWorktree, estagio: estagioAberto });
                  break;
                }
              }
            } catch {
              // Ignora arquivo inválido
            }
          }
        } catch {
          // Ignora erro ao ler diretório
        }
      }
    }

    return worktrees;
  } catch {
    return [];
  }
}

function formatarOutrosWorktreesAbertos(outrosWorktrees) {
  let trecho = `  outros worktrees em fluxo aberto (slug e estágio):\n`;
  for (const wt of outrosWorktrees) {
    const estagioStr = wt.estagio || "?";
    trecho += `    - slug: ${wt.slug}, estágio: ${estagioStr}\n`;
  }
  return trecho;
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

/* Uma linha JSON autocontida por decisão (D4), append-only.
 *
 * `escreveConferido` só aparece na linha quando é `false`: linha de `allow` sem
 * o campo significa allow conferido, que é o caso comum, e o log não paga um
 * campo em toda linha para dizer "nada de anormal". Quando aparece, diz que a
 * portaria aprovou SEM ter conseguido verificar o `escreve: false` do manifesto
 * (arquivo do agente ausente, sem frontmatter, ou sem `tools:`).
 *
 * `extra` acrescenta campos à linha. Existe para o allow de `escreve: true`
 * registrar SOB QUE isolamento a escrita foi aprovada: um log que diz "agente
 * que escreve rodou" sem dizer "isolado" não responde a pergunta pela qual ele
 * é evidência de primeira classe.
 */
function gravarDespacho(raiz, decisao, agente, estagio, sessao, motivo, escreveConferido, extra) {
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

    if (escreveConferido === false) {
      entrada.escreve_conferido = false;
    }

    if (extra && typeof extra === "object") {
      Object.assign(entrada, extra);
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

  // O estágio ativo é resolvido AQUI, antes da primeira negação possível, e a
  // ORDEM DAS DECISÕES não muda com isso: manifesto ausente continua negando
  // antes de qualquer outra coisa. O que muda é o log.
  //
  // Até 2026-09-02 toda negação anterior ao passo 4 gravava `estagio: "?"`,
  // porque o resolver só rodava depois. O log é evidência de primeira classe
  // (D4), e a linha que não diz em que estágio a sessão estava não responde a
  // pergunta para a qual ela existe — "quem rodou, quando, em qual estágio".
  // Medido no dia em que isto foi consertado: cinco negações de `executor`, em
  // duas sessões distintas, todas com `?`, e ninguém conseguia dizer pelo log
  // se o problema era o agente ou o estágio.
  //
  // `resolver` devolve null quando nenhum fluxo aberto casa com a branch, e
  // ESTOURA quando a instalação está quebrada (`scripts/estado.cjs` fora do
  // lugar, erro de sintaxe, I/O). Os dois negam, mas por motivos diferentes, e
  // aqui o erro é apenas GUARDADO — nunca engolido.
  //
  // A diferença não é cosmética. Antecipar esta resolução só para o log quase
  // custou a mensagem do caso 15 da bateria: com um `catch` que zerasse o
  // resultado, instalação quebrada passaria a negar dizendo "sem estágio ativo
  // — abra um fluxo", mandando consertar o que não estava errado. O erro sobe
  // no passo 4, onde a rede de `main` o transforma em exit 2 com "falha
  // interna", que é a mensagem que aponta para o conserto certo.
  let estResult = null;
  let estErro = null;
  try {
    estResult = require("./lib/estagio-ativo.cjs").resolver({ cwd: raiz });
  } catch (err) {
    estErro = err;
  }
  const estagioLog = (estResult && estResult.estagio) || "?";

  // Carrega manifesto (D3 passo 2: ausente ou inválido → nega)
  const manifestoPath = path.join(raiz, ".rainforest", "agentes.json");
  let manifesto;

  if (!fs.existsSync(manifestoPath)) {
    gravarDespacho(raiz, "deny", nomeAgente, estagioLog, sessao, "manifesto ausente");

    const branch = obterBranch(raiz);
    const outrosWorktrees = obterOutrosWorktreesComFluxoAberto(raiz);

    let msg = `Manifesto não encontrado em ${manifestoPath}\n`;
    msg += `  raiz lida: ${raiz}\n`;
    if (branch) {
      msg += `  branch: ${branch}\n`;
    }
    msg += `  estágio resolvido: ${estagioLog}\n`;

    if (outrosWorktrees.length > 0) {
      msg += formatarOutrosWorktreesAbertos(outrosWorktrees);
    }

    negar(msg.trim());
  }

  try {
    const brutoManifesto = fs.readFileSync(manifestoPath, "utf8");
    manifesto = JSON.parse(brutoManifesto);
  } catch {
    gravarDespacho(raiz, "deny", nomeAgente, estagioLog, sessao, "manifesto JSON inválido");
    negar("Manifesto JSON inválido");
  }

  // D3 passo 2b: validar versao e agentes (schema D2)
  if (manifesto.versao === undefined || manifesto.versao === null) {
    gravarDespacho(raiz, "deny", nomeAgente, estagioLog, sessao, "manifesto sem versao");
    negar("Manifesto sem versao");
  }

  if (manifesto.versao !== 1) {
    gravarDespacho(raiz, "deny", nomeAgente, estagioLog, sessao, `manifesto com versao desconhecida: ${manifesto.versao}`);
    negar(`Manifesto com versao desconhecida: ${manifesto.versao}`);
  }

  if (typeof manifesto.agentes !== "object" || manifesto.agentes === null || Array.isArray(manifesto.agentes)) {
    gravarDespacho(raiz, "deny", nomeAgente, estagioLog, sessao, "manifesto.agentes invalido");
    negar("Manifesto.agentes inválido");
  }

  // D3 passo 3: agente não declarado → nega
  if (!manifesto.agentes[nomeAgente]) {
    const motivo = `agente '${nomeAgente}' não consta no manifesto`;
    gravarDespacho(raiz, "deny", nomeAgente, estagioLog, sessao, motivo);
    negar(motivo);
  }

  const agentConfig = manifesto.agentes[nomeAgente];

  // D3 passo 4: sem estágio ativo → nega. `estResult` já foi resolvido acima,
  // para o log das negações anteriores; a decisão é a mesma de sempre.
  //
  // Resolver que estourou não é "sem estágio ativo". O erro foi só adiado até
  // aqui: sobe, e a rede de `main` o converte em exit 2 com "falha interna" —
  // fail-closed com o motivo certo.
  if (estErro) throw estErro;

  if (!estResult) {
    const motivo = "sem estágio ativo — abra um fluxo";
    gravarDespacho(raiz, "deny", nomeAgente, "?", sessao, motivo);

    const branch = obterBranch(raiz);
    const outrosWorktrees = obterOutrosWorktreesComFluxoAberto(raiz);

    let msg = `${motivo}\n`;
    msg += `  raiz lida: ${raiz}\n`;
    if (branch) {
      msg += `  branch: ${branch}\n`;
    }
    msg += `  estágio resolvido: ?\n`;

    if (outrosWorktrees.length > 0) {
      msg += formatarOutrosWorktreesAbertos(outrosWorktrees);
    }

    negar(msg.trim());
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

  // D3 passo 6: escreve: false com tools fora de allowlist → nega.
  //
  // `escreveConferido` existe por causa do critico 2 da rodada 4 da revisao: os
  // dois caminhos de "pular a checagem" (arquivo do agente ausente, ou presente
  // sem `tools:`) terminavam num allow byte a byte IGUAL ao de um agente que
  // passou pela checagem de verdade. Quem lesse o `despachos.jsonl` depois nao
  // tinha como distinguir "conferido e read-only" de "nao deu para conferir".
  //
  // Pular continua sendo o certo, e nao vira deny: em repositorio de CONSUMIDOR
  // do plugin nao existe `agents/` local — os agentes vem do cache do plugin —,
  // entao negar por arquivo ausente quebraria a portaria em todo repo que nao
  // seja este. E por isso que o `--lint` diverge de proposito: ele e local a
  // este repositorio, onde todo agente declarado TEM de ter arquivo, e ali a
  // ausencia e erro. A assimetria e desenho, o que estava errado era ela ser
  // invisivel.
  // `escreve` tem de ser BOOLEANO, e a checagem disso vem antes de tudo.
  //
  // Critico da rodada 5. `escreve === false` e igualdade estrita, e ate aqui
  // qualquer outro valor caia fora do `if` — a checagem de escrita inteira
  // desligava, e o allow saia SEM a marca `escreve_conferido`, byte a byte igual
  // ao de um agente conferido. Reproduzido: `"escreve": "false"` (string, o erro
  // de digitacao mais provavel em JSON escrito a mao) e `escreve` AUSENTE, os
  // dois liberando um agente cujo frontmatter declara `tools: Write, Edit, Bash`.
  // Reabria por outra porta exatamente o "allow que mentia" que a rodada 4
  // fechou — e sem nem a marca, que era o que tornava aquela porta auditavel.
  //
  // A regra e a mesma dos outros tres estados desta portaria: valor que nao da
  // para interpretar nao vira permissao. Nega, com motivo instrutivo.
  if (agentConfig.escreve !== false && agentConfig.escreve !== true) {
    const valor = JSON.stringify(agentConfig.escreve);
    const motivo =
      `agente '${nomeAgente}' tem 'escreve' ausente ou nao-booleano no manifesto (veio ${valor})` +
      ` — use o booleano false`;
    gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
    negar(motivo);
  }

  // `escreve: true` — o agente PODE escrever, e por isso a portaria exige aqui
  // a trava que torna isso aceitavel, em vez de negar de saida.
  //
  // Ate 2026-09-02 este ramo era um deny duro: o campo existia no schema (D2)
  // para que a excecao futura fosse uma linha de diff, mas o mecanismo que ela
  // exige nao estava implementado. O custo dessa espera foi medido, e nao era
  // o que se supunha. Com `executor`, `tester`, `documentador` e
  // `resolvedor-de-build` fora do manifesto, os tres agentes admitidos cobriam
  // `revisar`, `design` e `plano` — e NENHUM cobria `executar`. O estagio
  // inteiro ficou sem agente admitido, a regra 10 (que manda despachar toda
  // task mecanica no `executor`) ficou desligada, e nada dizia isso: duas
  // sessoes distintas bateram na parede antes de alguem somar as duas pontas.
  //
  // As duas condicoes abaixo nao sao invencao: sao as regras 11 e 10 escritas
  // em codigo, e as duas ja eram obrigatorias em prosa.
  //
  //   - regra 11: subagente que edita roda SEMPRE com `isolation: "worktree"`,
  //     nunca na arvore de trabalho do usuario.
  //   - regra 10: agente que edita NUNCA e nomeado. Nome sem worktree e a
  //     ilusao de isolamento — medido em 2026-08-08, um despacho com `name` E
  //     `isolation: "worktree"` rodou sem worktree nenhum (o meta do nomeado
  //     nao traz `worktreePath`) e commitou no checkout principal do usuario,
  //     enquanto o irmao sem nome, no mesmo despacho, foi isolado. Nomeado
  //     ainda troca entrega inline por `SendMessage`, e a entrega some.
  //
  // Os dois campos chegam em `tool_input` quando usados — esta medido em
  // `.rainforest/portaria/amostra-com-isolation.json`, e foi essa amostra que
  // tornou a checagem possivel. Ausencia e negacao: a portaria nao infere
  // isolamento que o payload nao afirma. E o que ela confere aqui e o PEDIDO,
  // nao o worktree em disco — o hook roda ANTES do despacho, e nesse instante
  // o worktree ainda nao existe. A conferencia do worktree real na volta e da
  // integracao (`scripts/conferir-entrega.cjs`), e continua sendo.
  if (agentConfig.escreve === true) {
    const isolamento = payload.tool_input.isolation;
    const nomeDado = payload.tool_input.name;

    if (isolamento !== "worktree") {
      const motivo =
        `agente '${nomeAgente}' declara 'escreve: true' e so roda com isolation: "worktree"` +
        ` (veio ${JSON.stringify(isolamento)}) — agente que edita nunca roda na arvore do usuario (regra 11)`;
      gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
      negar(motivo);
    }

    if (typeof nomeDado === "string" && nomeDado.trim() !== "") {
      const motivo =
        `agente '${nomeAgente}' declara 'escreve: true' e foi despachado com name: ${JSON.stringify(nomeDado)}` +
        ` — agente que edita nunca e nomeado (regra 10): nomeado vira teammate, o isolamento nao se aplica` +
        ` e a entrega para de voltar inline`;
      gravarDespacho(raiz, "deny", nomeAgente, estagioAtivo, sessao, motivo);
      negar(motivo);
    }

    // Allow conferido, e a linha diz SOB QUE isolamento — sem isso o log
    // registraria "agente que escreve rodou" sem registrar a unica coisa que
    // tornou aquilo admissivel.
    gravarDespacho(raiz, "allow", nomeAgente, estagioAtivo, sessao, null, undefined, {
      isolation: isolamento,
    });
    process.exit(0);
  }

  let escreveConferido = true;
  if (agentConfig.escreve === false) {
    const def = obterDefinicaoAgente(raiz, nomeAgente);
    if (!def) escreveConferido = false;

    if (def) {
      // Parse frontmatter para extrair tools (se declaradas)
      const fmMatch = def.match(/^---\n([\s\S]*?)\n---/);
      if (!fmMatch) escreveConferido = false; // arquivo sem frontmatter
      if (fmMatch) {
        const frontmatter = fmMatch[1];
        const { declarado, tools } = parseToolsDoFrontmatter(frontmatter);
        if (!declarado) escreveConferido = false; // sem `tools:` — nada a conferir

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
    // Se arquivo não encontrado, não falha — pula a checagem (D3 passo 6),
    // mas o allow sai MARCADO, e não indistinguível de um allow conferido.
  }

  // Passou tudo → aprova (D3 passo 7). `escreve_conferido: false` na linha do
  // log quando a checagem de escrita não pôde ser feita — o log é evidência de
  // primeira classe (D4), e evidência que não distingue "conferi" de "não deu
  // para conferir" afirma mais do que sabe.
  gravarDespacho(raiz, "allow", nomeAgente, estagioAtivo, sessao, null, escreveConferido);
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

  // Estagio VALIDO nao e a mesma coisa que estagio ALCANCAVEL. `arqueologia`
  // existe no grafo, mas o resolver de estagio ativo nunca o devolve — ele fica
  // fora da lista de "proximo" por desenho (senao todo projeto sem mapa ficaria
  // eternamente em "proximo: arqueologia" e o estagio opcional viraria
  // obrigatorio pela porta dos fundos; ver hooks/lib/estagio-ativo.cjs). Agente
  // restrito so a ele e indespachavel, e o lint tem de dizer isso.
  const ESTAGIOS_ALCANCAVEIS = new Set(
    [...estadioValidos].filter((e) => e !== "arqueologia")
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

    // Checagem 4b: a FORMA de `estagios`. Aviso 3 da rodada 5 — o lint aprovava
    // manifesto que o runtime nega sempre, e o dev que confia num `--lint` verde
    // (o gate que roda no `plano`) publicava agente indespachavel sem aviso.
    if (config && !Array.isArray(config.estagios)) {
      console.error(`erro: agente '${nome}' tem 'estagios' ausente ou que nao e lista — o runtime nega todo despacho dele`);
      erros++;
    } else if (config && config.estagios.length === 0) {
      console.error(`erro: agente '${nome}' tem 'estagios' vazio — nunca podera ser despachado`);
      erros++;
    } else if (config && config.estagios.every((e) => !ESTAGIOS_ALCANCAVEIS.has(e))) {
      // `arqueologia` e estagio de verdade, mas o resolver NUNCA o devolve como
      // ativo (fica fora da lista de proximo por desenho, senao todo projeto sem
      // mapa ficaria eternamente em "proximo: arqueologia"). Agente restrito so
      // a ele passa no lint e nega em runtime, sempre. Aviso, nao erro: o
      // manifesto nao esta malformado, esta inutil.
      console.error(
        `aviso: agente '${nome}' so declara estagio(s) que nunca ficam ativos ` +
        `(${config.estagios.join(", ")}) — o runtime vai negar todo despacho dele`
      );
      avisos++;
    }

    // Checagem 4d: entrada que não é objeto. `"agente": null` (ou string, ou
    // número) passava calada no lint e era negada para sempre em runtime, porque
    // `!manifesto.agentes[nome]` trata `null` como "não declarado". Buraco de
    // aviso apontado na rodada 6, mesma família do "só arqueologia": o manifesto
    // não está malformado o bastante para o runtime reclamar, mas o agente
    // nunca roda e ninguém avisa.
    if (!config || typeof config !== "object" || Array.isArray(config)) {
      console.error(
        `erro: agente '${nome}' nao tem objeto de configuracao no manifesto ` +
        `(veio ${JSON.stringify(config)}) — o runtime nega todo despacho dele`
      );
      erros++;
      continue;
    }

    // Checagem 4c: `escreve` tem de ser booleano — critico da rodada 5. Sem
    // isto, `"escreve": "false"` (string) desligava a checagem 3 inteira e o
    // lint saia 0, do mesmo jeito que o runtime liberava.
    if (config && config.escreve !== false && config.escreve !== true) {
      console.error(
        `erro: agente '${nome}' tem 'escreve' ausente ou nao-booleano ` +
        `(veio ${JSON.stringify(config.escreve)}) — use o booleano false`
      );
      erros++;
    } else if (config && config.escreve === true) {
      // `escreve: true` e valido desde 2026-09-02, mas o lint NAO consegue
      // conferir a trava dele: ela mora no payload do despacho (isolation +
      // name), que so existe em runtime. Dizer isso em voz alta e a mesma
      // licao do `escreve_conferido` — a assimetria entre o que se confere e o
      // que se pula e desenho; o defeito e ela ser invisivel. Aviso, nao erro:
      // o manifesto esta correto, o lint e que nao alcanca.
      console.error(
        `aviso: agente '${nome}' declara 'escreve: true' — o lint nao ve isolamento; ` +
        `a trava (isolation: "worktree" e despacho sem name) e conferida so em runtime`
      );
      avisos++;
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
    /* Falha interna da portaria NEGA. Não crasha.
     *
     * Crítico da rodada 6 da revisão, e o erro era de raciocínio, não de
     * digitação: a rodada 5 tirou o fallback do resolver com o argumento de que
     * "se o estado.cjs não carregar, o certo é estourar alto e agora, porque a
     * portaria é fail-closed". Estourar alto ela estoura — e ABRE.
     *
     * O contrato de hook do Claude Code é o que a própria casa já tinha escrito
     * (README, tabela de travas mecânicas): **exit 2 barra**. Exit 0 passa, e
     * qualquer outro código — 1 inclusive, que é o que uma exceção não tratada
     * produz — é erro NÃO-BLOQUEANTE: o harness mostra o erro e a tool call
     * SEGUE. Reproduzido: com `scripts/estado.cjs` fora do lugar, o hook saía 1
     * com stack trace do Node, sem chamar `negar()` e sem gravar linha nenhuma
     * no log — despacho aprovado em silêncio, sem passar por nenhuma das
     * checagens que este arquivo inteiro existe para fazer.
     *
     * Era estritamente pior que o estado anterior: a versão com fallback nunca
     * crashava, sempre chegava a uma decisão. Trocar "fallback sem teste" por
     * "sem fallback e crashante" fechou um risco e abriu um maior.
     *
     * Por isso a rede fica AQUI, no topo, e não em try/catch espalhado: qualquer
     * exceção que escape de `main()` — require quebrado, arquivo corrompido,
     * bug futuro neste arquivo — vira exit 2 com motivo. Se a portaria não
     * consegue decidir, admitir é exatamente a falha que ela existe para impedir.
     *
     * A saída de emergência não é variável de ambiente (isso seria a exceção em
     * runtime que o D1 proíbe): é tirar o bloco do `.claude/settings.json`, que
     * é arquivo versionado e passa pelo `revisar` — a mesma porta do manifesto.
     */
    /* A rede é síncrona, e por isso não basta sozinha.
     *
     * Auditoria externa (codex-cli, gpt-5.6-sol, 2026-09-01 — segunda família de
     * modelo, pedida justamente porque o defeito da rodada 6 foi erro de
     * raciocínio sobre contrato de plataforma, o tipo de viés que um revisor da
     * mesma família tende a repetir): o `try/catch` pega exceção SÍNCRONA que
     * escape de `main()`. Não pega `unhandledRejection` nem throw dentro de
     * callback/timer — os dois derrubam o processo com exit 1, que é o mesmo
     * fail-open de antes. `main()` é síncrono hoje; os handlers abaixo existem
     * para que ele possa deixar de ser sem reabrir o buraco.
     */
    const negarPorFalhaInterna = (origem, err) => {
      const detalhe = (err && err.message) ? err.message : String(err);
      process.stderr.write(
        `portaria: falha interna (${origem}), e por isso o despacho foi NEGADO — ${detalhe}\n` +
        `a portaria nega quando nao consegue decidir; crashar deixaria o despacho passar.\n` +
        `para destravar: conserte o erro acima, ou tire o bloco da portaria do .claude/settings.json.\n`
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
}
