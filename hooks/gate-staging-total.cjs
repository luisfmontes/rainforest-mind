#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse — barra staging em massa (`git add -A`, `git commit -am`) em
 * working tree compartilhado por varias sessoes.
 * Protege contra: git add -A / git add . / git commit -a (staging em massa)
 * Não protege contra: git add por caminho específico
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
const {
  tokensComAspas, ehComando, posicaoDeComando, textoAPartir, desempacotarWrapperDeString,
} = require("./lib/tokens-comando.cjs");
const {
  corpoDeHeredoc, linhaDoHeredocTemInterpretador, fimDaLinhaLogica, normalizarExecutavel,
} = require("./lib/heredoc.cjs");

// Flags globais do git que consomem o token seguinte (`git -C <dir> add`).
const FLAG_COM_VALOR = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix",
]);
// Pathspecs que significam "o repo inteiro".
const CAMINHO_TOTAL = new Set([".", "./", ":/", "*", "-A", "--all", "-u", "--update"]);
const PATHSPEC_TOTAL = new Set([".", "./", ":/", "*"]);

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
 * A partir da posicao de comando, o restante do segmento preserva todos os
 * tokens: aspas mudam agrupamento, nao a semantica de `git add "-A"`. Valores
 * de opcoes que nao podem virar flags sao tratados em `motivoDe`.
 */
function analisaGit(toksComAspas) {
  const pos = posicaoDeComando(toksComAspas);
  // `true`: `pos` VEM de `posicaoDeComando`, entao `"git" add -A` conta
  // (rodada 20, lote 3, achado do auditor na 18a revisao).
  if (pos === null || !ehComando(toksComAspas[pos], "git", true)) return null;
  const resto = toksComAspas.slice(pos + 1).map((t) => t.v);

  let i = 0;
  let dirC = null;
  while (i < resto.length && resto[i].startsWith("-")) {
    if (resto[i] === "-C" && resto[i + 1]) dirC = resto[i + 1];
    i += FLAG_COM_VALOR.has(resto[i]) && !resto[i].includes("=") ? 2 : 1;
  }
  if (i >= resto.length) return null;
  return { sub: resto[i], args: resto.slice(i + 1), dirC };
}

/**
 * `analisaGit` mais o desempacotamento de wrapper de STRING (T2, rodada 11,
 * lote 3, 2026-09-04): `Invoke-Expression "git add -A"`/`iex "..."`,
 * `eval "..."`, `bash -c "..."`/primos, `pwsh -Command "..."`, `cmd /c "..."`
 * escondem o `git` de verdade DENTRO de uma string, que `analisaGit` sozinho
 * nao ve (opera em TOKENS do segmento, e o comando de verdade e so um token
 * citado). Reprocessa recursivamente (o conteudo desempacotado pode ele
 * mesmo ter varios segmentos encadeados, e pode ele mesmo ser outro
 * wrapper).
 *
 * Conteudo ILEGIVEL (`$(`, crase, variavel) devolve `{ incerto: true }` —
 * nao da pra saber se esconde `git add -A`/`commit -a`; mesma postura
 * conservadora que `cwdPorSegmento` ja usa para `cd` que nao resolve.
 * `null` quando o segmento nao e git nem wrapper nenhum.
 *
 * P3 (auditor, 11a revisao, rodada 13, lote 3, 2026-09-04): o desempacotamento
 * rodava sobre `segTexto` CRU (posicao 0), nunca a partir da POSICAO DE
 * COMANDO — `timeout 5 bash -c "git add -A"`/`env -C . bash -c "git add -A"`
 * atravessavam com exit 0, porque `desempacotarWrapperDeString("timeout 5
 * bash -c ...")` nao reconhece `timeout` como wrapper de string (ele e
 * wrapper de PREFIXO, tratado por `posicaoDeComando`). Agora calcula a
 * posicao de comando primeiro e desempacota a partir dela — `textoAPartir`
 * reconstroi so o texto dali pra frente, sem o prefixo que ja foi
 * consumido — para o desempacotador enxergar `bash -c "..."` como tal.
 */

/**
 * Onde comeca cada `<<` que e mesmo OPERADOR de heredoc.
 *
 * `indexOf('<<')` nao serve: ele acha `<<` dentro de aspas e dentro de
 * comentario. Foi assim que a primeira versao desta mascara abriu o gate --
 * `echo "a << b"` numa linha fazia o corpo do 'heredoc' comecar na linha
 * seguinte e ir ate o fim do comando, apagando o `git add -A` que vinha
 * depois (auditoria de seguranca do zerar-issues-4, A01).
 *
 * Varre uma vez rastreando aspas simples (onde nada escapa), aspas duplas
 * (onde a contrabarra escapa), contrabarra solta e comentario `#` em inicio
 * de palavra. `<<<` e here-string, nao heredoc: e pulado.
 */
function posicoesDeOperadorHeredoc(cmd) {
  const achados = [];
  let simples = false;
  let duplas = false;
  for (let k = 0; k < cmd.length; k++) {
    const c = cmd[k];
    if (!simples && c === "\\") { k++; continue; }
    if (!duplas && c === "'") { simples = !simples; continue; }
    if (!simples && c === '"') { duplas = !duplas; continue; }
    if (simples || duplas) continue;
    if (c === "#") {
      const antes = k === 0 ? "" : cmd[k - 1];
      if (k === 0 || " \t\n;|&(".includes(antes)) {
        const quebra = cmd.indexOf("\n", k);
        if (quebra === -1) break;
        k = quebra;
        continue;
      }
    }
    if (c === "<" && cmd[k + 1] === "<") {
      if (cmd[k + 2] === "<") { k += 2; continue; }
      achados.push(k);
      k++;
    }
  }
  return achados;
}

// Comandos que EXECUTAM um arquivo passado como argumento. Superconjunto de
// INTERPRETADORES_DE_HEREDOC de proposito: aqui o custo de errar para o lado de
// bloquear e baixo, e o corpo pode ser script de qualquer linguagem.
const EXECUTAM_ARQUIVO = new Set([
  "bash", "sh", "zsh", "ksh", "dash", "pwsh", "powershell", "cmd", "eval",
  "source", ".", "node", "python", "python3", "py", "perl", "ruby", "deno", "bun",
]);

/**
 * O heredoc que abre em `i` e gravado num arquivo que o proprio comando executa
 * depois? Nesse caso o corpo e script, nao dado, e nao pode ser mascarado.
 *
 * Duas sutilezas medidas na auditoria do zerar-issues-4 (2026-09-15):
 *
 * 1. O redirecionamento pode vir ANTES do `<<` (`cat > x.sh <<'EOF'`). A
 *    primeira versao lia a linha a partir do `<<` e nao o via — `cat > x.sh`
 *    + `bash x.sh` atravessava o gate, com staging em massa no corpo. Agora a
 *    linha logica inteira e varrida, e todos os alvos de redirecionamento dela.
 *
 * 2. "Aparece depois" nao basta. `cat > /tmp/x.md <<'EOF'` seguido de
 *    `gh issue create --body-file /tmp/x.md` cita o arquivo sem executa-lo — e
 *    e exatamente o caso da Issue #258, que tem de continuar passando. So conta
 *    como execucao o arquivo citado como `./x` ou como argumento de um comando
 *    que executa arquivo (`bash x`, `sh -x x`, `source x`, `node x`).
 */
function alvoDoRedirecionamentoEhExecutadoDepois(cmd, i, fimDoHeredoc) {
  let ini = i;
  while (ini > 0 && cmd[ini - 1] !== "\n") ini--;
  let fimLinha = fimDaLinhaLogica(cmd, i);
  if (fimLinha === -1) fimLinha = cmd.length;
  const linha = cmd.slice(ini, fimLinha);

  const alvos = new Set();
  const re = /(?:^|[\s;|&])\d?>>?\s*([^\s;|&<>]+)/g;
  let m;
  while ((m = re.exec(linha)) !== null) {
    const alvo = m[1].replace(/^["']+|["']+$/g, "");
    if (!alvo) continue;
    const base = alvo.split(/[\\/]/).pop();
    if (base) alvos.add(base);
  }
  if (alvos.size === 0) return false;

  const depois = cmd.slice(Math.min(fimDoHeredoc, cmd.length));
  let toks;
  try { toks = tokensComAspas(depois).map((t) => String(t.v)); } catch { toks = depois.split(/\s+/); }

  for (let k = 0; k < toks.length; k++) {
    const t = toks[k];
    const nu = t.replace(/^["']+|["']+$/g, "");
    const base = nu.split(/[\\/]/).pop();
    if (!base || !alvos.has(base)) continue;
    // Citado com caminho explicito de execucao: `./x.sh`, `.\x.sh`.
    if (/^\.[\\/]/.test(nu)) return true;
    // Argumento de um comando que executa arquivo, pulando flags.
    for (let j = k - 1; j >= 0; j--) {
      const anterior = String(toks[j]);
      if (/^[|;&(){}]+$/.test(anterior)) break;
      if (anterior.startsWith("-")) continue;
      const alvoTok = anterior.split(/[|;&(){}]+/).filter(Boolean).pop();
      if (alvoTok && EXECUTAM_ARQUIVO.has(normalizarExecutavel(alvoTok))) return true;
      break;
    }
  }
  return false;
}

/**
 * D1 (zerar-issues-4, #258): troca o CORPO de um heredoc por espacos,
 * preservando o comprimento da string, quando aquele corpo e mesmo DADO.
 *
 * Por que MASCARAR e nao recortar. O indice do segmento onde o `git
 * add`/`commit` casou e usado para consultar `cwdPorSegmento` (H1, rodada 5,
 * lote 3). As duas travessias tem de ver a MESMA string: recortar o corpo
 * mudaria os deslocamentos e o indice passaria a apontar para outro segmento.
 * Espaco no lugar de cada caractere mantem todo deslocamento. O `\n` e
 * preservado porque e separador de comando.
 *
 * Por que isto conserta a #258. O gatilho nao era o heredoc nem a citacao de
 * comando git: era o `.` que abre frase depois de `)` -- `(folga de 2 B). Ele
 * sobe.` --, que `posicaoDeComando` le como o builtin `source`, fazendo o gate
 * bloquear por "comando dinamico".
 *
 * QUATRO condicoes, todas obrigatorias. A primeira versao exigia so a quarta
 * e abriu sete formas de atravessar o gate (auditoria do zerar-issues-4).
 * Cada condicao existe por um caso medido:
 *
 * 1. O `<<` e operador, nao texto -- `posicoesDeOperadorHeredoc`. Sem isto,
 *    `echo "a << b"` numa linha apaga o `git add -A` da linha seguinte.
 * 2. O delimitador esta entre aspas (`<<'EOF'` ou `<<"EOF"`). Corpo de
 *    heredoc NAO citado expande `$(...)` e crase: `cat <<EOF` com
 *    `$(git add -A)` no corpo EXECUTA o staging. Corpo que expande nao e dado.
 *    E o caso citado que a #258 relata e a propria Issue sugere isentar.
 * 3. O delimitador fecha em linha propria. Sem fechamento, `corpoDeHeredoc`
 *    devolve `fim = cmd.length` e a mascara engole o resto do comando --
 *    inclusive uma linha de fechamento FALSA plantada no fim.
 * 4. O comando receptor nao e interpretador (`bash <<'EOF'`), e o alvo do
 *    redirecionamento nao e executado adiante: nos dois casos o corpo e
 *    comando de verdade.
 *
 * Fora dessas quatro, o corpo segue para a analise como sempre seguiu -- o
 * lado de bloquear. Falha fechada e o unico default aceitavel aqui: este gate
 * existe por um `git add -A` que varreu o trabalho de outra sessao.
 */
function mascararCorposDeHeredoc(cmd) {
  let fora = cmd;
  let de = 0;
  for (let guarda = 0; guarda < 200; guarda++) {
    const i = posicoesDeOperadorHeredoc(fora).find((p) => p >= de);
    if (i === undefined) break;
    const heredoc = corpoDeHeredoc(fora, i);
    if (heredoc === null) { de = i + 2; continue; }
    const fimDoHeredoc = Math.min(heredoc.fim, fora.length);
    const dado =
      heredoc.delimitadorQuotado &&
      heredoc.fechado &&
      !linhaDoHeredocTemInterpretador(fora, i) &&
      !alvoDoRedirecionamentoEhExecutadoDepois(fora, i, fimDoHeredoc);
    if (dado) {
      const quebra = fora.indexOf("\n", i);
      const inicio = quebra === -1 ? fora.length : quebra + 1;
      if (fimDoHeredoc > inicio) {
        const emBranco = fora.slice(inicio, fimDoHeredoc).replace(/[^\n]/g, " ");
        fora = fora.slice(0, inicio) + emBranco + fora.slice(fimDoHeredoc);
      }
    }
    de = Math.max(fimDoHeredoc, i + 2);
  }
  return fora;
}

function analisaSegmentoGit(segTexto, ferramenta) {
  const g = analisaGit(tokensComAspas(segTexto));
  if (g) return g;
  const toks = tokensComAspas(segTexto);
  const pos = posicaoDeComando(toks);
  if (pos === null) return null;
  const { interno, ilegivel } = desempacotarWrapperDeString(textoAPartir(toks, pos), { ferramenta });
  if (ilegivel) return { incerto: true };
  if (interno !== null) {
    for (const sub of segmentosComAspas(interno)) {
      const r = analisaSegmentoGit(sub, ferramenta);
      if (r && (r.incerto || motivoDe(r))) return r;
    }
  }
  return null;
}

/** `-am` contem a curta `a`; `--amend` nao e curta e nao conta. */
function temCurta(args, letra) {
  return args.some((t) => /^-[A-Za-z]+$/.test(t) && t.slice(1).includes(letra));
}

/** Valores de -m/--message não são opções de staging, mesmo quando começam com `-`. */
function opcoesSemValoresDeMensagem(args) {
  const opcoes = [];
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === "--") break;
    if (arg === "-m" || arg === "--message") {
      if (i + 1 < args.length) i += 1;
      continue;
    }
    if (/^-m(?:.|$)/.test(arg) || arg.startsWith("--message=")) continue;
    opcoes.push(arg);
  }
  return opcoes;
}

/** Motivo do bloqueio, ou null se o segmento e inofensivo. */
function motivoDe(g) {
  if (g.sub === "add") {
    const delimitador = g.args.indexOf("--");
    const opcoes = delimitador === -1 ? g.args : g.args.slice(0, delimitador);
    const pathspecs = delimitador === -1 ? [] : g.args.slice(delimitador + 1);
    const total = opcoes.find((a) => CAMINHO_TOTAL.has(a)) ||
      pathspecs.find((a) => PATHSPEC_TOTAL.has(a));
    if (total) return `git add ${total}`;
    if (temCurta(opcoes, "A")) return "git add -A (em flag combinada)";
    if (temCurta(opcoes, "u")) return "git add -u (em flag combinada)";
    return null;
  }
  if (g.sub === "commit") {
    const opcoes = opcoesSemValoresDeMensagem(g.args);
    if (opcoes.includes("--all")) return "git commit --all";
    if (temCurta(opcoes, "a")) return "git commit -a";
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
  // R3 (rodada 9, lote 3, 2026-09-04): nesta maquina a ferramenta primaria e
  // `PowerShell`, nao `Bash` — `Set-Location <principal>; git add -A` pela
  // ferramenta `PowerShell` passava batido. O mesmo parser de segmentos/`git
  // -C`/movedores (cwd-efetivo.cjs) ja sabe ler texto PowerShell (R3 la).
  if (ev.tool_name !== "Bash" && ev.tool_name !== "PowerShell") process.exit(0);
  const cmd = (ev.tool_input || {}).command;
  if (typeof cmd !== "string") process.exit(0);

  let motivo = null;
  let dirC = null;
  let indiceSegmento = null;
  // D1 (zerar-issues-4): remover corpos de heredoc nao-interpretador ANTES de segmentar
  const cmdParaAnalise = mascararCorposDeHeredoc(cmd);
  const segs = segmentos(cmdParaAnalise);
  for (let idx = 0; idx < segs.length; idx += 1) {
    const g = analisaSegmentoGit(segs[idx], ev.tool_name);
    if (!g) continue;
    if (g.incerto) {
      motivo = "comando dinamico (eval/bash -c/Invoke-Expression/iex/pwsh -Command/cmd /c) com " +
        "conteudo nao resolvivel — pode esconder git add -A/commit -a";
      dirC = null;
      indiceSegmento = idx;
      break;
    }
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
  const porSegmento = cwdPorSegmento(cmdParaAnalise, cwdDoEvento);
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
