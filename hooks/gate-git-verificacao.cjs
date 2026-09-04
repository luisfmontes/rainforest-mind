#!/usr/bin/env node
/**
 * PreToolUse — barra pulo de verificacao no git.
 *
 * O executor de um fluxo do rainforest-mind e quem mais tem motivo para pular
 * hook de commit quando ele reprova: e o proprio executor que escreveu o codigo
 * que o hook esta reprovando, e `--no-verify` remove a fricção na hora exata em
 * que ela importa. Texto de skill dizendo "nao use --no-verify" nao alcanca esse
 * modo de falha — exit code alcanca (mesmo raciocinio do `gate-staging-total`,
 * tarefa 2 do plano `docs/rainforest/planos/2026-09-04-nao-mente.md`, D8-D11).
 *
 * REGRA, tres comandos:
 *   git commit --no-verify | -n | --no-gpg-sign   -> barrado
 *   git push   --no-verify                         -> barrado
 *   qualquer outra chamada de git, inclusive
 *   `git push -n` (que em push e --dry-run, nao --no-verify)  -> passa
 *
 * `-n` so conta para `commit` (onde e sinonimo de `--no-verify`). Em `push`,
 * `-n` e `--dry-run` — bloquear ali barraria uma operacao legitima e nao tem
 * nada a ver com pular verificacao. Isto e invariante do plano (D10).
 *
 * PARSING. `--no-verify` dentro de uma MENSAGEM de commit nao pode disparar o
 * gate (`git commit -m "removi o --no-verify do script"`): o texto entre aspas
 * e removido antes de procurar flag, entao a flag so conta fora de string.
 * `git -c commit.gpgsign=false commit -m x` tem que continuar identificando
 * `commit` como subcomando (nao a chave `commit.gpgsign=false`) — a mesma
 * varredura de flags-com-valor do `gate-staging-total` resolve isso.
 *
 * ESCOPO: vale para todo ator, sem distincao de agente ou janela principal — a
 * trava e sobre o COMANDO, nao sobre quem digita.
 *
 * Saidas de emergencia, as mesmas dos outros gates deste plugin:
 *   - env RAINFOREST_GATE_OFF=1        -> desliga na sessao inteira;
 *   - arquivo .rainforest-gate-off na raiz do repo -> desliga naquele repo;
 *   - `.rainforest/config.json` do projeto, chave `gate-git-verificacao`
 *     (lida via hooks/lib/config.cjs, quando registrada em CHAVES).
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

// Flags globais do git que consomem o token seguinte (`git -C <dir> commit`).
const FLAG_COM_VALOR = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix",
]);
// Prefixos que podem vir antes do `git` sem mudar o que ele faz.
const PREFIXO_NEUTRO = new Set(["env", "sudo", "nohup", "command", "time"]);

function git(dir, args) {
  try {
    const s = execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    });
    return s.trim();
  } catch {
    return null;
  }
}

/** Segmenta a linha de comando em invocacoes independentes. */
function segmentos(cmd) {
  return cmd.split(/\|\||&&|[;|\n]/);
}

/**
 * Tokeniza removendo trechos entre aspas. Um argumento citado nunca e o
 * subcomando nem uma flag, e removendo-o some o falso positivo de
 * `git commit -m "removi o --no-verify do script"`.
 */
function tokens(seg) {
  return seg
    .replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/g, " ")
    .trim().split(/\s+/).filter(Boolean);
}

/** null se o segmento nao e uma chamada de git; senao {sub, args, dirC}. */
function analisaGit(toks) {
  let i = 0;
  while (i < toks.length && (PREFIXO_NEUTRO.has(toks[i]) || /^\w+=/.test(toks[i]))) i += 1;
  if (toks[i] !== "git") return null;
  i += 1;

  let dirC = null;
  while (i < toks.length && toks[i].startsWith("-")) {
    if (toks[i] === "-C" && toks[i + 1]) dirC = toks[i + 1];
    i += FLAG_COM_VALOR.has(toks[i]) && !toks[i].includes("=") ? 2 : 1;
  }
  if (i >= toks.length) return null;
  return { sub: toks[i], args: toks.slice(i + 1), dirC };
}

/** `-na` contem a curta `n`; `--no-verify` nao e curta e nao conta aqui. */
function temCurta(args, letra) {
  return args.some((t) => /^-[A-Za-z]+$/.test(t) && t.slice(1).includes(letra));
}

/** Motivo do bloqueio, ou null se o segmento e inofensivo. */
function motivoDe(g) {
  if (g.sub === "commit") {
    if (g.args.includes("--no-verify")) return "git commit --no-verify";
    if (g.args.includes("--no-gpg-sign")) return "git commit --no-gpg-sign";
    if (temCurta(g.args, "n")) return "git commit -n (equivale a --no-verify)";
    return null;
  }
  if (g.sub === "push") {
    // `-n` em push e --dry-run, nao --no-verify: nao entra aqui de proposito.
    if (g.args.includes("--no-verify")) return "git push --no-verify";
    return null;
  }
  return null;
}

function bloqueia(motivo, dir) {
  process.stderr.write(
    `BLOQUEADO pelo gate de verificacao git do rainforest-mind.\n\n` +
    `Comando: ${motivo}\n` +
    `Repo: ${dir}\n\n` +
    `Este gate barra o pulo de verificacao no git — hook de commit ou de push que\n` +
    `existe para pegar erro ANTES de entrar no historico. Pular a verificacao na\n` +
    `hora em que ela reprova e exatamente a hora em que ela importa.\n\n` +
    `Nao use --no-verify, -n (em commit) nem --no-gpg-sign. Se o hook esta\n` +
    `reprovando por motivo legitimo, conserte o motivo — nao pule a checagem.\n\n` +
    `Saidas de emergencia, para quem decide seguir mesmo assim:\n` +
    `  - RAINFOREST_GATE_OFF=1 no ambiente da sessao (desliga na sessao inteira);\n` +
    `  - arquivo .rainforest-gate-off na raiz do repo (desliga so naquele repo).\n`
  );
  process.exit(2);
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0); // payload ilegivel nunca trava o trabalho do usuario
  }

  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  const cwdDoEvento = ev.cwd || process.cwd();
  // Toggle do setup, mesmo mecanismo dos outros gates: quem nao quer esta trava
  // num repositorio pode desliga-la por `.rainforest/config.json` do projeto, ou
  // de vez no arquivo de dados. Falha para o lado de LIGAR — config ilegivel nao
  // pode virar trava desligada em silencio.
  try { if (!require("./lib/config.cjs").ligado("gate-git-verificacao", { projeto: cwdDoEvento })) process.exit(0); } catch {}

  if (ev.tool_name !== "Bash") process.exit(0);
  const cmd = (ev.tool_input || {}).command;
  if (typeof cmd !== "string") process.exit(0);

  let motivo = null;
  let dirC = null;
  for (const seg of segmentos(cmd)) {
    const g = analisaGit(tokens(seg));
    if (!g) continue;
    const m = motivoDe(g);
    if (m) { motivo = m; dirC = g.dirC; break; }
  }
  if (!motivo) process.exit(0);

  const dir = dirC || cwdDoEvento;
  const toplevel = git(dir, ["rev-parse", "--show-toplevel"]) || dir;
  if (fs.existsSync(path.join(toplevel, ".rainforest-gate-off"))) process.exit(0);

  bloqueia(motivo, dir);
}

main();
