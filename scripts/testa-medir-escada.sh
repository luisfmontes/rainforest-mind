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

unset RFM_MEDIR_CLI_CMD

# TESTE 4: Com CLI com-escada — mede Ganho (Sem != Com)
echo
echo "Teste 4: CLI com-escada (mede ganho)"
export RFM_MEDIR_CLI_CMD="node scripts/fixtures/escada/cli-com-escada.cjs"

saida=$(bash scripts/medir-escada.sh 2>&1)
exit4=$?

marca "exit 0 com CLI com-escada" $((exit4 == 0 ? 0 : 1))
marca "tem PASS em todas as tarefas" $( (echo "$saida" | grep "PASS" | wc -l | grep -qE "^[5-9]" && echo 0) || echo 1)
marca "Ganho total > 0" $( (echo "$saida" | grep "Ganho:" | grep -qE "Ganho: [1-9]" && echo 0) || echo 1)
marca "Todos valores Ganho > 0 em tarefas" $( (! echo "$saida" | grep "tarefa" | grep "| *0 *|" && echo 0) || echo 1)

unset RFM_MEDIR_CLI_CMD

# TESTE 5: Payload hostil — a fronteira de isolamento decide o veredito
#
# Estes três casos existem para que a catraca tenha o que medir. Trocar
# `vm.runInNewContext` por `eval`, ou o base64 da passagem por interpolação
# de template, faz cada um deles virar PASS (ou pendurar), e é só por isso
# que a bateria fica vermelha quando a fronteira sai.
#
# Nenhum payload apaga, escreve ou chama rede — ver cli-hostil.cjs.
echo
echo "Teste 5: payload hostil (fronteira de isolamento)"
export RFM_MEDIR_CLI_CMD="node scripts/fixtures/escada/cli-hostil.cjs"

# 5a — injeção de template literal.
# Só vira fatorial válido se a passagem interpolar. Com base64, chega inerte.
export RFM_MEDIR_PAYLOAD=injecao
saida5a=$(bash scripts/medir-escada.sh 2>&1)
marca "injeção de template não vira código (tarefa-01 FAIL)" \
  $( (echo "$saida5a" | grep -qE "^tarefa-01.*FAIL" && echo 0) || echo 1)

# 5b — fuga do sandbox.
# Fatorial correto *desde que* `require` exista. Dentro do vm, não existe.
export RFM_MEDIR_PAYLOAD=escape
saida5b=$(bash scripts/medir-escada.sh 2>&1)
marca "código que depende de require não passa (tarefa-01 FAIL)" \
  $( (echo "$saida5b" | grep -qE "^tarefa-01.*FAIL" && echo 0) || echo 1)

# 5c — laço infinito.
# O relógio do vm só vale para o que roda dentro da chamada: se as provas
# chamarem a função do lado de fora, isto pendura a bateria para sempre.
# O `timeout` aqui é a rede de segurança; o veredito é o FAIL por timeout.
export RFM_MEDIR_PAYLOAD=laco
# O relógio curto é só aqui: 5 s de espera parada por run é tempo que o CI não
# tem (ver o comentário de timeout-minutes em .github/workflows/baterias.yml).
# 500 ms provam a mesma coisa — que existe relógio.
export RFM_GATE_TIMEOUT_MS=500
saida5c=$(timeout 60 bash scripts/medir-escada.sh 2>&1)
exit5c=$?
unset RFM_GATE_TIMEOUT_MS
marca "laço infinito não pendura a bateria (exit != 124)" $((exit5c != 124 ? 0 : 1))
marca "laço infinito dá FAIL por timeout (tarefa-01 FAIL)" \
  $( (echo "$saida5c" | grep -qE "^tarefa-01.*FAIL" && echo 0) || echo 1)

unset RFM_MEDIR_PAYLOAD
unset RFM_MEDIR_CLI_CMD

echo
echo "== Resultado =="
echo "✓ Passou:  $ok"
echo "✗ Falhou:  $falhou"
echo

exit $((falhou > 0 ? 1 : 0))
