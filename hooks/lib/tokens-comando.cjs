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

/** Nome de comando, ignorando caminho: um binario com caminho resolve para seu nome. */
function ehComando(tok, nome) {
  return !tok.q && new RegExp("(^|[\\\\/])" + nome + "(\\.exe)?$").test(tok.v);
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
    if (i < toks.length && !toks[i].q && WRAPPERS_QUE_REPASSAM.has(toks[i].v)) {
      const wrapper = toks[i].v;
      i += 1;
      i = pularFlagsDoWrapper(toks, i, wrapper, captura);
      if (wrapper === "timeout" && i < toks.length) i += 1; // a duracao
      continue;
    }
    break;
  }
  return i < toks.length ? i : null;
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
 */
function extrairPrimeiroToken(str) {
  const m = /^\s*(?:"([^"]*)"|'([^']*)'|(\S+))/.exec(str);
  if (!m) return null;
  const tok = m[1] !== undefined ? m[1] : m[2] !== undefined ? m[2] : m[3];
  return { tok, resto: str.slice(m[0].length) };
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

/** Tira UM nivel de aspas externas de `interno`, se houver. */
function desempacota(interno) {
  interno = interno.trim();
  const aspas = /^"([\s\S]*)"$/.exec(interno) || /^'([\s\S]*)'$/.exec(interno);
  return aspas ? aspas[1] : interno;
}

/**
 * A string interna de um wrapper e ilegivel quando contem substituicao de
 * comando (`$(...)`, crase) ou variavel (`$X`, `${X}`) — nao da para saber
 * com seguranca o que vai rodar dentro. Postura conservadora.
 */
function contemConstrucaoIlegivel(str) {
  return /\$\(|`|\$[A-Za-z_{]/.test(str);
}

/**
 * Se `segmento` e uma invocacao de wrapper de STRING — `eval`,
 * `Invoke-Expression`/`iex` (PowerShell), `bash -c`/`sh -c`/`zsh -c`/
 * `ksh -c`/`dash -c`, `pwsh`/`powershell` com qualquer abreviacao de
 * `-Command` (`-c`, `-co`, `-com`, ...) ou `-EncodedCommand`, ou
 * `cmd /c`/`cmd /k` — devolve `{ interno, ilegivel }`:
 *
 *   - `interno`: a string de comando encapsulada (sem UM nivel de aspas
 *     externas, se houver), ou `null` se `segmento` nao e nenhum destes
 *     wrappers (nesse caso `ilegivel` e sempre `false`);
 *   - `ilegivel`: `true` quando o conteudo tem substituicao de comando ou
 *     variavel (`contemConstrucaoIlegivel`), OU quando o wrapper e
 *     `-EncodedCommand` (base64, ilegivel por definicao — `interno` vem
 *     `null` nesse caso, so `ilegivel` importa).
 *
 * Quem chama decide o que fazer com cada combinacao: `interno` legivel
 * (nao-null, `ilegivel: false`) e reprocessado como se fosse o proprio
 * comando; `ilegivel: true` (com ou sem `interno`) e tratado como INCERTO —
 * mesma postura conservadora que `$(`/crase solto ja recebe nos tres gates.
 */
function desempacotarWrapperDeString(segmento) {
  const p1 = extrairPrimeiroToken(segmento);
  if (!p1) return { interno: null, ilegivel: false };
  const exe = normalizarNomeExecutavel(p1.tok);

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
  // Pula flags que começam com - e não são a flag esperada, até encontrá-la.
  let current = p2;
  while (current) {
    const tokLower = current.tok.toLowerCase();
    const ehFlagEsperada = tokLower === flagEsperada || /^-[a-z]*c$/i.test(current.tok);
    if (ehFlagEsperada) {
      const interno = desempacota(current.resto);
      return { interno, ilegivel: contemConstrucaoIlegivel(interno) };
    }
    // Se começa com - mas não é a flag esperada, pula e tenta próximo token
    if (current.tok.startsWith("-")) {
      current = extrairPrimeiroToken(current.resto);
    } else {
      // Token que não começa com -, não é flag — para aqui
      break;
    }
  }
  return { interno: null, ilegivel: false };
}

module.exports = {
  tokensComAspas,
  ehComando,
  WRAPPERS_QUE_REPASSAM,
  posicaoDeComando,
  WRAPPERS_DE_COMANDO,
  desempacotarWrapperDeString,
  contemConstrucaoIlegivel,
};
