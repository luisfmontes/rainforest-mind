#!/usr/bin/env node
/**
 * Limpar worktrees — lista os registrados e os do disco, classifica cada um
 * por confinamento e estado, e remove apenas os que estão limpos.
 *
 * Uso:
 *   node scripts/limpar-worktrees.cjs [--raiz <repo>] [--remover]
 *   node scripts/limpar-worktrees.cjs --remover-sujo <dir> --confirmo "<frase>"
 *
 * Comportamento:
 *   - Sem flags: lista o status de cada worktree (limpo, sujo, órfão), exit 0
 *   - Com --remover: remove os classificados como "limpo" via git worktree remove
 *     — "sujo" NUNCA entra aqui, com ou sem --confirmo
 *   - Com --remover-sujo <dir>: remove UM worktree classificado "sujo", e só
 *     com --confirmo "CONFIRMO apagar worktree sujo <caminho>", onde <caminho>
 *     é o mesmo que `git worktree list` imprime para aquele worktree. A frase
 *     é digitada pelo usuário e repassada verbatim — o script não a inventa.
 *     Sem a frase, ou com frase de outro caminho: exit 2, nada é removido.
 *
 * Classificação:
 *   - "limpo": toplevel DE DENTRO confere com o próprio dir E status vazio
 *   - "sujo": toplevel confere com o dir, mas há alterações
 *   - "órfão": diretório sem .git próprio (toplevel do pai)
 *   - "fantasma-travado": registro travado em git worktree list, mas diretório ausente
 */

const { spawnSync, execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

// Importa o helper de confinamento da Tarefa 1
const { toplevelConfinado } = require("../hooks/lib/cwd-efetivo.cjs");
const { resolver } = require("../hooks/lib/estagio-ativo.cjs");
const { resolverRaiz: resolverRaizDados } = require("../hooks/lib/raiz.cjs");

/**
 * O worktree tem agente registrado em voo?
 *
 * "Limpo" quer dizer "sem alteração pendente", e um agente que acabou de
 * commitar deixa o worktree dele exatamente assim — ainda trabalhando. Sem
 * esta consulta, `--remover` apagava por baixo de quem estava no meio da
 * tarefa, e o registro de `em_voo` (D16) existe justamente para responder
 * "tem alguém aí dentro?" sem depender de heurística de mtime ou de processo.
 *
 * Devolve `null` quando não há fluxo aberto, quando o estado é ilegível, ou
 * quando `em_voo` está vazio — nenhum desses casos segura a remoção.
 */
function agentesEmVoo(dir) {
  try {
    const ativo = resolver({ cwd: dir });
    if (!ativo || !ativo.slug) return null;
    const caminho = path.join(dir, "docs", "rainforest", "estado", `${ativo.slug}.json`);
    const estado = JSON.parse(fs.readFileSync(caminho, "utf8"));
    const bloco = estado[ativo.estagio];
    const voo = bloco && typeof bloco === "object" && Array.isArray(bloco.em_voo)
      ? bloco.em_voo.filter((a) => a && typeof a === "object" && a.agente)
      : [];
    return voo.length ? { slug: ativo.slug, estagio: ativo.estagio, voo } : null;
  } catch {
    return null;
  }
}

/**
 * Detecta se um worktree está sendo usado por uma sessão viva (outra que não esta).
 * Lê sessoes.json da raiz de dados (RFM_ROOT ou ~/.rainforest etc).
 * Uma sessão é viva se seu timestamp (prompt_ts ou stop_ts, o maior) for mais recente
 * que 5 horas atrás.
 *
 * @param {string} dir - Diretório do worktree
 * @param {string} [raizDados] - Raiz de dados (default: resolve automaticamente)
 * @returns {boolean} - true se há sessão viva com cwd normalizado igual ao do worktree
 */
function temSessaoViva(dir, raizDados) {
  try {
    // Resolve a raiz de dados se não foi passada
    const raiz = raizDados || resolverRaizDados().raiz;
    if (!raiz) return false;

    const caminhoSessoes = path.join(raiz, 'sessoes.json');
    if (!fs.existsSync(caminhoSessoes)) return false;

    const sessoes = JSON.parse(fs.readFileSync(caminhoSessoes, 'utf8'));
    if (!sessoes || typeof sessoes !== 'object') return false;

    const agora = Date.now();
    const limiarIdade = 5 * 3600 * 1000; // 5 horas em ms
    const dirNormalizado = normalizarCaminho(dir);

    for (const [sessionId, sessao] of Object.entries(sessoes)) {
      if (!sessao || typeof sessao !== 'object') continue;

      // Determina o timestamp mais recente (prompt ou stop)
      const ultimaAtividade = Math.max(
        sessao.prompt_ts || 0,
        sessao.stop_ts || 0
      );

      // Sessão é viva se mais recente que 5 horas atrás
      if (agora - ultimaAtividade < limiarIdade) {
        // Normaliza o cwd da sessão
        const cwdSessao = sessao.cwd;
        if (cwdSessao) {
          const cwdNormalizado = normalizarCaminho(cwdSessao);
          if (cwdNormalizado === dirNormalizado) {
            return true;
          }
        }
      }
    }

    return false;
  } catch {
    return false;
  }
}

// Argumentos
const tem = (nome) => process.argv.includes(`--${nome}`);
const argValor = (nome) => {
  const i = process.argv.indexOf(`--${nome}`);
  return i === -1 ? null : process.argv[i + 1] || null;
};

const raizArgumento = argValor("raiz");
const remover = tem("remover");
const removerSujoArg = argValor("remover-sujo");

/**
 * Resolve a raiz do repositório.
 * Se --raiz for passado, usa esse. Senão, tenta git rev-parse --show-toplevel.
 */
function resolverRaiz() {
  if (raizArgumento) {
    // Validar se existe e é um diretório
    try {
      const stat = fs.statSync(raizArgumento);
      if (stat.isDirectory()) {
        return raizArgumento;
      }
    } catch {
      console.error(`erro: --raiz '${raizArgumento}' não é um diretório`);
      process.exit(1);
    }
  }

  // Tenta git rev-parse --show-toplevel no cwd atual
  try {
    const result = execFileSync("git", ["rev-parse", "--show-toplevel"], {
      cwd: process.cwd(),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (result) {
      return result;
    }
  } catch {
    // Fallthrough
  }

  console.error("erro: não consegui descobrir a raiz do repositório");
  console.error("       use --raiz <repo> ou rode dentro de um repositório git");
  process.exit(1);
}

/**
 * Normaliza um caminho para comparação robusta entre separadores
 * (`/` vs `\`) e variação de caixa de letra de drive no Windows.
 * Prefere `realpath` nativo (resolve symlink e caixa real do disco);
 * cai para `path.resolve` + lowercase (no Windows) se o caminho não existir.
 */
function normalizarCaminho(p) {
  try {
    return fs.realpathSync.native(p);
  } catch {
    const resolvido = path.resolve(p);
    return process.platform === "win32" ? resolvido.toLowerCase() : resolvido;
  }
}

/**
 * Detecta worktrees travados cujo diretório sumiu do disco (fantasma-travado).
 * Retorna um mapa de caminho normalizado → true se fantasma-travado.
 */
function detectarFantasmaTravado(raiz) {
  const fantasmas = new Map();
  try {
    const output = execFileSync("git", ["worktree", "list", "--porcelain"], {
      cwd: raiz,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });

    const raizNormalizada = normalizarCaminho(raiz);
    const linhas = output.split("\n");
    let caminhoAtual = null;
    let temLocked = false;

    for (const linha of linhas) {
      if (linha.startsWith("worktree ")) {
        caminhoAtual = linha.slice("worktree ".length).trim();
        temLocked = false;
      } else if (linha.startsWith("locked")) {
        temLocked = true;
      } else if (caminhoAtual && linha === "") {
        // Fim da entrada do worktree
        if (
          temLocked &&
          normalizarCaminho(caminhoAtual) !== raizNormalizada &&
          !fs.existsSync(caminhoAtual)
        ) {
          fantasmas.set(normalizarCaminho(caminhoAtual), true);
        }
        caminhoAtual = null;
        temLocked = false;
      }
    }

    // Última entrada (sem linha vazia de encerramento)
    if (
      caminhoAtual &&
      temLocked &&
      normalizarCaminho(caminhoAtual) !== raizNormalizada &&
      !fs.existsSync(caminhoAtual)
    ) {
      fantasmas.set(normalizarCaminho(caminhoAtual), true);
    }
  } catch {
    // Fallthrough
  }

  return fantasmas;
}

/**
 * O caminho de um worktree exatamente como `git worktree list` (e o
 * `--porcelain`, que usa o mesmo texto de caminho) o imprime — absoluto, com
 * `/` mesmo no Windows. É esse texto, não o `path.resolve` do resto do
 * script (que troca para `\` no Windows), que entra na frase de confirmação:
 * quem digita `--confirmo` está lendo a saída do git, não a da tabela.
 * Devolve `null` se não achar um worktree cujo caminho normalizado bata com
 * `alvoNormalizado`.
 */
function caminhoConformeGitWorktreeList(raiz, alvoNormalizado) {
  try {
    const saida = execFileSync("git", ["worktree", "list", "--porcelain"], {
      cwd: raiz,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    for (const linha of saida.split("\n")) {
      if (!linha.startsWith("worktree ")) continue;
      const caminho = linha.slice("worktree ".length).trim();
      if (caminho && normalizarCaminho(caminho) === alvoNormalizado) return caminho;
    }
  } catch {
    // Fallthrough — devolve null
  }
  return null;
}

/**
 * Lista os worktrees registrados em `git worktree list --porcelain`.
 * Retorna array de caminhos (sem a raiz principal, que é o repositório em si).
 */
function listarWorktreesRegistrados(raiz) {
  try {
    const output = execFileSync("git", ["worktree", "list", "--porcelain"], {
      cwd: raiz,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });

    const raizNormalizada = normalizarCaminho(raiz);
    // Rodando de DENTRO de um worktree, a raiz é o worktree e o checkout
    // principal vira "mais um da lista". Ele nunca é candidato: o git recusa
    // remover o principal, e listar dá a impressão de que ele é removível.
    const principal = checkoutPrincipal(raiz);
    const principalNormalizado = principal ? normalizarCaminho(principal) : null;
    const caminhos = [];
    const linhas = output.split("\n");
    for (const linha of linhas) {
      if (linha.startsWith("worktree ")) {
        const caminho = linha.slice("worktree ".length).trim();
        // Nunca inclui a raiz principal (compara normalizado, não string crua:
        // git porcelain sempre usa "/", --raiz pode chegar com "\")
        const normalizado = normalizarCaminho(caminho);
        if (
          normalizado !== raizNormalizada &&
          normalizado !== principalNormalizado
        ) {
          caminhos.push(caminho);
        }
      }
    }
    return caminhos;
  } catch {
    return [];
  }
}

/**
 * Descobre as pastas que de fato guardam worktree deste repositório.
 *
 * A pasta de um worktree registrado continua valendo — worktree não é obrigado
 * a morar em `.claude/worktrees`, e a bateria cobre o layout `<repo>-worktrees`.
 * O que NÃO pode entrar é a pasta que guarda o checkout principal.
 *
 * Rodado de DENTRO de um worktree, `raiz` é o worktree e o checkout principal
 * aparece como "mais um registrado"; o dirname dele é a pasta que guarda TODOS
 * os projetos do usuário. Medido em 2026-09-08 nesta máquina: o `--remover`
 * chegou a disparar `git worktree remove` contra cinco repositórios alheios
 * (`segundo-cerebro`, `whatsapp-mcp`, três `tech-challenge-*`). Só não apagou
 * nada porque o git recusa ("is not a working tree") — sorte, não desenho:
 * bastava um deles ser worktree deste repo para sumir.
 *
 * Duas travas, então: o principal sai de `registrados`
 * (`listarWorktreesRegistrados`), e a pasta dele é recusada aqui mesmo se
 * chegar por outro caminho.
 */
function pastasDeWorktree(raiz, registrados) {
  const pastas = new Set();
  const principal = checkoutPrincipal(raiz);
  const pastaDoPrincipal = principal
    ? normalizarCaminho(path.dirname(principal))
    : null;

  const aceitar = (dir) => {
    if (!dir) return;
    const normalizado = normalizarCaminho(dir);
    // A pasta que guarda o checkout principal guarda os outros projetos junto.
    if (normalizado === pastaDoPrincipal) return;
    // `.git/worktrees` NÃO é pasta de worktree: é o diretório administrativo do
    // git, um subdiretório por worktree registrado, sem checkout nenhum dentro.
    // Varrê-lo faz cada worktree VIVO aparecer duas vezes na tabela, a segunda
    // como "órfão".
    if (normalizado.split("/").includes(".git")) return;
    if (!fs.existsSync(dir)) return;
    pastas.add(normalizado);
  };

  // A pasta padrão da raiz de onde o script está rodando.
  aceitar(path.join(raiz, ".claude", "worktrees"));

  // E a do checkout PRINCIPAL, que pode não ser a raiz: rodando de dentro de
  // um worktree, é lá que moram os irmãos.
  if (principal) {
    aceitar(path.join(principal, ".claude", "worktrees"));
  }

  // Worktree registrado fora do padrão ainda conta — a pasta dele entra.
  for (const wt of registrados) {
    aceitar(path.dirname(wt));
  }

  return [...pastas];
}

/**
 * O caminho do checkout principal, deduzido do git-common-dir (que aponta para
 * o `.git` dele mesmo quando estamos dentro de um worktree). Devolve null se
 * não der para medir — e quem chama trata isso como "não sei", nunca como
 * "não tem".
 */
function checkoutPrincipal(raiz) {
  try {
    const saida = execFileSync(
      "git",
      ["rev-parse", "--path-format=absolute", "--git-common-dir"],
      { cwd: raiz, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    if (!saida) return null;
    // <principal>/.git  ->  <principal>
    if (path.basename(saida) === ".git") return path.dirname(saida);
    return null;
  } catch {
    return null;
  }
}

/**
 * Lista os diretórios que estão dentro das pastas de worktree do repositório.
 */
function listarWorktreesDoDisco(raiz, registrados) {
  const achados = [];
  for (const pasta of pastasDeWorktree(raiz, registrados)) {
    try {
      const itens = fs.readdirSync(pasta, { withFileTypes: true });
      for (const item of itens) {
        if (item.isDirectory()) achados.push(path.join(pasta, item.name));
      }
    } catch {
      // Pasta que sumiu entre o existsSync e o readdir: segue.
    }
  }
  return achados;
}

/**
 * Classifica um diretório como "limpo", "sujo", "órfão" ou "fantasma-travado".
 *
 * - "limpo": toplevel DE DENTRO bate com o dir E status vazio
 * - "sujo": toplevel bate com o dir, mas há sujeira
 * - "órfão": toplevel não bate com o dir (sem .git próprio)
 * - "fantasma-travado": registro travado com diretório ausente
 */
function classificar(dir, fantasmas) {
  // Se é um fantasma-travado, retorna logo
  if (fantasmas && fantasmas.has(normalizarCaminho(dir))) {
    return {
      status: "fantasma-travado",
      detalhes: "registro travado, diretório ausente",
    };
  }

  // Verifica se é um worktree de uma sessão viva (outra janela)
  const sessaoViva = temSessaoViva(dir);
  if (sessaoViva) return 'de-outra-sessao';

  const confinado = toplevelConfinado(dir);

  if (!confinado.ok) {
    return {
      status: "órfão",
      detalhes: "toplevel não bate com o diretório",
    };
  }

  // Confinado: verifica se está limpo
  try {
    const porcelain = execFileSync("git", ["status", "--porcelain"], {
      cwd: dir,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();

    // S2 (8a revisao, rodada 10, lote 3, 2026-09-03): a lista de exclusao que
    // existia aqui ("arquivos especiais do worktree": HEAD, ORIG_HEAD,
    // commondir, gitdir, index, logs/) partia de uma premissa falsa — esses
    // nomes vivem em `.git/worktrees/<nome>/`, nunca na arvore de trabalho,
    // entao o `git status --porcelain` NUNCA os lista por serem especiais.
    // Reproduzido na caixa: worktree recem-criado tem porcelain vazio; um
    // `logs/app.log` NAO RASTREADO real produz a linha `?? logs/` — que essa
    // lista filtrava, classificando o worktree como "limpo" e deixando
    // `--remover` apagar o log de verdade. Um arquivo `index` na raiz sofria
    // o mesmo. Qualquer linha do porcelain e sujeira — sem excecao.
    const linhas = porcelain.split("\n").filter((linha) => linha.length > 0);

    if (linhas.length === 0) {
      return {
        status: "limpo",
        detalhes: "",
      };
    } else {
      return {
        status: "sujo",
        detalhes: `${linhas.length} alterações`,
      };
    }
  } catch {
    return {
      status: "erro",
      detalhes: "não consegui ler status",
    };
  }
}

/**
 * Imprime tabela formatada.
 */
function imprimirTabela(dados) {
  if (dados.length === 0) {
    console.log("nenhum worktree encontrado");
    return;
  }

  // Calcula larguras de coluna
  let maxCaminhoLen = "Caminho".length;
  let maxStatusLen = "Status".length;

  for (const item of dados) {
    maxCaminhoLen = Math.max(maxCaminhoLen, item.caminho.length);
    maxStatusLen = Math.max(maxStatusLen, item.classificacao.status.length);
  }

  // Cabeçalho
  console.log(
    "Caminho".padEnd(maxCaminhoLen + 2) +
      "Status".padEnd(maxStatusLen + 2) +
      "Detalhes"
  );
  console.log(
    "-".repeat(maxCaminhoLen + 2) +
      "-".repeat(maxStatusLen + 2) +
      "-".repeat(40)
  );

  // Linhas
  for (const item of dados) {
    console.log(
      item.caminho.padEnd(maxCaminhoLen + 2) +
        item.classificacao.status.padEnd(maxStatusLen + 2) +
        (item.classificacao.detalhes || "")
    );
  }
}

/**
 * Executa remoção (para "limpo" e "fantasma-travado").
 */
function executarRemocao(raiz, dadosLimpos) {
  if (dadosLimpos.length === 0) {
    console.log("nenhum worktree limpo para remover");
    return;
  }

  for (const item of dadosLimpos) {
    const classe = item.classificacao.status;

    // Worktree com agente em voo não é candidato a remoção, por mais limpo que
    // esteja: agente que acabou de commitar deixa a árvore limpa e continua
    // trabalhando. O aviso nomeia quem está lá dentro, para quem roda decidir.
    const emVoo = agentesEmVoo(item.caminhoOriginal);
    if (emVoo) {
      const nomes = emVoo.voo.map((a) => a.agente).join(", ");
      // A mensagem irmã, em `hooks/gate-agente-em-voo.cjs`, imprime o comando de
      // baixa; esta não imprimia, e quem só via esta saída não sabia destravar.
      // Assimetria apontada na revisão de 2026-09-05.
      console.log(
        `pulando ${item.caminho}: o estágio '${emVoo.estagio}' do fluxo ` +
          `'${emVoo.slug}' tem ${emVoo.voo.length} agente(s) em voo (${nomes})`
      );
      console.log(
        `  se o agente já voltou, dê a baixa antes de limpar:\n` +
          `  node scripts/estado.cjs marcar --slug ${emVoo.slug} ` +
          `--estagio ${emVoo.estagio} --status parcial --json '{"em_voo":[]}'`
      );
      continue;
    }

    if (classe === "fantasma-travado" && remover) {
      // Fantasma-travado: destrava, remove e poda.
      //
      // `git worktree lock` também é o mecanismo que o próprio git recomenda
      // para worktree em mídia removível ou de rede, e mídia desmontada tem
      // exatamente esta forma — travado, diretório ausente. O aviso abaixo
      // nomeia essa possibilidade: o que se destrói aqui é o vínculo
      // administrativo do git, não os arquivos, mas quem roda merece saber
      // qual das duas coisas está vendo.
      console.log(
        `aviso: ${item.caminho} está travado com o diretório ausente. Se for ` +
          `mídia removível ou de rede apenas desmontada, monte antes de seguir.`
      );
      console.log(`destravando ${item.caminho}...`);
      const unlockResult = spawnSync("git", ["worktree", "unlock", item.caminhoOriginal], {
        cwd: raiz,
        encoding: "utf8",
      });
      if (unlockResult.status !== 0) {
        console.error(
          `erro ao destravar ${item.caminho}: ${unlockResult.stderr || ""}`
        );
        continue;
      }

      console.log(`removendo ${item.caminho}...`);
      const removeResult = spawnSync("git", ["worktree", "remove", "--force", item.caminhoOriginal], {
        cwd: raiz,
        encoding: "utf8",
      });
      if (removeResult.status !== 0) {
        console.error(
          `erro ao remover ${item.caminho}: ${removeResult.stderr || ""}`
        );
        continue;
      }

      console.log(`podando worktrees...`);
      const pruneResult = spawnSync("git", ["worktree", "prune"], {
        cwd: raiz,
        encoding: "utf8",
      });
      if (pruneResult.status !== 0) {
        console.error(
          `aviso: falha ao podar ${item.caminho}: ${pruneResult.stderr || ""}`
        );
      }
    } else {
      console.log(`removendo ${item.caminho}...`);
      // S2 (8a revisao, rodada 10, lote 3, 2026-09-03): `--force` existia "para
      // eliminar os arquivos especiais do worktree" — premissa que a lista de
      // exclusao de `classificar()` carregava e que a caixa desmentiu (esses
      // nomes nunca aparecem no porcelain da arvore de trabalho). Sem a lista,
      // só chega aqui um worktree de verdade LIMPO (porcelain vazio); `git
      // worktree remove` sem `--force` funciona nesse caso (confirmado na
      // caixa) — e sem `--force` a remoção nunca apaga sujeira por engano.
      const result = spawnSync("git", ["worktree", "remove", item.caminhoOriginal], {
        cwd: raiz,
        encoding: "utf8",
      });

      if (result.status !== 0) {
        console.error(
          `aviso: falha ao remover ${item.caminho}: ${result.stderr || ""}`
        );
      }
    }
  }
}

/**
 * Main.
 */
function main() {
  const raiz = resolverRaiz();

  // Detecta fantasmas-travados antes de listar tudo
  const fantasmas = detectarFantasmaTravado(raiz);

  // Lista worktrees (registrados + disco)
  let registrados = listarWorktreesRegistrados(raiz);
  let doDisco = listarWorktreesDoDisco(raiz, registrados);

  // Normaliza caminhos para evitar duplicação (POSIX vs Windows)
  registrados = registrados.map((p) => path.resolve(p));
  doDisco = doDisco.map((p) => path.resolve(p));

  // Combina e deduplica
  const todosUnicos = new Set([...registrados, ...doDisco]);
  const todos = Array.from(todosUnicos).sort();

  // Classifica cada um, mantendo o caminho original (não normalizado)
  const dados = [];
  const mapNormalizado = new Map();

  // Cria mapa de normalizado -> original para poder recuperar o caminho original
  for (const p of registrados) {
    mapNormalizado.set(path.resolve(p), p);
  }
  for (const p of doDisco) {
    if (!mapNormalizado.has(path.resolve(p))) {
      mapNormalizado.set(path.resolve(p), p);
    }
  }

  for (const dir of todos) {
    let classificacao = classificar(dir, fantasmas);
    // Converte string em objeto se necessário
    if (typeof classificacao === 'string') {
      classificacao = {
        status: classificacao,
        detalhes: "sessão viva está usando este worktree",
      };
    }
    const caminhoOriginal = mapNormalizado.get(dir) || dir;
    dados.push({
      caminho: dir,
      caminhoOriginal,
      classificacao,
    });
  }

  // Imprime tabela
  imprimirTabela(dados);

  // Se --remover, remove os limpos e fantasmas-travados — "sujo" NUNCA entra
  // aqui, com ou sem --confirmo. Só --remover-sujo alcança "sujo".
  if (remover) {
    const removiveis = dados.filter((item) =>
      item.classificacao.status === "limpo" || item.classificacao.status === "fantasma-travado"
    );
    if (removiveis.length > 0) {
      console.log("");
      executarRemocao(raiz, removiveis);
    }
  }

  // --remover-sujo <dir>: remove UM worktree "sujo", só com a frase exata.
  if (removerSujoArg) {
    const alvoNormalizado = normalizarCaminho(removerSujoArg);
    const item = dados.find(
      (d) =>
        normalizarCaminho(d.caminhoOriginal) === alvoNormalizado ||
        normalizarCaminho(d.caminho) === alvoNormalizado
    );

    if (!item) {
      console.error(`erro: nao achei worktree '${removerSujoArg}' na listagem`);
      process.exit(1);
    }

    if (item.classificacao.status !== "sujo") {
      console.error(
        `erro: worktree '${removerSujoArg}' nao esta classificado como sujo ` +
          `(esta '${item.classificacao.status}')`
      );
      process.exit(1);
    }

    const caminhoGit =
      caminhoConformeGitWorktreeList(raiz, alvoNormalizado) || item.caminhoOriginal;
    const esperada = `CONFIRMO apagar worktree sujo ${caminhoGit}`;
    const frase = argValor("confirmo");

    if (frase !== esperada) {
      console.log("CONFIRMACAO NECESSARIA");
      console.log("");
      console.log(esperada);
      console.log("");
      console.log(
        "Essa frase precisa ser digitada pelo usuario e repassada verbatim para " +
          "--confirmo. O script nao a inventa."
      );
      process.exit(2);
    }

    // Mesma trava do --remover normal: agente em voo segura a remoção, por
    // mais que o alvo já esteja confirmado.
    const emVoo = agentesEmVoo(item.caminhoOriginal);
    if (emVoo) {
      const nomes = emVoo.voo.map((a) => a.agente).join(", ");
      console.log(
        `pulando ${item.caminho}: o estágio '${emVoo.estagio}' do fluxo ` +
          `'${emVoo.slug}' tem ${emVoo.voo.length} agente(s) em voo (${nomes})`
      );
      process.exit(1);
    }

    console.log(`removendo ${item.caminho} (sujo, confirmado)...`);
    const result = spawnSync("git", ["worktree", "remove", "--force", item.caminhoOriginal], {
      cwd: raiz,
      encoding: "utf8",
    });
    if (result.status !== 0) {
      console.error(`erro ao remover ${item.caminho}: ${result.stderr || ""}`);
      process.exit(1);
    }
    console.log(`ok removido: ${item.caminho}`);
  }

  process.exit(0);
}

main();
