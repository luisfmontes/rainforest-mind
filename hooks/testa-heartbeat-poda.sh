#!/bin/bash
# Teste do conserto: poda por IDADE, não por PID.
# Uso: bash hooks/testa-heartbeat-poda.sh
#
# O CONSERTO: podar só por IDADE (24h), não por PID. SessionEnd cuida do
# fechamento limpo. Asserção: com duas entradas recentes e um heartbeat de
# terceira sessão, todas as 3 coexistem no arquivo. SessionEnd remove, idade
# remove; pid nunca remove.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

echo
echo "=========================================="
echo "TESTE: Poda por IDADE, coexistência por recência"
echo "=========================================="

AGORA=$(date +%s000)

# Setup: 2 entradas recentes (simulando sessões vivas)
mkdir -p "$RAIZ_POSIX"
cat > "$RAIZ_POSIX/sessoes.json" << EOF
{
  "sessao1": { "cwd": "C:/proj1", "prompt_ts": $AGORA },
  "sessao2": { "cwd": "C:/proj2", "prompt_ts": $AGORA }
}
EOF

echo "Entradas ANTES: 2 sessões recentes"
cat "$RAIZ_POSIX/sessoes.json" | python3 -m json.tool 2>/dev/null | head -12

# Rodar heartbeat de TERCEIRA sessão
export RFM_ROOT="$RAIZ"
printf '{"session_id":"sessao3","cwd":"C:/proj3"}' | node "$SRC/hooks/heartbeat.cjs" prompt 2>/dev/null

RESULTADO="$(cat "$RAIZ_POSIX/sessoes.json")"

echo ""
echo "Entradas DEPOIS: rodar heartbeat de sessao3"
echo "$RESULTADO" | python3 -m json.tool 2>/dev/null | head -20

ENTRADA_COUNT=$(echo "$RESULTADO" | grep -oE '"sessao[123]"' | sort -u | wc -l)

if [ "$ENTRADA_COUNT" -eq 3 ]; then
  ok=$((ok+1)); echo "  ok    todas 3 entradas coexistem"
else
  falhou=$((falhou+1)); echo "  FALHA apenas $ENTRADA_COUNT entradas (esperado 3)"
fi

# Verificar que não há 'pid' gravado
if echo "$RESULTADO" | grep -q '"pid"'; then
  falhou=$((falhou+1)); echo "  FALHA encontrado campo 'pid' no arquivo (não deveria estar)"
else
  ok=$((ok+1)); echo "  ok    nenhuma entrada tem campo 'pid' (como esperado)"
fi

# Verificar que SessionEnd funciona (deletar entrada própria)
AGORA_2=$(date +%s000)
printf '{"session_id":"sessao1","cwd":"C:/proj1"}' | RFM_ROOT="$RAIZ" node "$SRC/hooks/heartbeat.cjs" end 2>/dev/null
RESULTADO_2="$(cat "$RAIZ_POSIX/sessoes.json")"

ENTRADA_COUNT_2=$(echo "$RESULTADO_2" | grep -oE '"sessao[123]"' | sort -u | wc -l)

if [ "$ENTRADA_COUNT_2" -eq 2 ]; then
  ok=$((ok+1)); echo "  ok    SessionEnd removeu sessao1, ficaram 2 entradas"
else
  falhou=$((falhou+1)); echo "  FALHA após SessionEnd de sessao1 ficaram $ENTRADA_COUNT_2 entradas (esperado 2)"
fi

if ! echo "$RESULTADO_2" | grep -q '"sessao1"'; then
  ok=$((ok+1)); echo "  ok    sessao1 foi removida por SessionEnd"
else
  falhou=$((falhou+1)); echo "  FALHA sessao1 ainda está no arquivo após SessionEnd"
fi

echo
echo "=========================================="
echo "Resumo: $ok ok, $falhou falhas"
echo "=========================================="
[ $falhou -eq 0 ]
