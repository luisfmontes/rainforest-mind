#!/usr/bin/env node
/**
 * Tokenização de um segmento de comando e localização da POSIÇÃO DE COMANDO
 * dentro dele — quem é o comando de verdade, pulando wrappers que só
 * repassam (`env`, `sudo`, `time`, ...) e as flags deles que consomem valor.
 *
 * Extraído de `hooks/gate-worktree.cjs` (nasceram ali para `procuraCLI`) e
 * generalizado para uso também em `hooks/lib/cwd-efetivo.cjs` (rodada 6,
 * lote 3, 2026-09-03): o K2 do auditor achou `cwdPorSegmento` decidindo se
 * um segmento é um comando `git` por SUBSTRING (`seg.includes("git")`), que
 * casava "git" dentro de "gitignore" citado como argumento de outro comando
 * (`grep -rn -C 3 "gitignore" .`). A mesma noção de posição de comando que
 * `procuraCLI` já usa para achar CLI que escreve resolve o mesmo problema
 * para `git` — em vez de reimplementar, os dois consumidores compartilham
 * este módulo.
 */

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

/**
 * Nome de comando, ignorando caminho: um binario com caminho resolve para seu
 * nome.
 *
 * `ehPosicaoDeComando` (rodada 20, lote 3, 2026-09-04 — achado do auditor na
 * 18a revisao): o `!tok.q` existe para um nome CITADO como ARGUMENTO nao virar
 * comando (`echo "gitignore"`, e o `>` dentro de aspas do conserto de
 * 2026-09-01). Mas aplica-lo tambem na POSICAO DE COMANDO deixava passar
 * `"git" add -A` (exit 0, contra exit 2 do `git add -A` puro) no
 * `gate-staging-total`, e `"cp"`/`"tee"`/`"sed"`/`"mv"` citados escapavam do
 * `alvosBashEscrita` do `gate-worktree`. Quem sabe que o token esta na posicao
 * de comando passa `true`, e o token citado conta — mesmo tratamento que
 * `procuraCLI` (gate-worktree.cjs) ja da ao nome de CLI citado, inclusive o
 * desconto do `$` do ANSI-C (A4). Default `false`: quem nao passa preserva o
 * comportamento de antes.
 */
function ehComando(tok, nome, ehPosicaoDeComando = false) {
  if (tok.q && !ehPosicaoDeComando) return false;
  let v = tok.v;
  if (tok.q && v.startsWith("$")) v = v.slice(1); // ANSI-C (A4), como procuraCLI
  return new RegExp("(^|[\\\\/])" + nome + "(\\.exe)?$").test(v);
}

/**
 * Nome de wrapper extraido de um token, removendo aspas e prefixo ANSI-C se
 * necessario. Usado para reconhecer wrappers que foram citados na posicao de
 * comando (R21, rodada 15, lote 4, 2026-09-04): `"env" FOO=1 git add -A`
 * tinha o nome do wrapper entre aspas, entao `posicaoDeComando` nunca passava
 * a checagem de `!tok.q` e `posicaoDeComando` retornava 0 (apontando para o
 * "env" citado em vez de pulá-lo), deixando a posição de comando errada.
 */
function nomeDeWrapper(tok) {
  if (tok.q && tok.v.startsWith("$")) return tok.v.slice(1);
  return tok.v;
}

// Wrappers que REPASSAM o comando adiante, na MESMA posicao de comando — o
// nome da CLI aparece DEPOIS deles. H3 (rodada 5, lote 3, 2026-09-03): antes
// disto, `procuraCLI` casava o nome em QUALQUER posicao do segmento (so
// pulando token citado em posicao de argumento), e `grep -rn claude .` virava
// falso positivo — "claude" ali e um PADRAO DE BUSCA, argumento do grep,
// nunca um comando.
const WRAPPERS_QUE_REPASSAM = new Set([
  "env", "command", "exec", "nohup", "nice", "timeout", "xargs", "sudo", "time",
]);

// Operadores de fronteira de segmento com DOIS caracteres que tem que ser
// consumidos JUNTOS — nunca so o primeiro deles. `|&` (#309, achado 1, revisao
// 2): atalho do bash para `2>&1 |` (liga stderr ao pipe seguinte). A
// fronteira de segmento ja tratava `|` sozinho como divisor incondicional
// (junto com `;`, `\n`, `(`, `)`, `{`, `}`), entao o `&` de `|&` sobrava e
// virava o PRIMEIRO TOKEN do segmento seguinte — `echo hi |& bash -c "gh
// issue close 12"` deixava `bash -c ...` fora da posicao de comando (o token
// inicial era `&`). Medido saindo exit 0 no `gate-fechar-issue.cjs` e no
// `gate-staging-total.cjs`, inclusive na `origin/main` (2026-09-22).
// Exportado para as copias da segmentacao (`gate-fechar-issue.cjs` e
// `cwd-efetivo.cjs`, que `gate-staging-total.cjs`/`gate-mensagem-commit.cjs`
// usam) compartilharem a MESMA lista, em vez de cada uma aprender o operador
// numa rodada diferente.
const OPERADORES_DE_DOIS = new Set(["|&"]);

// Palavras reservadas do shell que precedem um comando sem SEREM o comando —
// `posicaoDeComando` tem que pular por cima delas para achar o wrapper de
// verdade (#309): medido com o gate real, `do`/`then`/`else`/`elif`/`while`/
// `until`/`if`/`!` na frente de `bash -c "gh issue close 12"` faziam
// `posicaoDeComando` apontar para a PROPRIA palavra reservada (nao e
// atribuicao nem wrapper conhecido, o laco parava ali), entao
// `desempacotarWrapperDeString` nunca via o `bash -c` — `for t in x; do bash
// -c "gh issue close 12"; done` saia com exit 0 (bypass). `{`/`(` NAO entram
// aqui: `segmentosParaGate` (nos tres gates de texto) ja os consome como
// FRONTEIRA DE SEGMENTO antes de qualquer tokenizacao chegar aqui — medido
// que ja saiam exit 2 sem mudanca nenhuma.
// `coproc` (revisao #309, achado 1): mesmo bypass, medido com `coproc bash -c
// "gh issue close 12"` saindo exit 0 antes desta entrada. `coproc NOME { ...; }`
// (com nome) exige comando composto — o `{` ja e fronteira de segmento, entao
// so o `coproc bash -c ...` sem nome precisava deste pulo.
const PALAVRAS_RESERVADAS = new Set([
  "do", "then", "else", "elif", "while", "until", "if", "!", "coproc",
]);

// Flags que cada wrapper reconhece e que CONSOMEM VALOR: o proprio token
// mais o seguinte — ou so o proprio, se o valor vier colado com `=`
// (`--chdir=X`). Wrapper (ou flag) NAO listado aqui e tratado como SEM
// valor: so o proprio token e pulado — a mesma regra vale para toda flag
// DESCONHECIDA que comece com `-` (postura conservadora: e melhor pular de
// menos um argumento estranho do que engolir o comando de verdade).
//
// P1 (rodada 8, lote 3, 2026-09-04): a versao anterior so sabia `env -C`/
// `--chdir` e `sudo -u/-g/--user/--group` — qualquer outra flag destes
// wrappers (`env -u FOO`, `sudo -E`, `sudo -i`, ...) parava a busca ALI,
// tratando a propria flag como se fosse o comando efetivo (o proximo `while`
// da tabela nunca era alcancado, e o `while` externo tambem parava, porque a
// flag nao e nome de wrapper). `env -u OneDrive git add -A` e
// `env -u FOO codex exec --yolo` atravessavam os gates assim.
// T1 (rodada 11, lote 3, 2026-09-04): `timeout` nao tinha entrada aqui — o
// ramo `timeout` de `posicaoDeComando` tratava TODA flag como sem valor,
// entao `-s SIG`/`--signal SIG` e `-k DUR`/`--kill-after DUR` (forma COM
// ESPACO, valor separado) paravam de pular no proprio valor, e a duracao
// posicional (sempre pulada logo depois) caia no valor da flag em vez da
// duracao de verdade — o token de comando de verdade (`git`, `gh`, `codex`,
// ...) ficava um passo alem do que devia. `timeout -s TERM 30 gh issue close
// 12` classificava `30` como comando, escapando do `gate-fechar-issue`; o
// mesmo padrao com `git add -A` e `codex exec --yolo` escapava dos outros
// dois gates. `--signal=TERM`/`--kill-after=5` (forma colada com `=`)
// ja funcionava, porque `pularFlagsDoWrapper` sempre pulou so 1 quando ha
// `=`, independente de tabela.
const FLAGS_COM_VALOR = {
  env: new Set(["-u", "--unset", "-C", "--chdir"]),
  sudo: new Set(["-u", "-g", "-p", "-C", "--user", "--group"]),
  nice: new Set(["-n"]),
  xargs: new Set(["-n", "-I", "-d", "-P"]),
  timeout: new Set(["-s", "--signal", "-k", "--kill-after"]),
};

/** `NOME=valor` isolado — atribuicao de variavel antes do comando de verdade. */
function ehAtribuicao(tok) {
  return /^[A-Za-z_][A-Za-z0-9_]*=/.test(tok);
}

/** Nome "base" de uma flag, sem o `=valor` colado (`--chdir=X` -> `--chdir`). */
function baseDaFlag(tok) {
  const eq = tok.indexOf("=");
  return eq === -1 ? tok : tok.slice(0, eq);
}

/**
 * Pula, a partir do indice `i`, toda flag reconhecida (e desconhecida —
 * tratada como sem valor) de `wrapper`. Devolve o novo indice, na primeira
 * posicao que ja nao e flag.
 *
 * `nice -n5` (colado, sem `=` nem espaco) e o unico caso de valor grudado
 * sem separador — tratado a parte, antes de consultar a tabela.
 *
 * `captura` (opcional, R1 rodada 9 lote 3 2026-09-04): quando fornecido e o
 * wrapper e `env`, grava em `captura.chdir` o valor de `-C`/`--chdir`
 * encontrado (o ULTIMO, se houver mais de um — mesma regra de "usa o
 * ultimo" que `git -C`). Substitui o regex fixo que so reconhecia
 * `-C`/`--chdir=` logo apos `env` (pulando so `NOME=valor`) — `env -u FOO
 * --chdir=X cmd` nao casava porque `-u FOO` vinha antes. Chamadores que nao
 * passam `captura` mantem o comportamento antigo (so pula, nao coleta).
 */
function pularFlagsDoWrapper(toks, i, wrapper, captura) {
  const comValor = FLAGS_COM_VALOR[wrapper];
  while (i < toks.length && !toks[i].q && toks[i].v.startsWith("-")) {
    const tok = toks[i].v;
    if (wrapper === "nice" && /^-n\d+$/.test(tok)) {
      i += 1;
      continue;
    }
    const base = baseDaFlag(tok);
    if (comValor && comValor.has(base)) {
      if (captura && wrapper === "env" && (base === "-C" || base === "--chdir")) {
        if (tok.includes("=")) {
          captura.chdir = tok.slice(tok.indexOf("=") + 1);
        } else if (i + 1 < toks.length) {
          captura.chdir = toks[i + 1].v;
        }
      }
      i += tok.includes("=") ? 1 : 2;
    } else {
      i += 1; // sem valor (conhecida ou nao) — so o proprio token
    }
  }
  return i;
}

/**
 * Acha o INDICE do token que e a posicao de comando de um segmento
 * tokenizado, pulando atribuicoes `NOME=valor` soltas e os wrappers
 * conhecidos (e os argumentos deles que consomem valor, via
 * `pularFlagsDoWrapper`/`FLAGS_COM_VALOR`). `null` se o segmento acaba
 * dentro dos proprios prefixos (`env` sozinho, sem comando depois).
 *
 * `timeout` usa a MESMA `pularFlagsDoWrapper`/`FLAGS_COM_VALOR` dos outros
 * wrappers (T1, rodada 11) — `-s`/`--signal` e `-k`/`--kill-after` (forma com
 * espaco) consomem o token seguinte, qualquer outra flag e pulada sozinha —
 * e so DEPOIS disso pula mais um token, a duracao posicional (nunca a flag
 * em si, nem o valor dela).
 *
 * `exec`, `nohup`, `command`, `time` nao tem flags proprias na tabela: caem
 * no mesmo `pularFlagsDoWrapper`, que trata qualquer `-flag` deles como sem
 * valor (cobre `time -p`, `command -p`).
 *
 * `captura` (opcional): repassado para `pularFlagsDoWrapper` — veja o
 * comentario la para o uso (extrair `-C`/`--chdir` de um `env` em qualquer
 * ordem de flags).
 */
function posicaoDeComando(toks, captura) {
  let i = 0;
  for (;;) {
    if (i < toks.length && !toks[i].q && ehAtribuicao(toks[i].v)) {
      i += 1;
      continue;
    }
    if (i < toks.length && !toks[i].q && PALAVRAS_RESERVADAS.has(toks[i].v)) {
      i += 1;
      continue;
    }
    if (i < toks.length && WRAPPERS_QUE_REPASSAM.has(nomeDeWrapper(toks[i]))) {
      const wrapper = nomeDeWrapper(toks[i]);
      i += 1;
      i = pularFlagsDoWrapper(toks, i, wrapper, captura);
      if (wrapper === "timeout" && i < toks.length) i += 1; // a duracao
      continue;
    }
    break;
  }
  return i < toks.length ? i : null;
}

/**
 * Reconstroi, como texto, os tokens de `toks` a partir do indice `i` — usado
 * para alimentar `desempacotarWrapperDeString` (que espera uma STRING crua,
 * com o nome do wrapper como primeiro token dela) a partir de uma posicao de
 * comando ja calculada por `posicaoDeComando` (que pode vir depois de um
 * prefixo tipo `env`/`sudo`/`NOME=valor`). Token citado volta entre aspas
 * duplas — nenhum destes tokens pode conter `"` de verdade (era o delimitador).
 *
 * Movida de `gate-worktree.cjs` (rodada 13, lote 3, 2026-09-04): P3, achado
 * do auditor (11a revisao) — `posicaoDeComando` e `desempacotarWrapperDeString`
 * so se compunham ali (`procuraCLI` ja chamava `desempacotarWrapperDeString(
 * textoAPartir(toks, i))`); `gate-staging-total.cjs` e `gate-fechar-issue.cjs`
 * chamavam `desempacotarWrapperDeString` sobre o segmento CRU (posicao 0),
 * entao `timeout 5 bash -c "git add -A"`/`env -C . bash -c "git add -A"`
 * (staging-total) e `timeout 5 bash -c "gh issue close 12"` (fechar-issue)
 * atravessavam os dois gates com exit 0 — o wrapper de prefixo escondia o
 * wrapper de string do desempacotador. Exportada aqui para os tres gates
 * compartilharem a MESMA implementacao, em vez de `gate-worktree.cjs` manter
 * a unica copia e os outros dois reimplementarem por conta propria.
 */
function textoAPartir(toks, i) {
  return toks.slice(i).map((t) => (t.q ? `"${t.v}"` : t.v)).join(" ");
}

// --- Wrapper de STRING (T2, rodada 11, lote 3, 2026-09-04) -----------------
//
// Diferente de `WRAPPERS_QUE_REPASSAM` (o comando de verdade aparece como
// TOKEN, na mesma linha), estes wrappers encapsulam o comando de verdade
// DENTRO de uma STRING — `eval "git add -A"`, `bash -c "git add -A"`,
// `Invoke-Expression "git add -A"`/`iex "..."`, `pwsh -Command "..."`,
// `cmd /c "..."`. Nasceu em `gate-fechar-issue.cjs` (R2, rodada 9) so para
// `eval`/`Invoke-Expression`/`iex`/`bash -c`-e-primos/`pwsh|powershell
// -Command`/`cmd /c` — e so ali: `gate-staging-total.cjs` e
// `gate-worktree.cjs` nao desempacotavam NENHUM destes, entao
// `Invoke-Expression "git add -A"` (staging-total) e
// `iex "git commit -m x"`/`Invoke-Expression "codex exec --yolo"`
// (gate-worktree) atravessavam os dois gates com exit 0. Movido para aqui
// para os tres gates compartilharem a MESMA implementacao, em vez de cada
// um aprender o mesmo wrapper em rodadas diferentes.

// Executaveis que encapsulam uma string de comando, e a flag que a
// introduz. Chave normalizada por `normalizarNomeExecutavel` (sem
// caminho/extensao/aspas). `pwsh`/`powershell` e `cmd` sao tratados a parte
// em `desempacotarWrapperDeString` porque aceitam abreviacao de flag
// (`-c`, `-co`, `-com`, ... / `/c`, `/k`).
const WRAPPERS_DE_COMANDO = {
  bash: "-c",
  sh: "-c",
  zsh: "-c",
  ksh: "-c",
  dash: "-c",
};

// W1 (rodada 14, lote 3, 2026-09-04): o laco que procura o -c em
// `desempacotarWrapperDeString` parava, em silencio, no primeiro token que
// nao comeca com "-" — `bash -o pipefail -c "git add -A"` pulava "-o"
// (comeca com "-") e parava em "pipefail" (nao comeca com "-"), devolvendo
// {interno:null, ilegivel:false} como se o segmento nao fosse wrapper
// nenhum; os tres gates liberavam o comando encapsulado. Mesmo padrao com
// `-eo pipefail`, `--rcfile X`, `--init-file X`, `-O opt`, `+O opt`.
// Conserto: tabela das flags QUE TEM VALOR de cada shell — o caractere
// curto (bundle: so o ULTIMO caractere do bundle consome valor, como em
// `tar -xvf arq` — `-eo` = `-e` + `-o`, entao "o" no fim consome o proximo
// token) e a flag longa exata (`--rcfile`, `--init-file`, so em bash).
const CURTAS_COM_VALOR = {
  bash: new Set(["o", "O"]),
  sh: new Set(["o"]),
  zsh: new Set(["o"]),
  ksh: new Set(["o"]),
  dash: new Set(["o"]),
};
const LONGAS_COM_VALOR = {
  bash: new Set(["--rcfile", "--init-file"]),
};

/** Nome "limpo" de um executavel: sem aspas, sem caminho, sem extensao, minusculo. */
function normalizarNomeExecutavel(nome) {
  let s = String(nome == null ? "" : nome).replace(/^["']|["']$/g, "");
  s = s.split(/[\\/]/).pop();
  s = s.replace(/\.(exe|cmd|bat)$/i, "");
  return s.toLowerCase();
}

/**
 * Extrai o primeiro token de `str` (aspas simples/duplas respeitadas) e o
 * restante da string logo apos esse token (sem consumir as aspas do
 * restante). Retorna null se `str` nao tem nenhum token.
 *
 * Rodada 19 (lote 3): `{`/`}`/`(`/`)` FORA de aspas viram fronteira de token,
 * cada um capturado como token de UM caractere — antes disto a alternativa
 * final era `\S+`, que engolia `{`/`(` colados a um token vizinho.
 * `&{git add -A}` (call operator do PowerShell colado ao scriptblock, sem
 * espaco) tinha o primeiro token lido como `&{git` inteiro, que nunca casava
 * com `exe === "&"` — o `&` sozinho, tratado como fronteira logo antes do
 * `{`, corrige isso. Dentro de aspas nada muda: `"fix {json} parse"` continua
 * saindo como UM token so, via os ramos de aspas simples/duplas acima.
 */
function extrairPrimeiroToken(str) {
  const m = /^\s*(?:"([^"]*)"|'([^']*)'|([{}()])|([^\s{}()]+))/.exec(str);
  if (!m) return null;
  const tok = m[1] !== undefined ? m[1] : m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4];
  // `citado`/`aspa` (D2, #309): de qual ramo do regex veio o token — precisa
  // saber se era `"..."` (aspas duplas, onde o bash EXPANDE variavel) contra
  // `'...'` (aspas simples, literal) ou nu. `tok` sozinho nao distingue: o
  // conteudo capturado ja vem SEM as aspas nos tres casos, entao `"$t"` e
  // `$t` nu produzem o mesmo `tok` ("$t") — sem este par a chamadora nao tem
  // como saber se a variavel estava citada.
  const citado = m[1] !== undefined || m[2] !== undefined;
  const aspa = m[1] !== undefined ? '"' : m[2] !== undefined ? "'" : null;
  return { tok, resto: str.slice(m[0].length), citado, aspa };
}

/**
 * `current` (token de `extrairPrimeiroToken`) é EXATAMENTE uma variável
 * citada com aspas DUPLAS (`"$x"`/`"${x}"`) — o bash expande, e aspas
 * SIMPLES não contam (literal, não variável) — E não há mais nenhum
 * argumento depois dela, só redirecionamento ou nada (D2, #309).
 *
 * Por que isto importa: `bash "$t"` é `bash <caminho de script>`, igual a
 * `bash ./x.sh` — o CONTEÚDO de `$t` nunca é lido aqui, só o fato de que é
 * UM caminho, sozinho, na última posição. Sem este ramo, `contemConstrucaoIlegivel`
 * via de baixo marcava `"$t"` como ilegível pela MESMA regra que pega `bash
 * $CMD` (variável de verdade, não resolvida) — mas `"$f" "gh issue close
 * 12"` (variável com MAIS argumento depois) continua ilegível: a variável
 * ali não é o único argumento, pode ser qualquer coisa (incluindo um `-c`
 * escondido dentro dela).
 *
 * A variável pode vir seguida de um resto LITERAL de caminho que começa em
 * separador (`"$P/on-stop.sh"`, `"${D}\x.ps1"`): continua sendo UM caminho,
 * e o resto não tem `$`, crase nem aspa — nada ali expande. Barrado pelo
 * gate de staging em 2026-09-22 rodando o hook do plugin Warp à mão
 * (`bash "$P/on-stop.sh"`), enquanto `bash "$P"` e o caminho escrito por
 * extenso já passavam.
 */
function ehVariavelCitadaFinal(current) {
  if (!current.citado || current.aspa !== '"') return false;
  if (!/^\$(?:[A-Za-z_][A-Za-z0-9_]*|\{[A-Za-z_][A-Za-z0-9_]*\})(?:[\/\\][^$`"]*)?$/.test(current.tok)) return false;
  return ehApenasRedirecionamentos(current.resto);
}

/** Um redirecionamento (`>`, `>>`, `<`, `2>&1`, `&>`, ...) no INÍCIO de `s`,
 * consumindo também o alvo dele quando houver um (palavra citada ou não).
 * `null` se `s` não começa com redirecionamento nenhum. */
function consumirRedirecionamento(s) {
  const semFd = /^(&>>?|\d*>>?&\d+|\d*<&\d+)/.exec(s);
  if (semFd) return s.slice(semFd[0].length);
  const comAlvo = /^\d*(>>|>|<)/.exec(s);
  if (comAlvo) {
    const resto = s.slice(comAlvo[0].length);
    const alvo = extrairPrimeiroToken(resto);
    return alvo ? alvo.resto : resto.replace(/^\s+/, "");
  }
  return null;
}

/** `resto` não tem NENHUM argumento posicional — só espaço e zero ou mais
 * redirecionamentos, em qualquer sequência. */
function ehApenasRedirecionamentos(resto) {
  let s = resto;
  for (;;) {
    s = s.replace(/^\s+/, "");
    if (s === "") return true;
    const proximo = consumirRedirecionamento(s);
    if (proximo === null) return false;
    s = proximo;
  }
}

/**
 * `tok` e uma abreviacao valida de `nomeCompleto` (ex.: "-c", "-co", "-com"
 * para "-command")? O PowerShell aceita qualquer prefixo nao-ambiguo de uma
 * flag; aqui a checagem e conservadora — basta ser prefixo de `nomeCompleto`
 * com pelo menos 2 caracteres (o `-` e uma letra), case-insensitive.
 */
function casaPrefixoDeFlag(tok, nomeCompleto) {
  const t = String(tok || "").toLowerCase();
  return t.length >= 2 && t[0] === "-" && nomeCompleto.toLowerCase().startsWith(t);
}

/**
 * Remove continuacao de linha: contrabarra IMEDIATAMENTE seguida de quebra
 * de linha (LF ou CRLF) some — exatamente como o bash colapsa a string que
 * vira script de um wrapper (`bash -c "..."`, `eval "..."`) ANTES de rodar,
 * e exatamente como o bash colapsa o texto de NIVEL SUPERIOR de um comando
 * antes de fatiar em segmentos (tarefa 13).
 *
 * #309, revisao 3, achados 1 e 2: a versao anterior era uma regex cega
 * (`/\\\r?\n/g`) sobre o texto todo, com aspas simples mascaradas por
 * `/'[^']*'/g` só na chamada de topo (`colapsaContinuacaoDeLinhaNoTopo`).
 * Dois defeitos:
 *
 *   1. REGRESSAO (tarefa 13): a regex colapsa QUALQUER contrabarra antes de
 *      LF, sem olhar quantas vem antes. No bash, contrabarra escapa a
 *      PROXIMA — uma corrida de `n` contrabarras seguida de LF só vira
 *      continuacao quando `n` e IMPAR (a ultima contrabarra sobra e escapa o
 *      LF); quando `n` e PAR, as contrabarras se casam duas a duas e o LF
 *      fica de fora, continua fronteira de comando de verdade. Medido
 *      (`spawnSync(["bash","-x",arquivo])`, 2026-09-22): `echo hi \\<LF>gh
 *      issue close 12` (duas contrabarras) roda como DOIS comandos no bash
 *      real (`echo hi \` e `gh issue close 12`, xtrace com dois `+`) — a
 *      regex antiga colapsava do mesmo jeito que uma unica contrabarra,
 *      fundindo tudo num `echo ...` so e escondendo o `gh issue close 12`.
 *   2. BURACO ANTIGO: a mascara `/'[^']*'/g` da chamada de topo casa
 *      QUALQUER trecho entre dois `'`, inclusive um apostrofo solto DENTRO
 *      de aspas duplas (`"it's done"` — o `'` de "it's" e o `'` de "don't"
 *      formam um par falso que a mascara declara "aspas simples" e protege
 *      do colapso). `gh pr create --body "it's done, closes \<LF>#42, don't
 *      worry"` chegava com o LF intacto, o corpo partia em duas linhas e o
 *      `closes #42` nunca se formava.
 *
 * Os dois pedem a mesma correcao: varredura caractere a caractere com
 * ESTADO de aspas (fora / aspas simples / aspas duplas) e CONTAGEM da
 * corrida de contrabarras antes de decidir se a proxima quebra de linha
 * escapa. Dentro de aspas simples nunca colapsa (aspas simples sao literais
 * de ponta a ponta no bash, sem excecao para `\`); fora delas — sem aspas ou
 * dentro de aspas duplas, onde o bash TAMBEM colapsa continuacao — colapsa
 * quando a corrida de contrabarras imediatamente antes do LF/CRLF for
 * IMPAR, preservando as contrabarras que sobraram em pares (elas nao mexem
 * no texto, so a ULTIMA contrabarra impar + a quebra somem). Uma aspa dupla
 * so alterna o estado quando NAO esta em aspas simples; uma aspa simples so
 * abre quando o estado e "fora" (nunca dentro de aspas duplas — e o que
 * consertava o achado 2). Uma contrabarra que escapa um caractere qualquer
 * (inclusive uma aspa) e emitida com o caractere junto, sem passar pelo
 * teste de alternancia de estado — e por isso `\"` dentro de aspas duplas
 * nao fecha a aspa, e `\'` fora de aspas nao abre uma aspa simples.
 *
 * Serve os DOIS usos: o texto de NIVEL SUPERIOR (antes, `NoTopo`) e o
 * INTERNO de um wrapper de string (`desempacota()`, tarefa 12) — o mascarar-
 * e-desmascarar de `colapsaContinuacaoDeLinhaNoTopo` existia só porque a
 * regex de baixo nao sabia respeitar aspas; agora que a propria varredura
 * sabe, as duas funcoes fazem o mesmo trabalho e `colapsaContinuacaoDeLinhaNoTopo`
 * (mantida, exportada, usada por `gate-fechar-issue.cjs` e `cwd-efetivo.cjs`)
 * vira um alias direto — ver docblock dela.
 */
function colapsaContinuacaoDeLinha(str) {
  let saida = "";
  let estado = "fora"; // "fora" | "simples" | "duplas"
  const n = str.length;
  let i = 0;
  while (i < n) {
    const c = str[i];
    if (estado === "simples") {
      // Aspas simples sao literais de ponta a ponta — nem a propria aspa
      // simples de fechamento passa por processamento nenhum antes.
      if (c === "'") estado = "fora";
      saida += c;
      i += 1;
      continue;
    }
    if (c === "'" && estado === "fora") {
      estado = "simples";
      saida += c;
      i += 1;
      continue;
    }
    if (c === '"') {
      estado = estado === "duplas" ? "fora" : "duplas";
      saida += c;
      i += 1;
      continue;
    }
    if (c === "\\") {
      // Corrida de contrabarras consecutivas a partir daqui.
      let fim = i;
      while (fim < n && str[fim] === "\\") fim += 1;
      const qtd = fim - i;
      const pares = Math.floor(qtd / 2) * 2; // ficam como estao — nao mexem no texto
      saida += "\\".repeat(pares);
      if (qtd % 2 === 0) {
        i = fim; // corrida par: nenhuma contrabarra sobra pra escapar o que vem depois
        continue;
      }
      // Contrabarra impar sobrando: escapa o proximo caractere.
      const alvo = str[fim];
      const ehLF = alvo === "\n";
      const ehCRLF = alvo === "\r" && str[fim + 1] === "\n";
      if (ehLF || ehCRLF) {
        // Continuacao de linha de verdade: a contrabarra sobrando e a
        // quebra somem juntas, sem ir pra saida.
        i = fim + (ehCRLF ? 2 : 1);
        continue;
      }
      // Escapa um caractere qualquer (inclusive aspa): emite os dois juntos,
      // sem passar pelo teste de alternancia de estado acima.
      if (alvo === undefined) {
        // Contrabarra solta no fim absoluto (nada depois dela, nem quebra).
        // Medido: lido de script ou do stdin, o bash a DESCARTA (`echo hi\`
        // imprime `hi`); em `bash -c`, ela sobrevive. A funcao segue o
        // primeiro, e a diferenca nao muda veredito de gate nenhum: como nao
        // sobra caractere depois, nao ha comando a esconder ali (revisao 5).
        i = fim;
        continue;
      }
      // Escapa um caractere qualquer (inclusive aspa): emite os dois juntos,
      // sem passar pelo teste de alternancia de estado acima.
      saida += "\\" + alvo;
      i = fim + 1;
      continue;
    }
    saida += c;
    i += 1;
  }
  return saida;
}

/**
 * Alias de `colapsaContinuacaoDeLinha` para o texto de comando de NIVEL
 * SUPERIOR — mantido com nome proprio (e exportado) porque
 * `hooks/gate-fechar-issue.cjs` e `hooks/lib/cwd-efetivo.cjs` importam por
 * este nome (tarefa 14 não toca esses dois arquivos).
 *
 * Ate a tarefa 14 esta funcao tinha um corpo proprio: mascarava trecho entre
 * aspas simples (`/'[^']*'/g`) antes de chamar a regex cega de
 * `colapsaContinuacaoDeLinha` e desmascarava depois — só para que o colapso
 * não mexesse no que estava entre aspas simples de verdade. Agora que
 * `colapsaContinuacaoDeLinha` faz essa varredura com estado de aspas por
 * conta propria (fora / simples / duplas), a mascara daqui virou trabalho
 * duplicado — pior, era o proprio mecanismo do achado 2 (mascara por regex
 * cega tambem casava apostrofo solto dentro de aspas duplas como se fosse
 * par de aspas simples). As duas funcoes fazem hoje exatamente a mesma
 * varredura; ficam como alias em vez de uma so para nao editar os dois
 * arquivos que importam `colapsaContinuacaoDeLinhaNoTopo` por nome, fora do
 * escopo desta tarefa.
 */
function colapsaContinuacaoDeLinhaNoTopo(cmdOriginal) {
  return colapsaContinuacaoDeLinha(cmdOriginal);
}

/** Tira UM nivel de aspas externas de `interno`, se houver. */
function desempacota(interno) {
  interno = interno.trim();
  const aspas = /^"([\s\S]*)"$/.exec(interno) || /^'([\s\S]*)'$/.exec(interno);
  interno = aspas ? aspas[1] : interno;
  interno = colapsaContinuacaoDeLinha(interno);
  return interno;
}

/**
 * A string interna de um wrapper e ilegivel quando contem substituicao de
 * comando (`$(...)`, crase) ou variavel (`$X`, `${X}`) — nao da para saber
 * com seguranca o que vai rodar dentro. Postura conservadora.
 */
function contemConstrucaoIlegivel(str) {
  // O `0-9` cobre parametro posicional (`$1`, `$2`): `bash -c` com ele dentro e
  // tao ilegivel quanto com `$VAR`, e a classe sem digito o deixava passar.
  // Apontado como lacuna na revisao de 2026-09-05, na mesma linha que D22 tocou.
  // `@*#?$!-` cobre parametro especial (`$@`, `$*`, `$#`, `$?`, `$$`, `$!`,
  // `$-`): revisao #309, achado 2 — `set -- -c "gh issue close 12"; bash
  // "$@"`, `bash "$*"` e `eval "$@"`/`eval $@` saiam exit 0 porque a classe
  // sem esses caracteres nao via `$@`/`$*` como variavel nenhuma. `ehVariavelCitadaFinal`
  // continua so aceitando `"$nome"`/`"${nome}"` (identificador), entao
  // `"$@"`/`"$*"` nunca escapam por aquele ramo do caminho de script.
  return /\$\(|`|\$[A-Za-z_{0-9@*#?$!-]/.test(str);
}

/**
 * Se `segmento` e uma invocacao de wrapper de STRING — `eval`,
 * `Invoke-Expression`/`iex` (PowerShell), `bash -c`/`sh -c`/`zsh -c`/
 * `ksh -c`/`dash -c`, `pwsh`/`powershell` com qualquer abreviacao de
 * `-Command` (`-c`, `-co`, `-com`, ...) ou `-EncodedCommand`, ou
 * `cmd /c`/`cmd /k` — OU uma invocacao de wrapper de ARQUIVO opaco ao
 * parser (`source x.sh`, `. x.sh`/`. x.ps1`, `& x.ps1` — R18, auditor,
 * 16a revisao, lote 3, 2026-09-04) — devolve `{ interno, ilegivel }`:
 *
 *   - `interno`: a string de comando encapsulada (sem UM nivel de aspas
 *     externas, se houver), ou `null` se `segmento` nao e nenhum destes
 *     wrappers (nesse caso `ilegivel` e sempre `false`) OU se e um wrapper
 *     de ARQUIVO (nunca temos o conteudo do arquivo, so `ilegivel` importa);
 *   - `ilegivel`: `true` quando o conteudo tem substituicao de comando ou
 *     variavel (`contemConstrucaoIlegivel`), quando o wrapper e
 *     `-EncodedCommand` (base64, ilegivel por definicao — `interno` vem
 *     `null` nesse caso, so `ilegivel` importa), OU quando `segmento` roda
 *     um ARQUIVO externo ao parser: `source`/`.` (bash, qualquer ferramenta)
 *     sempre, e `&` (call operator do PowerShell) SOMENTE quando `ferramenta`
 *     e `"PowerShell"` — em Bash, `&` sozinho e SEPARADOR de comando (ja
 *     tratado nos gates desde a rodada 6) e nao pode virar ilegivel aqui, ou
 *     super-bloqueia algo como `echo hi & git status`. Mesma postura
 *     conservadora que `bash x.sh` (sem `-c`) ja recebe do laco W1 mais
 *     abaixo — antes deste conserto os tres saiam `{interno:null,
 *     ilegivel:false}` (arquivo opaco lido como "nao e wrapper, siga em
 *     frente") e os tres gates liberavam.
 *
 * `ferramenta` (opcional, ex.: `ev.tool_name` — `"Bash"`/`"PowerShell"`) so
 * importa para o caso `&` acima; quem nao passa preserva o comportamento de
 * antes (`&` nunca vira ilegivel por este motivo).
 *
 * Quem chama decide o que fazer com cada combinacao: `interno` legivel
 * (nao-null, `ilegivel: false`) e reprocessado como se fosse o proprio
 * comando; `ilegivel: true` (com ou sem `interno`) e tratado como INCERTO —
 * mesma postura conservadora que `$(`/crase solto ja recebe nos tres gates.
 */
function desempacotarWrapperDeString(segmento, { ferramenta } = {}) {
  const p1 = extrairPrimeiroToken(segmento);
  if (!p1) return { interno: null, ilegivel: false };
  const exe = normalizarNomeExecutavel(p1.tok);

  if (exe === "source" || exe === ".") {
    return { interno: null, ilegivel: true };
  }
  if (exe === "&" && ferramenta === "PowerShell") {
    // `& <caminho literal> args` e o mesmo comando que `<caminho> args`: o
    // call operator so existe porque o PowerShell nao executa string citada
    // sem ele (`& "C:\Program Files\nodejs\node.exe" --version`). Devolve o
    // resto como `interno`, e quem chama analisa como comando comum — `& git
    // add -A` continua barrando pelo git, nao pelo `&`. Mesma regra que `bash
    // ./x.sh` ja segue (D17). Continua ILEGIVEL o alvo que nao se le: script
    // block (`& { ... }`), subexpressao (`& (...)`), variavel ou crase fora de
    // aspas simples (`& $exe`, `& "$dir\x.exe"`). Barrado em 2026-09-22
    // conferindo o Node novo com o caminho escrito por extenso.
    const alvo = extrairPrimeiroToken(p1.resto);
    const naoSeLe = !alvo ||
      /^[{}()]$/.test(alvo.tok) ||
      /^[({]/.test(alvo.resto) ||
      (alvo.aspa !== "'" && /[$`@]/.test(alvo.tok));
    if (naoSeLe) return { interno: null, ilegivel: true };
    return { interno: p1.resto.trim(), ilegivel: false };
  }

  if (exe === "eval" || exe === "invoke-expression" || exe === "iex") {
    const interno = desempacota(p1.resto);
    return { interno, ilegivel: contemConstrucaoIlegivel(interno) };
  }

  const p2 = extrairPrimeiroToken(p1.resto);
  if (!p2) return { interno: null, ilegivel: false };

  if (exe === "pwsh" || exe === "powershell") {
    if (casaPrefixoDeFlag(p2.tok, "-encodedcommand")) {
      return { interno: null, ilegivel: true };
    }
    if (!casaPrefixoDeFlag(p2.tok, "-command")) return { interno: null, ilegivel: false };
    const interno = desempacota(p2.resto);
    return { interno, ilegivel: contemConstrucaoIlegivel(interno) };
  }

  if (exe === "cmd") {
    const flag = p2.tok.toLowerCase();
    if (flag !== "/c" && flag !== "/k") return { interno: null, ilegivel: false };
    const interno = desempacota(p2.resto);
    return { interno, ilegivel: contemConstrucaoIlegivel(interno) };
  }

  const flagEsperada = WRAPPERS_DE_COMANDO[exe];
  if (!flagEsperada) return { interno: null, ilegivel: false };

  // Aceita -c isolado ou flags curtas coladas terminando em c: -xc, -ec, etc.
  // Pula flags que começam com - ou + e não são a flag esperada, até
  // encontrá-la — flag com valor conhecida (W1: -o/+o/-O/+O/--rcfile/
  // --init-file) consome também o token seguinte, como o proprio valor.
  const curtas = CURTAS_COM_VALOR[exe];
  const longas = LONGAS_COM_VALOR[exe];
  let current = p2;
  while (current) {
    const tokLower = current.tok.toLowerCase();
    const ehFlagEsperada = tokLower === flagEsperada || /^-[a-z]*c$/i.test(current.tok);
    if (ehFlagEsperada) {
      const interno = desempacota(current.resto);
      return { interno, ilegivel: contemConstrucaoIlegivel(interno) };
    }
    // Se começa com - ou + mas não é a flag esperada, pula (e o valor dela,
    // se for flag reconhecida com valor) e tenta o próximo token.
    if (current.tok.startsWith("-") || current.tok.startsWith("+")) {
      const ehLonga = current.tok.startsWith("--");
      const consomeValor = ehLonga
        ? longas && longas.has(tokLower)
        : curtas && curtas.has(current.tok[current.tok.length - 1]);
      if (consomeValor) {
        const valor = extrairPrimeiroToken(current.resto);
        current = valor ? extrairPrimeiroToken(valor.resto) : null;
      } else {
        current = extrairPrimeiroToken(current.resto);
      }
      continue;
    }
    // Token que não começa com - nem +, não é flag conhecida nem o -c —
    // neste ponto é um CAMINHO DE SCRIPT (R21, rodada 15, lote 4, 2026-09-04).
    // Igual a `node x.cjs` e `./script.sh`, que ninguém bloqueia. Continua
    // ilegível: wrappers de ARQUIVO (source/./& PowerShell), flags -Command
    // base64 (-EncodedCommand), e construções com variável/substituição — as
    // três primeiras já saíram nos ramos acima; a última chega aqui, e é o que
    // a linha abaixo separa.
    //
    // O que D17 autoriza é parar de chamar de ilegível a execução de um ARQUIVO
    // — um caminho literal, que se pode ler. `bash $CMD` não é um caminho: é
    // uma variável não resolvida, e o que ela contém é exatamente o que ninguém
    // consegue ler aqui. Antes deste conserto ela caía junto com o caminho e os
    // três gates de texto liberavam em silêncio — e para wrapper conhecido não
    // existe a rede do W2 atrás, porque ela é pulada de propósito. Medido na
    // revisão do lote 4: `bash -c com aspas` barrava e `bash $CMD` passava.
    // O tokenizador separa chaves e parenteses em tokens proprios, entao
    // `${SCRIPT}` e `$(gerar)` chegam aqui como o token `$` sozinho, que nao
    // casa construcao nenhuma. O que se julga e a palavra INTEIRA: o token
    // mais o que vem colado nele ate o proximo espaco.
    // D2 (#309): variável citada com aspas duplas, sozinha, como ÚLTIMO
    // argumento (redirecionamento não conta) é um CAMINHO — mesmo tratamento
    // que um caminho literal (`./script.sh`) já recebe logo abaixo. Sem
    // aspas, ou com mais argumento depois, cai no `contemConstrucaoIlegivel`
    // de sempre.
    if (ehVariavelCitadaFinal(current)) {
      return { interno: null, ilegivel: false };
    }
    const coladoNoToken = /^[^\s]*/.exec(current.resto)[0];
    if (contemConstrucaoIlegivel(current.tok + coladoNoToken)) {
      return { interno: null, ilegivel: true };
    }
    return { interno: null, ilegivel: false };
  }
  return { interno: null, ilegivel: false };
}

module.exports = {
  tokensComAspas,
  ehComando,
  nomeDeWrapper,
  WRAPPERS_QUE_REPASSAM,
  OPERADORES_DE_DOIS,
  posicaoDeComando,
  textoAPartir,
  WRAPPERS_DE_COMANDO,
  desempacotarWrapperDeString,
  contemConstrucaoIlegivel,
  colapsaContinuacaoDeLinha,
  colapsaContinuacaoDeLinhaNoTopo,
};
