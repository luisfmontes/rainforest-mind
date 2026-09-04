#!/usr/bin/env node
/**
 * PreToolUse — barra `gh issue close` direto e `gh pr create/merge` sem evidência.
 *
 * Decisões D15, D16: fechar Issue sem o marcador de evidência é bloqueado.
 * - `gh issue close <n>` direto → exit 2, stderr aponta para scripts/fechar-issue.cjs
 * - `gh pr create`/`gh pr merge` com corpo citando `closes #N` para Issue sem marcador → exit 2
 * - Corpo ilegível (editor interativo) → exit 2 dizendo isso
 * - Saídas de emergência: `RAINFOREST_GATE_OFF=1`, `.rainforest-gate-off`
 *
 * O gate só LÊ comentários via `gh issue view --json comments`; nunca escreve.
 */

const { execFileSync, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const { MARCADOR } = require("./lib/marcador-evidencia.cjs");
const { executar } = require("./lib/resolver-executavel.cjs");
const {
  tokensComAspas, posicaoDeComando, textoAPartir, WRAPPERS_QUE_REPASSAM,
  WRAPPERS_DE_COMANDO, desempacotarWrapperDeString,
} = require("./lib/tokens-comando.cjs");
const { cwdPorSegmento } = require("./lib/cwd-efetivo.cjs");

/**
 * Normaliza o nome de um executável: remove caminho, extensão e aspas.
 * Exemplos: `gh`, `gh.exe`, `gh.cmd`, `"gh"`, `C:\x\gh.exe` → `gh`
 */
function normalizarExecutavel(nome) {
  let sem_aspas = nome.replace(/^["']|["']$/g, "");
  sem_aspas = path.basename(sem_aspas);
  sem_aspas = sem_aspas.replace(/\.(exe|cmd|bat)$/i, "");
  return sem_aspas.toLowerCase();
}

/**
 * Verifica se os subcomandos contêm uma sequência específica (case-insensitive).
 */
function temSubcomando(subcomandos, padrao) {
  return indiceSequencia(subcomandos, padrao) !== -1;
}

/**
 * Índice da primeira ocorrência de `padrao` como sub-sequência CONTÍGUA
 * (case-insensitive) em `tokens`, ou -1 se não achar.
 */
function indiceSequencia(tokens, padrao) {
  for (let i = 0; i <= tokens.length - padrao.length; i++) {
    if (
      tokens
        .slice(i, i + padrao.length)
        .every((s, idx) => s.toLowerCase() === padrao[idx].toLowerCase())
    ) {
      return i;
    }
  }
  return -1;
}

/**
 * Separa um comando em segmentos, respeitando aspas simples/duplas.
 * Delimitadores fora de aspas: `;`, `&&`, `||`, `|`, quebra de linha — e
 * também `(`, `)`, `{`, `}` (subshell, grupo, ou o `(` de uma substituição
 * `$(...)`), que aqui SEMPRE fecham o segmento corrente e abrem um novo: o
 * conteúdo de dentro vira segmento próprio, verificável como qualquer outro.
 *
 * É deliberadamente mais agressivo que a função homônima de
 * `lib/cwd-efetivo.cjs` (que só MARCA incerto, porque ali importa rastrear
 * o cwd através do subshell — dividir mudaria essa semântica). Aqui o
 * objetivo é só garantir que um `gh ...` escondido lá dentro apareça como
 * segmento verificável; não precisa entender a sintaxe do subshell/grupo.
 */
function segmentosParaGate(cmd) {
  const segmentos = [];
  let atual = "";
  let aspa = null;

  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];

    if (aspa) {
      // P4 (rodada 8, lote 3, 2026-09-04): `$(...)` DENTRO de aspas DUPLAS
      // e executado pelo bash mesmo citado — `echo "$(gh issue close 42)"`
      // fecha a Issue de verdade. Ate aqui `segmentosParaGate` so descia em
      // `(`/`)` FORA de aspas; dentro de aspas simples/duplas eram so
      // caracteres do texto, entao o `gh issue close` la dentro nunca virava
      // segmento verificavel. Aspas SIMPLES ficam de fora de proposito — o
      // bash NAO expande `$(...)` dentro delas.
      //
      // O extra aqui e um PUSH ADICIONAL, sem tocar em `atual`/`aspa`/`i`:
      // o texto original continua intacto e vira o MESMO segmento de
      // sempre (importa para `gh pr create --body "$(...)"`, que precisa
      // continuar batendo no corpo INTEIRO para a checagem de legibilidade
      // ver o `$(` e bloquear por ilegivel — cortar o texto ali quebraria
      // essa checagem). O conteudo interno so GANHA verificacao a mais.
      if (aspa === '"' && c === "$" && cmd[i + 1] === "(") {
        let profundidade = 1;
        let j = i + 2;
        let interno = "";
        while (j < cmd.length && profundidade > 0) {
          if (cmd[j] === "(") profundidade += 1;
          else if (cmd[j] === ")") {
            profundidade -= 1;
            if (profundidade === 0) break;
          }
          interno += cmd[j];
          j += 1;
        }
        if (interno.trim()) segmentos.push(interno);
      }
      if (c === aspa) aspa = null;
      atual += c;
      continue;
    }
    if (c === '"' || c === "'") {
      aspa = c;
      atual += c;
      continue;
    }
    if (c === "&" && cmd[i + 1] === "&") {
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      i++;
      continue;
    }
    if (c === "|" && cmd[i + 1] === "|") {
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      i++;
      continue;
    }
    if (c === ";" || c === "|" || c === "\n" || c === "(" || c === ")" || c === "{" || c === "}") {
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      continue;
    }
    if (
      c === "&" &&
      cmd[i + 1] !== "&" &&
      cmd[i + 1] !== ">" &&
      cmd[i - 1] !== ">" &&
      cmd[i - 1] !== "<" &&
      cmd[i - 1] !== "|"
    ) {
      // `&` simples (job em background) tambem separa (K1, rodada 6, lote
      // 3, 2026-09-03) — exceto colado em `&&` (braço acima), `&>`, ou
      // depois de `>`/`<`/`|` (`>&`, `<&`, `|&`): esses ficam no segmento.
      // Sem isto, `sudo & gh issue close 42` era UM segmento so, o `sudo`
      // (prefixo conhecido) fazia `pularPrefixos` parar em `&`, e como
      // `tokens[0]` era prefixo conhecido a rede de seguranca de wrapper
      // desconhecido (`ehPrefixoOuWrapperConhecido`) tambem pulava o
      // segmento — o `gh issue close` direto passava sem checagem nenhuma.
      if (atual.trim()) segmentos.push(atual);
      atual = "";
      continue;
    }
    atual += c;
  }

  if (atual.trim()) segmentos.push(atual);
  return segmentos;
}

/**
 * Tenta rodar um comando git neste diretório. Retorna output ou null se falhar.
 */
function git(dir, args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

/**
 * Extrai a lista de Issues citadas num corpo de PR usando padrões de fechamento.
 * Padrão: close(s|d)|fix(es|ed)|resolve(s|d) seguido de `#<n>` OU da URL
 * completa da Issue (`https://github.com/org/repo/issues/<n>`).
 * Retorna array de números únicos encontrados.
 *
 * M2 (auditor, 5a revisao, 2026-09-03): o GitHub tambem fecha Issue quando o
 * corpo cita a URL completa, nao so `#N` — `Closes
 * https://github.com/org/repo/issues/42` fecha a Issue 42 do jeito que
 * `Closes #42` fecha. A forma por URL e conhecimento do GitHub (as nove
 * palavras-chave: close, closes, closed, fix, fixes, fixed, resolve,
 * resolves, resolved), nao verificado por rede nesta rodada.
 */
function extrairIssuesCitadas(corpo) {
  const regex =
    /\b(?:close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)\s+(?:#|https?:\/\/\S*\/issues\/)(\d+)/gi;
  const issues = new Set();
  let match;
  while ((match = regex.exec(corpo)) !== null) {
    issues.add(parseInt(match[1], 10));
  }
  return Array.from(issues);
}

/**
 * Verifica se uma Issue tem comentário com o marcador de evidência.
 * Retorna true se encontrado, false caso contrário ou em erro.
 */
function temMarcadorEvidencia(issueNum) {
  try {
    const resultado = executar("gh", [
      "issue",
      "view",
      String(issueNum),
      "--json",
      "comments",
    ]);

    // Erro ao chamar o comando
    if (resultado.status === null || resultado.status === undefined) {
      return false;
    }

    if (resultado.status !== 0) {
      return false;
    }

    const saida = (resultado.stdout || "").trim();
    return saida.includes(MARCADOR);
  } catch (e) {
    return false;
  }
}

/**
 * Extrai o corpo do comando `gh pr create` ou `gh pr merge`.
 * Procura por `--body <valor>`/`--body=<valor>`/`-b <valor>` (o corpo direto)
 * ou `--body-file <arquivo>`/`--body-file=<arquivo>`.
 * Retorna { tipo: "direto"|"arquivo"|"nenhum", conteudo: string|null, legivel: bool }
 *
 * P3 (rodada 8, lote 3, 2026-09-04): a versao anterior usava o regex
 * `/--body\s+["']([^"']+)["']/i` sobre o texto CRU do comando — ele para no
 * PRIMEIRO apostrofo, porque `[^"']+` exclui aspas simples do meio do corpo.
 * `gh pr create --body "don't forget: closes #42"` capturava só `don`,
 * perdia o `closes #42` de vista, e o gate liberava um PR que de verdade
 * fecha a Issue #42 sem evidência — o caso mais grave, porque apostrofo em
 * prosa é rotina, não um ataque. Agora usa `tokensComAspas`: o token inteiro
 * (apostrofo incluso, se veio de dentro de aspas DUPLAS) sai intacto, sem
 * regex tentando adivinhar onde o valor termina.
 *
 * `cwdSegmento` (rodada 15, lote 3, 2026-09-04): o diretório onde ESTE
 * segmento roda de verdade, já resolvido por `cwdPorSegmento` em `main()` —
 * `null` quando não dá pra saber com segurança (segmento não achado no mapa,
 * ou marcado `incerto` por um `cd`/`pushd` que não resolve). Um caminho de
 * `--body-file` RELATIVO tem que ser lido contra ESTE cwd, não contra o do
 * processo do hook: `cd <worktree> && gh pr create --body-file corpo.txt`
 * roda o `gh` (e o shell real leria `corpo.txt`) de dentro do worktree,
 * nunca de onde o hook foi disparado. Caminho absoluto ignora `cwdSegmento`
 * por completo — não há ambiguidade a resolver.
 */
function extrairCorpoDoPR(segmento, cwdSegmento) {
  const toks = tokensComAspas(segmento);
  for (let i = 0; i < toks.length; i += 1) {
    const tok = toks[i].v;
    const pontoIgual = tok.indexOf("=");
    const chave = (pontoIgual === -1 ? tok : tok.slice(0, pontoIgual)).toLowerCase();

    if (chave === "--body" || chave === "-b") {
      let corpo;
      if (pontoIgual !== -1) {
        corpo = tok.slice(pontoIgual + 1);
      } else if (i + 1 < toks.length) {
        corpo = toks[i + 1].v;
      } else {
        continue;
      }
      // Validar se o corpo é legível: não contém $(...) nem crases.
      if (corpo.includes("$(") || corpo.includes("`")) {
        return { tipo: "direto", conteudo: corpo, legivel: false };
      }
      return { tipo: "direto", conteudo: corpo, legivel: true };
    }

    if (chave === "--body-file") {
      let arquivo;
      if (pontoIgual !== -1) {
        arquivo = tok.slice(pontoIgual + 1);
      } else if (i + 1 < toks.length) {
        arquivo = toks[i + 1].v;
      } else {
        continue;
      }
      if (!path.isAbsolute(arquivo) && cwdSegmento == null) {
        // Caminho relativo e não dá pra saber onde este segmento roda de
        // verdade (não achado no mapa de `cwdPorSegmento`, ou `incerto`):
        // ler contra o cwd do PROCESSO do hook seria adivinhar um lugar que
        // pode não ser onde o `gh` roda — bloqueia por segurança, igual a
        // um arquivo ilegível.
        return { tipo: "arquivo", conteudo: null, legivel: false, cwdIncerto: true };
      }
      const caminhoResolvido = path.isAbsolute(arquivo)
        ? arquivo
        : path.resolve(cwdSegmento, arquivo);
      try {
        const conteudo = fs.readFileSync(caminhoResolvido, "utf8");
        return { tipo: "arquivo", conteudo, legivel: true };
      } catch {
        return { tipo: "arquivo", conteudo: null, legivel: false };
      }
    }
  }

  return { tipo: "nenhum", conteudo: null, legivel: false };
}

function bloqueia(motivo) {
  process.stderr.write(motivo);
  process.exit(2);
}

// `WRAPPERS_DE_COMANDO`, `desempacotarWrapper` (agora
// `desempacotarWrapperDeString`) e as funcoes auxiliares dele
// (`extrairPrimeiroToken`, `casaPrefixoDeFlag`, `desempacota`,
// `contemConstrucaoIlegivel`) moraram AQUI ate a rodada 11 (lote 3,
// 2026-09-04) — moveram para `lib/tokens-comando.cjs` (importado no topo)
// para `gate-staging-total.cjs` e `gate-worktree.cjs` compartilharem a MESMA
// implementacao: nenhum dos dois desempacotava `eval`/`bash -c`/
// `Invoke-Expression`/`iex`/`pwsh -Command`/`cmd /c`, so este gate tinha
// aprendido (R2, rodada 9). Ver o docblock de `desempacotarWrapperDeString`
// la para o comportamento completo (incluindo `-EncodedCommand`).

/**
 * Aplica as checagens D15/D16 a uma invocação de `gh` já identificada:
 * `segmento` é o texto bruto (para extrair `--body`/`--body-file`),
 * `subcomandos` são os tokens que vêm depois de `gh`, e `cwdSegmento` é o
 * diretório efetivo deste segmento (ou `null` se incerto) — ver o docblock
 * de `extrairCorpoDoPR`.
 */
function verificarComandoGh(segmento, subcomandos, cwdSegmento) {
  // Caso (a): `gh issue close <n>` → exit 2
  if (temSubcomando(subcomandos, ["issue", "close"])) {
    bloqueia(
      `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
      `Razão: 'gh issue close' direto não registra a evidência de pronto.\n\n` +
      `Use:\n` +
      `  node scripts/fechar-issue.cjs <número> --comando "<seu-comando>" --saida "<saída-ou-arquivo>"\n\n` +
      `O script registra o comentário com a evidência antes de fechar.\n`
    );
  }

  // Caso (b) e (c): `gh pr create` ou `gh pr merge` → verificar corpo
  if (temSubcomando(subcomandos, ["pr", "create"]) || temSubcomando(subcomandos, ["pr", "merge"])) {
    const corpoDoPR = extrairCorpoDoPR(segmento, cwdSegmento);

    // Corpo ilegível (não consegue ler com segurança)
    if (!corpoDoPR.legivel) {
      if (corpoDoPR.tipo === "arquivo" && corpoDoPR.cwdIncerto) {
        bloqueia(
          `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
          `Razão: --body-file usa caminho relativo, e o diretório efetivo deste ` +
          `comando não pôde ser determinado com segurança (cd/pushd dinâmico ou ` +
          `não resolvível antes do 'gh').\n\n` +
          `Use um caminho absoluto em --body-file, ou remova o 'cd' dinâmico antes do 'gh'.\n`
        );
      } else if (corpoDoPR.tipo === "arquivo") {
        bloqueia(
          `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
          `Razão: não consegui ler o arquivo de corpo do PR.\n\n` +
          `Use --body "texto" ou --body-file <arquivo-legível>.\n`
        );
      } else if (corpoDoPR.tipo === "direto" && (corpoDoPR.conteudo.includes("$(") || corpoDoPR.conteudo.includes("`"))) {
        bloqueia(
          `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
          `Razão: o corpo do PR contém substituição de comando (\\$(...) ou backticks), não consegui ler com segurança.\n\n` +
          `Use --body "texto-plano" ou --body-file <arquivo> com o corpo já expandido.\n`
        );
      } else {
        bloqueia(
          `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
          `Razão: o corpo do PR vem de editor interativo (sem --body ou --body-file).\n\n` +
          `Se o corpo cita 'closes #N', a checagem não consegue ler.\n` +
          `Use --body "texto" ou --body-file <arquivo> para incluir a informação de fechamento.\n`
        );
      }
    }

    // Corpo legível: verificar Issues citadas
    const issues = extrairIssuesCitadas(corpoDoPR.conteudo || "");
    for (const issue of issues) {
      if (!temMarcadorEvidencia(issue)) {
        bloqueia(
          `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
          `Razão: Issue #${issue} não tem comentário com a evidência de pronto.\n\n` +
          `O critério de pronto deve ter sido rodado e colado em comentário.\n` +
          `Use:\n` +
          `  node scripts/fechar-issue.cjs ${issue} --comando "<seu-comando>" --saida "<saída-ou-arquivo>"\n\n` +
          `Depois crie o PR com o corpo citando closes #${issue}.\n`
        );
      }
    }
  }
}

/**
 * `exe` (já normalizado) é um prefixo que sabemos que só repassa o comando
 * adiante, ou um wrapper que sabemos desempacotar? Usado só pela checagem
 * de "wrapper desconhecido" (item 4) — o efeito de um prefixo/wrapper
 * RECONHECIDO já foi resolvido por `posicaoDeComando`/`desempacotarWrapper`,
 * e não deve ganhar uma segunda chance aqui: se o mecanismo específico dele
 * falhar (ou for mutado), a bateria tem que sentir, não ser socorrida por
 * este retorno de segurança genérico.
 *
 * `WRAPPERS_QUE_REPASSAM` vem de `lib/tokens-comando.cjs` — P2 (rodada 8,
 * lote 3, 2026-09-04): este gate tinha sua PRÓPRIA lista idêntica
 * (`PREFIXOS_QUE_PASSAM_ADIANTE`) e seu próprio tokenizador/`pularPrefixos`,
 * com o MESMO furo do P1 (`env -u FOO gh issue close 12` escapava). Em vez
 * de consertar duas vezes, os três gates (`gate-worktree.cjs`,
 * `gate-staging-total.cjs` e este) agora compartilham uma implementação só.
 */
function ehPrefixoOuWrapperConhecido(exe) {
  return (
    exe === "gh" ||
    exe === "eval" ||
    exe === "invoke-expression" ||
    exe === "iex" ||
    exe === "pwsh" ||
    exe === "powershell" ||
    exe === "cmd" ||
    WRAPPERS_QUE_REPASSAM.has(exe) ||
    !!WRAPPERS_DE_COMANDO[exe]
  );
}

/**
 * Diretório efetivo de `segmento`, segundo `mapaCwd` (a saída de
 * `cwdPorSegmento(comando, cwdDoEvento)` calculada uma vez em `main()` sobre
 * a linha INTEIRA). `null` quando não dá pra saber com segurança: segmento
 * não achado (por exemplo, um sub-segmento nascido de dentro de um
 * `eval`/`bash -c`/subshell, que não tem correspondência 1:1 com a
 * segmentação de `cwdPorSegmento` — ela NÃO desce em `(`/`{`, ao contrário
 * de `segmentosParaGate`) ou marcado `incerto` (um `cd`/`pushd` com `$(...)`,
 * variável, ou destino que não resolve).
 *
 * O casamento é por TEXTO (trim), não por índice: `segmentosParaGate` e a
 * `segmentosComAspas` que `cwdPorSegmento` usa por baixo dividem `;`, `&&`,
 * `||`, `|`, quebra de linha e `&` solto DA MESMA FORMA — só `segmentosParaGate`
 * desce além disso em `(`/`)`/`{`/`}`. Quando não há subshell no meio, os
 * segmentos batem exatamente; quando há, o texto não casa e o resultado é
 * `null` (conservador), nunca um cwd errado por índice desalinhado.
 *
 * Texto repetido (o MESMO comando `gh ...` aparece mais de uma vez na linha,
 * com `cwd`s diferentes por causa de `cd`s entre as ocorrências) quebrava
 * isso: `.find` sempre devolvia a PRIMEIRA entrada de `mapaCwd` com aquele
 * texto, não importa qual ocorrência estava sendo processada agora — a
 * segunda (ou terceira) ocorrência lia o cwd da primeira (auditor, 14ª
 * revisão). Conserto: `ordem` é a contagem de quantas vezes ESSE MESMO
 * texto já apareceu antes na sequência de segmentos processados (mantida
 * pelos chamadores — o laço de `main()` e a recursão de `processarSegmento`,
 * via `contadores`) — devolve a `ordem`-ésima entrada de `mapaCwd` com esse
 * texto. Sem essa ocorrência (índice não existe, ou `mapaCwd` tem menos
 * ocorrências do que o esperado — por exemplo por causa de um subshell que
 * dessincroniza a contagem), devolve `null` (conservador, mesma postura de
 * antes).
 */
function cwdDoSegmento(segmento, mapaCwd, ordem) {
  if (!mapaCwd) return null;
  const alvo = segmento.trim();
  let contagem = 0;
  for (const entrada of mapaCwd) {
    if (entrada.seg.trim() !== alvo) continue;
    if (contagem === ordem) {
      return entrada.incerto ? null : entrada.cwd;
    }
    contagem += 1;
  }
  return null;
}

/**
 * Aplica as checagens D15/D16 a UM segmento do comando (já separado por
 * `;`, `&&`, `||`, `|`, `(`, `)`, `{`, `}` via `segmentosParaGate`).
 *
 * `mapaCwd` é a saída de `cwdPorSegmento(comando, cwdDoEvento)` sobre a
 * linha inteira (calculada uma vez em `main()`) — usada só para resolver
 * `--body-file` com caminho relativo contra o cwd de ONDE O `gh` RODA de
 * verdade, via `cwdDoSegmento`.
 *
 * `contadores` (Map texto → nº de vezes já visto) é compartilhado por toda
 * a árvore de chamadas — o laço de `main()` e cada recursão aqui embaixo —
 * para que `cwdDoSegmento` saiba qual OCORRÊNCIA deste texto está sendo
 * processada agora (ver docblock de `cwdDoSegmento`).
 *
 * Ordem:
 *   1. `gh` como comando efetivo — direto ou atrás de um prefixo que só
 *      repassa (`env`, `nohup`, `timeout <dur>`, `xargs`, `X=1`, ...), via
 *      `tokensComAspas`/`posicaoDeComando` (P2, compartilhado com os outros
 *      dois gates).
 *   2. Wrapper que encapsula uma string (`eval`, `bash -c`, `pwsh -Command`
 *      abreviado, `cmd /c`/`/k`) — recursiona no conteúdo interno, que pode
 *      ele mesmo ter vários segmentos encadeados.
 *   3. Wrapper DESCONHECIDO (nem `gh`, nem prefixo, nem wrapper dos itens
 *      1/2): rede de segurança final — se a sequência não citada
 *      `gh issue close`/`gh pr create`/`gh pr merge` aparece em qualquer
 *      posição do segmento, trata como comando mesmo assim.
 */
function processarSegmento(segmento, mapaCwd, contadores) {
  // Ordem desta ocorrência do texto do segmento (0 = primeira vez que este
  // texto exato é processado, 1 = segunda, ...). Contada ANTES de qualquer
  // recursão/retorno abaixo — um único `processarSegmento(segmento, ...)`
  // corresponde a uma única ocorrência na sequência, não importa qual dos
  // dois pontos abaixo acaba chamando `cwdDoSegmento`.
  const alvo = segmento.trim();
  const ordem = contadores.get(alvo) || 0;
  contadores.set(alvo, ordem + 1);

  const toksComAspas = tokensComAspas(segmento);
  if (toksComAspas.length === 0) return;

  const pos = posicaoDeComando(toksComAspas);
  if (pos !== null && normalizarExecutavel(toksComAspas[pos].v) === "gh") {
    verificarComandoGh(
      segmento,
      toksComAspas.slice(pos + 1).map((t) => t.v),
      cwdDoSegmento(segmento, mapaCwd, ordem)
    );
    return;
  }

  // `desempacotarWrapperDeString` (lib/tokens-comando.cjs, movida aqui na
  // rodada 11): `ilegivel` cobre TANTO o conteudo com `$(`/crase/variavel
  // QUANTO `-EncodedCommand` (que nunca tem `interno` — so `ilegivel`
  // importa nesse caso), por isso a checagem de `ilegivel` vem ANTES da
  // checagem de `interno !== null`.
  //
  // P3 (auditor, 11a revisao, rodada 13, lote 3, 2026-09-04): desempacotava
  // sobre `segmento` CRU (posicao 0), nunca a partir da POSICAO DE COMANDO
  // ja calculada acima — `timeout 5 bash -c "gh issue close 12"` atravessava
  // com exit 0 porque `timeout` (wrapper de PREFIXO) nao e reconhecido pelo
  // desempacotador de STRING. Usa `textoAPartir(toksComAspas, pos)` quando
  // `pos` existe (o texto dali pra frente, sem o prefixo ja consumido);
  // sem posicao de comando (`pos === null`), nao ha o que desempacotar.
  const { interno, ilegivel } = pos === null
    ? { interno: null, ilegivel: false }
    : desempacotarWrapperDeString(textoAPartir(toksComAspas, pos));
  if (ilegivel) {
    bloqueia(
      `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
      `Razão: comando encapsulado (eval/bash -c/sh -c/pwsh -Command/cmd /c/-EncodedCommand) contém ` +
      `variável, substituição de comando, ou está em base64; não consigo ler o que roda dentro com ` +
      `segurança (ilegível).\n\n` +
      `Rode o comando 'gh' diretamente, sem encapsular, ou expanda a variável antes de chamar.\n`
    );
  }
  if (interno !== null) {
    for (const sub of segmentosParaGate(interno)) {
      processarSegmento(sub, mapaCwd, contadores);
    }
    return;
  }

  // W2 (rodada 14, lote 3, 2026-09-04): esta rede de seguranca (para
  // wrapper DESCONHECIDO) procurava a sequencia `gh issue close`/`gh pr
  // create|merge` em QUALQUER posicao do segmento — inclusive dentro de um
  // COMENTARIO shell (token nao citado que comeca com "#": tudo dali ate o
  // fim do segmento e texto morto, o shell nunca roda).
  // `# gh issue close 12 is handled by fechar-issue.cjs now` virava
  // super-bloqueio (exit 2) de um comando que nem chega a existir. Conserto:
  // tokens a partir do primeiro "#" NAO CITADO saem da busca — `"closes #7"`
  // citado (marcador de evidencia) continua intacto, porque o token inteiro
  // tem `.q === true`.
  const idxComentario = toksComAspas.findIndex((t) => !t.q && t.v.startsWith("#"));
  const toksSemComentario = idxComentario === -1 ? toksComAspas : toksComAspas.slice(0, idxComentario);
  const valores = toksSemComentario.map((t) => t.v);
  const primeiro = valores.length ? normalizarExecutavel(valores[0]) : null;
  if (primeiro !== null && !ehPrefixoOuWrapperConhecido(primeiro)) {
    for (const padrao of [["gh", "issue", "close"], ["gh", "pr", "create"], ["gh", "pr", "merge"]]) {
      const idx = indiceSequencia(valores, padrao);
      if (idx !== -1) {
        verificarComandoGh(segmento, valores.slice(idx + 1), cwdDoSegmento(segmento, mapaCwd, ordem));
        return;
      }
    }
  }
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
  } catch {
    process.exit(0);
  }

  // Verificar saídas de emergência
  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  const cwdDoEvento = ev.cwd || process.cwd();
  const gitTop = git(cwdDoEvento, ["rev-parse", "--show-toplevel"]);
  if (gitTop && fs.existsSync(path.join(gitTop, ".rainforest-gate-off"))) {
    process.exit(0);
  }

  // Toggle do setup
  try {
    if (!require("./lib/config.cjs").ligado("gate-fechar-issue", { projeto: cwdDoEvento })) {
      process.exit(0);
    }
  } catch {}

  // Só age em Bash/PowerShell
  const nome = ev.tool_name;
  if (nome !== "Bash" && nome !== "PowerShell") process.exit(0);

  const comando = (ev.tool_input && ev.tool_input.command) || "";
  if (!comando) process.exit(0);

  // Rodada 15, lote 3, 2026-09-04: cwd de CADA segmento da linha, calculado
  // uma vez sobre a linha inteira (mesma função que `gate-worktree.cjs` e
  // `gate-staging-total.cjs` usam) — resolve `--body-file` relativo contra
  // onde o `gh` roda de verdade, não contra o cwd do processo do hook. Ver
  // docblock de `cwdDoSegmento`.
  const mapaCwd = cwdPorSegmento(comando, cwdDoEvento);

  // Rodada 16, lote 3, 2026-09-04: contador por texto de segmento,
  // compartilhado com toda a recursão de `processarSegmento` — resolve a
  // K-ÉSIMA ocorrência de um texto repetido, não sempre a primeira. Ver
  // docblock de `cwdDoSegmento`.
  const contadores = new Map();
  for (const segmento of segmentosParaGate(comando)) {
    processarSegmento(segmento, mapaCwd, contadores);
  }

  process.exit(0);
}

if (require.main === module) main();
