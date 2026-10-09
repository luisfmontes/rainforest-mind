#!/bin/bash
# Bateria do indice nas references longas (scripts/conferir-indice-referencias.cjs)
# e do corte do indice na abertura do mod (tirarIndice, hooks/lib/contexto-sessao.cjs).
# Uso: bash scripts/testa-indice-referencias.sh
#
# Protege contra: reference > 100 linhas sem indice no topo; indice que aponta
#   para secao que nao existe ou fora de ordem; indice injetado na abertura,
#   gastando o teto das regras inteiras.
# Nao protege contra: indice que esquece uma secao (o corpo pode ter mais
#   secoes que o indice lista).

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$RAIZ/scripts/conferir-indice-referencias.cjs"
ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then echo "  ok    $1"; ok=$((ok+1)); else echo "  FALHA $1: obtido '$2', esperado '$3'"; falhou=$((falhou+1)); fi; }

echo "1. as references do repo passam"
node "$CONF" "$RAIZ/skills" > /dev/null; igual "repo real sai 0" "$?" "0"

SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/skills/x/references"
REF="$SB/skills/x/references/longa.md"
monta() { # $1 = bloco de indice (pode ser vazio)
  { echo "# Longa"; echo; printf '%s' "$1"; echo "**Primeira secao.** texto"; for i in $(seq 1 60); do echo "linha $i"; done
    echo "## Segunda secao"; for i in $(seq 1 60); do echo "linha $i"; done; echo "**Terceira** com \`crase\`"; } > "$REF"; }
BOM=$'<!-- indice -->\n- Primeira secao.\n- Segunda secao\n- Terceira com crase\n<!-- /indice -->\n'

echo; echo "2. caixa de areia"
monta "$BOM"; node "$CONF" "$SB/skills" > /dev/null; igual "indice certo sai 0" "$?" "0"
monta ""; node "$CONF" "$SB/skills" > /dev/null; igual "sem indice sai 1" "$?" "1"
monta "${BOM/Segunda secao/Secao que nao existe}"; node "$CONF" "$SB/skills" > /dev/null; igual "item sem secao sai 1" "$?" "1"
monta $'<!-- indice -->\n- Segunda secao\n- Primeira secao.\n- Terceira com crase\n<!-- /indice -->\n'
node "$CONF" "$SB/skills" > /dev/null; igual "fora de ordem sai 1" "$?" "1"
monta $'<!-- indice -->\n- Primeira secao.\n<!-- /indice -->\n'; node "$CONF" "$SB/skills" > /dev/null; igual "1 item so sai 1" "$?" "1"
printf '# Curta\nsem indice\n' > "$REF"; node "$CONF" "$SB/skills" > /dev/null; igual "curta sem indice sai 0" "$?" "0"

echo; echo "3. a abertura do mod tira o indice da regra injetada inteira"
SAIDA="$(cd "$RAIZ" && node -e '
const c = require("./hooks/lib/contexto-sessao.cjs");
const skill = require("fs").readFileSync("skills/rainforest-mind/SKILL.md", "utf8");
const t = c.montarContexto({ skillText: skill, focoText: "# Foco\n", destino: "mod", tetosMod: {},
  elaboracoes: [{ n: 99, texto: "# Regra 99\n\n<!-- indice -->\n- Corpo\n<!-- /indice -->\n\n**Corpo** da regra 99.\n" }] });
console.log([t.includes("<!-- indice -->") ? "com-indice" : "sem-indice", t.includes("**Corpo** da regra 99.") ? "com-corpo" : "sem-corpo"].join(" "));
')"
igual "indice fora, corpo dentro" "$SAIDA" "sem-indice com-corpo"

echo
echo "Resultado: $ok OK, $falhou FALHA"
[ "$falhou" -eq 0 ]
