#!/bin/bash
set -u
echo "== T5/T6 mutation test =="
RFM_PODA_PORTA=9999 bash scripts/testa-relatorio-poda.sh 2>&1 | grep -c "^  ok"
