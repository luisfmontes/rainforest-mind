#!/usr/bin/env node
/**
 * Limpar worktrees — lista os registrados e os do disco, classifica cada um
 * por confinamento e estado, e remove apenas os que estão limpos.
 *
 * Uso:
 *   node scripts/limpar-worktrees.cjs [--raiz <repo>] [--remover]
 *
 * Comportamento:
 *   - Sem flags: lista o status de cada worktree (limpo, sujo, órfão), exit 0
 *   - Com --remover: remove os classificados como "limpo" via git worktree remove
 *
 * Classificação:
 *   - "limpo": toplevel DE DENTRO confere com o próprio dir E status vazio
 *   - "sujo": toplevel confere com o dir, mas há alterações
 *   - "órfão": diretório sem .git próprio (toplevel do pai)
 */

const { spawnSync, execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

// Importa o helper de confinamento da Tarefa 1
const { toplevelConfinado } = require("../hooks/lib/cwd-efetivo.cjs");

// Argumentos
const tem = (nome) => process.argv.includes(`--${nome}`);
const argValor = (nome) => {
  const i = process.argv.indexOf(`--${nome}`);
  return i === -1 ? null : process.argv[i + 1] || null;
};

const raizArgumento = argValor("raiz");
const remover = tem("remover");

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

    const caminhos = [];
    const linhas = output.split("\n");
    for (const linha of linhas) {
      if (linha.startsWith("worktree ")) {
        const caminho = linha.slice("worktree ".length).trim();
        // Nunca inclui a raiz principal
        if (caminho !== raiz) {
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
 * Lista os diretórios do disco, inferindo a pasta padrão de worktrees
 * a partir do primeiro worktree registrado.
 */
function listarWorktreesDoDisco(raiz, registrados) {
  // Se não há worktrees registrados, tenta as pastas padrão
  if (registrados.length === 0) {
    const padroes = [
      path.join(raiz, ".claude", "worktrees"),
      path.join(raiz, ".git", "worktrees"),
    ];

    for (const padrao of padroes) {
      try {
        if (fs.existsSync(padrao)) {
          const itens = fs.readdirSync(padrao, { withFileTypes: true });
          const dirs = itens
            .filter((item) => item.isDirectory())
            .map((item) => path.join(padrao, item.name));
          return dirs;
        }
      } catch {
        // Continua
      }
    }
    return [];
  }

  // Extrai o pai do primeiro worktree registrado
  const primeiroWorktree = registrados[0];
  const paiDoWorktree = path.dirname(primeiroWorktree);

  // Lista todos os diretórios nesse pai
  try {
    if (fs.existsSync(paiDoWorktree)) {
      const itens = fs.readdirSync(paiDoWorktree, { withFileTypes: true });
      const dirs = itens
        .filter((item) => item.isDirectory())
        .map((item) => path.join(paiDoWorktree, item.name));
      return dirs;
    }
  } catch {
    // Fallthrough
  }

  return [];
}

/**
 * Classifica um diretório como "limpo", "sujo" ou "órfão".
 *
 * - "limpo": toplevel DE DENTRO bate com o dir E status vazio
 * - "sujo": toplevel bate com o dir, mas há sujeira
 * - "órfão": toplevel não bata com o dir (sem .git próprio)
 */
function classificar(dir) {
  const confinado = toplevelConfinado(dir);

  if (!confinado.ok) {
    return {
      status: "órfão",
      detalhes: "toplevel não bata com o diretório",
    };
  }

  // Confinado: verifica se está limpo
  try {
    const porcelain = execFileSync("git", ["status", "--porcelain"], {
      cwd: dir,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();

    // Filtra arquivos especiais do git worktree que não contam como sujeira
    const linhas = porcelain.split("\n").filter((linha) => {
      if (!linha) return false;
      // Arquivos especiais do worktree na raiz: HEAD, ORIG_HEAD, commondir, gitdir, index, logs/
      const arquivo = linha.slice(3).trim();
      return !(
        arquivo === "HEAD" ||
        arquivo === "ORIG_HEAD" ||
        arquivo === "commondir" ||
        arquivo === "gitdir" ||
        arquivo === "index" ||
        arquivo === "logs/"
      );
    });

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
 * Executa remoção (somente para "limpo").
 */
function executarRemocao(raiz, dadosLimpos) {
  if (dadosLimpos.length === 0) {
    console.log("nenhum worktree limpo para remover");
    return;
  }

  for (const item of dadosLimpos) {
    console.log(`removendo ${item.caminho}...`);
    // Tenta remover com --force para eliminar os arquivos especiais do worktree
    const result = spawnSync("git", ["worktree", "remove", "--force", item.caminhoOriginal], {
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

/**
 * Main.
 */
function main() {
  const raiz = resolverRaiz();

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
    const classificacao = classificar(dir);
    const caminhoOriginal = mapNormalizado.get(dir) || dir;
    dados.push({
      caminho: dir,
      caminhoOriginal,
      classificacao,
    });
  }

  // Imprime tabela
  imprimirTabela(dados);

  // Se --remover, remove os limpos
  if (remover) {
    const limpos = dados.filter((item) => item.classificacao.status === "limpo");
    if (limpos.length > 0) {
      console.log("");
      executarRemocao(raiz, limpos);
    }
  }

  process.exit(0);
}

main();
