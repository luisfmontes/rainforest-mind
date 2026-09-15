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
    // `mascararCorposDeHeredoc`, no gate-staging-total.cjs.
    delimitadorQuotado: tipoAspa !== null,
    fechado: achouFechamento
  };
}

module.exports = {
  INTERPRETADORES_DE_HEREDOC,
  corpoDeHeredoc,
  linhaDoHeredocTemInterpretador,
  normalizarExecutavel,
  fimDaLinhaLogica,
  extrairComandoDoHeredoc,
};
