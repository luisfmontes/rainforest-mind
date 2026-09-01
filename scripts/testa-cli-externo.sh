#!/bin/bash
# Bateria para cli-externo.cjs — transporte de CLI externo
# Uso: bash scripts/testa-cli-externo.sh
#
# Testa rodarCli e extrairJson contra fixture.

set -u

# Get source directory
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run test suite
node "$SRC/scripts/testa-cli-externo.cjs"
exit $?
