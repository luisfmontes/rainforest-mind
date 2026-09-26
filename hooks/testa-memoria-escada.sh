#!/bin/bash
# Casca para o CI: `scripts/varrer-baterias.sh` só descobre `testa-*.sh` (issue #335).
exec node "$(dirname "${BASH_SOURCE[0]}")/testa-memoria-escada.cjs"
