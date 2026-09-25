#!/bin/bash
# Bateria contratual incremental do plugin Codex.
# Uso: bash scripts/testa-plugin-codex.sh

set -u

SRC="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
SCRIPT="$SRC/scripts/testa-plugin-codex.cjs"
NODE_BIN="node"
if ! command -v "$NODE_BIN" >/dev/null 2>&1; then
  WINDOWS_NODE='/mnt/c/Program Files/nodejs/node.exe'
  if [ ! -x "$WINDOWS_NODE" ] || ! command -v wslpath >/dev/null 2>&1; then
    printf 'FALHA node nao encontrado para a bateria Codex\n'
    exit 1
  fi
  NODE_BIN="$WINDOWS_NODE"
  SCRIPT="$(wslpath -w "$SCRIPT")"
fi

OUTPUT_MANIFESTO="$("$NODE_BIN" "$SCRIPT" --contrato-manifesto)"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
  printf '%s\n' "$OUTPUT_MANIFESTO"
  exit "$STATUS"
fi

OUTPUT_ADAPTADOR="$("$NODE_BIN" "$SCRIPT" --contrato-adaptador-hook)"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
  printf '%s\n' "$OUTPUT_ADAPTADOR"
  exit "$STATUS"
fi

OUTPUT_MARKETPLACE="$("$NODE_BIN" "$SCRIPT" --contrato-marketplace)"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
  printf '%s\n' "$OUTPUT_MARKETPLACE"
  exit "$STATUS"
fi

OUTPUT_GEMINI="$("$NODE_BIN" "$SCRIPT" --contrato-gemini)"
STATUS=$?
OUTPUT="${OUTPUT_MANIFESTO}
${OUTPUT_ADAPTADOR}
${OUTPUT_MARKETPLACE}
${OUTPUT_GEMINI}"
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
  'ok ancora corpo regua:' \
  'ok hook seletivo Codex: PreToolUse/Bash, 1 adaptador' \
  'ok adaptador fino: stdin encaminhado ao core sem politica duplicada' \
  'ok adaptador Codex: allow exit 0 e stdout vazio' \
  'ok adaptador Codex: deny oficial preserva motivo do core' \
  'ok adaptador Codex: falha inesperada vira deny seguro' \
  'ok adaptador Codex: falha de spawn vira deny seguro' \
  'ok adaptador Codex: JSON malformado vira deny seguro sem ecoar payload' \
  'ok mutacao handler Codex -> core direto: vermelho e bytes restaurados' \
  'ok marketplace rainforest-mind: source.path ./ resolve a raiz com manifestos Claude e Codex' \
  'ok Gemini adiado: caminhos rastreados nao contem manifesto, hook, adaptador ou fixture de payload Gemini fora dos documentos do fluxo'
do
  case "$OUTPUT" in
    *"$MARKER"*) ;;
    *)
      printf 'FALHA wrapper omitiu marcador: %s\n' "$MARKER"
      exit 1
      ;;
  esac
done
