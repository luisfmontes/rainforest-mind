#!/bin/bash
# Teste da guarda D2 do hook de SessionEnd (hooks/titulo-sessao-end.cjs):
# "só daqui pra frente; nada de retro-marcar". A guarda é a "catraca" que
# barra qualquer sessão cujo session_id não tenha entrada (com fluxos) no
# ledger `fluxos-sessao.json` — o hook tem de sair sem escrever UMA linha
# sequer no transcript. Uso: bash hooks/testa-titulo-sessao-sem-carimbo.sh
#
# Companheiro de hooks/testa-titulo-sessao-end.sh: aquele testa o que o hook
# ESCREVE quando tem carimbo; este testa que ele NÃO escreve nada quando não
# tem. Reusa a mesma forma de fixture (transcript JSONL real, payload de 6
# chaves medido em 2026-09-15) e o mesmo esqueleto de bateria.
#
# O payload de stdin usa as 6 chaves medidas em sessão real em 2026-09-15
# (design: docs/rainforest/design/2026-09-15-titulo-de-sessao-encerrada.md):
# cwd, hook_event_name, prompt_id, reason, session_id, transcript_path.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_JS="$SRC/hooks/titulo-sessao-end.cjs"

BASE_POSIX="$(mktemp -d)"
trap 'rm -rf "$BASE_POSIX"' EXIT
echo "(caixa de areia: $BASE_POSIX)"

ok=0; falhou=0

aformato() {
  cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
}

# Escreve um transcript-fixture com a forma de um transcript real: turnos de
# user/assistant e, opcionalmente, uma linha de título no fim (ai-title ou
# custom-title, já serializada por quem chama).
# $1 = caminho de saida, $2 = linha de titulo (ou vazio para nenhuma)
escreverTranscript() {
  local out="$1" linha_titulo="$2"
  {
    echo '{"parentUuid":null,"isSidechain":false,"promptId":"22222222-2222-2222-2222-222222222222","type":"user","message":{"role":"user","content":"oi, tudo bem?"}}'
    echo '{"parentUuid":"22222222-2222-2222-2222-222222222222","isSidechain":false,"message":{"model":"claude-sonnet-5","id":"msg_teste","type":"message","role":"assistant","content":[{"type":"text","text":"tudo certo, e voce?"}]},"type":"assistant","timestamp":"2026-09-15T10:00:01.000Z"}'
    if [ -n "$linha_titulo" ]; then
      echo "$linha_titulo"
    fi
  } > "$out"
}

# Escreve fluxos-sessao.json com uma lista de fluxos ja pronta em JSON, para
# UM session_id (que pode ser diferente do session_id que o hook vai receber
# — é assim que simulamos "ledger existe, mas sem entrada para esta sessão").
# $1 = raiz posix, $2 = session_id da entrada, $3 = JSON do array de fluxos
escreverLedger() {
  local raiz="$1" sessao="$2" fluxos_json="$3"
  local ts; ts=$(date +%s000)
  printf '{"%s": {"ts": %s, "fluxos": %s}}' "$sessao" "$ts" "$fluxos_json" > "$raiz/fluxos-sessao.json"
}

# Monta o payload de 6 chaves e roda o hook. Devolve via variaveis globais
# OUT_STDOUT / OUT_STDERR / OUT_EXIT.
# $1 = raiz posix (RFM_ROOT), $2 = reason, $3 = session_id, $4 = transcript (formato node)
rodarHook() {
  local raiz="$1" reason="$2" sessao="$3" transcript="$4"
  local payload
  payload=$(printf '{"cwd":"C:/proj","hook_event_name":"SessionEnd","prompt_id":"p1","reason":"%s","session_id":"%s","transcript_path":"%s"}' \
    "$reason" "$sessao" "$transcript")
  local raiz_fmt; raiz_fmt="$(aformato "$raiz")"
  OUT_STDOUT=$(printf '%s' "$payload" | RFM_ROOT="$raiz_fmt" node "$HOOK_JS" 2> "$BASE_POSIX/stderr.tmp")
  OUT_EXIT=$?
  OUT_STDERR=$(cat "$BASE_POSIX/stderr.tmp")
}

ultimaLinhaCampo() {
  # $1 = caminho do transcript, imprime "tipo customTitle" da ultima linha
  tail -1 "$1" | node -e "const o=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(o.type, o.customTitle)" 2>&1
}

conferirIgual() {
  # $1 = rótulo, $2 = caminho do transcript, $3 = sha antes
  local rotulo="$1" trans="$2" sha_antes="$3"
  local sha_depois; sha_depois=$(sha256sum "$trans" | awk '{print $1}')
  echo "sha256 antes=$sha_antes depois=$sha_depois"
  if [ "$sha_antes" = "$sha_depois" ]; then
    ok=$((ok+1)); echo "  ok    $rotulo: transcript byte-a-byte identico"
  else
    falhou=$((falhou+1)); echo "  FALHA $rotulo: transcript MUDOU (guarda nao segurou)"
  fi
}

conferirExitESilencio() {
  # $1 = rótulo
  local rotulo="$1"
  if [ "$OUT_EXIT" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok    $rotulo: exit 0"
  else
    falhou=$((falhou+1)); echo "  FALHA $rotulo: exit $OUT_EXIT (esperado 0)"
  fi
  if [ -z "$OUT_STDOUT" ] && [ -z "$OUT_STDERR" ]; then
    ok=$((ok+1)); echo "  ok    $rotulo: stdout e stderr vazios"
  else
    falhou=$((falhou+1)); echo "  FALHA $rotulo: stdout ou stderr nao vazio: stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
  fi
}

echo
echo "=========================================="
echo "TESTE 1: session_id ausente do ledger (catraca) -> transcript intacto"
echo "=========================================="
T1_POSIX="$BASE_POSIX/t1"; mkdir -p "$T1_POSIX"
SESSAO_CATRACA="sessao-fora-da-catraca"
SESSAO_OUTRA="sessao-que-esta-no-ledger"
TRANS1="$T1_POSIX/transcript.jsonl"
escreverTranscript "$TRANS1" '{"type":"ai-title","aiTitle":"Confirmação simples","sessionId":"sessao-fora-da-catraca"}'
# Ledger existe e tem conteúdo, mas para OUTRA sessão — não para a que o hook recebe.
escreverLedger "$T1_POSIX" "$SESSAO_OUTRA" '[{"slug":"fluxo-outro","estagio":"design","aberto":"design","ts":1}]'

SHA1_ANTES=$(sha256sum "$TRANS1" | awk '{print $1}')
TRANS1_FMT="$(aformato "$TRANS1")"
rodarHook "$T1_POSIX" "prompt_input_exit" "$SESSAO_CATRACA" "$TRANS1_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
conferirIgual "caso 1" "$TRANS1" "$SHA1_ANTES"
conferirExitESilencio "caso 1"

echo
echo "=========================================="
echo "TESTE 2: session_id ausente do ledger, transcript ja tem custom-title de /rename -> intacto"
echo "=========================================="
T2_POSIX="$BASE_POSIX/t2"; mkdir -p "$T2_POSIX"
SESSAO2="sessao-fora-da-catraca-2"
SESSAO2_OUTRA="sessao-que-esta-no-ledger-2"
TRANS2="$T2_POSIX/transcript.jsonl"
escreverTranscript "$TRANS2" '{"type":"custom-title","customTitle":"Meu nome a dedo","sessionId":"sessao-fora-da-catraca-2"}'
escreverLedger "$T2_POSIX" "$SESSAO2_OUTRA" '[{"slug":"fluxo-outro-2","estagio":"design","aberto":"design","ts":1}]'

SHA2_ANTES=$(sha256sum "$TRANS2" | awk '{print $1}')
TRANS2_FMT="$(aformato "$TRANS2")"
rodarHook "$T2_POSIX" "prompt_input_exit" "$SESSAO2" "$TRANS2_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
conferirIgual "caso 2" "$TRANS2" "$SHA2_ANTES"
conferirExitESilencio "caso 2"
RES2=$(ultimaLinhaCampo "$TRANS2")
echo "ultima linha: $RES2"
if [ "$RES2" = "custom-title Meu nome a dedo" ]; then
  ok=$((ok+1)); echo "  ok    caso 2: custom-title de /rename continua sendo a ultima linha, intacto"
else
  falhou=$((falhou+1)); echo "  FALHA caso 2: esperava 'custom-title Meu nome a dedo', veio '$RES2'"
fi

echo
echo "=========================================="
echo "TESTE 3: fluxos-sessao.json nao existe -> transcript intacto"
echo "=========================================="
T3_POSIX="$BASE_POSIX/t3"; mkdir -p "$T3_POSIX"
SESSAO3="sessao-sem-ledger-nenhum"
TRANS3="$T3_POSIX/transcript.jsonl"
escreverTranscript "$TRANS3" '{"type":"ai-title","aiTitle":"Confirmação simples","sessionId":"sessao-sem-ledger-nenhum"}'
# NÃO chama escreverLedger — o arquivo fluxos-sessao.json não existe nesta raiz.

SHA3_ANTES=$(sha256sum "$TRANS3" | awk '{print $1}')
TRANS3_FMT="$(aformato "$TRANS3")"
rodarHook "$T3_POSIX" "prompt_input_exit" "$SESSAO3" "$TRANS3_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
conferirIgual "caso 3" "$TRANS3" "$SHA3_ANTES"
conferirExitESilencio "caso 3"

echo
echo "=========================================="
echo "TESTE 4: chave da sessao existe no ledger, mas fluxos e lista vazia -> transcript intacto"
echo "=========================================="
T4_POSIX="$BASE_POSIX/t4"; mkdir -p "$T4_POSIX"
SESSAO4="sessao-fluxos-vazios"
TRANS4="$T4_POSIX/transcript.jsonl"
escreverTranscript "$TRANS4" '{"type":"ai-title","aiTitle":"Confirmação simples","sessionId":"sessao-fluxos-vazios"}'
escreverLedger "$T4_POSIX" "$SESSAO4" '[]'

SHA4_ANTES=$(sha256sum "$TRANS4" | awk '{print $1}')
TRANS4_FMT="$(aformato "$TRANS4")"
rodarHook "$T4_POSIX" "prompt_input_exit" "$SESSAO4" "$TRANS4_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
conferirIgual "caso 4" "$TRANS4" "$SHA4_ANTES"
conferirExitESilencio "caso 4"

echo
echo "=========================================="
echo "TESTE 5 (contraprova): chave da sessao presente com fluxo aberto -> transcript MUDA"
echo "=========================================="
T5_POSIX="$BASE_POSIX/t5"; mkdir -p "$T5_POSIX"
SESSAO5="sessao-dentro-da-catraca"
TRANS5="$T5_POSIX/transcript.jsonl"
escreverTranscript "$TRANS5" '{"type":"ai-title","aiTitle":"Confirmação simples","sessionId":"sessao-dentro-da-catraca"}'
escreverLedger "$T5_POSIX" "$SESSAO5" '[{"slug":"fluxo-cinco","estagio":"design","aberto":"design","ts":1}]'

SHA5_ANTES=$(sha256sum "$TRANS5" | awk '{print $1}')
TRANS5_FMT="$(aformato "$TRANS5")"
rodarHook "$T5_POSIX" "prompt_input_exit" "$SESSAO5" "$TRANS5_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
SHA5_DEPOIS=$(sha256sum "$TRANS5" | awk '{print $1}')
echo "sha256 antes=$SHA5_ANTES depois=$SHA5_DEPOIS"
if [ "$SHA5_ANTES" != "$SHA5_DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok    caso 5: transcript MUDOU (contraprova — hook escreve quando ha carimbo)"
else
  falhou=$((falhou+1)); echo "  FALHA caso 5: transcript ficou igual (contraprova falhou — bateria nao pegaria hook morto)"
fi
RES5=$(ultimaLinhaCampo "$TRANS5")
echo "ultima linha: $RES5"
if [ "$RES5" = "custom-title [aberto: design] Confirmação simples" ]; then
  ok=$((ok+1)); echo "  ok    caso 5: ultima linha e o custom-title esperado"
else
  falhou=$((falhou+1)); echo "  FALHA caso 5: esperava 'custom-title [aberto: design] Confirmação simples', veio '$RES5'"
fi

echo
echo "=========================================="
echo "Resumo: $ok ok, $falhou falhas"
echo "=========================================="
[ $falhou -eq 0 ]
