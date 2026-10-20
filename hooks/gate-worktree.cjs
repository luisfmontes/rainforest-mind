#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse — barra subagente que escreve fora de worktree isolado.
 * Protege contra: escrita de subagente fora de worktree isolado via Write/Edit/Bash
 * Não protege contra: edição da janela principal fora de worktree (sem agent_id)
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
 *   - chave do config do projeto → desliga naquele repo.
 * O arquivo `.rainforest-gate-off` deixou de ser lido (#417).
 */

const { execFileSync } = require("node:child_process");
const os = require("node:os");
const fs = require("node:fs");
const path = require("node:path");
const { caminhoExecutavel } = require(path.join(__dirname, "lib", "resolver-executavel.cjs"));
const { cwdPorSegmento, resolverMovedor, toplevelConfinado, extrairUltimoDirGit, segmentosComAspas, SEPARADORES } = require(path.join(__dirname, "lib", "cwd-efetivo.cjs"));
const CLIS_QUE_ESCREVEM = require(path.join(__dirname, "lib", "clis-que-escrevem.cjs"));
// #530 (D4, D6): a palavra de comando como o bash a le, e o corpo de cada
// substituicao de comando (crase e `$(...)`), para o gate conferir o que roda la dentro.
const { normalizarComando, corposDeSubstituicao, expandirChaves } = require(path.join(__dirname, "lib", "palavra-bash.cjs"));
const { mascararCorposDeHeredoc } = require(path.join(__dirname, "lib", "heredoc.cjs"));
const {
  tokensComAspas, ehComando, WRAPPERS_QUE_REPASSAM, posicaoDeComando, textoAPartir, desempacotarWrapperDeString,
} = require(path.join(__dirname, "lib", "tokens-comando.cjs"));

const FERRAMENTAS_DE_ESCRITA = new Set(["Write", "Edit", "MultiEdit", "NotebookEdit"]);
// Subcomandos de git que mexem no estado do checkout. `git stash`/`pop` foi a falha N1.
const VERBOS_QUE_MEXEM = new Set([
  "stash", "checkout", "switch", "co", "reset", "merge", "rebase",
  "commit", "clean", "cherry-pick", "revert", "restore",
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
 *
 * Rodada 19 (lote 3): `{`/`}`/`(`/`)` FORA de aspas tambem viram fronteira de
 * palavra (tratados como espaco, nunca entram no resultado) — sem isto,
 * `&{git checkout main}` (call operator do PowerShell colado ao scriptblock)
 * virava as palavras `["&{git", "checkout", "main}"]`: nem `"&{git"` nem
 * `"main}"` batem com `"git"`/`"main"` exatos, e a checagem de sessao
 * co-locada (que busca a palavra `git` literal via `subcomandoGit`) nunca
 * achava o comando. Dentro de aspas nada muda: `"fix {json} parse"` continua
 * saindo como UMA palavra so.
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
    } else if (/\s/.test(c) || c === "{" || c === "}" || c === "(" || c === ")") {
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
 * Sentinela do teto (#530 rodada extra 2, tarefa 11): um wrapper legivel que sobra
 * depois do quarto nivel nao e desembrulhado. `subcomandoGit` devolve isto no lugar
 * do nada, e cada chamador o trata como casamento: falha fechado, nunca "nao achei git".
 */
const SUB_ANINHADO = { verbo: "?", args: [], incerto: true };
const MOTIVO_ANINHADO = "wrapper aninhado demais para conferir (mais de 4 niveis)";

/**
 * Acha o subcomando de `git` num segmento, com os argumentos dele.
 *
 * T2 (rodada 11, lote 3, 2026-09-04): nenhuma palavra bate com `git` — o
 * segmento pode ser um wrapper de STRING escondendo o `git` de verdade
 * (`Invoke-Expression "git commit -m x"`/`iex "..."`, `eval "..."`,
 * `bash -c "..."`/primos, `pwsh -Command "..."`, `cmd /c "..."`). Conteudo
 * LEGIVEL reprocessa recursivamente (pode ele mesmo ser outro wrapper).
 * Conteudo ILEGIVEL (`$(`, crase, variavel) nao tem como saber — cai no
 * `null` de "nao achei git aqui", sem falso positivo (o chamador que decide
 * incerteza de `cd`/CLI ja cobre esse conservadorismo pelo lado do cwd).
 *
 * #530 rodada extra (2026-10-15): devolve LISTA, um subcomando por leitura que
 * achou git (cru e normalizada, ver `leiturasDoComando`), sem duplicar. Os
 * chamadores barram se QUALQUER item der verbo no conjunto: a leitura do bash
 * so acrescenta bloqueio, nunca tira.
 *
 * @returns {Array<{verbo: string, args: string[]}>}
 */
function subcomandoGit(cmd, ferramenta, profundidade = 0) {
  const textos = [String(cmd), textoLido(cmd, ferramenta).seg];
  const achados = [];
  // #530 rodada extra 2: uma recursao por interno distinto (texto + ferramenta). Duas
  // leituras com o mesmo interno (`'eval' ` e `\eval `) dobravam o custo a cada nivel:
  // 22 niveis passavam de 60 s. Mais de 4 niveis nao recursa; quem barra e
  // alvosBashEscrita, com o motivo de sempre.
  const internosVistos = new Set();
  leiturasDoComando(cmd, ferramenta).forEach((w, k) => {
    if (k === 1 && textos[1] === textos[0]) return;
    const r = subcomandoNasPalavras(w);
    if (r.achou) { if (r.sub) achados.push(r.sub); return; }
    const { interno, ilegivel } = desempacotarWrapperDeString(textos[k], { ferramenta });
    if (interno === null || ilegivel) return;
    const ferr = ferramentaDoInterno(textos[k], ferramenta);
    const chave = interno + "\0" + ferr;
    if (internosVistos.has(chave)) return;
    internosVistos.add(chave);
    if (profundidade < 4) achados.push(...subcomandoGit(interno, ferr, profundidade + 1));
    if (profundidade >= 4) achados.push(SUB_ANINHADO);
  });
  const vistos = new Set();
  return achados.filter((s) => {
    const chave = JSON.stringify([s.verbo, s.args]);
    if (vistos.has(chave)) return false;
    vistos.add(chave);
    return true;
  });
}

/**
 * As duas leituras do comando, como listas de palavras: a do texto cru, exatamente
 * como a base 9f6b9ca3 lia, e a da palavra normalizada do bash. Com a ferramenta
 * PowerShell as duas coincidem.
 */
function leiturasDoComando(texto, ferramenta) {
  return [palavras(String(texto)), palavras(textoLido(texto, ferramenta).seg)];
}

/**
 * Procura o git numa lista de palavras. `achou` diz se a palavra `git` apareceu
 * (mesmo sem verbo depois dela); `sub` e o subcomando, ou null.
 */
function subcomandoNasPalavras(w) {
  for (let i = 0; i < w.length; i += 1) {
    if (w[i] !== "git" && !/[\\/]git(\.exe)?$/.test(w[i])) continue;
    let j = i + 1;
    while (j < w.length && w[j].startsWith("-")) {
      if (GLOBAIS_COM_VALOR.has(w[j])) j += 2;
      else j += 1;
    }
    return { achou: true, sub: j < w.length ? { verbo: w[j], args: w.slice(j + 1) } : null };
  }
  return { achou: false, sub: null };
}

/**
 * Texto que o gate le como comando. #530 rodada 2: so o Bash passa pela normalizacao
 * de `palavra-bash`. O PowerShell le o texto cru, como na base: normalizar
 * `C:\Git\cmd\git.exe` apagava as barras, o git deixava de ser reconhecido e o
 * commit no principal passava.
 */
function textoLido(texto, ferramenta) {
  const ehBash = ferramenta !== "PowerShell";
  return { ehBash, seg: ehBash ? normalizarComando(texto).seg : String(texto) };
}

/**
 * #530 rodada 3: o texto dentro de `powershell -Command "..."`, `pwsh -c` ou `cmd /c`
 * e sintaxe do PowerShell, mesmo quando o wrapper veio de uma chamada Bash. Le-se
 * cru, como o PowerShell le: a palavra do bash apagava as barras de
 * `C:\Git\cmd\git.exe` e o git deixava de ser reconhecido. O primeiro token sai por
 * regex, porque `normalizarNomeExecutavel` nao e exportado por `tokens-comando.cjs`.
 */
function ferramentaDoInterno(segmento, ferramenta) {
  const m = /^\s*(?:"([^"]*)"|'([^']*)'|(\S+))/.exec(String(segmento));
  const tok = m ? (m[1] !== undefined ? m[1] : m[2] !== undefined ? m[2] : m[3]) : "";
  const exe = tok.split(/[\\/]/).pop().replace(/\.exe$/i, "").toLowerCase();
  const ehShellWindows = exe === "pwsh" || exe === "powershell" || exe === "cmd";
  return ehShellWindows ? "PowerShell" : ferramenta;
}

/** Primeiro verbo de git da linha inteira que caia no conjunto dado, ou null. */
function verboNaLinha(comando, conjunto, ferramenta) {
  for (const seg of comando.split(SEPARADORES)) {
    // #530 rodada extra: qualquer leitura do git que der verbo no conjunto barra.
    const s = subcomandoGit(seg, ferramenta).find((x) => x.incerto || conjunto.has(x.verbo));
    if (s) return s.incerto ? SUB_ANINHADO.verbo : s.verbo;
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
 * Detecta se o comando e um restauro de arquivo (nao move HEAD).
 * Devolve uma linha descritiva se for `git checkout -- <caminhos>` ou
 * `git restore <caminhos>`, caso contrario devolve ''.
 *
 * Usado para avisar num subagente bloqueado que tentou restaurar: a trava
 * de worktree barra certo (subagente nao pode escrever no principal), mas
 * o ato de restauro merecia comunicacao, porque a arvore pode ter ficado
 * suja. Restora nao muda (exit 2 mantido), so a mensagem que ganha contexto.
 */
function linhaDeRestauro(cmd, toplevel, ferramenta) {
  // #530 rodada extra: a primeira leitura que der restauro vira a mensagem.
  for (const s of subcomandoGit(cmd, ferramenta)) {
    const linha = linhaDeRestauroDe(s, toplevel);
    if (linha) return linha;
  }
  return '';
}

/** Restauro de um subcomando ja achado por `subcomandoGit`. */
function linhaDeRestauroDe(s, toplevel) {
  // `git restore` e restauro puro — nao tem variante que move HEAD
  if (s.verbo === 'restore') {
    const args = s.args;
    const caminhos = args.filter((a) => !a.startsWith("-")).join(", ");
    if (caminhos) {
      return `a restauracao e da janela principal: git -C ${toplevel} restore ${caminhos} — a arvore pode ter ficado suja por este agente; avise no relato.`;
    }
  }

  // `git checkout` pode ser restauro (`-- <paths>`) ou movimento de HEAD
  if (s.verbo === 'checkout' || s.verbo === 'co') {
    const args = s.args;
    // Se tem `--`, e restauro (arquivo, nao branch)
    if (args.includes("--")) {
      const i = args.indexOf("--");
      const caminhos = args.slice(i + 1).join(", ");
      if (caminhos) {
        return `a restauracao e da janela principal: git -C ${toplevel} checkout -- ${caminhos} — a arvore pode ter ficado suja por este agente; avise no relato.`;
      }
    }
  }

  return '';
}

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
function moveOHead(cmd, cwd, ferramenta, existe = fs.existsSync) {
  // #530 rodada extra: qualquer leitura que mova o HEAD barra.
  return subcomandoGit(cmd, ferramenta).some((s) => s.incerto || moveOHeadDe(s, cwd, existe));
}

/** Movimento de HEAD de um subcomando ja achado por `subcomandoGit`. */
function moveOHeadDe(s, cwd, existe) {
  if (!VERBOS_QUE_MOVEM.has(s.verbo)) return false;
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
    return execFileSync(caminhoExecutavel("git"), ["-C", dir, ...args], {
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

// Windows: nome curto 8.3 (`RUNNER~1`) vira o longo, pelo ancestral mais fundo que existe.
// O git devolve o nome longo; comparar por texto com o curto tirava o cwd do worktree e
// deixava citar o principal pelo nome curto (#552). So caminho com `~` paga o realpath.
const LONGO = new Map();
function semNomeCurto(s) {
  if (process.platform !== "win32" || !s.includes("~")) return s;
  if (LONGO.has(s)) return LONGO.get(s);
  let base = s, resto = "";
  while (!fs.existsSync(base) && path.dirname(base) !== base) {
    resto = "/" + path.basename(base) + resto;
    base = path.dirname(base);
  }
  const real = (p) => fs.realpathSync.native(p).replace(/\\/g, "/").replace(/\/+$/, "");
  let longo = s;
  try {
    // Link no FIM do caminho: so o pai se resolve. Seguir o link trocaria a entrada, que mora
    // no principal, pelo alvo (`rm <P>/link` deixava de barrar). Com caminho depois do link
    // (`<W>/link/novo/f`), a operacao atravessa o link e ele se resolve.
    const ehLink = resto === "" && fs.lstatSync(base).isSymbolicLink();
    longo = (ehLink ? real(path.dirname(base)) + "/" + path.basename(base) : real(base)) + resto;
  } catch {}
  LONGO.set(s, longo);
  return longo;
}

// Raiz temporaria do sistema, normalizada uma vez. O scratchpad da sessao mora
// abaixo dela, em `<temp>/claude/<projeto>/<sessao>/scratchpad`.
const TEMP_DO_SISTEMA = semNomeCurto(path.resolve(os.tmpdir()).replace(/\\/g, "/")).toLowerCase();

/**
 * O alvo esta dentro do scratchpad da sessao?
 *
 * Duas condicoes, e as DUAS sao necessarias: abaixo do temp do sistema E com um
 * segmento `scratchpad` no caminho. So a primeira isentaria qualquer repo criado
 * em temp — inclusive a caixa de areia desta bateria.
 */
function ehScratchpad(alvo) {
  const n = semNomeCurto(path.resolve(alvo).replace(/\\/g, "/")).toLowerCase();
  if (n !== TEMP_DO_SISTEMA && !n.startsWith(TEMP_DO_SISTEMA + "/")) return false;
  return n.split("/").includes("scratchpad");
}

/**
 * Diretorio de onde o repositorio do alvo e lido: o proprio alvo se for diretorio,
 * senao o primeiro ancestral que existe (#552, D6). Subir um nivel so deixava passar
 * `New-Item <P>/n1/n2/f -Force`: `<P>/n1/n2` nao existe, o git nao achava repositorio.
 */
function dirDe(alvo) {
  try {
    if (fs.existsSync(alvo) && fs.statSync(alvo).isDirectory()) return alvo;
  } catch {}
  let atual = path.dirname(alvo);
  while (!fs.existsSync(atual) && path.dirname(atual) !== atual) atual = path.dirname(atual);
  return atual;
}

function bloqueia(motivo, toplevel, agente, apenasRestauracao = null, ehWorktreeAlvo = false) {
  // P1 do relatorio 2026-08-11-escotilha-do-gate-usada-para-contornar: a saida
  // de emergencia era NOMEADA na mensagem que o SUBAGENTE le. Um implementador
  // bloqueado leu o nome do arquivo de escape na propria mensagem de bloqueio,
  // criou o arquivo de desligar na raiz do checkout principal - fora do
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
    : `Quem decide seguir sem isolamento e voce, e tem duas saidas:\n` +
      `  - node scripts/setup.cjs --desligar gate-worktree --escopo projeto (preferida);\n` +
      `  - RAINFOREST_GATE_OFF=1 no ambiente da sessao (desliga na sessao inteira).\n`;

  let msg = `BLOQUEADO pelo gate de worktree do rainforest-mind.\n\n` +
    `${motivo}\n` +
    `Repo: ${toplevel}\n` +
    `Agente: ${agente}\n\n`;

  if (apenasRestauracao) {
    msg += `${apenasRestauracao}\n\n`;
  }

  msg += ehWorktreeAlvo
    ? `Este diretorio E um worktree isolado, mas nao deu para confirmar o cwd real de onde\n` +
      `o comando roda (cd com variavel, subshell ou movedor que o parser nao resolve). Por\n` +
      `precaucao o gate bloqueia mesmo assim — a incerteza pode esconder um comando rodando\n` +
      `em outro lugar, inclusive no diretorio principal.\n\n` +
      saidas
    : `Este e o diretorio de trabalho principal, nao um worktree isolado. A regra 11 manda\n` +
      `subagente que edita arquivos trabalhar em worktree proprio, para o trabalho poder ser\n` +
      `descartado sem tocar no estado dele.\n\n` +
      saidas;

  process.stderr.write(msg);
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
 *
 * Movedores de diretorio (`cd`, `pushd`/`popd`, `env -C`) vem de
 * `resolverMovedor` (lib/cwd-efetivo.cjs) — emenda do auditor a rodada 5
 * (lote 3, 2026-09-03): ate aqui esta funcao so reconhecia `cd` (via
 * `seg.match(CD)` cru), entao `pushd <principal> && git commit -m x` e
 * `env -C <principal> git commit -m x` de dentro do worktree passavam com
 * exit 0 — o A2 do auditor aplicado ao caminho mais critico (commit,
 * checkout, reset, merge no principal). `cwdPorSegmento` ja reconhecia os
 * quatro movedores para o ramo de CLI e para `gate-staging-total.cjs`; agora
 * os tres consumidores chamam o MESMO `resolverMovedor`, em vez de cada um
 * ter sua propria lista (parcial) de movedores.
 *
 * `resolverMovedor` devolve `soMovedor: true` para `cd`/`pushd`/`popd` — a
 * regex e ANCORADA de ponta a ponta, o segmento INTEIRO e so o comando de
 * mudanca de diretorio, e o `casa()` nunca precisa olhar esses segmentos.
 * `env -C` NAO e `soMovedor`: e um PREFIXO (`env -C X git commit -m x`), o
 * `casa()` ainda avalia o RESTO do segmento, so que com o cwd do `-C`
 * (`mov.cwd`) no lugar do `atual` de antes.
 */
function alvosBash(comando, cwdInicial, casa = (seg, _cwd, ferr) => {
  return subcomandoGit(seg, ferr).some((s) => s.incerto || VERBOS_QUE_MEXEM.has(s.verbo));
}, ferramenta) {
  const ehPowerShell = ferramenta === "PowerShell";
  // `segmentosComAspas`, nao `comando.split(SEPARADORES)` cru: o split cru
  // nao respeita aspas (`git commit -m "a & b"` quebraria dentro da mensagem)
  // e, ate a rodada 6, `SEPARADORES` nem reconhecia `&` simples como
  // separador (K1 do auditor, lote 3, 2026-09-03).
  const segmentos = segmentosComAspas(comando, ehPowerShell);
  const estado = { atual: cwdInicial, incerto: false, pilhaPushd: [] };
  const alvos = [];

  for (const seg of segmentos) {
    const mov = resolverMovedor(seg, estado, ehPowerShell);
    if (mov.soMovedor) continue; // cd/pushd/popd: o segmento INTEIRO e o movedor

    if (!casa(seg, mov.cwd, ferramenta)) continue;
    // #530 rodada extra: o verbo da mensagem e o primeiro achado que move o estado
    // (ou que move o HEAD); so sai "?" quando nenhuma leitura achou git.
    const subs = subcomandoGit(seg, ferramenta);
    const aninhado = subs.some((x) => x.incerto === true);
    const s = subs.find((x) => VERBOS_QUE_MEXEM.has(x.verbo) || VERBOS_QUE_MOVEM.has(x.verbo)) || subs[0];
    const verbo = s ? s.verbo : "?";

    // O ÚLTIMO `-C`/`--work-tree` do segmento vence — o git usa o ultimo
    // quando ha varios (`git -C /a -C /b commit` roda em `/b`). O regex
    // antigo so achava a PRIMEIRA ocorrencia (`.match` unico e lazy), entao
    // `git -C <worktree> -C <principal> commit` classificava o alvo como
    // worktree e liberava, com o commit caindo no principal de verdade.
    // #530 (D4): sobre a palavra normalizada. No cru, `{git,-C,X,commit}` casaria
    // o `-C` e capturaria `X,commit,-m,x}` como diretorio.
    const p = extrairUltimoDirGit(textoLido(seg, ferramenta).seg);
    if (p) {
      // `-C` com variavel: nao da para resolver — cai no conservador.
      if (/[$`]/.test(p)) { alvos.push({ dir: cwdInicial, verbo, incerto: true }); continue; }
      alvos.push({ dir: path.resolve(mov.cwd, p), verbo, incerto: mov.incerto || aninhado });
      continue;
    }
    // `incerto` vai junto do alvo (nao so como alvo extra em `cwdInicial`):
    // um `popd` sem `pushd` correspondente pode deixar o shell em QUALQUER
    // diretorio, inclusive um que hoje E um worktree legitimo mas nao e o
    // de onde o comando rodou de verdade — cwdInicial e mov.cwd podem ser o
    // MESMO worktree (o agente ja estava la), e nesse caso a adicao antiga
    // (so `cwdInicial` como alvo extra) nao pegava nada. Quem consome (main)
    // trata `incerto: true` bloqueando direto, sem confiar na classificacao
    // de worktree — mesmo espirito do ramo de CLI (H2, rodada 5).
    alvos.push({ dir: mov.cwd, verbo, incerto: mov.incerto || aninhado });
    if (mov.incerto) alvos.push({ dir: cwdInicial, verbo, incerto: true });
  }
  return alvos;
}

// `tokensComAspas`, `ehComando`, `WRAPPERS_QUE_REPASSAM` e `posicaoDeComando`
// agora moram em `lib/tokens-comando.cjs` (rodada 6, lote 3, 2026-09-03) —
// `cwd-efetivo.cjs` passou a precisar da mesma nocao de posicao de comando
// (K2 do auditor) e duplicar a logica era exatamente o que a rodada 5 tinha
// evitado ao consolidar `resolverMovedor`. Import no topo do arquivo.

// Operador de redirecionamento: quando a linha de comando redireciona para arquivo.
// Procura por padrao no inicio do token, diferente de operadores em nomes.
const OPERADOR_REDIRECT = /^(?:[0-9]*|&)(>>?)(.*)$/;

/** Posicionais de um segmento a partir do indice do comando (pula flags). */
function posicionaisApos(toks, i) {
  return toks.slice(i + 1).filter((t) => !t.v.startsWith("-"));
}

// `textoAPartir` agora mora em `lib/tokens-comando.cjs` (rodada 13, lote 3,
// 2026-09-04) — `gate-staging-total.cjs` e `gate-fechar-issue.cjs` passaram
// a precisar dela tambem para compor `posicaoDeComando` com
// `desempacotarWrapperDeString` (P3 do auditor). Import no topo do arquivo.

/**
 * Acha CLI(s) numa string de comando ja isolada — reusado pela recursao de
 * `eval`/`bash -c` em `procuraCLI`. Conteudo com `$(`, crase ou `$VAR` nao da
 * pra resolver estaticamente (o script dentro do eval pode rodar QUALQUER
 * coisa): marca INCERTO em vez de so olhar se um nome conhecido aparece.
 */
function achadasEmString(str, clis, ferramenta) {
  if (/[$`]/.test(str)) return [{ nome: "?", incerto: true }];
  return procuraCLI(str, clis, ferramenta);
}

/**
 * Procura por CLI externa que escreve (codex, gemini, claude, aider, cursor,
 * copilot), em POSICAO DE COMANDO — primeiro token do segmento, ou o
 * primeiro token depois de um wrapper conhecido que repassa o comando
 * adiante (`env`, `command`, `exec`, `nohup`, `nice`, `timeout`, `xargs`,
 * `sudo`, `time`). Retorna `[{nome, indiceSegmento, incerto?}]` — um item
 * por achado, na ordem dos segmentos.
 *
 * Segmentacao usa `segmentosComAspas` (respeita aspas), nao `comando.split`
 * cru: `echo "abc ; codex exec --yolo"` tem um `;` DENTRO da string, que o
 * split ingenuo tratava como separador de verdade e criava um segmento
 * `codex exec --yolo"` fantasma — falso positivo num `echo` de texto.
 *
 * Token citado em posicao de COMANDO continua contando (R2): `"codex" exec
 * --yolo` e comando de verdade disfarcado de string.
 *
 * `$'codex'`/`$"codex"` (ANSI-C / locale quoting, A4): o bash expande para o
 * literal `codex`, mas o `$` fica FORA da aspa em `tokensComAspas` e gruda no
 * valor (`$codex`), escapando da lista. Na posicao de comando, um token
 * citado cujo valor comeca com `$` perde o `$`.
 *
 * Wrapper de STRING (`eval`, `bash -c`/`sh -c`/`zsh -c`/`ksh -c`/`dash -c`,
 * `Invoke-Expression`/`iex`, `pwsh|powershell -Command`, `cmd /c`/`/k` — H3 +
 * T2, rodada 11, lote 3, 2026-09-04): o comando de verdade esta DENTRO da
 * string citada — `desempacotarWrapperDeString` (lib/tokens-comando.cjs,
 * compartilhada com `gate-staging-total.cjs` e `gate-fechar-issue.cjs`)
 * devolve o conteudo, e `achadasEmString` recursiona sobre ele, no MESMO
 * `indiceSegmento` (mesmo cwd do segmento que contem o wrapper). Antes desta
 * rodada so `eval`/`bash -c` eram reconhecidos aqui (ad hoc, cada um com seu
 * proprio `if`) — `Invoke-Expression "codex exec --yolo"`/`iex "..."`
 * atravessava com exit 0.
 */
function procuraCLI(comando, clis, ferramenta) {
  const segmentos = segmentosComAspas(comando, ferramenta === "PowerShell");
  const achadas = [];
  segmentos.forEach((seg, indiceSegmento) => {
    const toks = tokensComAspas(seg);
    const i = posicaoDeComando(toks);
    if (i === null) return;
    const tok = toks[i];
    let v = tok.v;
    if (tok.q && v.startsWith("$")) v = v.slice(1); // $'codex' (A4)
    const nome = v.split(/[\\/]/).pop().replace(/\.exe$/, "");

    const { interno, ilegivel } = desempacotarWrapperDeString(textoAPartir(toks, i), { ferramenta });
    if (ilegivel) {
      achadas.push({ nome: "?", incerto: true, indiceSegmento });
      return;
    }
    if (interno !== null) {
      for (const a of achadasEmString(interno, clis, ferramentaDoInterno(textoAPartir(toks, i), ferramenta))) achadas.push({ ...a, indiceSegmento });
      return;
    }

    if (clis.includes(nome)) achadas.push({ nome, indiceSegmento });
  });
  return achadas;
}

/**
 * Detecta escrita em Bash via redirecionamento ou ferramentas comuns.
 * Resolve alvos e retorna {dir, tipo} para cada um.
 *
 * Tipos: ">", ">>", "tee", "sed", "cp", "mv", e construcoes nao-resolvidas.
 * Mantem a mesma seguranca do `alvosBash`: `cd`/`pushd`/`popd`/`env -C` que
 * nao resolve vira INCERTO e conservadorismo inclui cwdInicial nos alvos.
 * Movedores vem de `resolverMovedor` (lib/cwd-efetivo.cjs) — antes esta
 * funcao so reconhecia `cd`, mesmo buraco do `alvosBash` (emenda do auditor,
 * rodada 5, lote 3): `env -C <principal> echo x > f.txt` de dentro do
 * worktree escrevia no principal e passava com exit 0.
 *
 * Tudo aqui decide por TOKEN, nunca por match no texto cru — ver o docblock de
 * `tokensComAspas`.
 */
/**
 * O destino do redirecionamento descarta a saida — nao e escrita em lugar nenhum?
 *
 * `/dev/null` sempre; `$null` SO na ferramenta PowerShell, onde e automatico e
 * nao aceita atribuicao (#514, P1). No bash `$null` e variavel comum —
 * `null=a.txt; echo x > $null` escreve —, entao la segue como alvo. Sem isto, `(ls x) 2>/dev/null`
 * no principal dava alvo + `incerto` (do parentese) e barrava um agente de leitura.
 * `NUL` NAO entra: no MSYS/Cygwin `> nul` pode criar um arquivo literal `nul`.
 */
function ehDescarteDeSaida(alvo, ehPowerShell) {
  return alvo === "/dev/null" || (ehPowerShell === true && /^\$null$/i.test(alvo));
}

// Cmdlets de escrita do PowerShell (#533, D2). Nome sem diferenciar caixa e sem
// qualificador de modulo: `Microsoft.PowerShell.Management\Set-Content` conta como `Set-Content`.
const CMDLETS_DE_ESCRITA = new Set([
  "set-content", "sc", "add-content", "ac", "out-file", "new-item", "ni", "tee-object",
  "copy-item", "copy", "cpi", "move-item", "move", "mi",
  // Aliases do PowerShell com nome de comando do bash: no PowerShell, `cp`, `mv` e `tee`
  // sao Copy-Item, Move-Item e Tee-Object e aceitam `-Destination`/`-FilePath` (2a revisao).
  "cp", "mv", "tee",
]);
// Parametros do PowerShell, por classe (rodada 2, #533, falha fechada). Alias, nome
// exato ou prefixo unico (`-Val`, `-Dest`) conta. Nome que nao casa com nenhuma
// lista, ou casa com mais de uma sem ser exato, e DESCONHECIDO: vira alvo incerto.
const ALIASES_DE_PARAMETRO = new Map([
  ["vb", "verbose"], ["db", "debug"], ["wi", "whatif"], ["cf", "confirm"],
  ["ea", "erroraction"], ["wa", "warningaction"], ["infa", "informationaction"],
  ["ev", "errorvariable"], ["wv", "warningvariable"], ["iv", "informationvariable"],
  ["ov", "outvariable"], ["ob", "outbuffer"], ["pv", "pipelinevariable"], ["lp", "literalpath"],
  // New-Item: `-Type` e alias de `-ItemType`, `-Target` de `-Value` (2a revisao do fluxo).
  ["type", "itemtype"], ["target", "value"],
]);
// Parametros cujo valor e um caminho: o valor vira alvo.
// `-Name` do New-Item tambem: `New-Item -Name <P>/f` cria pelo caminho do nome (revisao de seguranca, rodada 2).
const PARAMETROS_DE_CAMINHO = ["path", "literalpath", "filepath", "pspath", "destination", "name"];
// Parametros que levam valor: o token seguinte nao e alvo (salvo se for de caminho).
const PARAMETROS_COM_VALOR = [
  "value", "itemtype", "encoding", "inputobject", "width", "filter", "include",
  "exclude", "variable", "stream", "credential", "erroraction", "warningaction",
  "informationaction", "errorvariable", "warningvariable", "informationvariable",
  "outvariable", "outbuffer", "pipelinevariable", "progressaction", "fromsession", "tosession",
];
// Parametros sem valor. `-Confirm:$false` e booleano, nao caminho.
const PARAMETROS_SEM_VALOR = [
  "force", "append", "nonewline", "noclobber", "passthru", "recurse",
  "verbose", "debug", "whatif", "confirm", "asbytestream", "container", "usetransaction",
];
// Prefixo de uma letra tambem vale quando unico (`cp -r a b` e `-Recurse`).
const ehParametro = (flag, nome) => flag.length >= 1 && nome.startsWith(flag);

// Parametros de cada cmdlet (3a revisao do fluxo): o prefixo e resolvido contra o
// conjunto do cmdlet, como o PowerShell faz (`cp -v` e `-Verbose`, nao ambiguo com `-Value`).
const PARAMETROS_COMUNS = [
  "verbose", "debug", "erroraction", "warningaction", "informationaction", "progressaction",
  "errorvariable", "warningvariable", "informationvariable", "outvariable", "outbuffer",
  "pipelinevariable", "whatif", "confirm", "usetransaction",
];
const PARAMETROS_DO_CMDLET = new Map(Object.entries({
  "set-content": ["path", "literalpath", "pspath", "value", "passthru", "filter", "include", "exclude", "force", "credential", "nonewline", "encoding", "stream", "asbytestream"],
  "out-file": ["filepath", "literalpath", "pspath", "encoding", "append", "force", "noclobber", "width", "nonewline", "inputobject"],
  "new-item": ["path", "literalpath", "pspath", "name", "itemtype", "value", "force", "credential"],
  "tee-object": ["filepath", "literalpath", "pspath", "append", "variable", "inputobject", "encoding"],
  "copy-item": ["path", "literalpath", "pspath", "destination", "container", "force", "filter", "include", "exclude", "recurse", "passthru", "credential", "fromsession", "tosession"],
  "move-item": ["path", "literalpath", "pspath", "destination", "force", "filter", "include", "exclude", "passthru", "credential"],
}));
const CMDLET_CANONICO = new Map(Object.entries({
  "sc": "set-content", "add-content": "set-content", "ac": "set-content",
  "ni": "new-item", "tee": "tee-object", "copy": "copy-item", "cpi": "copy-item", "cp": "copy-item",
  "move": "move-item", "mi": "move-item", "mv": "move-item",
}));

/** Nome canonico do parametro (`-Path` -> "path"), ou null se desconhecido ou ambiguo no conjunto do cmdlet. */
function nomeDoParametro(flag, cmdlet) {
  if (ALIASES_DE_PARAMETRO.has(flag)) return ALIASES_DE_PARAMETRO.get(flag);
  const doCmdlet = PARAMETROS_DO_CMDLET.get(CMDLET_CANONICO.get(cmdlet) || cmdlet);
  const todos = doCmdlet ? [...doCmdlet, ...PARAMETROS_COMUNS]
    : [...PARAMETROS_DE_CAMINHO, ...PARAMETROS_COM_VALOR, ...PARAMETROS_SEM_VALOR];
  if (todos.includes(flag)) return flag;
  const casam = todos.filter((n) => ehParametro(flag, n));
  return casam.length === 1 ? casam[0] : null;
}

// Cmdlets de escrita com destino de COPIA: o alvo e `-Destination` ou o ultimo
// posicional, e o primeiro posicional e so origem (D5).
const CMDLETS_DE_COPIA = new Set(["copy-item", "copy", "cpi", "cp", "move-item", "move", "mi", "mv"]);
const CMDLETS_DE_MOVER = new Set(["move-item", "move", "mi", "mv"]);
// Parametros de caminho que o cmdlet le ou escreve (`-Path` e os aliases de caminho).
const PARAMETROS_DE_CAMINHO_PS = ["path", "literalpath", "filepath", "pspath"];

/**
 * Indice do nome do cmdlet, a partir de `i` (D5, #533 rodada 3): pula o `&` (call
 * operator) e a atribuicao (`$null = `, `$a = `, `$a=`) que o PowerShell roda antes
 * do comando. Null se nao sobra token.
 */
// Operador de atribuicao do PowerShell, sozinho (`=`, `+=`, `??=`).
const OPERADOR_DE_ATRIBUICAO = /^[-+*/%?]{0,2}=$/;
// Token que comeca o lado esquerdo de uma atribuicao: variavel, cast (`[string]$a`) ou lista (`$a,`).
const INICIO_DE_LADO_ESQUERDO = /^[$[,]/;

/**
 * Nome do cmdlet a partir de `i` (D5, #533 rodada 3 e 2a revisao do fluxo): pula o `&`
 * e o `.` (dot-source) e a atribuicao que o PowerShell roda antes do comando, em
 * qualquer grafia: `$a = `, `$a=Set-Content`, `$a+=`, `$a[0]=`, `[string]$a = `,
 * `$a, $b = `, `$env:X=` e o `=` que sobra no inicio do segmento quando a segmentacao
 * cortou em `(`/`{` (`($a) = `, `${a} = `). Devolve `{k, nome}` (o `nome` vem do resto
 * do token quando ele cola no `=`), ou null se nao sobra comando.
 */
function indiceDoCmdletPS(toks, i) {
  let k = i;
  while (k < toks.length) {
    const t = toks[k];
    if (t.q) return { k, nome: t.v };
    if (t.v === "&" || t.v === ".") { k += 1; continue; }
    if (OPERADOR_DE_ATRIBUICAO.test(t.v)) { k += 1; continue; }
    if (INICIO_DE_LADO_ESQUERDO.test(t.v)) {
      // Procura o `=` ate o fim do lado esquerdo (tokens que ainda parecem variavel, cast ou lista).
      let j = k;
      let achou = null;
      while (j < toks.length && !toks[j].q) {
        const v = toks[j].v;
        if (OPERADOR_DE_ATRIBUICAO.test(v)) { achou = { prox: j + 1, resto: "" }; break; }
        // `=` de atribuicao colado (`$a=x`, `$a+=x`): nao `==`, nem o de `!=`, `<=`, `>=`.
        const idx = v.search(/=(?!=)/);
        if (idx > 0 && !"!<>=".includes(v[idx - 1])) { achou = { prox: j + 1, resto: v.slice(idx + 1) }; break; }
        if (j > k && !INICIO_DE_LADO_ESQUERDO.test(v) && !/,$/.test(toks[j - 1].v)) break;
        j += 1;
      }
      if (!achou) return { k, nome: t.v };
      if (achou.resto) return { k: achou.prox - 1, nome: achou.resto };
      k = achou.prox;
      continue;
    }
    return { k, nome: t.v };
  }
  return null;
}

/** Nome do cmdlet comparavel: sem qualificador de modulo, sem crase (o PowerShell a ignora em `Set-`Content`), em minusculas. */
function nomeDeCmdletPS(v) {
  return v.replace(/`/g, "").split(/[\\/]/).pop().toLowerCase();
}

/**
 * Le um argumento a partir de `k`, juntando a lista que o espaco partiu (`a.txt, <P>/f`,
 * `a.txt ,<P>/f`): enquanto o token termina em `,` ou o seguinte comeca com `,`.
 * Devolve `{t: {v, q}, k}` com `k` no ultimo token consumido.
 */
function lerArgumentoPS(toks, k) {
  let v = toks[k].v;
  let q = toks[k].q;
  let j = k;
  while (j + 1 < toks.length && (v.endsWith(",") || toks[j + 1].v.startsWith(","))) {
    j += 1;
    v += toks[j].v;
    q = q || toks[j].q;
  }
  return { t: { v, q }, k: j };
}

/**
 * D2 e D5 de um segmento (#533, rodadas 2 e 3). O candidato a alvo e: o valor de
 * `-Path`/`-LiteralPath`/`-FilePath`/`-PSPath` se houver, senao o PRIMEIRO posicional
 * (escritores simples). Em copia/movimento, `-Destination` se houver, senao o ULTIMO
 * posicional (com `-Path` nomeado, o posicional unico e o destino). `-Value` e os
 * posicionais que nao sao o candidato nao sao caminho. `New-Item -Name`: alvo = o
 * caminho (ou o cwd) juntado ao nome. Candidato com `$`, `(`, crase ou `@` inicial
 * (splat) e alvo incerto, que o gate barra dentro de repositorio. Parametro
 * desconhecido ou ambiguo tambem.
 */
function alvosDeCmdlet(toks, posCmd, base, empurra) {
  if (posCmd === null || posCmd === undefined) return;
  const cmd = indiceDoCmdletPS(toks, posCmd);
  if (cmd === null) return;
  const iNome = cmd.k;
  const nome = nomeDeCmdletPS(cmd.nome);
  if (!CMDLETS_DE_ESCRITA.has(nome)) return;
  const posicionais = [];
  const caminhos = [];
  const destinos = [];
  const nomes = [];
  let desconhecido = false;
  for (let k = iNome + 1; k < toks.length; k += 1) {
    const t = toks[k];
    // `-Nome` ou `-Nome:valor`. Token citado so e parametro com `:` (`-Path:'x'`,
    // que o tokenizador devolve como citado); sem `:` e um argumento citado.
    // O PowerShell aceita travessao (`–`, `—`, `―`) como prefixo de parametro.
    const m = /^[-–—―]([A-Za-z]+)(:(.*))?$/.exec(t.v);
    if (!m || (t.q && m[2] === undefined)) {
      const arg = lerArgumentoPS(toks, k);
      posicionais.push(arg.t);
      k = arg.k;
      continue;
    }
    const param = nomeDoParametro(m[1].toLowerCase(), nome);
    if (param === null) { desconhecido = true; continue; } // o token seguinte segue posicional
    if (PARAMETROS_SEM_VALOR.includes(param)) continue;
    let valor = null;
    if (m[2] !== undefined && m[3] !== "") valor = { v: m[3], q: t.q }; // -Nome:valor
    else if (k + 1 < toks.length) { const arg = lerArgumentoPS(toks, k + 1); valor = arg.t; k = arg.k; } // -Nome valor, o valor nao e posicional
    if (valor !== null && m[2] !== undefined && m[3] !== "" && valor.v.endsWith(",") && k + 1 < toks.length) {
      // `-Path:a, <P>/f`: a lista continua no token seguinte.
      const arg = lerArgumentoPS(toks, k + 1);
      valor = { v: valor.v + arg.t.v, q: valor.q || arg.t.q };
      k = arg.k;
    }
    if (valor === null) continue;
    if (PARAMETROS_DE_CAMINHO_PS.includes(param)) caminhos.push(valor);
    else if (param === "destination") destinos.push(valor);
    else if (param === "name") nomes.push(valor);
  }
  if (desconhecido) empurra(base, null, "cmdlet", true);
  // Splat em qualquer posicao (`Set-Content x -Value y @a`) traz parametros que nao
  // se veem: incerto (revisao de seguranca).
  if (toks.slice(iNome + 1).some((t) => !t.q && /^@\w+$/.test(t.v))) empurra(base, null, "cmdlet", true);

  if (nome === "new-item" || nome === "ni") {
    if (nomes.length) {
      // `-Name` junta-se ao caminho (ou ao cwd): nome com `..` ou separador tambem conta.
      for (const n of nomes) {
        // Sem `-Path` nomeado, o primeiro posicional e o caminho (`New-Item <P> -Name f`).
        const bases = caminhos.length ? caminhos : posicionais.length ? posicionais.slice(0, 1) : [null];
        // Lista no caminho (`-Path a,<P>`): cada elemento se junta ao nome.
        const partes = bases.flatMap((p) => (p === null ? [null] : p.v.split(",").filter((x) => x !== "")));
        for (const p of partes) {
          const trechos = [n.v, p].filter((x) => x !== null);
          if (trechos.some((x) => /[$`()@‘-„]/.test(x))) { empurra(base, null, "cmdlet", true); continue; }
          empurra(base, path.resolve(base, p === null ? "." : p, n.v), "cmdlet");
        }
      }
      return;
    }
  }

  let candidatos;
  if (CMDLETS_DE_MOVER.has(nome)) {
    // Mover apaga a origem: origem e destino sao alvos (revisao de seguranca da rodada 3).
    candidatos = [...destinos, ...caminhos, ...posicionais];
    // Sem destino, o item cai no cwd, como na copia.
    if (!destinos.length && posicionais.length < (caminhos.length ? 1 : 2)) candidatos.push({ v: ".", q: false });
  } else if (CMDLETS_DE_COPIA.has(nome)) {
    if (destinos.length) candidatos = destinos;
    else {
      const minimo = caminhos.length ? 1 : 2;
      // Sem destino, a copia cai no cwd: ele e o alvo (revisao de seguranca).
      candidatos = posicionais.length >= minimo ? [posicionais[posicionais.length - 1]] : [{ v: ".", q: false }];
    }
  } else {
    candidatos = caminhos.length ? caminhos : posicionais.slice(0, 1);
  }
  // Lista (`a,<P>/b`): cada elemento e um alvo. Variavel, crase, subexpressao ou splat: incerto.
  for (const c of candidatos) {
    for (const parte of c.v.split(",")) {
      if (parte === "") continue;
      // Aspa tipografica: o tokenizador nao a reconhece, o PowerShell sim. Incerto.
      if (/[$`()‘-„]|^@/.test(parte)) empurra(base, null, "cmdlet", true);
      else empurra(base, parte, "cmdlet");
    }
  }
}

/**
 * Crase fora de aspas, `#` fora de aspas ou here-string (`@'`/`@"`) (D5, rodada 3): a
 * mascara de aspas nao acompanha a leitura do PowerShell nesses casos (a crase faz o
 * apostrofo seguinte literal, o comentario `# it's` abre uma aspa falsa, o here-string
 * tem as suas). Quem tem qualquer um deles nao e mascarado.
 */
function desalinhaAMascara(texto) {
  let aspa = null;
  for (let i = 0; i < texto.length; i += 1) {
    const c = texto[i];
    if (aspa) {
      if (c === "`" && aspa === '"') i += 1; // crase escapa o proximo dentro de aspas duplas
      else if (c === aspa) aspa = null;
      continue;
    }
    if (c === "'" || c === '"') { aspa = c; continue; }
    // Aspas tipograficas (U+2018 a U+201E) tambem sao aspas para o PowerShell (revisao de seguranca).
    if (c === "`" || c === "#" || (c >= "‘" && c <= "„")) return true;
    if (c === "@" && (texto[i + 1] === "'" || texto[i + 1] === '"')) return true;
  }
  return false;
}

/** Texto com o conteudo entre aspas trocado por espacos, do mesmo tamanho: chamada dentro de aspas nao conta (D3). */
function mascaraAspas(texto) {
  if (desalinhaAMascara(texto)) return texto;
  // PowerShell (revisao de seguranca da rodada 2): so aspas simples sao inertes. Aspas
  // duplas expandem `$(...)`, entao so se mascaram sem `$` dentro; crase escapa o
  // caractere seguinte dentro delas. Estado de aspas desbalanceado: nao mascara nada
  // (falha fechada, a chamada volta a contar).
  let saida = "";
  let i = 0;
  while (i < texto.length) {
    const c = texto[i];
    if (c === "'") {
      const j = texto.indexOf("'", i + 1);
      if (j < 0) return texto;
      saida += "'" + " ".repeat(j - i - 1) + "'";
      i = j + 1;
    } else if (c === '"') {
      let j = i + 1;
      while (j < texto.length && texto[j] !== '"') j += texto[j] === "`" ? 2 : 1;
      if (j >= texto.length) return texto;
      const dentro = texto.slice(i + 1, j);
      saida += dentro.includes("$") ? texto.slice(i, j + 1) : '"' + " ".repeat(j - i - 1) + '"';
      i = j + 1;
    } else {
      saida += c;
      i += 1;
    }
  }
  return saida;
}

// Chamada .NET (#533, D3, emenda da rodada 2): qualquer tipo sob o namespace IO
// (`[IO.File]`, `[System.IO.Directory]`, `[IO.FileStream]`...), exceto `Path`, que so
// manipula string. Metodo de leitura conhecido passa; qualquer outro e escrita.
// Espaco e aceito em volta do nome do tipo, de `::` e antes do `(` (D5, rodada 3).
const CHAMADA_NET = /\[\s*([\w.]*\bIO\.[\w.]+)\s*\]\s*::\s*(\w+)\s*\(/gi;
const METODOS_NET_DE_LEITURA = new Set([
  "readalltext", "readalllines", "readallbytes", "readlines", "exists", "openread", "opentext",
  "getattributes", "getlastwritetime", "getfiles", "getdirectories", "enumeratefiles", "enumeratedirectories",
  // 2a revisao do fluxo: leitura comum que a lista nao tinha.
  "readalltextasync", "readalllinesasync", "readallbytesasync", "getcreationtime", "getlastaccesstime",
  "getlastwritetimeutc", "getcreationtimeutc", "getlastaccesstimeutc", "getfilesystementries",
  "enumeratefilesystementries", "getcurrentdirectory", "getparent", "getdirectoryroot", "getlogicaldrives",
]);
// Tipos cujo construtor (`::new`) nao escreve em arquivo: leitores, buffers em memoria e
// descritores (`[IO.FileInfo]::new(p).Length`).
// `FileInfo`/`DirectoryInfo` nao entram: `[IO.FileInfo]::new(p).Create()` escreve (revisao de seguranca).
const TIPOS_NET_NEW_SEM_ESCRITA = /(^|\.)(streamreader|stringreader|stringwriter|memorystream|binaryreader)$/i;
// Posicoes de caminho que a escrita toca, por metodo. `Move` e `Replace` apagam a origem;
// o 3o argumento de `Replace` e o backup (2a revisao do fluxo). Os demais: todo literal.
const POSICAO_DO_ALVO_NET = new Map([
  ["writealltext", [0]], ["appendalltext", [0]], ["writealllines", [0]], ["appendalllines", [0]],
  ["writeallbytes", [0]], ["copy", [1]], ["move", [0, 1]], ["replace", [0, 1, 2]],
]);

/** Argumentos de uma chamada, a partir de `inicio` (logo depois do `(`). Virgula so conta fora de aspas e parenteses. */
function argumentosDaChamada(texto, inicio) {
  const args = [];
  let atual = "", aspa = null, prof = 0;
  for (let i = inicio; i < texto.length; i += 1) {
    const c = texto[i];
    if (aspa) { atual += c; if (c === aspa) aspa = null; continue; }
    if (c === "'" || c === '"') { aspa = c; atual += c; continue; }
    if (c === "(") prof += 1;
    else if (c === ")") {
      if (prof === 0) { args.push(atual.trim()); return { args, fechou: true }; }
      prof -= 1;
    } else if (c === "," && prof === 0) { args.push(atual.trim()); atual = ""; continue; }
    atual += c;
  }
  return { args, fechou: false };
}

/** Texto de um argumento que e string literal: `'...'`, ou `"..."` sem `$` nem crase. Senao null. */
function literalDoArgumento(arg) {
  const s = /^'([^']*)'$/.exec(arg) || /^"([^"$`]*)"$/.exec(arg);
  return s ? s[1] : null;
}

/**
 * Uma entrada por chamada de escrita .NET do COMANDO: `{alvo}` (literal, relativo
 * ao cwd) ou `{incerto: true}`. Le o comando inteiro, nao o segmento: a segmentacao
 * parte em `(` e `)`. A busca roda sobre o texto com aspas mascaradas (so conta
 * chamada fora de aspas); os argumentos sao lidos do texto original.
 */
function alvosNetDoComando(comando) {
  const saida = [];
  // Texto executado como codigo (`iex`, `Invoke-Expression`, `[scriptblock]::Create`): a
  // chamada dentro de aspas PODE rodar, entao nesta linha a busca nao mascara as aspas.
  const executa = /(^|[\s;|&(])(iex|invoke-expression|\[scriptblock\]::create)(?=[\s(;|)]|$)/i.test(comando);
  const mascarado = executa ? comando : mascaraAspas(comando);
  for (const m of mascarado.matchAll(CHAMADA_NET)) {
    const tipo = m[1];
    if (/(^|\.)path$/i.test(tipo)) continue;
    const metodo = m[2].toLowerCase();
    if (METODOS_NET_DE_LEITURA.has(metodo)) continue;
    if (metodo === "new" && TIPOS_NET_NEW_SEM_ESCRITA.test(tipo)) continue;
    const { args, fechou } = argumentosDaChamada(comando, m.index + m[0].length);
    if (!fechou) { saida.push({ incerto: true }); continue; }
    if (POSICAO_DO_ALVO_NET.has(metodo)) {
      for (const pos of POSICAO_DO_ALVO_NET.get(metodo)) {
        if (pos > 0 && args.length <= pos) continue; // argumento opcional ausente
        if (pos > 0 && /^\$null$/i.test(args[pos])) continue; // `Replace(a, b, $null)`: sem backup
        const lit = args.length > pos ? literalDoArgumento(args[pos]) : null;
        saida.push(lit === null ? { incerto: true } : { alvo: lit });
      }
      continue;
    }
    // Metodo de escrita nao conhecido: todo literal e candidato; sem literal, incerto.
    const literais = args.map(literalDoArgumento).filter((x) => x !== null);
    if (!literais.length) saida.push({ incerto: true });
    else for (const alvo of literais) saida.push({ alvo });
  }
  return saida;
}

/**
 * Junta a continuacao de linha do PowerShell (crase no fim da linha), so quando a
 * crase esta fora de aspas e de comentario e nao e escapada (revisao de seguranca):
 * `# c ` + quebra + `Set-Content ...` nao pode virar uma linha so de comentario.
 * `#` so abre comentario no inicio de token (`a#b` e uma palavra). Crase solta no fim
 * do comando sai. Devolve `{texto, incerto}`: continuacao que ficou sem juntar (dentro
 * de comentario ou de aspas), ou continuacao num comando com here-string ou aspa
 * tipografica, que esta leitura nao acompanha, e incerta (falha fechada).
 */
function juntaContinuacoesPS(t) {
  const texto = juntaContinuacoesPSTexto(t);
  const temContinuacao = /`\r?\n/.test(t);
  // `#` fora de aspas junto com continuacao: o PowerShell abre comentario em mais
  // lugares do que esta leitura acompanha (`'x'#c`, `$a.b#c`, `$a[0]#c`), e a crase
  // pode estar dentro dele. Incerto, sem tentar decidir (4a revisao do fluxo).
  const incerto = /`\r?\n/.test(texto) ||
    (temContinuacao && (/@['"]|[‘-„]/.test(t) || temForaDeAspas(t, "#")));
  return { texto, incerto };
}

function juntaContinuacoesPSTexto(t) {
  let out = "";
  let aspa = null;
  let comentario = false;
  for (let i = 0; i < t.length; i += 1) {
    const c = t[i];
    if (comentario) { out += c; if (c === "\n") comentario = false; continue; }
    if (aspa) {
      out += c;
      if (c === "`" && aspa === '"' && i + 1 < t.length) { out += t[i + 1]; i += 1; }
      else if (c === aspa) aspa = null;
      continue;
    }
    if (c === "'" || c === '"') { aspa = c; out += c; continue; }
    if (c === "#" && (out === "" || /[\s;|&(){}]$/.test(out))) { comentario = true; out += c; continue; }
    if (c === "`") {
      const m = /^\r?\n/.exec(t.slice(i + 1));
      if (m) { out += " "; i += m[0].length; continue; }
      out += c;
      if (i + 1 < t.length) { out += t[i + 1]; i += 1; } // crase escapa o proximo caractere
      continue;
    }
    out += c;
  }
  return aspa === null && !comentario ? out.replace(/\s`\s*$/, "") : out;
}

/** `trecho` aparece fora de aspas simples e duplas? Aspa desbalanceada: conta como fora (falha fechada). */
function temForaDeAspas(texto, trecho) {
  let aspa = null;
  for (let i = 0; i < texto.length; i += 1) {
    const c = texto[i];
    if (aspa) {
      if (c === "`" && aspa === '"') i += 1;
      else if (c === aspa) aspa = null;
      continue;
    }
    if (c === "'" || c === '"') { aspa = c; continue; }
    if (texto.startsWith(trecho, i)) return true;
  }
  return aspa !== null && texto.includes(trecho);
}

function alvosBashEscrita(comando, cwdInicial, ehPowerShell = false, profundidade = 0) {
  // #530 (D3): mais de 4 niveis de wrapper/substituicao nao sao conferidos. Barrar,
  // nao liberar sem olhar (D5 do design). O motivo chega ao stderr por `main`.
  if (profundidade > 4) {
    return [{ dir: cwdInicial, tipo: "barrar", motivo: MOTIVO_ANINHADO }];
  }
  const ferramenta = ehPowerShell ? "PowerShell" : "Bash";
  // `segmentosComAspas` pelo mesmo motivo de `alvosBash`: respeita aspas e
  // reconhece `&` simples como separador (K1, rodada 6, lote 3, 2026-09-03).
  // PowerShell: crase no fim da linha e continuacao, a linha seguinte e o mesmo
  // comando; crase solta no fim do comando nao e argumento (3a revisao do fluxo).
  let continuacaoIncerta = false;
  if (ehPowerShell) ({ texto: comando, incerto: continuacaoIncerta } = juntaContinuacoesPS(comando));
  const segmentos = segmentosComAspas(comando, ehPowerShell);
  const estado = { atual: cwdInicial, incerto: false, pilhaPushd: [], estouro: false };
  const alvos = [];
  // Todo cwd que a linha visita: a chamada .NET (D3) nao sabe em qual segmento
  // esta, entao um alvo relativo vale para cada um deles (conservador).
  const visitados = new Set([cwdInicial]);

  // #530 (D6, emenda do advisor): crase SEM aspas nao fecha segmento, mas
  // `segmentosComAspas` corta no `;` dentro dela. Por isso o corpo que ATRAVESSA
  // segmento e lido sobre o comando INTEIRO, a partir do cwd inicial. Corpo que cabe
  // inteiro num segmento fica de fora: o passo do segmento o resolve a partir do cwd
  // DELE (rodada 2 — `cd hooks; echo "$(echo x > ../f)"` nao e escrita fora do worktree).
  if (textoLido(comando, ferramenta).ehBash) {
    for (const corpo of corposDeSubstituicao(comando)) {
      if (segmentos.some((seg) => seg.includes(corpo))) continue;
      alvos.push(...alvosBashEscrita(corpo, cwdInicial, ehPowerShell, profundidade + 1));
    }
  }

  // Resolve o alvo contra o cwd EFETIVO deste segmento (`base` — o de
  // `env -C`, se houver, senao o `estado.atual` corrente); construcao com
  // $ ou ` fica INCERTA e aponta para o proprio diretorio, que e o lado
  // seguro.
  // `alvo` null com `incerto` = so incerto, sem caminho (parametro desconhecido do cmdlet).
  const empurra = (base, alvo, tipo, incerto = false) => {
    if (alvo === null) { if (incerto) alvos.push({ dir: base, tipo, incerto: true }); return; }
    if (!alvo) return;
    if (/[$`]/.test(alvo)) alvos.push({ dir: base, tipo });
    else alvos.push({ dir: path.resolve(base, alvo), tipo });
  };

  // Comentario de bloco do PowerShell (`<#...#>`): o tokenizador nao o conhece, e ele
  // pode ocupar a posicao do caminho (`Set-Content <##> <P>/f x`). Incerto (2a revisao).
  // So fora de aspas: `Select-String '<#' a.txt` e texto (3a revisao do fluxo).
  // Sem confianca nas aspas (crase, `#` ou here-string fora delas), qualquer `<#` conta.
  const temBloco = desalinhaAMascara(comando) ? comando.includes("<#") : temForaDeAspas(comando, "<#");
  if (ehPowerShell && temBloco) alvos.push({ dir: cwdInicial, tipo: "cmdlet", incerto: true });
  if (continuacaoIncerta) alvos.push({ dir: cwdInicial, tipo: "cmdlet", incerto: true });

  for (const seg of segmentos) {
    const mov = resolverMovedor(seg, estado, ehPowerShell);
    visitados.add(mov.cwd);
    if (mov.soMovedor) continue; // cd/pushd/popd: o segmento INTEIRO e o movedor
    const base = mov.cwd;

    // #530 (D3): `bash -c`, `sh -c`, `eval` etc. com a escrita DENTRO da string. A
    // palavra e lida normalizada (`'bash' -c` conta). Conteudo ilegivel nao
    // recursa: quem barra e `procuraCLI`, como antes.
    // Recursao de wrapper e de substituicao so no Bash (rodada 2): no PowerShell, a base.
    const lido = textoLido(seg, ferramenta);
    if (lido.ehBash) {
      const { interno, ilegivel } = desempacotarWrapperDeString(lido.seg, { ferramenta });
      if (interno !== null && !ilegivel) alvos.push(...alvosBashEscrita(interno, base, ferramentaDoInterno(lido.seg, ferramenta) === "PowerShell", profundidade + 1));
      // #530 (D6): cada corpo de crase ou `$(...)` roda como comando, a partir do cwd deste segmento.
      for (const corpo of corposDeSubstituicao(seg)) {
        alvos.push(...alvosBashEscrita(corpo, base, ehPowerShell, profundidade + 1));
      }
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
      if (ehDescarteDeSaida(alvo, ehPowerShell)) continue;
      empurra(base, alvo, tipo);
    }

    // Posicao de comando do segmento: so ali um nome CITADO conta como comando
    // (rodada 20, lote 3 — `"cp" a.txt <principal>/b.txt` escapava daqui).
    // Fora dela o token citado segue sendo argumento, nunca comando.
    const posCmd = posicaoDeComando(toks);
    const ehCmd = (i, nome) => ehComando(toks[i], nome, i === posCmd);
    // D2 (#533): cmdlet de escrita do PowerShell, so na ferramenta PowerShell.
    if (ehPowerShell) alvosDeCmdlet(toks, posCmd, base, empurra);
    // D5 (rodada 3): `iex`/`Invoke-Expression` com texto literal roda, de fato, o que
    // o texto diz — a mesma analise de cmdlet vale para o texto. Argumento nao literal: incerto.
    if (ehPowerShell && posCmd !== null && posCmd !== undefined) {
      const cmd = indiceDoCmdletPS(toks, posCmd);
      if (cmd !== null && /^(iex|invoke-expression)$/.test(nomeDeCmdletPS(cmd.nome))) {
        // `-Command` (ou prefixo dele) antes do texto e o nome do parametro, nao codigo.
        let args = toks.slice(cmd.k + 1);
        if (args.length && !args[0].q && /^[-–—―]c(o(m(m(a(n(d)?)?)?)?)?)?:?$/i.test(args[0].v)) args = args.slice(1);
        // Qualquer outro parametro no texto (`-Command:'...'`, que o tokenizador devolve
        // citado): incerto (revisao de seguranca).
        const comParametro = args.some((t) => /^[-–—―]/.test(t.v));
        // Literal so sem `$` nem crase em parte nenhuma: o token pode misturar aspas
        // (`'a'"$(...)"`), e a aspa registrada e so a primeira (revisao de seguranca).
        const literal = args.every((t) => !/[$`‘-„]/.test(t.v));
        // Sem argumento, o texto chega pelo pipeline (`$s | iex`): incerto (revisao de seguranca da rodada 3).
        if (!args.length || !literal || comParametro) empurra(base, null, "iex", true);
        else alvos.push(...alvosBashEscrita(args.map((t) => t.v).join(" "), base, true, profundidade + 1));
      }
    }

    for (let i = 0; i < toks.length; i += 1) {
      // `tee arquivo`, `tee -a arquivo`
      if (ehCmd(i, "tee")) {
        const pos = posicionaisApos(toks, i);
        if (pos.length) empurra(base, pos[0].v, "tee");
        break;
      }
      // `sed -i arquivo` — so com a flag de edicao no lugar. O alvo e o ULTIMO
      // posicional: antes dele vem a expressao, que pode ser varios argumentos.
      if (ehCmd(i, "sed")) {
        const temInPlace = toks.slice(i + 1).some((t) => !t.q && /^-[a-z]*i/.test(t.v));
        if (!temInPlace) break;
        const pos = posicionaisApos(toks, i);
        if (pos.length) empurra(base, pos[pos.length - 1].v, "sed");
        break;
      }
      // `cp origem destino`, `mv origem destino` — o destino e o ultimo posicional,
      // que e o que vale tambem para `cp a b c pasta/`.
      if (ehCmd(i, "cp") || ehCmd(i, "mv")) {
        const tipo = ehCmd(i, "cp") ? "cp" : "mv";
        const pos = posicionaisApos(toks, i);
        if (pos.length >= 2) empurra(base, pos[pos.length - 1].v, tipo);
        break;
      }
    }
  }

  // #530 (D5): expansao de chaves que estourou o teto nao e conferida. Barrar.
  if (estado.estouro) {
    alvos.push({ dir: cwdInicial, tipo: "barrar", motivo: "expansao de chaves grande demais para conferir" });
  }

  // D3 (#533): chamada .NET de escrita, so na ferramenta PowerShell. Literal
  // relativo vale para cada cwd visitado; nao literal e incerto no cwd inicial.
  if (ehPowerShell) {
    for (const net of alvosNetDoComando(comando)) {
      if (net.incerto) alvos.push({ dir: cwdInicial, tipo: "net", incerto: true });
      else for (const base of visitados) alvos.push({ dir: path.resolve(base, net.alvo), tipo: "net" });
    }
  }

  // Conservadorismo: se houver `cd`/`pushd`/`popd` nao-resolvivel, incluir
  // cwdInicial tambem.
  if (estado.incerto && alvos.length > 0) {
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
function bloqueiaColocada(verbo, toplevel, outras, agora, incerto) {
  const lista = outras
    .map((s) => {
      const min = Math.round((agora - s.ultimo_ts) / 60000);
      return `  - ${s.session_id} — ${s.parada ? "parada" : "ativa"} ha ${min} min`;
    })
    .join("\n");

  const quem = verbo === SUB_ANINHADO.verbo
    ? `${MOTIVO_ANINHADO} — nao da para ver se move o HEAD`
    : `git ${verbo} — move o HEAD deste checkout.`;
  let msg = `BLOQUEADO pelo gate de sessao co-locada do rainforest-mind.\n\n` +
    `Comando: ${quem}\n` +
    `Repo: ${toplevel}\n`;

  if (incerto) {
    msg += `O alvo do comando usa variavel, substituicao ou cd que o gate nao resolve, por\n` +
      `isso ele foi lido como este checkout daqui. Com um caminho literal — sem variavel,\n` +
      `sem substituicao e sem cd nao-resolvivel — o gate compara o repo de verdade.\n` +
      `Clone de outro repo git passa se o caminho for literal.\n\n`;
  }

  msg += `Outra(s) sessao(oes) do Claude Code neste MESMO diretorio:\n${lista}\n\n` +
    `HEAD e do CHECKOUT, nao da janela: trocar de branch aqui troca para as duas.\n` +
    `Um \`git checkout -b\` numa arranca a outra da branch em que ela estava.\n\n` +
    `A SAIDA e um checkout so seu, que ninguem mais compartilha:\n` +
    `  git worktree add .claude/worktrees/<nome> -b <branch>\n` +
    `  cd .claude/worktrees/<nome>\n` +
    `Assim as duas sessoes ficam donas do proprio HEAD, e nenhuma move o da outra.\n\n` +
    `Se voce SABE que a outra sessao nao esta trabalhando aqui, tem duas saidas:\n` +
    `  - node scripts/setup.cjs --desligar gate-worktree --escopo projeto (preferida);\n` +
    `  - RAINFOREST_GATE_OFF=1 no ambiente da sessao (desliga na sessao inteira).\n`;

  process.stderr.write(msg);
  process.exit(2);
}

/**
 * A trava de sessao co-locada. Volta sem fazer nada quando nao se aplica; nao volta
 * quando barra.
 *
 * FALHA PARA O LADO DE LIBERAR em tudo que ela nao consegue medir por falta de
 * INFRAESTRUTURA — sem `session_id` no evento, sem `sessoes.json`, sem raiz de dados,
 * fora de repo git. E o mesmo principio que o `estadoDoRepo` ja aplica quando o git
 * nao responde, e aqui ele pesa mais: esta e a UNICA condicao do arquivo que pode
 * barrar a janela principal, e um falso positivo aqui trava o trabalho de quem esta
 * sozinho no repo.
 *
 * ALVO QUE O PARSER NAO RESOLVE NAO E falta de infraestrutura, e BARRA (#350): `-C`
 * com variavel, `$(...)`, `cd` nao-resolvivel. A outra sessao existe e foi medida; o
 * que falta e saber para onde o comando vai, e liberar ali e o incidente que a trava
 * existe para impedir. Nenhuma expansao de variavel entra no parser — a rodada 9
 * tentou no gate-fechar-issue e quatro revisoes acharam bypass. O que o alvo incerto
 * ganha e a mensagem: `bloqueiaColocada` diz que a causa e o `$` e manda usar o
 * caminho literal, que o gate compara pelo toplevel (clone de outro repo passa).
 *
 * O `session_id` e o que distingue quem pergunta de quem esta la — as duas entradas
 * do incidente tinham `cwd` identico, entao `cwd` sozinho nao serve (D5). O hook
 * recebe o campo; quem prova e `hooks/heartbeat.cjs:50`, que escreve as chaves do
 * `sessoes.json` com ele.
 */
function gateDeSessaoColocada(ev, cwd) {
  // R3 (rodada 9, lote 3, 2026-09-04): nesta maquina a ferramenta primaria
  // e `PowerShell`, nao `Bash` — um subagente no principal rodando
  // `git commit -m x` pela ferramenta `PowerShell` passava batido aqui.
  // `alvosBash`/`cwdPorSegmento` ja sabem ler `Set-Location`/`Push-Location`/
  // `Pop-Location` (R3 em cwd-efetivo.cjs), entao o mesmo parser serve.
  if (ev.tool_name !== "Bash" && ev.tool_name !== "PowerShell") return;
  const comando = (ev.tool_input || {}).command;
  if (typeof comando !== "string") return;
  // Recusa barata antes de tocar em disco: a linha tem algum verbo que possa mover
  // o HEAD? Quem decide de verdade e o `moveOHead` la embaixo, com o cwd do segmento.
  if (!verboNaLinha(comando, VERBOS_QUE_MOVEM, ev.tool_name)) return;
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

  for (const alvo of alvosBash(comando, cwd, moveOHead, ev.tool_name)) {
    const estado = estadoDoRepo(dirDe(alvo.dir));
    if (!estado) continue;
    if (estado.toplevel !== daqui.toplevel) continue;
    bloqueiaColocada(alvo.verbo, daqui.toplevel, outras, agora, alvo.incerto === true);
  }
}

// ------------------------------------------------------------------------------
// Rede de caminho do principal (#552). Segunda camada, por cima da lista de formas
// de escrita: a partir de um worktree linkado, todo comando que cite um caminho do
// checkout principal (fora dos worktrees e do scratchpad) e barrado, salvo o
// segmento de leitura conhecida (D2). A lista nao converge: cada revisao do
// #530/#533 achou grafias novas; a rede so precisa ver o caminho.

// Comandos de leitura (D2). Movedor (`cd`, `Set-Location`) tambem: ele nao escreve,
// e o segmento seguinte, ja com cwd no principal, cai na rede pelo cwd.
const LEITURA_DA_REDE = new Set([
  "cat", "head", "tail", "less", "more", "ls", "dir", "stat", "file", "wc", "grep", "egrep", "fgrep",
  "rg", "find", "diff", "realpath", "readlink", "basename", "dirname", "test", "[", "echo", "printf",
  // `Join-Path`/`Split-Path`/`Resolve-Path` nao: montam o caminho que outro comando usa
  // (`Set-Content -Path (Join-Path <P> f)`).
  "get-content", "gc", "type", "get-childitem", "gci", "get-item", "gi", "test-path",
  "select-string", "sls", "get-filehash", "measure-object", "measure", "write-output", "write-host",
  // Filtros de pipeline que nao escrevem (`ForEach-Object`, `awk`, `sed`, `xargs` ficam de fora: podem).
  "select-object", "select", "where-object", "where", "?", "sort-object", "group-object",
  "format-table", "ft", "format-list", "fl", "out-string", "out-host", "convertto-json", "convertfrom-json",
  "sort", "uniq", "cut", "tr", "jq", "column", "nl", "tac", "rev",
  "cd", "pushd", "popd", "chdir", "set-location", "sl", "push-location", "pop-location",
]);
const GIT_DE_LEITURA = new Set(["log", "show", "diff", "status", "rev-parse", "ls-files", "blame", "grep", "cat-file"]);
// Opcoes cujo valor e texto de mensagem em `git`/`gh` (D4).
const OPCOES_DE_TEXTO = new Set(["-m", "--message", "--body", "--title", "-t"]);
// Caminho absoluto no texto: `C:\...`, `C:/...`, e no Bash a forma MSYS `/c/...`.
const CAMINHO_WINDOWS = /[A-Za-z]:[\\/][^\s'"`;|&<>(){},]*/g;
const CAMINHO_MSYS = /(?:^|(?<=[\s'"=:({,]))\/[A-Za-z]\/[^\s'"`;|&<>(){},]*/g;
// Componente `..` (D5): o token inteiro que o contem.
const CAMINHO_RELATIVO_ACIMA = /(?:^|(?<=[\s'"=:({,]))(?:[^\s'"`;|&<>(){},]*[\\/])?\.\.(?:[\\/][^\s'"`;|&<>(){},]*)?(?=$|[\s'"`;|&<>(){},])/g;

/** Caminho comparavel: barras normais, MSYS `/c/` vira `c:/`, sem barra final, minusculo no Windows. */
function normalizaCaminho(p, base) {
  let s = p.replace(/\\/g, "/");
  const msys = /^\/([A-Za-z])(\/.*|$)/.exec(s);
  if (msys) s = `${msys[1]}:${msys[2] || "/"}`;
  s = semNomeCurto(path.resolve(base, s).replace(/\\/g, "/").replace(/\/+$/, ""));
  return process.platform === "win32" ? s.toLowerCase() : s;
}
const dentroDe = (a, b) => a === b || a.startsWith(b + "/");

/** `{principal, worktrees}` normalizados quando o cwd esta num worktree linkado; senao null. */
function principalDoWorktree(cwd) {
  const saida = git(cwd, ["worktree", "list", "--porcelain"]);
  if (!saida) return null;
  const caminhos = saida.split(/\r?\n/).filter((l) => l.startsWith("worktree ")).map((l) => normalizaCaminho(l.slice(9), cwd));
  if (caminhos.length < 2) return null;
  const [principal, ...worktrees] = caminhos;
  const aqui = normalizaCaminho(cwd, cwd);
  if (!worktrees.some((w) => dentroDe(aqui, w))) return null;
  return { principal, worktrees };
}

/**
 * Segmentos da rede: corta so em `;`, `|`, `&` e quebra de linha fora de aspas. Ao
 * contrario de `segmentosComAspas`, parenteses e chaves ficam no segmento: o que esta
 * entre eles alimenta o comando de fora (`Set-Content -Path (Join-Path <P> f)`).
 */
function segmentosDaRede(texto, ehPowerShell) {
  const segs = [];
  let atual = "";
  let aspa = null;
  for (let i = 0; i < texto.length; i += 1) {
    const c = texto[i];
    if (aspa) {
      atual += c;
      if (c === "`" && ehPowerShell && aspa === '"' && i + 1 < texto.length) { atual += texto[i + 1]; i += 1; }
      else if (c === "\\" && !ehPowerShell && aspa === '"' && i + 1 < texto.length) { atual += texto[i + 1]; i += 1; }
      else if (c === aspa) aspa = null;
      continue;
    }
    if (c === "'" || c === '"') { aspa = c; atual += c; continue; }
    if (c === ";" || c === "|" || c === "&" || c === "\n" || c === "\r") {
      // `2>&1`, `>&2`, `&>`: e redirecionamento, nao separador.
      if (c === "&" && (/[<>]$/.test(atual) || texto[i + 1] === ">")) { atual += c; continue; }
      if (atual.trim()) segs.push(atual);
      atual = "";
      continue;
    }
    atual += c;
  }
  if (atual.trim()) segs.push(atual);
  return segs;
}

/** O texto entre parenteses e chaves fora de aspas, concatenado. */
function trechosAninhados(seg) {
  let saida = "";
  let prof = 0;
  let aspa = null;
  for (const c of seg) {
    if (aspa) { if (prof > 0) saida += c; if (c === aspa) aspa = null; continue; }
    if (c === "'" || c === '"') { aspa = c; if (prof > 0) saida += c; continue; }
    if (c === "(" || c === "{") { prof += 1; saida += " "; continue; }
    if ((c === ")" || c === "}") && prof > 0) { prof -= 1; saida += " "; continue; }
    if (prof > 0) saida += c;
  }
  return saida;
}

// Copia: a origem e leitura, o destino fica com a lista (`Copy-Item <P>/a .` e legitimo).
const COPIA_DA_REDE = new Set(["copy-item", "copy", "cpi", "cp"]);
// Chamada .NET de leitura, inteira no segmento: `[IO.File]::ReadAllText('<P>/f')`.
const CHAMADA_NET_NO_INICIO = /^\s*\[\s*[\w.]*\bIO\.[\w.]+\s*\]\s*::\s*(\w+)\s*\(/i;

/** O segmento roda um comando de leitura conhecida (D2)? */
function segmentoDeLeitura(toks, seg, ehPowerShell, configGitNaLinha) {
  if (ehPowerShell) {
    const net = CHAMADA_NET_NO_INICIO.exec(seg);
    if (net) {
      if (!METODOS_NET_DE_LEITURA.has(net[1].toLowerCase())) return false;
      const { args, fechou } = argumentosDaChamada(seg, net[0].length);
      return fechou && args.every((a) => literalDoArgumento(a) !== null) ? "net" : false;
    }
  }
  const pos = posicaoDeComando(toks);
  // So atribuicao (`P=<P>`): o caminho vai para uma variavel que o resto da linha usa
  // (`echo x > $P/f`). Nao e leitura: o caminho citado conta.
  if (pos === null || pos === undefined) return false;
  // PowerShell: string citada na posicao de comando e expressao, nao roda nada (rodar pede `&`).
  // So vale quando o segmento ABRE com a aspa: atribuicao colada (`$p='<P>'`, `[string]$p='<P>'`,
  // `$p,$q='<P>'`) tambem vira um token citado, e ali o caminho vai para a variavel que o
  // resto da linha usa, e conta.
  if (ehPowerShell && toks[pos].q) return pos === 0 && /^\s*['"]/.test(seg);
  const nome = toks[pos].v.replace(/`/g, "").split(/[\\/]/).pop().toLowerCase().replace(/\.exe$/, "");
  if (COPIA_DA_REDE.has(nome) && (ehPowerShell || nome === "cp")) {
    // `cp -t <P> a` poe o destino numa opcao: a lista nao o ve, entao nao e leitura.
    return !toks.some((t) => /^(-t|--target-directory)(=|$)/.test(t.v));
  }
  // Leitura que escreve por opcao (revisao de seguranca): `git log --output=f`,
  // `sort -o f`, `uniq a f`, `rg --pre cmd`, `find -fls f`.
  // Token citado tambem conta: o shell tira as aspas antes de o programa ler a opcao
  // (`find <P> "-delete"`).
  const tem = (re) => toks.some((t) => re.test(t.v));
  // Atribuicao antes do comando (`GIT_EXTERNAL_DIFF='rm <P>/f' git diff`) pode mudar o que
  // ele roda: nao e leitura.
  if (toks.slice(0, pos).some((t) => /^[A-Za-z_][A-Za-z0-9_]*=/.test(t.v))) return false;
  if (nome === "git") {
    // Config do git mexida na mesma linha (`export GIT_EXTERNAL_DIFF=...; git diff`,
    // `git config diff.external ...`): o git "de leitura" pode rodar comando.
    if (configGitNaLinha) return false;
    const subs = subcomandoGit(seg, ehPowerShell ? "PowerShell" : "Bash");
    // `-O` com valor colado, abreviacao de opcao longa (`--outp=f`, `--ext`, `--textc`), e o que
    // faz o git rodar comando da config (`-c diff.external=...`, `--ext-diff`, `--textconv`, `--exec-path`).
    return subs.length > 0 && subs.every((s) => !s.incerto && GIT_DE_LEITURA.has(s.verbo))
      && !tem(/^-O|^--ou(t(p(u(t)?)?)?)?(=|$)|^--op(e(n[-a-z]*)?)?(=|$)/)
      && !tem(/^-c|^--config-env|^--ext|^--textc|^--exec-path/);
  }
  if (nome === "find") return !tem(/^-(delete|exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls)$/);
  // `-o` em grupo de opcoes curtas (`-ro f`), abreviacao de `--output` e o compressor
  // (`--co...`, abreviacao de `--compress-program`), que e comando.
  if (nome === "sort") return !tem(/^-[^-]*o|^--o(u(t(p(u(t)?)?)?)?)?(=|$)|^--co/);
  if (nome === "rg") return !tem(/^--pre(-glob)?(=|$)/);
  if (nome === "uniq") return toks.slice(pos + 1).filter((t) => !/^-/.test(t.v)).length <= 1;
  return LEITURA_DA_REDE.has(nome);
}

/**
 * Destinos de redirecionamento lidos do texto cru, fora de aspas (revisao de seguranca):
 * `>`, `>>`, `>|`, `<>`, `&>`, `n>`, `*>` e destino entre aspas. Duplicacao de
 * descritor (`2>&1`, `>&-`) nao e destino.
 */
function destinosDeRedirecionamento(seg, ehPowerShell) {
  // Escape: contrabarra no Bash, crase no PowerShell (os dois valem fora de aspa simples).
  const esc = ehPowerShell ? "`" : "\\";
  const destinos = [];
  let aspa = null;
  for (let i = 0; i < seg.length; i += 1) {
    const c = seg[i];
    if (c === esc && aspa !== "'") { i += 1; continue; }
    if (aspa) { if (c === aspa) aspa = null; continue; }
    if (c === "'" || c === '"') { aspa = c; continue; }
    if (c !== ">") continue;
    let j = i + 1;
    while (j < seg.length && (seg[j] === ">" || seg[j] === "|")) j += 1;
    if (seg[j] === "&" && /[0-9-]/.test(seg[j + 1] || "")) { i = j; continue; }
    if (seg[j] === "&") j += 1;
    while (j < seg.length && /\s/.test(seg[j])) j += 1;
    // A palavra inteira: trechos citados e nao citados colados ("<P>"/f) viram um so.
    let alvo = "", cru = "", q = null;
    for (; j < seg.length; j += 1) {
      const d = seg[j];
      if (!q && /[\s;|&<>]/.test(d)) break;
      cru += d;
      if (d === esc && q !== "'") { j += 1; if (j < seg.length) { alvo += seg[j]; cru += seg[j]; } continue; }
      if (q) { if (d === q) q = null; else alvo += d; continue; }
      if (d === "'" || d === '"') { q = d; continue; }
      alvo += d;
    }
    // Aspa sem fechar: o resto do segmento e o destino (falha fechado).
    if (q) alvo = cru = seg.slice(i + 1);
    if (alvo) destinos.push(alvo);
    if (cru && cru !== alvo) destinos.push(cru);
    i = j;
  }
  // Aspa sem fechar: o texto citado pode esconder um redirecionamento (falha fechado).
  if (aspa && seg.includes(">")) destinos.push(seg.slice(seg.indexOf(">") + 1));
  return destinos;
}

/** Tokens do segmento sem o valor das opcoes de mensagem de `git`/`gh` (D4). */
function semTextoDeMensagem(toks) {
  const pos = posicaoDeComando(toks);
  const nome = pos === null || pos === undefined ? "" : toks[pos].v.split(/[\\/]/).pop().toLowerCase().replace(/\.exe$/, "");
  if (nome !== "git" && nome !== "gh") return toks;
  const saida = [];
  for (let i = 0; i < toks.length; i += 1) {
    const t = toks[i];
    if (!t.q && OPCOES_DE_TEXTO.has(t.v)) { i += 1; continue; }
    // Valor colado so na opcao longa (`--message="..."`, o token fica citado). `-m"..."` colado
    // nao sai: em grupo de opcoes curtas (`git rebase -mx"rm <P>/f"`) o resto e outra opcao.
    if (/^--(message|body|title)=/.test(t.v)) continue;
    saida.push(t);
  }
  return saida;
}

// Caminho absoluto POSIX (`/srv/repo/...`), fora do Windows.
const CAMINHO_POSIX = /(?:^|(?<=[\s'"=:({,]))\/[^\s'"`;|&<>(){},]*/g;
// Pasta do usuario por atalho (revisao de seguranca): til, a variavel HOME e as de
// perfil do PowerShell e do cmd.
const ATALHO_DE_HOME = /(^|[\s'"=:(,])~(?=[\\/]|$|[\s'"])|\$\{HOME\}|\$HOME\b|\$\{?HOMEDRIVE\}?\$\{?HOMEPATH\}?|\$\{USERPROFILE\}|\$USERPROFILE\b|\$\{?env:HOMEDRIVE\}?\$\{?env:HOMEPATH\}?|%HOMEDRIVE%%HOMEPATH%|\$\{env:(?:USERPROFILE|HOME)\}|\$env:(?:USERPROFILE|HOME)\b|%USERPROFILE%/gi;

/** Caminhos citados num texto: absolutos (Windows, MSYS no Bash, POSIX fora do Windows), com `..` e por atalho de home. */
function caminhosCitados(texto, ehPowerShell) {
  const casa = os.homedir().replace(/\\/g, "/");
  // Replacer por funcao: `$` no texto novo seria padrao de substituicao.
  const t = texto.replace(ATALHO_DE_HOME, (m, antes) => (antes !== undefined ? antes + casa : casa));
  const achados = [...(t.match(CAMINHO_WINDOWS) || []), ...(t.match(CAMINHO_RELATIVO_ACIMA) || [])];
  if (process.platform !== "win32") achados.push(...(t.match(CAMINHO_POSIX) || []));
  else if (!ehPowerShell) achados.push(...(t.match(CAMINHO_MSYS) || []));
  return achados.map((c) => c.replace(/^FileSystem::/i, ""));
}

// Casa redefinida na propria linha (#561): com `HOME=<W>; touch ~/../f` o shell expande o atalho
// para outro lugar, e a rede leria a casa real. Tiradas as formas de leitura (`$NOME`, `${NOME}`,
// `$env:NOME`, `${env:NOME}`, `%NOME%`, sem `=` depois), qualquer mencao aos quatro nomes com a
// casa em uso na linha falha fechado. Regra ampla, nao lista de grafias. Caixa exata no Bash,
// indiferente no PowerShell e no cmd. A mencao se procura sem aspas nem escapes (`H""OME=`), e,
// com a casa em uso, comando que define variavel pelo nome (o nome pode vir montado:
// `export $(echo HOME)=`, `eval`) tambem falha fechado, assim como execucao indireta
// (substituicao, interpretador com `-c`, `source`, `env:` fora de leitura no PowerShell).
// O til em posicao de expansao (`~/x`, `{~,x}`, `=~`; `HEAD~1` nao) e `cd` sem destino usam a
// casa. Ofuscacao deliberada fora dessas classes fica fora do modelo de ameaca: a trava protege
// contra o engano da sessao.
const NOMES_DA_CASA = "HOME|USERPROFILE|HOMEDRIVE|HOMEPATH";
const DEFINE_VARIAVEL = /(^|[\s;&|(`{])(export|declare|typeset|local|readonly|read|mapfile|readarray|unset|eval|env|Set-Variable|New-Variable|sv|nv|Set-Item|si|Invoke-Expression|iex)(?=$|[\s;&|)}])|(^|[\s;&|(`{])printf\s+-v|(^|[\s;&|(`{])(Set-Item|New-Item|Set-Content|Remove-Item|Clear-Item|Rename-Item|Copy-Item|si|ni|sc|ri)\s+(-Path\s+|-LiteralPath\s+)?['"]?env:|\[(System\.)?Environment\]::SetEnvironmentVariable/i;
// `source`/`.` como palavra em qualquer posicao (depois de `if`, `time`, `>/dev/null`, `builtin`,
// quebra de linha), procurado no texto sem aspas nem escapes (`\source`).
const FONTE_DE_SCRIPT = /(^|[^\w.\/$-])(source|\.)(?=\s)/;
const EXECUCAO_INDIRETA = /\$\(|<\(|>\(|(^|[;&|(`{]\s*)(source|\.)(?=\s)|(^|[\s;&|(`{])(bash|sh|zsh|dash|ksh|pwsh|powershell|cmd|node|python3?|perl|ruby)(\.exe)?(\s+[^\s;&|]+)*?\s+(-\w*c|-e|--eval|-Command|-EncodedCommand|-enc|\/c)(?=$|\s)|\[scriptblock\]|\$ExecutionContext|(^|[\s;|(])&\s*[{($'"]/i;
// Bash: aspas simples, e duplas sem `$` nem crase, nao expandem o til nem rodam `cd`; o corpo de
// heredoc com delimitador entre aspas e dado. Desbalanceado: nao mascara (falha fechado).
function mascaraAspasBash(texto) {
  let saida = "";
  for (let i = 0; i < texto.length; i += 1) {
    const c = texto[i];
    if (c === "\\") { saida += texto.slice(i, i + 2); i += 1; continue; }
    if (c !== "'" && c !== '"') { saida += c; continue; }
    let j = i + 1;
    while (j < texto.length && texto[j] !== c) j += c === '"' && texto[j] === "\\" ? 2 : 1;
    if (j >= texto.length) return texto;
    const dentro = texto.slice(i + 1, j);
    saida += c === '"' && /[$`]/.test(dentro) ? texto.slice(i, j + 1) : c + " ".repeat(j - i - 1) + c;
    i = j;
  }
  return saida;
}
// Corpo de heredoc que e dado, inclusive dentro de `"$(cat <<'EOF' ...)"` (a busca do operador
// nao entra em aspas duplas: a aspa que abre a substituicao sai so na copia da busca).
function mascaraHeredocsBash(texto) {
  const busca = mascararCorposDeHeredoc(texto.replace(/"\$\(/g, " $("));
  let saida = "";
  for (let i = 0; i < texto.length; i += 1) {
    const aspaDaSubstituicao = texto[i] === '"' && texto.startsWith("$(", i + 1);
    saida += busca[i] === " " && texto[i] !== "\n" && !aspaDaSubstituicao ? " " : texto[i];
  }
  return saida;
}
// So comandos que nao avaliam os argumentos deixam mascarar as aspas: qualquer outro (`awk`,
// `find -exec`, `bash -c`, alias de git com `!`) pode transformar o texto entre aspas em comando.
const COMANDOS_INERTES = new Set(["echo", "printf", "cat", "grep", "rg", "ls", "head", "tail", "wc", "sort", "uniq", "true", "false", "date", "pwd", "touch", "mkdir", "cp", "mv", "rm"]);
const SUBCOMANDOS_INERTES = { git: /^(commit|log|diff|show|status|add|push|fetch|branch|rev-parse|merge-base|tag)$/, gh: /^(pr|issue)$/ };
function soComandosInertes(texto) {
  const palavras = [...texto.matchAll(/(?:^|[;&|(\n]|\$\()\s*((?:[A-Za-z_]\w*=\S*\s+)*)([^\s;&|()<>]+)(?:\s+([^\s;&|()<>]+))?/g)];
  return palavras.every((m) => {
    const cmd = m[2], sub = m[3] || "";
    if (SUBCOMANDOS_INERTES[cmd]) return SUBCOMANDOS_INERTES[cmd].test(sub);
    return COMANDOS_INERTES.has(cmd) && !(cmd === "printf" && sub === "-v");
  });
}
// Escrita na variavel: `=`, atribuicao composta (`+=`, `??=`), lista (`$env:X, $y =`) e `foreach ($env:X in`.
const ESCRITA_DEPOIS = String.raw`(?!\s*(?:[-+*/%]|\?\?)?=(?!=)|\s*,|\s+in\b)`;
function casaRedefinida(comando, ehPowerShell) {
  const usaCasa = new RegExp(`[$%]\\{?(?:env:)?(?:${NOMES_DA_CASA})`, "i");
  // `cd` sem destino: so opcoes (`-P`, `--`), e depois fim, separador, redirecionamento,
  // comentario ou quebra de linha.
  const cdSemArgumento = /(^|[\s;&|(`{])(cd|chdir|pushd)([ \t]+-[-\w@]*)*[ \t]*($|[;&|)}#<>\r\n]|\d>)/;
  // Til fora de palavra: depois de letra, numero, `_` ou contrabarra ele nao expande (`HEAD~1`);
  // qualquer outro vizinho (`${X/y/~}`, `${U:-~}`) e posicao de expansao, sem lista de grafias.
  const tilDeCasa = /(^|[^\w\\])~/;
  // Continuacao de linha some antes de qualquer checagem (`HO\<LF>ME=`, `${HO\<LF>ME}`, `c\<LF>d`).
  const junto = comando.replace(ehPowerShell ? /`\r?\n/g : /\\\r?\n/g, "");
  const semAspas = junto.replace(ehPowerShell ? /["'`]/g : /["'\\]/g, "");
  const leitura = new RegExp(`(?:\\$\\{(?:env:)?(?:${NOMES_DA_CASA})\\}|\\$(?:env:)?(?:${NOMES_DA_CASA})\\b|%(?:${NOMES_DA_CASA})%)${ESCRITA_DEPOIS}`, ehPowerShell ? "gi" : "g");
  const resto = semAspas.replace(leitura, " ");
  const mencao = new RegExp(`\\b(?:${NOMES_DA_CASA})\\b`, ehPowerShell ? "i" : "");
  // Linha que mexe na casa nunca e inerte: a lista de comandos inertes vira lista de grafias
  // (`printf -vHOME`, `>/dev/null HOME=x git push`), o defeito que derrubou a #552.
  const mexeNaCasa = DEFINE_VARIAVEL.test(semAspas) || mencao.test(resto);
  const mascarado = ehPowerShell ? comando : mascaraAspasBash(mascaraHeredocsBash(junto));
  const vivo = ehPowerShell || mexeNaCasa || !soComandosInertes(mascarado) ? junto : mascarado;
  if (!tilDeCasa.test(vivo) && !usaCasa.test(vivo) && !cdSemArgumento.test(vivo.replace(/["'\\]/g, ""))) return false;
  if (mexeNaCasa) return true;
  if (EXECUCAO_INDIRETA.test(junto)) return true;
  if (FONTE_DE_SCRIPT.test(semAspas)) return true;
  if (!ehPowerShell && comando.includes("`")) return true;
  if (ehPowerShell && /env:/i.test(resto.replace(new RegExp(String.raw`\$\{?env:\w+\}?` + ESCRITA_DEPOIS, "gi"), " "))) return true;
  return false;
}

/**
 * Alvos da rede (D1-D5): um `{dir: <principal>, incerto: true}` por segmento que cita
 * caminho do principal fora de leitura, ou que roda com cwd no principal. Vazio
 * quando o cwd nao e um worktree linkado.
 */
function alvosDaRede(comando, cwd, ehPowerShell) {
  const repo = principalDoWorktree(cwd);
  if (!repo) return [];
  // Isencao dos worktrees por PALAVRA de shell (revisao de seguranca): o caminho do worktree
  // citado numa palavra pode subir para o principal sem o literal `..` que a leitura por token ve.
  // A palavra respeita aspas e escape (`<W>/'a b'/...` e uma so). Perde a isencao quando tem
  // variavel, substituicao ou crase (`<W>/$D/f`); quando, sem aspas e escapes, cai no principal
  // fora dos worktrees (`"<W>"/../../f`, `<W>/.\./f`); ou, no Bash, quando tem chave que monta `..`
  // (`{<W>,y}/../f`, `<W>/.{.,}/f`, `{x,.}.`, `.{,}.`). `{1..3}`, `{a,b}.txt`, `f.{js,ts}`, `{cd,<W>}` seguem
  // isentos, e expansao em outra palavra da linha nao importa.
  const casa = os.homedir().replace(/\\/g, "/");
  const comCasa = (t) => t.replace(ATALHO_DE_HOME, (m, antes) => (antes !== undefined ? antes + casa : casa));
  const esc = ehPowerShell ? "`" : "\\";
  // Palavras do texto, com a fronteira so fora de aspas e de escape; cada uma com o texto cru
  // e o texto sem aspas nem escapes.
  const palavrasDe = (texto) => {
    const saida = [];
    let cru = "", limpo = "", aspa = null;
    const fecha = () => { if (cru) saida.push({ cru, limpo }); cru = ""; limpo = ""; };
    for (let i = 0; i < texto.length; i += 1) {
      const c = texto[i];
      if (c === esc && aspa !== "'" && i + 1 < texto.length) { cru += c + texto[i + 1]; if (texto[i + 1] !== "\n") limpo += texto[i + 1]; i += 1; continue; }
      if (aspa) { cru += c; if (c === aspa) aspa = null; else limpo += c; continue; }
      if (c === "'" || c === '"') { aspa = c; cru += c; continue; }
      if (/[\s;|&<>()]/.test(c)) { fecha(); continue; }
      cru += c; limpo += c;
    }
    fecha();
    return saida;
  };
  const sobeNaChave = (p0) => {
    const p = p0.replace(/\{-?\w+\.\.-?\w+(\.\.-?\d+)?\}/g, "{}");
    if (!/[{}]/.test(p)) return false;
    if (/\.\.|[{,]\.|\.[},]/.test(p)) return true;
    // Ponto antes e depois do MESMO grupo com alternativa vazia (`.{,}.`, `.{x,}.`, `.{{,},}.`).
    for (const m of p.matchAll(/\.\{((?:[^{}]|\{[^{}]*\})*)\}\./g)) if (/^,|,$|,,|\{,|,\}|\{\}/.test(m[1])) return true;
    return false;
  };
  // Atalho de home por shell. Bash: so `$HOME`, `${HOME}`, `$USERPROFILE`, `${USERPROFILE}`, com caixa exata e
  // chave fechada (`${HOME/x/y}` e substituicao, `$home` e outra variavel). PowerShell: `$env:`,
  // `${env:}`, `%USERPROFILE%` e `$HOME` em qualquer caixa.
  const CASA = ehPowerShell
    ? /(\$\{env:(?:USERPROFILE|HOME)\}|\$env:(?:USERPROFILE|HOME)\b|\$HOME\b|%USERPROFILE%)/i
    : /(\$\{HOME\}|\$HOME\b|\$\{USERPROFILE\}|\$USERPROFILE\b)/;
  const CASA_NO_INICIO = new RegExp("^(['\"]?)" + CASA.source + "(?=[\\\\/])", CASA.flags);
  const foraDosWorktrees = (n) => dentroDe(n, repo.principal) && !repo.worktrees.some((w) => dentroDe(n, w)) && !ehScratchpad(n);
  // `p.cru` e o texto ORIGINAL da palavra (o `$` de `$HOME` conta); `p.limpo` vem do texto com o
  // atalho de home expandido, so para achar e resolver o caminho `c`.
  // O atalho de home no INICIO da palavra (`$HOME/...`, `${env:USERPROFILE}\...`) nao conta como
  // expansao: o valor e o da casa. HOME redefinido na propria linha ja caiu antes, em
  // `casaRedefinida` (#561). No meio (`<W>/$HOME/f`) conta.
  const palavraQueSobe = (p, base, c) => {
    if (/[$`]/.test(p.cru.replace(CASA_NO_INICIO, (m, aspa) => aspa))) return true;
    // Com chave (Bash), cada alternativa da expansao conta, e mais a checagem da chave; expansao
    // que estoura falha fechado. Virgula fora de chave (`W,W` de trecho aninhado, lista do
    // PowerShell) separa caminhos: cada pedaco conta.
    // A palavra inteira e o trecho que comeca no caminho citado (`of="<W>"/../../f`: o prefixo
    // `of=` faria a palavra inteira virar caminho relativo).
    const i0 = p.limpo.indexOf(c);
    const i = i0 > 0 && !/[{},]/.test(p.limpo.slice(0, i0)) ? i0 : -1;
    let alternativas = i > 0 ? [p.limpo, p.limpo.slice(i)] : [p.limpo];
    if (!ehPowerShell && /[{}]/.test(p.limpo)) {
      if (sobeNaChave(p.limpo)) return true;
      alternativas = expandirChaves(p.limpo, "u".repeat(p.limpo.length));
      if (!alternativas) return true;
      if (i > 0) alternativas = alternativas.concat(expandirChaves(p.limpo.slice(i), "u".repeat(p.limpo.length - i)) || ["\0"]);
    }
    return alternativas.some((a) => a.split(",").some((x) => x && foraDosWorktrees(normalizaCaminho(x, base))));
  };
  const protegido = (c, base, texto = "") => {
    const n = normalizaCaminho(c, base);
    if (!dentroDe(n, repo.principal) || ehScratchpad(n)) return false;
    if (!repo.worktrees.some((w) => dentroDe(n, w))) return true;
    // Palavras do texto original; cada uma com o `limpo` do texto com atalho de home expandido.
    const palavras = palavrasDe(texto).map((p) => ({ cru: p.cru, limpo: palavrasDe(comCasa(p.cru)).map((x) => x.limpo).join(" ") || p.limpo }))
      .filter((p) => p.cru.includes(c) || p.limpo.includes(c));
    // Palavra nao achada: falha fechado, com a linha inteira no lugar da palavra.
    if (!palavras.length) return /[{}$`]/.test(texto);
    return palavras.some((p) => palavraQueSobe(p, base, c));
  };
  const citaProtegido = (texto, base) => caminhosCitados(texto, ehPowerShell).some((c) => protegido(c, base, texto));
  const alvo = [{ dir: repo.principal, incerto: true }];
  if (casaRedefinida(comando, ehPowerShell)) return alvo;
  // Segmentacao nao confiavel (D2): a linha inteira e um segmento so, e nada e leitura.
  // Bash com `\` + quebra: colar as linhas erra quando as contrabarras sao pares (`ls \\` + quebra +
  // `rm <P>/f`), e nao colar erra a continuacao; a linha toda vira um segmento so.
  const naoConfiavel = /\$\(|`|\$'|\\\r?\n/.test(comando) && !ehPowerShell
    || ehPowerShell && (desalinhaAMascara(comando) || /[\u2018-\u201e]/.test(comando) || /"[^"]*\$\(/.test(comando) || /@['"]/.test(comando));
  if (naoConfiavel) return citaProtegido(comando, cwd) ? alvo : [];

  const segmentos = segmentosDaRede(comando, ehPowerShell);
  // Config do git ou do pager mexida em qualquer segmento da linha (revisao de seguranca).
  const configGitNaLinha = /(^|[\s;&|(])(export\s+)?(GIT_\w*|\w*PAGER)=|\$env:(GIT_|\w*PAGER)|\bgit\b[^;&|]*\sconfig\b/i.test(comando);
  const leitura = segmentos.map((seg) => segmentoDeLeitura(tokensComAspas(seg), seg, ehPowerShell, configGitNaLinha));
  // Pipeline com escritor (`Get-Item <P>/a | Set-Content -Value x`): o segmento de
  // leitura alimenta quem escreve, entao os caminhos dele tambem contam.
  const pipelineComEscritor = temForaDeAspas(comando, "|") && leitura.some((l) => !l);
  const estado = { atual: cwd, incerto: false, pilhaPushd: [] };
  for (let i = 0; i < segmentos.length; i += 1) {
    const seg = segmentos[i];
    const mov = resolverMovedor(seg, estado, ehPowerShell);
    const base = mov.cwd;
    const toks = tokensComAspas(seg);
    if (leitura[i] && !pipelineComEscritor) {
      // Leitura: conta o destino de redirecionamento e o que esta entre parenteses ou
      // chaves (`Get-Content (Remove-Item <P>/f)` roda o de dentro).
      for (const destino of destinosDeRedirecionamento(seg, ehPowerShell)) {
        if (ehDescarteDeSaida(destino, ehPowerShell)) continue;
        if (caminhosCitados(destino, ehPowerShell).concat([destino.replace(/^FileSystem::/i, "")]).some((c) => protegido(c, base, destino))) return alvo;
      }
      // Na chamada .NET de leitura, o argumento entre parenteses e o proprio alvo da leitura.
      if (leitura[i] !== "net" && citaProtegido(trechosAninhados(seg), base)) return alvo;
      continue;
    }
    // Fora de leitura: rodar com cwd no principal, ou citar caminho dele.
    if (!mov.incerto && protegido(base, base)) return alvo;
    // Texto cru (as aspas delimitam o caminho: `('<P>'+'/f')`); em `git`/`gh`, os tokens sem a mensagem (D4).
    const semMensagem = semTextoDeMensagem(toks);
    const texto = semMensagem === toks ? seg : semMensagem.map((t) => t.v).join(" ");
    if (citaProtegido(texto, base)) return alvo;
  }
  return [];
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
  // #530 (D3/D5): comando que nao se consegue conferir (estouro de chaves, wrapper
  // fundo demais) barra como o ramo incerto de `procuraCLI`: so dentro de repo,
  // e o motivo vai ao stderr pela `bloqueia`.
  const barraSemConferir = (motivo) => {
    if (ehScratchpad(cwd)) return;
    const estadoAqui = estadoDoRepo(cwd);
    if (estadoAqui) bloqueia(motivo, estadoAqui.toplevel, `${ev.agent_type || "?"} (${ev.agent_id})`);
  };
  let motivo = null;

  if (FERRAMENTAS_DE_ESCRITA.has(nome)) {
    const alvo = entrada.file_path || entrada.notebook_path || null;
    if (alvo) { alvos = [{ dir: alvo, incerto: false }]; motivo = `Escrita (${nome}) em ${alvo}`; }
  } else if ((nome === "Bash" || nome === "PowerShell") && typeof entrada.command === "string") {
    const ehPS = nome === "PowerShell";
    // #530 (D5): expansao de chaves que estoura o teto nao e conferida em nenhum
    // segmento. Barrar antes de qualquer outra conta, com o motivo no stderr.
    if (cwdPorSegmento(entrada.command, cwd, ehPS).some((s) => s.estouro)) {
      barraSemConferir("expansao de chaves grande demais para conferir");
    }
    // Rede de caminho do principal (#552): somada aos alvos da lista, no fim do ramo.
    const rede = alvosDaRede(entrada.command, cwd, ehPS);
    const verbo = verboNaLinha(entrada.command, VERBOS_QUE_MEXEM, nome);
    if (verbo === SUB_ANINHADO.verbo) barraSemConferir(MOTIVO_ANINHADO);
    // Escrita por redirecionamento ou cmdlet (D4, rodada 2): e checada TAMBEM na linha
    // com verbo git (`echo x > <P>/f && git commit`). Antes so rodava sem verbo, e a
    // linha com verbo passava batida.
    const escritaLida = alvosBashEscrita(entrada.command, cwd, ehPS);
    // #530 (D3/D5): `barrar` nao e destino de escrita, e sim "nao deu para conferir".
    const barrar = escritaLida.find((a) => a.tipo === "barrar");
    if (barrar) barraSemConferir(barrar.motivo);
    const alvosEscrita = escritaLida.filter((a) => a.tipo !== "barrar").map((a) => ({ dir: a.dir, incerto: !!a.incerto }));
    if (verbo) {
      // `incerto` viaja junto (nao so como alvo extra em cwdInicial) — ver o
      // comentario em `alvosBash`.
      alvos = alvosBash(entrada.command, cwd, undefined, nome).map((a) => ({ dir: a.dir, incerto: !!a.incerto }));
      alvos = alvos.concat(alvosEscrita);
      motivo = `Comando que mexe no estado do repo: git ${verbo}`;
    } else {
      // Inspecionar redirecionamentos e ferramentas de escrita
      if (alvosEscrita.length > 0) {
        alvos = alvosEscrita;
        motivo = `Escrita via Bash (redirecionamento ou ferramenta)`;
      } else {
        // Procurar por CLI externa que escreve. H1 (rodada 5): cada CLI
        // achada tem o cwd do PROPRIO segmento (`cwdPorSegmento`), nao o cwd
        // FINAL da linha inteira (`resolverCwdEfetivo` antigo) — e o que
        // fecha `codex exec --yolo && cd <worktree>` rodado no principal: o
        // `codex` roda no principal, mas o cwd final (depois do `cd`) e o
        // worktree, e o gate liberava lendo o lugar errado. Mais de uma CLI
        // na mesma linha, cada uma com o seu proprio cwd — bloqueia na
        // PRIMEIRA que estiver fora de worktree (bloqueia() sai o processo).
        const achadas = procuraCLI(entrada.command, CLIS_QUE_ESCREVEM, nome);
        if (achadas.length) {
          const porSegmento = cwdPorSegmento(entrada.command, cwd, ehPS);
          for (const achado of achadas) {
            const doSegmento = porSegmento[achado.indiceSegmento] || { cwd, incerto: true };
            const incerto = achado.incerto || doSegmento.incerto;
            if (incerto) {
              // `cd` que nao resolve (variavel, subshell, `cd -`), `popd`
              // sem `pushd`, ou conteudo dinamico de `eval`/`bash -c` podem
              // levar a QUALQUER diretorio ou rodar QUALQUER CLI, inclusive
              // no principal: bloqueia direto, sem passar pela classificacao
              // de worktree que dependeria do proprio cwd que nao da pra
              // confiar.
              if (!ehScratchpad(cwd)) {
                const estadoAqui = estadoDoRepo(cwd);
                if (estadoAqui) {
                  bloqueia(
                    achado.incerto
                      ? `Comando dinamico (eval/bash -c) com conteudo nao resolvivel — pode rodar CLI que escreve`
                      : `CLI que escreve (${achado.nome}) com cd nao resolvido — destino desconhecido`,
                    estadoAqui.toplevel,
                    `${ev.agent_type || "?"} (${ev.agent_id})`
                  );
                }
              }
            } else if (!ehScratchpad(doSegmento.cwd)) {
              const estado = estadoDoRepo(dirDe(doSegmento.cwd));
              if (estado && !estado.ehWorktree) {
                bloqueia(
                  `CLI que escreve (${achado.nome})`,
                  estado.toplevel,
                  `${ev.agent_type || "?"} (${ev.agent_id})`
                );
              }
            }
          }
        }
      }
    }
    if (rede.length) {
      if (!alvos.length) motivo = "Comando que cita caminho do checkout principal (fora de leitura)";
      alvos = alvos.concat(rede);
    }
  }

  if (!alvos.length) process.exit(0);

  for (const { dir, incerto } of alvos) {
    if (ehScratchpad(dir)) continue; // scratchpad da sessao: livre, ainda que seja repo git
    const estado = estadoDoRepo(dirDe(dir));
    if (!estado) continue;           // fora de repo git: livre
    // `incerto` (emenda auditor, rodada 5): `popd` sem `pushd` correspondente,
    // ou outro movedor que nao resolve, pode ter deixado o shell em QUALQUER
    // diretorio — inclusive um que E um worktree legitimo, mas nao e
    // necessariamente o de onde o comando de verdade rodou. Bloqueia direto,
    // sem confiar na classificacao de worktree — mesmo espirito do ramo de
    // CLI que ja faz isso para `cd`/subshell nao resolvidos.
    if (!incerto && estado.ehWorktree) continue; // worktree linkado: era pra ser isso mesmo
    const restauro = linhaDeRestauro(entrada.command || '', estado.toplevel, nome);
    bloqueia(motivo, estado.toplevel, `${ev.agent_type || "?"} (${ev.agent_id})`, restauro, estado.ehWorktree);
  }
  process.exit(0);
}

main();
