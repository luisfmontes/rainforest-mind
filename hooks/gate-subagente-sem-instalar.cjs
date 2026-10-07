#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse (Bash, PowerShell; o registro em hooks.json casa só esses dois,
 * desde que a trava do arquivo saiu em #417) — nega, dentro de subagente,
 * comandos de instalação de pacotes e a definição de `RAINFOREST_GATE_OFF`.
 *
 * Protege contra: subagente rodando `npm install`, `pip install`, e variações de
 * outros gerenciadores; também nega a definição de `RAINFOREST_GATE_OFF`.
 * (A trava de criar `.rainforest-gate-off` saiu em #417/D9: o arquivo deixou de
 * desligar qualquer gate, então não há o que proteger.)
 *
 * Design: D5–D8 do plano de zerar-issues-16.
 * Só subagente (D5): `agent_id` só aparece no payload quando a chamada sai de
 * dentro de um. Presença da chave, não truthiness. Toggle `subagente-sem-instalar`,
 * padrão ligado. NÃO honra `RAINFOREST_GATE_OFF` (diferente de outros gates).
 *
 * Como lê o comando (revisão da zerar-issues-16): a primeira versão partia o
 * texto por `;&|` e olhava só a primeira palavra — `bash -c "npm install x"`,
 * `sudo npm install x`, `FOO=1 npm install x` passavam — e procurava o verbo em
 * QUALQUER posição — `npm test -- add`, `yarn test` e `python x.py install`
 * eram barrados. Agora os segmentos vêm do `segmentosParaGate` do
 * `gate-subagente-sem-gh` (mesmo desempacotar de `bash -c`/`eval`/`pwsh
 * -Command`), a posição de comando pula atribuição e wrapper (`env`, `sudo`,
 * `time`, `timeout`…), e o verbo é o SUBCOMANDO: o primeiro argumento que não
 * é flag.
 *
 * Payload ilegível, vazio ou de outra ferramenta: sai 0, como os gates irmãos.
 */

const fs = require("node:fs");
const path = require("node:path");
const {
  tokensComAspas, posicaoDeComando, textoAPartir, desempacotarWrapperDeString,
} = require("./lib/tokens-comando.cjs");
const { segmentosParaGate } = require("./gate-subagente-sem-gh.cjs");

/**
 * D6 — verbo (subcomando) que instala, por gerenciador. Conjunto vazio =
 * qualquer invocação instala (cmdlet do PowerShell).
 */
const VERBOS_QUE_INSTALAM = {
  npm: new Set(["install", "i", "in", "ins", "inst", "insta", "instal", "isntall", "add", "ci", "clean-install", "install-clean", "install-test", "it"]),
  pnpm: new Set(["add", "install", "i"]),
  yarn: new Set(["add", "install"]),
  bun: new Set(["add", "install", "i"]),
  pip: new Set(["install"]),
  pip3: new Set(["install"]),
  pipx: new Set(["install", "inject"]),
  poetry: new Set(["add", "install"]),
  conda: new Set(["install"]),
  mamba: new Set(["install"]),
  winget: new Set(["install", "add"]),
  choco: new Set(["install"]),
  scoop: new Set(["install"]),
  cargo: new Set(["install", "add"]),
  go: new Set(["install", "get"]),
  gem: new Set(["install"]),
  brew: new Set(["install"]),
  apt: new Set(["install"]),
  "apt-get": new Set(["install"]),
  "install-module": new Set(),
  "install-package": new Set(),
  "install-script": new Set(),
  "install-psresource": new Set(),
};

const PYTHONS = new Set(["python", "python3", "python2", "py"]);

/** Nome do executável comparável: sem aspas, sem caminho, sem .exe/.cmd/.bat/.ps1. */
function normalizarExecutavel(nome) {
  const semAspas = String(nome).replace(/^["']|["']$/g, "");
  const base = path.basename(semAspas).replace(/\.(exe|cmd|bat|ps1)$/i, "").toLowerCase();
  // `python3.11`, `pip3.12`: a versão no nome não muda o que o comando faz.
  return base.replace(/^(python3?|pip3?)\.\d+$/, "$1");
}

/**
 * Flags que consomem o token seguinte como valor, por gerenciador (revisão 2
 * da zerar-issues-16): sem isto `npm --prefix x install` lia `x` como
 * subcomando e passava. A forma `--flag=valor` já é um token só.
 */
const FLAGS_COM_VALOR = {
  npm: ["--prefix", "-C", "-w", "--workspace", "--registry", "--cache", "--userconfig", "--globalconfig", "--loglevel", "--tag", "--otp"],
  pnpm: ["-C", "--dir", "--filter", "-F", "--workspace-dir", "--registry", "--store-dir", "--loglevel"],
  yarn: ["--cwd", "--registry", "--modules-folder", "--cache-folder"],
  bun: ["--cwd", "--registry", "--cache-dir"],
  pip: ["-i", "--index-url", "--extra-index-url", "-t", "--target", "--proxy", "--cache-dir", "--log", "-r", "--requirement", "-c", "--constraint", "--python", "--root", "--prefix"],
  poetry: ["-C", "--directory", "-P", "--project"],
  cargo: ["-Z", "--config", "--manifest-path", "--color"],
  uv: ["--directory", "--project", "--python", "-p", "--index-url", "--cache-dir"],
  winget: ["--source", "-s"],
  choco: ["--source", "-s"],
};
FLAGS_COM_VALOR.pip3 = FLAGS_COM_VALOR.pip;

/**
 * Argumentos posicionais (não-flag), pulando o valor das flags que o consomem,
 * toolchain do rustup (`+nightly`) e tudo depois de `--` (argumento do script,
 * não do gerenciador: `npm test -- add`).
 */
function naoFlags(args, exe) {
  const comValor = new Set(FLAGS_COM_VALOR[exe] || []);
  const saida = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--") break;
    if (/^-/.test(a)) {
      if (comValor.has(a)) i += 1;
      continue;
    }
    if (/^\+/.test(a)) continue;
    saida.push(a);
  }
  return saida;
}

/**
 * O segmento (já na posição de comando) instala? Devolve o executável ou null.
 * `args` são os valores dos tokens depois do executável.
 */
function instalacaoNoComando(exe, args) {
  // Pedido de ajuda nao instala: `npm install --help`, `cargo install --list`.
  if (args.some((a) => /^(--help|-h|--list)$/.test(a))) return null;
  let posicionais = naoFlags(args, exe);
  // `yarn workspace <nome> add x`: o verbo vem depois do nome do workspace.
  if (exe === "yarn" && (posicionais[0] || "").toLowerCase() === "workspace") posicionais = posicionais.slice(2);
  // `yarn global add x`: `global` é prefixo, o verbo vem depois.
  if (exe === "yarn" && (posicionais[0] || "").toLowerCase() === "global") posicionais = posicionais.slice(1);
  const sub = (posicionais[0] || "").toLowerCase();

  // `yarn` sozinho (ou só com flags, `yarn --frozen-lockfile`) é install
  // implícito; `yarn test` e `yarn --version`/`--help` não são.
  if (exe === "yarn" && sub === "") {
    const informativa = args.some((a) => /^(--version|-v|--help|-h)$/.test(a));
    return informativa ? null : exe;
  }

  // `npx --yes`/`-y` instala o pacote sem perguntar (D6).
  if (exe === "npx" && args.some((a) => a === "--yes" || a === "-y")) return exe;

  // `python -m pip install`, `py -m pip install` (D6).
  if (PYTHONS.has(exe)) {
    const i = args.indexOf("-m");
    if (i !== -1 && /^pip3?$/i.test(args[i + 1] || "")) {
      if ((naoFlags(args.slice(i + 2), "pip")[0] || "").toLowerCase() === "install") return exe;
    }
    return null;
  }

  // `uv add`, `uv pip install`, `uv tool install` (D6); `uv run` passa.
  if (exe === "uv") {
    const nf = naoFlags(args, "uv").map((a) => a.toLowerCase());
    if (nf[0] === "add") return exe;
    if ((nf[0] === "pip" || nf[0] === "tool") && nf[1] === "install") return exe;
    return null;
  }

  const verbos = VERBOS_QUE_INSTALAM[exe];
  if (!verbos) return null;
  if (verbos.size === 0) return exe;
  return verbos.has(sub) ? exe : null;
}

/**
 * D7 — definir `RAINFOREST_GATE_OFF` no ambiente. Texto cru: a variável no
 * comando já diz a intenção; ler (`echo $RAINFOREST_GATE_OFF`) e tirar
 * (`unset`, `export -n`, `Remove-Item env:`) passam.
 */
const DEFINE_GATE_OFF = [
  /(^|[\s;&|(`'"])RAINFOREST_GATE_OFF\s*=/,
  /\bexport\s+(?:-[a-mo-z]+\s+)*RAINFOREST_GATE_OFF\b/,
  /\b(?:declare|typeset)\s+-\w*x\w*\s+RAINFOREST_GATE_OFF\b/,
  /\$env:RAINFOREST_GATE_OFF\s*=/i,
  /\b(?:set-item|si|new-item|ni|set-content|sc)\s+(?:-path\s+)?["']?env:[\\/]?RAINFOREST_GATE_OFF\b/i,
  /SetEnvironmentVariable\s*\(\s*["']RAINFOREST_GATE_OFF["']/i,
  /\bsetx\s+RAINFOREST_GATE_OFF\b/i,
  /\bset\s+["']?RAINFOREST_GATE_OFF=/i,
];

function instalarLigada(projeto) {
  const { ligado } = require("./lib/config.cjs");
  return ligado("subagente-sem-instalar", { projeto });
}

function bloqueia(razao, visto) {
  process.stderr.write(
    "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
    (visto ? `Comando: \`${String(visto).trim()}\`\n\n` : "") +
    `Razão: ${razao}\n`
  );
  process.exit(2);
}

const RAZAO_INSTALAR = "subagente não pode instalar pacotes. Instalação é da janela principal, com a palavra do usuário.";
const RAZAO_VARIAVEL = "subagente não pode definir `RAINFOREST_GATE_OFF`.";

/** Um segmento: desce em `bash -c`/`eval`/`pwsh -Command`, depois decide. */
function processarSegmento(segmento, profundidade) {
  if (profundidade > 8) return;
  let toks = tokensComAspas(segmento);
  // Operador de chamada do PowerShell (`& npm install`, `. npm install`): o
  // comando é o token seguinte (revisão 2 da zerar-issues-16).
  // Atribuição com valor citado (`FOO="a b" npm install`) é um token citado, que
  // `posicaoDeComando` não reconhece como atribuição.
  while (toks.length > 1 && ((!toks[0].q && (toks[0].v === "&" || toks[0].v === "."))
    || /^[A-Za-z_][A-Za-z0-9_]*=/.test(toks[0].v))) toks = toks.slice(1);
  if (!toks.length) return;
  const pos = posicaoDeComando(toks);

  if (pos === null) return;

  const exe = normalizarExecutavel(toks[pos].v);

  // `pwsh`/`powershell` com flags ANTES do `-Command` (`-NoProfile
  // -ExecutionPolicy Bypass -Command "..."`, a forma comum de chamar do Bash):
  // o desempacotador compartilhado só reconhece o `-Command` logo depois do
  // nome. O texto depois do `-Command`/`-c` é o comando.
  if (exe === "pwsh" || exe === "powershell") {
    const i = toks.findIndex((t, k) => k > pos && !t.q && /^-(c|command)$/i.test(t.v));
    if (i !== -1) {
      const texto = toks.slice(i + 1).map((t) => t.v).join(" ");
      for (const sub of segmentosParaGate(texto)) processarSegmento(sub, profundidade + 1);
      return;
    }
  }

  const { interno } = desempacotarWrapperDeString(textoAPartir(toks, pos));
  if (interno !== null) {
    for (const sub of segmentosParaGate(interno)) processarSegmento(sub, profundidade + 1);
    return;
  }

  const args = toks.slice(pos + 1).map((t) => t.v);
  if (instalacaoNoComando(exe, args)) bloqueia(RAZAO_INSTALAR, segmento);
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

  // Detecta subagente pela presença de agent_id
  const ehSubagente = Object.prototype.hasOwnProperty.call(ev, 'agent_id');
  if (!ehSubagente) process.exit(0);

  const projeto = ev.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  if (!instalarLigada(path.resolve(projeto))) process.exit(0);

  const entrada = ev.tool_input || {};

  // === BASH / POWERSHELL ===
  if (ev.tool_name === "Bash" || ev.tool_name === "PowerShell") {
    const comando = entrada.command;
    if (typeof comando !== "string" || !comando) process.exit(0);
    if (DEFINE_GATE_OFF.some((p) => p.test(comando))) bloqueia(RAZAO_VARIAVEL, comando);
    for (const segmento of segmentosParaGate(comando)) processarSegmento(segmento, 0);
    process.exit(0);
  }

  process.exit(0);
}

if (require.main === module) main();

module.exports = { instalacaoNoComando };
