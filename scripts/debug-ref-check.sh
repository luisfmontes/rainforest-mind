#!/bin/bash
mkdir -p /tmp/debug-test/skills/rainforest-mind/references /tmp/debug-test/scripts /tmp/debug-test/hooks
cp scripts/conferir-invariantes.cjs /tmp/debug-test/scripts/
cp skills/rainforest-mind/invariantes.json /tmp/debug-test/skills/rainforest-mind/
cp skills/rainforest-mind/SKILL.md /tmp/debug-test/skills/rainforest-mind/
cp -r skills/rainforest-mind/references /tmp/debug-test/skills/rainforest-mind/
cp -r hooks /tmp/debug-test/
# Remove a frase da referencia
sed -i 's/printenv NOME/printenv VARNAME/g' /tmp/debug-test/skills/rainforest-mind/references/regra-15.md
# Verifica que foi removido
echo "=== Check if removal worked ==="
grep "printenv NOME" /tmp/debug-test/skills/rainforest-mind/references/regra-15.md || echo "Phrase removed from reference"
# Executa o conferir na cópia com a mutação
echo "=== Running conferir-invariantes ==="
(cd /tmp/debug-test/scripts && node conferir-invariantes.cjs)
RESULTADO=$?
echo "=== Exit code: $RESULTADO ==="
rm -rf /tmp/debug-test
exit $RESULTADO
