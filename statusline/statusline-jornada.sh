#!/usr/bin/env bash
# Atualiza, em segundo plano, o cache de jornada lido pela statusline.
#
# A jornada efetiva NAO e calculada aqui: quem mede e o scripts/jornada.cjs do
# rainforest-mind (regra 8 — jornada nunca se infere de commit, log ou mtime).
# Este script so acha a versao mais nova do script, roda, extrai o numero e
# grava no cache. Custa ~3 s, por isso roda destacado da barra.

set -u

CACHE="${TEMP:-$HOME/AppData/Local/Temp}/claude-statusline-jornada.txt"
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

command -v node >/dev/null 2>&1 || exit 0

# A versao do plugin muda a cada atualizacao — pega a mais recente das duas
# pastas de configuracao (trabalho e pessoal) em vez de fixar o numero.
SCRIPT=$(ls -1t /c/Users/Luis/.claude*/plugins/cache/rainforest-mind/rainforest-mind/*/scripts/jornada.cjs 2>/dev/null | head -1)
[ -n "$SCRIPT" ] || exit 0

VALOR=$(node "$SCRIPT" 2>/dev/null | sed -n 's/^JORNADA EFETIVA[ .]*\([0-9]\+h[0-9]\+\).*/\1/p' | head -1)
[ -n "$VALOR" ] || exit 0

printf '%s' "$VALOR" > "$CACHE"
