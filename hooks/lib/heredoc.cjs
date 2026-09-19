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
 *
 * Movida de `hooks/gate-staging-total.cjs` para `hooks/lib/heredoc.cjs` na
 * Issue #263 (zerar-issues-5, tarefa 2): `gate-mensagem-commit.cjs` tambem
 * precisa isentar corpo de heredoc, e as duas travas nao podiam duplicar a
 * logica sem duplicar tambem o risco de uma desalinhar da outra.
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

module.exports = {
  INTERPRETADORES_DE_HEREDOC,
  corpoDeHeredoc,
  linhaDoHeredocTemInterpretador,
  normalizarExecutavel,
  fimDaLinhaLogica,
  extrairComandoDoHeredoc,
  posicoesDeOperadorHeredoc,
  EXECUTAM_ARQUIVO,
  alvoDoRedirecionamentoEhExecutadoDepois,
  mascararCorposDeHeredoc,
};
