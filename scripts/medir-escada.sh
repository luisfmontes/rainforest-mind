#!/usr/bin/env bash
#
# medir-escada.sh — bateria de medição do efeito da escada
#
# Roda um conjunto fixo de tarefas COM E SEM o additionalContext da escada,
# e mede linhas de código + gate de correção.
#
# Ambiente: RFM_MEDIR_CLI_CMD (para teste com dublé)
# Saída: relatório tabulado, ou "PULO: nenhum CLI declarado"
# Exit: 0 em sucesso (mesmo que tarefas falhem)

set -u

cd "$(dirname "$0")/.." || exit 1

FIXTURES_DIR="scripts/fixtures/escada"
GATES_FILE="$FIXTURES_DIR/gates.cjs"
RODAR_SCRIPT="$FIXTURES_DIR/rodar-tarefa.cjs"

# Validar que as fixtures existem
if [ ! -d "$FIXTURES_DIR" ] || [ ! -f "$GATES_FILE" ] || [ ! -f "$RODAR_SCRIPT" ]; then
  echo "ERRO: fixtures não encontradas" >&2
  exit 1
fi

# Descobrir qual CLI usar
if [ -z "${RFM_MEDIR_CLI_CMD:-}" ]; then
  echo "PULO: nenhum CLI declarado"
  exit 0
fi

CLI_CMD="$RFM_MEDIR_CLI_CMD"

echo "== Medição da Escada =="
echo "CLI: $CLI_CMD"
echo

# Coletar tarefas
TAREFAS=()
for f in "$FIXTURES_DIR"/tarefa-*.txt; do
  if [ -f "$f" ]; then
    TAREFAS+=("$(basename "$f" .txt)")
  fi
done

if [ ${#TAREFAS[@]} -eq 0 ]; then
  echo "ERRO: nenhuma tarefa encontrada" >&2
  exit 1
fi

echo "Tarefas encontradas: ${#TAREFAS[@]}"
echo

# Função: rodar gate
rodar_gate() {
  local tarefa="$1" codigo="$2"
  # Codificar o código em base64 para evitar injeção de template literal
  local codigo_b64
  codigo_b64=$(printf '%s' "$codigo" | base64 -w 0)

  node -e "
const gates = require('./$GATES_FILE');
const gate = gates['$tarefa'];
if (!gate) { console.log(JSON.stringify({ok:false})); process.exit(0); }
try {
  const codigo = Buffer.from('$codigo_b64', 'base64').toString('utf8');
  const resultado = gate.assert(codigo);
  console.log(JSON.stringify(resultado));
} catch(e) {
  console.log(JSON.stringify({ok:false,erro:e.message}));
}
" || echo '{"ok":false}'
}

# Relatório
printf "%-12s | %8s | %8s | %8s | %s\n" "Tarefa" "Sem" "Com" "Ganho" "Status"
printf "%s\n" "-------------------------------------------"

total_ganho=0 pass=0 fail=0

for tarefa in "${TAREFAS[@]}"; do
  # Rodar SEM e COM escada usando o script dedicado
  sem=$(node "$RODAR_SCRIPT" "$tarefa" "$CLI_CMD" false 2>/dev/null || echo "")
  com=$(node "$RODAR_SCRIPT" "$tarefa" "$CLI_CMD" true 2>/dev/null || echo "")

  # Contar caracteres
  n_sem=${#sem}
  n_com=${#com}
  ganho=$((n_sem - n_com))

  # Gate (testar apenas a versão COM escada)
  gate=$(rodar_gate "$tarefa" "$com")
  ok=$(echo "$gate" | grep -o '"ok":\s*true' | wc -l)

  if [ "$ok" -eq 1 ]; then
    [ "$ganho" -gt 0 ] && total_ganho=$((total_ganho + ganho))
    pass=$((pass + 1))
    status="PASS"
  else
    fail=$((fail + 1))
    status="FAIL"
  fi

  printf "%-12s | %8d | %8d | %8d | %s\n" "$tarefa" "$n_sem" "$n_com" "$ganho" "$status"
done

echo
echo "== Sumário =="
echo "Total: ${#TAREFAS[@]} | Pass: $pass | Fail: $fail | Ganho: $total_ganho"

exit 0
