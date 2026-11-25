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
function fimDaLinhaLogica(cmd, i) {
  let idx = cmd.indexOf('\n', i);
  while (idx > 0 && cmd[idx - 1] === '\\') idx = cmd.indexOf('\n', idx + 1);
  return idx;
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

// D7 (zerar-issues-17): operador colado ao nome se separa antes da busca do alvo.
// `tokensComAspas` devolve `t.sh;` e `t.cjs|sh` como um token so, e `bash t.sh; true`
// atravessava o gate. O digito de descritor so conta no COMECO do token (`2>log` e
// `2>` + `log`); `t2>log` e `t2` + `>` + `log`, como no bash. `2>&1`, `>&2` e `&>`
// ficam inteiros: sao redirecionamento, nao o `&` de segundo plano.
const RE_OPERADOR_COLADO = /(^\d+[<>]&\d*-?|[<>]&\d*-?|&>>?|^\d+>>?|^\d+<|>>?|<|[|;&(){}]+)/;
// Redirecionamento cujo ALVO e o token seguinte (`<`, `0<`, `>`, `2>>`, `&>`).
const RE_REDIR_COM_ALVO = /^(?:\d*(?:<|>>?)|&>>?)$/;
// Redirecionamento que ja traz o alvo (`2>&1`, `>&2`, `<&0`, `2>&-`).
const RE_REDIR_FECHADO = /^\d*[<>]&\d*-?$/;
const ehOperador = (t) => /^[|;&(){}]+$/.test(t);
// Prefixos que rodam o comando seguinte (`sudo sh < t.cjs`, `cat t | env sh`).
const PREFIXOS_DE_COMANDO = new Set(["sudo", "env", "command", "exec", "nohup", "nice", "time", "timeout", "builtin"]);

/**
 * Tokens de `texto` com o operador colado separado (D7) e a quebra de linha entre
 * dois tokens virando `;` (separa comandos). A continuacao `\`+quebra some antes.
 */
function tokensSeparados(texto) {
  const limpo = String(texto).replace(/\\\r?\n/g, " ");
  let toks;
  try {
    toks = [];
    let anterior = null;
    for (const t of tokensComAspas(limpo)) {
      if (anterior && typeof anterior.fim === "number" && typeof t.ini === "number" && limpo.slice(anterior.fim, t.ini).includes("\n")) toks.push(";");
      toks.push(String(t.v));
      anterior = t;
    }
  } catch { toks = limpo.replace(/\n/g, " ; ").split(/\s+/); }
  return toks.flatMap((t) => t.split(RE_OPERADOR_COLADO)).filter(Boolean);
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
 * Comando e argumentos posicionais de `toks[ini..fim)`: pula atribuicao (`X=1`),
 * redirecionamento (com o alvo dele) e prefixo que roda o comando seguinte (`sudo`,
 * `env`, `timeout 5`). Posicional = token que nao comeca com `-`. Devolve
 * `{ nome, posicionais }`, com `nome` normalizado (ou null) e os INDICES dos posicionais.
 */
function lerTrecho(toks, ini, fim) {
  let nome = null;
  const posicionais = [];
  for (let j = ini; j < fim; j++) {
    const t = toks[j];
    if (RE_REDIR_COM_ALVO.test(t)) { j++; continue; }
    if (RE_REDIR_FECHADO.test(t)) continue;
    if (nome === null) {
      if (/^\w+=/.test(t) || t.startsWith("-") || /^\d+[smhd]?$/.test(t)) continue;
      const n = normalizarExecutavel(t);
      if (PREFIXOS_DE_COMANDO.has(n)) continue;
      nome = n;
      continue;
    }
    if (!t.startsWith("-")) posicionais.push(j);
  }
  return { nome, posicionais };
}

// D2: executor que le o script do STDIN, sem arquivo de script proprio.
function executorDeStdin(trecho) {
  return trecho.nome && EXECUTAM_ARQUIVO.has(trecho.nome) && trecho.posicionais.length === 0 ? trecho.nome : null;
}

/**
 * O alvo em `k` e argumento de um comando que executa arquivo? Varre para tras,
 * pulando flags e redirecionamentos (`bash 2>/dev/null t.sh`, `bash 2>&1 t.sh`).
 * Alvo que e ele mesmo destino de redirecionamento (`cat x > t.sh`) nao e argumento.
 */
function executorAntes(toks, k, ini) {
  if (k > ini && RE_REDIR_COM_ALVO.test(toks[k - 1])) return null;
  for (let j = k - 1; j >= ini; j--) {
    const t = toks[j];
    if (t.startsWith("-") || RE_REDIR_FECHADO.test(t)) continue;
    if (j - 1 >= ini && RE_REDIR_COM_ALVO.test(toks[j - 1])) { j--; continue; }
    const n = normalizarExecutavel(t);
    return EXECUTAM_ARQUIVO.has(n) ? n : null;
  }
  return null;
}

// Nomes-base dos alvos de `>`/`>>` na linha logica que abre o heredoc em `i`.
function alvosDaLinha(cmd, i) {
  let ini = i;
  while (ini > 0 && cmd[ini - 1] !== "\n") ini--;
  let fimLinha = fimDaLinhaLogica(cmd, i);
  if (fimLinha === -1) fimLinha = cmd.length;
  const linha = cmd.slice(ini, fimLinha);
  const alvos = new Set();
  const re = /(?:^|[\s;|&])\d?>>?\s*([^\s;|&<>]+)/g;
  let m;
  while ((m = re.exec(linha)) !== null) {
    const base = nomeBase(m[1]);
    if (base) alvos.add(base);
  }
  return alvos;
}

const COPIAM_ARQUIVO = new Set(["cp", "mv", "ln", "install"]);

/**
 * D3 (zerar-issues-17): o conteudo gravado chega ao executor por outro nome.
 * `cp`/`mv`/`ln`/`install` com um alvo entre as origens acrescentam o nome-base do
 * destino; `cat <alvo> > <novo>` acrescenta `<novo>`. Repete ate nao crescer
 * (`cp a b; mv b c`), com teto de 10 voltas.
 */
function expandirAlvosPorCopia(toks, alvos) {
  for (let volta = 0; volta < 10; volta++) {
    const antes = alvos.size;
    for (let ini = 0; ini < toks.length; ) {
      const [, fim] = trechoEm(toks, ini);
      const { nome, posicionais } = lerTrecho(toks, ini, fim);
      if (COPIAM_ARQUIVO.has(nome) && posicionais.length >= 2) {
        const origens = posicionais.slice(0, -1).map((j) => nomeBase(toks[j]));
        const destino = nomeBase(toks[posicionais[posicionais.length - 1]]);
        if (destino && origens.some((b) => alvos.has(b))) alvos.add(destino);
      } else if (nome === "cat" && posicionais.some((j) => alvos.has(nomeBase(toks[j])))) {
        for (let j = ini; j < fim - 1; j++) {
          if (/^(?:\d*>>?|&>>?)$/.test(toks[j])) {
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

/**
 * Quem EXECUTA o arquivo que o heredoc em `i` grava? `"./"` para `./x`, o nome
 * normalizado do comando nos outros casos. Vazio = nenhum executor.
 *
 * Le o resto da linha que abre o heredoc, depois do `<<` (D8: `cat > t.cjs <<'EOF'
 * && node t.cjs` roda depois do corpo gravado), e o texto depois do fechamento. O
 * arquivo conta como executado quando (zerar-issues-17):
 * - e citado como `./x`;
 * - e argumento de um executor, pulando flags e redirecionamentos;
 * - e o stdin (`<`) de um executor sem arquivo de script proprio (D2);
 * - e argumento de `cat` cujo trecho segue por `|` para um executor assim (D2);
 * - chega a qualquer um desses por outro nome, via copia (D3).
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
    if (/^\.[\\/]/.test(t.replace(/^["']+/, ""))) { executores.push("./"); continue; }
    const [ini, fim] = trechoEm(toks, k);
    if (k > ini && ehRedirecionamentoDeEntrada(toks[k - 1])) {
      const ex = executorDeStdin(lerTrecho(toks, ini, fim));
      if (ex) executores.push(ex);
      continue;
    }
    const ex = executorAntes(toks, k, ini);
    if (ex) { executores.push(ex); continue; }
    if (lerTrecho(toks, ini, fim).nome === "cat" && (toks[fim] === "|" || toks[fim] === "|&")) {
      const [ini2, fim2] = trechoEm(toks, fim + 1);
      const ex2 = executorDeStdin(lerTrecho(toks, ini2, fim2));
      if (ex2) executores.push(ex2);
    }
  }
  return executores;
}

function ehRedirecionamentoDeEntrada(t) {
  return /^\d*<$/.test(t);
}

/**
 * D5 (zerar-issues-17): `spawnSync('git',['add','-A'])` e `subprocess.run(["git",
 * "add", "-A"])` -- o comando em lista de strings. Acha cada literal `git` entre
 * aspas e o estende enquanto vier, depois de espacos, virgulas, colchetes e
 * quebras de linha, outro literal completo de mesma aspa na abertura e no
 * fechamento. Devolve os intervalos `[ini, fim)` no texto inteiro.
 */
function trechosDeListaGit(texto) {
  const intervalos = [];
  const re = /(['"`])git\1/g;
  let m;
  while ((m = re.exec(texto)) !== null) {
    let fim = m.index + m[0].length;
    const seguinte = /^[\s,[\]]*(['"`])[^'"`\n]*\1/;
    let s;
    while ((s = seguinte.exec(texto.slice(fim))) !== null) fim += s[0].length;
    intervalos.push([m.index, fim]);
    re.lastIndex = fim;
  }
  return intervalos;
}

/**
 * Corpo de script nao-shell: tudo fica em branco, exceto os trechos `git ...`
 * (ate aspa, `;`, `|`, `&`, `)` ou fim de linha) e o comando em lista de strings
 * (D5), com aspas, virgulas e colchetes trocados por espaco e a quebra de linha de
 * DENTRO da lista virando espaco (le-se um comando so). Comprimento preservado; as
 * outras quebras de linha tambem.
 */
function mascaraSoGit(trecho) {
  const chars = trecho.replace(/[^\n]/g, " ").split("");
  const re = /\bgit\b[^'"`;|&)\n]*/g;
  let m;
  while ((m = re.exec(trecho)) !== null) {
    for (let k = m.index; k < m.index + m[0].length; k++) chars[k] = trecho[k];
  }
  for (const [a, z] of trechosDeListaGit(trecho)) {
    for (let k = a; k < z; k++) chars[k] = /['"`,[\]\r\n]/.test(trecho[k]) ? " " : trecho[k];
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
      !alvoDoRedirecionamentoEhExecutadoDepois(fora, i, fimDoHeredoc);
    if (dado) {
      const inicio = inicioDoCorpo(fora, i);
      if (fimDoHeredoc > inicio) {
        const emBranco = fora.slice(inicio, fimDoHeredoc).replace(/[^\n]/g, " ");
        fora = fora.slice(0, inicio) + emBranco + fora.slice(fimDoHeredoc);
      }
    } else if (opcoes.scriptNaoShell === true && heredoc.delimitadorQuotado && heredoc.fechado && !linhaDoHeredocTemInterpretador(fora, i)) {
      const ex = executoresDoAlvo(fora, i, fimDoHeredoc);
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
