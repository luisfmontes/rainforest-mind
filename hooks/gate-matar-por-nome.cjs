#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse (Bash, PowerShell) — nega matar processo POR NOME, na janela
 * principal e dentro de subagente. Matar pelo PID passa.
 *
 * Protege contra: `taskkill /IM` e `taskkill /FI "IMAGENAME …"`, `pkill`,
 * `killall`, `Stop-Process -Name`/`-ProcessName`/`-n` (e `spps`/`kill` com
 * `-Name`/`-ProcessName`; `kill -n` é sinal do Bash, ver lacunas),
 * `Stop-Process <nome>` (primeiro posicional que não é número, variável nem
 * expansão: `$p`, `$(…)`, `@`, `%`, `(` e crase ficam de fora; os parâmetros
 * comuns com valor, como `-ErrorAction SilentlyContinue`, são pulados), pipeline
 * `Get-Process <nome> | Stop-Process` sem `-Id` (com `-Id:1234` também conta
 * como `-Id`; com ou sem `Where-Object` no meio),
 * `pgrep`/`pidof` alimentando `xargs kill`, e `kill $(pgrep …)` / ``kill
 * `pidof …` ``. Matar por nome derruba processo de outra sessão (regra 15).
 *
 * Fora do escopo (não tenta cobrir): `wmic … delete`, `Invoke-CimMethod …
 * Terminate`, matar de dentro de script (`python -c`, `node -e`), PID lido de
 * arquivo, matar por porta, e `ps … | xargs kill` (o `ps` não entra no pipe
 * que termina em `xargs`; o pgrep/pidof entra).
 *
 * Lacunas declaradas (passam, de propósito, sem parser novo):
 * - `Stop-Process (Get-Process node)` e `-InputObject (Get-Process node)`: o `(`
 *   faz o argumento parecer expansão. A forma de pipe `Get-Process <nome> |
 *   Stop-Process` continua barrada, e o vetor do incidente era `taskkill /IM`.
 * - `kill -n node`: `-n` é sinal do Bash, não `-Name`. No PowerShell, `-n`
 *   abrevia `-Name` do Stop-Process, e essa forma passa.
 * - `kill $(ps … | grep … | awk …)` e `pgrep … | while read p; do kill $p; done`:
 *   o PID chega por `ps` ou por variável.
 * - Abreviação de parâmetro comum (`-ErrorA SilentlyContinue`): só a grafia
 *   listada em `COMUNS_COM_VALOR` é reconhecida (`-ea`, `-ErrorAction` sim).
 * - Heredoc de delimitador citado (`<<'EOF'`): o corpo é texto, exceto quando a
 *   linha chama interpretador (`bash`, `sh`, `python`, `node`…; reconhecido por
 *   palavra, não por parser). Heredoc SEM aspas com `pkill` no corpo não é
 *   barrado hoje (sai 0) e não entra no gate.
 *
 * Como lê o comando: primeiro o texto é cortado em unidades (`;`, `&&`, `||`,
 * `&`, quebra de linha, fora de aspas) e cada unidade em estágios de pipe
 * (`|`), para que `Get-Process x | Stop-Process` seja olhado JUNTO — o
 * `segmentosParaGate` do `gate-subagente-sem-gh` corta no `|` e perderia a
 * relação. Cada estágio desce em `bash -c`/`sh -c`/`eval`/`pwsh -Command`/
 * `powershell -Command` pelos helpers de `lib/tokens-comando.cjs` (posição de
 * comando, pulando `sudo`/`env`/`FOO=1`), e `$(…)`/crase são lidos como comando
 * próprio. Esse `$(…)`/crase NÃO vale dentro de aspa simples nem no corpo de
 * heredoc citado: ali é texto (`mascararLiteral`). A exceção é o argumento de
 * `-c`/`-Command`/`eval`, que é código e desce no wrapper. Os segmentos de
 * `segmentosParaGate` ainda passam pela checagem de comando simples, para cobrir
 * parêntese e chave que o corte de pipe não vê.
 *
 * Toggle `matar-por-nome` (padrão ligado), lido com `ligado()` na cadeia de
 * config do projeto e do usuário. `RAINFOREST_GATE_OFF` vale só na janela
 * principal (payload SEM `agent_id`); subagente nunca o honra.
 *
 * Payload vazio, JSON inválido, `tool_name` que não é Bash/PowerShell: sai 0.
 */

const fs = require("node:fs");
const path = require("node:path");
const {
  tokensComAspas, posicaoDeComando, textoAPartir, desempacotarWrapperDeString,
} = require("./lib/tokens-comando.cjs");
const { segmentosParaGate } = require("./gate-subagente-sem-gh.cjs");

const STOP = new Set(["stop-process", "spps", "kill"]);
const OBTEM_PROCESSO = new Set(["get-process", "gps", "ps"]);
// Parâmetros comuns do PowerShell que também levam valor. Sem eles,
// `-ErrorAction SilentlyContinue` faria `SilentlyContinue` passar por nome.
const COMUNS_COM_VALOR = [
  "-erroraction", "-ea", "-warningaction", "-wa", "-errorvariable", "-ev",
  "-warningvariable", "-wv", "-informationaction", "-infa", "-informationvariable", "-iv",
  "-outvariable", "-ov", "-outbuffer", "-ob", "-pipelinevariable", "-pv",
];
// Flags que consomem o token seguinte como valor (não é nome nem PID).
const VALOR_STOP = new Set(["-id", "-inputobject", "-timeout", ...COMUNS_COM_VALOR]);
// `kill` é alias de Stop-Process no PowerShell, então herda o conjunto. `-s` e
// `-n` são do Bash (sinal de `kill`).
const VALOR_KILL = new Set([...VALOR_STOP, "-s", "-n"]);
// Redirecionamento sem aspas (`<`, `>`, `2>`, `&>`): o alvo não é argumento.
const RE_REDIRECIONAMENTO = /^\d*(?:<|>|&>)/;
// Operador sozinho (`<`, `2>`, `<<`, `>>`): o alvo é o token seguinte.
const RE_REDIRECIONAMENTO_SOLTO = /^\d*(?:<<?-?|>>?|&>>?)$/;
// `-Id` e `-Id:1234` (valor colado com dois-pontos) são o mesmo parâmetro.
const RE_PARAM_ID = /^-id(:|$)/i;
// Posicional que começa com `$`, `(`, `@`, `%` ou crase: variável, subexpressão,
// array ou job spec, expandido pelo shell/PowerShell. Não é nome de processo.
const RE_VARIAVEL_OU_EXPANSAO = /^[$(@%`]/;
// Argumento que é `$(pgrep …)`/`$(pidof …)` (ou crase), lido como argumento de
// comando. O texto citado em `echo "kill $(pgrep x)"` não é comando e não casa.
const RE_SUBSTITUICAO_PGREP = /^(?:\$\(|`)\s*(?:pgrep|pidof)\b/i;
// Heredoc de delimitador citado (`<<'EOF'`, `<<"EOF"`, `<<\EOF`): corpo literal.
const RE_HEREDOC_CITADO = /<<-?\s*(?:'(\w+)'|"(\w+)"|\\(\w+))/g;
// Linha que chama interpretador: o corpo do heredoc é executado, não é literal.
const RE_INTERPRETADOR_NA_LINHA = /\b(?:bash|sh|zsh|dash|ksh|pwsh|powershell|cmd|python3?|node|perl|ruby|eval|source)\b/i;
// Palavra antes de uma aspa simples que faz o conteúdo ser código (`bash -c '…'`).
const RE_PALAVRA_DE_WRAPPER = /^(?:-c|-command|\/c|\/\/c|eval)$/i;

function normalizarExecutavel(nome) {
  const semAspas = String(nome).replace(/^["']|["']$/g, "");
  return path.basename(semAspas).replace(/\.(exe|cmd|bat|ps1)$/i, "").toLowerCase();
}

/** Conteúdo de `$(…)` (sem aninhamento) e de crases, para ler como comando próprio. */
function conteudoDeSubstituicao(texto) {
  const dentro = [];
  for (const m of texto.matchAll(/\$\(([^()]*)\)/g)) dentro.push(m[1]);
  for (const m of texto.matchAll(/`([^`]*)`/g)) dentro.push(m[1]);
  return dentro;
}

/**
 * Cópia do comando em que o texto literal do shell vira espaço: o conteúdo de
 * aspa simples (`'…'`) e o corpo de heredoc de delimitador citado (`<<'EOF'`),
 * que não expandem `$(…)` nem crase. Só `conteudoDeSubstituicao` lê a cópia; o
 * resto do gate lê o texto cru, porque o argumento de `bash -c '…'` é código e
 * precisa chegar à descida do wrapper (por isso o argumento de `-c`/`-Command`/
 * `eval` não é mascarado). Aspa sem fecho não é mascarada. Corpo de heredoc
 * citado de linha que chama interpretador também não é, porque o interpretador
 * executa o corpo.
 */
function mascararLiteral(cmd) {
  const chars = cmd.split("");
  const apaga = (ini, fim) => {
    for (let k = ini; k < fim; k += 1) if (chars[k] !== "\n") chars[k] = " ";
  };
  for (const m of cmd.matchAll(RE_HEREDOC_CITADO)) {
    const fimDaLinha = cmd.indexOf("\n", m.index);
    if (fimDaLinha === -1) continue;
    const inicioDaLinha = cmd.lastIndexOf("\n", m.index) + 1;
    if (RE_INTERPRETADOR_NA_LINHA.test(cmd.slice(inicioDaLinha, fimDaLinha))) continue;
    const delimitador = m[1] || m[2] || m[3];
    const corpoIni = fimDaLinha + 1;
    let fim = cmd.length;
    let p = corpoIni;
    while (p < cmd.length) {
      const nl = cmd.indexOf("\n", p);
      const fimLinha = nl === -1 ? cmd.length : nl;
      if (cmd.slice(p, fimLinha).trim() === delimitador) { fim = p; break; }
      if (nl === -1) break;
      p = nl + 1;
    }
    apaga(corpoIni, fim);
  }
  // Aspas são lidas no texto já sem o corpo do heredoc, para que um apóstrofo
  // dentro do corpo não abra uma aspa falsa sobre código de verdade.
  const s = chars.join("");
  let dupla = false;
  for (let i = 0; i < s.length; i += 1) {
    const c = s[i];
    if (c === "\\") { i += 1; continue; }
    if (dupla) { if (c === '"') dupla = false; continue; }
    if (c === '"') { dupla = true; continue; }
    if (c !== "'") continue;
    const fecha = s.indexOf("'", i + 1);
    if (fecha === -1) break;
    const antes = s.slice(0, i).match(/(\S+)\s*$/);
    if (!(antes && RE_PALAVRA_DE_WRAPPER.test(antes[1]))) apaga(i + 1, fecha);
    i = fecha;
  }
  return chars.join("");
}

/**
 * Corta o comando em unidades (`;`, `&&`, `||`, `&`, quebra de linha — fora de
 * aspas e de redirecionamento `>&`/`<&`) e cada unidade em estágios de pipe
 * (`|`, `|&`). Devolve uma lista de unidades; cada unidade, uma lista de
 * estágios (texto cru, sem o `|`).
 */
function unidadesDePipe(cmd) {
  const unidades = [];
  let estagios = [];
  let atual = "";
  let aspa = null;
  const fechaEstagio = () => { if (atual.trim()) estagios.push(atual); atual = ""; };
  const fechaUnidade = () => { fechaEstagio(); if (estagios.length) unidades.push(estagios); estagios = []; };
  for (let i = 0; i < cmd.length; i += 1) {
    const c = cmd[i];
    const d = cmd[i + 1];
    if (aspa) {
      if (c === aspa) aspa = null;
      atual += c;
      continue;
    }
    if (c === '"' || c === "'") { aspa = c; atual += c; continue; }
    if (c === "|" && d === "|") { fechaUnidade(); i += 1; continue; }
    if (c === "&" && d === "&") { fechaUnidade(); i += 1; continue; }
    if (c === "|") { fechaEstagio(); if (d === "&") i += 1; continue; }
    if (c === "&" && d !== ">" && cmd[i - 1] !== ">" && cmd[i - 1] !== "<") { fechaUnidade(); continue; }
    if (c === ";" || c === "\n" || c === "\r") { fechaUnidade(); continue; }
    atual += c;
  }
  fechaUnidade();
  return unidades;
}

/** Posição de comando de um estágio: o executável, o que veio antes dele e os argumentos. */
function comandoDe(trecho) {
  // `(Get-Process x)` e `& taskkill …`: o parêntese e o call operator não são o
  // comando; sem tirá-los o estágio nunca chega à posição de comando.
  const toks = tokensComAspas(trecho.replace(/^[\s(&]+/, ""));
  if (!toks.length) return null;
  const pos = posicaoDeComando(toks);
  if (pos === null) return null;
  return {
    exe: normalizarExecutavel(toks[pos].v),
    cabeca: toks.slice(0, pos).map((t) => normalizarExecutavel(t.v)),
    args: toks.slice(pos + 1),
    toks,
    pos,
  };
}

/** Primeiro argumento que não é flag, pulando o valor das flags de `comValor`. */
function primeiroNaoFlag(args, comValor) {
  for (let i = 0; i < args.length; i += 1) {
    const { v, q } = args[i];
    // Redirecionamento sem aspas não é argumento: `kill -9 < pids.txt` lê o PID de
    // arquivo (fora do escopo), e `pids.txt` é o alvo do `<`, não um nome.
    if (!q && RE_REDIRECIONAMENTO.test(v)) {
      if (RE_REDIRECIONAMENTO_SOLTO.test(v)) i += 1;
      continue;
    }
    if (v.startsWith("-")) {
      if (comValor.has(v.toLowerCase())) i += 1;
      continue;
    }
    return args[i];
  }
  return null;
}

/**
 * Forma de PIPELINE: `Get-Process x | Stop-Process` (ou `ps x | kill`) sem -Id,
 * e `pgrep …`/`pidof …` seguido de `xargs kill`. Olha os estágios juntos.
 */
function formaDoPipe(estagios) {
  if (estagios.length < 2) return null;
  const cmds = estagios.map(comandoDe);
  for (let i = 0; i < cmds.length; i += 1) {
    const a = cmds[i];
    if (!a) continue;
    const depois = cmds.slice(i + 1).filter(Boolean);
    if (OBTEM_PROCESSO.has(a.exe) && !a.args.some((t) => RE_PARAM_ID.test(t.v))) {
      // `ps` não casa com parada que vem atrás de `xargs`: `ps -p 1234 | xargs kill` é por PID.
      const parada = depois.find((b) => STOP.has(b.exe) && !b.cabeca.includes("xargs"));
      if (parada) return `${a.exe} sem -Id | ${parada.exe}`;
    }
    if ((a.exe === "pgrep" || a.exe === "pidof")
      && depois.some((b) => b.exe === "kill" && b.cabeca.includes("xargs"))) {
      return `${a.exe} | xargs kill`;
    }
  }
  return null;
}

/** Forma de um comando simples (já na posição de comando, sem wrapper de string). */
function formaDoComandoSimples(exe, args) {
  if (exe === "taskkill") {
    // Git Bash converte `/IM` em caminho, então a forma idiomática é `//IM`.
    if (args.some((t) => /^[\/-]{1,2}im([:=].*)?$/i.test(t.v))) return "taskkill /IM";
    if (args.some((t) => /imagename/i.test(t.v))) return "taskkill /FI IMAGENAME";
    return null;
  }
  if (exe === "pkill") return "pkill";
  if (exe === "killall") return "killall";
  if (STOP.has(exe)) {
    if (args.some((t) => /^-(name|processname)$/i.test(t.v))) return `${exe} -Name`;
    if (args.some((t) => RE_SUBSTITUICAO_PGREP.test(t.v))) return `${exe} com $(pgrep|pidof)`;
    const achado = primeiroNaoFlag(args, exe === "kill" ? VALOR_KILL : VALOR_STOP);
    if (achado && !RE_VARIAVEL_OU_EXPANSAO.test(achado.v) && !/^%?\d+$/.test(achado.v)) {
      return `${exe} <nome>`;
    }
  }
  return null;
}

/**
 * Um estágio: desce em `pwsh -Command`/`bash -c`/`eval` (e os demais wrappers
 * de string) e, sem wrapper, olha o comando simples.
 */
function formaDoComando(trecho, profundidade) {
  const c = comandoDe(trecho);
  if (!c) return null;
  const { exe, toks, pos } = c;
  if (exe === "pwsh" || exe === "powershell") {
    // Flags ANTES do -Command (`-NoProfile -Command "..."`): o desempacotador
    // compartilhado só reconhece o -Command logo depois do nome.
    const i = toks.findIndex((t, k) => k > pos && !t.q && /^-(c|command)$/i.test(t.v));
    if (i !== -1) return formaPorNome(toks.slice(i + 1).map((t) => t.v).join(" "), profundidade + 1);
  }
  if (exe === "cmd") {
    // `cmd.exe //c "taskkill …"`: o helper compartilhado só lê `/c` e `/k`, não a barra dupla.
    const i = toks.findIndex((t, k) => k > pos && !t.q && /^\/\/?[ck]$/i.test(t.v));
    if (i !== -1) return formaPorNome(toks.slice(i + 1).map((t) => t.v).join(" "), profundidade + 1);
  }
  const { interno } = desempacotarWrapperDeString(textoAPartir(toks, pos));
  if (interno !== null) return formaPorNome(interno, profundidade + 1);
  return formaDoComandoSimples(exe, c.args);
}

/**
 * Nome da forma de "matar por nome" que o comando casa, ou `null`. Devolve uma
 * string como "taskkill /IM" ou "pgrep | xargs kill".
 */
function formaPorNome(comando, profundidade = 0) {
  if (typeof comando !== "string" || profundidade > 8) return null;
  for (const dentro of conteudoDeSubstituicao(mascararLiteral(comando))) {
    const forma = formaPorNome(dentro, profundidade + 1);
    if (forma) return forma;
  }
  for (const estagios of unidadesDePipe(comando)) {
    const forma = formaDoPipe(estagios);
    if (forma) return forma;
  }
  const segmentos = segmentosParaGate(comando);
  // `kill $(pgrep x)`: o segmentador corta no `(` e devolve "kill $" seguido de
  // "pgrep x". Só conta se o `$` fecha um estágio de parada, na posição de comando.
  for (let k = 0; k < segmentos.length - 1; k += 1) {
    if (!/\$\s*$/.test(segmentos[k]) || !/^\s*(?:pgrep|pidof)\b/i.test(segmentos[k + 1])) continue;
    const c = comandoDe(segmentos[k]);
    if (c && STOP.has(c.exe)) return `${c.exe} com $(pgrep|pidof)`;
  }
  for (const trecho of segmentos) {
    const forma = formaDoComando(trecho, profundidade);
    if (forma) return forma;
  }
  return null;
}

function matarLigado(projeto) {
  const { ligado } = require("./lib/config.cjs");
  return ligado("matar-por-nome", { projeto });
}

function bloqueia(forma, visto, ehSubagente) {
  process.stderr.write(
    "BLOQUEADO pelo gate matar-por-nome do rainforest-mind.\n\n" +
    `Comando visto: \`${String(visto).trim()}\`\n` +
    `Forma casada: ${forma}\n\n` +
    "Razão: matar processo por nome derruba processo de outra sessão (regra 15). " +
    "Mate pelo PID deste trabalho.\n\n" +
    "Como fazer:\n" +
    "  1. listar: tasklist /FI \"IMAGENAME eq <nome>\"  ou  Get-Process <nome>  ou  pgrep -a <nome>\n" +
    "  2. conferir que o processo é desta sessão (PID e hora de início)\n" +
    "  3. matar pelo PID: taskkill /PID <pid> /F  ou  Stop-Process -Id <pid>  ou  kill <pid>\n" +
    (ehSubagente
      ? ""
      : "\nNa janela principal, RAINFOREST_GATE_OFF=1 desliga este gate na sessão, se o usuário pediu.\n")
  );
  process.exit(2);
}

function main() {
  let ev;
  try {
    const bruto = fs.readFileSync(0, "utf8");
    if (!bruto.trim()) process.exit(0);
    ev = JSON.parse(bruto);
  } catch {
    process.exit(0);
  }
  if (!ev || typeof ev !== "object") process.exit(0);
  if (ev.tool_name !== "Bash" && ev.tool_name !== "PowerShell") process.exit(0);
  const comando = ev.tool_input && ev.tool_input.command;
  if (typeof comando !== "string" || !comando) process.exit(0);

  // Subagente = presença da chave agent_id. Só a janela principal honra RAINFOREST_GATE_OFF.
  const ehSubagente = Object.prototype.hasOwnProperty.call(ev, "agent_id");
  if (!ehSubagente && process.env.RAINFOREST_GATE_OFF) process.exit(0);
  const projeto = ev.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  if (!matarLigado(path.resolve(projeto))) process.exit(0);

  const forma = formaPorNome(comando);
  if (forma) bloqueia(forma, comando, ehSubagente);
  process.exit(0);
}

if (require.main === module) main();

module.exports = { formaPorNome };
