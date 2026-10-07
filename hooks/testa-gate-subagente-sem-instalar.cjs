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

// === #417/D9: criar .rainforest-gate-off PASSA (o arquivo não desliga mais nada) ===

r = rodar("touch .rainforest-gate-off");
caso("touch .rainforest-gate-off passa (arquivo não desliga gate)", r.status, 0);

r = rodar("echo 1 > .rainforest-gate-off");
caso("echo 1 > .rainforest-gate-off passa", r.status, 0);

r = rodar("dummy", { toolName: "Write", toolInput: { file_path: ".rainforest-gate-off" } });
caso("Write com file_path .rainforest-gate-off passa", r.status, 0);

r = rodar("dummy", { toolName: "Edit", toolInput: { file_path: ".rainforest-gate-off" } });
caso("Edit com file_path .rainforest-gate-off passa", r.status, 0);

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

// === Revisão da zerar-issues-16: contornos que passavam e trabalho barrado ===
// A primeira versão olhava só a 1ª palavra do segmento (contornos abaixo
// passavam) e o verbo em qualquer posição (os legítimos eram barrados).
console.log("");
console.log("== contornos: instalação fora da 1ª palavra, PowerShell e definição da variável ==");
const CONTORNOS = [
  ["Bash", 'bash -c "npm install x"'], ["Bash", 'sh -c "pip install x"'], ["Bash", "FOO=1 npm install x"],
  ["Bash", "env FOO=1 npm install x"], ["Bash", "sudo npm install x"], ["Bash", "time npm install x"],
  ["Bash", "(npm install x)"], ["Bash", "npm.cmd install x"], ["Bash", "py -m pip install x"],
  ["Bash", "bun add x"], ["Bash", "poetry add x"], ["Bash", "pipx install x"], ["Bash", "cargo add x"],
  ["Bash", "cd sub && npm i x"], ["Bash", "timeout 60 npm install x"], ["Bash", "yarn --frozen-lockfile"],
  ["PowerShell", "pip install x"], ["PowerShell", "winget install x"], ["PowerShell", "uv add x"],
  ["PowerShell", "pnpm add x"], ["PowerShell", "choco install x"], ["PowerShell", "python -m pip install x"],
  ["PowerShell", 'pwsh -Command "npm install x"'],
  ["PowerShell", '[Environment]::SetEnvironmentVariable("RAINFOREST_GATE_OFF", "1")'],
  ["Bash", "export RAINFOREST_GATE_OFF"],
];
for (const [ferramenta, cmd] of CONTORNOS) {
  caso(`[${ferramenta}] ${cmd} nega`, rodar(cmd, { toolName: ferramenta }).status, 2);
}
console.log("");
console.log("== legítimos: verbo fora da posição de subcomando, leitura do arquivo de desligar ==");
const LEGITIMOS = [
  "yarn test", "yarn build", "yarn run x", "yarn --version", "npm test -- add", "npm run ci", "npm run build add",
  "npm ls ci", "npm view foo i", "python script.py install", "go test ./... -run install", "uv run script.py add",
  "gem list install", "brew list install", "cat .rainforest-gate-off", "rm .rainforest-gate-off",
  "echo $RAINFOREST_GATE_OFF", "unset RAINFOREST_GATE_OFF", 'git commit -m "nao rode npm install aqui"',
];
for (const cmd of LEGITIMOS) caso(`${cmd} passa`, rodar(cmd).status, 0);

// Revisão 2: flag com valor antes do verbo, operador `&`/`.` do PowerShell,
// `pwsh -NoProfile -Command`, versão no nome do executável, atribuição citada.
console.log("");
console.log("== revisão 2: flag com valor, & do PowerShell, pwsh com flags, versão no nome ==");
const CONTORNOS_R2 = [
  ["Bash", "npm --prefix x install"], ["Bash", "npm -C x install"], ["Bash", "npm -w pkg install"],
  ["Bash", "npm --workspace pkg i left-pad"], ["Bash", "pnpm --filter web add y"], ["Bash", "pnpm --dir x install"],
  ["Bash", "yarn --cwd x add y"], ["Bash", "yarn workspace web add y"], ["Bash", "bun --cwd x add y"],
  ["Bash", "pip --index-url U install y"], ["Bash", "poetry --directory x install"], ["Bash", "cargo +nightly install x"],
  ["PowerShell", "& npm install"], ["PowerShell", "& pip install x"], ["PowerShell", '& "npm" install'],
  ["PowerShell", ". npm install"], ["PowerShell", "& Install-Module Foo"], ["PowerShell", "& cmd /c npm install"],
  ["Bash", 'pwsh -NoProfile -Command "npm install x"'],
  ["Bash", 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "pip install x"'],
  ["Bash", "pwsh -NoProfile -Command npm install x"], ["Bash", "python3.11 -m pip install y"],
  ["Bash", "pip3.11 install x"], ["Bash", 'FOO="a b" npm install'],
  // Revisão 3: redirecionamento colado ao alvo citado, `yarn global add`.
  ["Bash", "yarn global add x"],
];
for (const [ferramenta, cmd] of CONTORNOS_R2) {
  caso(`[${ferramenta}] ${cmd} nega`, rodar(cmd, { toolName: ferramenta }).status, 2);
}
const LEGITIMOS_R2 = [
  ["Bash", "npm install --help"], ["Bash", "pip install --help"], ["Bash", "cargo install --list"],
  ["Bash", "npm --prefix x test"], ["Bash", "pnpm --filter web test"], ["Bash", "yarn workspace web build"],
  ["PowerShell", "& npm test"], ["Bash", 'pwsh -NoProfile -Command "npm test"'],
];
for (const [ferramenta, cmd] of LEGITIMOS_R2) {
  caso(`[${ferramenta}] ${cmd} passa`, rodar(cmd, { toolName: ferramenta }).status, 0);
}
// #417/D9: nenhuma forma de escrever o arquivo é barrada (ele não desliga mais gate).
const ARQUIVO_PASSA = [
  ["Bash", "printf 1 > ./.rainforest-gate-off"], ["Bash", "> /x/.rainforest-gate-off"],
  ["Bash", 'echo 1 > ".rainforest-gate-off"'], ["Bash", "cp a .rainforest-gate-off"], ["Bash", "mv a .rainforest-gate-off"],
  ["Bash", "echo 1 | tee .rainforest-gate-off"], ["Bash", "ln -s a .rainforest-gate-off"],
  ["Bash", "sed -i s/x/y/ .rainforest-gate-off"], ["PowerShell", "Set-Content .rainforest-gate-off 1"],
  ["PowerShell", '"1" | Out-File .rainforest-gate-off'], ["PowerShell", "Copy-Item a .rainforest-gate-off"],
  ["Bash", 'echo x >".rainforest-gate-off"'], ["Bash", "echo x 2>'.rainforest-gate-off'"],
];
for (const [ferramenta, cmd] of ARQUIVO_PASSA) {
  caso(`[${ferramenta}] ${cmd} passa (arquivo não desliga gate)`, rodar(cmd, { toolName: ferramenta }).status, 0);
}
for (const ferramenta of ["MultiEdit", "NotebookEdit"]) {
  const campo = ferramenta === "NotebookEdit" ? { notebook_path: path.join(projeto, ".rainforest-gate-off") }
    : { file_path: path.join(projeto, ".rainforest-gate-off") };
  caso(`${ferramenta} em .rainforest-gate-off passa`, rodar("", { toolName: ferramenta, toolInput: campo }).status, 0);
}

// === Resultado ===

console.log("");
if (falhou === 0) {
  console.log(`${ok} ok, 0 falha(s)`);
  process.exit(0);
} else {
  console.log(`${ok} ok, ${falhou} falha(s)`);
  process.exit(1);
}
