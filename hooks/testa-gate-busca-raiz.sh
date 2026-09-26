#!/bin/bash
# Casca para o CI: `scripts/varrer-baterias.sh` só descobre `testa-*.sh`, e a
# bateria do gate-busca-raiz é node. Sem esta casca ela nunca rodaria no CI.
exec node "$(dirname "${BASH_SOURCE[0]}")/testa-gate-busca-raiz.cjs"
