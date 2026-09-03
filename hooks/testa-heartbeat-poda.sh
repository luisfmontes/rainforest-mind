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

# As entradas do fixture levam um pid GARANTIDAMENTE MORTO, e isso é o que faz o
# teste discriminar. Sem ele, a asserção de coexistência passa contra o código
# antigo também: a poda velha era `x.pid && ... && !processoVivo(x.pid)`, que
# curto-circuita quando não há `pid`. Medido em 2026-08-13 — a primeira versão
# deste teste gravava o fixture sem pid e dava "3 entradas coexistem" nos dois
# lados, provando nada. Com pid morto, o código antigo poda as duas e sobra 1.
MORTO=$(node -e 'const c=require("child_process");const p=c.spawnSync(process.execPath,["-e",""]);console.log(p.pid)')
node -e 'process.exit(0)' # garante que o interpretador acima já saiu
echo "(pid morto usado no fixture: $MORTO)"

# Setup: 2 entradas recentes (simulando sessões vivas) com pid já morto
mkdir -p "$RAIZ_POSIX"
cat > "$RAIZ_POSIX/sessoes.json" << EOF
{
  "sessao1": { "cwd": "C:/proj1", "pid": $MORTO, "prompt_ts": $AGORA },
  "sessao2": { "cwd": "C:/proj2", "pid": $MORTO, "prompt_ts": $AGORA }
}
EOF

echo "Entradas ANTES: 2 sessões recentes"
cat "$RAIZ_POSIX/sessoes.json" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{console.log(JSON.stringify(JSON.parse(d),null,2))}catch{}})' | head -12

# Rodar heartbeat de TERCEIRA sessão
export RFM_ROOT="$RAIZ"
printf '{"session_id":"sessao3","cwd":"C:/proj3"}' | node "$SRC/hooks/heartbeat.cjs" prompt 2>/dev/null

RESULTADO="$(cat "$RAIZ_POSIX/sessoes.json")"

echo ""
echo "Entradas DEPOIS: rodar heartbeat de sessao3"
echo "$RESULTADO" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{console.log(JSON.stringify(JSON.parse(d),null,2))}catch{}})' | head -20

ENTRADA_COUNT=$(echo "$RESULTADO" | grep -oE '"sessao[123]"' | sort -u | wc -l)

if [ "$ENTRADA_COUNT" -eq 3 ]; then
  ok=$((ok+1)); echo "  ok    todas 3 entradas coexistem"
else
  falhou=$((falhou+1)); echo "  FALHA apenas $ENTRADA_COUNT entradas (esperado 3)"
fi

# A entrada ESCRITA pelo heartbeat não leva pid. A pergunta é sobre `sessao3`, não
# sobre o arquivo: o fixture tem pid de propósito (ver acima), então varrer o
# arquivo inteiro por '"pid"' acusaria o próprio fixture.
if node -e '
  const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  process.exit(s.sessao3 && !("pid" in s.sessao3) ? 0 : 1);
' "$RAIZ_POSIX/sessoes.json"; then
  ok=$((ok+1)); echo "  ok    a entrada escrita pelo heartbeat (sessao3) nao tem pid"
else
  falhou=$((falhou+1)); echo "  FALHA sessao3 gravou campo 'pid' (nao deveria)"
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

# A poda por IDADE é a única que sobrou, então é a única rede embaixo: se ela não
# funcionar, entrada de janela fechada fica no arquivo para sempre e o radar conta
# janela morta como viva. Sem esta asserção o conserto trocava uma cegueira por
# um vazamento — e nada no repo media isso (não havia teste de idade antes).
echo
echo "IDADE: entrada com atividade mais velha que 24h sai"
VELHO=$(( $(date +%s) * 1000 - 25 * 3600 * 1000 ))
cat > "$RAIZ_POSIX/sessoes.json" << EOF
{
  "antiga":  { "cwd": "C:/velha", "prompt_ts": $VELHO },
  "recente": { "cwd": "C:/nova",  "prompt_ts": $AGORA }
}
EOF
printf '{"session_id":"gatilho","cwd":"C:/g"}' | RFM_ROOT="$RAIZ" node "$SRC/hooks/heartbeat.cjs" prompt 2>/dev/null
RESULTADO_3="$(cat "$RAIZ_POSIX/sessoes.json")"

if ! echo "$RESULTADO_3" | grep -q '"antiga"'; then
  ok=$((ok+1)); echo "  ok    entrada de 25h atras foi podada"
else
  falhou=$((falhou+1)); echo "  FALHA entrada de 25h atras sobreviveu"
fi

if echo "$RESULTADO_3" | grep -q '"recente"'; then
  ok=$((ok+1)); echo "  ok    entrada recente sobreviveu a poda de idade"
else
  falhou=$((falhou+1)); echo "  FALHA poda de idade levou a entrada recente junto"
fi

echo
echo "=========================================="
echo "Resumo: $ok ok, $falhou falhas"
echo "=========================================="
[ $falhou -eq 0 ]
