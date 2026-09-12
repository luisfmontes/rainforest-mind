#!/bin/bash
# Bateria contratual incremental do plugin Codex.
# Uso: bash scripts/testa-plugin-codex.sh

set -u

SRC="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

OUTPUT="$(node "$SRC/scripts/testa-plugin-codex.cjs" --contrato-manifesto)"
STATUS=$?
printf '%s\n' "$OUTPUT"

if [ "$STATUS" -ne 0 ]; then
  exit "$STATUS"
fi

for MARKER in \
  'ok manifesto Codex: metadados name/version/description/author iguais ao manifesto Claude' \
  'ok frontmatter Codex:' \
  'ok ancora corpo fechar:' \
  'ok ancora corpo modo-dev:' \
  'ok ancora corpo montar-corpus:' \
  'ok ancora corpo regua:'
do
  case "$OUTPUT" in
    *"$MARKER"*) ;;
    *)
      printf 'FALHA wrapper omitiu marcador: %s\n' "$MARKER"
      exit 1
      ;;
  esac
done
