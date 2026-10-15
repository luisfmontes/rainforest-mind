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

console.log("\nok: " + ok + "   falhou: " + falhou);
process.exit(falhou > 0 ? 1 : 0);
NODESCRIPT

LIB="$SRC/hooks/lib/palavra-bash.cjs"
LIB_NODE="$(cygpath -m "$LIB" 2>/dev/null || printf '%s' "$LIB")"
node "$TESTE_JS" "$LIB_NODE"
exit $?
