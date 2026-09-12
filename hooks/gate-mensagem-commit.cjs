#!/usr/bin/env node
/**
 * PreToolUse — exige forma minima na mensagem de `git commit` (Bash e
 * PowerShell, janela principal e subagente).
 *
 * Origem: analise do plugin de dados `wildz-data` (Rootz) — 25 trailers
 * `Co-Authored-By` e commits sem corpo num repo que bania os dois por
 * CLAUDE.md (docs/rainforest/design/2026-09-12-absorver-data-skills.md, D2).
 * Regra que so vive em texto se viola; a metade que faltava neste plugin era
 * a MENSAGEM — `gate-staging-total.cjs` ja obriga `git add` por caminho, e
 * "por partes" ja e um commit por tarefa do plano.
 *
 * REGRA: assunto (primeira linha da mensagem) nao pode ser vazio, tem que
 * caber em 72 colunas e nao pode terminar em ponto final. Corpo (linha em
 * branco seguida de ao menos uma linha que NAO seja trailer, forma
 * `^[A-Za-z-]+: `) e obrigatorio quando o diff em stage do repositorio do
 * cwd toca MAIS de 3 arquivos OU MAIS de 150 linhas somadas
 * (`git diff --cached --numstat`, adicoes + remocoes). Commit pequeno
 * (ate 3 arquivos e ate 150 linhas) continua passando so com assunto —
 * o gate nao pode virar friccao no commit que ele quer incentivar.
 *
 * MENSAGEM. Vem de `-m`/`--message` (cada ocorrencia e um paragrafo; a
 * segunda em diante ja conta como corpo, exceto se for so trailer) ou de
 * `-F`/`--file <arquivo>` (le o arquivo: primeira linha e assunto, resto e
 * corpo). `-F -` (le de stdin) e heredoc como fonte de `-F -` sao mensagem
 * NAO RESOLVIVEL por este gate — ele nao executa o comando, so le o texto
 * de `tool_input.command` — e barram com exit 2 pedindo `-F <arquivo>`.
 * Sem nenhuma fonte de mensagem (nem `-m`, nem `-F`, nem flag de reuso)
 * tambem e nao-resolvivel. `--amend`, `--no-edit`, `-C <rev>` (reusa
 * mensagem) e `-c <rev>` (reusa e edita) pulam toda checagem — a mensagem
 * ja existe em outro commit.
 *
 * ESCOPO/DETECCAO: reaproveita `hooks/lib/tokens-comando.cjs` e
 * `hooks/lib/cwd-efetivo.cjs` (os mesmos modulos de `gate-staging-total.cjs`)
 * para segmentar a linha por `;`/`&&`/`||`/`|`/quebra de linha respeitando
 * aspas, achar a POSICAO DE COMANDO pulando wrapper de prefixo (`env`,
 * `sudo`, ...) e desempacotar wrapper de STRING (`bash -c "..."`, `eval
 * "..."`, `Invoke-Expression`/`iex`, `pwsh -Command`, `cmd /c`) — a mesma
 * extracao que `hooks/gate-git-verificacao.cjs` documenta para achar `git
 * commit` escondido, sem copiar aquele arquivo (ele e so-Bash; aqui precisa
 * valer para PowerShell tambem).
 *
 * Protege contra: `git commit` direto ou dentro de wrapper conhecido
 * (bash -c, eval, Invoke-Expression/iex, pwsh -Command, cmd /c) com assunto
 * vazio, longo demais, terminando em ponto, ou sem corpo num diff grande;
 * e mensagem que este gate nao consegue ler (`-F -`, heredoc, nem `-m` nem
 * `-F`). Isso inclui `git commit` PELADO, que abriria o editor — o harness
 * nao tem editor, e o commit que fecha um merge com conflito resolvido cai
 * aqui: o gesto e `git commit -F .git/MERGE_MSG` (achado da revisao,
 * 2026-09-12).
 * Não protege contra: indirecao por variavel (`M="$msg"; git commit -m
 * "$M"` — o valor so existe apos expansao do shell, que roda depois deste
 * gate ler `tool_input.command`); ofuscacao desenhada de proposito para
 * escapar deste parser escrito a mao (mesma ressalva de
 * `gate-git-verificacao.cjs`: isto e um quebra-molas contra o atalho por
 * conveniencia, nao uma fronteira contra evasao deliberada); `-F <arquivo>`
 * cujo arquivo nao pode ser lido (fail-open, ver `main()`).
 *
 * Saidas de emergencia: nenhuma alem do fail-open acima — nao ha
 * `.rainforest-gate-off` nem `RAINFOREST_GATE_OFF` aqui de proposito: a
 * pior consequencia de bloqueio e "use -F <arquivo>" ou "escreva um corpo",
 * nunca perda de trabalho, entao nao ha necessidade de escape dedicado.
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { segmentosComAspas } = require("./lib/cwd-efetivo.cjs");
const {
  tokensComAspas, ehComando, posicaoDeComando, textoAPartir, desempacotarWrapperDeString,
} = require("./lib/tokens-comando.cjs");

// Flags globais do git (antes do subcomando) que consomem o token seguinte.
const FLAG_GLOBAL_COM_VALOR = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix",
]);

const TRAILER = /^[A-Za-z-]+: /;
const LIMITE_ASSUNTO = 72;
const LIMITE_ARQUIVOS = 3;
const LIMITE_LINHAS = 150;

function git(dir, args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    return null;
  }
}

/**
 * `null` se o segmento tokenizado nao e uma chamada `git commit`; senao os
 * tokens (com aspas preservadas, ver `tokensComAspas`) depois do subcomando.
 */
function analisaGitCommit(toks) {
  const pos = posicaoDeComando(toks);
  if (pos === null || !ehComando(toks[pos], "git", true)) return null;
  let i = pos + 1;
  while (i < toks.length && !toks[i].q && toks[i].v.startsWith("-")) {
    const v = toks[i].v;
    i += (FLAG_GLOBAL_COM_VALOR.has(v) && !v.includes("=")) ? 2 : 1;
  }
  if (i >= toks.length || toks[i].v !== "commit") return null;
  return { argsToks: toks.slice(i + 1) };
}

/**
 * `analisaGitCommit` mais o desempacotamento de wrapper de STRING (mesma
 * extracao usada por `gate-staging-total.cjs`) — acha `git commit` dentro de
 * `bash -c "..."`, `eval "..."`, `Invoke-Expression`/`iex`, `pwsh -Command`,
 * `cmd /c`. `{ incerto: true }` quando o conteudo do wrapper nao e legivel
 * (substituicao de comando, variavel) — tratado como "nao achei nada aqui",
 * nao como bloqueio: este gate e sobre FORMA de mensagem, nao sobre evasao.
 */
function analisaSegmentoCommit(segTexto, ferramenta) {
  const toks = tokensComAspas(segTexto);
  const g = analisaGitCommit(toks);
  if (g) return g;
  const pos = posicaoDeComando(toks);
  if (pos === null) return null;
  const { interno, ilegivel } = desempacotarWrapperDeString(textoAPartir(toks, pos), { ferramenta });
  if (ilegivel || interno === null) return null;
  for (const sub of segmentosComAspas(interno)) {
    const r = analisaSegmentoCommit(sub, ferramenta);
    if (r) return r;
  }
  return null;
}

/** Acha o primeiro `git commit` em qualquer segmento do comando bruto. */
function achaGitCommit(cmd, ferramenta) {
  for (const seg of segmentosComAspas(cmd)) {
    const g = analisaSegmentoCommit(seg, ferramenta);
    if (g) return g;
  }
  return null;
}

/**
 * Le as flags de mensagem/reuso do `git commit`. Devolve
 * `{ mParts, fFile, reusaMensagem }`. `reusaMensagem` e true com
 * `--amend`, `--no-edit`, `-C <rev>` ou `-c <rev>` — qualquer um ja basta
 * para pular toda checagem de forma.
 */
function leFlagsCommit(argsToks) {
  const mParts = [];
  let fFile = null;
  let reusaMensagem = false;
  let i = 0;
  while (i < argsToks.length) {
    const tok = argsToks[i];
    const v = tok.v;
    if (!tok.q && (v === "-m" || v === "--message")) {
      if (i + 1 < argsToks.length) { mParts.push(argsToks[i + 1].v); i += 2; } else i += 1;
      continue;
    }
    if (!tok.q && v.startsWith("--message=")) { mParts.push(v.slice("--message=".length)); i += 1; continue; }
    if (!tok.q && (v === "-F" || v === "--file")) {
      if (i + 1 < argsToks.length) { fFile = argsToks[i + 1].v; i += 2; } else i += 1;
      continue;
    }
    if (!tok.q && v.startsWith("--file=")) { fFile = v.slice("--file=".length); i += 1; continue; }
    if (!tok.q && (v === "--amend" || v === "--no-edit")) { reusaMensagem = true; i += 1; continue; }
    if (!tok.q && (v === "-C" || v === "--reuse-message" || v === "-c" || v === "--reedit-message")) {
      reusaMensagem = true;
      i += (i + 1 < argsToks.length) ? 2 : 1;
      continue;
    }
    i += 1;
  }
  return { mParts, fFile, reusaMensagem };
}

/**
 * `true` se, depois da primeira linha em branco em `linhasResto`, existe ao
 * menos uma linha nao-vazia que NAO seja trailer (`^[A-Za-z-]+: `).
 */
function temCorpo(linhasResto) {
  let viuBranco = false;
  for (const l of linhasResto) {
    if (!viuBranco) {
      if (l.trim() === "") viuBranco = true;
      continue;
    }
    if (l.trim() === "") continue;
    if (TRAILER.test(l)) continue;
    return true;
  }
  return false;
}

/** `{arquivos, linhas}` a partir da saida crua de `git diff --cached --numstat`. */
function contaDiff(numstatRaw) {
  const linhasBrutas = numstatRaw.split(/\r?\n/).filter((l) => l.trim() !== "");
  let linhas = 0;
  for (const l of linhasBrutas) {
    const [add, rem] = l.split("\t");
    linhas += (/^\d+$/.test(add) ? parseInt(add, 10) : 0) + (/^\d+$/.test(rem) ? parseInt(rem, 10) : 0);
  }
  return { arquivos: linhasBrutas.length, linhas };
}

const FORMA_ESPERADA =
  `Forma esperada da mensagem de commit:\n` +
  `  Assunto ate ${LIMITE_ASSUNTO} colunas, sem ponto final\n` +
  `  <linha em branco>\n` +
  `  Corpo explicando o PORQUE da mudanca (trailer como Co-Authored-By nao conta como corpo)\n\n` +
  `Use -m "Assunto" -m "corpo que explica o porque", ou -F <arquivo> com a mensagem completa.\n`;

function bloqueia(motivo) {
  process.stderr.write(
    `BLOQUEADO pelo gate de mensagem de commit do rainforest-mind.\n\n` +
    `Motivo: ${motivo}\n\n` +
    FORMA_ESPERADA
  );
  process.exit(2);
}

/**
 * Ramo separado (nao passa por `bloqueia()`) para o corpo obrigatorio
 * ausente — mantido como ponto de saida proprio de proposito, para a
 * mutacao de prova (Objetivo 4) poder trocar SO este `process.exit(2)`,
 * sem afetar a validacao de assunto nem a de mensagem nao-resolvivel.
 */
function bloqueiaCorpoAusente(arquivos, linhas) {
  process.stderr.write(
    `BLOQUEADO pelo gate de mensagem de commit do rainforest-mind.\n\n` +
    `Motivo: ${arquivos} arquivo(s), ${linhas} linha(s) em stage — acima do limiar ` +
    `(${LIMITE_ARQUIVOS} arquivos ou ${LIMITE_LINHAS} linhas), corpo e obrigatorio\n\n` +
    FORMA_ESPERADA
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

  if (ev.tool_name !== "Bash" && ev.tool_name !== "PowerShell") process.exit(0);
  const cmd = (ev.tool_input || {}).command;
  if (typeof cmd !== "string") process.exit(0);

  const achado = achaGitCommit(cmd, ev.tool_name);
  if (!achado) process.exit(0); // comando sem `git commit`

  const { mParts, fFile, reusaMensagem } = leFlagsCommit(achado.argsToks);
  if (reusaMensagem) process.exit(0); // --amend/--no-edit/-C/-c: mensagem ja existe

  if (fFile === "-") {
    bloqueia("mensagem via `-F -` (stdin) ou heredoc nao e resolvivel por este gate — use -F <arquivo>");
  }

  const cwdDoEvento = ev.cwd || process.cwd();
  const partes = [...mParts];
  if (fFile !== null && fFile !== "-") {
    const caminho = path.isAbsolute(fFile) ? fFile : path.join(cwdDoEvento, fFile);
    let conteudo;
    try {
      conteudo = fs.readFileSync(caminho, "utf8");
    } catch {
      process.stderr.write(`[gate-mensagem-commit] nao consegui ler '${caminho}' — gate INATIVO nesta chamada.\n`);
      process.exit(0);
    }
    partes.push(conteudo);
  }

  if (partes.length === 0) {
    bloqueia("nenhuma mensagem resolvivel (sem -m, sem -F, sem flag de reuso) — use -F <arquivo>; fechando merge, -F .git/MERGE_MSG");
  }

  const linhas = partes.join("\n\n").split(/\r?\n/);
  const assunto = linhas[0] || "";
  if (assunto === "") bloqueia("assunto vazio");
  if (assunto.length > LIMITE_ASSUNTO) {
    bloqueia(`assunto com ${assunto.length} colunas, acima do limite de ${LIMITE_ASSUNTO}`);
  }
  if (assunto.endsWith(".")) bloqueia("assunto termina em ponto final");

  const numstatRaw = git(cwdDoEvento, ["diff", "--cached", "--numstat"]);
  if (numstatRaw === null) {
    // Sem resposta do git: ou o cwd nao e repo (silencioso — nao ha o que
    // avisar), ou o proprio git esta quebrado (avisa e libera mesmo assim).
    if (git(cwdDoEvento, ["--version"]) === null && git(process.cwd(), ["--version"]) === null) {
      process.stderr.write(`[gate-mensagem-commit] git nao respondeu para '${cwdDoEvento}' — gate INATIVO nesta chamada.\n`);
    }
    process.exit(0);
  }

  const { arquivos, linhas: numLinhas } = contaDiff(numstatRaw);
  if (arquivos > LIMITE_ARQUIVOS || numLinhas > LIMITE_LINHAS) {
    if (!temCorpo(linhas.slice(1))) {
      bloqueiaCorpoAusente(arquivos, numLinhas);
    }
  }

  process.exit(0);
}

main();
