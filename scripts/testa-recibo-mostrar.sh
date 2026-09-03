#!/bin/bash
# Bateria de testes para `recibo.cjs mostrar`.
# Uso: bash scripts/testa-recibo-mostrar.sh
#
# Tarefa 1 do plano `docs/rainforest/planos/2026-09-02-fluxo-7-recibo.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR:
#
#   1. Que `mostrar` trate ausencia de recibo como erro. Ausencia nao e' erro —
#      a maioria dos fluxos nao vai ter recibo porque o manifesto e' opt-in.
#
#   2. Que `mostrar` retorne estrutura errada quando recibo existe. Deve exibir
#      caminho, sha256 e bytes de cada entregavel, e a lista nao_provado.
#
#   3. Que `mostrar` aceite slug invalido. Slug com `/`, `\` ou `..` deve sair
#      com exit 2 e recusar no stderr.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIBO="$RAIZ/scripts/recibo.cjs"
FIX="$RAIZ/test/fixtures/recibo"

[ -f "$RECIBO" ] || { echo "FALHA: nao achei $RECIBO"; exit 1; }
[ -f "$FIX/recibo-exemplo.json" ] || { echo "FALHA: nao achei $FIX/recibo-exemplo.json"; exit 1; }

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT

afirma() {
  local nome="$1" cond="$2"
  if [ "$cond" = "1" ]; then echo "  ok   $nome"; ok=$((ok+1));
  else echo "  FALHA $nome"; falhou=$((falhou+1)); fi
}

rec() { (cd "$RAIZ" && RFM_ESTADO_ROOT="$S" node "$RECIBO" "$@" 2>&1); }

echo "== slug sem recibo: ausencia nao e' erro =="
SAIDA="$(rec mostrar sem-recibo)"; C=$?
afirma "T1a1. saida contem 'sem recibo gravado para'" \
  "$(printf '%s' "$SAIDA" | grep -q "sem recibo gravado para" && echo 1 || echo 0)"
afirma "T1a2. exit 0" "$([ "$C" -eq 0 ] && echo 1 || echo 0)"

echo "== recibo gravado: exibe entregaveis, sha256, bytes e nao_provado =="
mkdir -p "$S/.rainforest/colheita"
cp "$FIX/recibo-exemplo.json" "$S/.rainforest/colheita/exemplo-recibo.json"
SAIDA="$(rec mostrar exemplo)"; C=$?
afirma "T1b1. exit 0" "$([ "$C" -eq 0 ] && echo 1 || echo 0)"
afirma "T1b2. saida contem slug no titulo" \
  "$(printf '%s' "$SAIDA" | grep -q "recibo de 'exemplo'" && echo 1 || echo 0)"
afirma "T1b3. saida contem primeiro entregavel" \
  "$(printf '%s' "$SAIDA" | grep -q "docs/rainforest/planos/exemplo.md" && echo 1 || echo 0)"
afirma "T1b4. saida contem sha256 do primeiro entregavel" \
  "$(printf '%s' "$SAIDA" | grep -q "sha256 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" && echo 1 || echo 0)"
afirma "T1b5. saida contem bytes do primeiro entregavel" \
  "$(printf '%s' "$SAIDA" | grep -q "bytes  0" && echo 1 || echo 0)"
afirma "T1b6. saida contem segundo entregavel" \
  "$(printf '%s' "$SAIDA" | grep -q "scripts/exemplo.cjs" && echo 1 || echo 0)"
afirma "T1b7. saida contem primeiro item de nao_provado" \
  "$(printf '%s' "$SAIDA" | grep -q "revisao visual" && echo 1 || echo 0)"
afirma "T1b8. saida contem segundo item de nao_provado" \
  "$(printf '%s' "$SAIDA" | grep -q "comportamento em producao" && echo 1 || echo 0)"

echo "== slug invalido: exit 2 e stderr menciona slug invalido =="
SAIDA="$(rec mostrar "slug/com-barra" 2>&1)"; C=$?
afirma "T1c1. exit 2 para slug com barra" "$([ "$C" -eq 2 ] && echo 1 || echo 0)"
afirma "T1c2. stderr menciona 'slug invalido'" \
  "$(printf '%s' "$SAIDA" | grep -q "slug invalido" && echo 1 || echo 0)"

SAIDA="$(rec mostrar "slug\\com-contrabarra" 2>&1)"; C=$?
afirma "T1c3. exit 2 para slug com contrabarra" "$([ "$C" -eq 2 ] && echo 1 || echo 0)"

SAIDA="$(rec mostrar "slug/../travessia" 2>&1)"; C=$?
afirma "T1c4. exit 2 para slug com .." "$([ "$C" -eq 2 ] && echo 1 || echo 0)"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
