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
const { resolverCwdEfetivo, cwdPorSegmento, toplevelConfinado } = require(process.argv[2]);
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
console.log("== Caso (f): git -C <wt> -C <principal> resolve o ÚLTIMO ==");
test("(f) múltiplos -C: o último vence", () => {
  const cmd = `git -C '${testA}' -C '${testB}' commit`;
  const result = resolverCwdEfetivo(cmd, testDir);
  eq(result.cwd, testB, "cwd");
  eq(result.incerto, false, "incerto");
});

console.log();
console.log("== Caso (g): echo \"; cd <lixo>\" resolve o cwd INICIAL ==");
test("(g) ; dentro de aspas duplas não é separador", () => {
  const cmd = `echo "; cd '${testD}'" && git commit`;
  const result = resolverCwdEfetivo(cmd, testDir);
  eq(result.cwd, testDir, "cwd");
  eq(result.incerto, false, "incerto");
});

console.log();
console.log("== Caso (h): echo '; cd <lixo>' resolve o cwd INICIAL ==");
test("(h) ; dentro de aspas simples não é separador", () => {
  const cmd = `echo '; cd ${testD}' && git commit`;
  const result = resolverCwdEfetivo(cmd, testDir);
  eq(result.cwd, testDir, "cwd");
  eq(result.incerto, false, "incerto");
});

console.log();
console.log("== Caso (i): cd \"<dir com espaco>\" resolve o dir com espaco ==");
test("(i) cd com aspas duplas e espaço resolve corretamente", () => {
  const dirComEspaco = path.join(testDir, "dir com espaço");
  fs.mkdirSync(dirComEspaco, { recursive: true });
  const cmd = `cd "${dirComEspaco}" && git commit`;
  const result = resolverCwdEfetivo(cmd, testDir);
  eq(result.cwd, dirComEspaco, "cwd");
  eq(result.incerto, false, "incerto");
});

console.log();
console.log("== Caso (j): (cd X && y) e subshell/grupo — vira INCERTO (rodada 4, lote 3) ==");
test("(j) (cd X && y) marca incerto", () => {
  const cmd = `(cd '${testD}' && y)`;
  const result = resolverCwdEfetivo(cmd, testDir);
  eq(result.incerto, true, "incerto deve ser true");
});

console.log();
console.log("== Caso (k): cwdPorSegmento devolve o cwd de CADA segmento (H1, rodada 5) ==");
test("(k) cd A && x && cd B -> [A, A, B]", () => {
  const cmd = `cd '${testA}' && x && cd '${testB}'`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 3, "numero de segmentos");
  eq(r[0].cwd, testA, "cwd do segmento 0 (cd A)");
  eq(r[1].cwd, testA, "cwd do segmento 1 (x, sem cd)");
  eq(r[2].cwd, testB, "cwd do segmento 2 (cd B)");
  eq(r[0].incerto, false, "incerto do segmento 0");
  eq(r[2].incerto, false, "incerto do segmento 2");
});

console.log();
console.log("== Caso (l): pushd move como cd, popd desfaz (H2, rodada 5) ==");
test("(l) pushd A && x -> cwd A no segmento do x", () => {
  const cmd = `pushd '${testA}' && x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r[1].cwd, testA, "cwd apos pushd");
  eq(r[1].incerto, false, "incerto apos pushd resolvivel");
});
test("(l2) pushd A && popd && x -> volta ao cwd inicial", () => {
  const cmd = `pushd '${testA}' && popd && x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r[2].cwd, testDir, "cwd apos popd desfazer o pushd");
  eq(r[2].incerto, false, "incerto apos popd com pushd correspondente");
});
test("(l3) popd sem pushd correspondente vira INCERTO", () => {
  const cmd = `popd && x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r[0].incerto, true, "popd sem pushd marca incerto");
  eq(r[1].incerto, true, "incerto propaga para o segmento seguinte");
});

console.log();
console.log("== Caso (m): env -C muda o cwd SO daquele comando (H2, rodada 5) ==");
test("(m) env -C A cmd -> cwd A so no proprio segmento", () => {
  const cmd = `env -C '${testA}' x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r[0].cwd, testA, "cwd do segmento do env -C");
  eq(r[0].incerto, false, "incerto");
});
test("(m2) env -C A cmd && y -> NAO persiste para o segmento seguinte", () => {
  const cmd = `env -C '${testA}' x && y`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r[1].cwd, testDir, "cwd do segmento seguinte volta ao inicial");
});

console.log();
console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou);
NODESCRIPT

# Roda o teste
node "$TESTE_JS" "$SRC/hooks/lib/cwd-efetivo.cjs" "$RAIZ"
