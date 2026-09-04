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
 * O QUE ESTE GATE E, E O QUE NAO E — declarado aqui depois de tres rodadas de
 * ataque, porque ficar implicito ja causou confianca em cobertura que o gate
 * nao tem:
 *
 * Isto e um QUEBRA-MOLAS contra o atalho, nao uma FRONTEIRA contra evasao
 * deliberada. Ele existe porque quem executa um fluxo chega em `--no-verify`
 * por CONVENIENCIA no momento em que o hook de commit reprova — nao porque
 * alguem vai ofuscar o comando de proposito para escapar de uma trava que
 * nem sabe que existe. O gate reduz o atalho automatico; ele nao foi
 * desenhado, e nao seria vencedor, contra quem monta o comando de proposito
 * para passar por baixo dele.
 *
 * Prova disso: um PARSER DE SHELL ESCRITO A MAO NUNCA GANHA a corrida contra
 * ofuscacao. Isto e fato medido neste arquivo, nao suposicao — tres rodadas
 * de ataque, forma nova a cada uma:
 *   - rodada 1, 2026-09-04 (security review de fundo, commit 7d0fb268): flag
 *     citada de tres formas (aspas simples, duplas, coladas: `--no-"verify"`),
 *     abreviacao de long option que o git aceita (`--no-veri`), separador `&`
 *     solto, prefixo nao reconhecido antes do `git` (`then`), substituicao de
 *     comando `$(...)`, linha continuada com `\` + quebra de linha;
 *   - rodada 2, 2026-09-04 (commit fb713c3): `bash -c "..."`, `sh -c '...'`,
 *     subshell `(...)`, flag combinada (`bash -lc`) e aninhamento simples;
 *   - rodada 3, 2026-09-04: nome de shell com caminho na frente (`/bin/bash`,
 *     `/bin/bash.exe`), `eval`, escape por barra invertida (`--no\-verify`)
 *     e aspa dupla escapada dentro de shell aninhado;
 *   - rodada 4, 2026-09-04 (revisor independente, esta rodada): variacao de
 *     CAIXA no nome do executavel (`GIT`, `Git`, `gIt`, `BASH`, `Bash`) —
 *     em sistema de arquivos case-insensitive (NTFS/Windows, o padrao do
 *     Git Bash) o SO resolve `GIT` para o mesmo binario de `git`, e so a
 *     tecla Shift bastava para contornar o gate.
 * Quatro rodadas, forma nova a cada uma. Nao ha razao para crer que uma
 * quinta rodada nao acharia uma sexta forma — e e por isso que este bloco
 * declara o limite em vez de prometer cobertura completa.
 *
 * O QUE SABIDAMENTE ESCAPA E NAO SERA PERSEGUIDO (a lista e o valor deste
 * bloco — ser honesto sobre o buraco, nao ser curto):
 *   - indirecao por variavel (`F=--no-verify; git commit $F`) — nao-objetivo
 *     declarado no plano `2026-09-04-nao-mente.md`. O valor de `$F` so existe
 *     depois da expansao do shell, que acontece DEPOIS deste gate ler
 *     `tool_input.command`. Nao ha como cobrir isso lendo o texto do
 *     comando: o gate cobre o que esta ESCRITO nele, nada alem disso;
 *   - qualquer forma de ofuscacao que dependa do SHELL DE VERDADE interpretar
 *     o comando de um jeito que este parser escrito a mao (que nao e um
 *     shell) nao replica com exatidao — `$'...'` com escape ANSI-C, alias,
 *     funcao de shell, `IFS` alterado, encoding, e formas ainda nao medidas.
 *     Este gate cobre os padroes das tres rodadas acima, nao todo padrao
 *     hipotetico.
 *
 * ONDE MORA O ENFORCEMENT DE VERDADE, para quem precisar de garantia e nao so
 * de fricção: `pre-receive` no servidor git, ou uma checagem de CI que roda a
 * mesma verificacao e reprova o PR. Nenhum dos dois e alcancado por
 * `--no-verify` por construcao — a flag so desliga hook LOCAL. Este arquivo
 * aqui e o quebra-molas na hora do commit; a garantia final mora nos dois
 * acima, e dizer isso aqui evita que alguem confie demais neste gate.
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
 * jeito que o shell faz (`--no-"verify"` -> `--no-verify`). Fora de aspas
 * simples, barra invertida de escape some e o char seguinte vira literal
 * (`--no\-verify` -> `--no-verify`); dentro de aspas duplas so `\"`, `\\`,
 * `\$` e `` \` `` sao escapes de verdade, e o fechamento da aspa ignora um
 * `\"` escapado (senao um `bash -c "...\"..."` aninhado fecha a aspa cedo
 * demais e quebra a extracao do comando interno).
 * `git -c commit.gpgsign=false commit -m x` tem que continuar identificando
 * `commit` como subcomando (nao a chave `commit.gpgsign=false`) — a mesma
 * varredura de flags-com-valor do `gate-staging-total` resolve isso.
 *
 * Prefixo de opcao longa (o git aceita: `--no-veri` resolve para `--no-verify`
 * se for prefixo unico) conta como a flag inteira — comparado por prefixo
 * contra `--no-verify` e `--no-gpg-sign`, nao por igualdade.
 *
 * Encadeamento (`;`, `|`, `||`, `&&`, `&`, quebra de linha, `(`, `)`) segmenta
 * o comando, e cada segmento e varrido procurando o token `git` em QUALQUER
 * posicao (nao so no inicio) — lista de prefixos aceitos antes do `git`
 * sempre esquece um caso (`then`, `do`, `else`, `{`...). Substituicao de
 * comando `$(...)` e crase tem o delimitador removido e o conteudo interno
 * vira mais um segmento. Linha continuada com `\` + quebra de linha e
 * costurada de volta antes de segmentar, senao a flag fica orfa de comando
 * no segmento seguinte. Parenteses de subshell (`(git commit --no-verify)`)
 * viram separador tambem — tratados DEPOIS da extracao de `$(...)`, entao
 * essa substituicao (que ja funciona) continua intacta.
 *
 * SHELL AGRUPADO (`bash -c "<cmd>"`, `sh -c '<cmd>'`, com ou sem flags
 * combinadas antes do -c: `bash -lc`, `sh -ec`, `bash -o pipefail -c`).
 * Para `git commit -m`, o conteudo citado e TEXTO (mensagem) e nunca vira
 * comando — e assim que a tarefa anterior fechou o falso positivo de
 * `git commit -m "removi o --no-verify do script"`. Mas para `bash -c`/
 * `sh -c`/`zsh -c`/`dash -c`/`ash -c` (e `busybox sh -c`) — com ou sem
 * caminho e `.exe` na frente do nome (`/bin/bash`, `bash.exe`, achado
 * atacando a terceira rodada) —, o argumento seguinte ao `-c` e uma LINHA DE
 * COMANDO, nao mensagem, e e analisado RECURSIVAMENTE, como se fosse um
 * segmento novo (segmentar, tokenizar, analisaGit, motivoDe de novo). `eval
 * "<comando>"` (achado atacando a terceira rodada tambem) entra na mesma
 * recursao: o argumento de `eval` e uma linha de comando igual a de
 * `bash -c`, so que sem exigir `-c` na frente. A distincao entre linha de
 * comando e mensagem e o proprio token anterior: `-m`/`--message` de `git
 * commit` nunca dispara recursao, so `-c` (ou flag combinada com `c`)
 * precedido do NOME de um shell, ou o token `eval`, disparam. Profundidade
 * tem teto (3): shell dentro de shell dentro de shell alem do teto BARRA em
 * vez de liberar — este gate e fail-closed, e nao ha como provar ausencia de
 * `--no-verify` num aninhamento arbitrario.
 *
 * ESCOPO: vale para todo ator, sem distincao de agente ou janela principal — a
 * trava e sobre o COMANDO, nao sobre quem digita.
 *
 * Saidas de emergencia, as mesmas dos outros gates deste plugin:
 *   - env RAINFOREST_GATE_OFF=1        -> desliga na sessao inteira;
 *   - arquivo .rainforest-gate-off na raiz do repo -> desliga naquele repo;
 *   - `.rainforest/config.json` do projeto, chave `gate-git-verificacao`
 *     (registrada em CHAVES de hooks/lib/config.cjs, lida por `ligado()`;
 *     padrao LIGADO — quem quiser desligar declara `false` na chave).
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

/**
 * Segmenta um trecho de comando em invocacoes independentes. `(` e `)`
 * entram como separador (subshell `(git commit --no-verify)`) — chamado
 * DEPOIS de extraiSubstituicoes(), que ja removeu `$(...)` e crase com
 * delimitador e tudo, entao esta chamada aqui so encontra parenteses de
 * subshell "nu", nunca os de substituicao de comando.
 */
function segmentos(cmd) {
  return cmd.split(/\|\||&&|[;|\n&()]/);
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
 *
 * ESCAPE POR BARRA INVERTIDA (achado atacando a terceira rodada): fora de
 * aspas simples, `\` remove a si mesma e faz o char seguinte virar literal
 * — `--no\-verify` chega ao shell como `--no-verify`, e tem que comparar
 * como tal. Aspas simples preservam a barra invertida literal (shell de
 * verdade nao processa escape dentro delas, e por isso o ramo de `'` abaixo
 * nao trata `\` como especial). Dentro de aspas DUPLAS o fechamento tem que
 * ignorar `\"` escapada (senao um `bash -c "...\"..."` aninhado fecha a
 * aspa cedo demais e quebra a extracao do comando interno) — so `\"`, `\\`,
 * `\$` e `` \` `` sao especiais ali, mesma regra do shell.
 */
function tokens(seg) {
  const toks = [];
  let cur = "";
  let tem = false;
  for (let i = 0; i < seg.length; i += 1) {
    const c = seg[i];
    if (c === "'") {
      const fechar = seg.indexOf(c, i + 1);
      const fim = fechar === -1 ? seg.length : fechar;
      cur += seg.slice(i + 1, fim);
      tem = true;
      i = fim;
      continue;
    }
    if (c === '"') {
      let j = i + 1;
      let fechou = false;
      while (j < seg.length) {
        const cc = seg[j];
        if (cc === "\\" && j + 1 < seg.length && '"\\$`'.includes(seg[j + 1])) {
          cur += seg[j + 1];
          j += 2;
          continue;
        }
        if (cc === '"') { fechou = true; j += 1; break; }
        cur += cc;
        j += 1;
      }
      tem = true;
      i = fechou ? j - 1 : seg.length;
      continue;
    }
    if (c === "\\" && i + 1 < seg.length) {
      cur += seg[i + 1];
      tem = true;
      i += 1;
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
  const inicio = toks.findIndex(ehTokenGit);
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

// Shells cujo `-c <cmd>` recebe uma LINHA DE COMANDO (nao mensagem) como
// argumento seguinte — o argumento e analisado recursivamente.
const NOMES_SHELL = new Set(["bash", "sh", "zsh", "dash", "ash"]);

// Teto de profundidade da recursao em shell -c aninhado. "3 basta": nenhuma
// forma legitima testada precisa de mais, e estourar o teto BARRA (fail
// closed) em vez de liberar, porque nao ha como provar ausencia de
// `--no-verify` num aninhamento arbitrariamente fundo.
const PROFUNDIDADE_MAXIMA = 3;

/**
 * Acha o indice do token de flag `-c` (ou combinada: `-lc`, `-ec`, ...) a
 * partir de `inicio`, pulando flags sem valor pelo caminho e o valor de
 * `-o <opcao>` (forma `bash -o pipefail -c ...`). -1 se nao achar antes de
 * esbarrar num token que nao e flag (o script a rodar, nao `-c`).
 */
function achaFlagC(toks, inicio) {
  for (let j = inicio; j < toks.length; j += 1) {
    const t = toks[j];
    if (t === "-c" || /^-[A-Za-z]*c[A-Za-z]*$/.test(t)) return j;
    if (t === "-o") { j += 1; continue; }
    if (t.startsWith("-")) continue;
    break;
  }
  return -1;
}

/**
 * Nome "puro" de um token de shell: sem caminho (`/bin/bash` -> `bash`,
 * tanto `/` quanto `\` contam, para cobrir caminho Windows) e sem `.exe`
 * (achado atacando a terceira rodada — comparar o token inteiro contra
 * `bash` deixava `/bin/bash -c ...` e `bash.exe -c ...` passarem sem serem
 * reconhecidos como shell).
 *
 * A caixa (maiuscula/minuscula) NAO e normalizada aqui de proposito — quem
 * compara e que decide se normaliza, porque a resposta muda por chamador
 * (ver ehTokenGit e o uso desta funcao em achaInvocacaoShell, achado da
 * rodada 4, revisor independente).
 */
function basenomeShell(tok) {
  const semCaminho = tok.split(/[\\/]/).pop() || tok;
  return semCaminho.replace(/\.exe$/i, "");
}

/**
 * true se `tok` e o executavel `git`, em QUALQUER caixa (`GIT`, `Git`,
 * `gIt`...). Achado da rodada 4 (revisor independente, 2026-09-04): em
 * sistema de arquivos case-insensitive (NTFS no Windows, o padrao do
 * `Git Bash`), o SO resolve `GIT` para o mesmo binario de `git` — a tecla
 * Shift bastava para contornar o gate. Normalizar aqui NAO cria falso
 * positivo: em sistema de arquivos case-SENSITIVE (Linux tipico) o comando
 * `GIT` falharia de qualquer jeito ("command not found"), entao barrar por
 * excesso de zelo nunca acontece de verdade — so em maquina onde `GIT`
 * teria funcionado mesmo.
 *
 * O mesmo raciocinio vale para o nome do shell (`bash`, `BASH`, `/BIN/BASH`)
 * em achaInvocacaoShell, que tambem compara em minusculas — mas NAO para
 * `eval`, que e builtin do shell e e case-sensitive de verdade (`EVAL` da
 * "command not found" no bash), nem para subcomando do git (`commit`,
 * `push`), que o proprio git so reconhece em minusculas (`git COMMIT` ->
 * "'COMMIT' is not a git command"), nem para flags (`--No-Verify` o git
 * rejeita como opcao desconhecida). Normalizar esses tres criaria falso
 * positivo — so o NOME DO EXECUTAVEL resolvido pelo PATH e case-insensitive
 * na pratica.
 */
function ehTokenGit(tok) {
  return tok.toLowerCase() === "git";
}

/**
 * null se os tokens do segmento nao sao uma invocacao `<shell> -c <cmd>`;
 * senao o texto do `<cmd>` (para ser analisado recursivamente). Aceita o
 * nome do shell em qualquer posicao (mesmo motivo do `analisaGit` com
 * `git`: lista de prefixos aceitos antes sempre esquece um caso), com ou
 * sem caminho/`.exe` na frente, e o prefixo `busybox sh -c`.
 */
function achaInvocacaoShell(toks) {
  for (let i = 0; i < toks.length; i += 1) {
    let idx = i;
    if (basenomeShell(toks[idx]).toLowerCase() === "busybox" && NOMES_SHELL.has(basenomeShell(toks[idx + 1] || "").toLowerCase())) idx += 1;
    if (!NOMES_SHELL.has(basenomeShell(toks[idx]).toLowerCase())) continue;
    const j = achaFlagC(toks, idx + 1);
    if (j === -1 || j + 1 >= toks.length) continue;
    return toks[j + 1];
  }
  return null;
}

/**
 * null se os tokens do segmento nao contem `eval`; senao o texto do
 * argumento (para ser analisado recursivamente, mesma recursao do `<shell>
 * -c <cmd>`). `eval "<comando>"` executa o argumento como comando — igual a
 * `bash -c` — e o bash de verdade junta TODOS os argumentos de `eval` com
 * espaco antes de avaliar, entao aqui tambem: comeca no primeiro token que
 * nao e flag (eval nao tem flag de verdade, mas um token comecando com `-`
 * ali e argumento do proprio comando, nao opcao do eval) e junta ate o fim
 * do segmento.
 */
function achaInvocacaoEval(toks) {
  const idx = toks.indexOf("eval");
  if (idx === -1) return null;
  let j = idx + 1;
  while (j < toks.length && toks[j].startsWith("-")) j += 1;
  if (j >= toks.length) return null;
  return toks.slice(j).join(" ");
}

/**
 * Analisa um comando bruto (o `tool_input.command` original, ou o texto de
 * um `-c` de shell aninhado) e devolve {motivo, dirC} do primeiro segmento
 * problematico, ou null se nao achou nada. Recursivo: cada `<shell> -c
 * <cmd>` encontrado tem `<cmd>` analisado de novo, ate `PROFUNDIDADE_MAXIMA`.
 */
function analisaComando(cmd, profundidade) {
  if (profundidade > PROFUNDIDADE_MAXIMA) {
    return { motivo: "shell aninhado alem da profundidade maxima (fail-closed)", dirC: null };
  }
  for (const seg of segmentosDoComando(cmd)) {
    const toks = tokens(seg);

    const g = analisaGit(toks);
    if (g) {
      const m = motivoDe(g);
      if (m) return { motivo: m, dirC: g.dirC };
    }

    const cmdAninhado = achaInvocacaoShell(toks);
    if (cmdAninhado !== null) {
      const r = analisaComando(cmdAninhado, profundidade + 1);
      if (r) return r;
    }

    const cmdEval = achaInvocacaoEval(toks);
    if (cmdEval !== null) {
      const r = analisaComando(cmdEval, profundidade + 1);
      if (r) return r;
    }
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
    `  - arquivo .rainforest-gate-off na raiz do repo (desliga so naquele repo);\n` +
    `  - chave "gate-git-verificacao": false em .rainforest/config.json do\n` +
    `    projeto (desliga so naquele repo, sem precisar de arquivo marcador).\n`
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

  const achado = analisaComando(cmd, 0);
  if (!achado) process.exit(0);
  const { motivo, dirC } = achado;

  const dir = dirC || cwdDoEvento;
  const toplevel = git(dir, ["rev-parse", "--show-toplevel"]) || dir;
  if (fs.existsSync(path.join(toplevel, ".rainforest-gate-off"))) process.exit(0);

  bloqueia(motivo, dir);
}

main();
