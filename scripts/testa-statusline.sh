#!/bin/bash
# Invocador da bateria de prazo da statusline — ela esta em Python e o CI so
# pega scripts sh, entao este arquivo chama a bateria de verdade.
#
# A bateria de verdade mora em statusline/testa-statusline-prazo.py e prova que
# o segmento de prazo da statusline classifica corretamente cada caso. Este script
# existe para que o workflow de CI (que procura scripts/testa-*.sh e hooks/testa-*.sh)
# a encontre e a rode junto com o resto da bateria do repositorio.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v python &> /dev/null; then
  echo "FALHA: python nao esta instalado ou nao esta no PATH" >&2
  exit 1
fi

python "$SRC/statusline/testa-statusline-prazo.py" "$SRC/statusline/statusline.py"
