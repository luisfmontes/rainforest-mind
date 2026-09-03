#!/bin/bash
# Bateria do cwd-efetivo.cjs. Testa resolução do diretório efetivo
# onde comandos Bash rodam, seguindo `cd` e `git -C`.
# Uso: bash hooks/testa-cwd-efetivo.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT

# Script Node para rodar os testes
TESTE_JS="$RAIZ/teste.js"
cat > "$TESTE_JS" << 'NODESCRIPT'
const path = require("path");
const fs = require("fs");
const { resolverCwdEfetivo, toplevelConfinado } = require(process.argv[2]);
const { execSync } = require("child_process");

let ok = 0, falhou = 0;

function test(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`  ok   ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`  FALHA ${nome}: ${e.message}`);
  }
}

function eq(obtido, esperado, msg) {
  if (obtido !== esperado) {
    throw new Error(`${msg}: esperava '${esperado}', veio '${obtido}'`);
  }
}

// Cria estrutura de teste
const testDir = process.argv[3];
const testA = path.join(testDir, "test-a");
const testB = path.join(testDir, "projeto");
const testD = path.join(testDir, "test-d");
const repoPai = path.join(testDir, "repo-pai");
const subdir = path.join(repoPai, "subdir");

fs.mkdirSync(testA, { recursive: true });
fs.mkdirSync(testB, { recursive: true });
fs.mkdirSync(testD, { recursive: true });
fs.mkdirSync(repoPai, { recursive: true });
fs.mkdirSync(subdir, { recursive: true });

// Setup repo para teste (e)
try {
  execSync(`git init -q "${repoPai}"`, { stdio: "ignore" });
  execSync(`git -C "${repoPai}" config user.email t@t`, { stdio: "ignore" });
  execSync(`git -C "${repoPai}" config user.name t`, { stdio: "ignore" });
  execSync(`git -C "${repoPai}" config commit.gpgsign false`, { stdio: "ignore" });
  fs.writeFileSync(path.join(repoPai, "arquivo.txt"), "x\n");
  execSync(`git -C "${repoPai}" add .`, { stdio: "ignore" });
  execSync(`git -C "${repoPai}" commit -qm base`, { stdio: "ignore" });
} catch (e) {
  // ignore
}

console.log("== Caso (a): cd <dir> && git commit resolve <dir> como cwd efetivo ==");
test("(a) cd resolve para dir", () => {
  const cmd = `cd '${testA}' && git commit`;
  const result = resolverCwdEfetivo(cmd, testDir);
  eq(result.cwd, testA, "cwd");
  eq(result.incerto, false, "incerto");
});

console.log();
console.log("== Caso (b): cd C:/PROJETO/x && git commit NÃO vira incerto ==");
test("(b) cd resolve sem marcar incerto", () => {
  const cmd = `cd '${testB}' && git commit`;
  const result = resolverCwdEfetivo(cmd, testDir);
  eq(result.cwd, testB, "cwd");
  eq(result.incerto, false, "incerto");
});

// Teste adicional (fixture Issue #16): caminho com til no meio (formato 8.3)
// O til no meio NÃO é expansão de home — não marca incerto
test("(b2) caminho 8.3 com til no meio NÃO marca incerto", () => {
  const pathWith8Dot3 = "C:/PROGRA~1/project";
  const cwdInicial = "C:/PROGRA~1";
  const cmd = `cd '${pathWith8Dot3}' && git commit`;
  const result = resolverCwdEfetivo(cmd, cwdInicial);
  // Sem incerteza, resolve o caminho completo
  const expectedCwd = path.resolve(cwdInicial, "project");
  eq(result.cwd, expectedCwd, "cwd");
  eq(result.incerto, false, "incerto=false com til no meio");
});

console.log();
console.log("== Caso (c): cd ~/algo && git commit vira incerto ==");
test("(c) cd ~ marca incerto", () => {
  const cmd = "cd ~/algo && git commit";
  const result = resolverCwdEfetivo(cmd, testDir);
  eq(result.incerto, true, "incerto deve ser true");
});

console.log();
console.log("== Caso (d): git -C <dir> commit resolve <dir> direto ==");
test("(d) git -C resolve para dir", () => {
  const cmd = `git -C '${testD}' commit`;
  const result = resolverCwdEfetivo(cmd, testDir);
  eq(result.cwd, testD, "cwd");
  eq(result.incerto, false, "incerto");
});

console.log();
console.log("== Caso (e): confinamento — git -C <subdir-sem-.git-proprio> ==");
test("(e) subdir sem .git próprio não é confinado", () => {
  const result = toplevelConfinado(subdir);
  eq(result.ok, false, "ok");
});

test("(e2) repo principal com .git é confinado", () => {
  const result = toplevelConfinado(repoPai);
  eq(result.ok, true, "ok");
});

console.log();
console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou);
NODESCRIPT

# Roda o teste
node "$TESTE_JS" "$SRC/hooks/lib/cwd-efetivo.cjs" "$RAIZ"
