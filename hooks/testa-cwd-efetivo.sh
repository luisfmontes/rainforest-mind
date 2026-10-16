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
const { resolverCwdEfetivo, cwdPorSegmento, toplevelConfinado, normalizarMsys } = require(process.argv[2]);
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
console.log("== rodada 19 (lote 3): extrairPrimeiroToken trata {}/() como fronteira ==");
{
  // Teste DIRETO em `desempacotarWrapperDeString` — sem passar por nenhum
  // segmentador (`segmentosComAspas`/`segmentosParaGate`) antes, que já
  // separam '&' de '{' sozinhos. Isso prova o mecanismo de
  // `extrairPrimeiroToken` por si só: os três gates (staging-total,
  // worktree, fechar-issue) hoje blindam esse caso ANTES de chegar aqui
  // (cada um separa '&{...}' em segmentos próprios antes de desempacotar),
  // então uma bateria que só passasse pelo gate inteiro não provaria que
  // ESTA função está corrigida — só que o resultado final está certo.
  const { desempacotarWrapperDeString } = require(path.join(path.dirname(process.argv[2]), "tokens-comando.cjs"));
  test("(w1) &{git checkout main} (colado, sem espaco) -> ilegivel (PowerShell)", () => {
    const r = desempacotarWrapperDeString("&{git checkout main}", { ferramenta: "PowerShell" });
    eq(r.ilegivel, true, "ilegivel deve ser true (call operator reconhecido apesar do '{' colado)");
  });
  test("(w2) &{ git checkout main } (espaco so por dentro) -> ilegivel (PowerShell)", () => {
    const r = desempacotarWrapperDeString("&{ git checkout main }", { ferramenta: "PowerShell" });
    eq(r.ilegivel, true, "ilegivel deve ser true");
  });
  test("(w3) & {git checkout main} (espaco antes do '{', regressao) -> ilegivel (PowerShell)", () => {
    const r = desempacotarWrapperDeString("& {git checkout main}", { ferramenta: "PowerShell" });
    eq(r.ilegivel, true, "ja funcionava antes do conserto — nao pode regredir");
  });
  test("(w4) contraprova: & sozinho em Bash NUNCA vira ilegivel por este motivo", () => {
    const r = desempacotarWrapperDeString("&{git checkout main}", { ferramenta: "Bash" });
    eq(r.ilegivel, false, "em Bash, '&' e separador de comando, nao call operator — super-bloquear aqui quebraria 'echo hi & git status'");
  });
}

console.log();
console.log("== Caso (r): nome de comando CITADO na posicao de comando conta (R20, rodada 20, lote 3) ==");
test('(r) "git" -C A add -A -> o -C do git citado move o cwd do segmento', () => {
  const cmd = '"git" -C ' + JSON.stringify(testA) + ' add -A';
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 1, "numero de segmentos");
  eq(r[0].cwd, testA, "cwd do segmento (git citado ainda e git)");
});
test('(r2) nome citado como ARGUMENTO nao move nada', () => {
  const cmd = 'grep -rn "git -C ' + testA + '" docs/';
  const r = cwdPorSegmento(cmd, testDir);
  eq(r.length, 1, "numero de segmentos");
  eq(r[0].cwd, testDir, "cwd do segmento (nada moveu)");
});

console.log();
console.log("== Caso (msys): normalizarMsys so converte /<letra>/... em win32 (D11) ==");
test("(msys-1) plataforma injetada 'linux': /c/proj/x volta INTACTO", () => {
  eq(normalizarMsys("/c/proj/x", "linux"), "/c/proj/x", "caminho fora do win32 nao muda");
});
test("(msys-2) plataforma injetada 'win32': /c/proj/x vira c:/proj/x", () => {
  eq(normalizarMsys("/c/proj/x", "win32"), "c:/proj/x", "caminho em win32 converte pra forma Windows");
});

console.log();
console.log("== #514 (P2): expansao de chaves em argumento nao e fronteira ==");
{
  const { segmentosComAspas } = require(process.argv[2]);
  const n = (c) => segmentosComAspas(c).length;
  test("(514a) echo a/{b,c}/d -> 1 segmento", () => eq(n("echo a/{b,c}/d"), 1, "argumento com chaves fica inteiro"));
  test("(514b) wc -l s/{a,b}/S.md; echo {1..3} -> 2 segmentos", () => eq(n("wc -l s/{a,b}/S.md; echo {1..3}"), 2, "so o ; separa"));
  test("(514c) {cd,x} em posicao de comando, no Bash, vira um segmento so (D1, #530)", () => eq(n("{cd,x}"), 1, "a chave expande, nao corta"));
  test("(514c) {cd,lib} && echo x, no Bash, move o cwd (a chave expandida e cd de verdade)", () => {
    const hooksDir = path.resolve(path.dirname(process.argv[2]), "..");
    const r = cwdPorSegmento("{cd,lib} && echo x", hooksDir);
    eq(path.resolve(r[r.length - 1].cwd), path.resolve(hooksDir, "lib"), "cwd final e hooks/lib");
  });
  test("(514c) {cd,x} em PowerShell continua cortando (bloco de script, nao expansao)", () => {
    eq(segmentosComAspas("{cd,x}", true).length > 1, true, "PowerShell nao expande chaves");
    const hooksDir = path.resolve(path.dirname(process.argv[2]), "..");
    const r = cwdPorSegmento("{cd,lib}; echo x", hooksDir, true);
    eq(path.resolve(r[r.length - 1].cwd), hooksDir, "PowerShell: {cd,lib} nao muda o cwd");
  });
  test("(514d) A=1 {cd,x} / then {cd,x} / then A=1 {cd,x} / ! {cd,x} viram um segmento so (D1, rodada 3)", () => {
    for (const c of ["A=1 {cd,x}", "then {cd,x}", "then A=1 {cd,x}", "! {cd,x}"]) eq(n(c), 1, c);
  });
  test("(514d) {cd,\"x\"} e {cd,'x'} com aspas dentro das chaves viram um segmento so (D1, rodada 3)", () => {
    eq(n('{cd,"x"} && echo y'), 2, 'aspa dupla: so o && separa');
    eq(n("{cd,'x'} && echo y"), 2, "aspa simples: so o && separa");
    eq(n('A=1 {cd,"x"}'), 1, "atribuicao antes, aspa dentro");
  });
  // #530 (D4) mudou esta asserção: `{cd,x}` em posição de comando é expansão
  // de chaves (`cd x`), não fronteira. Antes afirmava `n > 1` (cortava).
  test("(514c) {cd,x} em posicao de comando nao corta (#530, D4): e uma palavra so", () => eq(n("{cd,x}"), 1, "expansao de chaves inteira no segmento"));
  // #530 (D4) mudou esta asserção: as cinco formas viraram um segmento só. Antes
  // afirmavam `n > 1` (cortavam). O cwd delas fica na seção (#530) abaixo.
  test("(514d) A=1 {cd,x} / then {cd,x} / builtin {cd,x} nao cortam (#530, D4)", () => {
    for (const c of ["A=1 {cd,x}", "then {cd,x}", "then A=1 {cd,x}", "builtin {cd,x}", "env -i {cd,x}"]) eq(n(c), 1, c);
  });
  test("(514e) { cd x; } e &{git checkout main} continuam cortando", () => {
    eq(n("{ cd x; }") > 1, true, "grupo com espaco");
    eq(n("&{git checkout main}") > 1, true, "scriptblock do PowerShell");
  });
  test("(514f) chave sem , nem x..y, ou com $ dentro, continua cortando", () => {
    eq(n("echo {abc}") > 1, true, "sem virgula");
    eq(n("echo {a,$x}") > 1, true, "com $");
  });
}

console.log();
console.log("== (#530) rodada 3: git de caminho Windows sem aspas mantem o -C ==");
{
  // Achado 3 da revisao 2: `C:\Git\cmd\git.exe -C P status`, sem aspas. A normalizacao
  // apagava as barras, o git deixava de ser reconhecido e o `-C` se perdia (cwd = W).
  // A contrabarra vem de String.fromCharCode(92): sem ela o caso falha, e e isso que prova.
  const B = String.fromCharCode(92);
  const W = path.join(testDir, "wt-r3");
  const P = path.join(testDir, "p-r3");
  fs.mkdirSync(W, { recursive: true });
  fs.mkdirSync(P, { recursive: true });
  const Pf = P.split(B).join("/");
  const GIT_WIN = "C:" + B + "Git" + B + "cmd" + B + "git.exe";
  const primeiroCwd = (cmd) => cwdPorSegmento(cmd, W)[0].cwd;
  test("(r3a) caminho Windows sem aspas: git.exe -C P status -> cwd = P", () => {
    eq(primeiroCwd(GIT_WIN + " -C " + Pf + " status"), path.resolve(P), "cwd do segmento");
  });
  test("(r3b) caminho Windows sem aspas antes de '; codex exec x' -> cwd = P", () => {
    eq(primeiroCwd(GIT_WIN + " -C " + Pf + " status; codex exec x"), path.resolve(P), "cwd do primeiro segmento");
  });
  test("(r3c) contraprova: {git,-C,P,status} continua -> cwd = P", () => {
    eq(primeiroCwd("{git,-C," + Pf + ",status}"), path.resolve(P), "cwd do segmento");
  });
  test("(r3d) contraprova: 'git' -C P status continua -> cwd = P", () => {
    eq(primeiroCwd("'git' -C " + Pf + " status"), path.resolve(P), "cwd do segmento");
  });
}

console.log("== (#530) palavra de comando reconstruida: aspas, escape, ANSI-C e chaves ==");
{
  // W: worktree temporario (cwd inicial). P: outro diretorio existente.
  // P vai com barra normal: `{...}` nao aceita barra invertida dentro.
  const B = String.fromCharCode(92);
  const W = path.join(testDir, "wt-530");
  const P = path.join(testDir, "p-530");
  fs.mkdirSync(W, { recursive: true });
  fs.mkdirSync(P, { recursive: true });
  const Pf = P.split(B).join("/");
  // Segmento seguinte: o `echo x > f` que o gate pergunta. O cwd dele vem do
  // movedor que rodou antes na mesma linha.
  const seguinte = (cmd) => { const r = cwdPorSegmento(cmd + "; echo x > f", W); return r[r.length - 1]; };
  const cwdEhP = (cmd) => eq(seguinte(cmd).cwd, path.resolve(P), cmd + ": cwd do segmento seguinte");
  const cwdEhW = (cmd) => eq(seguinte(cmd).cwd, path.resolve(W), cmd + ": cwd do segmento seguinte");
  test("(530a) 'cd' P -> cwd do segmento seguinte = P", () => cwdEhP(`'cd' ${Pf}`));
  test("(530b) c\\d P -> cwd = P", () => cwdEhP(`c${B}d ${Pf}`));
  test("(530c) $'\\x63d' P -> cwd = P", () => cwdEhP(`$'${B}x63d' ${Pf}`));
  test("(530d) {cd,P} -> cwd = P", () => cwdEhP(`{cd,${Pf}}`));
  test("(530e) A=1 {cd,P} -> cwd = P", () => cwdEhP(`A=1 {cd,${Pf}}`));
  test('(530f) A="a b" {cd,P} -> cwd = P', () => cwdEhP(`A="a b" {cd,${Pf}}`));
  test("(530g) builtin {cd,P} -> cwd = P", () => cwdEhP(`builtin {cd,${Pf}}`));
  test("(530h) then {cd,P} -> incerto (then ja faz incerto na base)", () => {
    eq(seguinte(`then {cd,${Pf}}`).incerto, true, "then {cd,P} incerto");
  });
  test("(530i) {c,}d P -> continua W (o bash roda 'cd d P', que falha)", () => cwdEhW(`{c,}d ${Pf}`));
  // #530 (emenda, 2026-10-15): aspa BALANCEADA dentro da chave nao e mais fronteira.
  // O bash expande `{cd,"P"}` para `cd P`, entao o movedor e exato, nao incerto.
  // (Antes era incerto; a expectativa mudou junto com a regra, de proposito.)
  test('(530j) {cd,"P"} -> cwd = P, exato (aspa balanceada na chave nao e fronteira)', () => {
    cwdEhP(`{cd,"${Pf}"}`);
    eq(seguinte(`{cd,"${Pf}"}`).incerto, false, '{cd,"P"} exato');
  });
  test('(530j2) {"cd",P} -> cwd = P, exato (aspa na palavra de comando)', () => {
    cwdEhP(`{"cd",${Pf}}`);
    eq(seguinte(`{"cd",${Pf}}`).incerto, false, '{"cd",P} exato');
  });
  test('(530j3) {cd,"P x"} com espaco dentro da aspa continua fronteira (incerto)', () => {
    eq(seguinte(`{cd,"${Pf} x"}`).incerto, true, '{cd,"P x"} incerto');
  });
  test("(530k) 13 grupos {a,b} em posicao de comando -> estouro: true", () => {
    const r = cwdPorSegmento("{a,b}".repeat(13) + " /x", W);
    eq(r[0].estouro, true, "estouro do teto de 4096 palavras");
  });
  test("(530l) echo {a,b} (argumento, 2 palavras) nao estoura", () => {
    const r = cwdPorSegmento("echo {a,b}", W);
    eq(r[0].estouro, false, "estouro em argumento pequeno");
  });
  // #530 (emenda, 2026-10-15): redirecionamento antes ou depois do destino nao
  // muda o movedor. O cd roda no MESMO shell; so o destino do redirecionamento e
  // outro assunto (quem le e alvosBashEscrita, no segmento cru).
  test("(530m) cd P > /dev/null -> cwd = P", () => cwdEhP(`cd ${Pf} > /dev/null`));
  test("(530n) cd P 2>/dev/null -> cwd = P", () => cwdEhP(`cd ${Pf} 2>/dev/null`));
  test("(530o) >/dev/null cd P -> cwd = P", () => cwdEhP(`>/dev/null cd ${Pf}`));
  test("(530p) 2>&1 cd P -> cwd = P", () => cwdEhP(`2>&1 cd ${Pf}`));
  test("(530q) A=a\\ b cd P -> cwd = P", () => cwdEhP(`A=a${B} b cd ${Pf}`));
  // `cd hooks` muda para W/hooks (o cd roda, mesmo com o redirecionamento). Nao e W.
  test("(530r) cd hooks > /dev/null -> cwd = W/hooks", () => {
    eq(seguinte(`cd hooks > /dev/null`).cwd, path.resolve(W, "hooks"), "cd hooks > /dev/null -> W/hooks");
  });
  test("(530s) dir2>x nao e descritor: cd dir2>x muda para dir2", () => {
    const r = seguinte(`cd dir2>x`);
    eq(r.cwd, path.resolve(W, "dir2"), "cd dir2>x -> dir2");
  });
}

console.log();
console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou);
NODESCRIPT

# Roda o teste
node "$TESTE_JS" "$SRC/hooks/lib/cwd-efetivo.cjs" "$RAIZ"
