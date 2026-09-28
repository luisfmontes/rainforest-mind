#!/usr/bin/env node
"use strict";
/* Bateria do gate-subagente-sem-gh (D1, D2, D3, D6 — tarefa 1 do plano
 * `docs/rainforest/planos/gate-subagente-sem-gh.md`).
 *
 * O payload é o mesmo fixture de `gate-bateria-sem-timeout` (payload real de
 * PreToolUse/Bash de subagente, capturado em 2026-09-24), com só
 * `tool_input.command` trocado por caso.
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

const HOOK = path.join(__dirname, "gate-subagente-sem-gh.cjs");
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

const caixa = fs.mkdtempSync(path.join(os.tmpdir(), "subagente-sem-gh-"));
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

console.log("== gate-subagente-sem-gh ==");

// === D2/D3: comandos que ESCREVEM no GitHub → 2 em subagente ===

let r = rodar("gh issue close 12");
caso("(D2) gh issue close 12 em subagente", r.status, 2);

r = rodar("gh issue comment 12 -b x");
caso("gh issue comment 12 -b x em subagente", r.status, 2);

r = rodar("gh pr merge 1");
caso("gh pr merge 1 em subagente", r.status, 2);

r = rodar("gh pr create -t t -b b");
caso("gh pr create -t t -b b em subagente", r.status, 2);

r = rodar("gh release create v1");
caso("gh release create v1 em subagente", r.status, 2);

// Integração (2026-09-28): flag global antes da família, ou entre família e
// verbo, e `-XPOST` colado escapavam (saíam 0).
r = rodar("gh -R o/r issue close 12");
caso("(integração) gh -R o/r issue close 12 em subagente", r.status, 2);
r = rodar("gh --repo o/r pr create -t t -b b");
caso("(integração) gh --repo o/r pr create em subagente", r.status, 2);
r = rodar("gh issue -R o/r close 12");
caso("(integração) gh issue -R o/r close 12 em subagente", r.status, 2);
r = rodar("gh api -XPOST repos/o/r/issues");
caso("(integração) gh api -XPOST em subagente", r.status, 2);
r = rodar("gh -R o/r issue view 12");
caso("(integração) gh -R o/r issue view 12 (leitura) em subagente", r.status, 0);

r = rodar("gh workflow run x.yml");
caso("gh workflow run x.yml em subagente", r.status, 2);

r = rodar("gh run rerun 1");
caso("gh run rerun 1 em subagente", r.status, 2);

r = rodar("gh api -X PATCH repos/o/r/issues/1 -f state=closed");
caso("gh api -X PATCH ... em subagente", r.status, 2);

r = rodar("gh api repos/o/r/issues/1/comments -f body=x");
caso("gh api ... -f body=x sem -X (POST implícito) em subagente", r.status, 2);

r = rodar("gh issue \\close 12");
caso("gh issue \\close 12 (contrabarra) em subagente", r.status, 2);

r = rodar("gh issue $'close' 12");
caso("gh issue $'close' 12 (ANSI-C) em subagente", r.status, 2);

r = rodar("stdbuf -oL gh issue close 12");
caso("stdbuf -oL gh issue close 12 em subagente", r.status, 2);

r = rodar('bash -c "gh issue close 12"');
caso('bash -c "gh issue close 12" em subagente', r.status, 2);

r = rodar('bash -c "$x"');
caso('bash -c "$x" (ilegível) em subagente', r.status, 2);

r = rodar('eval "$x"');
caso('eval "$x" (ilegível) em subagente', r.status, 2);

r = rodar("cat > /tmp/x.sh <<'EOF'\ngh issue close 12\nEOF");
caso("cat > /tmp/x.sh <<'EOF' com gh issue close 12 no corpo em subagente", r.status, 2);

// === Mensagem de bloqueio (D6): nomeia o comando, diz que é da janela
// principal, e mostra como medir pelo payload no stdin ===
r = rodar("gh issue close 12");
casoContem(
  "(D6) mensagem de bloqueio nomeia o comando, a janela principal e o payload no stdin",
  r.status, r.stderr, 2,
  ["gh issue close 12", "janela principal", "payload JSON no stdin"]
);

// === Leituras (não podem quebrar) → 0 ===

r = rodar("gh issue view 12");
caso("gh issue view 12 (leitura) em subagente", r.status, 0);

r = rodar("gh issue list");
caso("gh issue list (leitura) em subagente", r.status, 0);

r = rodar("gh pr view 1");
caso("gh pr view 1 (leitura) em subagente", r.status, 0);

r = rodar("gh pr checks 1");
caso("gh pr checks 1 (leitura) em subagente", r.status, 0);

r = rodar("gh run view 1");
caso("gh run view 1 (leitura) em subagente", r.status, 0);

r = rodar("gh api repos/o/r/issues/1");
caso("gh api repos/o/r/issues/1 (GET, leitura) em subagente", r.status, 0);

r = rodar("gh api -X GET repos/o/r/issues -f state=open");
caso("gh api -X GET ... -f state=open (GET explícito) em subagente", r.status, 0);

r = rodar('echo "gh issue close 12"');
caso('echo "gh issue close 12" (texto citado) em subagente', r.status, 0);

// === Janela principal (sem agent_id) — nunca barrada ===

r = rodar("gh issue close 12", { subagente: false });
caso("gh issue close 12 sem agent_id (janela principal)", r.status, 0);

r = rodar("gh pr create -t t -b b", { subagente: false });
caso("gh pr create -t t -b b sem agent_id (janela principal)", r.status, 0);

r = rodar("node scripts/fechar-issue.cjs 12 --comando x --saida y", { subagente: false });
caso("node scripts/fechar-issue.cjs ... sem agent_id (janela principal)", r.status, 0);

// === Bateria versionada roda em subagente (sem gh na linha de comando) ===

r = rodar("bash hooks/testa-gate-fechar-issue.sh");
caso("bash hooks/testa-gate-fechar-issue.sh em subagente", r.status, 0);

r = rodar("node hooks/testa-gate-bateria-sem-timeout.cjs");
caso("node hooks/testa-gate-bateria-sem-timeout.cjs em subagente", r.status, 0);

// === Toggle desligado no projeto → 0 mesmo com escrita ===

r = rodar("gh issue close 12", { config: { "subagente-sem-gh": false } });
caso("toggle subagente-sem-gh false no projeto → 0", r.status, 0);

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

// =====================================================================
// Tarefa 2 (D4/D5): script executado é lido, com isenção de bateria
// rastreada. Caixa de areia própria (mktemp -d), arquivos REAIS em disco —
// os fixtures só CONTÊM o texto `gh issue close 12`/forma de chamada, NUNCA
// são executados: a bateria só manda o payload PreToolUse ao hook.
// =====================================================================

function toPosix(p) {
  return p.split(path.sep).join("/");
}

function rodarComCwd(comando, cwdReal, { subagente = true } = {}) {
  const payload = JSON.parse(JSON.stringify(BASE));
  payload.tool_input.command = comando;
  payload.cwd = cwdReal;
  if (!subagente) { delete payload.agent_id; delete payload.agent_type; }
  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload), encoding: "utf8",
    env: { ...process.env, CLAUDE_PROJECT_DIR: cwdReal, RFM_ROOT: path.join(caixa, "dados-d4-d5") },
  });
  return { status: r.status, stderr: r.stderr || "" };
}

console.log("== gate-subagente-sem-gh (tarefa 2: D4/D5) ==");

// --- D4: segmento executa um arquivo — lido antes de rodar ---

const sandboxD4 = path.join(caixa, "sandbox-d4");
fs.mkdirSync(sandboxD4, { recursive: true });
fs.writeFileSync(path.join(sandboxD4, "x.sh"), "gh issue close 12\n");
fs.writeFileSync(path.join(sandboxD4, "view.sh"), "gh issue view 12\n");
fs.writeFileSync(path.join(sandboxD4, "commentado.sh"), "# gh issue close 12\n");
fs.writeFileSync(path.join(sandboxD4, "y.cjs"), "execFileSync('gh', ['issue', 'close', '12']);\n");

const xshAbs = toPosix(path.join(sandboxD4, "x.sh"));

r = rodarComCwd(`bash ${xshAbs}`, sandboxD4);
casoContem("(D4) bash script avulso com gh issue close", r.status, r.stderr, 2, ["x.sh:1"]);

r = rodarComCwd(`sh ${xshAbs}`, sandboxD4);
caso("(D4) sh <caminho absoluto de x.sh> em subagente", r.status, 2);

// Integração (2026-09-28): quatro formas escapavam da leitura do script.
fs.writeFileSync(path.join(sandboxD4, "y.py"), "import subprocess\nsubprocess.run(['gh', 'issue', 'close', '12'])\n");
fs.writeFileSync(path.join(sandboxD4, "z.sh"), "G=gh\n$G issue close 12\n");
r = rodarComCwd(`python3 ${toPosix(path.join(sandboxD4, "y.py"))}`, sandboxD4);
caso("(integração) python3 script com gh issue close", r.status, 2);
r = rodarComCwd(`bash < ${xshAbs}`, sandboxD4);
caso("(integração) bash < x.sh (stdin redirecionado)", r.status, 2);
r = rodarComCwd(`cat ${xshAbs} | bash`, sandboxD4);
caso("(integração) cat x.sh | bash (pipe)", r.status, 2);
r = rodarComCwd(`bash ${toPosix(path.join(sandboxD4, "z.sh"))}`, sandboxD4);
caso("(integração) script com variavel no lugar do gh", r.status, 2);
r = rodarComCwd(`cat ${xshAbs} | grep issue`, sandboxD4);
caso("(integração) cat x.sh | grep (leitura, nao interpretador)", r.status, 0);

r = rodarComCwd(`source ${xshAbs}`, sandboxD4);
caso("(D4) source <caminho absoluto de x.sh> em subagente", r.status, 2);

r = rodarComCwd(`. ${xshAbs}`, sandboxD4);
caso("(D4) . <caminho absoluto de x.sh> (dot) em subagente", r.status, 2);

r = rodarComCwd("./x.sh", sandboxD4);
caso("(D4) ./x.sh (caminho direto) em subagente", r.status, 2);

r = rodarComCwd("bash x.sh", sandboxD4);
caso("(D4) bash x.sh (caminho relativo resolvido contra o cwd do payload) em subagente", r.status, 2);

r = rodarComCwd("bash view.sh", sandboxD4);
caso("(D4) bash view.sh (só gh issue view, leitura) em subagente", r.status, 0);

r = rodarComCwd("bash commentado.sh", sandboxD4);
caso("(D4) bash commentado.sh (linha # gh issue close 12 comentada) em subagente", r.status, 0);

r = rodarComCwd("bash nao-existe.sh", sandboxD4);
caso("(D4) bash nao-existe.sh (arquivo inexistente) em subagente", r.status, 0);

r = rodarComCwd("node y.cjs", sandboxD4);
caso("(D4) node y.cjs (forma de chamada execFileSync('gh', [...])) em subagente", r.status, 2);

// --- D5: isenção de bateria testa-* rastreada, e exceção de fechar-issue.cjs ---

const sandboxD5 = path.join(caixa, "sandbox-d5");
fs.mkdirSync(sandboxD5, { recursive: true });
spawnSync("git", ["init", "-q"], { cwd: sandboxD5 });
spawnSync("git", ["config", "user.email", "teste" + "@" + "invalido.local"], { cwd: sandboxD5 });
spawnSync("git", ["config", "user.name", "Teste"], { cwd: sandboxD5 });

fs.writeFileSync(path.join(sandboxD5, "testa-a.sh"), "gh issue close 12\n");
spawnSync("git", ["add", "testa-a.sh"], { cwd: sandboxD5 });
spawnSync("git", ["commit", "-q", "-m", "fixture testa-a"], { cwd: sandboxD5 });

r = rodarComCwd("bash testa-a.sh", sandboxD5);
caso("(D5) testa-a.sh rastreado (commitado) com gh issue close 12 em subagente", r.status, 0);

fs.writeFileSync(path.join(sandboxD5, "testa-a.sh"), "gh issue close 12\necho depois do commit\n");
r = rodarComCwd("bash testa-a.sh", sandboxD5);
caso("(D5) testa-a.sh alterado depois do commit continua isento", r.status, 0);

fs.writeFileSync(path.join(sandboxD5, "testa-b.sh"), "gh issue close 12\n");
spawnSync("git", ["add", "testa-b.sh"], { cwd: sandboxD5 });
r = rodarComCwd("bash testa-b.sh", sandboxD5);
caso("(D5) testa-b.sh só no stage (git add, sem commit) em subagente", r.status, 0);

fs.writeFileSync(path.join(sandboxD5, "testa-c.sh"), "gh issue close 12\n");
r = rodarComCwd("bash testa-c.sh", sandboxD5);
casoContem("(D5) testa-c.sh não rastreado em subagente (mensagem diz git add)", r.status, r.stderr, 2, ["git add"]);

fs.writeFileSync(path.join(sandboxD5, "outro.sh"), "gh issue close 12\n");
spawnSync("git", ["add", "outro.sh"], { cwd: sandboxD5 });
spawnSync("git", ["commit", "-q", "-m", "fixture outro"], { cwd: sandboxD5 });
r = rodarComCwd("bash outro.sh", sandboxD5);
caso("(D5) outro.sh rastreado mas não se chama testa-* em subagente", r.status, 2);

fs.mkdirSync(path.join(sandboxD5, "scripts"), { recursive: true });
fs.writeFileSync(path.join(sandboxD5, "scripts", "fechar-issue.cjs"), "// fechador oficial, monta o comando gh dinamicamente\n");
spawnSync("git", ["add", "scripts/fechar-issue.cjs"], { cwd: sandboxD5 });
spawnSync("git", ["commit", "-q", "-m", "fixture fechar-issue"], { cwd: sandboxD5 });

r = rodarComCwd("node scripts/fechar-issue.cjs 12 --comando x --saida y", sandboxD5);
caso("(D5) node scripts/fechar-issue.cjs em subagente → pelo nome, mesmo versionado", r.status, 2);

r = rodarComCwd("node scripts/fechar-issue.cjs 12 --comando x --saida y", sandboxD5, { subagente: false });
caso("(D5) node scripts/fechar-issue.cjs sem agent_id (janela principal) → 0", r.status, 0);

console.log("-----------------------------------------");
console.log(`ok: ${ok}   falhou: ${falhou}`);
process.exit(falhou === 0 ? 0 : 1);
