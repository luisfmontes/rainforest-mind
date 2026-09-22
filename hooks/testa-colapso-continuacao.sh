#!/usr/bin/env bash
# Roda a bateria de unidade do colapso de continuacao de linha.
# Existe como .sh porque `scripts/varrer-baterias.sh` e o CONTRIBUTING varrem
# `hooks/testa-*.sh` — um `.cjs` solto nunca rodaria no caminho oficial, que foi
# como o gemeo Python da #303 congelou por tres semanas.
set -u
cd "$(dirname "$0")/.." || exit 1
exec node hooks/testa-colapso-continuacao.cjs
