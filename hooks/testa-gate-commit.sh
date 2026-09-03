#!/usr/bin/env bash
# Wrapper que põe a bateria da trava de commit dentro da suíte.
#
# A bateria em si é `hooks/testa-gate-commit.cjs`, em node de propósito (o
# cabeçalho dela explica: a Issue #158 mediu uma bateria irmã reportando "4 ok"
# sobre casos que ninguém exerceu, porque sem `jq` o payload saía vazio).
#
# Este arquivo existe porque o glob que define a suíte casa **só** `.sh`:
#
#   .github/workflows/baterias.yml -> ls scripts/testa-*.sh hooks/testa-*.sh
#   CONTRIBUTING.md                -> for t in scripts/testa-*.sh hooks/testa-*.sh
#
# Bateria `.cjs` sem wrapper nasce órfã — foi o que aconteceu com as seis do
# fluxo 9, escritas, verdes, e nunca executadas por ninguém até 2026-09-02.
# Mesmo padrão do `hooks/testa-portaria.sh`.
set -u

cd "$(dirname "$0")/.." || exit 1

exec node hooks/testa-gate-commit.cjs
