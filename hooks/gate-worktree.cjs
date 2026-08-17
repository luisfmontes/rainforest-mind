#!/usr/bin/env node
/**
 * PreToolUse — barra subagente que escreve fora de worktree isolado.
 *
 * O P2 do relatorio de 2026-08-08
 * (relatorios/2026-08-08-executor-reincidencia-isolamento.md):
 *
 *   "Enquanto o veredito de uma checagem for redigido pelo mesmo agente que
 *    ela deveria travar, ela nao trava nada. Exit code nao se argumenta."
 *
 * Naquele dia a regra 20-26 do executor.md estava escrita, sem ambiguidade, no
 * system prompt do agente E repetida no briefing. Ele rodou a verificacao,
 * recebeu o diretorio principal — a condicao de parada —, transcreveu a
 * condicao corretamente e escreveu um OK do lado. Texto nao alcanca esse modo
 * de falha, porque o texto ja estava la e foi lido.
 *
 * Isto e a mesma regra, com exit 2 no lugar do pedido.
 *
 * Por que da pra fazer: hooks rodam DENTRO do subagente. Da doc oficial —
 * "When a subagent calls a tool, tool events such as PreToolUse and PostToolUse
 * fire the same configured hooks as in the main conversation, and the input
 * carries the agent_id and agent_type". Entao nao e preciso interceptar o
 * despacho do Task: intercepta-se a escrita, ja sabendo quem esta escrevendo.
 *
 * ESCOPO, de proposito estreito:
 *   - so age quando ha `agent_id` — a janela principal nunca e barrada;
 *   - escrita de arquivo (Write/Edit/MultiEdit/NotebookEdit) para dentro de
 *     repo git que NAO e worktree linkado;
 *   - Bash: so a lista curta de comandos que mexem no estado do repo
 *     (stash, checkout, switch, reset, merge, rebase, commit, clean) — foi
 *     `git stash`/`pop` que moveu o HEAD do usuario na falha N1. Leitura passa.
 *   - fora de repo git (scratchpad, temp) passa sempre.
 *
 * Saidas de emergencia, as duas nomeadas na mensagem de bloqueio:
 *   - env RAINFOREST_GATE_OFF=1  → desliga na sessao inteira;
 *   - arquivo .rainforest-gate-off na raiz do repo → desliga naquele repo.
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const FERRAMENTAS_DE_ESCRITA = new Set(["Write", "Edit", "MultiEdit", "NotebookEdit"]);
// Subcomandos de git que mexem no estado do checkout. `git stash`/`pop` foi a falha N1.
const GIT_QUE_MEXE = /\bgit\b[^\n;&|]*?\b(stash|checkout|switch|reset|merge|rebase|commit|clean|cherry-pick|revert)\b/;

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
 * null = nao e repo git (livre) | {toplevel, ehWorktree}
 *
 * Quando o git nao responde, o gate LIBERA — trava de seguranca nao pode
 * derrubar o trabalho por ambiente quebrado. Mas libera FALANDO: em
 * 2026-08-09 a bateria passou verde por engano porque o teste mandava
 * caminho `/tmp/...` do Git Bash, que o Node no Windows nao resolve; o git
 * falhava, o gate liberava calado e parecia funcionar. Trava que falha em
 * silencio e o mesmo defeito que ela existe pra consertar.
 */
function estadoDoRepo(dir) {
  const gitDir = git(dir, ["rev-parse", "--git-dir"]);
  if (gitDir === null) {
    if (git(dir, ["--version"]) === null && git(process.cwd(), ["--version"]) === null) {
      process.stderr.write(
        `[gate-worktree] git nao respondeu para '${dir}' — gate INATIVO nesta chamada.\n`
      );
    }
    return null;
  }
  return {
    toplevel: git(dir, ["rev-parse", "--show-toplevel"]) || dir,
    ehWorktree: gitDir.replace(/\\/g, "/").includes("/worktrees/"),
  };
}

function dirDe(alvo) {
  try {
    return fs.existsSync(alvo) && fs.statSync(alvo).isDirectory() ? alvo : path.dirname(alvo);
  } catch {
    return path.dirname(alvo);
  }
}

function bloqueia(motivo, toplevel, agente) {
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
  const ehSubagente = !!agente;
  const saidas = ehSubagente
    ? `PARE e reporte isto para a janela principal — ela decide como seguir.\n` +
      `NAO crie arquivo nem variavel para desativar esta trava: a decisao nao e sua,\n` +
      `e desativa-la para si mesmo e o contorno que esta trava existe para impedir.\n`
    : `Quem decide seguir sem isolamento e voce, e tem tres saidas:\n` +
      `  - node scripts/setup.cjs --desligar gate-worktree --escopo projeto (preferida);\n` +
      `  - RAINFOREST_GATE_OFF=1 no ambiente da sessao (desliga na sessao inteira);\n` +
      `  - arquivo .rainforest-gate-off na raiz do repo (desliga so naquele repo).\n`;

  process.stderr.write(
    `BLOQUEADO pelo gate de worktree do rainforest-mind.\n\n` +
    `${motivo}\n` +
    `Repo: ${toplevel}\n` +
    `Agente: ${agente}\n\n` +
    `Este e o diretorio de trabalho principal, nao um worktree isolado. A regra 11 manda\n` +
    `subagente que edita arquivos trabalhar em worktree proprio, para o trabalho poder ser\n` +
    `descartado sem tocar no estado dele. Em 2026-08-08 um agente escreveu aqui duas vezes,\n` +
    `trocou a branch e moveu o HEAD com stash/pop.\n\n` +
    saidas
  );
  process.exit(2);
}

// `cd X` isolado num segmento do encadeamento.
const CD = /^\s*cd\s+(?:--\s+)?(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))\s*$/;
// Diretorio que o proprio git recebe, e que vence o cwd do shell.
const GIT_DIR_EXPLICITO = /\bgit\b[^\n;&|]*?(?:-C|--work-tree(?:=|\s+))\s*(?:"([^"]+)"|'([^']+)'|([^\s;&|]+))/;

/**
 * Diretorios onde os `git` que MEXEM no repo realmente vao rodar.
 *
 * O bug que isto conserta (2026-08-09, repo inovacao): o alvo era `ev.cwd`, o cwd
 * REGISTRADO da sessao do agente. Como o cwd registrado de um subagente e o diretorio
 * principal, `cd <worktree> && git commit` era lido como commit no diretorio do usuario e
 * barrado — com a assinatura do bug na mensagem, "Repo:" sem o sufixo do worktree.
 * Efeito pratico: toda entrega de subagente exigia commit da janela principal, o que
 * empurra trabalho mecanico para o lugar caro e contraria a regra 10.
 *
 * O `ao_colher` avisou do buraco obvio, e ele e real: ler o `cd` e mandar ver
 * trocaria o falso positivo por um falso NEGATIVO, que e o lado caro —
 * `cd /worktree/ok && git -C /repo/principal commit` passaria batido num parser
 * ingenuo. Por isso aqui NAO se escolhe um alvo: percorre-se o encadeamento
 * mantendo o diretorio corrente, e cada git-que-mexe contribui com o SEU diretorio.
 * Basta um deles cair no diretorio principal para bloquear.
 *
 * Conservador de proposito: `cd` que nao da para resolver (variavel, subshell,
 * `cd -`) marca o diretorio corrente como INCERTO, e dai em diante os alvos incluem
 * tambem o cwd registrado. Na duvida o gate barra — falso positivo custa uma ida e
 * volta, falso negativo custa o estado do usuario.
 */
function alvosBash(comando, cwdInicial) {
  const segmentos = comando.split(/&&|\|\||;|\n|\|/);
  let atual = cwdInicial;
  let incerto = false;
  const alvos = [];

  for (const seg of segmentos) {
    const cd = seg.match(CD);
    if (cd) {
      const destino = cd[1] || cd[2] || cd[3];
      // `cd -`, `cd ~`, `$VAR`, `$(...)`: nao da para resolver aqui sem executar.
      //
      // O `~` so e expansao de home no COMECO (`~`, `~/x`, `~fulano/x`). Ate
      // 2026-08-17 este teste era /[$`~]/, que casava com o til em QUALQUER
      // posicao — e caminho do Windows tem til no meio o tempo todo, na forma
      // 8.3: `C:/Users/RUNNER~1/...`, `C:/Users/LUISFE~1/...`. O efeito era o
      // pior possivel para um gate: `cd <worktree> && git commit` num caminho
      // 8.3 virava INCERTO, o conservadorismo somava o cwd principal aos alvos,
      // e o gate BARRAVA um commit perfeitamente legitimo dentro do worktree.
      // Achado pelo CI (Issue #16): o TEMP do runner e `C:/Users/RUNNER~1/...`,
      // e a bateria hooks/testa-gate-worktree.sh ficou vermelha la e verde aqui.
      // `$` e crase continuam valendo em qualquer posicao — sao expansao mesmo.
      if (/[$`]/.test(destino) || /^~/.test(destino) || destino === "-") { incerto = true; continue; }
      atual = path.resolve(atual, destino);
      continue;
    }
    if (!GIT_QUE_MEXE.test(seg)) continue;

    const exp = seg.match(GIT_DIR_EXPLICITO);
    if (exp) {
      const p = exp[1] || exp[2] || exp[3];
      // `-C` com variavel: nao da para resolver — cai no conservador.
      if (/[$`]/.test(p)) { alvos.push(cwdInicial); continue; }
      alvos.push(path.resolve(atual, p));
      continue;
    }
    alvos.push(atual);
    if (incerto) alvos.push(cwdInicial);
  }
  return alvos;
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0); // payload ilegivel nunca trava o trabalho do usuario
  }

  // A janela principal e livre: o gate existe para quem foi despachado.
  if (!ev.agent_id) process.exit(0);
  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  const cwdDoEvento = ev.cwd || process.cwd();
  // Toggle do setup: quem nao quer este gate num repositorio pode desliga-lo por
  // `.rainforest/config.json` do projeto, ou de vez no arquivo de dados. A leitura
  // mora em hooks/lib/config.cjs e falha para o lado de LIGAR - config ilegivel
  // nao pode virar trava desligada em silencio.
  try { if (!require("./lib/config.cjs").ligado("gate-worktree", { projeto: cwdDoEvento })) process.exit(0); } catch {}

  const entrada = ev.tool_input || {};
  const nome = ev.tool_name;
  const cwd = cwdDoEvento;
  let alvos = [];
  let motivo = null;

  if (FERRAMENTAS_DE_ESCRITA.has(nome)) {
    const alvo = entrada.file_path || entrada.notebook_path || null;
    if (alvo) { alvos = [alvo]; motivo = `Escrita (${nome}) em ${alvo}`; }
  } else if (nome === "Bash" && typeof entrada.command === "string") {
    const m = entrada.command.match(GIT_QUE_MEXE);
    if (!m) process.exit(0);
    alvos = alvosBash(entrada.command, cwd);
    motivo = `Comando que mexe no estado do repo: git ${m[1]}`;
  }

  if (!alvos.length) process.exit(0);

  for (const alvo of alvos) {
    const estado = estadoDoRepo(dirDe(alvo));
    if (!estado) continue;           // fora de repo git: livre
    if (estado.ehWorktree) continue; // worktree linkado: era pra ser isso mesmo
    if (fs.existsSync(path.join(estado.toplevel, ".rainforest-gate-off"))) continue;
    bloqueia(motivo, estado.toplevel, `${ev.agent_type || "?"} (${ev.agent_id})`);
  }
  process.exit(0);
}

main();
