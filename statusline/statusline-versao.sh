#!/usr/bin/env bash
# Atualiza, em segundo plano, o cache de versao estavel da CLI lido pela statusline.
#
# Busca a versao publicada no CDN, valida que e um numero semver, e grava num
# cache atomico. Se a rede falha, timeout ou a resposta nao e numero semver,
# exit 0 sem tocar no cache — um aviso que aparece uma hora depois ainda presta.
# Lock por mkdir atomico e limpeza de orfao acima de 5 min, mesmo molde do
# statusline-jornada.sh, porque cache lido durante render precisa sair atomico
# (redirecionamento trunca antes de saber se o dado presta).

set -u

CACHE="${TEMP:-$HOME/AppData/Local/Temp}/claude-statusline-versao.txt"
CACHE="${CACHE//\\//}"
LOCK="$CACHE.lock"

# Uma execucao por vez: mkdir e atomico. Lock com mais de 5 min e orfao.
if [ -d "$LOCK" ]; then
  if [ -z "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then
    exit 0
  fi
  rmdir "$LOCK" 2>/dev/null
fi
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

command -v curl >/dev/null 2>&1 || exit 0

URL="${RAINFOREST_VERSAO_URL:-https://downloads.claude.ai/claude-code-releases/stable}"
VALOR=$(curl -s --max-time 10 "$URL" 2>/dev/null | tr -d ' \t\n\r')
[ -n "$VALOR" ] || exit 0

# Valida que a resposta e numero semver: X.Y.Z.
if ! printf '%s' "$VALOR" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  exit 0
fi

# Grava atomicamente por arquivo temporario + mv: truncamento nao descarta
# cache valido se curl falha no meio.
TEMP_CACHE="$CACHE.$$.tmp"
printf '%s' "$VALOR" > "$TEMP_CACHE" || exit 0
mv "$TEMP_CACHE" "$CACHE" 2>/dev/null || exit 0

exit 0
