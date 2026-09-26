#!/usr/bin/env node
"use strict";
/* Bateria do gate-busca-raiz (D1–D3 do design 2026-09-25-busca-na-raiz.md).
 *
 * O payload é o de `PreToolUse` de subagente capturado ao vivo em 2026-09-24
 * (`hooks/fixtures/portaria-folha/payload-de-subagente.json`), com só
 * `tool_name` e `tool_input` trocados para Bash (fixture
 * `hooks/fixtures/busca-raiz/payload-bash-subagente.json`). Os comandos são os
 * dos incidentes medidos, copiados dos transcritos.
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

const HOOK = path.join(__dirname, "gate-busca-raiz.cjs");
const BASE = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "busca-raiz", "payload-bash-subagente.json"), "utf8"));

let ok = 0;
let falhou = 0;
function caso(nome, cond, detalhe) {
  if (cond) { ok++; console.log(`  ok   ${nome}`); }
  else { falhou++; console.log(`  FALHA ${nome}${detalhe ? ` — ${String(detalhe).slice(0, 400)}` : ""}`); }
}

const caixa = fs.mkdtempSync(path.join(os.tmpdir(), "busca-raiz-"));
process.on("exit", () => fs.rmSync(caixa, { recursive: true, force: true }));
const projeto = path.join(caixa, "projeto");
fs.mkdirSync(path.join(projeto, ".rainforest"), { recursive: true });

function rodar(comando, { subagente = true, config } = {}) {
  const payload = JSON.parse(JSON.stringify(BASE));
  payload.tool_input.command = comando;
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

console.log("== gate-busca-raiz ==");

let r = rodar("find / -iname accounts.json 2>/dev/null; cat \"$HOME/.whatsapp-mcp/accounts.json\" 2>/dev/null");
caso("subagente: find / -iname nega com o caminho conhecido na mensagem", r.status === 2 && /segundo plano/.test(r.stderr) && /caminho conhecido/.test(r.stderr), `${r.status} ${r.stderr}`);

r = rodar("find / -maxdepth 6 -iname \"payload-ok.json\" 2>/dev/null");
caso("subagente: find / -maxdepth 6 nega (profundidade não é saída)", r.status === 2, `${r.status} ${r.stderr}`);
r = rodar("find /tmp/teste 2>/dev/null; find / -maxdepth 2 -iname \"tmp\" 2>/dev/null; ls -la /");
caso("subagente: find / depois de ; nega", r.status === 2, `${r.status} ${r.stderr}`);
r = rodar("go env GOMODCACHE && find / -maxdepth 6 -type d -iname \"whatsmeow@*\"");
caso("subagente: find / depois de && nega", r.status === 2, `${r.status} ${r.stderr}`);
r = rodar("echo x | find / -name y");
caso("subagente: find / depois de | nega", r.status === 2, `${r.status} ${r.stderr}`);

for (const raiz of ["/c", "/c/", "C:/", "C:\\", "c:\\\\", "\"/\"", "'C:/'"]) {
  r = rodar(`find ${raiz} -iname ideias.jsonl`);
  caso(`subagente: raiz ${raiz} nega`, r.status === 2, `${r.status} ${r.stderr}`);
}
r = rodar("timeout 300 find / -name x");
caso("subagente: timeout N find / nega", r.status === 2, `${r.status} ${r.stderr}`);
r = rodar("find -L / -name x");
caso("subagente: find -L / nega", r.status === 2, `${r.status} ${r.stderr}`);

r = rodar("find / -iname accounts.json 2>/dev/null", { subagente: false });
caso("janela principal: find / passa", r.status === 0, `${r.status} ${r.stderr}`);

for (const cmd of [
  "find /c/Projetos/rainforest-mind -iname \"ideias.jsonl\" 2>/dev/null | head -5",
  "find . -name y",
  "find \"$SB\" -type f",
  "grep -n \"find /\" scripts/x.sh",
  "echo find /",
  "git log --oneline -1",
]) {
  r = rodar(cmd);
  caso(`subagente: passa — ${cmd}`, r.status === 0, `${r.status} ${r.stderr}`);
}

r = rodar("find / -name x", { config: { "busca-na-raiz": false } });
caso("toggle busca-na-raiz false no projeto: passa", r.status === 0, `${r.status} ${r.stderr}`);
r = rodar("find / -name x", { config: { "busca-na-raiz": true } });
caso("toggle busca-na-raiz true no projeto: nega", r.status === 2, `${r.status} ${r.stderr}`);

// Revisão de 2026-09-25: separadores que o parser não via, e texto em heredoc.
for (const cmd of [
  "sleep 1 & find / -iname accounts.json",
  "echo $(find / -iname accounts.json)",
  "echo `find / -iname accounts.json`",
  "( find / -name x )",
  "find / -name x 2>&1 | head",
  // segunda revisão: `(` colado ao separador e substituição de processo
  "true;(find / -name x)",
  "true &&(find / -name x)",
  "true||(find / -name x)",
  "true|(find / -name x)",
  "echo hi &(find / -name x)",
  "diff <(find / -name x) /dev/null",
  "tee >(find / -name x) </dev/null",
  "x=$(true)$(find / -name x)",
  // terceira revisão: palavra antes do find
  "{ find / -name x; }",
  "if find / -name x; then echo hi; fi",
  "if find / -iname accounts.json 2>/dev/null | grep -q .; then echo tem; fi",
  "while find / -name x; do echo hi; done",
  "! find / -name x",
  "time find / -name x",
  "time -p find / -name x",
  "nice find / -name x",
  "nice -n 10 find / -name x",
  "env find / -name x",
  "env LANG=C find / -name x",
  "nohup find / -name x",
  "timeout -s KILL 10s find / -name x",
  "eval \"find / -name x\"",
  "bash -c \"find / -name x\"",
  "sh -c 'cd /tmp; find / -name x'",
]) {
  r = rodar(cmd);
  caso(`subagente: nega — ${cmd}`, r.status === 2, `${r.status} ${r.stderr}`);
}
for (const cmd of [
  "cat <<'EOF' > relato.md\nUm caso incidente foi\nfind / -iname accounts.json\nque travou.\nEOF",
  "cat <<-EOF\n\tfind / -name x\n\tEOF\necho ok",
  "find . \\( -name a -o -name b \\) -print",
  "ls >/dev/null 2>&1 && find . -name y",
  "find \"$(pwd)\" -name y",
  "diff <(find . -name a) <(find src -name a)",
  "find . \\( -name a \\) &>/dev/null",
  "if find . -name y; then echo tem; fi",
  "time find src -name y",
  "bash -c \"find . -name y\"",
  "eval \"echo find /\"",
  "echo / | xargs ls",
  "find \"/c/Program Files (x86)/App\" -iname x.exe",
]) {
  r = rodar(cmd);
  caso(`subagente: passa — ${JSON.stringify(cmd)}`, r.status === 0, `${r.status} ${r.stderr}`);
}
r = rodar("cat <<'EOF'\ntexto\nEOF\nfind / -name x");
caso("subagente: find / depois do fim do heredoc nega", r.status === 2, `${r.status} ${r.stderr}`);

// O toggle vale para o projeto do EVENTO (payload.cwd), como na portaria e nos
// gates irmãos — não para CLAUDE_PROJECT_DIR, que num worktree aponta o
// checkout principal. Dois projetos de propósito, nos dois sentidos.
function rodarDoisProjetos(configDoCwd, configDoEnv) {
  const doCwd = fs.mkdtempSync(path.join(caixa, "cwd-"));
  const doEnv = fs.mkdtempSync(path.join(caixa, "env-"));
  for (const [dir, cfg] of [[doCwd, configDoCwd], [doEnv, configDoEnv]]) {
    fs.mkdirSync(path.join(dir, ".rainforest"), { recursive: true });
    if (cfg) fs.writeFileSync(path.join(dir, ".rainforest", "config.json"), JSON.stringify(cfg));
  }
  const payload = JSON.parse(JSON.stringify(BASE));
  payload.tool_input.command = "find / -name x";
  payload.cwd = doCwd;
  const s = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload), encoding: "utf8",
    env: { ...process.env, CLAUDE_PROJECT_DIR: doEnv, RFM_ROOT: path.join(caixa, "dados") },
  });
  return s.status;
}
caso("toggle: desligado no projeto do cwd vale mesmo com CLAUDE_PROJECT_DIR ligado",
  rodarDoisProjetos({ "busca-na-raiz": false }, null) === 0);
caso("toggle: desligado só no CLAUDE_PROJECT_DIR não solta o projeto do cwd",
  rodarDoisProjetos(null, { "busca-na-raiz": false }) === 2);

for (const [nome, entrada] of [["vazio", ""], ["json inválido", "{x"], ["outra ferramenta", JSON.stringify({ ...BASE, tool_name: "Read", tool_input: { file_path: "/" } })]]) {
  const s = spawnSync(process.execPath, [HOOK], { input: entrada, encoding: "utf8", env: { ...process.env, CLAUDE_PROJECT_DIR: projeto } });
  caso(`payload ${nome}: sai 0`, s.status === 0, `${s.status} ${s.stderr}`);
}

console.log("-----------------------------------------");
console.log(`ok: ${ok}   falhou: ${falhou}`);
process.exit(falhou === 0 ? 0 : 1);
