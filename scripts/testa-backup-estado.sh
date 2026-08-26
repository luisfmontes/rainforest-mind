#!/bin/bash
# Bateria do vigias/backup-estado.ps1 — o backup do sentinela.
#
# Ela EXECUTA o arquivo real, nao o le. A primeira tentativa desta bateria
# (2026-08-26, Issue #118) fabricava uma copia do bloco numa caixa e rodava a
# copia: com `git push origin main` reintroduzido no arquivo de verdade ela saia
# `9 ok, 0 falha(s)`. Bateria que nao executa o artefato certifica um arquivo que
# nunca leu.
#
# O que ela cobre, e por que cada um:
#   1. Nenhum commit nasce, em raiz nenhuma — e as caixas TEM commit antes, senao
#      `git log` falha nas duas pontas e a comparacao passa por vazio. Foi assim
#      que a primeira versao ficou verde: `fatal: your current branch 'master'
#      does not have any commits yet` dos dois lados.
#   2. Nenhum push e tentado — a remota e uma pasta local, e o bare e conferido.
#   3. Falha de backup FALA: uma linha no ERROS.md, no formato do run-vigia.ps1.
#   4. `-Teste` nao escreve backup nenhum.
#   5. O caminho feliz cria a copia de verdade.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1: '$2' != '$3'"; fi; }
verdade() { if [ "$2" = "sim" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1"; fi; }

command -v powershell >/dev/null 2>&1 || { echo "FALHA powershell nao esta no PATH — esta bateria nao significaria nada"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FALHA node nao esta no PATH"; exit 1; }

win() { cygpath -w "$1"; }

# --- caixa: um "plugin" e uma "raiz de dados", cada um repo git COM commit,
#     cada um com uma remota que e outra pasta local (nunca a internet).
montar() {
  rm -rf "$SB/plugin" "$SB/dados" "$SB/plugin-bare" "$SB/dados-bare"
  for par in "plugin" "dados"; do
    git init --bare -q -b main "$SB/$par-bare"
    git init -q -b main "$SB/$par"
    ( cd "$SB/$par" && git config user.email t@t && git config user.name t &&
      mkdir -p vigias && echo base > vigias/ERROS.md && git add vigias/ERROS.md &&
      git commit -qm base && git remote add origin "$SB/$par-bare" && git push -q -u origin main )
  done
  # A caixa precisa das dependencias do foco.cjs, nao so dele. Copiar o script
  # solto foi o defeito que a #110 ja tinha ensinado: o modulo some, o erro vira
  # `Cannot find module`, e a bateria mede a caixa em vez do artefato.
  mkdir -p "$SB/plugin/scripts" "$SB/plugin/vigias" "$SB/plugin/hooks/lib"
  cp "$SRC/scripts/foco.cjs" "$SB/plugin/scripts/foco.cjs"
  cp "$SRC/hooks/lib/raiz.cjs" "$SB/plugin/hooks/lib/raiz.cjs"
  cp "$SRC/hooks/lib/contexto-sessao.cjs" "$SB/plugin/hooks/lib/contexto-sessao.cjs"
  cp "$SRC/vigias/backup-estado.ps1" "$SB/plugin/vigias/backup-estado.ps1"
  printf 'foco de caixa\n' > "$SB/dados/FOCO.md"
}

contar() { ( cd "$1" && git log --oneline 2>/dev/null | wc -l ); }

rodar() {  # rodar <raiz-de-dados> [-Teste]
  powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
    -Vigia sentinela-foco -Root "$(win "$1")" -Plugin "$(win "$SB/plugin")" \
    -Log "$(win "$SB/plugin/vigias/log.txt")" ${2:-} > /dev/null 2>&1
  echo $?
}

echo "== 0. a caixa tem commit — senao a comparacao passa por vazio =="
montar
igual "plugin-local nasce com 1 commit" "$(contar "$SB/plugin")" "1"
igual "dados-local nasce com 1 commit"  "$(contar "$SB/dados")"  "1"
igual "plugin-bare recebeu o push"      "$(contar "$SB/plugin-bare")" "1"
igual "dados-bare recebeu o push"       "$(contar "$SB/dados-bare")"  "1"

echo
echo "== 1. o sentinela nao commita nem empurra em raiz nenhuma =="
montar
A_P=$(contar "$SB/plugin"); A_D=$(contar "$SB/dados")
A_PB=$(contar "$SB/plugin-bare"); A_DB=$(contar "$SB/dados-bare")
rodar "$SB/dados" > /dev/null
D_P=$(contar "$SB/plugin"); D_D=$(contar "$SB/dados")
D_PB=$(contar "$SB/plugin-bare"); D_DB=$(contar "$SB/dados-bare")
if [ "$A_P" = "$D_P" ] && [ "$A_D" = "$D_D" ] && [ "$A_PB" = "$D_PB" ] && [ "$A_DB" = "$D_DB" ]; then
  ok=$((ok+1)); echo "  ok    o sentinela nao commita nem empurra em raiz nenhuma"
else
  falhou=$((falhou+1))
  echo "  FALHA o sentinela nao commita nem empurra em raiz nenhuma"
  echo "        plugin $A_P->$D_P  dados $A_D->$D_D  plugin-bare $A_PB->$D_PB  dados-bare $A_DB->$D_DB"
fi

echo
echo "== 2. o caminho feliz faz o backup de verdade =="
montar
rodar "$SB/dados" > /dev/null
n=$(ls "$SB/dados/.foco-backups" 2>/dev/null | wc -l)
igual "criou exatamente uma copia" "$n" "1"
copia=$(ls "$SB/dados/.foco-backups"/*.md 2>/dev/null | head -1)
if [ -n "$copia" ] && cmp -s "$SB/dados/FOCO.md" "$copia"; then
  ok=$((ok+1)); echo "  ok    a copia e byte a byte igual ao FOCO.md"
else
  falhou=$((falhou+1)); echo "  FALHA a copia nao confere com o FOCO.md"
fi

echo
echo "== 3. -Teste nao escreve backup nenhum =="
montar
rodar "$SB/dados" "-Teste" > /dev/null
if [ -d "$SB/dados/.foco-backups" ]; then
  falhou=$((falhou+1)); echo "  FALHA -Teste criou backup"
else
  ok=$((ok+1)); echo "  ok    -Teste nao criou backup"
fi
grep -q 'modo teste' "$SB/plugin/vigias/log.txt" 2>/dev/null && r=sim || r=nao
verdade "-Teste registrou 'modo teste' no log" "$r"

echo
echo "== 4. falha de backup FALA no ERROS.md =="
montar
codigo=$(rodar "$SB/nao-existe")
igual "sai diferente de zero quando a raiz nao existe" "$codigo" "1"
conteudo=$(cat "$SB/plugin/vigias/ERROS.md")
echo "  -- ERROS.md depois da falha:"
printf '%s\n' "$conteudo" | sed 's/^/     /'
printf '%s' "$conteudo" | grep -qE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \[sentinela-foco\]: ' && r=sim || r=nao
verdade "a linha esta no formato do run-vigia.ps1" "$r"
printf '%s' "$conteudo" | grep -q 'FOCO.md' && r=sim || r=nao
verdade "a linha diz o que falhou" "$r"

echo
echo "== 5. nenhum git no backup-estado.ps1, fora de comentario =="
if grep -vE '^\s*#' "$SRC/vigias/backup-estado.ps1" | grep -qE '\bgit\b'; then
  falhou=$((falhou+1)); echo "  FALHA achei git em linha de execucao"
else
  ok=$((ok+1)); echo "  ok    nenhum git em linha de execucao"
fi

echo
echo "== 6. o run-vigia.ps1 nao volta a commitar nem empurrar =="
# A trava. Ela olha LINHA DE EXECUCAO, nao o arquivo inteiro: o comentario que
# explica por que o bloco saiu cita `git add`, `git commit` e `git push` de
# proposito, e apagar esse comentario para a trava passar seria apagar a razao.
exec_do_vigia="$(grep -vE '^\s*#' "$SRC/vigias/run-vigia.ps1")"
for proibido in 'git .*add' 'git .*commit' 'git .*push'; do
  if printf '%s' "$exec_do_vigia" | grep -qE "$proibido"; then
    falhou=$((falhou+1)); echo "  FALHA achei '$proibido' em linha de execucao do run-vigia.ps1"
  else
    ok=$((ok+1)); echo "  ok    nenhum '$proibido' em linha de execucao do run-vigia.ps1"
  fi
done
# E o contrario: a mesma string em COMENTARIO nao pode acender a trava.
if printf '%s' "$(grep -E '^\s*#' "$SRC/vigias/run-vigia.ps1")" | grep -qE 'git .*push'; then
  ok=$((ok+1)); echo "  ok    o comentario cita 'git push' e a trava nao acende por isso"
else
  falhou=$((falhou+1)); echo "  FALHA o comentario deveria citar 'git push' — sem isso a trava nao esta provada nos dois sentidos"
fi

echo
echo "== 7. o _comum.md nao pode divergir do codigo =="
# Nao e teste de prosa: e o UNICO numero do backup que aparece em dois lugares.
# O teto vive no backup-estado.ps1 e e prometido no _comum.md; se um mudar e o
# outro nao, o vigia le uma promessa que o codigo nao cumpre.
teto_codigo="$(grep -oE '^\$TETO_COPIAS = [0-9]+' "$SRC/vigias/backup-estado.ps1" | grep -oE '[0-9]+')"
if [ -z "$teto_codigo" ]; then
  falhou=$((falhou+1)); echo "  FALHA nao achei \$TETO_COPIAS no backup-estado.ps1"
else
  ok=$((ok+1)); echo "  ok    o codigo declara o teto ($teto_codigo)"
  if grep -qE "\*\*${teto_codigo}\*\*" "$SRC/vigias/_comum.md"; then
    ok=$((ok+1)); echo "  ok    o _comum.md promete o mesmo teto ($teto_codigo)"
  else
    falhou=$((falhou+1)); echo "  FALHA o _comum.md nao promete o teto $teto_codigo que o codigo usa"
  fi
fi
if grep -q 'commita nem empurra' "$SRC/vigias/_comum.md"; then
  ok=$((ok+1)); echo "  ok    o _comum.md diz que o sentinela nao commita nem empurra"
else
  falhou=$((falhou+1)); echo "  FALHA o _comum.md nao diz que o sentinela nao commita nem empurra"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
