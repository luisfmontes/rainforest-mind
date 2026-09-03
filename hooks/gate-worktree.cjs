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
 *   - so age quando ha `agent_id` — a janela principal nunca e barrada, EXCETO
 *     no caso de sessao co-locada abaixo;
 *   - escrita de arquivo (Write/Edit/MultiEdit/NotebookEdit) para dentro de
 *     repo git que NAO e worktree linkado;
 *   - Bash: so a lista curta de comandos que mexem no estado do repo
 *     (stash, checkout, switch, reset, merge, rebase, commit, clean) — foi
 *     `git stash`/`pop` que moveu o HEAD do usuario na falha N1. Leitura passa.
 *   - fora de repo git passa sempre;
 *   - dentro do SCRATCHPAD da sessao passa sempre, MESMO sendo repo git. Ate
 *     2026-09-01 a isencao era so "nao e repo git", e clone de terceiro no
 *     scratchpad E repo git: a avaliacao de repo alheio — justamente o trabalho
 *     para o qual o scratchpad existe — rodava barrada, com a mensagem chamando
 *     um clone descartavel de "diretorio de trabalho principal". O docblock ja
 *     prometia "scratchpad, temp"; o codigo nao cumpria.
 *     A isencao e do scratchpad, NAO do temp inteiro: a primeira tentativa deste
 *     conserto isentou `os.tmpdir()` todo, e a caixa de areia da propria bateria
 *     (`mktemp -d`) caiu dentro dela — 23 casos que deviam barrar passaram, e o
 *     gate ficou inerte sem ninguem notar pela cor da suite.
 *
 * SEGUNDA TRAVA, e esta e da JANELA PRINCIPAL (2026-08-21, Issues #25 e #38):
 * duas janelas do Claude Code abertas no MESMO diretorio, `git checkout -b` numa
 * delas arrancou a outra da branch em que ela trabalhava — e ela commitou tres
 * vezes na branch alheia sem perceber. Onze registros do acervo na mesma familia,
 * e o texto da regra 11 tinha sido seguido corretamente: a saida que ele prescrevia
 * ("branch nova, tirada da base") E o ato que causa o dano. HEAD e do CHECKOUT,
 * nao da janela. Aqui isso vira exit 2, com `git worktree add` como saida.
 *
 * Saidas de emergencia, as duas nomeadas na mensagem de bloqueio:
 *   - env RAINFOREST_GATE_OFF=1  → desliga na sessao inteira;
 *   - arquivo .rainforest-gate-off na raiz do repo → desliga naquele repo.
 */

const { execFileSync } = require("node:child_process");
const os = require("node:os");
const fs = require("node:fs");
const path = require("node:path");
const { resolverCwdEfetivo, toplevelConfinado, CD, GIT_DIR_EXPLICITO, SEPARADORES } = require(path.join(__dirname, "lib", "cwd-efetivo.cjs"));
const CLIS_QUE_ESCREVEM = require(path.join(__dirname, "lib", "clis-que-escrevem.cjs"));

const FERRAMENTAS_DE_ESCRITA = new Set(["Write", "Edit", "MultiEdit", "NotebookEdit"]);
// Subcomandos de git que mexem no estado do checkout. `git stash`/`pop` foi a falha N1.
const VERBOS_QUE_MEXEM = new Set([
  "stash", "checkout", "switch", "co", "reset", "merge", "rebase",
  "commit", "clean", "cherry-pick", "revert",
]);
// Opcoes globais do git, as que vem ANTES do subcomando. As de valor separado
// (`-C <dir>`, `-c <k=v>`) precisam comer o proprio argumento, senao o valor delas
// e lido como se fosse o subcomando.
const GLOBAIS_COM_VALOR = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path",
]);

/**
 * Quebra a linha de comando em palavras respeitando aspas simples e duplas.
 * E o que impede `git commit -m "checkout later"` de virar um checkout: o texto
 * da mensagem sai como UMA palavra, e nao como candidato a subcomando.
 */
function palavras(cmd) {
  const out = [];
  let atual = "";
  let aspa = null;
  let temAlgo = false;
  for (let i = 0; i < cmd.length; i += 1) {
    const c = cmd[i];
    if (aspa) {
      if (c === aspa) aspa = null;
      else atual += c;
      temAlgo = true;
    } else if (c === '"' || c === "'") {
      aspa = c;
      temAlgo = true;
    } else if (/\s/.test(c)) {
      if (temAlgo) out.push(atual);
      atual = "";
      temAlgo = false;
    } else {
      atual += c;
      temAlgo = true;
    }
  }
  if (temAlgo) out.push(atual);
  return out;
}

/**
 * Acha o subcomando de `git` num segmento, com os argumentos dele.
 * @returns {{verbo: string, args: string[]}|null}
 */
function subcomandoGit(cmd) {
  const w = palavras(cmd);
  for (let i = 0; i < w.length; i += 1) {
    if (w[i] !== "git" && !/[\\/]git(\.exe)?$/.test(w[i])) continue;
    let j = i + 1;
    while (j < w.length && w[j].startsWith("-")) {
      if (GLOBAIS_COM_VALOR.has(w[j])) j += 2;
      else j += 1;
    }
    return j < w.length ? { verbo: w[j], args: w.slice(j + 1) } : null;
  }
  return null;
}

/** Primeiro verbo de git da linha inteira que caia no conjunto dado, ou null. */
function verboNaLinha(comando, conjunto) {
  for (const seg of comando.split(SEPARADORES)) {
    const s = subcomandoGit(seg);
    if (s && conjunto.has(s.verbo)) return s.verbo;
  }
  return null;
}

/**
 * Verbos que movem o HEAD do CHECKOUT — os unicos que a trava de sessao co-locada
 * cobre, e o recorte e deliberado (D2 do design de 2026-08-21).
 *
 * `commit`, `merge`, `rebase` e `reset` ficam de FORA. Barrar os verbos que MEXEM
 * inteiros barraria as duas sessoes simetricamente — inclusive a DONA legitima da
 * branch, que so quer commitar no trabalho dela. Trava que atrapalha quem esta
 * certo vira trava desligada, e ai ela nao protege mais ninguem.
 */
const VERBOS_QUE_MOVEM = new Set(["checkout", "switch", "co"]);
// Restauram arquivo, nao movem o HEAD.
const FLAGS_DE_RESTAURO = new Set(["-p", "--patch", "--", "--ours", "--theirs", "--merge", "-m"]);
// Movem o HEAD sem sombra de duvida.
const FLAGS_QUE_MOVEM = new Set(["-b", "-B", "-c", "-C", "--orphan", "--detach", "-d", "--track", "-t", "--guess"]);

/**
 * Este comando move o HEAD do checkout em `cwd`?
 *
 * A licao das duas tentativas anteriores: decidir isto pela FORMA lexica do
 * argumento e indecidivel — `agente/t7` e `docs/x.md` tem a mesma cara. A primeira
 * casava a palavra em qualquer lugar e barrava `git commit -m "checkout later"`;
 * a segunda exigia nome sem ponto nem barra e deixava passar `git checkout
 * agente/t7`, que e literalmente o comando do incidente.
 *
 * O que resolve: quem decide TEM o cwd. Caminho existe em disco e e verificavel;
 * ref nao existe em disco. E o que sobrar ambiguo BARRA, porque barrar errado
 * custa uma mensagem explicando o worktree e deixar passar errado custa o HEAD da
 * outra sessao andando debaixo dela.
 */
function moveOHead(cmd, cwd, existe = fs.existsSync) {
  const s = subcomandoGit(cmd);
  if (!s || !VERBOS_QUE_MOVEM.has(s.verbo)) return false;
  const args = s.args;

  // `--` em qualquer posicao: o que vem depois e caminho, e a forma
  // `git checkout <tree-ish> -- <paths>` nao move o HEAD.
  if (args.includes("--")) return false;

  for (const a of args) {
    if (FLAGS_QUE_MOVEM.has(a)) return true;
    if (FLAGS_DE_RESTAURO.has(a)) return false;
  }

  const posicionais = args.filter((a) => !a.startsWith("-"));
  if (posicionais.length === 0) return true; // `git switch` pelado: pergunta ao git, barra
  return !posicionais.every((a) => existe(path.resolve(cwd, a)));
}

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

// Raiz temporaria do sistema, normalizada uma vez. O scratchpad da sessao mora
// abaixo dela, em `<temp>/claude/<projeto>/<sessao>/scratchpad`.
const TEMP_DO_SISTEMA = path.resolve(os.tmpdir()).replace(/\\/g, "/").toLowerCase();

/**
 * O alvo esta dentro do scratchpad da sessao?
 *
 * Duas condicoes, e as DUAS sao necessarias: abaixo do temp do sistema E com um
 * segmento `scratchpad` no caminho. So a primeira isentaria qualquer repo criado
 * em temp — inclusive a caixa de areia desta bateria.
 */
function ehScratchpad(alvo) {
  const n = path.resolve(alvo).replace(/\\/g, "/").toLowerCase();
  if (n !== TEMP_DO_SISTEMA && !n.startsWith(TEMP_DO_SISTEMA + "/")) return false;
  return n.split("/").includes("scratchpad");
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
 *
 * O `casa` e parametro desde 2026-08-21 porque a trava de sessao co-locada olha um
 * recorte MENOR de verbos (so os que movem o HEAD). Reescrever esta travessia para ela
 * duplicaria o parser de `cd` — e e o parser de `cd`, nao a lista de verbos, que
 * concentra os dois modos de falha que este comentario descreve.
 *
 * `casa` recebe `(segmento, cwdDoSegmento)` — o cwd vai junto porque decidir se um
 * `git checkout X` move o HEAD depende de X existir em disco, e so esta travessia
 * sabe em que diretorio o segmento vai rodar.
 *
 * Devolve `{dir, verbo}` por alvo: quem bloqueia precisa nomear o verbo na mensagem,
 * e o verbo e do SEGMENTO que casou, nao da linha inteira.
 */
function alvosBash(comando, cwdInicial, casa = (seg) => {
  const s = subcomandoGit(seg);
  return !!s && VERBOS_QUE_MEXEM.has(s.verbo);
}) {
  const segmentos = comando.split(SEPARADORES);
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
      // 8.3: `C:/PROGRA~1/...`, `<home>/DOCUM~1/...`. O efeito era o
      // pior possivel para um gate: `cd <worktree> && git commit` num caminho
      // 8.3 virava INCERTO, o conservadorismo somava o cwd principal aos alvos,
      // e o gate BARRAVA um commit perfeitamente legitimo dentro do worktree.
      // Achado pelo CI (Issue #16): temp do runner pode ter formato 8.3,
      // e a bateria hooks/testa-gate-worktree.sh ficou vermelha la e verde aqui.
      // `$` e crase continuam valendo em qualquer posicao — sao expansao mesmo.
      if (/[$`]/.test(destino) || /^~/.test(destino) || destino === "-") { incerto = true; continue; }
      atual = path.resolve(atual, destino);
      continue;
    }
    if (!casa(seg, atual)) continue;
    const s = subcomandoGit(seg);
    const verbo = s ? s.verbo : "?";

    const exp = seg.match(GIT_DIR_EXPLICITO);
    if (exp) {
      const p = exp[1] || exp[2] || exp[3];
      // `-C` com variavel: nao da para resolver — cai no conservador.
      if (/[$`]/.test(p)) { alvos.push({ dir: cwdInicial, verbo }); continue; }
      alvos.push({ dir: path.resolve(atual, p), verbo });
      continue;
    }
    alvos.push({ dir: atual, verbo });
    if (incerto) alvos.push({ dir: cwdInicial, verbo });
  }
  return alvos;
}

/**
 * Quebra em tokens preservando se cada um veio de DENTRO de aspas.
 *
 * `q: true` significa "este texto estava entre aspas" — e um `>` ali e TEXTO,
 * nunca redirecionamento. E o conserto de 2026-09-01: um avaliador de repo de
 * terceiro foi barrado rodando
 *   grep -n "qualified_name\|<project>" README.md
 * — comando sem redirecionamento nenhum. O gate casava o `>` de `<project>` no
 * texto cru do comando. `->`, `=>`, generics e tag HTML sao rotina em busca de
 * codigo, entao o falso positivo era diario e empurrava o agente a reescrever
 * comando legitimo ate passar. `palavras()` ja sabia respeitar aspas para achar
 * subcomando de git; a deteccao de escrita e que tinha ficado no regex cru.
 */
function tokensComAspas(cmd) {
  const out = [];
  let atual = "", aspa = null, temAlgo = false, citado = false;
  for (let i = 0; i < cmd.length; i += 1) {
    const c = cmd[i];
    if (aspa) {
      if (c === aspa) aspa = null;
      else atual += c;
      temAlgo = true;
    } else if (c === '"' || c === "'") {
      aspa = c; temAlgo = true; citado = true;
    } else if (/\s/.test(c)) {
      if (temAlgo) out.push({ v: atual, q: citado });
      atual = ""; temAlgo = false; citado = false;
    } else {
      atual += c; temAlgo = true;
    }
  }
  if (temAlgo) out.push({ v: atual, q: citado });
  return out;
}

// Operador de redirecionamento: quando a linha de comando redireciona para arquivo.
// Procura por padrao no inicio do token, diferente de operadores em nomes.
const OPERADOR_REDIRECT = /^(?:[0-9]*|&)(>>?)(.*)$/;

/** Nome de comando, ignorando caminho: um binario com caminho resolve para seu nome. */
function ehComando(tok, nome) {
  return !tok.q && new RegExp("(^|[\\\\/])" + nome + "(\\.exe)?$").test(tok.v);
}

/** Posicionais de um segmento a partir do indice do comando (pula flags). */
function posicionaisApos(toks, i) {
  return toks.slice(i + 1).filter((t) => !t.v.startsWith("-"));
}

/**
 * Procura por CLI externa que escreve (codex, gemini, claude, aider, cursor, copilot).
 * Retorna o nome da CLI encontrada, ou null.
 *
 * Token citado so e IGNORADO em posicao de ARGUMENTO (`echo "codex"`): ali e
 * texto. Em posicao de COMANDO — primeiro token de cada segmento separado por
 * `;`, `&&`, `||`, `|` — um token citado (`"codex" exec --yolo`) e comando de
 * verdade disfarcado de string, e ate 2026-09-03 passava batido porque o
 * `if (tok.q) continue` pulava TODO token citado, sem olhar a posicao.
 */
function procuraCLI(comando, clis) {
  const segmentos = comando.split(SEPARADORES);
  for (const seg of segmentos) {
    const toks = tokensComAspas(seg);
    for (let i = 0; i < toks.length; i += 1) {
      const tok = toks[i];
      if (tok.q && i !== 0) continue; // citado em posicao de argumento: ignora
      // Extrair nome do token, ignorando caminho e extensão .exe
      const nome = tok.v.split(/[\\/]/).pop().replace(/\.exe$/, "");
      if (clis.includes(nome)) {
        return nome;
      }
    }
  }
  return null;
}

/**
 * Detecta escrita em Bash via redirecionamento ou ferramentas comuns.
 * Resolve alvos e retorna {dir, tipo} para cada um.
 *
 * Tipos: ">", ">>", "tee", "sed", "cp", "mv", e construcoes nao-resolvidas.
 * Mantem a mesma seguranca do `alvosBash`: `cd` que nao resolve vira INCERTO
 * e conservadorismo inclui cwdInicial nos alvos.
 *
 * Tudo aqui decide por TOKEN, nunca por match no texto cru — ver o docblock de
 * `tokensComAspas`.
 */
function alvosBashEscrita(comando, cwdInicial) {
  const segmentos = comando.split(SEPARADORES);
  let atual = cwdInicial;
  let incerto = false;
  const alvos = [];

  // Resolve o alvo contra o cwd corrente; construcao com $ ou ` fica INCERTA e
  // aponta para o proprio diretorio, que e o lado seguro.
  const empurra = (alvo, tipo) => {
    if (!alvo) return;
    if (/[$`]/.test(alvo)) alvos.push({ dir: atual, tipo });
    else alvos.push({ dir: path.resolve(atual, alvo), tipo });
  };

  for (const seg of segmentos) {
    // `cd` precisa ser tratado igual ao `alvosBash`
    const cd = seg.match(CD);
    if (cd) {
      const destino = cd[1] || cd[2] || cd[3];
      if (/[$`]/.test(destino) || /^~/.test(destino) || destino === "-") { incerto = true; continue; }
      atual = path.resolve(atual, destino);
      continue;
    }

    const toks = tokensComAspas(seg);

    // Redirecionamento: `> arq`, `>>arq`, `2>arq`. `2>&1` e `>&2` duplicam
    // descritor e nao escrevem em arquivo nenhum — nao sao alvo.
    for (let i = 0; i < toks.length; i += 1) {
      if (toks[i].q) continue;
      const m = toks[i].v.match(OPERADOR_REDIRECT);
      if (!m) continue;
      const tipo = m[1] === ">>" ? ">>" : ">";
      let alvo = m[2];
      if (alvo.startsWith("&")) continue;
      if (!alvo) {
        const prox = toks[i + 1];
        if (!prox) continue;
        alvo = prox.v;
        i += 1;
      }
      empurra(alvo, tipo);
    }

    for (let i = 0; i < toks.length; i += 1) {
      // `tee arquivo`, `tee -a arquivo`
      if (ehComando(toks[i], "tee")) {
        const pos = posicionaisApos(toks, i);
        if (pos.length) empurra(pos[0].v, "tee");
        break;
      }
      // `sed -i arquivo` — so com a flag de edicao no lugar. O alvo e o ULTIMO
      // posicional: antes dele vem a expressao, que pode ser varios argumentos.
      if (ehComando(toks[i], "sed")) {
        const temInPlace = toks.slice(i + 1).some((t) => !t.q && /^-[a-z]*i/.test(t.v));
        if (!temInPlace) break;
        const pos = posicionaisApos(toks, i);
        if (pos.length) empurra(pos[pos.length - 1].v, "sed");
        break;
      }
      // `cp origem destino`, `mv origem destino` — o destino e o ultimo posicional,
      // que e o que vale tambem para `cp a b c pasta/`.
      if (ehComando(toks[i], "cp") || ehComando(toks[i], "mv")) {
        const tipo = ehComando(toks[i], "cp") ? "cp" : "mv";
        const pos = posicionaisApos(toks, i);
        if (pos.length >= 2) empurra(pos[pos.length - 1].v, tipo);
        break;
      }
    }
  }

  // Conservadorismo: se houver `cd` nao-resolvivel, incluir cwdInicial tambem
  if (incerto && alvos.length > 0) {
    alvos.push({ dir: cwdInicial, tipo: "?" });
  }

  return alvos;
}

/**
 * Mensagem da trava de sessao co-locada. Publico: a JANELA PRINCIPAL.
 *
 * Aqui as escotilhas SAO nomeadas, ao contrario da mensagem ao subagente. O P1 do
 * relatorio de 2026-08-11 e sobre AUTORIDADE, nao sobre segredo: um implementador
 * despachado leu o nome do arquivo de escape na propria mensagem de bloqueio e se
 * desligou a trava. Quem le ESTA mensagem e quem tem a autoridade de decidir seguir
 * — e uma trava que barra sem dizer como sair e uma trava que o usuario arranca.
 */
function bloqueiaColocada(verbo, toplevel, outras, agora) {
  const lista = outras
    .map((s) => {
      const min = Math.round((agora - s.ultimo_ts) / 60000);
      return `  - ${s.session_id} — ${s.parada ? "parada" : "ativa"} ha ${min} min`;
    })
    .join("\n");

  process.stderr.write(
    `BLOQUEADO pelo gate de sessao co-locada do rainforest-mind.\n\n` +
    `Comando: git ${verbo} — move o HEAD deste checkout.\n` +
    `Repo: ${toplevel}\n` +
    `Outra(s) sessao(oes) do Claude Code neste MESMO diretorio:\n${lista}\n\n` +
    `HEAD e do CHECKOUT, nao da janela: trocar de branch aqui troca para as duas.\n` +
    `Em 2026-08-21 foi exatamente isso — um \`git checkout -b\` arrancou a outra sessao\n` +
    `da branch dela, e ela commitou tres vezes na branch alheia sem perceber\n` +
    `(Issues #25 e #38, 11 registros do acervo na mesma familia).\n\n` +
    `A SAIDA e um checkout so seu, que ninguem mais compartilha:\n` +
    `  git worktree add .claude/worktrees/<nome> -b <branch>\n` +
    `  cd .claude/worktrees/<nome>\n` +
    `Assim as duas sessoes ficam donas do proprio HEAD, e nenhuma move o da outra.\n\n` +
    `Se voce SABE que a outra sessao nao esta trabalhando aqui, tem tres saidas:\n` +
    `  - node scripts/setup.cjs --desligar gate-worktree --escopo projeto (preferida);\n` +
    `  - RAINFOREST_GATE_OFF=1 no ambiente da sessao (desliga na sessao inteira);\n` +
    `  - arquivo .rainforest-gate-off na raiz do repo (desliga so naquele repo).\n`
  );
  process.exit(2);
}

/**
 * A trava de sessao co-locada. Volta sem fazer nada quando nao se aplica; nao volta
 * quando barra.
 *
 * FALHA PARA O LADO DE LIBERAR em tudo que ela nao consegue medir — sem `session_id`
 * no evento, sem `sessoes.json`, sem raiz de dados, fora de repo git. E o mesmo
 * principio que o `estadoDoRepo` ja aplica quando o git nao responde, e aqui ele pesa
 * mais: esta e a UNICA condicao do arquivo que pode barrar a janela principal, e um
 * falso positivo aqui trava o trabalho de quem esta sozinho no repo.
 *
 * O `session_id` e o que distingue quem pergunta de quem esta la — as duas entradas
 * do incidente tinham `cwd` identico, entao `cwd` sozinho nao serve (D5). O hook
 * recebe o campo; quem prova e `hooks/heartbeat.cjs:50`, que escreve as chaves do
 * `sessoes.json` com ele.
 */
function gateDeSessaoColocada(ev, cwd) {
  if (ev.tool_name !== "Bash") return;
  const comando = (ev.tool_input || {}).command;
  if (typeof comando !== "string") return;
  // Recusa barata antes de tocar em disco: a linha tem algum verbo que possa mover
  // o HEAD? Quem decide de verdade e o `moveOHead` la embaixo, com o cwd do segmento.
  if (!verboNaLinha(comando, VERBOS_QUE_MOVEM)) return;
  if (!ev.session_id) return;

  const agora = Date.now();
  let outras;
  try {
    outras = require("./lib/contexto-sessao.cjs")
      .sessaoColocada({ cwd, sessionId: ev.session_id, agora });
  } catch {
    return;
  }
  if (!Array.isArray(outras) || !outras.length) return;

  // O `checkout` precisa cair NESTE checkout para doer. `cd .claude/worktrees/x &&
  // git checkout -b y` e justamente a saida que a mensagem de bloqueio recomenda, e
  // barra-la seria fechar a porta e a janela ao mesmo tempo: o worktree tem toplevel
  // proprio, entao ele nao casa com o daqui e passa. O parser de `cd` do `alvosBash`
  // ja resolve o encadeamento, incluindo o conservadorismo do `cd` nao-resolvivel.
  const daqui = estadoDoRepo(cwd);
  if (!daqui) return; // fora de repo git: nao ha HEAD para mover
  if (fs.existsSync(path.join(daqui.toplevel, ".rainforest-gate-off"))) return;

  for (const alvo of alvosBash(comando, cwd, moveOHead)) {
    const estado = estadoDoRepo(dirDe(alvo.dir));
    if (!estado) continue;
    if (estado.toplevel !== daqui.toplevel) continue;
    bloqueiaColocada(alvo.verbo, daqui.toplevel, outras, agora);
  }
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
  try { if (!require("./lib/config.cjs").ligado("gate-worktree", { projeto: cwdDoEvento })) process.exit(0); } catch {}

  // AS DUAS SAIDAS DE EMERGENCIA SUBIRAM PARA CA em 2026-08-21, e a ordem e o ponto:
  // elas ficavam DEPOIS do `if (!ev.agent_id)`, entao a janela principal saia antes
  // de o toggle ser sequer lido. Enquanto o gate so barrava subagente isso nao tinha
  // efeito visivel; com a trava de sessao co-locada teria — `--desligar gate-worktree`
  // deixaria de desligar o unico ramo que barra a janela principal, que e o ramo em
  // que desligar mais importa. Saida de emergencia que so vale para metade das travas
  // do arquivo e saida quebrada.
  if (!ev.agent_id) {
    // A janela principal e livre em quase tudo — o gate existe para quem foi
    // despachado. A excecao mora aqui, e ela nao volta quando barra.
    gateDeSessaoColocada(ev, cwdDoEvento);
    process.exit(0);
  }

  const entrada = ev.tool_input || {};
  const nome = ev.tool_name;
  const cwd = cwdDoEvento;
  let alvos = [];
  let motivo = null;

  if (FERRAMENTAS_DE_ESCRITA.has(nome)) {
    const alvo = entrada.file_path || entrada.notebook_path || null;
    if (alvo) { alvos = [alvo]; motivo = `Escrita (${nome}) em ${alvo}`; }
  } else if (nome === "Bash" && typeof entrada.command === "string") {
    const verbo = verboNaLinha(entrada.command, VERBOS_QUE_MEXEM);
    if (verbo) {
      alvos = alvosBash(entrada.command, cwd).map((a) => a.dir);
      motivo = `Comando que mexe no estado do repo: git ${verbo}`;
    } else {
      // Inspecionar redirecionamentos e ferramentas de escrita
      const alvosEscrita = alvosBashEscrita(entrada.command, cwd);
      if (alvosEscrita.length > 0) {
        alvos = alvosEscrita.map((a) => a.dir);
        motivo = `Escrita via Bash (redirecionamento ou ferramenta)`;
      } else {
        // Procurar por CLI externa que escreve
        const cli = procuraCLI(entrada.command, CLIS_QUE_ESCREVEM);
        if (cli) {
          const cwdEfetivo = resolverCwdEfetivo(entrada.command, cwd);
          if (cwdEfetivo.incerto) {
            // `cd` que nao resolve (variavel, subshell, `cd -`) pode levar a
            // QUALQUER diretorio, inclusive o principal: `cd $(pwd)/../principal
            // && codex exec --yolo` de dentro do worktree fica incerto, o cwd
            // efetivo cai de volta no proprio worktree (legitimo) e o gate
            // liberava. Mesmo espirito conservador do `alvosBash` (que soma o
            // cwdInicial aos alvos quando incerto), mas aqui somar nao basta:
            // o destino em si e desconhecido, entao bloqueia direto, sem
            // passar pela classificacao de worktree que depende do proprio
            // cwd que nao da pra confiar.
            if (!ehScratchpad(cwd)) {
              const estadoAqui = estadoDoRepo(cwd);
              if (estadoAqui && !fs.existsSync(path.join(estadoAqui.toplevel, ".rainforest-gate-off"))) {
                bloqueia(
                  `CLI que escreve (${cli}) com cd nao resolvido — destino desconhecido`,
                  estadoAqui.toplevel,
                  `${ev.agent_type || "?"} (${ev.agent_id})`
                );
              }
            }
          } else {
            alvos = [cwdEfetivo.cwd];
            motivo = `CLI que escreve (${cli})`;
          }
        }
      }
    }
  }

  if (!alvos.length) process.exit(0);

  for (const alvo of alvos) {
    if (ehScratchpad(alvo)) continue; // scratchpad da sessao: livre, ainda que seja repo git
    const estado = estadoDoRepo(dirDe(alvo));
    if (!estado) continue;           // fora de repo git: livre
    if (estado.ehWorktree) continue; // worktree linkado: era pra ser isso mesmo
    if (fs.existsSync(path.join(estado.toplevel, ".rainforest-gate-off"))) continue;
    bloqueia(motivo, estado.toplevel, `${ev.agent_type || "?"} (${ev.agent_id})`);
  }
  process.exit(0);
}

main();
