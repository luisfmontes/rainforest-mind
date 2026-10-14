#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse (Bash, PowerShell) — nega matar processo POR NOME, na janela
 * principal e dentro de subagente. Matar pelo PID passa.
 *
 * Protege contra: `taskkill /IM` e `taskkill /FI "IMAGENAME …"`, `pkill`,
 * `killall`, `Stop-Process -Name`/`-ProcessName` (e `spps`/`kill` no mesmo
 * jeito), `Stop-Process <nome>` (primeiro posicional que não é número),
 * pipeline `Get-Process <nome> | Stop-Process` sem `-Id` (com ou sem
 * `Where-Object` no meio), `pgrep`/`pidof` alimentando `xargs kill`, e
 * `kill $(pgrep …)` / ``kill `pidof …` ``. Matar por nome derruba processo de
 * outra sessão (regra 15).
 *
 * Fora do escopo (não tenta cobrir): `wmic … delete`, `Invoke-CimMethod …
 * Terminate`, matar de dentro de script (`python -c`, `node -e`), PID lido de
 * arquivo, matar por porta, `ps … | xargs kill` (sem pgrep/pidof), e a
 * abreviação `-n` de `-Name` no Stop-Process.
 *
 * Como lê o comando: primeiro o texto é cortado em unidades (`;`, `&&`, `||`,
 * `&`, quebra de linha, fora de aspas) e cada unidade em estágios de pipe
 * (`|`), para que `Get-Process x | Stop-Process` seja olhado JUNTO — o
 * `segmentosParaGate` do `gate-subagente-sem-gh` corta no `|` e perderia a
 * relação. Cada estágio desce em `bash -c`/`sh -c`/`eval`/`pwsh -Command`/
 * `powershell -Command` pelos helpers de `lib/tokens-comando.cjs` (posição de
 * comando, pulando `sudo`/`env`/`FOO=1`), e `$(…)`/crase são lidos como comando
 * próprio. Os segmentos de `segmentosParaGate` ainda passam pela checagem de
 * comando simples, para cobrir parêntese e chave que o corte de pipe não vê.
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
// Flags que consomem o token seguinte como valor (não é nome nem PID).
const VALOR_STOP = new Set(["-id", "-inputobject", "-timeout"]);
const VALOR_KILL = new Set(["-s", "-n"]);

// `$(pgrep …)`, `$(pidof …)` ou crase com pgrep/pidof, depois de kill/spps/Stop-Process.
const RE_KILL_SUBSTITUICAO = /\b(?:kill|spps|stop-process)\b[^;&|\n]*?(?:\$\(\s*(?:pgrep|pidof)\b|`\s*(?:pgrep|pidof)\b)/i;

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
  const toks = tokensComAspas(trecho);
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
    const v = args[i].v;
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
    if (OBTEM_PROCESSO.has(a.exe) && !a.args.some((t) => t.v.toLowerCase() === "-id")) {
      const parada = depois.find((b) => STOP.has(b.exe));
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
    if (args.some((t) => /^[\/-]im([:=].*)?$/i.test(t.v))) return "taskkill /IM";
    if (args.some((t) => /imagename/i.test(t.v))) return "taskkill /FI IMAGENAME";
    return null;
  }
  if (exe === "pkill") return "pkill";
  if (exe === "killall") return "killall";
  if (STOP.has(exe)) {
    if (args.some((t) => /^-(name|processname)$/i.test(t.v))) return `${exe} -Name`;
    const achado = primeiroNaoFlag(args, exe === "kill" ? VALOR_KILL : VALOR_STOP);
    if (achado && !/^%?\d+$/.test(achado.v)) return `${exe} <nome>`;
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
  if (RE_KILL_SUBSTITUICAO.test(comando)) return "kill com $(pgrep|pidof)";
  for (const dentro of conteudoDeSubstituicao(comando)) {
    const forma = formaPorNome(dentro, profundidade + 1);
    if (forma) return forma;
  }
  for (const estagios of unidadesDePipe(comando)) {
    const forma = formaDoPipe(estagios);
    if (forma) return forma;
  }
  for (const trecho of segmentosParaGate(comando)) {
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
