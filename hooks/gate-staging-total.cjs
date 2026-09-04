#!/usr/bin/env node
/**
 * PreToolUse — barra staging em massa (`git add -A`, `git commit -am`) em
 * working tree compartilhado por varias sessoes.
 *
 * Por que existe, com data: em 2026-08-09, numa unica sessao, `git add -A`
 * levou junto trabalho de outra janela DUAS vezes.
 *
 *   1. Varreu `sessoes.json` e tres logs do vigia para o controle de versao —
 *      arquivos gerados, que ninguem quis versionar.
 *   2. Varreu `relatorios/2026-08-09-relato-de-agente-vs-evidencia.md`, escrito
 *      por outra sessao a pedido do usuario, para dentro da branch
 *      `skill-em-ingles`. Se a branch tivesse sido descartada — que era o plano
 *      dela — o relatorio teria sumido junto. Nao sumiu por sorte.
 *
 * O diagnostico que importa: a sessao que escreveu o arquivo nao errou nada.
 * Ela escreveu e deixou la, que e o comportamento de qualquer editor. Quem
 * errou foi a janela que varreu, e a regra "nao use add -A" ja era obvia para
 * ela — eu sabia, e digitei assim mesmo, duas vezes na mesma noite. Texto nao
 * alcanca esse modo de falha. Exit code alcanca.
 *
 * NAO adianta consertar na origem. Um `/feedback` que commitasse na hora teria
 * commitado na `skill-em-ingles` do mesmo jeito, porque o working tree e
 * compartilhado e era a MINHA janela que tinha trocado a branch. O conserto so
 * funciona no lado de quem faz o staging.
 *
 * REGRA, uma so: nada entra no index sem caminho explicito.
 *   git add -A | --all | . | ./ | :/ | * | -u | --update   -> barrado
 *   git commit -a | -am | --all                            -> barrado
 *   git add <caminho> ...                                  -> passa
 *
 * `-u`/`commit -a` entram na lista por coerencia, nao por incidente: `commit -a`
 * e literalmente `add -u` + commit, e nesta repo outra sessao mexe em arquivo
 * RASTREADO o tempo todo (ideias.jsonl, SKILL.md). Bloquear um e liberar o
 * outro seria uma regra que nao se explica.
 *
 * ESCOPO, de proposito estreito:
 *   - vale para a janela principal TAMBEM — e o oposto do gate-worktree, e de
 *     proposito: os dois incidentes foram na janela principal;
 *   - worktree linkado passa livre. La so escreve o agente dono do worktree,
 *     entao nao ha trabalho alheio para varrer, e e onde subagente commita;
 *   - fora de repo git, passa.
 *
 * A mensagem de bloqueio nao so recusa: ela roda `git status --porcelain` e
 * mostra O QUE seria varrido, com o `git add` por caminho ja montado. Trava que
 * so diz "nao" vira trava desligada.
 *
 * Saidas de emergencia, as mesmas do gate-worktree e nomeadas na mensagem:
 *   - env RAINFOREST_GATE_OFF=1  -> desliga na sessao inteira;
 *   - arquivo .rainforest-gate-off na raiz do repo -> desliga naquele repo.
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { cwdPorSegmento, segmentosComAspas } = require("./lib/cwd-efetivo.cjs");
const { tokensComAspas, ehComando, posicaoDeComando } = require("./lib/tokens-comando.cjs");

// Flags globais do git que consomem o token seguinte (`git -C <dir> add`).
const FLAG_COM_VALOR = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix",
]);
// Pathspecs que significam "o repo inteiro".
const CAMINHO_TOTAL = new Set([".", "./", ":/", "*", "-A", "--all", "-u", "--update"]);

/**
 * `cru` preserva o espaco a esquerda. Nao e preciosismo: o porcelain usa duas
 * COLUNAS de status, e arquivo modificado-nao-staged sai como ' M arquivo'. Um
 * .trim() come esse espaco na PRIMEIRA linha so, e o slice(3) devolve o caminho
 * sem a primeira letra — 'ideias.jsonl' virou 'deias.jsonl' no repo real, em
 * 2026-08-09, com a bateria toda verde: a caixa de areia tinha um '??' na
 * primeira linha, que nao tem espaco a esquerda e nao expunha o defeito.
 */
function git(dir, args, { cru = false } = {}) {
  try {
    const s = execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    });
    return cru ? s.replace(/\r?\n+$/, "") : s.trim();
  } catch {
    return null;
  }
}

/**
 * Segmenta a linha de comando em invocacoes independentes.
 *
 * Delega para `segmentosComAspas` (H1, rodada 5, lote 3): precisa ser a
 * MESMA segmentacao que `cwdPorSegmento` usa, senao o indice do segmento
 * onde `git add`/`commit` casou não bate com o indice do cwd resolvido —
 * cada um cortaria a linha num lugar diferente perto de `;`/`&&` dentro de
 * aspas. Antes era `cmd.split(/\|\||&&|[;|\n]/)`, sem respeitar aspas.
 */
function segmentos(cmd) {
  return segmentosComAspas(cmd);
}

/**
 * Acha a POSICAO DE COMANDO do segmento (pulando `env -C X`, `env NOME=v`,
 * `sudo -u x`, `nice -n 5`, `timeout 5`, `nohup`, `command`, `exec`, `time`,
 * `xargs`, ...) via `posicaoDeComando`/`tokensComAspas` de
 * `hooks/lib/tokens-comando.cjs` — o mesmo modulo que `gate-worktree.cjs` e
 * `cwd-efetivo.cjs` ja usam. `null` se o comando ali nao e `git`.
 *
 * M1 (auditor, 5a revisao, 2026-09-03): o tokenizador antigo desta funcao so
 * pulava `PREFIXO_NEUTRO` como token UNICO, entao `env -C . git add -A` ou
 * `sudo -u x git add -A` paravam na flag do wrapper (`toks[i] !== "git"`) e o
 * `git add -A` passava sem checagem — o incidente de 2026-08-09 que este gate
 * existe para impedir.
 *
 * A partir da posicao de comando, o restante do segmento e filtrado dos
 * tokens citados (um argumento entre aspas nunca e subcomando nem flag —
 * `git commit -m "suporte a add -A"` nao pode virar falso positivo) e
 * analisado como antes.
 */
function analisaGit(toksComAspas) {
  const pos = posicaoDeComando(toksComAspas);
  if (pos === null || !ehComando(toksComAspas[pos], "git")) return null;
  const resto = toksComAspas.slice(pos + 1).filter((t) => !t.q).map((t) => t.v);

  let i = 0;
  let dirC = null;
  while (i < resto.length && resto[i].startsWith("-")) {
    if (resto[i] === "-C" && resto[i + 1]) dirC = resto[i + 1];
    i += FLAG_COM_VALOR.has(resto[i]) && !resto[i].includes("=") ? 2 : 1;
  }
  if (i >= resto.length) return null;
  return { sub: resto[i], args: resto.slice(i + 1), dirC };
}

/** `-am` contem a curta `a`; `--amend` nao e curta e nao conta. */
function temCurta(args, letra) {
  return args.some((t) => /^-[A-Za-z]+$/.test(t) && t.slice(1).includes(letra));
}

/** Motivo do bloqueio, ou null se o segmento e inofensivo. */
function motivoDe(g) {
  if (g.sub === "add") {
    const total = g.args.find((a) => CAMINHO_TOTAL.has(a));
    if (total) return `git add ${total}`;
    if (temCurta(g.args, "A")) return "git add -A (em flag combinada)";
    if (temCurta(g.args, "u")) return "git add -u (em flag combinada)";
    return null;
  }
  if (g.sub === "commit") {
    if (g.args.includes("--all")) return "git commit --all";
    if (temCurta(g.args, "a")) return "git commit -a";
    return null;
  }
  return null;
}

/**
 * O que o comando pegaria agora, e o `git add` por caminho ja pronto.
 *
 * `-uall` nao e detalhe: sem ele o git COLAPSA diretorio nao rastreado numa
 * linha so (`?? relatorios/`) e a mensagem esconde justamente o arquivo que
 * seria varrido — que e a unica informacao pela qual ela existe. A primeira
 * versao saiu assim e a bateria pegou.
 */
function oQueSeriaVarrido(dir) {
  const saida = git(dir, ["status", "--porcelain", "-uall"], { cru: true });
  if (!saida) return "";
  const linhas = saida.split("\n").filter(Boolean);
  // Rename vem como `R  antigo -> novo`; o caminho que interessa e o novo.
  const caminhos = linhas.map((l) => {
    const cru = l.slice(3);
    return (cru.includes(" -> ") ? cru.split(" -> ").pop() : cru).replace(/^"|"$/g, "");
  });
  const mostra = linhas.slice(0, 15).map((l) => `  ${l}`).join("\n");
  const corte = linhas.length > 15 ? `\n  ... e mais ${linhas.length - 15}` : "";
  const pronto = caminhos.slice(0, 15).map((c) => `"${c}"`).join(" ");
  return (
    `\nO que o comando pegaria AGORA (git status --porcelain):\n${mostra}${corte}\n` +
    `\nSe for tudo seu, o comando por caminho ja esta pronto:\n  git add ${pronto}\n`
  );
}

function bloqueia(motivo, dir, quem) {
  // P1 do relatorio 2026-08-11-escotilha-do-gate-usada-para-contornar: a saida
  // de emergencia era NOMEADA na mensagem que o SUBAGENTE le. Um implementador
  // bloqueado leu o nome do arquivo de escape na propria mensagem de bloqueio,
  // criou `.rainforest-gate-off` na raiz do checkout principal - fora do
  // worktree dele - e seguiu trabalhando. Reportou `DONE`, e o achado so apareceu
  // porque um revisor leu o relatorio completo linha a linha.
  //
  // As saidas continuam existindo e continuam valendo: elas sao para a JANELA
  // PRINCIPAL, que e quem decide seguir sem isolamento. Ela as conhece pela skill
  // `setup` e por este codigo. Deixam de ser instrucao visivel para quem nao tem
  // autoridade de usa-las - escotilha nomeada na mensagem de bloqueio, sem
  // verificacao de proveniencia, e indistinguivel de instrucao de contorno para
  // quem esta justamente tentando contornar.
  //
  // Em 2026-08-11 (tarde) o `/setup` acrescentou uma TERCEIRA rota - o toggle em
  // `.rainforest/config.json` -, e ela e a mais amigavel das tres, com comando
  // documentado. Por isso a mensagem para o subagente nao nomeia nenhuma.
  const ehSubagente = quem && !/principal/i.test(String(quem));
  const saidas = ehSubagente
    ? `PARE e reporte isto para a janela principal — ela decide como seguir.\n` +
      `NAO crie arquivo nem variavel para desativar esta trava: a decisao nao e sua,\n` +
      `e desativa-la para si mesmo e o contorno que esta trava existe para impedir.\n`
    : `Quem decide seguir sem isolamento e voce, e tem tres saidas:\n` +
      `  - node scripts/setup.cjs --desligar gate-staging --escopo projeto (preferida);\n` +
      `  - RAINFOREST_GATE_OFF=1 no ambiente da sessao (desliga na sessao inteira);\n` +
      `  - arquivo .rainforest-gate-off na raiz do repo (desliga so naquele repo).\n`;

  process.stderr.write(
    `BLOQUEADO pelo gate de staging total do rainforest-mind.\n\n` +
    `Comando: ${motivo}\n` +
    `Repo: ${dir}\n` +
    `Quem: ${quem}\n\n` +
    `Varias sessoes podem trabalhar no MESMO working tree. Staging em massa nao\n` +
    `distingue o seu trabalho do da janela do lado. Em 2026-08-09, na mesma sessao,\n` +
    `'git add -A' varreu trabalho alheio duas vezes: logs e sessoes.json numa, e o\n` +
    `relatorio escrito por outra sessao para dentro de uma branch que ia ser\n` +
    `descartada na outra.\n` +
    `${oQueSeriaVarrido(dir)}` +
    `\nAdicione por caminho. Se algum arquivo acima nao e seu, ele nao entra — e vale\n` +
    `perguntar de quem e antes de commitar.\n\n` +
    saidas
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
  // Toggle do setup: quem nao quer este gate num repositorio pode desliga-lo por
  // `.rainforest/config.json` do projeto, ou de vez no arquivo de dados. A leitura
  // mora em hooks/lib/config.cjs e falha para o lado de LIGAR - config ilegivel
  // nao pode virar trava desligada em silencio.
  try { if (!require("./lib/config.cjs").ligado("gate-staging", { projeto: cwdDoEvento })) process.exit(0); } catch {}
  if (ev.tool_name !== "Bash") process.exit(0);
  const cmd = (ev.tool_input || {}).command;
  if (typeof cmd !== "string") process.exit(0);

  let motivo = null;
  let dirC = null;
  let indiceSegmento = null;
  const segs = segmentos(cmd);
  for (let idx = 0; idx < segs.length; idx += 1) {
    const g = analisaGit(tokensComAspas(segs[idx]));
    if (!g) continue;
    const m = motivoDe(g);
    if (m) { motivo = m; dirC = g.dirC; indiceSegmento = idx; break; }
  }
  if (!motivo) process.exit(0);

  // H1 (rodada 5, lote 3): resolve o cwd efetivo NO SEGMENTO onde o `git
  // add`/`commit` apareceu, nao o cwd FINAL da linha inteira. Antes disto,
  // `git add -A && cd <worktree>` no principal fazia o `add` de verdade no
  // principal, mas o cwd FINAL (depois do `cd`) caia no worktree, e o gate
  // liberava lendo o lugar errado — o mesmo defeito do H1 no ramo de CLI do
  // `gate-worktree.cjs`. `dirC` (git -C) vence sempre — nao ha `cd` antes de
  // `git -C`, e `-C` e explicito. `incerto` (cd variavel, subshell, `~` no
  // comeco, `popd` sem `pushd`) = conservadorismo: usa o cwd inicial, evitando
  // decidir por adivinhacao.
  const porSegmento = cwdPorSegmento(cmd, cwdDoEvento);
  const doSegmento = porSegmento[indiceSegmento] || { cwd: cwdDoEvento, incerto: true };
  const dir = dirC || (doSegmento.incerto ? cwdDoEvento : doSegmento.cwd);
  const gitDir = git(dir, ["rev-parse", "--git-dir"]);
  if (gitDir === null) {
    // Fora de repo git o comando falha sozinho. Mas se o git nao respondeu por
    // ambiente quebrado, o gate libera FALANDO — foi liberar calado que fez a
    // bateria do gate-worktree passar verde testando nada, em 2026-08-09.
    if (git(dir, ["--version"]) === null && git(process.cwd(), ["--version"]) === null) {
      process.stderr.write(
        `[gate-staging-total] git nao respondeu para '${dir}' — gate INATIVO nesta chamada.\n`
      );
    }
    process.exit(0);
  }
  // Worktree linkado e isolado: so o dono escreve la, nao ha alheio para varrer.
  if (gitDir.replace(/\\/g, "/").includes("/worktrees/")) process.exit(0);

  const toplevel = git(dir, ["rev-parse", "--show-toplevel"]) || dir;
  if (fs.existsSync(path.join(toplevel, ".rainforest-gate-off"))) process.exit(0);

  bloqueia(motivo, toplevel, ev.agent_id ? `${ev.agent_type || "?"} (${ev.agent_id})` : "janela principal");
}

main();
