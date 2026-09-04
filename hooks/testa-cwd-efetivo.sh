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
// S1 (rodada 10, lote 3): dir REAL com til no meio (formato 8.3), para o
// teste (b2) continuar existindo em disco depois do fix "destino que nao
// existe vira incerto" — sem isso o fixture sintetico do Issue #16 (que
// nunca existiu de verdade) passaria a marcar incerto por um motivo NOVO
// (nao existe em disco), mascarando o que o teste queria provar (til no
// meio nao e expansao de home).
const dir8Dot3 = path.join(testDir, "PROGRA~1");
const dir8Dot3Project = path.join(dir8Dot3, "project");

fs.mkdirSync(testA, { recursive: true });
fs.mkdirSync(testB, { recursive: true });
fs.mkdirSync(testD, { recursive: true });
fs.mkdirSync(repoPai, { recursive: true });
fs.mkdirSync(dir8Dot3Project, { recursive: true });
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
  const cmd = `cd '${dir8Dot3Project}' && git commit`;
  const result = resolverCwdEfetivo(cmd, dir8Dot3);
  // Sem incerteza, resolve o caminho completo (dir existe de verdade —
  // S1 exige isso pra nao confundir "til no meio" com "nao existe em disco")
  eq(result.cwd, dir8Dot3Project, "cwd");
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
console.log("== Caso (n): '&' simples separa segmento, sem confundir com '&&' (K1, rodada 6, lote 3) ==");
test("(n) echo hi & cd A; x -> 3 segmentos, o 3o com cwd A", () => {
  const cmd = `echo hi & cd '${testA}'; x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 3, "numero de segmentos");
  eq(r[2].cwd, testA, "cwd do 3o segmento");
});
test("(o) x 2>&1 && cd A && y -> 3 segmentos, o 3o cwd A (2>&1 nao separa)", () => {
  const cmd = `x 2>&1 && cd '${testA}' && y`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 3, "numero de segmentos");
  eq(r[2].cwd, testA, "cwd do 3o segmento");
});

console.log();
console.log("== Caso (p): git \"por posicao de comando\", nao substring (K2, rodada 6, lote 3) ==");
test('(p) grep -C 3 "gitignore" . && git add -A -> 2o segmento cwd inicial, incerto false', () => {
  const cmdGit = "g" + "it";
  const cmd = `grep -rn -C 3 "gitignore" . && ${cmdGit} add -A`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[1].cwd, testDir, "cwd do 2o segmento (git de verdade, sem -C)");
  eq(r[1].incerto, false, "incerto do 2o segmento");
});
test("(q) git -C X status && y -> 1o segmento cwd X, 2o cwd inicial (nao persiste)", () => {
  const cmdGit = "g" + "it";
  const cmd = `${cmdGit} -C '${testA}' status && y`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[0].cwd, testA, "cwd do 1o segmento (git -C X)");
  eq(r[1].cwd, testDir, "cwd do 2o segmento NAO herda o -C do 1o");
});

// (p) e (q) so afirmavam o cwd do segmento SEGUINTE ao grep — a mutacao
// `comandoEhGit` -> `seg.includes("git")` (K2) so muda o cwd do PROPRIO
// segmento do grep (o -C do grep, ali, nao persiste para o segmento
// seguinte de qualquer jeito), e nada acima cobria isso: a catraca
// `conferir-mutacao` ficou verde (rodada 6, lote 3, 2026-09-03).
test('(p2) grep -C 3 "gitignore" . sozinho -> 1 segmento, cwd inicial (isola comandoEhGit)', () => {
  const cmd = `grep -rn -C 3 "gitignore" .`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 1, "numero de segmentos");
  eq(r[0].cwd, testDir, "cwd do unico segmento (grep nao e git; com a mutacao viraria <cwd>/3)");
  eq(r[0].incerto, false, "incerto do segmento");
});
test('(p3) grep -C 3 "gitignore" . && git add -A -> o 1o segmento (grep) TAMBEM cwd inicial', () => {
  const cmdGit = "g" + "it";
  const cmd = `grep -rn -C 3 "gitignore" . && ${cmdGit} add -A`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[0].cwd, testDir, "cwd do 1o segmento (grep; com a mutacao viraria <cwd>/3)");
  eq(r[0].incerto, false, "incerto do 1o segmento");
});

console.log();
console.log("== Caso (r): P5 (rodada 8, lote 3) — \\cd, command cd, builtin cd tambem movem o cwd ==");
test("(r) \\cd A && x -> 2o segmento com cwd A (barra escapa alias/funcao)", () => {
  const cmd = `\\cd '${testA}' && x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[1].cwd, testA, "cwd do 2o segmento (apos o \\cd)");
});
test("(r2) command cd A && x -> 2o segmento com cwd A", () => {
  const cmd = `command cd '${testA}' && x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[1].cwd, testA, "cwd do 2o segmento (apos o command cd)");
});
test("(r3) builtin cd A && x -> 2o segmento com cwd A", () => {
  const cmd = `builtin cd '${testA}' && x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[1].cwd, testA, "cwd do 2o segmento (apos o builtin cd)");
});

console.log();
console.log("== Caso (s): P1 (rodada 8, lote 3) — env -u nao pode parar comandoEhGit na propria flag ==");
test("(s) env -u FOO git -C A status && y -> 1o segmento cwd A, 2o cwd inicial (nao persiste)", () => {
  const cmdGit = "g" + "it";
  const cmd = `env -u FOO ${cmdGit} -C '${testA}' status && y`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[0].cwd, testA, "cwd do 1o segmento (git de verdade, atras de env -u FOO)");
  eq(r[1].cwd, testDir, "cwd do 2o segmento NAO herda o -C do 1o");
});

console.log();
console.log("== Caso (t): R1 (rodada 9, lote 3) — env -C/--chdir por tokens, qualquer ordem de flags ==");
test("(t) env -u FOO --chdir=A git status && y -> 1o segmento cwd A, 2o cwd inicial", () => {
  const cmdGit = "g" + "it";
  const cmd = `env -u FOO --chdir=${testA} ${cmdGit} status && y`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[0].cwd, testA, "cwd do 1o segmento (env --chdir apos -u FOO)");
  eq(r[1].cwd, testDir, "cwd do 2o segmento nao herda o --chdir do 1o");
});
test("(t2) env -i -C A x -> cwd A so no proprio segmento", () => {
  const cmd = `env -i -C '${testA}' x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r[0].cwd, testA, "cwd do segmento do env -i -C (flag sem valor antes)");
  eq(r[0].incerto, false, "incerto");
});

console.log();
console.log("== Caso (u): R3 (rodada 9, lote 3) — movedores do PowerShell (Set-Location/sl/Push-Location/Pop-Location) ==");
test("(u) Set-Location A; x -> 2o segmento com cwd A", () => {
  const cmd = `Set-Location '${testA}'; x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[1].cwd, testA, "cwd do 2o segmento (apos Set-Location)");
});
test("(u2) sl -Path A; x -> 2o segmento com cwd A", () => {
  const cmd = `sl -Path '${testA}'; x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[1].cwd, testA, "cwd do 2o segmento (apos sl -Path)");
});
test("(u3) Push-Location A; x -> 2o segmento com cwd A", () => {
  const cmd = `Push-Location '${testA}'; x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[1].cwd, testA, "cwd do 2o segmento (apos Push-Location)");
});
test("(u4) Pop-Location; x -> sem Push-Location correspondente nesta linha, incerto", () => {
  const cmd = `Pop-Location; x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[0].incerto, true, "Pop-Location sem Push-Location marca incerto");
  eq(r[1].incerto, true, "incerto propaga para o segmento seguinte");
});

console.log();
console.log("== Caso (v): S1 (8a revisao, rodada 10, lote 3) — sintaxe de dois-pontos e destino inexistente ==");
test("(v1) Set-Location -Path:A; x -> 2o segmento com cwd A (A existente na caixa)", () => {
  const cmd = `Set-Location -Path:${testA}; x`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[1].cwd, testA, "cwd do 2o segmento (apos Set-Location -Path: com dois-pontos)");
  eq(r[1].incerto, false, "incerto=false: A existe em disco");
});
test("(v2) Set-Location -Path:-x; y -> incerto (valor comeca com '-', nunca destino de verdade)", () => {
  const cmd = `Set-Location -Path:-x; y`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 2, "numero de segmentos");
  eq(r[0].incerto, true, "Set-Location -Path:-x marca incerto");
  eq(r[1].incerto, true, "incerto propaga para o segmento seguinte");
});
test("(v3) cd /caminho/que/nao/existe && y -> incerto (destino nao existe em disco)", () => {
  const alvo = path.join(testDir, "caminho-que-nao-existe");
  const cmd = `cd '${alvo}' && y`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r[0].incerto, true, "cd para destino inexistente marca incerto");
  eq(r[1].incerto, true, "incerto propaga para o segmento seguinte");
});
test("(v4) mkdir novo && cd novo && y -> incerto (destino criado no mesmo comando, nao existe AINDA)", () => {
  const cmd = `mkdir novo && cd novo && y`;
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 3, "numero de segmentos");
  eq(r[1].incerto, true, "cd novo marca incerto: 'novo' nao existe no momento da analise");
  eq(r[2].incerto, true, "incerto propaga para o segmento seguinte (y)");
});

console.log();
console.log("== T1 (rodada 11, lote 3, 2026-09-04): timeout -s/-k na tabela de flags ==");
{
  const { tokensComAspas, posicaoDeComando } = require(path.join(path.dirname(process.argv[2]), "tokens-comando.cjs"));
  test("(t1) timeout -s TERM 30 git commit -m x -> posicao de comando e 'git'", () => {
    const toks = tokensComAspas("timeout -s TERM 30 git commit -m x");
    const i = posicaoDeComando(toks);
    eq(toks[i].v, "git", "token na posicao de comando");
  });
  test("(t2) timeout --signal=TERM 30 git ... -> 'git' (forma colada com =)", () => {
    const toks = tokensComAspas("timeout --signal=TERM 30 git status");
    const i = posicaoDeComando(toks);
    eq(toks[i].v, "git", "token na posicao de comando");
  });
  test("(t3) timeout -k 5 30 git ... -> 'git' (--kill-after curto)", () => {
    const toks = tokensComAspas("timeout -k 5 30 git status");
    const i = posicaoDeComando(toks);
    eq(toks[i].v, "git", "token na posicao de comando");
  });
}

console.log();
console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou);
NODESCRIPT

# Roda o teste
node "$TESTE_JS" "$SRC/hooks/lib/cwd-efetivo.cjs" "$RAIZ"
