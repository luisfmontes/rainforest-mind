#!/bin/bash

# Testes de ferramentas.cjs — a porta única do ledger
# Valida os 5 critérios de sucesso do briefing

# Setup
TMPDIR="${TMPDIR:-.}"
CAIXA=$(mktemp -d)
export RFM_ROOT="$CAIXA"
trap "rm -rf '$CAIXA'" EXIT

mkdir -p "$CAIXA"

# Contadores
OK=0
FALHA=0

# Atalhos para o script
NODE_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/ferramentas.cjs"

# ==== CRITÉRIO 1 ====
echo "=== CRITÉRIO 1: Consultar ferramenta existente ==="
RECEITA_ORIGINAL='C:\Program Files\whisper-cli\whisper.exe --model C:\models\model.bin'
node "$NODE_SCRIPT" registrar whisper-cli "$RECEITA_ORIGINAL" "descoberta-por-prompt" >/dev/null 2>&1
RESULTADO=$(node "$NODE_SCRIPT" consultar whisper-cli 2>/dev/null)
if [ "$RESULTADO" = "$RECEITA_ORIGINAL" ]; then
  echo "✓ consultar whisper-cli retorna receita gravada"
  OK=$((OK + 1))
else
  echo "✗ FALHA: esperava '$RECEITA_ORIGINAL', obteve '$RESULTADO'"
  FALHA=$((FALHA + 1))
fi

# ==== CRITÉRIO 2 ====
echo ""
echo "=== CRITÉRIO 2: Consultar inexistente ==="
RESULTADO=$(node "$NODE_SCRIPT" consultar ferramenta-inexistente 2>/dev/null)
if [ "$RESULTADO" = "desconhecido" ] && ! echo "$RESULTADO" | grep -qi "ausente"; then
  echo "✓ consultar inexistente: imprime 'desconhecido', sem 'ausente'"
  OK=$((OK + 1))
else
  echo "✗ FALHA: resultado='$RESULTADO'"
  FALHA=$((FALHA + 1))
fi

# ==== CRITÉRIO 3 ====
echo ""
echo "=== CRITÉRIO 3: Rejeitar campo de negativa ==="
TEMP_JSON="$CAIXA/temp-entrada.json"
echo '{"nome":"teste-neg","receita":"cmd","descoberto":"prompt","ausente":true}' > "$TEMP_JSON"
node "$NODE_SCRIPT" registrar --json < "$TEMP_JSON" > "$CAIXA/temp-saida.txt" 2>&1
TESTE_EXIT=$?
TESTE_SAIDA=$(cat "$CAIXA/temp-saida.txt")
if [ $TESTE_EXIT -eq 2 ] && echo "$TESTE_SAIDA" | grep -q "ausente"; then
  echo "✓ registrar com 'ausente': rejeitado (exit 2), mensagem nomeia chave"
  OK=$((OK + 1))
else
  echo "✗ FALHA: exit=$TESTE_EXIT, saída='$TESTE_SAIDA'"
  FALHA=$((FALHA + 1))
fi
rm -f "$TEMP_JSON" "$CAIXA/temp-saida.txt"

# ==== CRITÉRIO 4 ====
echo ""
echo "=== CRITÉRIO 4: Reescrever mesmo nome (D13) ==="
ANTES=$(wc -l < "$CAIXA/ferramentas.jsonl" 2>/dev/null || echo "0")
node "$NODE_SCRIPT" registrar whisper-cli "nova-receita-v2" "descoberta-manual" >/dev/null 2>&1
DEPOIS=$(wc -l < "$CAIXA/ferramentas.jsonl" 2>/dev/null || echo "0")
RESULTADO=$(node "$NODE_SCRIPT" consultar whisper-cli 2>/dev/null)

if [ "$ANTES" -eq "$DEPOIS" ] && [ "$RESULTADO" = "nova-receita-v2" ]; then
  echo "✓ reescrever mesmo nome: contagem mantida ($ANTES = $DEPOIS), receita atualizada"
  OK=$((OK + 1))
else
  echo "✗ FALHA: antes=$ANTES, depois=$DEPOIS, resultado=$RESULTADO"
  FALHA=$((FALHA + 1))
fi

# ==== CRITERIO 4b: receita e OPCIONAL, e quebra de linha e recusada ====
# Nasceu do defeito de 2026-08-25: com `receita` obrigatoria, o hook de consulta
# foi forcado a inventar uma e gravou a saida crua do `where` — dois caminhos
# concatenados, com um CR no meio. Receita inventada custa mais que ausente.
echo ""
echo "=== CRITERIO 4b: receita opcional, e sem saida crua de comando ==="

node -e "console.log(JSON.stringify({nome:'sem-receita',descoberto:'sonda-consulta'}))"   | node "$NODE_SCRIPT" registrar --json >/dev/null 2>&1
SEM_RECEITA_EXIT=$?
LINHA=$(grep '"nome":"sem-receita"' "$RFM_ROOT/ferramentas.jsonl" 2>/dev/null)
CONSULTA=$(node "$NODE_SCRIPT" consultar sem-receita 2>/dev/null)

if [ "$SEM_RECEITA_EXIT" -eq 0 ] && [ -n "$LINHA" ] && ! printf '%s' "$LINHA" | grep -q '"receita"'; then
  echo "✓ registrar sem receita: aceito, e a linha nao ganha campo 'receita'"
  OK=$((OK + 1))
else
  echo "✗ FALHA: exit=$SEM_RECEITA_EXIT linha=$LINHA"
  FALHA=$((FALHA + 1))
fi

if [ -n "$CONSULTA" ] && [ "$CONSULTA" != "desconhecido" ]; then
  echo "✓ consultar entrada sem receita: nao diz 'desconhecido' ($CONSULTA)"
  OK=$((OK + 1))
else
  echo "✗ FALHA: consulta de entrada sem receita devolveu '$CONSULTA'"
  FALHA=$((FALHA + 1))
fi

node -e "console.log(JSON.stringify({nome:'crua',receita:'a'+String.fromCharCode(10)+'b',descoberto:'t'}))" | node "$NODE_SCRIPT" registrar --json >/dev/null 2>&1
CRUA_EXIT=$?
if [ "$CRUA_EXIT" -eq 2 ]; then
  echo "✓ receita com quebra de linha: recusada (exit 2)"
  OK=$((OK + 1))
else
  echo "✗ FALHA: receita com quebra de linha saiu $CRUA_EXIT, esperava 2"
  FALHA=$((FALHA + 1))
fi

# ==== CRITÉRIO 5 ====
echo ""
echo "=== CRITÉRIO 5: Placar final ==="
PLACAR="$OK ok, $FALHA falha(s)"
echo "$PLACAR"

# Exit baseado em falhas
if [ $FALHA -gt 0 ]; then
  exit 1
else
  exit 0
fi
