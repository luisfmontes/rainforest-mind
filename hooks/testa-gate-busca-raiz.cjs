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

for (const [nome, entrada] of [["vazio", ""], ["json inválido", "{x"], ["outra ferramenta", JSON.stringify({ ...BASE, tool_name: "Read", tool_input: { file_path: "/" } })]]) {
  const s = spawnSync(process.execPath, [HOOK], { input: entrada, encoding: "utf8", env: { ...process.env, CLAUDE_PROJECT_DIR: projeto } });
  caso(`payload ${nome}: sai 0`, s.status === 0, `${s.status} ${s.stderr}`);
}

console.log("-----------------------------------------");
console.log(`ok: ${ok}   falhou: ${falhou}`);
process.exit(falhou === 0 ? 0 : 1);
