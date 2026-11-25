/**
 * Extração e análise de corpos de heredoc.
 * Decisões D1 e D2 (zerar-issues-4, 2026-09-14).
 */

const {
  tokensComAspas, posicaoDeComando, textoAPartir,
} = require("./tokens-comando.cjs");

// Comandos para os quais o corpo de um heredoc (ou a string de um here-string)
// é script, não dado (D1 do zerar-issues-3).
const INTERPRETADORES_DE_HEREDOC = ["bash", "sh", "zsh", "ksh", "dash", "pwsh", "powershell", "cmd", "eval", "source", "."];

/**
 * Normaliza o nome de um executável: remove caminho, extensão e aspas.
 * Exemplos: `gh`, `gh.exe`, `gh.cmd`, `"gh"`, `C:\x\gh.exe` → `gh`
 */
function normalizarExecutavel(nome) {
  const path = require("node:path");
  let sem_aspas = nome.replace(/^["']|["']$/g, "");
  sem_aspas = path.basename(sem_aspas);
  sem_aspas = sem_aspas.replace(/\.(exe|cmd|bat)$/i, "");
  return sem_aspas.toLowerCase();
}

// Fim da linha LÓGICA a partir de `i`: a primeira quebra de linha que não
// vem precedida de `\` (continuação). Sétima revisão (2026-09-13):
// `cat <<'EOF' \` + `| bash` na linha de baixo é UMA linha para o bash, e o
// corpo começa depois da segunda quebra — a versão anterior parava na
// primeira e o `| bash` virava corpo, invisível.
//
// Revisao 1 do zerar-issues-17: a varredura e de verdade, nao "quebra precedida de
// `\`". `\\` + quebra e contrabarra escapada (a linha acaba ali); `#` em inicio de
// palavra abre comentario, onde `\` nao continua nada; quebra dentro de aspas ou de
// `$(...)` nao encerra a linha. Nos tres casos o bash abria o corpo em outro lugar.
function fimDaLinhaLogica(cmd, i) {
  let simples = false;
  let duplas = false;
  let sub = 0;
  for (let k = i; k < cmd.length; k++) {
    const c = cmd[k];
    if (simples) { if (c === "'") simples = false; continue; }
    if (c === '\\') { k++; continue; }
    if (duplas) { if (c === '"') duplas = false; continue; }
    if (c === '$' && cmd[k + 1] === "'") {
      for (k += 2; k < cmd.length && cmd[k] !== "'"; k++) if (cmd[k] === '\\') k++;
      continue;
    }
    if (c === "'") { simples = true; continue; }
    if (c === '"') { duplas = true; continue; }
    if (c === '$' && cmd[k + 1] === '(') { sub++; k++; continue; }
    if (c === ')' && sub > 0) { sub--; continue; }
    if (c === '#' && (k === 0 || /[\s;|&()]/.test(cmd[k - 1]))) {
      const q = cmd.indexOf('\n', k);
      if (q === -1) return -1;
      if (sub === 0) return q;
      k = q;
      continue;
    }
    if (c === '\n' && sub === 0) return k;
  }
  return -1;
}

/**
 * A LINHA que abre o heredoc/here-string em `i` tem um interpretador em
 * qualquer posição? Sexta revisão do zerar-issues-3 (2026-09-13): decidir
 * pelo comando que recebe o `<<` deixou passar `(bash) <<EOF`, `{ bash; }
 * <<EOF` e `cat <<EOF | bash` — em todos o corpo acaba executado, e o
 * comando "dono" do heredoc não é `bash`. A regra conservadora é olhar a
 * linha inteira (do `\n` anterior ao `\n` que abre o corpo): se `bash`,
 * `sh`, `eval`… aparecem em qualquer token, o corpo é script. `cat <<EOF >
 * d.md` e `tee x <<EOF` continuam dado. Parênteses, chaves, `;`, `|`, `&`
 * são tirados dos tokens antes de comparar; wrappers e caminhos
 * (`/bin/bash`, `bash.exe`) passam por `normalizarExecutavel`.
 */
function linhaDoHeredocTemInterpretador(cmd, i) {
  let ini = i;
  while (ini > 0 && cmd[ini - 1] !== '\n') ini--;
  let fim = fimDaLinhaLogica(cmd, i);
  if (fim === -1) fim = cmd.length;
  const linha = cmd.slice(ini, fim);
  let toks;
  try { toks = tokensComAspas(linha).map((t) => t.v); } catch { toks = linha.split(/\s+/); }
  for (const t of toks) {
    for (const pedaco of String(t).split(/[|;&(){}]+/)) {
      if (pedaco && INTERPRETADORES_DE_HEREDOC.includes(normalizarExecutavel(pedaco))) return true;
    }
  }
  return false;
}

/**
 * Extrai o comando (primeiro token) da linha que contém o `<<` da posição `i`.
 * Procura para trás até encontrar um separador (`;`, `&&`, `||`, `|`, `(`) ou início.
 * Normaliza o comando (remove caminho, extensão, minúsculo).
 */
function extrairComandoDoHeredoc(cmd, i) {
  // Encontrar o início da linha
  let inicioLinha = i;
  while (inicioLinha > 0 && cmd[inicioLinha - 1] !== '\n') {
    inicioLinha--;
  }

  const textoAteHeredoc = cmd.slice(inicioLinha, i);
  let inicioComando = 0;

  // Procurar para trás pelos separadores
  for (let k = textoAteHeredoc.length - 1; k >= 0; k--) {
    const c = textoAteHeredoc[k];
    if (c === ';' || c === '|' || c === '(') {
      inicioComando = k + 1;
      break;
    }
    // Detectar `&&` e `||`
    if (c === '&' && k > 0 && textoAteHeredoc[k - 1] === '&') {
      inicioComando = k + 1;
      break;
    }
    if (c === '|' && k > 0 && textoAteHeredoc[k - 1] === '|') {
      inicioComando = k + 1;
      break;
    }
  }

  // Pular espaços
  while (inicioComando < textoAteHeredoc.length && (textoAteHeredoc[inicioComando] === ' ' || textoAteHeredoc[inicioComando] === '\t')) {
    inicioComando++;
  }

  // Quinta revisão do zerar-issues-3 (2026-09-13): o comando que recebe o
  // heredoc pode vir atrás de um wrapper que repassa stdin (`env bash`,
  // `command bash`, `nohup bash`, `timeout 5 bash`, `sudo bash`) — o primeiro
  // token literal era `env`, nunca batia na lista de interpretadores, e o
  // corpo virava dado. Mesma resolução de wrapper que o resto do gate usa
  // (`posicaoDeComando`, de lib/tokens-comando.cjs).
  const trecho = textoAteHeredoc.slice(inicioComando);
  let toks = null;
  try { toks = tokensComAspas(trecho); } catch { toks = null; }
  if (toks && toks.length) {
    const pos = posicaoDeComando(toks);
    if (pos !== null) return normalizarExecutavel(toks[pos].v);
  }

  // Sem tokens legíveis: o primeiro token literal, como antes
  let comando = '';
  for (let k = inicioComando; k < textoAteHeredoc.length && textoAteHeredoc[k] !== ' ' && textoAteHeredoc[k] !== '\t' && textoAteHeredoc[k] !== '\n'; k++) {
    comando += textoAteHeredoc[k];
  }

  return normalizarExecutavel(comando);
}

/**
 * Extrai o corpo de um heredoc a partir da posição `i`.
 * Recebe `cmd[i..]` começando por `<<` ou `<<-` seguido de delimitador
 * (nu, entre aspas simples ou duplas).
 * Retorna `{ fim, corpo, comando }` ou `null` se não há heredoc.
 *
 * `fim` = índice logo após a linha do delimitador de fechamento
 * `corpo` = texto entre a linha do `<<` e a linha de fechamento
 * `comando` = primeiro token (nome executável normalizado, minúsculo) do comando
 *
 * Se o delimitador nunca aparece, trata todo o resto como corpo.
 */
function corpoDeHeredoc(cmd, i) {
  if (cmd[i] !== '<' || cmd[i + 1] !== '<') return null;
  // `<<<` é here-string: a string vem na mesma linha, não há corpo nem linha de
  // fechamento, e a linha seguinte é comando novo (terceira revisão do
  // zerar-issues-3, 2026-09-13: `cat <<<bar\ngh issue close 12` era lido como
  // heredoc de delimitador `<bar`, que nunca fecha, e o `gh` virava corpo).
  if (cmd[i + 2] === '<' || (i > 0 && cmd[i - 1] === '<')) return null;

  let j = i + 2;
  const tiraTabs = cmd[j] === '-';
  if (tiraTabs) j++;

  // Pular espaços antes do delimitador
  while (j < cmd.length && (cmd[j] === ' ' || cmd[j] === '\t')) j++;

  // Extrair delimitador (nu, simples ou duplas)
  let delimitador = '';
  let tipoAspa = null;
  if (cmd[j] === "'" || cmd[j] === '"') {
    tipoAspa = cmd[j];
    j++;
    while (j < cmd.length && cmd[j] !== tipoAspa) {
      delimitador += cmd[j];
      j++;
    }
    if (j < cmd.length && cmd[j] === tipoAspa) j++;
  } else {
    // Delimitador nu — até espaço, quebra de linha ou fim
    while (j < cmd.length && cmd[j] !== ' ' && cmd[j] !== '\t' && cmd[j] !== '\n' && cmd[j] !== ';' && cmd[j] !== '&' && cmd[j] !== '|' && cmd[j] !== ')' && cmd[j] !== '<' && cmd[j] !== '>') {
      delimitador += cmd[j];
      j++;
    }
  }

  if (!delimitador) return null;

  // Encontrar o início do corpo (fim da linha lógica — `\`+quebra continua)
  const inicioCorpo = fimDaLinhaLogica(cmd, i);
  if (inicioCorpo === -1) {
    // Sem quebra de linha após `<<`, todo resto é "corpo" vazio
    return {
      fim: cmd.length,
      corpo: '',
      comando: extrairComandoDoHeredoc(cmd, i),
      delimitadorQuotado: tipoAspa !== null,
      fechado: false
    };
  }

  // Procurar a linha de fechamento
  let corpo = '';
  let linhaAtual = '';
  let fim = cmd.length;
  let achouFechamento = false;
  let k = inicioCorpo + 1;

  while (k < cmd.length) {
    const char = cmd[k];
    if (char === '\n') {
      // Verificar se a linha atual é o delimitador (exatamente, sem espaços).
      // Com `<<-` o bash tira as TABULAÇÕES à esquerda da linha de fechamento
      // antes de comparar (segunda revisão do zerar-issues-3, 2026-09-13:
      // `cat <<-EOF\n\tcorpo\n\tEOF\ngh issue close 12` fechava no `\tEOF` de
      // verdade e o gate, comparando exato, lia o `gh` como corpo e liberava).
      // Espaços não contam — nem para o bash.
      const linhaComparada = tiraTabs ? linhaAtual.replace(/^\t+/, '') : linhaAtual;
      if (linhaComparada === delimitador) {
        fim = k + 1;
        achouFechamento = true;
        break;
      }
      corpo += linhaAtual + '\n';
      linhaAtual = '';
      k++;
    } else {
      linhaAtual += char;
      k++;
    }
  }

  // Se saiu do loop sem encontrar o delimitador, adiciona a última linha ao corpo
  if (fim === cmd.length && linhaAtual) {
    // Sem quebra de linha final, o laco nunca compara a ultima linha. Ela
    // ainda pode ser o delimitador: um heredoc citado cujo texto termina em
    // EOF sem quebra depois FECHA no bash, e precisa contar como fechado.
    // So a marca muda; `fim` e `corpo` ficam como estavam, para nao alterar
    // o comportamento de quem ja consome os tres campos (gate-fechar-issue).
    if ((tiraTabs ? linhaAtual.replace(/^\t+/, '') : linhaAtual) === delimitador) {
      achouFechamento = true;
    } else {
      corpo += linhaAtual;
    }
  }

  return {
    fim: fim,
    corpo: corpo,
    comando: extrairComandoDoHeredoc(cmd, i),
    // Campos ACRESCENTADOS (zerar-issues-4, segunda revisao). Os tres acima
    // mantem nome, tipo e valor: quem so le `fim`/`corpo`/`comando` nao muda.
    // Quem decide MASCARAR precisa dos dois abaixo -- ver a nota em
    // `mascararCorposDeHeredoc`, abaixo neste arquivo.
    delimitadorQuotado: tipoAspa !== null,
    fechado: achouFechamento
  };
}

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
    // Revisao 1 do zerar-issues-17: `$'...'` (onde `\'` nao fecha) e `${...}` nao
    // abrem heredoc (`echo ${x:-<<'A'}`).
    if (!simples && !duplas && c === "$" && cmd[k + 1] === "'") {
      for (k += 2; k < cmd.length && cmd[k] !== "'"; k++) if (cmd[k] === "\\") k++;
      continue;
    }
    // Dentro de `${...}`, chave entre aspas ou escapada nao conta (`${x:-"}"<<'A'}`:
    // a expansao so fecha na ultima chave; revisao de seguranca automatica).
    if (!simples && !duplas && c === "$" && cmd[k + 1] === "{") {
      let d = 0;
      let s1 = false;
      let s2 = false;
      for (k += 1; k < cmd.length; k++) {
        const x = cmd[k];
        if (s1) { if (x === "'") s1 = false; continue; }
        if (x === "\\") { k++; continue; }
        if (s2) { if (x === '"') s2 = false; continue; }
        // `$'...'` dentro de `${...}` tambem e ANSI-C: `\'` nao fecha (revisao 2).
        if (x === "$" && cmd[k + 1] === "'") {
          for (k += 2; k < cmd.length && cmd[k] !== "'"; k++) if (cmd[k] === "\\") k++;
          continue;
        }
        if (x === "'") s1 = true;
        else if (x === '"') s2 = true;
        else if (x === "{") d++;
        else if (x === "}" && --d === 0) break;
      }
      continue;
    }
    if (!simples && c === "\\") { k++; continue; }
    if (!duplas && c === "'") { simples = !simples; continue; }
    if (!simples && c === '"') { duplas = !duplas; continue; }
    if (simples || duplas) continue;
    if (c === "#") {
      const antes = k === 0 ? "" : cmd[k - 1];
      if (k === 0 || " \t\n;|&()".includes(antes)) {
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

// D7 (zerar-issues-17): operador colado ao nome se separa antes da busca do alvo.
// `tokensComAspas` devolve `t.sh;` e `t.cjs|sh` como um token so, e `bash t.sh; true`
// atravessava o gate. O digito de descritor so conta no COMECO do token (`2>log` e
// `2>` + `log`); `t2>log` e `t2` + `>` + `log`, como no bash. `2>&1`, `>&2` e `&>`
// ficam inteiros: sao redirecionamento, nao o `&` de segundo plano. `<<`, `<<-` e
// `<<<` tambem: abrem heredoc e here-string, com o delimitador ou a string depois.
const RE_OPERADOR_COLADO = /(^\d+[<>]&\d*-?|[<>]&\d*-?|&>>?|<<<|<<-?|^\d+>[>|]?|^\d+<|>[>|]?|<|[|;&(){}]+)/;
// Redirecionamento cujo ALVO e o token seguinte (`<`, `0<`, `>`, `2>>`, `>|`, `&>`, `<<`).
const RE_REDIR_COM_ALVO = /^(?:\d*(?:<|>[>|]?)|&>>?|<<-?|<<<)$/;
// Redirecionamento que ja traz o alvo (`2>&1`, `>&2`, `<&0`, `2>&-`).
const RE_REDIR_FECHADO = /^\d*[<>]&\d*-?$/;
const ehOperador = (t) => /^[|;&(){}]+$/.test(t);
const ehFlag = (t) => t.startsWith("-") || /^\+[A-Za-z]+$/.test(t);
// Prefixos que rodam o comando seguinte (`sudo sh < t.cjs`, `cat t | env sh`).
const PREFIXOS_DE_COMANDO = new Set(["sudo", "env", "command", "exec", "nohup", "nice", "time", "timeout", "builtin", "xargs", "watch", "strace", "setsid", "stdbuf", "ionice", "chrt"]);
// Flags que levam valor no token seguinte. Depois do comando: `bash -o pipefail t.sh`,
// `python -W ignore t.py`, `node -r x t.cjs` (revisao 1). Antes dele, as dos prefixos:
// `sudo -u x sh`, `env -C d sh`, `timeout -s KILL 5 sh`, `nice -n 5 sh`.
const FLAGS_COM_VALOR = new Set(["-o", "+o", "-O", "+O", "--rcfile", "--init-file", "-W", "-X", "-r", "--require", "--import", "--loader", "--experimental-loader", "-I"]);
const FLAGS_COM_VALOR_DE_PREFIXO = new Set(["-u", "-g", "-C", "-s", "-k", "-n", "--chdir", "--user", "--group", "--signal", "--kill-after", "--adjustment"]);

const separarOperadores = (t) => String(t).split(RE_OPERADOR_COLADO).filter(Boolean);

// Ferramentas cujo `-c` leva dado, nao comando (`grep -c` conta linhas). Lista de
// excecao, nao de shells: `su -c`, `fish -c`, `flock f -c` e `runuser -c` tambem rodam
// texto, e o padrao segue fechado (revisao de seguranca automatica da revisao 2).
const C_DE_DADO = new Set(["grep", "egrep", "fgrep", "rg", "ag", "wc", "head", "tail", "cut", "uniq", "ls", "tr", "cmp", "git"]);

/**
 * O proximo token, logo depois de `saida`, e texto de comando? Depois de `eval`, ou
 * de `-c`/`/c`, salvo quando o comando do trecho (primeiro token que nao e
 * atribuicao) e ferramenta de `C_DE_DADO` (achado 12 da revisao 2).
 */
function proximoEhTextoDeComando(saida) {
  const ant = saida[saida.length - 1];
  if (ant === undefined) return false;
  if (normalizarExecutavel(ant) === "eval") return true;
  if (!/^-\w*c\w*$/i.test(ant) && !/^\/c$/i.test(ant)) return false;
  let ini = saida.length - 1;
  while (ini > 0 && !ehOperador(saida[ini - 1])) ini--;
  while (ini < saida.length - 1 && /^[A-Za-z_]\w*=/.test(saida[ini])) ini++;
  return !C_DE_DADO.has(normalizarExecutavel(saida[ini]));
}

/**
 * Tokens de `texto` com o operador colado separado (D7) e a quebra de linha entre
 * dois tokens virando `;` (separa comandos). A continuacao `\`+quebra some antes.
 * Texto passado a `eval` ou ao `-c` de um shell (`bash -c 'cd . && bash t.sh'`) e
 * comando: entra tokenizado de novo, entre `;`, ANTES de qualquer corte por operador
 * (revisao 1; na revisao 2 o corte vinha antes e partia o texto no `&&`).
 */
function tokensSeparados(texto) {
  const limpo = String(texto).replace(/\\\r?\n/g, " ");
  let brutos;
  try { brutos = tokensComAspas(limpo); } catch {
    return limpo.replace(/\n/g, " ; ").split(/\s+/).flatMap(separarOperadores);
  }
  const saida = [];
  let anterior = null;
  for (const t of brutos) {
    if (anterior && typeof anterior.fim === "number" && typeof t.ini === "number" && limpo.slice(anterior.fim, t.ini).includes("\n")) saida.push(";");
    const v = String(t.v);
    if (/\s/.test(v) && proximoEhTextoDeComando(saida)) saida.push(";", ...tokensSeparados(v), ";");
    else saida.push(...separarOperadores(v));
    anterior = t;
  }
  return saida;
}

// Nome-base de um token de arquivo: sem aspas nas pontas, sem diretorio.
function nomeBase(t) {
  return String(t).replace(/^["']+|["']+$/g, "").split(/[\\/]/).pop();
}

// `[ini, fim)` do trecho (comando simples, entre operadores) que contem `k`.
function trechoEm(toks, k) {
  let ini = k;
  while (ini > 0 && !ehOperador(toks[ini - 1])) ini--;
  let fim = k;
  while (fim < toks.length && !ehOperador(toks[fim])) fim++;
  return [ini, fim];
}

/**
 * Comando e argumentos de `toks[ini..fim)`: pula atribuicao (`X=1`), redirecionamento
 * (com o alvo dele) e prefixo que roda o comando seguinte (`sudo`, `env`, `timeout 5`),
 * com as flags de valor deles. Devolve `{ nome, nomeIdx, posicionais, flags,
 * stdinComoScript }`: `nome` normalizado (ou null) e o indice do token dele, os
 * INDICES dos posicionais, as flags depois do comando, e se um `-` veio antes de
 * qualquer posicional (`node - arg`: o script e o stdin).
 */
function lerTrecho(toks, ini, fim) {
  let nome = null;
  let nomeIdx = -1;
  let stdinComoScript = false;
  const posicionais = [];
  const flags = [];
  for (let j = ini; j < fim; j++) {
    const t = toks[j];
    if (RE_REDIR_COM_ALVO.test(t)) { j++; continue; }
    if (RE_REDIR_FECHADO.test(t)) continue;
    if (nome === null) {
      if (FLAGS_COM_VALOR_DE_PREFIXO.has(t)) { j++; continue; }
      if (/^\w+=/.test(t) || ehFlag(t) || /^\d+[smhd]?$/.test(t)) continue;
      const n = normalizarExecutavel(t);
      if (PREFIXOS_DE_COMANDO.has(n)) continue;
      nome = n;
      nomeIdx = j;
      continue;
    }
    // `deno run t.ts`, `bun run t.ts`: o subcomando nao e o script.
    if ((nome === "deno" || nome === "bun") && t === "run" && posicionais.length === 0) continue;
    if (t === "-" && posicionais.length === 0) { stdinComoScript = true; flags.push(t); continue; }
    if (FLAGS_COM_VALOR.has(t)) { flags.push(t); j++; continue; }
    if (ehFlag(t)) flags.push(t);
    else posicionais.push(j);
  }
  return { nome, nomeIdx, posicionais, flags, stdinComoScript };
}

const SHELLS_COM_S = new Set(["bash", "sh", "zsh", "ksh", "dash"]);

// D2: executor que le o script do STDIN. Sem posicional (`sh`, `bash -x`), com `-s`
// num shell (`sh -s arg`: os posicionais sao argumentos do script), ou com o
// "arquivo" sendo o proprio stdin (`node - arg`, `bash /dev/stdin`). Com arquivo de
// script proprio (`python script.py < dados.txt`, `python tool.py -`), o stdin e
// dado do script.
function executorDeStdin(trecho, toks) {
  if (!trecho.nome || !EXECUTAM_ARQUIVO.has(trecho.nome)) return null;
  if (trecho.posicionais.length === 0) return trecho.nome;
  if (trecho.stdinComoScript) return trecho.nome;
  if (SHELLS_COM_S.has(trecho.nome) && trecho.flags.some((x) => /^-[a-z]*s[a-z]*$/i.test(x))) return trecho.nome;
  if (toks[trecho.posicionais[0]] === "/dev/stdin") return trecho.nome;
  return null;
}

/**
 * O alvo em `k` e o arquivo de script de um executor? Duas leituras, qualquer uma
 * basta: o alvo e o primeiro posicional de um trecho cujo comando executa arquivo
 * (`sudo bash t.sh`, `bash -o pipefail t.sh`), ou o token que vem antes dele --
 * pulando flags, valor de flag e redirecionamento (`bash 2>/dev/null t.sh`, `bash
 * 2>&1 t.sh`) -- e um executor (`find . -exec bash t.sh`). Alvo que e destino de
 * redirecionamento (`cat x > t.sh`) nao e argumento.
 */
function executorAntes(toks, k, ini, trecho) {
  if (k > ini && RE_REDIR_COM_ALVO.test(toks[k - 1])) return null;
  if (trecho.nome && EXECUTAM_ARQUIVO.has(trecho.nome) && trecho.posicionais[0] === k) return trecho.nome;
  for (let j = k - 1; j >= ini; j--) {
    const t = toks[j];
    if (ehFlag(t) || RE_REDIR_FECHADO.test(t)) continue;
    if (j - 1 >= ini && (RE_REDIR_COM_ALVO.test(toks[j - 1]) || FLAGS_COM_VALOR.has(toks[j - 1]))) { j--; continue; }
    const n = normalizarExecutavel(t);
    return EXECUTAM_ARQUIVO.has(n) ? n : null;
  }
  return null;
}

/**
 * Nomes-base dos arquivos que a linha logica do heredoc em `i` grava: alvo de `>`,
 * `>>` e `>|`, com ou sem espaco antes (`cat>t.sh`), e os arquivos de `tee`
 * (`tee t.sh <<'A' > /dev/null`, revisao 1).
 */
function alvosDaLinha(cmd, i) {
  let ini = i;
  while (ini > 0 && cmd[ini - 1] !== "\n") ini--;
  let fimLinha = fimDaLinhaLogica(cmd, i);
  if (fimLinha === -1) fimLinha = cmd.length;
  const linha = cmd.slice(ini, fimLinha);
  const alvos = new Set();
  const re = /\d?>[>|]?\s*([^\s;|&<>()]+)/g;
  let m;
  while ((m = re.exec(linha)) !== null) {
    const base = nomeBase(m[1]);
    if (base) alvos.add(base);
  }
  const toks = tokensSeparados(linha);
  for (let a = 0; a < toks.length; ) {
    const [, fim] = trechoEm(toks, a);
    const t = lerTrecho(toks, a, fim);
    if (t.nome === "tee") for (const j of t.posicionais) { const b = nomeBase(toks[j]); if (b) alvos.add(b); }
    a = fim + 1;
  }
  return alvos;
}

const COPIAM_ARQUIVO = new Set(["cp", "mv", "ln", "install"]);

// O trecho le algum alvo, como argumento ou como stdin (`cat t.sh`, `cat < t.sh`)?
function trechoLeAlvo(toks, ini, fim, trecho, alvos) {
  if (trecho.posicionais.some((j) => alvos.has(nomeBase(toks[j])))) return true;
  for (let j = ini; j < fim - 1; j++) {
    if (ehRedirecionamentoDeEntrada(toks[j]) && alvos.has(nomeBase(toks[j + 1]))) return true;
  }
  return false;
}

/**
 * D3 (zerar-issues-17): o conteudo gravado chega ao executor por outro nome.
 * `cp`/`mv`/`ln`/`install` com um alvo entre as origens acrescentam o nome-base do
 * destino; `cat <alvo> > <novo>` e `cat < <alvo> > <novo>` acrescentam `<novo>`.
 * Repete ate nao crescer (`cp a b; mv b c`), com teto de 10 voltas.
 */
function expandirAlvosPorCopia(toks, alvos) {
  for (let volta = 0; volta < 10; volta++) {
    const antes = alvos.size;
    for (let ini = 0; ini < toks.length; ) {
      const [, fim] = trechoEm(toks, ini);
      const trecho = lerTrecho(toks, ini, fim);
      const { nome, posicionais } = trecho;
      if (COPIAM_ARQUIVO.has(nome) && posicionais.length >= 2) {
        const origens = posicionais.slice(0, -1).map((j) => nomeBase(toks[j]));
        const destino = nomeBase(toks[posicionais[posicionais.length - 1]]);
        if (destino && origens.some((b) => alvos.has(b))) alvos.add(destino);
      } else if (nome === "cat" && trechoLeAlvo(toks, ini, fim, trecho, alvos)) {
        for (let j = ini; j < fim - 1; j++) {
          if (/^(?:\d*>[>|]?|&>>?)$/.test(toks[j])) {
            const destino = nomeBase(toks[j + 1]);
            if (destino) alvos.add(destino);
          }
        }
      }
      ini = fim + 1;
    }
    if (alvos.size === antes) break;
  }
}

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
 *    como execucao o que `executoresDoAlvo` reconhece.
 *
 * D4 (zerar-issues-17): e a MESMA regua de `executoresDoAlvo`. As duas repetiam a
 * varredura; com stdin, pipe e copia so numa delas, o corpo podia ser mascarado
 * como dado com executor achado pela outra.
 */
function alvoDoRedirecionamentoEhExecutadoDepois(cmd, i, fimDoHeredoc) {
  return executoresDoAlvo(cmd, i, fimDoHeredoc).length > 0;
}

/**
 * Interpretadores que EXECUTAM o arquivo gravado por heredoc sem ser shell
 * (gates-sem-ruido D6). O corpo deles e codigo de outra linguagem: um `git`
 * dentro de string JS nao e comando. Shell fica fora de proposito -- `bash
 * x.sh` segue com o script inteiro analisado.
 */
const INTERPRETADORES_NAO_SHELL = new Set(["node", "python", "python3", "py", "perl", "ruby", "deno", "bun"]);

// D2: executores de stdin na mesma pipeline depois de `toks[fim]` (`| head | bash`,
// `| tee o | sh`, `| (sh)`, `| { sh; }`). Para no primeiro operador que nao e pipe
// nem agrupamento.
function executoresDaPipeline(toks, fim) {
  const achados = [];
  let p = fim;
  while (p < toks.length && (toks[p] === "|" || toks[p] === "|&")) {
    p++;
    while (p < toks.length && /^[({]+$/.test(toks[p])) p++;
    const [ini2, fim2] = trechoEm(toks, p);
    const ex = executorDeStdin(lerTrecho(toks, ini2, fim2), toks);
    if (ex) achados.push(ex);
    p = fim2;
    while (p < toks.length && /^[)}]+$/.test(toks[p])) p++;
  }
  return achados;
}

/**
 * Quem EXECUTA o arquivo que o heredoc em `i` grava? `"./"` para execucao por
 * caminho, o nome normalizado do comando nos outros casos. Vazio = nenhum executor.
 *
 * Le o resto da linha que abre o heredoc, depois do `<<` (D8: `cat > t.cjs <<'EOF'
 * && node t.cjs` roda depois do corpo gravado), e o texto depois do fechamento. O
 * arquivo conta como executado quando (zerar-issues-17):
 * - e o comando do trecho, com caminho (`./x`, `../x`, `d/x`, `$PWD/x`, `/tmp/x`) (D9);
 * - e o arquivo de script de um executor, pulando flags e redirecionamentos;
 * - e o stdin (`<`) de um executor que le o script do stdin (D2);
 * - e lido (argumento ou stdin) por um trecho que segue por pipe ate um executor
 *   assim (D2);
 * - chega a qualquer um desses por outro nome, via copia (D3);
 * - aparece no texto de `eval` ou `-c` (revisao 1).
 */
function executoresDoAlvo(cmd, i, fimDoHeredoc) {
  const alvos = alvosDaLinha(cmd, i);
  const executores = [];
  if (alvos.size === 0) return executores;

  let fimLinha = fimDaLinhaLogica(cmd, i);
  if (fimLinha === -1) fimLinha = cmd.length;
  const restoDaLinha = cmd.slice(i, Math.min(fimLinha, cmd.length));
  const depois = cmd.slice(Math.min(fimDoHeredoc, cmd.length));
  const toks = tokensSeparados(restoDaLinha + "\n" + depois);
  expandirAlvosPorCopia(toks, alvos);

  for (let k = 0; k < toks.length; k++) {
    const t = toks[k];
    const base = nomeBase(t);
    if (!base || !alvos.has(base)) continue;
    const [ini, fim] = trechoEm(toks, k);
    const trecho = lerTrecho(toks, ini, fim);
    // `./x` em qualquer posicao (`find . -exec ./t.sh`), como antes da rodada; e
    // caminho na posicao de comando (`../t.sh`, `$PWD/t.sh`) (D9).
    if (/^\.[\\/]/.test(t.replace(/^["']+/, "")) || (trecho.nomeIdx === k && /[\\/]/.test(t))) { executores.push("./"); continue; }
    if (k > ini && ehRedirecionamentoDeEntrada(toks[k - 1])) {
      const ex = executorDeStdin(trecho, toks);
      if (ex) { executores.push(ex); continue; }
    } else {
      const ex = executorAntes(toks, k, ini, trecho);
      if (ex) { executores.push(ex); continue; }
    }
    if (trechoLeAlvo(toks, ini, fim, trecho, alvos)) executores.push(...executoresDaPipeline(toks, fim));
  }
  return executores;
}

function ehRedirecionamentoDeEntrada(t) {
  return /^\d*<$/.test(t);
}

/**
 * Revisao 1 (zerar-issues-17): o heredoc e o STDIN de um interpretador nao-shell que
 * le o script dele (`node - <<'A'`, `python <<'A'`). Devolve o nome, ou null.
 */
function interpretadorNaoShellDoHeredoc(cmd, i) {
  let ini = i;
  while (ini > 0 && cmd[ini - 1] !== "\n") ini--;
  let fimLinha = fimDaLinhaLogica(cmd, i);
  if (fimLinha === -1) fimLinha = cmd.length;
  const L = tokensSeparados(cmd.slice(ini, i) + "<<").length - 1;
  const toks = tokensSeparados(cmd.slice(ini, fimLinha));
  if (L < 0 || !/^<<-?$/.test(toks[L] || "")) return null;
  const [a, z] = trechoEm(toks, L);
  const ex = executorDeStdin(lerTrecho(toks, a, z), toks);
  return ex && INTERPRETADORES_NAO_SHELL.has(ex) ? ex : null;
}

/**
 * D5 (zerar-issues-17): `spawnSync('git',['add','-A'])`, `subprocess.run(["git",
 * "add", "-A"])` e `new Deno.Command('git', {args: ['add', '-A']})` -- o comando em
 * lista de strings. Acha cada literal `git` entre aspas (com caminho e `.exe`:
 * `'/usr/bin/git'`, `'git.exe'`) e o estende enquanto vier, depois de espacos,
 * quebras de linha, virgulas, colchetes, chaves, parenteses, comentario de bloco e
 * chave de objeto (`args:`), outro literal completo de mesma aspa na abertura e no
 * fechamento. Devolve `{ ini, fim, conteudos }`: o intervalo inteiro e o miolo de
 * cada literal.
 */
function trechosDeListaGit(texto) {
  const achados = [];
  const re = /(['"`])((?:[^'"`\n]*[\\/])?git(?:\.exe)?)\1/gi;
  const seguinte = /^(?:[\s,[\](){}]|\/\*[\s\S]*?\*\/|\w+\s*:)*(['"`])([^'"`\n]*)\1/;
  let m;
  while ((m = re.exec(texto)) !== null) {
    const conteudos = [[m.index + 1, m.index + 1 + m[2].length]];
    let fim = m.index + m[0].length;
    let s;
    while ((s = seguinte.exec(texto.slice(fim))) !== null) {
      const fimLiteral = fim + s[0].length;
      conteudos.push([fimLiteral - 1 - s[2].length, fimLiteral - 1]);
      fim = fimLiteral;
    }
    achados.push({ ini: m.index, fim, conteudos });
    re.lastIndex = fim;
  }
  return achados;
}

/**
 * Corpo de script nao-shell: tudo fica em branco, exceto os trechos `git ...`
 * (ate aspa, `;`, `|`, `&`, `)` ou fim de linha) e o comando em lista de strings
 * (D5): ali so o miolo de cada literal fica, e o resto do intervalo -- aspas,
 * virgulas, colchetes, comentario, chave de objeto, quebra de linha -- vira espaco,
 * para a analise ler um comando so. Comprimento preservado; as quebras de linha de
 * fora da lista tambem.
 */
function mascaraSoGit(trecho) {
  const chars = trecho.replace(/[^\n]/g, " ").split("");
  const re = /\bgit\b[^'"`;|&)\n]*/g;
  let m;
  while ((m = re.exec(trecho)) !== null) {
    for (let k = m.index; k < m.index + m[0].length; k++) chars[k] = trecho[k];
  }
  for (const lista of trechosDeListaGit(trecho)) {
    for (let k = lista.ini; k < lista.fim; k++) chars[k] = " ";
    for (const [a, z] of lista.conteudos) {
      for (let k = a; k < z; k++) chars[k] = trecho[k] === "\n" ? " " : trecho[k];
    }
  }
  return chars.join("");
}

// #724 (zerar-issues-17): o corpo comeca depois da linha LOGICA que abre o heredoc,
// como em `corpoDeHeredoc`. Com `cat <<'A' \` + quebra + `> x; git add -A`, a mascara
// comecava na primeira quebra fisica e apagava o comando da continuacao.
function inicioDoCorpo(fora, i) {
  const fl = fimDaLinhaLogica(fora, i);
  return fl === -1 ? fora.length : fl + 1;
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
 *
 * Opcao `{ scriptNaoShell: true }` (gates-sem-ruido D6). Sem ela, o resultado e o
 * de sempre. Com ela, um corpo que as quatro condicoes deixariam ANALISADO como
 * shell -- porque o arquivo que ele grava e executado depois -- passa a ser
 * mascarado quando TODO executor desse arquivo e interpretador nao-shell
 * (`node x.cjs`, `python x.py`): so os trechos `git ...` ficam visiveis. Ex.:
 * `cat > t.cjs <<'EOF'` + `const m=s.match(/x\.(cjs)/)` + `EOF` + `node t.cjs`
 * deixa de barrar, e `execSync('git add -A')` no mesmo corpo continua barrando.
 * So o `gate-staging-total` passa a opcao; os outros gates chamam sem ela.
 *
 * Movida de `hooks/gate-staging-total.cjs` para `hooks/lib/heredoc.cjs` na
 * Issue #263 (zerar-issues-5, tarefa 2): `gate-mensagem-commit.cjs` tambem
 * precisa isentar corpo de heredoc, e as duas travas nao podiam duplicar a
 * logica sem duplicar tambem o risco de uma desalinhar da outra.
 */
function mascararCorposDeHeredoc(cmd, opcoes = {}) {
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
      !alvoDoRedirecionamentoEhExecutadoDepois(fora, i, fimDoHeredoc) &&
      !(opcoes.scriptNaoShell === true && interpretadorNaoShellDoHeredoc(fora, i));
    if (dado) {
      const inicio = inicioDoCorpo(fora, i);
      if (fimDoHeredoc > inicio) {
        const emBranco = fora.slice(inicio, fimDoHeredoc).replace(/[^\n]/g, " ");
        fora = fora.slice(0, inicio) + emBranco + fora.slice(fimDoHeredoc);
      }
    } else if (opcoes.scriptNaoShell === true && heredoc.delimitadorQuotado && heredoc.fechado && !linhaDoHeredocTemInterpretador(fora, i)) {
      const ex = executoresDoAlvo(fora, i, fimDoHeredoc);
      const doStdin = interpretadorNaoShellDoHeredoc(fora, i);
      if (doStdin) ex.push(doStdin);
      if (ex.length > 0 && ex.every((e) => INTERPRETADORES_NAO_SHELL.has(e))) {
        const inicio = inicioDoCorpo(fora, i);
        if (fimDoHeredoc > inicio) {
          fora = fora.slice(0, inicio) + mascaraSoGit(fora.slice(inicio, fimDoHeredoc)) + fora.slice(fimDoHeredoc);
        }
      }
    }
    de = Math.max(fimDoHeredoc, i + 2);
  }
  return fora;
}

/**
 * Texto do comando que vem DEPOIS da linha do delimitador de um heredoc (#706).
 * `fim` é o índice logo após essa linha, como devolve `corpoDeHeredoc`.
 *  - Delimitador seguido de `\n` e de mais um comando: `cmd[fim - 1]` é a quebra
 *    que separa o próximo comando. Ela volta, para o segmentador partir ali.
 *  - Delimitador no fim do comando: `fim === cmd.length` e `cmd[fim - 1]` é o
 *    ÚLTIMO CARACTERE DO DELIMITADOR. Devolvê-lo colava `F` em `novo.md` (#706).
 *    Nesse caso o resto é vazio.
 */
function restoDepoisDoHeredoc(cmd, fim) {
  if (fim <= 0 || fim >= cmd.length) return '';
  return cmd[fim - 1] === '\n' ? cmd.slice(fim - 1) : cmd.slice(fim);
}

module.exports = {
  INTERPRETADORES_DE_HEREDOC,
  restoDepoisDoHeredoc,
  corpoDeHeredoc,
  linhaDoHeredocTemInterpretador,
  normalizarExecutavel,
  fimDaLinhaLogica,
  extrairComandoDoHeredoc,
  posicoesDeOperadorHeredoc,
  EXECUTAM_ARQUIVO,
  alvoDoRedirecionamentoEhExecutadoDepois,
  INTERPRETADORES_NAO_SHELL,
  executoresDoAlvo,
  mascararCorposDeHeredoc,
};
