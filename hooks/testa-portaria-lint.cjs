#!/usr/bin/env node
"use strict";
/* Bateria de testes para `portaria.cjs --lint` (Tarefa 5 do fluxo 9).
 *
 * Testa as cinco checagens de D5:
 *   1. Agente no manifesto sem arquivo correspondente → erro
 *   2. Arquivo em agentes-dir sem entrada no manifesto → aviso
 *   3. escreve:false com tool de escrita fora allowlist → erro
 *   4. Estágios desconhecidos → erro
 *   5. Manifesto inválido, sem versao, ou versao desconhecida → erro
 *
 * Chama o hook como processo real via spawnSync, assere sobre exit code e saída.
 *
 * Exit 0 = tudo passou; exit 1+ = alguma falha.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const HOOK = path.join(__dirname, "portaria.cjs");
const FIXTURES = path.join(__dirname, "..", "test", "fixtures", "portaria");

let ok = 0;
let falhou = 0;

function caso(nome, cond, detalhe) {
  if (cond) {
    ok++;
    console.log(`  ok   ${nome}`);
  } else {
    falhou++;
    console.log(`  FALHA ${nome}${detalhe ? ` — ${detalhe}` : ""}`);
  }
}

function rodaLint(manifestoPath, agentesDir) {
  return spawnSync(process.execPath, [HOOK, "--lint", "--manifesto", manifestoPath, "--agentes-dir", agentesDir], {
    encoding: "utf8",
  });
}

// == 1. Caminho verde: manifesto-ok.json → exit 0 ==
console.log("== 1. caminho verde ==");
{
  const manifestoPath = path.join(FIXTURES, "manifesto-ok.json");
  const agentesDir = path.join(FIXTURES, "agentes");
  const r = rodaLint(manifestoPath, agentesDir);

  caso("exit 0", r.status === 0, `exit=${r.status}`);
}

// == 2. Agente sem arquivo (checagem 1) → exit ≠ 0, nomeado na saída ==
console.log("== 2. agente sem arquivo ==");
{
  const manifestoPath = path.join(FIXTURES, "manifesto-agente-sem-arquivo.json");
  const agentesDir = path.join(FIXTURES, "agentes");
  const r = rodaLint(manifestoPath, agentesDir);

  caso("exit ≠ 0", r.status !== 0, `exit=${r.status}`);
  caso("saída menciona 'inexistente'", (r.stderr + r.stdout).includes("inexistente"), `stderr: ${r.stderr}, stdout: ${r.stdout}`);
}

// == 3. escreve:false com Write (checagem 3) → exit ≠ 0, nomeado ==
console.log("== 3. escreve inconsistente ==");
{
  const manifestoPath = path.join(FIXTURES, "manifesto-escreve-inconsistente.json");
  const agentesDir = path.join(FIXTURES, "agentes");
  const r = rodaLint(manifestoPath, agentesDir);

  caso("exit ≠ 0", r.status !== 0, `exit=${r.status}`);
  caso("saída menciona 'escritor'", (r.stderr + r.stdout).includes("escritor"), `stderr: ${r.stderr}, stdout: ${r.stdout}`);
}

// == 4. Estágio desconhecido (checagem 4) → exit ≠ 0, nomeado ==
console.log("== 4. estagio desconhecido ==");
{
  const manifestoPath = path.join(FIXTURES, "manifesto-estagio-desconhecido.json");
  const agentesDir = path.join(FIXTURES, "agentes");
  const r = rodaLint(manifestoPath, agentesDir);

  caso("exit ≠ 0", r.status !== 0, `exit=${r.status}`);
  caso("saída menciona estágio", (r.stderr + r.stdout).includes("estago_fantasma"), `stderr: ${r.stderr}, stdout: ${r.stdout}`);
}

// == 5. Manifesto JSON inválido (checagem 5) → exit ≠ 0 ==
console.log("== 5. manifesto invalido ==");
{
  const manifestoPath = path.join(FIXTURES, "manifesto-invalido.json");
  const agentesDir = path.join(FIXTURES, "agentes");
  const r = rodaLint(manifestoPath, agentesDir);

  caso("exit ≠ 0", r.status !== 0, `exit=${r.status}`);
}

// == 6. Órfão: arquivo sem entrada (checagem 2) → exit 0 (aviso), nomeado ==
console.log("== 6. agente orfao (aviso, nao erro) ==");
{
  const manifestoPath = path.join(FIXTURES, "manifesto-ok.json"); // Só declara 'leitor'
  const agentesDir = path.join(FIXTURES, "agentes"); // Tem 'leitor' e 'escritor'
  const r = rodaLint(manifestoPath, agentesDir);

  caso("exit 0 (aviso não muda)", r.status === 0, `exit=${r.status}`);
  caso("saída menciona 'escritor' como órfão", (r.stderr + r.stdout).includes("escritor"), `stderr: ${r.stderr}, stdout: ${r.stdout}`);
}

// == 7. Manifesto sem versao → exit ≠ 0 ==
console.log("== 7. manifesto sem versao ==");
{
  // Criar manifesto sem versao temporariamente
  const tmpDir = fs.mkdtempSync(path.join(require("os").tmpdir(), "lint-test-"));
  const tmpManifesto = path.join(tmpDir, "manifesto.json");
  fs.writeFileSync(tmpManifesto, JSON.stringify({
    agentes: {
      leitor: { estagios: ["executar"], escreve: false }
    }
  }, null, 2), "utf8");

  const agentesDir = path.join(FIXTURES, "agentes");
  const r = rodaLint(tmpManifesto, agentesDir);

  caso("exit ≠ 0", r.status !== 0, `exit=${r.status}`);
  caso("saída menciona 'versao'", (r.stderr + r.stdout).includes("versao"), `stderr: ${r.stderr}, stdout: ${r.stdout}`);

  fs.rmSync(tmpDir, { recursive: true, force: true });
}

// == 8. Manifesto com versao desconhecida (99) → exit ≠ 0 ==
console.log("== 8. manifesto com versao desconhecida ==");
{
  const tmpDir = fs.mkdtempSync(path.join(require("os").tmpdir(), "lint-test-"));
  const tmpManifesto = path.join(tmpDir, "manifesto.json");
  fs.writeFileSync(tmpManifesto, JSON.stringify({
    versao: 99,
    agentes: {
      leitor: { estagios: ["executar"], escreve: false }
    }
  }, null, 2), "utf8");

  const agentesDir = path.join(FIXTURES, "agentes");
  const r = rodaLint(tmpManifesto, agentesDir);

  caso("exit ≠ 0", r.status !== 0, `exit=${r.status}`);
  caso("saída menciona versao 99", (r.stderr + r.stdout).includes("99"), `stderr: ${r.stderr}, stdout: ${r.stdout}`);

  fs.rmSync(tmpDir, { recursive: true, force: true });
}

console.log(`\n== resultado: ${ok} ok, ${falhou} falha(s) ==`);

if (falhou > 0) {
  process.exit(1);
} else {
  console.log("todos os casos: OK");
  process.exit(0);
}
