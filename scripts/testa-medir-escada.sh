#!/usr/bin/env bash
#
# testa-medir-escada.sh — teste de medir-escada.sh com dublés
#
# Testes:
# 1. Com CLI dublador OK — tarefas passam, tem números
# 2. Com CLI dublador FAIL — tarefas falham, não contam como ganho
# 3. Sem RFM_MEDIR_CLI_CMD — reporta PULO, exit 0
#
# Exit 0 = todos passaram

set -u

cd "$(dirname "$0")/.." || exit 1

ok=0 falhou=0

marca() {
  if [ "$2" -eq 0 ]; then
    ok=$((ok+1)); echo "  ✓ $1"
  else
    falhou=$((falhou+1)); echo "  ✗ FALHA: $1"
  fi
}

echo "== Teste de medir-escada.sh com dublés =="
echo

# TESTE 1: Com CLI fake que retorna código curto (passa no gate)
echo "Teste 1: CLI fake OK (dublador-ok)"
export RFM_MEDIR_CLI_CMD="node scripts/fixtures/escada/cli-ok.cjs"

saida=$(bash scripts/medir-escada.sh 2>&1)
exit1=$?

marca "exit 0 com CLI ok" $((exit1 == 0 ? 0 : 1))
marca "tem 'Medição da Escada'" $( (echo "$saida" | grep -q "Medição" && echo 0) || echo 1)
marca "tem 'Tarefa' no cabeçalho" $( (echo "$saida" | grep -q "Tarefa" && echo 0) || echo 1)
marca "tem PASS (tarefas aprovadas)" $( (echo "$saida" | grep -q "PASS" && echo 0) || echo 1)
marca "tem Sumário" $( (echo "$saida" | grep -q "Sumário" && echo 0) || echo 1)

unset RFM_MEDIR_CLI_CMD

# TESTE 2: Com CLI fake que retorna null (falha no gate)
echo
echo "Teste 2: CLI fake FAIL (dublador-fail/null)"
export RFM_MEDIR_CLI_CMD="node scripts/fixtures/escada/cli-fail.cjs"

saida=$(bash scripts/medir-escada.sh 2>&1)
exit2=$?

marca "exit 0 com CLI fail" $((exit2 == 0 ? 0 : 1))
marca "tem FAIL no relatório" $( (echo "$saida" | grep -q "FAIL" && echo 0) || echo 1)
marca "tem 'Fail: [1-9]' no sumário" $( (echo "$saida" | grep -qE "Fail:\s+[1-9]" && echo 0) || echo 1)

unset RFM_MEDIR_CLI_CMD

# TESTE 3: Sem RFM_MEDIR_CLI_CMD (sem CLI declarado)
echo
echo "Teste 3: Sem RFM_MEDIR_CLI_CMD"

saida=$(bash scripts/medir-escada.sh 2>&1)
exit3=$?

marca "exit 0 sem CLI" $((exit3 == 0 ? 0 : 1))
marca "reporta 'PULO'" $( (echo "$saida" | grep -q "PULO" && echo 0) || echo 1)
marca "NÃO tem números de medição" $( (! echo "$saida" | grep -qE "^\s+tarefa" && echo 0) || echo 1)

echo
echo "== Resultado =="
echo "✓ Passou:  $ok"
echo "✗ Falhou:  $falhou"
echo

exit $((falhou > 0 ? 1 : 0))
