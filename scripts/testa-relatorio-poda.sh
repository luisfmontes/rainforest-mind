#!/bin/bash
# Bateria de testes para scripts/relatorio-poda.cjs (Tarefa 8 do plano).
#
# A contagem PROPAGA (nada de incremento em subshell) e os totais impressos
# são conferidos contra números calculados à mão a partir do fixture, não
# contra o que o próprio relatório decidiu imprimir.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi; }
afirma() { if eval "$1"; then ok=$((ok+1)); echo "  ok   $2"; else falhou=$((falhou+1)); echo "  FALHA $2"; fi; }

RAIZ="$SBP/raiz"
mkdir -p "$RAIZ/poda"

metrica() {
  # metrica <timestamp-iso> <estagio-ou-null> <input> <output> <cache_read> <cache_creation> <duracao_ms>
  local ts="$1" estagio="$2" input="$3" output="$4" cread="$5" ccreate="$6" dur="$7"
  local estagio_json
  if [ "$estagio" = "null" ]; then estagio_json="null"; else estagio_json="\"$estagio\""; fi
  printf '{"timestamp":"%s","estagio":%s,"duracao_ms":%s,"usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s}}\n' \
    "$ts" "$estagio_json" "$dur" "$input" "$output" "$cread" "$ccreate"
}

echo "== 1. Gate FECHADO com 3 dias-calendario distintos =="

{
  metrica "2026-08-01T10:00:00.000Z" "executar" 10 5 2 0 100
  metrica "2026-08-02T10:00:00.000Z" "executar" 15 6 3 0 110
  metrica "2026-08-03T10:00:00.000Z" "executar" 12 5 2 0 105
} > "$RAIZ/poda/metricas.jsonl"

SAIDA_FECHADO=$(RFM_ROOT="$RAIZ" node "$SRC/scripts/relatorio-poda.cjs" 2>&1)
EXIT_FECHADO=$?

afirma "echo \"\$SAIDA_FECHADO\" | grep -q 'FECHADO'" "saida cita FECHADO"
afirma "echo \"\$SAIDA_FECHADO\" | grep -q '3 de 7 dias'" "saida cita '3 de 7 dias' (contagem certa de dias faltando)"
afirma "[ '$EXIT_FECHADO' -ne 0 ]" "exit != 0 com gate fechado (veio $EXIT_FECHADO)"

SAIDA_FECHADO_JSON=$(RFM_ROOT="$RAIZ" node "$SRC/scripts/relatorio-poda.cjs" --json 2>&1)
DIAS_JSON_FECHADO=$(node -e "console.log(JSON.parse(process.argv[1]).dias_distintos)" "$SAIDA_FECHADO_JSON" 2>/dev/null || echo "ERRO")
igual "--json com gate fechado: dias_distintos == 3" "3" "$DIAS_JSON_FECHADO"
GATE_JSON_FECHADO=$(node -e "console.log(JSON.parse(process.argv[1]).gate)" "$SAIDA_FECHADO_JSON" 2>/dev/null || echo "ERRO")
igual "--json com gate fechado: gate == FECHADO" "FECHADO" "$GATE_JSON_FECHADO"

echo
echo "== 2. Gate ABERTO com 7 dias-calendario distintos (8 registros: dia 1 tem 2) =="

# Fixture com estagio VARIADO (incluindo null -> 'desconhecido') e valores
# fixos, para conferir as somas a mao. Dia 1 recebe DOIS registros para provar
# que "multiplos registros no mesmo dia contam como 1 dia".
{
  metrica "2026-08-01T10:00:00.000Z" "executar" 100 50 20 5 200
  metrica "2026-08-01T15:00:00.000Z" "executar" 150 60 30 10 300
  metrica "2026-08-02T10:00:00.000Z" "revisar"  200 80 40 0  100
  metrica "2026-08-03T10:00:00.000Z" "null"      50  20 10 0  150
  metrica "2026-08-04T10:00:00.000Z" "executar" 300 100 60 0  250
  metrica "2026-08-05T10:00:00.000Z" "revisar"  100 40 20 0  120
  metrica "2026-08-06T10:00:00.000Z" "null"      75  30 15 0  180
  metrica "2026-08-07T10:00:00.000Z" "executar" 125 45 25 0  220
} > "$RAIZ/poda/metricas.jsonl"

# Totais calculados A MAO (nao pelo relatorio):
#   executar:     input=675  output=255 cache_read=135 requisicoes=4
#   revisar:      input=300  output=120 cache_read=60  requisicoes=2
#   desconhecido: input=125  output=50  cache_read=25  requisicoes=2
#   total input=1100 total cache_read=220 -> cache_hit = 220/1320*100 = 16.666...% -> 16.67
#   soma duracao = 200+300+100+150+250+120+180+220 = 1520 / 8 registros = 190ms

SAIDA_ABERTO=$(RFM_ROOT="$RAIZ" node "$SRC/scripts/relatorio-poda.cjs" 2>&1)
EXIT_ABERTO=$?

afirma "echo \"\$SAIDA_ABERTO\" | grep -q 'ABERTO'" "saida cita ABERTO"
afirma "[ '$EXIT_ABERTO' -eq 0 ]" "exit 0 com gate aberto (veio $EXIT_ABERTO)"

afirma "echo \"\$SAIDA_ABERTO\" | grep -qF 'executar: input=675, output=255, cache_read=135, requisicoes=4'" "soma do estagio 'executar' bate a mao (4 registros, 2 no mesmo dia)"
afirma "echo \"\$SAIDA_ABERTO\" | grep -qF 'revisar: input=300, output=120, cache_read=60, requisicoes=2'" "soma do estagio 'revisar' bate a mao"
afirma "echo \"\$SAIDA_ABERTO\" | grep -qF 'desconhecido: input=125, output=50, cache_read=25, requisicoes=2'" "estagio null vira linha 'desconhecido' com soma certa"

afirma "echo \"\$SAIDA_ABERTO\" | grep -qF 'Cache hit agregado: 16.67%'" "cache hit agregado == cache_read/(cache_read+input) calculado a mao (220/1320)"
afirma "echo \"\$SAIDA_ABERTO\" | grep -qF 'Requisições totais: 8'" "requisicoes totais == 8 (nao confunde com 7 dias distintos)"
afirma "echo \"\$SAIDA_ABERTO\" | grep -qF 'Duração média: 190ms'" "duracao media bate a mao (1520ms / 8 registros)"

afirma "echo \"\$SAIDA_ABERTO\" | grep -q 'sem proxy.*não é possível\\|não é possível.*sem proxy'" "nota 'nao compara com sem-proxy' presente na saida"

echo
echo "== 3. --json com o mesmo fixture (7 dias, 8 registros) =="

SAIDA_JSON=$(RFM_ROOT="$RAIZ" node "$SRC/scripts/relatorio-poda.cjs" --json 2>&1)

GATE_JSON=$(node -e "console.log(JSON.parse(process.argv[1]).gate)" "$SAIDA_JSON" 2>/dev/null || echo "ERRO")
igual "--json: gate == ABERTO" "ABERTO" "$GATE_JSON"

DIAS_JSON=$(node -e "console.log(JSON.parse(process.argv[1]).dias_distintos)" "$SAIDA_JSON" 2>/dev/null || echo "ERRO")
igual "--json: dias_distintos == 7 (nao 8, apesar de 8 registros)" "7" "$DIAS_JSON"

REQ_JSON=$(node -e "console.log(JSON.parse(process.argv[1]).requisicoes_totais)" "$SAIDA_JSON" 2>/dev/null || echo "ERRO")
igual "--json: requisicoes_totais == 8" "8" "$REQ_JSON"

CACHE_HIT_JSON=$(node -e "console.log(JSON.parse(process.argv[1]).cache_hit_percentual)" "$SAIDA_JSON" 2>/dev/null || echo "ERRO")
igual "--json: cache_hit_percentual == 16.67" "16.67" "$CACHE_HIT_JSON"

DUR_MEDIA_JSON=$(node -e "console.log(JSON.parse(process.argv[1]).duracao_media_ms)" "$SAIDA_JSON" 2>/dev/null || echo "ERRO")
igual "--json: duracao_media_ms == 190" "190" "$DUR_MEDIA_JSON"

EXECUTAR_INPUT_JSON=$(node -e "console.log(JSON.parse(process.argv[1]).por_estagio.executar.input_tokens)" "$SAIDA_JSON" 2>/dev/null || echo "ERRO")
igual "--json: por_estagio.executar.input_tokens == 675" "675" "$EXECUTAR_INPUT_JSON"

DESCONHECIDO_REQ_JSON=$(node -e "console.log(JSON.parse(process.argv[1]).por_estagio.desconhecido.requisicoes)" "$SAIDA_JSON" 2>/dev/null || echo "ERRO")
igual "--json: por_estagio.desconhecido.requisicoes == 2 (o null do fixture)" "2" "$DESCONHECIDO_REQ_JSON"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
