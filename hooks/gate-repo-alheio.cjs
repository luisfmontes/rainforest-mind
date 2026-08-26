#!/usr/bin/env node
/**
 * PreToolUse — barra escrita cujo destino está dentro de OUTRO repositório git.
 *
 * Incidente de 2026-08-23: uma sessão cujo cwd era `C:/Projetos/whatsapp-mcp`
 * achou dois defeitos do plugin `rainforest-mind` e foi consertá-los ali mesmo,
 * deixando um worktree com 39+/10− não commitados que se perdeu.
 *
 * O cwd da sessão é conhecido e o caminho a ser escrito também — então
 * "estou escrevendo em repo alheio" é verificável por máquina.
 *
 * RECORTE, deliberadamente estreito:
 *   - Write/Edit/MultiEdit/NotebookEdit (ferramentas de escrita)
 *   - arquivo dentro de OUTRO repo git — mesmo repo passa, fora de repo passa
 *   - worktree linkado do MESMO repo — compara git-common-dir, não só toplevel
 *   - arquivo fora de repo git (scratchpad, temp) passa sempre
 *
 * Saídas de emergência, as mesmas dos outros gates:
 *   - env RAINFOREST_GATE_OFF=1  → desliga na sessão inteira
 *   - arquivo .rainforest-gate-off na raiz do destino → desliga naquele repo
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const FERRAMENTAS_DE_ESCRITA = new Set(["Write", "Edit", "MultiEdit", "NotebookEdit"]);

/**
 * Tenta rodar um comando git neste diretório. Retorna output ou null se falhar.
 */
function git(dir, args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

/**
 * null = não é repo git (livre) | {toplevel, commonDir}
 *
 * Quando o git não responde, o gate LIBERA — trava de segurança não pode
 * derrubar o trabalho por ambiente quebrado. Mas libera FALANDO.
 *
 * NOTA: git-common-dir retorna paths relativos (.git) para repos normais, mas
 * absolutos para worktrees. Normaliza para absolute para comparação segura.
 *
 * Verifica recursivamente para cima se o diretório está dentro de um repo git,
 * mesmo que o diretório não exista ainda (arquivo a ser criado em subdir novo).
 */
function estadoDoRepo(dir) {
  let tentativa = dir;
  let tentouRaiz = false;

  while (true) {
    const gitDir = git(tentativa, ["rev-parse", "--git-dir"]);
    if (gitDir !== null) {
      // Achou um repo git
      const commonDirRaw = git(tentativa, ["rev-parse", "--git-common-dir"]) || gitDir;
      return {
        toplevel: git(tentativa, ["rev-parse", "--show-toplevel"]) || tentativa,
        commonDir: path.resolve(tentativa, commonDirRaw),
      };
    }

    // Subir um nível
    const parent = path.dirname(tentativa);
    if (parent === tentativa) {
      // Chegou na raiz do filesystem
      if (!tentouRaiz && git(tentativa, ["--version"]) === null && git(process.cwd(), ["--version"]) === null) {
        process.stderr.write(
          `[gate-repo-alheio] git não respondeu para '${dir}' — gate INATIVO nesta chamada.\n`
        );
      }
      return null;
    }

    tentativa = parent;
    tentouRaiz = true;
  }
}

function dirDe(alvo) {
  try {
    return fs.existsSync(alvo) && fs.statSync(alvo).isDirectory() ? alvo : path.dirname(alvo);
  } catch {
    return path.dirname(alvo);
  }
}

function bloqueia(motivo, repoAlheio, agente) {
  const ehSubagente = !!agente;
  const saidas = ehSubagente
    ? `PARE e reporte isto para a janela principal — ela decide como seguir.\n` +
      `NÃO crie arquivo nem variável para desativar esta trava: a decisão não é sua,\n` +
      `e desativá-la para si mesmo é o contorno que esta trava existe para impedir.\n`
    : `Quem decide seguir sem isolamento é você, e tem três saídas:\n` +
      `  - node scripts/setup.cjs --desligar gate-repo-alheio --escopo projeto (preferida);\n` +
      `  - RAINFOREST_GATE_OFF=1 no ambiente da sessão (desliga na sessão inteira);\n` +
      `  - arquivo .rainforest-gate-off na raiz do repo alheio (desliga só naquele repo).\n`;

  process.stderr.write(
    `BLOQUEADO pelo gate de repo alheio do rainforest-mind.\n\n` +
    `${motivo}\n` +
    `Repo alheio: ${repoAlheio}\n` +
    `Agente: ${agente}\n\n` +
    `Esta escrita seria para dentro de OUTRO repositório git, diferente da sessão\n` +
    `que está sendo executada. Em 2026-08-23 um agente escreveu numa sessão de\n` +
    `worktree alheio, deixando um checkout divergente que se perdeu.\n\n` +
    `A saída correta é usar um worktree próprio naquele repo — ou deixar para a\n` +
    `sessão que já está lá trabalhar nele.\n\n` +
    saidas
  );
  process.exit(2);
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0); // payload ilegível nunca trava o trabalho do usuário
  }

  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  // Sem `cwd` no payload nao ha como saber qual e' o repo DESTA sessao, e cair
  // em process.cwd() e' pior que nao decidir: o cwd do processo do hook nao e'
  // necessariamente o da sessao, e barrar por um palpite barra trabalho legitimo.
  // Mesma politica do payload ilegivel — na duvida, libera.
  const cwdDoEvento = ev.cwd;
  if (!cwdDoEvento) process.exit(0);

  // A JANELA PRINCIPAL NAO PASSA. O incidente que justifica esta trava e' de
  // janela principal: em 2026-08-23 uma sessao cujo cwd era C:/Projetos/whatsapp-mcp
  // foi consertar o rainforest-mind dali mesmo, e deixou 39+/10- nao commitados num
  // worktree que se perdeu. Copiar daqui a guarda `if (!ev.agent_id) exit(0)` do
  // gate-worktree seria copiar o recorte errado: la a trava e' sobre ISOLAMENTO de
  // subagente, que e' problema de subagente; aqui e' sobre escrever FORA DO PROJETO
  // DESTA JANELA, que a janela principal faz igual — ou mais, porque e' ela que decide.

  // Toggle do setup
  try { if (!require("./lib/config.cjs").ligado("gate-repo-alheio", { projeto: cwdDoEvento })) process.exit(0); } catch {}

  const nome = ev.tool_name;
  if (!FERRAMENTAS_DE_ESCRITA.has(nome)) process.exit(0);

  const entrada = ev.tool_input || {};
  let alvos = [];

  if (nome === "Write" && typeof entrada.file_path === "string") {
    alvos = [entrada.file_path];
  } else if (nome === "Edit" && typeof entrada.file_path === "string") {
    alvos = [entrada.file_path];
  } else if (nome === "MultiEdit") {
    const edits = Array.isArray(entrada.edits) ? entrada.edits : [];
    alvos = edits.map(e => e.file_path).filter(p => typeof p === "string");
  } else if (nome === "NotebookEdit" && typeof entrada.notebook_path === "string") {
    alvos = [entrada.notebook_path];
  }

  if (!alvos.length) process.exit(0);

  // Determina o estado do repo da sessão
  const estadoSessao = estadoDoRepo(cwdDoEvento);
  if (!estadoSessao) process.exit(0); // fora de repo git: sempre passa

  for (const alvo of alvos) {
    const dirDoAlvo = dirDe(alvo);
    const estadoAlvo = estadoDoRepo(dirDoAlvo);

    if (!estadoAlvo) continue; // fora de repo git: passa

    // Verifica se é o MESMO repo (comparando git-common-dir para worktrees)
    // Normaliza paths para comparação (windows vs unix separators)
    const normalizarCaminho = (p) => p.replace(/\\/g, "/").toLowerCase();
    // A caixa desce junto: no Windows o mesmo diretorio chega escrito com caixa
    // diferente, e comparar sem baixar trata um repo como dois. Mesma razao do
    // normalizarCwd() em hooks/lib/contexto-sessao.cjs.
    if (normalizarCaminho(estadoAlvo.commonDir) === normalizarCaminho(estadoSessao.commonDir)) continue;

    // Extra: se toplevel for igual, também passa (redundante, mas seguro)
    if (normalizarCaminho(estadoAlvo.toplevel) === normalizarCaminho(estadoSessao.toplevel)) continue;

    // Verifica escape por arquivo .rainforest-gate-off
    if (fs.existsSync(path.join(estadoAlvo.toplevel, ".rainforest-gate-off"))) continue;

    // É repo alheio: barra
    const motivo = `Escrita (${nome}) em ${alvo}`;
    bloqueia(motivo, estadoAlvo.toplevel, (ev.agent_id ? `${ev.agent_type || "?"} (${ev.agent_id})` : "janela principal"));
  }

  process.exit(0);
}

main();
