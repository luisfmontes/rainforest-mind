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
 * gate (`git commit -m "removi o --no-verify do script"`): o conteudo citado
 * e PRESERVADO como parte do token (nao apagado — apagar e o que deixava a
 * flag citada passar sem barrar, ver historico da tarefa 2 do plano acima),
 * so que o token inteiro (`removi o --no-verify do script`) nunca e igual a
 * `--no-verify`. Aspas adjacentes a texto sem aspas viram UM token so, do
 * jeito que o shell faz (`--no-"verify"` -> `--no-verify`).
 * `git -c commit.gpgsign=false commit -m x` tem que continuar identificando
 * `commit` como subcomando (nao a chave `commit.gpgsign=false`) — a mesma
 * varredura de flags-com-valor do `gate-staging-total` resolve isso.
 *
 * Prefixo de opcao longa (o git aceita: `--no-veri` resolve para `--no-verify`
 * se for prefixo unico) conta como a flag inteira — comparado por prefixo
 * contra `--no-verify` e `--no-gpg-sign`, nao por igualdade.
 *
 * Encadeamento (`;`, `|`, `||`, `&&`, `&`, quebra de linha) segmenta o
 * comando, e cada segmento e varrido procurando o token `git` em QUALQUER
 * posicao (nao so no inicio) — lista de prefixos aceitos antes do `git`
 * sempre esquece um caso (`then`, `do`, `else`, `{`...). Substituicao de
 * comando `$(...)` e crase tem o delimitador removido e o conteudo interno
 * vira mais um segmento. Linha continuada com `\` + quebra de linha e
 * costurada de volta antes de segmentar, senao a flag fica orfa de comando
 * no segmento seguinte.
 *
 * NAO-OBJETIVO declarado (plano `2026-09-04-nao-mente.md`): indirecao por
 * variavel (`F=--no-verify; git commit $F`) fica FORA do alcance deste gate.
 * O valor de `$F` so existe depois da expansao do shell, e o gate le o
 * tool_input.command ANTES dela — nao ha como cobrir isso lendo o texto do
 * comando. O gate cobre o que esta ESCRITO no comando, nada alem disso.
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

/** Segmenta um trecho de comando em invocacoes independentes. */
function segmentos(cmd) {
  return cmd.split(/\|\||&&|[;|\n&]/);
}

/**
 * Costura de volta linha continuada (`\` + quebra de linha): sem isso, a
 * quebra de linha vira separador de segmento e a flag fica orfa de comando
 * no segmento seguinte (`git commit \` + quebra + ` --no-verify -m x`).
 */
function costuraContinuacao(cmd) {
  return cmd.replace(/\\\r?\n/g, " ");
}

/**
 * Extrai o conteudo de `$(...)` (nao aninhado, suficiente para o escopo
 * deste gate) e de `` `...` ``, removendo o delimitador do texto original.
 * Devolve [textoSemSubstituicao, ...conteudoDeCadaSubstituicao] — cada
 * elemento e depois segmentado e analisado como os demais.
 */
function extraiSubstituicoes(cmd) {
  const extras = [];
  let semSub = cmd.replace(/\$\(([^()]*)\)/g, (_, dentro) => { extras.push(dentro); return " "; });
  semSub = semSub.replace(/`([^`]*)`/g, (_, dentro) => { extras.push(dentro); return " "; });
  return [semSub, ...extras];
}

/** Todos os segmentos analisaveis de um comando bruto (ver comentario do topo). */
function segmentosDoComando(cmd) {
  const partes = extraiSubstituicoes(costuraContinuacao(cmd));
  return partes.flatMap(segmentos);
}

/**
 * Tokeniza PRESERVANDO o conteudo citado como parte do token, em vez de
 * apagar (apagar e o que deixava a flag citada passar sem barrar). Aspas
 * adjacentes a texto sem aspas se fundem em UM token so, do jeito que o
 * shell faz: `--no-"verify"` vira o token `--no-verify`; `-m "removi o
 * --no-verify do script"` vira UM token so com a frase inteira (que nunca e
 * igual a `--no-verify`).
 */
function tokens(seg) {
  const toks = [];
  let cur = "";
  let tem = false;
  for (let i = 0; i < seg.length; i += 1) {
    const c = seg[i];
    if (c === '"' || c === "'") {
      const fechar = seg.indexOf(c, i + 1);
      const fim = fechar === -1 ? seg.length : fechar;
      cur += seg.slice(i + 1, fim);
      tem = true;
      i = fim;
      continue;
    }
    if (/\s/.test(c)) {
      if (tem) { toks.push(cur); cur = ""; tem = false; }
      continue;
    }
    cur += c;
    tem = true;
  }
  if (tem) toks.push(cur);
  return toks;
}

/**
 * null se o segmento nao contem uma chamada de git; senao {sub, args, dirC}.
 * Varre o token `git` em QUALQUER posicao do segmento (nao so no inicio):
 * lista de prefixos aceitos antes dele (`env`, `sudo`, `VAR=valor`...)
 * sempre esquece um caso — `then`, `do`, `else`, `{` inclusive.
 */
function analisaGit(toks) {
  const inicio = toks.indexOf("git");
  if (inicio === -1) return null;
  let i = inicio + 1;

  let dirC = null;
  while (i < toks.length && toks[i].startsWith("-")) {
    if (toks[i] === "-C" && toks[i + 1]) dirC = toks[i + 1];
    i += FLAG_COM_VALOR.has(toks[i]) && !toks[i].includes("=") ? 2 : 1;
  }
  if (i >= toks.length) return null;
  return { sub: toks[i], args: toks.slice(i + 1), dirC };
}

/**
 * true se `token` e uma opcao longa (comeca com `--`) que e PREFIXO de
 * `alvo` — o git aceita prefixo unico de opcao longa (`--no-veri` resolve
 * para `--no-verify`, e o proprio git aceita isso na pratica).
 */
function ehPrefixoDeFlag(token, alvo) {
  return token.length > 2 && token.startsWith("--") && alvo.startsWith(token);
}

/** `-na` contem a curta `n`; `--no-verify` nao e curta e nao conta aqui. */
function temCurta(args, letra) {
  return args.some((t) => /^-[A-Za-z]+$/.test(t) && t.slice(1).includes(letra));
}

/** Motivo do bloqueio, ou null se o segmento e inofensivo. */
function motivoDe(g) {
  if (g.sub === "commit") {
    if (g.args.some((t) => ehPrefixoDeFlag(t, "--no-verify"))) return "git commit --no-verify";
    if (g.args.some((t) => ehPrefixoDeFlag(t, "--no-gpg-sign"))) return "git commit --no-gpg-sign";
    if (temCurta(g.args, "n")) return "git commit -n (equivale a --no-verify)";
    return null;
  }
  if (g.sub === "push") {
    // `-n` em push e --dry-run, nao --no-verify: nao entra aqui de proposito.
    if (g.args.some((t) => ehPrefixoDeFlag(t, "--no-verify"))) return "git push --no-verify";
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
  for (const seg of segmentosDoComando(cmd)) {
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
