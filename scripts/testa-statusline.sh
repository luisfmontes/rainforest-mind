#!/bin/bash
# Invocador das baterias da statusline — elas estao em Python e o CI so pega
# scripts sh, entao este arquivo chama as baterias de verdade. Cada uma prova um
# segmento diferente (prazo, versao, sessao co-locada, ...).
#
# Este script existe para que o workflow de CI (que procura scripts/testa-*.sh e
# hooks/testa-*.sh) as encontre e as rode junto com o resto da bateria.
#
# TODAS rodam SEMPRE, mesmo que uma falhe, e o codigo de saida junta todas:
# invocador que so propaga o resultado da primeira e o defeito que esta versao
# existe para nao ter — a segunda bateria ficaria verde por nunca rodar.
#
# A LISTA E ENUMERADA, NAO CHUMBADA, e isso mudou em 2026-08-23 pelo mesmo motivo
# que o paragrafo acima descreve, um nivel acima: a bateria do segmento co-locado
# foi escrita, commitada, e o arnes continuou chamando os dois arquivos que ele
# citava por nome. As 44 baterias do repo ficaram verdes com a bateria nova NUNCA
# TENDO RODADO — verde por ausencia, que e o pior tipo de verde. Bateria que
# precisa ser inscrita a mao acaba nao sendo.
#
# O PISO existe pelo motivo oposto: glob que nao casa com ninguem roda zero
# bateria e sai 0. E a mesma guarda que o `.github/workflows/baterias.yml` tem,
# e pelo mesmo motivo.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v python &> /dev/null; then
  echo "FALHA: python nao esta instalado ou nao esta no PATH" >&2
  exit 1
fi

PISO=3
BATERIAS=$(ls "$SRC"/statusline/testa-statusline-*.py 2>/dev/null)
TOTAL=$(printf '%s\n' "$BATERIAS" | grep -c . || true)

if [ "$TOTAL" -lt "$PISO" ]; then
  echo "FALHA: achei $TOTAL bateria(s) da statusline — esperava pelo menos $PISO." >&2
  echo "       Glob quebrado ou arvore incompleta: uma bateria que nao e achada" >&2
  echo "       nao reprova nada, ela some." >&2
  exit 1
fi

FALHAS=0
for f in $BATERIAS; do
  nome=$(basename "$f" .py | sed 's/^testa-statusline-//')
  echo
  echo "== bateria de $nome =="
  python "$f" "$SRC/statusline/statusline.py" || FALHAS=$((FALHAS + 1))
done

echo
if [ "$FALHAS" -ne 0 ]; then
  echo "FALHA: $FALHAS de $TOTAL baterias da statusline reprovaram" >&2
  exit 1
fi

echo "as $TOTAL baterias da statusline passaram"
