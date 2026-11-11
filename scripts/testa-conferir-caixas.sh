#!/usr/bin/env bash
# Bateria: o checador conferir-caixas acusa a caixa que copia um script sem a
# lib que ele exige, e so essa; a linha caixa-sem so vale com motivo.
# Design: docs/rainforest/design/caixa-confere-requires.md (D1 a D3, D5).
#
# Cada caso monta uma raiz temporaria (scripts/, hooks/lib/ e uma bateria de
# caixa escrita por printf), roda o checador com --raiz e le o exit e a saida.
# A bateria de caixa e so lida pelo checador, nunca executada.

set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }
win() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

# caso <nome>: raiz nova com scripts/ e hooks/lib/ (x.cjs e y.cjs existem)
CASO=""
caso() {
  CASO="$SBP/$1"
  mkdir -p "$CASO/scripts" "$CASO/hooks/lib"
  printf '%s\n' "module.exports = {};" > "$CASO/hooks/lib/x.cjs"
  printf '%s\n' "module.exports = {};" > "$CASO/hooks/lib/y.cjs"
}
# cjs <arquivo> <linha>...: escreve um .cjs na raiz do caso
cjs() {
  local arq="$1"; shift
  printf '%s\n' "$@" > "$CASO/$arq"
}
# bateria <linha>...: escreve hooks/testa-caso.sh, uma linha por argumento
bateria() {
  printf '%s\n' "SRC=/src" "SBP=/sbp" "$@" > "$CASO/hooks/testa-caso.sh"
}
# roda <caso>: roda o checador na raiz do caso; saida em $SBP/saida, exit em $E
roda() {
  node "$SRC/scripts/conferir-caixas.cjs" --raiz "$(win "$SBP/$1")" > "$SBP/saida" 2>&1
  E=$?
}
sai() {
  if [ "$E" = "$2" ]; then test_ok "$1: exit $2"
  else test_fail "$1: exit $E (esperado $2) -- $(head -4 "$SBP/saida" | tr '\n' ' ')"; fi
}
tem() {
  if grep -qF -- "$2" "$SBP/saida"; then test_ok "$1: saida tem '$2'"
  else test_fail "$1: saida sem '$2' -- $(head -4 "$SBP/saida" | tr '\n' ' ')"; fi
}

# (1) script copiado sem a lib que ele exige
caso c1
cjs scripts/a.cjs "const path = require('path');" "require(path.join(__dirname, '..', 'hooks', 'lib', 'x.cjs'));"
bateria 'cp "$SRC/scripts/a.cjs" "$SBP/scripts/"'
roda c1
sai "(1)" 1
tem "(1)" "falta hooks/lib/x.cjs (exigido por scripts/a.cjs)"

# (2) lib copiada pelo laco
caso c2
cjs scripts/a.cjs "const path = require('path');" "require(path.join(__dirname, '..', 'hooks', 'lib', 'x.cjs'));"
bateria 'cp "$SRC/scripts/a.cjs" "$SBP/scripts/"' 'for lib in x y; do cp "$SRC/hooks/lib/$lib.cjs" "$SBP/hooks/lib/"; done'
roda c2
sai "(2)" 0
tem "(2)" "0 achado(s)"

# (3) require tardio: dentro de funcao, so a.cjs copiado
caso c3
cjs scripts/a.cjs "function f() { return require('./b.cjs'); }"
cjs scripts/b.cjs "module.exports = {};"
bateria 'cp "$SRC/scripts/a.cjs" "$SBP/scripts/"'
roda c3
sai "(3)" 1
tem "(3)" "falta scripts/b.cjs (exigido por scripts/a.cjs)"

# (4) transitivo: a -> b -> lib, copiados a e b
caso c4
cjs scripts/a.cjs "function f() { return require('./b.cjs'); }"
cjs scripts/b.cjs "const path = require('path');" "module.exports = require(path.join(__dirname, '..', 'hooks', 'lib', 'x.cjs'));"
bateria 'cp "$SRC/scripts/a.cjs" "$SBP/scripts/"' 'cp "$SRC/scripts/b.cjs" "$SBP/scripts/"'
roda c4
sai "(4)" 1
tem "(4)" "falta hooks/lib/x.cjs (exigido por scripts/b.cjs)"

# (5) caixa-sem com motivo: a ausencia e declarada e nao vira achado
caso c5
cjs scripts/a.cjs "const path = require('path');" "require(path.join(__dirname, '..', 'hooks', 'lib', 'x.cjs'));"
bateria 'cp "$SRC/scripts/a.cjs" "$SBP/scripts/"' '# caixa-sem: hooks/lib/x.cjs — degrada para aviso'
roda c5
sai "(5)" 0
tem "(5)" "0 achado(s)"

# (6) caixa-sem sem motivo: nao vale, o achado continua
caso c6
cjs scripts/a.cjs "const path = require('path');" "require(path.join(__dirname, '..', 'hooks', 'lib', 'x.cjs'));"
bateria 'cp "$SRC/scripts/a.cjs" "$SBP/scripts/"' '# caixa-sem: hooks/lib/x.cjs'
roda c6
sai "(6)" 1
tem "(6)" "falta hooks/lib/x.cjs"

# (7) cp -r da pasta inteira: a bateria e pulada
caso c7
cjs scripts/a.cjs "const path = require('path');" "require(path.join(__dirname, '..', 'hooks', 'lib', 'x.cjs'));"
bateria 'cp -r "$SRC/scripts" "$SBP/"' 'cp "$SRC/scripts/a.cjs" "$SBP/scripts/"'
roda c7
sai "(7)" 0
tem "(7)" "pulada"

# (8) modulo do Node nao conta
caso c8
cjs scripts/a.cjs "const fs = require('fs');" "const path = require('path');"
bateria 'cp "$SRC/scripts/a.cjs" "$SBP/scripts/"'
roda c8
sai "(8)" 0
tem "(8)" "0 achado(s)"

# (9) cp -r de subpasta lib conta como copiada
caso c9
cjs scripts/a.cjs "const path = require('path');" "require(path.join(__dirname, '..', 'hooks', 'lib', 'x.cjs'));"
bateria 'cp "$SRC/scripts/a.cjs" "$SBP/scripts/"' 'cp -r "$SRC/hooks/lib" "$SBP/hooks/"'
roda c9
sai "(9)" 0
tem "(9)" "0 achado(s)"

echo "ok: $ok   falhou: $falhou"
if [ "$falhou" -gt 0 ]; then exit 1; fi
