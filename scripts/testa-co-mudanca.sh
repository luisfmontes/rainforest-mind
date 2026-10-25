#!/bin/bash
# Bateria do co-mudanca. Monta um repo git temporario DENTRO da bateria
# (mktemp -d, apagado no fim) com o historico do "pronto quando" da tarefa 4:
# quatro commits com a.js e b.js, um com a.js e c.js, e tres commits grandes
# (25 arquivos cada) com a.js e d.js. Depois confere o que o script imprime e
# o exit de cada caso. Uso: bash scripts/testa-co-mudanca.sh
#
# Afirma sobre a saida e o exit do script, nunca sobre o texto do fonte: quem
# le o fonte e quem decide "passou" e o que o script imprime.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMC="$SRC/scripts/co-mudanca.cjs"
RAIZ="$(mktemp -d)"
trap 'rm -rf "$RAIZ"' EXIT

ok=0; falhou=0
passou() { ok=$((ok+1)); echo "  ok   $1"; }
falha()  { falhou=$((falhou+1)); echo "  FALHA $1"; }

# roda <dir> <args...>: executa o script em <dir>, grava RC, OUT e ERR
run() {
  local dir="$1"; shift
  (cd "$dir" && node "$CMC" "$@") >"$RAIZ/out" 2>"$RAIZ/err"
  RC=$?
  OUT=$(cat "$RAIZ/out")
  ERR=$(cat "$RAIZ/err")
}

# ---------------------------------------------------------------- cenario
R="$RAIZ/repo"
mkdir -p "$R"
cd "$R" || exit 1
git init -q

G() { git -c user.name=t -c user.email=t@t -c core.autocrlf=false "$@"; }
commit() { G add -A && G commit -q -m "$1"; }

for i in 1 2 3 4; do
  echo "$i" >> a.js
  echo "$i" >> b.js
  commit "a e b $i"
done

echo 1 >> a.js
echo 1 >> c.js
commit "a e c"

for i in 1 2 3; do
  echo "$i" >> a.js
  echo "$i" >> d.js
  for k in $(seq 1 23); do echo "$i" > "g${i}_$k.js"; done
  commit "commit grande $i"
done

# ---------------------------------------------------------------- casos
run "$R" a.js --min 3
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -qxF "b.js  4/5  0.80" \
   && ! echo "$OUT" | grep -q '^c\.js'; then
  passou "b.js listado com 4/5 e 0.80; c.js ausente (1 vez)"
else
  falha "b.js listado e c.js ausente: rc=$RC saida=[$OUT]"
fi

run "$R" a.js --min 3
if [ "$RC" -eq 0 ] && ! echo "$OUT" | grep -q '^d\.js'; then
  passou "commit com mais de 20 arquivos não conta par: d.js ausente"
else
  falha "commit com mais de 20 arquivos não conta par: rc=$RC saida=[$OUT]"
fi

run "$R" c.js --min 3
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -qxF "histórico insuficiente: c.js mudou 1 vez(es) em 6 meses (mínimo 3)"; then
  passou "histórico insuficiente sai 0 com a frase"
else
  falha "histórico insuficiente sai 0 com a frase: rc=$RC saida=[$OUT]"
fi

F="$RAIZ/fora"
mkdir -p "$F"
run "$F" a.js
if [ "$RC" -ne 0 ] && [ -n "$ERR" ]; then
  passou "fora de repo sai $RC com motivo no stderr"
else
  falha "fora de repo sai diferente de 0 com motivo: rc=$RC err=[$ERR]"
fi

run "$R"
RC_SEM=$RC
run "$R" a.js --foo
RC_OPC=$RC
if [ "$RC_SEM" -eq 2 ] && [ "$RC_OPC" -eq 2 ]; then
  passou "uso errado sai 2 (sem argumento e opção desconhecida)"
else
  falha "uso errado sai 2: sem-arg=$RC_SEM opcao-desconhecida=$RC_OPC"
fi

# ------------------------------------------- caminho com acento (quotePath)
# Sem core.quotePath=false o git devolve "Gest\303\243o de Contratos/..." entre
# aspas: o alvo nao casa e o script diz "historico insuficiente" com 4 mudancas.
R2="$RAIZ/repo-acento"
mkdir -p "$R2/Gestão de Contratos"
cd "$R2" || exit 1
git init -q
for i in 1 2 3 4; do
  echo "$i" >> "Gestão de Contratos/MT100.prw"
  echo "$i" >> "Gestão de Contratos/MT100b.prw"
  commit "mt100 $i"
done

run "$R2" "Gestão de Contratos/MT100.prw" --min 3
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -qxF "Gestão de Contratos/MT100b.prw  4/4  1.00" \
   && ! echo "$OUT" | grep -qF '\303' \
   && ! echo "$OUT" | grep -q 'histórico insuficiente'; then
  passou "caminho com acento: MT100b.prw listado legível, sem \\303 nem histórico insuficiente"
else
  falha "caminho com acento: rc=$RC saida=[$OUT]"
fi

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
