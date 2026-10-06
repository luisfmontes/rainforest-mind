#!/usr/bin/env node
// @categoria: guia
/**
 * PreToolUse (Bash, PowerShell, Write, Edit) — nega, dentro de subagente,
 * comandos de instalação de pacotes e tentativas de desligar o gate.
 *
 * Protege contra: subagente rodando `npm install`, `pip install`, e variações de
 * outros gerenciadores; também nega criação de `.rainforest-gate-off` e definição
 * de `RAINFOREST_GATE_OFF`.
 *
 * Design: D5–D8 do plano de zerar-issues-16.
 * Só subagente (D5): `agent_id` só aparece no payload quando a chamada sai de
 * dentro de um. Presença da chave, não truthiness. Toggle `subagente-sem-instalar`,
 * padrão ligado. NÃO honra `RAINFOREST_GATE_OFF` nem `.rainforest-gate-off`
 * (diferente de outros gates).
 *
 * Payload ilegível, vazio ou de outra ferramenta: sai 0, como os gates irmãos.
 */

const fs = require("node:fs");
const path = require("node:path");

/**
 * Comandos de instalação negados (D6): todos os gerenciadores de pacotes comuns.
 */
const COMANDOS_NEGADOS = {
  npm: new Set(["install", "i", "add", "ci"]),
  npx: new Set(["install", "--yes", "-y"]),
  pnpm: new Set(["add", "install", "i"]),
  yarn: new Set(["add", "install"]),
  pip: new Set(["install"]),
  pip3: new Set(["install"]),
  python: new Set(["install"]), // python -m pip install
  python3: new Set(["install"]),
  python2: new Set(["install"]),
  uv: new Set(["add", "install"]), // uv add, uv pip install, uv tool install
  winget: new Set(["install"]),
  choco: new Set(["install"]),
  scoop: new Set(["install"]),
  cargo: new Set(["install"]),
  go: new Set(["install"]),
  gem: new Set(["install"]),
  brew: new Set(["install"]),
  apt: new Set(["install"]),
  "apt-get": new Set(["install"]),
  "Install-Module": new Set([]), // PowerShell - qualquer instância é negada
  "Install-Package": new Set([]), // PowerShell - qualquer instância é negada
};

/**
 * Variantes de yarn sozinho (toda invocação de `yarn` sem subcomando é install implícito).
 */
const YARN_SOZINHO = /^yarn$|^yarn\s+--/;

/**
 * Expressa formas de definir RAINFOREST_GATE_OFF no environment.
 * Export, prefixo, e PowerShell $env:.
 */
const RAINFOREST_GATE_OFF_PATTERNS = [
  /\bexport\s+RAINFOREST_GATE_OFF\b/,
  /\bRAINFOREST_GATE_OFF\s*=/,
  /\$env:RAINFOREST_GATE_OFF\s*=/,
  /\bsetx\s+RAINFOREST_GATE_OFF\b/,
];

function instalarLigada(projeto) {
  const { ligado } = require("./lib/config.cjs");
  return ligado("subagente-sem-instalar", { projeto });
}

/**
 * Detecta se um segmento começa com um comando de instalação negado.
 */
function ehComandoDeInstalacao(segmento) {
  const partes = segmento.trim().split(/\s+/);
  if (partes.length === 0) return null;

  const exe = partes[0].toLowerCase();

  // `yarn` sozinho é install implícito
  if (YARN_SOZINHO.test(exe)) {
    return exe;
  }

  // Casos especiais para PowerShell (Install-Module, Install-Package)
  if (exe === "install-module" || exe === "install-package") {
    return exe;
  }

  // Caso `python -m pip install`
  if ((exe === "python" || exe === "python3" || exe === "python2") && partes.length > 2) {
    if (partes[1] === "-m" && partes[2] === "pip" && partes[3] === "install") {
      return exe;
    }
  }

  // Caso `uv pip install`, `uv add`, `uv tool install`
  if (exe === "uv" && partes.length > 1) {
    const subcmd = partes[1].toLowerCase();
    if (subcmd === "pip" && partes[2] === "install") return "uv";
    if (["add", "install", "tool"].includes(subcmd)) return "uv";
  }

  // Caso `npx --yes` ou `npx -y` com qualquer coisa depois
  if (exe === "npx") {
    if (partes.some(p => p === "--yes" || p === "-y")) return "npx";
  }

  // Casos normais: comando com subcomando
  const negados = COMANDOS_NEGADOS[exe];
  if (!negados) return null;

  if (negados.size === 0) {
    // Install-Module e Install-Package (PowerShell) — qualquer invocação é negada
    return exe;
  }

  // Para npm, pip, etc.: procura pelo subcomando
  for (let i = 1; i < partes.length; i++) {
    if (negados.has(partes[i].toLowerCase())) {
      return exe;
    }
  }

  return null;
}

/**
 * Detecta se o comando tenta definir RAINFOREST_GATE_OFF no environment.
 */
function ehDefinicaoDeGateOff(comando) {
  return RAINFOREST_GATE_OFF_PATTERNS.some(p => p.test(comando));
}

/**
 * Divide comando em segmentos por operadores e linhas (simples).
 */
function segmentarComando(comando) {
  // Remove linhas de continuação (barra invertida no final)
  comando = comando.replace(/\\\s*\n/g, " ");
  // Divide por ;, &&, ||, |, e quebra de linha
  const partes = comando.split(/[;&|]/);
  return partes.map(p => p.trim()).filter(p => p);
}

function bloquia(motivo) {
  process.stderr.write(motivo);
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

  if (!ev) process.exit(0);

  // Detecta subagente pela presença de agent_id
  const ehSubagente = Object.prototype.hasOwnProperty.call(ev, 'agent_id');
  if (!ehSubagente) process.exit(0);

  const projeto = ev.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  if (!instalarLigada(path.resolve(projeto))) process.exit(0);

  // === ESCRITA (Write/Edit) ===
  if (ev.tool_name === "Write" || ev.tool_name === "Edit" || ev.tool_name === "MultiEdit" || ev.tool_name === "NotebookEdit") {
    const filepath = ev.tool_input && ev.tool_input.file_path;
    if (typeof filepath === "string" && filepath.endsWith(".rainforest-gate-off")) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        `Arquivo: \`${filepath}\`\n\n` +
        "Razão: subagente não pode criar ou editar `.rainforest-gate-off`.\n"
      );
    }
    process.exit(0);
  }

  // === BASH ===
  if (ev.tool_name === "Bash") {
    const comando = ev.tool_input && ev.tool_input.command;
    if (typeof comando !== "string" || !comando) process.exit(0);

    // Verifica se há tentativa de definir RAINFOREST_GATE_OFF
    if (ehDefinicaoDeGateOff(comando)) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        "Razão: subagente não pode definir `RAINFOREST_GATE_OFF`.\n"
      );
    }

    // Verifica se há redireção para .rainforest-gate-off
    if (/>+\s*\.rainforest-gate-off\b/.test(comando)) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        "Razão: subagente não pode escrever em `.rainforest-gate-off`.\n"
      );
    }

    // Verifica se há comando touch .rainforest-gate-off
    if (/\btouch\s+[^&|;]*\.rainforest-gate-off\b/.test(comando)) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        "Razão: subagente não pode criar `.rainforest-gate-off`.\n"
      );
    }

    // Verifica segmentos para comandos de instalação
    const segmentos = segmentarComando(comando);
    for (const segmento of segmentos) {
      const cmdNegado = ehComandoDeInstalacao(segmento);
      if (cmdNegado) {
        bloquia(
          "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
          `Comando: \`${segmento.trim()}\`\n\n` +
          "Razão: subagente não pode instalar pacotes. Instalação é da janela principal, com a palavra do usuário.\n"
        );
      }
    }

    process.exit(0);
  }

  // === POWERSHELL ===
  if (ev.tool_name === "PowerShell") {
    const comando = ev.tool_input && ev.tool_input.command;
    if (typeof comando !== "string" || !comando) process.exit(0);

    // Verifica se há tentativa de definir RAINFOREST_GATE_OFF
    if (ehDefinicaoDeGateOff(comando)) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        "Razão: subagente não pode definir `RAINFOREST_GATE_OFF`.\n"
      );
    }

    // Verifica se há redireção para .rainforest-gate-off
    if (/>+\s*\.rainforest-gate-off\b/.test(comando)) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        "Razão: subagente não pode escrever em `.rainforest-gate-off`.\n"
      );
    }

    // Verifica se há New-Item .rainforest-gate-off
    if (/\bNew-Item\s+[^&|;]*\.rainforest-gate-off\b/.test(comando)) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        "Razão: subagente não pode criar `.rainforest-gate-off`.\n"
      );
    }

    // Verifica se há Copy-Item/Copy/cp/mv para .rainforest-gate-off
    if (/(Copy-Item|Copy|cp|move|mv|Move-Item).*\.rainforest-gate-off\b/.test(comando)) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        "Razão: subagente não pode escrever em `.rainforest-gate-off`.\n"
      );
    }

    // Verifica segmentos para comandos de instalação (case-insensitive para PowerShell)
    const cmdLower = comando.toLowerCase();

    // Install-Module ou Install-Package
    if (/\b(install-module|install-package)\b/.test(cmdLower)) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        "Razão: subagente não pode instalar pacotes. Instalação é da janela principal, com a palavra do usuário.\n"
      );
    }

    // npm install (pode rodar em PowerShell também)
    if (/\bnpm\s+(install|i|add|ci)\b/.test(cmdLower)) {
      bloquia(
        "BLOQUEADO pelo gate de subagente sem instalação do rainforest-mind.\n\n" +
        "Razão: subagente não pode instalar pacotes. Instalação é da janela principal, com a palavra do usuário.\n"
      );
    }

    process.exit(0);
  }

  process.exit(0);
}

if (require.main === module) main();
