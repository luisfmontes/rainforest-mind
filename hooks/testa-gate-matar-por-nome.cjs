#!/usr/bin/env node
"use strict";
/* Bateria do gate-matar-por-nome (Issue #517, tarefa 1 do fluxo 2026-10-14-gate-matar-por-nome).
 *
 * O payload é o mesmo fixture de `gate-subagente-sem-instalar` (payload real de
 * PreToolUse de subagente), com `tool_name`, `tool_input` e `cwd` trocados por caso.
 * Janela principal = o mesmo payload sem `agent_id` nem `agent_type`.
 *
 * Roda o hook como processo real, payload no stdin. Isolamento: cada caso usa
 * um projeto em mkdtemp (CLAUDE_PROJECT_DIR e RFM_ROOT dentro dele). O
 * `RAINFOREST_GATE_OFF` herdado do ambiente é removido, salvo nos casos que o definem.
 *
 * Nenhum caso lê o texto do fonte do gate: só roda o hook e olha a saída.
 * Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "gate-matar-por-nome.cjs");
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

function casoStderr(nome, status, stderr, esperadoStatus, { contem = [], naoContem = [] } = {}) {
  const faltando = contem.filter((t) => !stderr.includes(t));
  const proibidos = naoContem.filter((t) => stderr.includes(t));
  if (status === esperadoStatus && faltando.length === 0 && proibidos.length === 0) {
    ok++;
    console.log(`  ok    ${nome} — status ${esperadoStatus}, trechos do stderr conferem`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome} — status esperado ${esperadoStatus}, obtido ${status}; faltando ${JSON.stringify(faltando)}; proibidos ${JSON.stringify(proibidos)}; stderr: ${stderr}`);
  }
}

const caixa = fs.mkdtempSync(path.join(os.tmpdir(), "matar-por-nome-"));
process.on("exit", () => fs.rmSync(caixa, { recursive: true, force: true }));
const projeto = path.join(caixa, "projeto");
fs.mkdirSync(path.join(projeto, ".rainforest"), { recursive: true });

function rodar(comando, { subagente = true, ferramenta = "Bash", config, env = {} } = {}) {
  const payload = JSON.parse(JSON.stringify(BASE));
  payload.tool_name = ferramenta;
  payload.tool_input = { command: comando };
  payload.cwd = projeto;
  if (!subagente) { delete payload.agent_id; delete payload.agent_type; }

  const cfg = path.join(projeto, ".rainforest", "config.json");
  if (config) fs.writeFileSync(cfg, JSON.stringify(config)); else fs.rmSync(cfg, { force: true });

  const ambiente = { ...process.env, CLAUDE_PROJECT_DIR: projeto, RFM_ROOT: path.join(caixa, "dados") };
  delete ambiente.RAINFOREST_GATE_OFF;
  Object.assign(ambiente, env);

  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload), encoding: "utf8", env: ambiente,
  });
  return { status: r.status, stderr: r.stderr || "" };
}

// Pares [comando, ferramentas em que roda]. Os de cmdlet do PowerShell rodam
// nas duas ferramentas; o resto, só no Bash (é o que o Bash entrega).
const BASH = ["Bash"];
const AMBAS = ["Bash", "PowerShell"];

const CONTORNOS = [
  // taskkill por nome
  ["taskkill /IM python.exe /F", BASH],
  ["taskkill /F /IM node.exe", BASH],
  ["TASKKILL.EXE /im node.exe", BASH],
  ["taskkill -im node.exe", BASH],
  ['taskkill /FI "IMAGENAME eq python.exe" /F', BASH],
  // pkill / killall / prefixos / wrappers de string
  ["pkill node", BASH],
  ["pkill -f python", BASH],
  ['pkill -9 -f "node server"', BASH],
  ["killall node", BASH],
  ["sudo pkill x", BASH],
  ["FOO=1 killall x", BASH],
  ['bash -c "pkill node"', BASH],
  ["sh -c 'killall node'", BASH],
  // PowerShell por nome
  ["Stop-Process -Name python", AMBAS],
  ["Stop-Process -Name python -Force", AMBAS],
  ["Stop-Process -ProcessName node", AMBAS],
  ["spps -Name node", AMBAS],
  ["kill -Name node", AMBAS],
  ["Stop-Process node", AMBAS],
  // pipeline sem -Id
  ["Get-Process python | Stop-Process", AMBAS],
  ["Get-Process -Name node | Stop-Process -Force", AMBAS],
  ["gps node | spps", AMBAS],
  ["ps node | kill", AMBAS],
  ["Get-Process | Where-Object { $_.Name -eq 'node' } | Stop-Process", AMBAS],
  // substituição de comando e pgrep/pidof em pipeline
  ["kill $(pgrep python)", BASH],
  ["kill -9 $(pidof node)", BASH],
  ["kill `pgrep node`", BASH],
  ["pgrep python | xargs kill", BASH],
  ["pidof node | xargs kill -9", BASH],
  // wrappers de PowerShell
  ['pwsh -NoProfile -Command "Stop-Process -Name node"', BASH],
  ['powershell -Command "Get-Process node | Stop-Process"', BASH],
  // barra dupla do Git Bash (`//IM`), e cmd /c com ela
  ["taskkill //IM python.exe //F", BASH],
  ["taskkill //F //IM node.exe", BASH],
  ["taskkill //im node.exe", BASH],
  ['cmd.exe //c "taskkill /im node.exe"', BASH],
  // call operator e parêntese na frente do comando; abreviação -n de -Name
  ["& taskkill /IM node.exe /F", BASH],
  ["(Get-Process node) | Stop-Process", AMBAS],
  ["Stop-Process -n node", AMBAS],
  ["Stop-Process -Name node -ErrorAction SilentlyContinue", AMBAS],
  // heredoc de delimitador citado com interpretador: o corpo é executado
  ["bash <<'EOF'\npkill node\nEOF", BASH],
  ["bash <<'EOF'\nuse `pkill node` x\nEOF", BASH],
];

const LEGITIMOS = [
  // matar pelo PID
  ["taskkill /PID 1234 /F", BASH],
  ["taskkill /F /T /PID 1234", BASH],
  ["kill 1234", BASH],
  ["kill -9 1234", BASH],
  ["kill -TERM 1234 5678", BASH],
  ["Stop-Process -Id 1234", AMBAS],
  ["Stop-Process -Id 1234 -Force", AMBAS],
  ["Stop-Process 1234", AMBAS],
  ["Get-Process -Id 1234 | Stop-Process", AMBAS],
  // consultas
  ["Get-Process node", AMBAS],
  ["pgrep -a python", BASH],
  ["pidof node", BASH],
  ['tasklist /FI "IMAGENAME eq python.exe"', BASH],
  ["ps aux | grep python", BASH],
  // texto que só cita o comando
  ['echo "pkill node"', BASH],
  ['grep -rn "taskkill /IM" hooks', BASH],
  ['git commit -m "barra pkill e killall"', BASH],
  ["cat notas.txt | grep Stop-Process", BASH],
  ['git commit -m "kill $(pgrep x)"', BASH],
  ["git commit -m 'kill $(pgrep x)'", BASH],
  ["grep -rn 'kill $(pgrep' hooks", BASH],
  ['echo "kill $(pgrep node)"', BASH],
  // matar pelo PID em variável, em substituição ou em expansão: o shell troca
  // pelo número antes de rodar, então o argumento nunca é nome de processo
  ["kill $PID", BASH],
  ["kill -9 $pid", BASH],
  ["kill -s TERM $pid", BASH],
  ["kill -TERM $pid", BASH],
  ["kill $!", BASH],
  ["kill $$", BASH],
  ['kill "$pid"', BASH],
  ["kill ${pid}", BASH],
  ["kill -0 $pid", BASH],
  ["kill $SERVER_PID 2>/dev/null", BASH],
  ["node server.js & PID=$!; sleep 2; kill $PID", BASH],
  ["kill $(cat pid)", BASH],
  ["kill -9 $(cat pid)", BASH],
  ["kill $(jobs -p)", BASH],
  ["kill ${PIDS[@]}", BASH],
  ['bash -c "kill $PID"', BASH],
  ["for p in $pids; do kill $p; done", BASH],
  ["Stop-Process $p.Id", AMBAS],
  ["Stop-Process $p -Force", AMBAS],
  ["Stop-Process $proc", AMBAS],
  ["Stop-Process -Id $p.Id", AMBAS],
  ["kill $p.Id", AMBAS],
  ["Stop-Process -Id $x", AMBAS],
  ["Stop-Process -InputObject $p", AMBAS],
  ["taskkill /PID $pid /F", BASH],
  ["$p | Stop-Process", AMBAS],
  // ps como fonte de PID em pipe com xargs kill: fora do escopo (docstring)
  ["ps -p 1234 -o pid= | xargs kill", BASH],
  // parâmetros comuns do PowerShell com valor não são nome de processo
  ["Stop-Process -Id 1234 -ErrorAction SilentlyContinue", AMBAS],
  ["Stop-Process -Id 1234 -Force -ErrorAction Stop", AMBAS],
  ["Stop-Process -Id 1234 -ea SilentlyContinue", AMBAS],
  ["Stop-Process -Id $pid -Force -ErrorAction Ignore", AMBAS],
  ["Stop-Process -Force -ErrorAction SilentlyContinue -Id 1234", AMBAS],
  ["Stop-Process -InputObject $p -ErrorAction SilentlyContinue", AMBAS],
  ["Stop-Process -Id 1234 -ErrorVariable e", AMBAS],
  ["Stop-Process -Id 1234 -WarningAction SilentlyContinue", AMBAS],
  ["Stop-Process -Id 1234 -InformationAction SilentlyContinue -OutVariable saida", AMBAS],
  ["$procs | Stop-Process -Force -ErrorAction SilentlyContinue", AMBAS],
  ["Get-Process -Id 1234 | Stop-Process -ErrorAction SilentlyContinue", AMBAS],
  ['pwsh -NoProfile -Command "Stop-Process -Id 1234 -Force -ErrorAction SilentlyContinue"', BASH],
  // -Id com dois-pontos colado ao valor é o mesmo parâmetro
  ["Get-Process -Id:1234 | Stop-Process", AMBAS],
  ["Stop-Process -Id:1234", AMBAS],
  // redirecionamento não é argumento: o alvo de `<` é arquivo, não nome
  ["xargs kill -9 < pids.txt", BASH],
  // texto entre aspas simples e corpo de heredoc citado é literal, não comando
  ["git commit -m 'uso de `pkill node` no gate'", BASH],
  ["echo 'text $(pkill node)'", BASH],
  ["cat > a.md <<'EOF'\nuse `pkill node` no lugar\nEOF", BASH],
  ["cat > a.md <<'EOF'\ntexto $(pkill node) citado\nEOF", BASH],
];

console.log("== gate-matar-por-nome: contornos (esperado 2, subagente e janela) ==");
for (const [cmd, ferramentas] of CONTORNOS) {
  for (const ferramenta of ferramentas) {
    caso(`contorno: ${cmd} [${ferramenta}] subagente`, rodar(cmd, { ferramenta }).status, 2);
    caso(`contorno: ${cmd} [${ferramenta}] janela`, rodar(cmd, { ferramenta, subagente: false }).status, 2);
  }
}

console.log("");
console.log("== gate-matar-por-nome: legítimos (esperado 0, subagente e janela) ==");
for (const [cmd, ferramentas] of LEGITIMOS) {
  for (const ferramenta of ferramentas) {
    caso(`legitimo: ${cmd} [${ferramenta}] subagente`, rodar(cmd, { ferramenta }).status, 0);
    caso(`legitimo: ${cmd} [${ferramenta}] janela`, rodar(cmd, { ferramenta, subagente: false }).status, 0);
  }
}

console.log("");
console.log("== gate-matar-por-nome: mensagem de bloqueio ==");
{
  const janela = rodar("taskkill /IM python.exe /F", { subagente: false });
  casoStderr("contorno: taskkill /IM — janela: mensagem com alternativas e RAINFOREST_GATE_OFF",
    janela.status, janela.stderr, 2,
    { contem: ["taskkill /PID", "Stop-Process -Id", "tasklist", "RAINFOREST_GATE_OFF"] });
  const sub = rodar("taskkill /IM python.exe /F");
  casoStderr("contorno: taskkill /IM — subagente: mensagem com alternativas, sem RAINFOREST_GATE_OFF",
    sub.status, sub.stderr, 2,
    { contem: ["taskkill /PID", "Stop-Process -Id", "tasklist"], naoContem: ["RAINFOREST_GATE_OFF"] });
}

console.log("");
console.log("== gate-matar-por-nome: saídas de emergência ==");
caso("legitimo: config matar-por-nome=false — pkill node passa (subagente)",
  rodar("pkill node", { config: { "matar-por-nome": false } }).status, 0);
caso("legitimo: config matar-por-nome=false — pkill node passa (janela)",
  rodar("pkill node", { subagente: false, config: { "matar-por-nome": false } }).status, 0);
caso("legitimo: janela + RAINFOREST_GATE_OFF=1 — pkill node passa",
  rodar("pkill node", { subagente: false, env: { RAINFOREST_GATE_OFF: "1" } }).status, 0);
caso("contorno: subagente + RAINFOREST_GATE_OFF=1 — pkill node continua barrado",
  rodar("pkill node", { env: { RAINFOREST_GATE_OFF: "1" } }).status, 2);

console.log("");
console.log("== gate-matar-por-nome: o gate nunca derruba a sessão por erro próprio ==");
const rVazio = spawnSync(process.execPath, [HOOK], {
  input: "", encoding: "utf8",
  env: { ...process.env, CLAUDE_PROJECT_DIR: projeto },
});
caso("legitimo: stdin vazio → 0", rVazio.status, 0);

const rMalformado = spawnSync(process.execPath, [HOOK], {
  input: "{ isto nao e json", encoding: "utf8",
  env: { ...process.env, CLAUDE_PROJECT_DIR: projeto },
});
caso("legitimo: payload malformado → 0", rMalformado.status, 0);

caso("legitimo: tool_name Read, mesmo com pkill no comando → 0",
  (() => {
    const p = JSON.parse(JSON.stringify(BASE));
    p.tool_name = "Read";
    p.tool_input = { command: "pkill node" };
    p.cwd = projeto;
    return spawnSync(process.execPath, [HOOK], {
      input: JSON.stringify(p), encoding: "utf8",
      env: { ...process.env, CLAUDE_PROJECT_DIR: projeto },
    }).status;
  })(), 0);

console.log("");
if (falhou === 0) {
  console.log(`${ok} ok, 0 falha(s)`);
  process.exit(0);
} else {
  console.log(`${ok} ok, ${falhou} falha(s)`);
  process.exit(1);
}
