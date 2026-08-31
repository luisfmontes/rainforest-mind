#!/bin/bash
# Bateria do hooks/lib/poda-dados.cjs — resolução de raiz e caminhos.
#
# O que prova:
#   1. raizPoda() reusa a cadeia de resolverRaiz() corretamente.
#   2. Todas as funções de caminho devolvem valores corretos (sem criar pasta).
#   3. portaPadrao() respeita RFM_PODA_PORTA e valida a faixa numérica.
#   4. Valores fora da faixa caem no padrão com aviso.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
SBP="$(mktemp -d)"
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
trap 'rm -rf "$SBP"' EXIT

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi; }

echo "(caixa de areia: $SB)"

echo
echo "== 1. raizPoda() resolve a raiz da poda via cadeia =="
# Com RFM_ROOT apontando pra pasta com FOCO.md, raizPoda devolve <raiz>/poda
RAIZ_FIXTURE="$SBP/raiz-fixture"
mkdir -p "$RAIZ_FIXTURE"
echo "# Foco" > "$RAIZ_FIXTURE/FOCO.md"

RAIZ=$(RFM_ROOT="$SB/raiz-fixture" node -e "
  const path = require('path');
  const { raizPoda } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  const r = raizPoda({ env: { RFM_ROOT: process.env.RFM_ROOT } });
  // Normaliza barras pra comparação
  process.stdout.write((r || 'null').split('\\\\').join('/'));
" 2>&1)
ESPERADO="$SB/raiz-fixture/poda"
ESPERADO_NORM="${ESPERADO//\\/\/}"
igual "raizPoda com RFM_ROOT válido" "$ESPERADO_NORM" "$RAIZ"

# Sem marcador e sem RFM_ROOT, devolve null
RAIZ_NULL=$(node -e "
  const path = require('path');
  const { raizPoda } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  const r = raizPoda({ env: {}, cwd: '$SBP/inexistente' });
  process.stdout.write(r || 'null');
" 2>&1)
igual "raizPoda sem marcador e sem RFM_ROOT" "null" "$RAIZ_NULL"

echo
echo "== 2. caminhoMetricas(), caminhoContexto(), caminhoPid() retornam caminhos corretos =="
METRICAS=$(RFM_ROOT="$SB/raiz-fixture" node -e "
  const { caminhoMetricas } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  const c = caminhoMetricas({ env: { RFM_ROOT: process.env.RFM_ROOT } });
  process.stdout.write((c || 'null').split('\\\\').join('/'));
" 2>&1)
METRICAS_ESP="$SB/raiz-fixture/poda/metricas.jsonl"
METRICAS_NORM="${METRICAS_ESP//\\/\/}"
igual "caminhoMetricas" "$METRICAS_NORM" "$METRICAS"

CONTEXTO=$(RFM_ROOT="$SB/raiz-fixture" node -e "
  const { caminhoContexto } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  const c = caminhoContexto({ env: { RFM_ROOT: process.env.RFM_ROOT } });
  process.stdout.write((c || 'null').split('\\\\').join('/'));
" 2>&1)
CONTEXTO_ESP="$SB/raiz-fixture/poda/contexto.json"
CONTEXTO_NORM="${CONTEXTO_ESP//\\/\/}"
igual "caminhoContexto" "$CONTEXTO_NORM" "$CONTEXTO"

PID=$(RFM_ROOT="$SB/raiz-fixture" node -e "
  const { caminhoPid } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  const c = caminhoPid({ env: { RFM_ROOT: process.env.RFM_ROOT } });
  process.stdout.write((c || 'null').split('\\\\').join('/'));
" 2>&1)
PID_ESP="$SB/raiz-fixture/poda/poda.pid"
PID_NORM="${PID_ESP//\\/\/}"
igual "caminhoPid" "$PID_NORM" "$PID"

echo
echo "== 3. Nenhuma função cria a pasta =="
[ ! -d "$SB/raiz-fixture/poda" ] && ok=$((ok+1)); echo "  ok   pasta poda não foi criada" || \
  { falhou=$((falhou+1)); echo "  FALHA pasta poda foi criada por raizPoda()"; }

echo
echo "== 4. portaPadrao() respeita padrão e env var =="
PORTA_PADRAO=$(node -e "
  const { portaPadrao } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  process.stdout.write(String(portaPadrao({ env: {} })));
" 2>&1)
igual "portaPadrao sem env var" "4141" "$PORTA_PADRAO"

PORTA_OVERRIDE=$(node -e "
  const { portaPadrao } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  process.stdout.write(String(portaPadrao({ env: { RFM_PODA_PORTA: '5555' } })));
" 2>&1)
igual "portaPadrao com RFM_PODA_PORTA válida" "5555" "$PORTA_OVERRIDE"

echo
echo "== 5. Valores inválidos caem no padrão com aviso =="
PORTA_INVALIDA=$(RFM_PODA_PORTA="99999" node -e "
  const { portaPadrao } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  process.stdout.write(String(portaPadrao({ env: process.env })));
" 2>&1)
AVISO_PRESENTE=$(echo "$PORTA_INVALIDA" | grep -c "aviso" || echo 0)
if [ "$AVISO_PRESENTE" -gt 0 ] && [ "$(echo "$PORTA_INVALIDA" | tail -1)" = "4141" ]; then
  ok=$((ok+1)); echo "  ok   porta > 65535 cai no padrão com aviso"
else
  falhou=$((falhou+1)); echo "  FALHA porta inválida: esperava aviso + 4141, veio: $PORTA_INVALIDA"
fi

PORTA_NAO_NUM=$(RFM_PODA_PORTA="abc" node -e "
  const { portaPadrao } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  process.stdout.write(String(portaPadrao({ env: process.env })));
" 2>&1)
if [ "$(echo "$PORTA_NAO_NUM" | tail -1)" = "4141" ]; then
  ok=$((ok+1)); echo "  ok   porta não-numérica cai no padrão"
else
  falhou=$((falhou+1)); echo "  FALHA porta não-numérica: esperava 4141, veio $(echo "$PORTA_NAO_NUM" | tail -1)"
fi

PORTA_ZERO=$(RFM_PODA_PORTA="0" node -e "
  const { portaPadrao } = require('$SRC_WIN/hooks/lib/poda-dados.cjs');
  process.stdout.write(String(portaPadrao({ env: process.env })));
" 2>&1)
if [ "$(echo "$PORTA_ZERO" | tail -1)" = "4141" ]; then
  ok=$((ok+1)); echo "  ok   porta 0 cai no padrão"
else
  falhou=$((falhou+1)); echo "  FALHA porta 0: esperava 4141, veio $(echo "$PORTA_ZERO" | tail -1)"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
