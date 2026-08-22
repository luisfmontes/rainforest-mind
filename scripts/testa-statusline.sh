#!/bin/bash
# Invocador das baterias da statusline — elas estao em Python e o CI so pega
# scripts sh, entao este arquivo chama as baterias de verdade.
#
# Sao duas, e cada uma prova um segmento diferente:
#   statusline/testa-statusline-prazo.py   — o segmento de prazo classifica
#                                            cada caso corretamente
#   statusline/testa-statusline-versao.py  — o segmento de versao acende quando
#                                            a sessao esta atras do estavel
#
# Este script existe para que o workflow de CI (que procura scripts/testa-*.sh e
# hooks/testa-*.sh) as encontre e as rode junto com o resto da bateria.
#
# As duas rodam SEMPRE, mesmo que a primeira falhe, e o codigo de saida junta as
# duas: invocador que so propaga o resultado da primeira e o defeito que esta
# versao existe para nao ter — a segunda bateria ficaria verde por nunca rodar.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v python &> /dev/null; then
  echo "FALHA: python nao esta instalado ou nao esta no PATH" >&2
  exit 1
fi

FALHAS=0

echo "== bateria de prazo =="
python "$SRC/statusline/testa-statusline-prazo.py" "$SRC/statusline/statusline.py" || FALHAS=$((FALHAS + 1))

echo
echo "== bateria de versao =="
python "$SRC/statusline/testa-statusline-versao.py" "$SRC/statusline/statusline.py" || FALHAS=$((FALHAS + 1))

echo
if [ "$FALHAS" -ne 0 ]; then
  echo "FALHA: $FALHAS de 2 baterias da statusline reprovaram" >&2
  exit 1
fi

echo "as 2 baterias da statusline passaram"
