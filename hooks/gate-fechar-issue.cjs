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
const { tokensComAspas, posicaoDeComando, WRAPPERS_QUE_REPASSAM } = require("./lib/tokens-comando.cjs");

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
 */
function extrairCorpoDoPR(segmento) {
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
      try {
        const conteudo = fs.readFileSync(arquivo, "utf8");
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

// Executáveis que encapsulam uma string de comando, e a flag que a introduz.
// Chave normalizada por `normalizarExecutavel` (sem caminho/extensão/aspas).
// `pwsh`/`powershell` e `cmd` são tratados à parte em `desempacotarWrapper`
// porque aceitam abreviação de flag (`-c`, `-co`, `-com`, ... / `/c`, `/k`).
const WRAPPERS_DE_COMANDO = {
  bash: "-c",
  sh: "-c",
  zsh: "-c",
  ksh: "-c",
  dash: "-c",
};

/**
 * Extrai o primeiro token de `str` (aspas simples/duplas respeitadas) e o
 * restante da string logo após esse token (sem consumir as aspas do restante).
 * Retorna null se `str` não tem nenhum token.
 */
function extrairPrimeiroToken(str) {
  const m = /^\s*(?:"([^"]*)"|'([^']*)'|(\S+))/.exec(str);
  if (!m) return null;
  const tok = m[1] !== undefined ? m[1] : m[2] !== undefined ? m[2] : m[3];
  return { tok, resto: str.slice(m[0].length) };
}

/**
 * `tok` é uma abreviação válida de `nomeCompleto` (ex.: "-c", "-co", "-com"
 * para "-command")? O PowerShell aceita qualquer prefixo não-ambíguo de uma
 * flag; aqui a checagem é conservadora — basta ser prefixo de `nomeCompleto`
 * com pelo menos 2 caracteres (o `-` e uma letra), case-insensitive.
 */
function casaPrefixoDeFlag(tok, nomeCompleto) {
  const t = String(tok || "").toLowerCase();
  return t.length >= 2 && t[0] === "-" && nomeCompleto.toLowerCase().startsWith(t);
}

function desempacota(interno) {
  interno = interno.trim();
  const aspas = /^"([\s\S]*)"$/.exec(interno) || /^'([\s\S]*)'$/.exec(interno);
  return aspas ? aspas[1] : interno;
}

/**
 * Se `segmento` é uma invocação de `eval`, `bash -c`/`sh -c`/`zsh -c`/
 * `ksh -c`/`dash -c`, `pwsh`/`powershell` com qualquer abreviação de
 * `-Command` (`-c`, `-co`, `-com`, ...), ou `cmd /c`/`cmd /k` (executável
 * reconhecido + flag certa), devolve a string de comando encapsulada (sem
 * UM nível de aspas externas, se houver). Devolve null se `segmento` não é
 * um desses wrappers.
 *
 * `pwsh`/`powershell -EncodedCommand` (ou qualquer abreviação dela — `-e`,
 * `-ec`, `-enc`, ...) chega em base64: ilegível por definição, bloqueia
 * direto aqui, sem tentar decodificar.
 */
function desempacotarWrapper(segmento) {
  const p1 = extrairPrimeiroToken(segmento);
  if (!p1) return null;
  const exe = normalizarExecutavel(p1.tok);

  if (exe === "eval") {
    return desempacota(p1.resto);
  }

  const p2 = extrairPrimeiroToken(p1.resto);
  if (!p2) return null;

  if (exe === "pwsh" || exe === "powershell") {
    if (casaPrefixoDeFlag(p2.tok, "-encodedcommand")) {
      bloqueia(
        `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
        `Razão: '-EncodedCommand' codifica o comando em base64; não consigo ler o que roda ` +
        `dentro com segurança (ilegível).\n\n` +
        `Rode o comando 'gh' diretamente, sem -EncodedCommand.\n`
      );
    }
    if (!casaPrefixoDeFlag(p2.tok, "-command")) return null;
    return desempacota(p2.resto);
  }

  if (exe === "cmd") {
    const flag = p2.tok.toLowerCase();
    if (flag !== "/c" && flag !== "/k") return null;
    return desempacota(p2.resto);
  }

  const flagEsperada = WRAPPERS_DE_COMANDO[exe];
  if (!flagEsperada) return null;
  if (p2.tok.toLowerCase() !== flagEsperada) return null;
  return desempacota(p2.resto);
}

/**
 * A string interna de um wrapper é ilegível quando contém substituição de
 * comando (`$(...)`, crase) ou variável (`$X`, `${X}`) — não dá para saber
 * com segurança o que vai rodar. Mesma postura conservadora do corpo de PR.
 */
function contemConstrucaoIlegivel(str) {
  return /\$\(|`|\$[A-Za-z_{]/.test(str);
}

/**
 * Aplica as checagens D15/D16 a uma invocação de `gh` já identificada:
 * `segmento` é o texto bruto (para extrair `--body`/`--body-file`) e
 * `subcomandos` são os tokens que vêm depois de `gh`.
 */
function verificarComandoGh(segmento, subcomandos) {
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
    const corpoDoPR = extrairCorpoDoPR(segmento);

    // Corpo ilegível (não consegue ler com segurança)
    if (!corpoDoPR.legivel) {
      if (corpoDoPR.tipo === "arquivo") {
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
    exe === "pwsh" ||
    exe === "powershell" ||
    exe === "cmd" ||
    WRAPPERS_QUE_REPASSAM.has(exe) ||
    !!WRAPPERS_DE_COMANDO[exe]
  );
}

/**
 * Aplica as checagens D15/D16 a UM segmento do comando (já separado por
 * `;`, `&&`, `||`, `|`, `(`, `)`, `{`, `}` via `segmentosParaGate`).
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
function processarSegmento(segmento) {
  const toksComAspas = tokensComAspas(segmento);
  if (toksComAspas.length === 0) return;

  const pos = posicaoDeComando(toksComAspas);
  if (pos !== null && normalizarExecutavel(toksComAspas[pos].v) === "gh") {
    verificarComandoGh(segmento, toksComAspas.slice(pos + 1).map((t) => t.v));
    return;
  }

  const interno = desempacotarWrapper(segmento);
  if (interno !== null) {
    if (contemConstrucaoIlegivel(interno)) {
      bloqueia(
        `BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\n` +
        `Razão: comando encapsulado (eval/bash -c/sh -c/pwsh -Command/cmd /c) contém variável ou ` +
        `substituição de comando; não consigo ler o que roda dentro com segurança (ilegível).\n\n` +
        `Rode o comando 'gh' diretamente, sem encapsular, ou expanda a variável antes de chamar.\n`
      );
    }
    for (const sub of segmentosParaGate(interno)) {
      processarSegmento(sub);
    }
    return;
  }

  const valores = toksComAspas.map((t) => t.v);
  const primeiro = valores.length ? normalizarExecutavel(valores[0]) : null;
  if (primeiro !== null && !ehPrefixoOuWrapperConhecido(primeiro)) {
    for (const padrao of [["gh", "issue", "close"], ["gh", "pr", "create"], ["gh", "pr", "merge"]]) {
      const idx = indiceSequencia(valores, padrao);
      if (idx !== -1) {
        verificarComandoGh(segmento, valores.slice(idx + 1));
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

  for (const segmento of segmentosParaGate(comando)) {
    processarSegmento(segmento);
  }

  process.exit(0);
}

if (require.main === module) main();
