#!/bin/bash
# Bateria do baterias-do-diff. Monta um repo git temporario DENTRO da bateria
# (mktemp -d, apagado no fim), com baterias e bibliotecas de verdade, faz um
# commit de base e um commit por caso, e confere o que o script devolve: a lista
# de baterias, as duvidas e o exit. Uso: bash scripts/testa-baterias-do-diff.sh
#
# Afirma sobre a saida e o exit do script, nunca sobre o texto do fonte: quem
# le o fonte e quem decide "passou" e o que o script imprime.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BDD="$SRC/scripts/baterias-do-diff.cjs"
RAIZ="$(mktemp -d)"
trap 'rm -rf "$RAIZ"' EXIT

ok=0; falhou=0
passou() { ok=$((ok+1)); echo "  ok   $1"; }
falha()  { falhou=$((falhou+1)); echo "  FALHA $1"; }

# ---------------------------------------------------------------- cenario
R="$RAIZ/repo"
mkdir -p "$R/scripts" "$R/hooks/lib"
cd "$R" || exit 1
git init -q
git config user.email t@t; git config user.name t
git config commit.gpgsign false
git config core.autocrlf false
printf 'cita a.cjs e x.cjs\n' > scripts/testa-a.sh
printf 'cita x.cjs\n'         > scripts/testa-d.sh
printf 'cita c.cjs\n'         > hooks/testa-c.sh
echo a > scripts/a.cjs; echo x > scripts/x.cjs; echo b > scripts/b.cjs
echo c > hooks/lib/c.cjs; echo r > README.md
printf 'cita velha.cjs\n'     > scripts/testa-velha.sh
printf 'cita Gestão.cjs\n'    > scripts/testa-gestao.sh
printf 'cita SKILL.md\n'      > scripts/testa-teto.sh
git add -A && git commit -qm base
BASE=$(git rev-parse HEAD)

# Volta ao BASE e acrescenta uma linha em cada arquivo dado: um commit por caso.
novo_caso() {
  cd "$R" || exit 1
  git reset -q --hard "$BASE" && git clean -qfd
  local f
  for f in "$@"; do mkdir -p "$(dirname "$f")"; echo mudanca >> "$f"; done
  git add -A && git commit -qm caso
}

# Roda o script contra o BASE; stdout em OUT, exit em RC, stderr descartado.
rodar() {
  OUT=$(node "$BDD" --base "$BASE" --raiz "$R" "$@" 2>/dev/null); RC=$?
}

# ---------------------------------------------------------------- casos
echo "== baterias-do-diff: escolha pelo diff, duvidas e exit =="

novo_caso scripts/a.cjs
rodar
if [ "$RC" = 0 ] && [ "$OUT" = "scripts/testa-a.sh" ]; then
  passou "alterar so a.cjs lista a bateria que o cita, exit 0"
else falha "alterar so a.cjs: exit=$RC saida=[$OUT]"; fi

novo_caso scripts/a.cjs scripts/x.cjs
rodar
if [ "$RC" = 0 ] && [ "$OUT" = "$(printf 'scripts/testa-a.sh\nscripts/testa-d.sh')" ]; then
  passou "a.cjs e x.cjs: uma linha por bateria, sem repetir e ordenadas"
else falha "a.cjs e x.cjs: exit=$RC saida=[$OUT]"; fi

novo_caso scripts/b.cjs
rodar
if [ "$RC" = 3 ] && grep -qxF "rodar tudo: scripts/b.cjs — nenhuma bateria cita" <<< "$OUT"; then
  passou "arquivo que nenhuma bateria cita sai rodar tudo com exit 3"
else falha "arquivo que nenhuma bateria cita sai rodar tudo com exit 3: exit=$RC saida=[$OUT]"; fi

novo_caso hooks/lib/c.cjs
rodar
if [ "$RC" = 3 ] && grep -qxF "hooks/testa-c.sh" <<< "$OUT" \
   && grep -qxF "rodar tudo: hooks/lib/c.cjs — biblioteca compartilhada" <<< "$OUT"; then
  passou "biblioteca compartilhada sai 3 com motivo, e a bateria que a cita entra"
else falha "biblioteca compartilhada: exit=$RC saida=[$OUT]"; fi

novo_caso scripts/testa-a.sh
rodar
if [ "$RC" = 0 ] && [ "$OUT" = "scripts/testa-a.sh" ]; then
  passou "bateria alterada entra na lista, a propria, exit 0"
else falha "bateria alterada: exit=$RC saida=[$OUT]"; fi

novo_caso README.md
rodar
if [ "$RC" = 0 ] && [ -z "$OUT" ]; then
  passou ".md sem bateria que o cite nao gera bateria nem duvida"
else falha ".md sem bateria que o cite: exit=$RC saida=[$OUT]"; fi

novo_caso skills/x/SKILL.md
rodar
if [ "$RC" = 0 ] && [ "$OUT" = "scripts/testa-teto.sh" ]; then
  passou ".md citado por bateria lista a bateria, exit 0"
else falha ".md citado por bateria: exit=$RC saida=[$OUT]"; fi

novo_caso docs/a.json
rodar
if [ "$RC" = 0 ] && [ -z "$OUT" ]; then
  passou "arquivo sob docs/ sem citacao nao gera rodar tudo"
else falha "arquivo sob docs/ sem citacao: exit=$RC saida=[$OUT]"; fi

# Bateria apagada entre base e head nao entra na lista (o arquivo nao existe mais).
cd "$R" || exit 1
git reset -q --hard "$BASE" && git clean -qfd
git rm -q scripts/testa-velha.sh && git commit -qm caso
rodar
if [ "$RC" = 0 ] && [ -z "$OUT" ]; then
  passou "bateria apagada entre base e head nao e listada"
else falha "bateria apagada: exit=$RC saida=[$OUT]"; fi

novo_caso "scripts/Gestão.cjs"
rodar
if [ "$RC" = 0 ] && [ "$OUT" = "scripts/testa-gestao.sh" ]; then
  passou "arquivo com acento citado por bateria lista a bateria, sem escape"
else falha "arquivo com acento citado: exit=$RC saida=[$OUT]"; fi

novo_caso scripts/a.cjs
echo mudanca >> scripts/b.cjs; git add -A && git commit -qm depois
OUT=$(node "$BDD" --base "$BASE" --head HEAD~1 --raiz "$R" 2>/dev/null); RC=$?
if [ "$RC" = 0 ] && [ "$OUT" = "scripts/testa-a.sh" ]; then
  passou "--head limita o diff ao ref dado (sem o commit de b.cjs)"
else falha "--head HEAD~1: exit=$RC saida=[$OUT]"; fi

novo_caso scripts/a.cjs
OUT=$(node "$BDD" --raiz "$R" 2>/dev/null); RC=$?
if [ "$RC" = 2 ] && [ -z "$OUT" ]; then passou "sem --base sai 2"
else falha "sem --base: exit=$RC saida=[$OUT]"; fi

OUT=$(node "$BDD" --base "$BASE" --raiz "$R" --cores 2>/dev/null); RC=$?
if [ "$RC" = 2 ]; then passou "argumento desconhecido sai 2"
else falha "argumento desconhecido: exit=$RC"; fi

OUT=$(node "$BDD" --base "$BASE" --raiz "$R" --head 2>/dev/null); RC=$?
if [ "$RC" = 2 ]; then passou "--head sem valor sai 2"
else falha "--head sem valor: exit=$RC"; fi

OUT=$(node "$BDD" --base ref-que-nao-existe --raiz "$R" 2>/dev/null); RC=$?
if [ "$RC" = 1 ] && [ -z "$OUT" ]; then passou "ref que nao existe sai 1, sem lista"
else falha "ref inexistente: exit=$RC saida=[$OUT]"; fi

# A leitura de citacao e uma so: o script e o conferir-entrega chamam a mesma
# funcao de scripts/lib/baterias-vizinhas.cjs. Aqui se prova a funcao pelo que
# devolve sobre o repo de verdade.
novo_caso scripts/a.cjs
OUT=$(node -e "const { bateriasQueCitam } = require(process.argv[1]); console.log(bateriasQueCitam(process.argv[2], 'scripts/a.cjs').join(','))" "$SRC/scripts/lib/baterias-vizinhas.cjs" "$R" 2>/dev/null); RC=$?
if [ "$RC" = 0 ] && [ "$OUT" = "scripts/testa-a.sh" ]; then
  passou "bateriasQueCitam devolve so as baterias que citam o nome-base"
else falha "bateriasQueCitam: exit=$RC saida=[$OUT]"; fi

echo "ok: $ok   falhou: $falhou"
if [ "$falhou" -gt 0 ]; then exit 1; fi
exit 0
