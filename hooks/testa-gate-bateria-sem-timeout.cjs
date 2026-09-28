#!/usr/bin/env node
"use strict";
/* Bateria do gate-bateria-sem-timeout (D1–D3 do design agente-sem-background.md).
 *
 * O payload é o de `PreToolUse` de subagente capturado ao vivo em 2026-09-24
 * (`hooks/fixtures/busca-raiz/payload-bash-subagente.json`), com só
 * `tool_name` e `tool_input` trocados para Bash. Os comandos são as baterias
 * mencionadas no plano.
 *
 * Roda o hook como processo real, payload no stdin. Isolamento: cada caso usa
 * um projeto em mkdtemp (CLAUDE_PROJECT_DIR e RFM_ROOT dentro dele) — nunca
 * escreve em ~/.rainforest nem em ~/.claude* reais.
 *
 * Exit 0 = tudo passou; exit 1 = alguma falha.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "gate-bateria-sem-timeout.cjs");
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
    console.log(`  FALHA ${nome} — status esperado ${esperadoStatus}, obtido ${status}; trechos: ${JSON.stringify(trechosStderr)}`);
  }
}

const caixa = fs.mkdtempSync(path.join(os.tmpdir(), "bateria-sem-timeout-"));
process.on("exit", () => fs.rmSync(caixa, { recursive: true, force: true }));
const projeto = path.join(caixa, "projeto");
fs.mkdirSync(path.join(projeto, ".rainforest"), { recursive: true });

function rodar(comando, { subagente = true, config, timeout } = {}) {
  const payload = JSON.parse(JSON.stringify(BASE));
  payload.tool_input.command = comando;
  payload.cwd = projeto;
  if (!subagente) { delete payload.agent_id; delete payload.agent_type; }
  if (typeof timeout === "number") { payload.tool_input.timeout = timeout; } else { delete payload.tool_input.timeout; }
  const cfg = path.join(projeto, ".rainforest", "config.json");
  if (config) fs.writeFileSync(cfg, JSON.stringify(config)); else fs.rmSync(cfg, { force: true });
  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload), encoding: "utf8",
    env: { ...process.env, CLAUDE_PROJECT_DIR: projeto, RFM_ROOT: path.join(caixa, "dados") },
  });
  return { status: r.status, stderr: r.stderr || "" };
}

console.log("== gate-bateria-sem-timeout ==");

// === TAREFA 1: Bateria sem timeout → 2 ===

// Caso fixture 1: bash hooks/testa-gate-worktree.sh sem timeout em subagente → 2
let r = rodar("bash hooks/testa-gate-worktree.sh 2>&1 | tail -5");
caso("bash hooks/testa-gate-worktree.sh sem timeout em subagente → 2", r.status, 2);

// Caso fixture 2: node hooks/testa-gate-busca-raiz.cjs sem timeout em subagente → 2
r = rodar("node hooks/testa-gate-busca-raiz.cjs");
caso("node hooks/testa-gate-busca-raiz.cjs sem timeout em subagente → 2", r.status, 2);

// Caso 3: timeout 300 bash scripts/testa-estado.sh sem parâmetro timeout → 2
r = rodar("timeout 300 bash scripts/testa-estado.sh");
caso("timeout 300 bash scripts/testa-estado.sh sem parâmetro timeout → 2", r.status, 2);

// Caso 4: node scripts/conferir-mutacao.cjs sem timeout → 2
r = rodar("node scripts/conferir-mutacao.cjs --arquivo x --de a --para b --bateria c");
caso("node scripts/conferir-mutacao.cjs sem timeout → 2", r.status, 2);

// Caso 5: node scripts/conferir-fluxo.cjs mutacoes sem timeout → 2
r = rodar("node scripts/conferir-fluxo.cjs mutacoes --slug x");
caso("node scripts/conferir-fluxo.cjs mutacoes sem timeout → 2", r.status, 2);

// Caso 6: ./scripts/testa-estado.sh sem timeout → 2
r = rodar("./scripts/testa-estado.sh");
caso("./scripts/testa-estado.sh sem timeout → 2", r.status, 2);

// Caso 7: bash hooks/testa-gate-worktree.sh com timeout: 120000 (exatamente no limiar, rejeita) → 2
r = rodar("bash hooks/testa-gate-worktree.sh", { timeout: 120000 });
caso("bash hooks/testa-gate-worktree.sh com timeout: 120000 em subagente → 2", r.status, 2);

// Caso 8: bash hooks/testa-gate-worktree.sh 2>&1 | tail -5 sem timeout → 2 com asserção de stderr (fixture 1 revisão 1)
r = rodar("bash hooks/testa-gate-worktree.sh 2>&1 | tail -5");
casoContem("bash hooks/testa-gate-worktree.sh 2>&1 | tail -5 sem timeout → 2", r.status, r.stderr, 2, ["timeout: 600000", "bateria-sem-timeout"]);

// Caso 9: scripts/testa-estado.sh (caminho direto) sem timeout → 2
r = rodar("scripts/testa-estado.sh");
caso("scripts/testa-estado.sh sem timeout → 2", r.status, 2);

// Caso 10: hooks/testa-gate-worktree.sh (caminho direto) sem timeout → 2
r = rodar("hooks/testa-gate-worktree.sh");
caso("hooks/testa-gate-worktree.sh sem timeout → 2", r.status, 2);

// Caso 11: /c/Projetos/rainforest-mind/scripts/testa-estado.sh (caminho absoluto MSYS) sem timeout → 2
r = rodar("/c/Projetos/rainforest-mind/scripts/testa-estado.sh");
caso("/c/Projetos/rainforest-mind/scripts/testa-estado.sh sem timeout → 2", r.status, 2);

// Caso 12: C:/Projetos/rainforest-mind/scripts/testa-estado.sh (caminho absoluto Windows) sem timeout → 2
r = rodar("C:/Projetos/rainforest-mind/scripts/testa-estado.sh");
caso("C:/Projetos/rainforest-mind/scripts/testa-estado.sh sem timeout → 2", r.status, 2);

// Caso 13: bash \ + quebra + hooks/testa-gate-worktree.sh (continuação de linha) sem timeout → 2
r = rodar("bash \\\n  hooks/testa-gate-worktree.sh");
caso("bash \\\\\\n  hooks/testa-gate-worktree.sh sem timeout → 2", r.status, 2);

// Caso 14: (cd <wt> && bash scripts/testa-estado.sh) (subshell) sem timeout → 2
r = rodar("(cd " + projeto + " && bash scripts/testa-estado.sh)");
caso("(cd <wt> && bash scripts/testa-estado.sh) sem timeout → 2", r.status, 2);

// Caso 15: echo $(bash scripts/testa-estado.sh) (substituição) sem timeout → 2
r = rodar("echo $(bash scripts/testa-estado.sh)");
caso("echo $(bash scripts/testa-estado.sh) sem timeout → 2", r.status, 2);

// Caso 16: cd <wt> && bash hooks/testa-gate-worktree.sh 2>&1 | tail -5 com asserção de stderr
r = rodar("cd " + projeto + " && bash hooks/testa-gate-worktree.sh 2>&1 | tail -5");
casoContem("cd <wt> && bash hooks/testa-gate-worktree.sh 2>&1 | tail -5 → 2", r.status, r.stderr, 2, ["timeout: 600000", "bateria-sem-timeout"]);

// === TAREFA 1: Permite (pass → 0) ===

// Caso 1: bash hooks/testa-gate-worktree.sh com timeout: 600000 → 0
r = rodar("bash hooks/testa-gate-worktree.sh", { timeout: 600000 });
caso("bash hooks/testa-gate-worktree.sh com timeout: 600000 → 0", r.status, 0);

// Caso 2: cat hooks/testa-gate-worktree.sh → 0 (leitura)
r = rodar("cat hooks/testa-gate-worktree.sh");
caso("cat hooks/testa-gate-worktree.sh → 0", r.status, 0);

// Caso 3: grep -n x scripts/testa-estado.sh → 0 (leitura)
r = rodar("grep -n x scripts/testa-estado.sh");
caso("grep -n x scripts/testa-estado.sh → 0", r.status, 0);

// Caso 4: sed -n 1,5p hooks/testa-gate-busca-raiz.cjs → 0 (leitura)
r = rodar("sed -n 1,5p hooks/testa-gate-busca-raiz.cjs");
caso("sed -n 1,5p hooks/testa-gate-busca-raiz.cjs → 0", r.status, 0);

// Caso 5: node scripts/conferir-fluxo.cjs cobertura --slug x → 0 (não é mutacoes)
r = rodar("node scripts/conferir-fluxo.cjs cobertura --slug x");
caso("node scripts/conferir-fluxo.cjs cobertura --slug x → 0", r.status, 0);

// Caso 6: cat com heredoc contendo bateria → 0 (corpo é texto)
r = rodar("cat <<'EOF'\nbash hooks/testa-gate-worktree.sh\nEOF");
caso("cat <<'EOF' com bash hooks/testa-gate-worktree.sh no corpo → 0", r.status, 0);

// Caso 6b: git diff -- hooks/testa-x.sh → 0 (leitura)
r = rodar("git diff -- hooks/testa-x.sh");
caso("git diff -- hooks/testa-x.sh → 0", r.status, 0);

// Caso 6c: git log -- hooks/testa-x.sh → 0 (leitura)
r = rodar("git log -- hooks/testa-x.sh");
caso("git log -- hooks/testa-x.sh → 0", r.status, 0);

// Caso 6d: ls hooks/testa-*.cjs → 0 (leitura)
r = rodar("ls hooks/testa-*.cjs");
caso("ls hooks/testa-*.cjs → 0", r.status, 0);

// Caso 6e: echo "rode bash hooks/testa-x.sh" → 0 (texto)
r = rodar("echo \"rode bash hooks/testa-x.sh\"");
caso("echo \"rode bash hooks/testa-x.sh\" → 0", r.status, 0);

// Caso 6f: git commit -m "bash hooks/testa-x.sh" → 0 (texto)
r = rodar("git commit -m \"bash hooks/testa-x.sh\"");
caso("git commit -m \"bash hooks/testa-x.sh\" → 0", r.status, 0);

// === Achado 1: Segmentação cega a aspas (revisão 2) ===

// Caso 6g: gh pr create --body "Teste: cd wt && bash hooks/testa-x.sh" → 0 (&& dentro de aspas é texto)
r = rodar("gh pr create --title t --body \"Teste: cd wt && bash hooks/testa-x.sh\"");
caso("gh pr create --body \"Teste: && bash hooks/testa-x.sh\" → 0", r.status, 0);

// Caso 6h: git commit -m "gate: nega bateria; bash hooks/testa-x.sh exige timeout" → 0 (; dentro de aspas)
r = rodar("git commit -m \"gate: nega bateria; bash hooks/testa-x.sh exige timeout\"");
caso("git commit -m \"gate: ; bash hooks/testa-x.sh exige timeout\" → 0", r.status, 0);

// Caso 6i: git commit -m "gate (bash hooks/testa-x.sh) sem timeout" → 0 (() dentro de aspas)
r = rodar("git commit -m \"gate (bash hooks/testa-x.sh) sem timeout\"");
caso("git commit -m \"gate (bash hooks/testa-x.sh) sem timeout\" → 0", r.status, 0);

// Caso 6j: git commit -m "x && y" → 0 (&& dentro de aspas é texto)
r = rodar("git commit -m \"x && y\"");
caso("git commit -m \"x && y\" → 0", r.status, 0);

// === Achado 2: Envoltório com flag (revisão 2) ===

// Caso 6k: nice -n 10 bash hooks/testa-x.sh sem timeout → 2
r = rodar("nice -n 10 bash hooks/testa-x.sh");
caso("nice -n 10 bash hooks/testa-x.sh sem timeout → 2", r.status, 2);

// Caso 6l: timeout -k 5 300 bash hooks/testa-x.sh sem timeout → 2
r = rodar("timeout -k 5 300 bash hooks/testa-x.sh");
caso("timeout -k 5 300 bash hooks/testa-x.sh sem timeout → 2", r.status, 2);

// Caso 6m: env -i bash hooks/testa-x.sh sem timeout → 2
r = rodar("env -i bash hooks/testa-x.sh");
caso("env -i bash hooks/testa-x.sh sem timeout → 2", r.status, 2);

// Revisão 3 (rodada extra): `stdbuf` repassa o comando como `nice`; checagem
// de sintaxe não é execução; `-x`/`-e` continuam sendo execução.
r = rodar("stdbuf -oL bash hooks/testa-x.sh");
caso("stdbuf -oL bash hooks/testa-x.sh sem timeout → 2", r.status, 2);
r = rodar("stdbuf -i0 -o0 -e0 bash hooks/testa-x.sh");
caso("stdbuf -i0 -o0 -e0 bash hooks/testa-x.sh sem timeout → 2", r.status, 2);
r = rodar("stdbuf -o L bash hooks/testa-x.sh");
caso("stdbuf -o L bash hooks/testa-x.sh sem timeout → 2", r.status, 2);
r = rodar("stdbuf --output L bash hooks/testa-x.sh");
caso("(#346) stdbuf --output L (forma longa com espaco) sem timeout → 2", r.status, 2);
r = rodar("stdbuf -oL bash hooks/testa-x.sh", { timeout: 600000 });
caso("stdbuf -oL bash hooks/testa-x.sh com timeout: 600000 → 0", r.status, 0);
r = rodar("stdbuf -oL git log -- hooks/testa-x.sh");
caso("stdbuf -oL git log -- hooks/testa-x.sh → 0", r.status, 0);
r = rodar("bash -n hooks/testa-x.sh");
caso("bash -n hooks/testa-x.sh sem timeout → 0 (só sintaxe)", r.status, 0);
r = rodar("node --check hooks/testa-x.cjs");
caso("node --check hooks/testa-x.cjs sem timeout → 0 (só sintaxe)", r.status, 0);
r = rodar("bash -x hooks/testa-x.sh");
caso("bash -x hooks/testa-x.sh sem timeout → 2", r.status, 2);
r = rodar("bash -e hooks/testa-x.sh");
caso("bash -e hooks/testa-x.sh sem timeout → 2", r.status, 2);

// === Casos adicionais ===

// Caso 6n: echo "$(bash hooks/testa-x.sh)" → 2 (substituição dentro de aspas duplas executa)
r = rodar("echo \"$(bash hooks/testa-x.sh)\"");
caso("echo \"$(bash hooks/testa-x.sh)\" sem timeout → 2", r.status, 2);

// Caso 6o: echo '$(bash hooks/testa-x.sh)' → 0 (aspas simples são literais)
r = rodar("echo '$(bash hooks/testa-x.sh)'");
caso("echo '$(bash hooks/testa-x.sh)' → 0", r.status, 0);

// Caso 6p: bash -c "bash hooks/testa-x.sh" com timeout 600000 → 0 (string desempacotada legível)
r = rodar("bash -c \"bash hooks/testa-x.sh\"", { timeout: 600000 });
caso("bash -c \"bash hooks/testa-x.sh\" com timeout 600000 → 0", r.status, 0);

// Caso 7: payload sem agent_id com bateria sem timeout → 0 (janela principal)
r = rodar("bash hooks/testa-gate-worktree.sh", { subagente: false });
caso("bash hooks/testa-gate-worktree.sh sem timeout, sem agent_id (janela) → 0", r.status, 0);

// Caso 8: toggle desligado no projeto → 0
r = rodar("bash hooks/testa-gate-worktree.sh", { config: { "bateria-sem-timeout": false } });
caso("toggle bateria-sem-timeout false no projeto → 0", r.status, 0);

// Caso 9: tool_name diferente de Bash → 0
const payloadEdit = JSON.parse(JSON.stringify(BASE));
payloadEdit.tool_input = { file_path: "/tmp/x" };
payloadEdit.tool_name = "Read";
const r9 = spawnSync(process.execPath, [HOOK], {
  input: JSON.stringify(payloadEdit), encoding: "utf8",
  env: { ...process.env, CLAUDE_PROJECT_DIR: projeto },
});
caso("tool_name = Read, não Bash → 0", r9.status, 0);

// Caso 10: stdin vazio → 0
const r10 = spawnSync(process.execPath, [HOOK], {
  input: "", encoding: "utf8",
  env: { ...process.env, CLAUDE_PROJECT_DIR: projeto },
});
caso("stdin vazio → 0", r10.status, 0);

// === TAREFA 2: Varredura completa negada ===

// Caso fixture: bash scripts/varrer-baterias.sh com timeout 600000 em subagente → 2 (com asserção de stderr)
r = rodar("bash scripts/varrer-baterias.sh", { timeout: 600000 });
casoContem("bash scripts/varrer-baterias.sh com timeout 600000 em subagente → 2", r.status, r.stderr, 2, ["--so", "varredura completa"]);

// Caso 2: cd <wt> && bash scripts/varrer-baterias.sh com timeout 600000 → 2
r = rodar("cd " + projeto + " && bash scripts/varrer-baterias.sh", { timeout: 600000 });
caso("cd <wt> && bash scripts/varrer-baterias.sh com timeout 600000 → 2", r.status, 2);

// Caso 2b: scripts/varrer-baterias.sh (caminho direto) com timeout 600000 → 2 (D2)
r = rodar("scripts/varrer-baterias.sh", { timeout: 600000 });
casoContem("scripts/varrer-baterias.sh com timeout 600000 → 2", r.status, r.stderr, 2, ["--so", "varredura completa"]);

// Caso 3: bash scripts/varrer-baterias.sh --so hooks/testa-gate-worktree.sh com timeout 600000 → 0
r = rodar("bash scripts/varrer-baterias.sh --so hooks/testa-gate-worktree.sh", { timeout: 600000 });
caso("bash scripts/varrer-baterias.sh --so hooks/testa-gate-worktree.sh com timeout 600000 → 0", r.status, 0);

// Caso 4: bash scripts/varrer-baterias.sh --so hooks/testa-gate-worktree.sh sem timeout → 2 (regra tarefa 1)
r = rodar("bash scripts/varrer-baterias.sh --so hooks/testa-gate-worktree.sh");
caso("bash scripts/varrer-baterias.sh --so hooks/testa-gate-worktree.sh sem timeout → 2", r.status, 2);

// Caso 5: bash scripts/varrer-baterias.sh sem agent_id com timeout 600000 → 0
r = rodar("bash scripts/varrer-baterias.sh", { subagente: false, timeout: 600000 });
caso("bash scripts/varrer-baterias.sh sem agent_id (janela) com timeout 600000 → 0", r.status, 0);

// === Toggle de cwd vs CLAUDE_PROJECT_DIR ===

function rodarDoisProjetos(configDoCwd, configDoEnv, comando, timeout) {
  const doCwd = fs.mkdtempSync(path.join(caixa, "cwd-"));
  const doEnv = fs.mkdtempSync(path.join(caixa, "env-"));
  for (const [dir, cfg] of [[doCwd, configDoCwd], [doEnv, configDoEnv]]) {
    fs.mkdirSync(path.join(dir, ".rainforest"), { recursive: true });
    if (cfg) fs.writeFileSync(path.join(dir, ".rainforest", "config.json"), JSON.stringify(cfg));
  }
  const payload = JSON.parse(JSON.stringify(BASE));
  payload.tool_input.command = comando;
  payload.tool_input.timeout = timeout;
  payload.cwd = doCwd;
  const s = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload), encoding: "utf8",
    env: { ...process.env, CLAUDE_PROJECT_DIR: doEnv, RFM_ROOT: path.join(caixa, "dados") },
  });
  return s.status;
}

const status1 = rodarDoisProjetos({ "bateria-sem-timeout": false }, null, "bash hooks/testa-gate-worktree.sh", 600000);
caso("toggle: desligado no cwd vale mesmo com CLAUDE_PROJECT_DIR ligado", status1, 0);

const status2 = rodarDoisProjetos(null, { "bateria-sem-timeout": false }, "bash hooks/testa-gate-worktree.sh");
caso("toggle: padrão (ligado) no cwd bloqueia mesmo com CLAUDE_PROJECT_DIR desligado", status2, 2);

console.log("-----------------------------------------");
console.log(`ok: ${ok}   falhou: ${falhou}`);
process.exit(falhou === 0 ? 0 : 1);
