#!/bin/bash
#
# Catraca: inverter o cálculo de ganho (sempre 0) e verificar que testa-medir-escada falha
# (demonstra que a coluna Ganho é medida e influencia o resultado)

set -u
cd "$(dirname "$0")/.." || exit 1

# Fazer backup do medir-escada.sh
cp scripts/medir-escada.sh scripts/medir-escada.sh.bak

# Criar versão com ganho invertido (sempre 0)
sed 's/ganho=\$((n_sem - n_com))/ganho=0  # CATRACA: ganho invertido/' \
  scripts/medir-escada.sh > scripts/medir-escada-catraca.sh
chmod +x scripts/medir-escada-catraca.sh

# Fazer backup do testa-medir-escada.sh
cp scripts/testa-medir-escada.sh scripts/testa-medir-escada.sh.bak

# Criar versão que chama o medir-escada modificado
sed 's|bash scripts/medir-escada.sh|bash scripts/medir-escada-catraca.sh|g' \
  scripts/testa-medir-escada.sh > scripts/testa-medir-escada-catraca.sh
chmod +x scripts/testa-medir-escada-catraca.sh

# Rodar a bateria de testes com ganho invertido
echo "Catraca: Ganho invertido (sempre 0) - bateria deve ficar vermelha"
bash scripts/testa-medir-escada-catraca.sh 2>&1
exit_code=$?

# Restaurar originais
mv scripts/medir-escada.sh.bak scripts/medir-escada.sh
mv scripts/testa-medir-escada.sh.bak scripts/testa-medir-escada.sh
rm -f scripts/medir-escada-catraca.sh scripts/testa-medir-escada-catraca.sh

echo ""
echo "Exit code: $exit_code (esperado: 1 - bateria vermelha)"

exit $exit_code
