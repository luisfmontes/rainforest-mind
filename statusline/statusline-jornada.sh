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
#
# A raiz sai do HOME de quem roda, nunca de um nome chumbado. Ate 2026-09-02
# este caminho tinha o home do autor escrito, e SEM variavel de escape: na
# maquina de qualquer outra pessoa o glob nao casava, `SCRIPT` ficava vazio e a
# linha seguinte saia 0 em silencio. Statusline que nao aparece e a falha mais
# facil de nao notar que existe — nada quebra, so nao aparece.
#
# `cd ~ && pwd` e nao `$USERPROFILE`: o glob precisa da forma POSIX
# (`/c/Users/<nome>`), e `$USERPROFILE` chega em forma Windows. Mesmo idioma do
# `scripts/instalar-statusline.sh`.
CACHE_ROOT="${RAINFOREST_STATUSLINE_CACHE:-$(cd ~ 2>/dev/null && pwd || echo "$HOME")/.claude*/plugins/cache/rainforest-mind/rainforest-mind}"
SCRIPT=$(ls -1t $CACHE_ROOT/*/scripts/jornada.cjs 2>/dev/null | head -1)
[ -n "$SCRIPT" ] || exit 0

VALOR=$(node "$SCRIPT" 2>/dev/null | sed -n 's/^JORNADA EFETIVA[ .]*\([0-9]\+h[0-9]\+\).*/\1/p' | head -1)
[ -n "$VALOR" ] || exit 0

printf '%s' "$VALOR" > "$CACHE"
