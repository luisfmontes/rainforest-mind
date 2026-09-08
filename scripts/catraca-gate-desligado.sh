#!/bin/bash
#
# Catraca: desligar o gate de correção e verificar que a bateria fica vermelha
# (passa para tarefas que falharam no gate, o que é errado)

set -u
cd "$(dirname "$0")/.." || exit 1

# Fazer backup do gates.cjs
cp scripts/fixtures/escada/gates.cjs scripts/fixtures/escada/gates.cjs.bak

# Criar gates fake que sempre passam
cat > scripts/fixtures/escada/gates.cjs << 'EOF'
#!/usr/bin/env node
const gates = {
  'tarefa-01': { descricao: 'ok', assert: () => ({ ok: true }) },
  'tarefa-02': { descricao: 'ok', assert: () => ({ ok: true }) },
  'tarefa-03': { descricao: 'ok', assert: () => ({ ok: true }) },
  'tarefa-04': { descricao: 'ok', assert: () => ({ ok: true }) },
  'tarefa-05': { descricao: 'ok', assert: () => ({ ok: true }) }
};
module.exports = gates;
EOF

# Rodar a medição
export RFM_MEDIR_CLI_CMD="node scripts/fixtures/escada/cli-com-escada.cjs"
saida=$(bash scripts/medir-escada.sh 2>&1)
exit_code=$?

# Restaurar gates original
mv scripts/fixtures/escada/gates.cjs.bak scripts/fixtures/escada/gates.cjs

# Exibir resultado (deve passar porque gates sempre ok)
echo "Catraca: Gate de correção desligado (gates sempre passam)"
echo "$saida"
echo ""
echo "Exit code: $exit_code (esperado: 0)"

exit $exit_code
