#!/bin/bash
# Teste do ledger local de fluxos por sessão (hooks/lib/ledger-fluxos.cjs),
# carimbado pelos verbos de scripts/estado.cjs (iniciar/exigir/marcar).
# Uso: bash hooks/testa-ledger-fluxos.sh
#
# Duas raízes diferentes entram em jogo, e os testes isolam as duas:
#   RFM_ESTADO_ROOT -> onde mora docs/rainforest/estado/<slug>.json (estado.cjs)
#   RFM_ROOT         -> onde mora fluxos-sessao.json, via resolverRaiz (a MESMA
#                        cadeia que hooks/heartbeat.cjs usa para sessoes.json)
# RFM_ROOT vence a cadeia de resolverRaiz mesmo sem marcador (FOCO.md /
# ideias.jsonl) — ver hooks/lib/raiz.cjs, nível 1 — então basta apontá-lo para
# a sandbox para isolar o ledger por completo, independente do que exista no
# projeto real ou no HOME de quem roda o teste.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESTADO_JS="$SRC/scripts/estado.cjs"

BASE_POSIX="$(mktemp -d)"
trap 'rm -rf "$BASE_POSIX"' EXIT
echo "(caixa de areia: $BASE_POSIX)"

ok=0; falhou=0

# Devolve o caminho no formato que o node no Windows aceita (drive letter),
# igual a testa-heartbeat-poda.sh.
aformato() {
  cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
}

lerCampos() {
  # $1 = caminho do fluxos-sessao.json, $2 = session_id
  node -e '
    const fs = require("fs");
    const l = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const e = l[process.argv[2]];
    const f = (e && e.fluxos) || [];
    console.log(f.length, f[0] && f[0].slug, f[0] && f[0].estagio);
  ' "$1" "$2" 2>&1
}

lerAberto() {
  # $1 = caminho do fluxos-sessao.json, $2 = session_id
  node -e '
    const fs = require("fs");
    const l = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const e = l[process.argv[2]];
    const f = (e && e.fluxos) || [];
    console.log(JSON.stringify(f[0] && f[0].aberto));
  ' "$1" "$2" 2>&1
}

echo
echo "=========================================="
echo "TESTE 1: iniciar carimba slug e estagio sob o CLAUDE_SESSION_ID do ambiente"
echo "=========================================="
T1_POSIX="$BASE_POSIX/t1"; mkdir -p "$T1_POSIX"
T1="$(aformato "$T1_POSIX")"
SESSAO1="11111111-1111-1111-1111-111111111111"

OUT1=$(RFM_ESTADO_ROOT="$T1" RFM_ROOT="$T1" CLAUDE_SESSION_ID="$SESSAO1" \
  node "$ESTADO_JS" iniciar --slug teste-carimbo --titulo "t" 2>&1)
EXIT1=$?
echo "$OUT1"
echo "(exit=$EXIT1)"

if [ "$EXIT1" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar saiu 0"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar saiu $EXIT1 (esperado 0)"
fi

LEDGER1="$T1_POSIX/fluxos-sessao.json"
if [ -f "$LEDGER1" ]; then
  RES1=$(lerCampos "$LEDGER1" "$SESSAO1")
  echo "ledger: $RES1"
  if [ "$RES1" = "1 teste-carimbo design" ]; then
    ok=$((ok+1)); echo "  ok    ledger carimbou {slug:teste-carimbo, estagio:design}"
  else
    falhou=$((falhou+1)); echo "  FALHA ledger inesperado: '$RES1' (esperado '1 teste-carimbo design')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json nao foi criado em $LEDGER1"
fi

echo
echo "=========================================="
echo "TESTE 2: sem CLAUDE_SESSION_ID, nada e gravado e o verbo ainda sai 0"
echo "=========================================="
T2_POSIX="$BASE_POSIX/t2"; mkdir -p "$T2_POSIX"
T2="$(aformato "$T2_POSIX")"

OUT2=$(RFM_ESTADO_ROOT="$T2" RFM_ROOT="$T2" \
  env -u CLAUDE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-sem-sessao --titulo "t" 2>&1)
EXIT2=$?
echo "$OUT2"
echo "(exit=$EXIT2)"

if [ "$EXIT2" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar saiu 0 mesmo sem CLAUDE_SESSION_ID"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar saiu $EXIT2 (esperado 0)"
fi

LEDGER2="$T2_POSIX/fluxos-sessao.json"
if [ ! -f "$LEDGER2" ]; then
  ok=$((ok+1)); echo "  ok    fluxos-sessao.json nao foi criado (sem sessao, sem gravacao)"
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json foi criado sem CLAUDE_SESSION_ID: $(cat "$LEDGER2")"
fi

echo
echo "=========================================="
echo "TESTE 3: exigir --estagio plano depois do iniciar atualiza a MESMA entrada"
echo "=========================================="
T3_POSIX="$BASE_POSIX/t3"; mkdir -p "$T3_POSIX"
T3="$(aformato "$T3_POSIX")"
SESSAO3="33333333-3333-3333-3333-333333333333"

RFM_ESTADO_ROOT="$T3" RFM_ROOT="$T3" CLAUDE_SESSION_ID="$SESSAO3" \
  node "$ESTADO_JS" iniciar --slug teste-atualiza --titulo "t" > /dev/null 2>&1

# Fecha 'design' (pré-requisito de 'plano') para o 'exigir' seguinte passar.
OUT_MARCAR=$(RFM_ESTADO_ROOT="$T3" RFM_ROOT="$T3" CLAUDE_SESSION_ID="$SESSAO3" \
  node "$ESTADO_JS" marcar --slug teste-atualiza --estagio design --status aprovado 2>&1)
EXIT_MARCAR=$?

OUT3=$(RFM_ESTADO_ROOT="$T3" RFM_ROOT="$T3" CLAUDE_SESSION_ID="$SESSAO3" \
  node "$ESTADO_JS" exigir --slug teste-atualiza --estagio plano 2>&1)
EXIT3=$?
echo "marcar design aprovado: $OUT_MARCAR (exit=$EXIT_MARCAR)"
echo "exigir plano: $OUT3 (exit=$EXIT3)"

if [ "$EXIT_MARCAR" -eq 0 ] && [ "$EXIT3" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    marcar design + exigir plano saem 0 (pre-condicao do caso)"
else
  falhou=$((falhou+1)); echo "  FALHA marcar (exit=$EXIT_MARCAR) ou exigir (exit=$EXIT3) nao saiu 0"
fi

LEDGER3="$T3_POSIX/fluxos-sessao.json"
if [ -f "$LEDGER3" ]; then
  RES3=$(lerCampos "$LEDGER3" "$SESSAO3")
  echo "ledger: $RES3"
  if [ "$RES3" = "1 teste-atualiza plano" ]; then
    ok=$((ok+1)); echo "  ok    exigir atualizou a MESMA entrada (1 item, estagio=plano)"
  else
    falhou=$((falhou+1)); echo "  FALHA ledger inesperado: '$RES3' (esperado '1 teste-atualiza plano')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json nao existe em $LEDGER3"
fi

echo
echo "=========================================="
echo "TESTE 4: entrada de sessao com ts de 25h atras e podada na escrita seguinte"
echo "=========================================="
T4_POSIX="$BASE_POSIX/t4"; mkdir -p "$T4_POSIX"
T4="$(aformato "$T4_POSIX")"

AGORA_MS=$(date +%s000)
VELHO_MS=$(( $(date +%s) * 1000 - 25 * 3600 * 1000 ))

cat > "$T4_POSIX/fluxos-sessao.json" << EOF
{
  "sessao-velha":   { "ts": $VELHO_MS, "fluxos": [ { "slug": "antigo", "estagio": "design", "ts": $VELHO_MS } ] },
  "sessao-recente": { "ts": $AGORA_MS, "fluxos": [ { "slug": "novo",   "estagio": "design", "ts": $AGORA_MS } ] }
}
EOF

echo "ANTES:"
cat "$T4_POSIX/fluxos-sessao.json"

OUT4=$(RFM_ESTADO_ROOT="$T4" RFM_ROOT="$T4" CLAUDE_SESSION_ID="sessao-gatilho" \
  node "$ESTADO_JS" iniciar --slug teste-poda --titulo "t" 2>&1)
EXIT4=$?
echo "iniciar (gatilho da poda): exit=$EXIT4"

RESULTADO4="$(cat "$T4_POSIX/fluxos-sessao.json")"
echo "DEPOIS:"
echo "$RESULTADO4"

if [ "$EXIT4" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar (gatilho) saiu 0"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar (gatilho) saiu $EXIT4"
fi

if ! echo "$RESULTADO4" | grep -q '"sessao-velha"'; then
  ok=$((ok+1)); echo "  ok    sessao-velha (25h) foi podada"
else
  falhou=$((falhou+1)); echo "  FALHA sessao-velha sobreviveu a poda"
fi

if echo "$RESULTADO4" | grep -q '"sessao-recente"'; then
  ok=$((ok+1)); echo "  ok    sessao-recente sobreviveu a poda"
else
  falhou=$((falhou+1)); echo "  FALHA sessao-recente foi podada por engano"
fi

if echo "$RESULTADO4" | grep -q '"sessao-gatilho"'; then
  ok=$((ok+1)); echo "  ok    sessao-gatilho foi gravada"
else
  falhou=$((falhou+1)); echo "  FALHA sessao-gatilho nao foi gravada"
fi

echo
echo "=========================================="
echo "TESTE 5: ledger com JSON corrompido nao derruba o verbo"
echo "=========================================="
T5_POSIX="$BASE_POSIX/t5"; mkdir -p "$T5_POSIX"
T5="$(aformato "$T5_POSIX")"

printf '{ isso nao e json valido' > "$T5_POSIX/fluxos-sessao.json"
echo "ANTES (corrompido): $(cat "$T5_POSIX/fluxos-sessao.json")"

OUT5=$(RFM_ESTADO_ROOT="$T5" RFM_ROOT="$T5" CLAUDE_SESSION_ID="sessao-corrompida" \
  node "$ESTADO_JS" iniciar --slug teste-corrompido --titulo "t" 2>&1)
EXIT5=$?
echo "$OUT5"
echo "(exit=$EXIT5)"

if [ "$EXIT5" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar sai 0 mesmo com ledger corrompido"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar saiu $EXIT5 (esperado 0) com ledger corrompido"
fi

LEDGER5="$T5_POSIX/fluxos-sessao.json"
RES5=$(lerCampos "$LEDGER5" "sessao-corrompida" 2>&1)
echo "ledger apos recuperacao: $RES5"
if [ "$RES5" = "1 teste-corrompido design" ]; then
  ok=$((ok+1)); echo "  ok    ledger se recuperou do JSON corrompido e carimbou a sessao atual"
else
  falhou=$((falhou+1)); echo "  FALHA ledger nao se recuperou: '$RES5'"
fi

echo
echo "=========================================="
echo "TESTE 6: campo 'aberto' distingue fluxo aberto de fluxo completo (Parte A)"
echo "=========================================="
T6_POSIX="$BASE_POSIX/t6"; mkdir -p "$T6_POSIX"
T6="$(aformato "$T6_POSIX")"
SESSAO6="66666666-6666-6666-6666-666666666666"
E6="RFM_ESTADO_ROOT=$T6 RFM_ROOT=$T6 CLAUDE_SESSION_ID=$SESSAO6"

# Percorre o fluxo inteiro ate 'exigir --estagio fechar' (fluxo ainda ABERTO
# nele mesmo), depois fecha com 'marcar --estagio fechar --status ok' (fluxo
# COMPLETO) — mesma sequencia de scripts/testa-estado.sh, secao 2.
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  node "$ESTADO_JS" iniciar --slug teste-aberto --titulo "t" > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  node "$ESTADO_JS" marcar --slug teste-aberto --estagio design --status aprovado > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  node "$ESTADO_JS" marcar --slug teste-aberto --estagio plano --status ok > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  node "$ESTADO_JS" exigir --slug teste-aberto --estagio executar > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  node "$ESTADO_JS" marcar --slug teste-aberto --estagio executar --status ok \
  --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso-teste-1"}]}' > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  node "$ESTADO_JS" marcar --slug teste-aberto --estagio revisar --status ok > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  node "$ESTADO_JS" marcar --slug teste-aberto --estagio verificar --status ok \
  --json '{"comando":"bash test.sh","saida":"3 cases passed"}' > /dev/null 2>&1

OUT6A=$(RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  node "$ESTADO_JS" exigir --slug teste-aberto --estagio fechar 2>&1)
EXIT6A=$?
echo "exigir fechar: $OUT6A (exit=$EXIT6A)"

LEDGER6="$T6_POSIX/fluxos-sessao.json"
if [ "$EXIT6A" -eq 0 ] && [ -f "$LEDGER6" ]; then
  ABERTO6A=$(lerAberto "$LEDGER6" "$SESSAO6")
  echo "ledger apos 'exigir fechar': aberto=$ABERTO6A"
  if [ "$ABERTO6A" = '"fechar"' ]; then
    ok=$((ok+1)); echo "  ok    exigir --estagio fechar grava aberto: \"fechar\" (fluxo ainda aberto)"
  else
    falhou=$((falhou+1)); echo "  FALHA aberto inesperado apos exigir: '$ABERTO6A' (esperado '\"fechar\"')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA exigir --estagio fechar nao saiu 0 ou ledger ausente"
fi

OUT6B=$(RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  node "$ESTADO_JS" marcar --slug teste-aberto --estagio fechar --status ok 2>&1)
EXIT6B=$?
echo "marcar fechar ok: $OUT6B (exit=$EXIT6B)"

if [ "$EXIT6B" -eq 0 ] && [ -f "$LEDGER6" ]; then
  ABERTO6B=$(lerAberto "$LEDGER6" "$SESSAO6")
  echo "ledger apos 'marcar fechar ok': aberto=$ABERTO6B"
  if [ "$ABERTO6B" = 'null' ]; then
    ok=$((ok+1)); echo "  ok    marcar --estagio fechar --status ok grava aberto: null (fluxo completo)"
  else
    falhou=$((falhou+1)); echo "  FALHA aberto inesperado apos marcar ok: '$ABERTO6B' (esperado 'null')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA marcar --estagio fechar --status ok nao saiu 0 ou ledger ausente"
fi

echo
echo "=========================================="
echo "Resumo: $ok ok, $falhou falhas"
echo "=========================================="
[ $falhou -eq 0 ]
