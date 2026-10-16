#!/bin/bash
# Bateria do palavra-bash.cjs. Testa a leitura da primeira palavra de um
# segmento Bash (aspas, escape, $'...'), a expansao de chaves e a extracao de
# corpos de substituicao.
# Uso: bash hooks/testa-palavra-bash.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_POSIX="$(mktemp -d)"
trap 'rm -rf "$TMP_POSIX"' EXIT

TESTE_JS="$TMP_POSIX/teste.js"
cat > "$TESTE_JS" << 'NODESCRIPT'
const assert = require("assert");
const { normalizarComando, expandirChaves, corposDeSubstituicao } = require(process.argv[2]);

// Contrabarra montada aqui: heredoc de teste come ou troca a barra invertida.
const B = String.fromCharCode(92);

let ok = 0;
let falhou = 0;

function secao(titulo) {
  console.log("\n" + titulo);
}

function caso(nome, fn) {
  try {
    fn();
    ok++;
    console.log("  ok    " + nome);
  } catch (e) {
    falhou++;
    console.log("  FALHA " + nome + ": " + e.message);
  }
}

secao("normalizarComando: primeira palavra lida como o bash");
caso("'cd' /x vira cd /x", () => assert.strictEqual(normalizarComando("'cd' /x").seg, "cd /x"));
caso("c\\d /x vira cd /x", () => assert.strictEqual(normalizarComando("c" + B + "d /x").seg, "cd /x"));
caso("$'\\x63d' /x vira cd /x", () => assert.strictEqual(normalizarComando("$'" + B + "x63d' /x").seg, "cd /x"));
caso("{cd,/x} && y vira cd /x && y", () => assert.strictEqual(normalizarComando("{cd,/x} && y").seg, "cd /x && y"));
caso("{c,}d /x vira cd d /x", () => assert.strictEqual(normalizarComando("{c,}d /x").seg, "cd d /x"));
caso("cd /x sem aspa fica identico", () => {
  const entrada = "cd /x";
  const r = normalizarComando(entrada);
  assert.strictEqual(r.seg, entrada);
  assert.strictEqual(r.estouro, false);
});
caso("echo {1..3} fica identico (sequencia nao expande)", () => {
  const entrada = "echo {1..3}";
  assert.strictEqual(normalizarComando(entrada).seg, entrada);
});
caso("${a,b} fica identico (parametro nao expande)", () => {
  const entrada = "${a,b}";
  assert.strictEqual(normalizarComando(entrada).seg, entrada);
});
caso("13 grupos {a,b} colados (8192 palavras) estouram", () => {
  const r = normalizarComando("{a,b}".repeat(13) + " /x");
  assert.strictEqual(r.estouro, true);
});

secao("chave entre aspas ou escapada nao expande");
caso("'{cd,/x}' fica {cd,/x} (aspas simples)", () => assert.strictEqual(normalizarComando("'{cd,/x}'").seg, "{cd,/x}"));
caso(B + "{cd,/x} fica {cd,/x} (escapada)", () => assert.strictEqual(normalizarComando(B + "{cd,/x}").seg, "{cd,/x}"));

secao("expandirChaves");
caso("a{b,c}d vira abd, acd", () => assert.deepStrictEqual(expandirChaves("a{b,c}d", "u".repeat("a{b,c}d".length)), ["abd", "acd"]));
caso("{a,b}{c,d} vira ac, ad, bc, bd", () =>
  assert.deepStrictEqual(expandirChaves("{a,b}{c,d}", "u".repeat("{a,b}{c,d}".length)), ["ac", "ad", "bc", "bd"]));
caso("{a,{b,c}} vira a, b, c", () =>
  assert.deepStrictEqual(expandirChaves("{a,{b,c}}", "u".repeat("{a,{b,c}}".length)), ["a", "b", "c"]));

secao("corposDeSubstituicao");
caso('echo "$(cd /x; y)" devolve ["cd /x; y"]', () =>
  assert.deepStrictEqual(corposDeSubstituicao('echo "$(cd /x; y)"'), ["cd /x; y"]));
caso("echo `cd /x` devolve [\"cd /x\"]", () =>
  assert.deepStrictEqual(corposDeSubstituicao("echo `cd /x`"), ["cd /x"]));
caso("echo 'a`b`' devolve []", () =>
  assert.deepStrictEqual(corposDeSubstituicao("echo 'a`b`'"), []));
caso('echo "a $(cd /x) b" devolve ["cd /x"]', () =>
  assert.deepStrictEqual(corposDeSubstituicao('echo "a $(cd /x) b"'), ["cd /x"]));
caso("x=`cd /x` devolve [\"cd /x\"]", () =>
  assert.deepStrictEqual(corposDeSubstituicao("x=`cd /x`"), ["cd /x"]));
caso("${y:-$(cd /x)} devolve o corpo de dentro", () =>
  assert.ok(corposDeSubstituicao("echo ${y:-$(cd /x)}").includes("cd /x")));
// Crase dentro de $(...) e $(...) dentro de crase saem como corpo de um nivel
// so. O chamador recursa sobre o corpo (ver o cabecalho da lib): todos() junta
// os niveis, e o `cd /x` do centro tem que aparecer no fim.
const todos = (t) => { const c = corposDeSubstituicao(t); return c.concat(...c.map(todos)); };
caso("crase dentro de $(...) chega ao cd por recursao", () =>
  assert.ok(todos("echo $(echo `cd /x`)").includes("cd /x")));
caso("$(...) dentro de crase chega ao cd por recursao", () =>
  assert.ok(todos("echo `echo $(cd /x)`").includes("cd /x")));
caso("$((1+2)) nao quebra a leitura do resto: $(cd /x) depois ainda sai", () =>
  assert.ok(corposDeSubstituicao("echo $((1+2)) && echo $(cd /x)").includes("cd /x")));
caso("$((1+$(cd /x))) sai o cd de dentro da aritmetica", () =>
  assert.ok(todos("echo $((1+$(cd /x)))").includes("cd /x")));

secao("diferencas contra o bash real (#530, parte A)");
// Cada caso foi confirmado no bash real com script em arquivo (ver o relato).
caso('$"cd" /x vira cd /x (aspas de locale sao aspas duplas)', () =>
  assert.strictEqual(normalizarComando('$"cd" /x').seg, "cd /x"));
caso("$'cd\\x00zz' /x: o NUL corta a string, sobra cd /x", () =>
  assert.strictEqual(normalizarComando("$'cd" + B + "x00zz' /x").seg, "cd /x"));
caso("$'cd\\0zz' /x: NUL octal corta a string, sobra cd /x", () =>
  assert.strictEqual(normalizarComando("$'cd" + B + "0zz' /x").seg, "cd /x"));
caso("c\\<NL>d /x: contrabarra + quebra de linha some (continuacao)", () =>
  assert.strictEqual(normalizarComando("c" + B + "\nd /x").seg, "cd /x"));
caso('"c\\<NL>d" /x: continuacao dentro de aspas duplas tambem some', () =>
  assert.strictEqual(normalizarComando('"c' + B + '\nd" /x').seg, "cd /x"));
caso("$'...' com NUL no meio: o que vem depois do NUL nao entra na palavra", () =>
  assert.strictEqual(normalizarComando("$'a" + B + "x00b' /x").seg, "a /x"));

console.log("\nok: " + ok + "   falhou: " + falhou);
process.exit(falhou > 0 ? 1 : 0);
NODESCRIPT

LIB="$SRC/hooks/lib/palavra-bash.cjs"
LIB_NODE="$(cygpath -m "$LIB" 2>/dev/null || printf '%s' "$LIB")"
node "$TESTE_JS" "$LIB_NODE"
exit $?
