#!/usr/bin/env node
"use strict";
/* Bateria do gate-subagente-sem-instalar (D5–D8, tarefa 3 do plano
 * `docs/rainforest/planos/2026-10-06-zerar-issues-16.md`).
 *
 * O payload é o mesmo fixture de `gate-bateria-sem-timeout` (payload real de
 * PreToolUse de subagente), com `tool_input` trocado por caso.
 *
 * Roda o hook como processo real, payload no stdin. Isolamento: cada caso usa
 * um projeto em mkdtemp (CLAUDE_PROJECT_DIR e RFM_ROOT dentro dele).
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "gate-subagente-sem-instalar.cjs");
const BASE = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "busca-raiz", "payload-bash-subagente.json"), "utf8"));

let ok = 0;
let falhou = 0;

function caso(nome, obtido, esperado) {
  if (obtido === esperado) {
    ok++;
    console.log(`  ok    ${nome} — esperado ${esperado}, obtido ${obtido}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome} — esperado ${esperado}, obtido ${obtido}`);
  }
}

function casoContem(nome, status, stderr, esperadoStatus, trechosStderr) {
  let ok_local = status === esperadoStatus;
  if (ok_local && Array.isArray(trechosStderr)) {
    for (const trecho of trechosStderr) {
      if (!stderr.includes(trecho)) {
        ok_local = false;
        break;
      }
    }
  }
  if (ok_local) {
    ok++;
    console.log(`  ok    ${nome} — status ${esperadoStatus}, stderr contém trechos esperados`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome} — status esperado ${esperadoStatus}, obtido ${status}; trechos: ${JSON.stringify(trechosStderr)}; stderr: ${stderr}`);
  }
}

const caixa = fs.mkdtempSync(path.join(os.tmpdir(), "subagente-sem-instalar-"));
process.on("exit", () => fs.rmSync(caixa, { recursive: true, force: true }));
const projeto = path.join(caixa, "projeto");
fs.mkdirSync(path.join(projeto, ".rainforest"), { recursive: true });

function rodar(comando, { subagente = true, toolName = "Bash", toolInput = {}, config } = {}) {
  const payload = JSON.parse(JSON.stringify(BASE));
  payload.tool_name = toolName;
  payload.tool_input = { command: comando, ...toolInput };
  payload.cwd = projeto;
  if (!subagente) { delete payload.agent_id; delete payload.agent_type; }

  const cfg = path.join(projeto, ".rainforest", "config.json");
  if (config) fs.writeFileSync(cfg, JSON.stringify(config)); else fs.rmSync(cfg, { force: true });

  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload), encoding: "utf8",
    env: { ...process.env, CLAUDE_PROJECT_DIR: projeto, RFM_ROOT: path.join(caixa, "dados") },
  });
  return { status: r.status, stderr: r.stderr || "" };
}

console.log("== gate-subagente-sem-instalar ==");

// === D6: Comandos de instalação são negados em subagente ===

// npm
let r = rodar("npm install x");
caso("subagente npm install x nega com exit 2", r.status, 2);

r = rodar("npm install");
caso("npm install sem pacote nega", r.status, 2);

r = rodar("npm i lodash");
caso("npm i (alias de install) nega", r.status, 2);

r = rodar("npm add lodash");
caso("npm add nega", r.status, 2);

r = rodar("npm ci");
caso("npm ci nega", r.status, 2);

// npx
r = rodar("npx --yes package");
caso("npx --yes nega", r.status, 2);

r = rodar("npx -y package");
caso("npx -y nega", r.status, 2);

// pnpm
r = rodar("pnpm add lodash");
caso("pnpm add nega", r.status, 2);

r = rodar("pnpm install");
caso("pnpm install nega", r.status, 2);

// yarn
r = rodar("yarn add lodash");
caso("yarn add nega", r.status, 2);

r = rodar("yarn install");
caso("yarn install nega", r.status, 2);

r = rodar("yarn");
caso("yarn (install implícito) nega", r.status, 2);

// pip
r = rodar("pip install requests");
caso("pip install nega", r.status, 2);

r = rodar("pip3 install requests");
caso("pip3 install nega", r.status, 2);

r = rodar("python -m pip install requests");
caso("python -m pip install nega", r.status, 2);

r = rodar("python3 -m pip install requests");
caso("python3 -m pip install nega", r.status, 2);

// uv
r = rodar("uv add requests");
caso("uv add nega", r.status, 2);

r = rodar("uv pip install requests");
caso("uv pip install nega", r.status, 2);

r = rodar("uv tool install black");
caso("uv tool install nega", r.status, 2);

// winget
r = rodar("winget install Git.Git");
caso("winget install nega", r.status, 2);

// choco
r = rodar("choco install nodejs");
caso("choco install nega", r.status, 2);

// scoop
r = rodar("scoop install nodejs");
caso("scoop install nega", r.status, 2);

// cargo
r = rodar("cargo install ripgrep");
caso("cargo install nega", r.status, 2);

// go
r = rodar("go install github.com/user/tool");
caso("go install nega", r.status, 2);

// gem
r = rodar("gem install bundler");
caso("gem install nega", r.status, 2);

// brew
r = rodar("brew install git");
caso("brew install nega", r.status, 2);

// apt
r = rodar("apt install git");
caso("apt install nega", r.status, 2);

r = rodar("apt-get install git");
caso("apt-get install nega", r.status, 2);

// === D6: Comandos de leitura passam ===

r = rodar("npm test");
caso("npm test passa", r.status, 0);

r = rodar("npm run build");
caso("npm run build passa", r.status, 0);

r = rodar("pip list");
caso("pip list passa", r.status, 0);

r = rodar("uv run x");
caso("uv run passa", r.status, 0);

// === D6: Sem agent_id (janela principal) passa ===

r = rodar("npm install x", { subagente: false });
caso("npm install x sem agent_id (janela principal) passa", r.status, 0);

r = rodar("pip install requests", { subagente: false });
caso("pip install requests sem agent_id passa", r.status, 0);

// === D7: Criar .rainforest-gate-off é negado ===

// Touch
r = rodar("touch .rainforest-gate-off");
caso("touch .rainforest-gate-off nega", r.status, 2);

// Echo redirect
r = rodar("echo 1 > .rainforest-gate-off");
caso("echo 1 > .rainforest-gate-off nega", r.status, 2);

// Write tool
r = rodar("dummy", { toolName: "Write", toolInput: { file_path: ".rainforest-gate-off" } });
caso("Write com file_path .rainforest-gate-off nega", r.status, 2);

// Edit tool
r = rodar("dummy", { toolName: "Edit", toolInput: { file_path: ".rainforest-gate-off" } });
caso("Edit com file_path .rainforest-gate-off nega", r.status, 2);

// === D7: RAINFOREST_GATE_OFF em environment é negado ===

r = rodar("export RAINFOREST_GATE_OFF=1 && npm install x");
caso("export RAINFOREST_GATE_OFF em Bash nega", r.status, 2);

r = rodar("RAINFOREST_GATE_OFF=1 git commit -m x");
caso("RAINFOREST_GATE_OFF=1 prefixo em Bash nega", r.status, 2);

// PowerShell
r = rodar("$env:RAINFOREST_GATE_OFF=1; npm install x", { toolName: "PowerShell" });
caso("$env:RAINFOREST_GATE_OFF em PowerShell nega", r.status, 2);

// === PowerShell Install-Module ===

r = rodar("Install-Module PowerShellGet", { toolName: "PowerShell" });
caso("Install-Module em PowerShell nega", r.status, 2);

r = rodar("Install-Package posh-git", { toolName: "PowerShell" });
caso("Install-Package em PowerShell nega", r.status, 2);

// === O gate nunca derruba a sessão por erro próprio ===

const rVazio = spawnSync(process.execPath, [HOOK], {
  input: "", encoding: "utf8",
  env: { ...process.env, CLAUDE_PROJECT_DIR: projeto },
});
caso("stdin vazio → 0", rVazio.status, 0);

const rMalformado = spawnSync(process.execPath, [HOOK], {
  input: "{ isto nao e json", encoding: "utf8",
  env: { ...process.env, CLAUDE_PROJECT_DIR: projeto },
});
caso("payload malformado → 0", rMalformado.status, 0);

const payloadOutraFerramenta = JSON.parse(JSON.stringify(BASE));
payloadOutraFerramenta.tool_input = { file_path: "/tmp/x" };
payloadOutraFerramenta.tool_name = "Read";
const rOutraFerramenta = spawnSync(process.execPath, [HOOK], {
  input: JSON.stringify(payloadOutraFerramenta), encoding: "utf8",
  env: { ...process.env, CLAUDE_PROJECT_DIR: projeto },
});
caso("tool_name = Read, não Bash → 0", rOutraFerramenta.status, 0);

// === RAINFOREST_GATE_OFF no ambiente não desliga (diferente de outros gates) ===

const payloadComEnv = JSON.parse(JSON.stringify(BASE));
payloadComEnv.tool_name = "Bash";
payloadComEnv.tool_input = { command: "npm install x" };
payloadComEnv.cwd = projeto;
const rComEnv = spawnSync(process.execPath, [HOOK], {
  input: JSON.stringify(payloadComEnv), encoding: "utf8",
  env: { ...process.env, CLAUDE_PROJECT_DIR: projeto, RFM_ROOT: path.join(caixa, "dados"), RAINFOREST_GATE_OFF: "1" },
});
caso("RAINFOREST_GATE_OFF no ambiente não desliga o gate", rComEnv.status, 2);

// === Toggle: a chave do config desliga (e só ela) ===
r = rodar("npm install x", { config: { "subagente-sem-instalar": false } });
caso("subagente-sem-instalar false no config do projeto desliga", r.status, 0);

r = rodar("npm install x", { config: { "subagente-sem-instalar": true } });
caso("subagente-sem-instalar true no config segue negando", r.status, 2);

// === Resultado ===

console.log("");
if (falhou === 0) {
  console.log(`${ok} ok, 0 falha(s)`);
  process.exit(0);
} else {
  console.log(`${ok} ok, ${falhou} falha(s)`);
  process.exit(1);
}
