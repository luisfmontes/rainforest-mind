#!/bin/bash
# Teste do hook de SessionEnd que marca o título da sessão com o estado do
# fluxo (hooks/titulo-sessao-end.cjs). Uso: bash hooks/testa-titulo-sessao-end.sh
#
# O fixture de transcript imita a FORMA de um transcript real do Claude Code:
# linhas JSONL com "type":"user"/"assistant" de verdade, mais as linhas de
# título que o CC também grava ("ai-title" automático, "custom-title" quando
# o usuário roda /rename). Schema inventado é o defeito registrado em
# 2026-08-19 na skill `plano` — por isso nenhum campo aqui é chute.
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
# user/assistant e, opcionalmente, uma linha de título no fim.
# $1 = caminho de saida, $2 = linha de titulo (ou vazio para nenhuma)
escreverTranscript() {
  local out="$1" linha_titulo="$2"
  {
    echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"oi, tudo bem?"}]},"timestamp":"2026-09-15T10:00:00.000Z"}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"tudo certo, e voce?"}]},"timestamp":"2026-09-15T10:00:01.000Z"}'
    if [ -n "$linha_titulo" ]; then
      echo "$linha_titulo"
    fi
  } > "$out"
}

# Escreve fluxos-sessao.json com uma lista de fluxos ja pronta em JSON.
# $1 = raiz posix, $2 = session_id, $3 = JSON do array de fluxos
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

echo
echo "=========================================="
echo "TESTE 1: reason=prompt_input_exit, ledger com fluxo aberto=design, transcript com ai-title"
echo "=========================================="
T1_POSIX="$BASE_POSIX/t1"; mkdir -p "$T1_POSIX"
SESSAO1="sessao-teste-01"
TRANS1="$T1_POSIX/transcript.jsonl"
escreverTranscript "$TRANS1" '{"type":"ai-title","aiTitle":"Confirmação simples","sessionId":"sessao-teste-01"}'
escreverLedger "$T1_POSIX" "$SESSAO1" '[{"slug":"fluxo-um","estagio":"design","aberto":"design","ts":1}]'

TRANS1_FMT="$(aformato "$TRANS1")"
rodarHook "$T1_POSIX" "prompt_input_exit" "$SESSAO1" "$TRANS1_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
RES1=$(ultimaLinhaCampo "$TRANS1")
echo "ultima linha: $RES1"
if [ "$RES1" = "custom-title [aberto: design] Confirmação simples" ]; then
  ok=$((ok+1)); echo "  ok    escreveu [aberto: design] prefixando o ai-title"
else
  falhou=$((falhou+1)); echo "  FALHA esperava 'custom-title [aberto: design] Confirmação simples', veio '$RES1'"
fi

echo
echo "=========================================="
echo "TESTE 2: reason=clear nao escreve nada no transcript"
echo "=========================================="
T2_POSIX="$BASE_POSIX/t2"; mkdir -p "$T2_POSIX"
SESSAO2="sessao-teste-02"
TRANS2="$T2_POSIX/transcript.jsonl"
escreverTranscript "$TRANS2" '{"type":"ai-title","aiTitle":"Confirmação simples","sessionId":"sessao-teste-02"}'
escreverLedger "$T2_POSIX" "$SESSAO2" '[{"slug":"fluxo-dois","estagio":"design","aberto":"design","ts":1}]'

SHA_ANTES=$(sha256sum "$TRANS2" | awk '{print $1}')
TRANS2_FMT="$(aformato "$TRANS2")"
rodarHook "$T2_POSIX" "clear" "$SESSAO2" "$TRANS2_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
SHA_DEPOIS=$(sha256sum "$TRANS2" | awk '{print $1}')
echo "sha256 antes=$SHA_ANTES depois=$SHA_DEPOIS"

if [ "$OUT_EXIT" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    hook sai 0 com reason=clear"
else
  falhou=$((falhou+1)); echo "  FALHA hook saiu $OUT_EXIT (esperado 0)"
fi
if [ "$SHA_ANTES" = "$SHA_DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok    transcript byte-a-byte identico (reason=clear nao escreve)"
else
  falhou=$((falhou+1)); echo "  FALHA transcript mudou com reason=clear"
fi
if [ -z "$OUT_STDOUT" ] && [ -z "$OUT_STDERR" ]; then
  ok=$((ok+1)); echo "  ok    stdout e stderr vazios"
else
  falhou=$((falhou+1)); echo "  FALHA stdout ou stderr nao vazio: stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
fi

echo
echo "=========================================="
echo "TESTE 3: ledger com todos os fluxos aberto=null -> [ok]"
echo "=========================================="
T3_POSIX="$BASE_POSIX/t3"; mkdir -p "$T3_POSIX"
SESSAO3="sessao-teste-03"
TRANS3="$T3_POSIX/transcript.jsonl"
escreverTranscript "$TRANS3" '{"type":"ai-title","aiTitle":"Confirmação simples","sessionId":"sessao-teste-03"}'
escreverLedger "$T3_POSIX" "$SESSAO3" '[{"slug":"fluxo-tres","estagio":"fechar","aberto":null,"ts":1}]'

TRANS3_FMT="$(aformato "$TRANS3")"
rodarHook "$T3_POSIX" "prompt_input_exit" "$SESSAO3" "$TRANS3_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
RES3=$(ultimaLinhaCampo "$TRANS3")
echo "ultima linha: $RES3"
if [ "$RES3" = "custom-title [ok] Confirmação simples" ]; then
  ok=$((ok+1)); echo "  ok    escreveu [ok] quando todos os fluxos fecharam"
else
  falhou=$((falhou+1)); echo "  FALHA esperava 'custom-title [ok] Confirmação simples', veio '$RES3'"
fi

echo
echo "=========================================="
echo "TESTE 4: dois fluxos abertos, o menos avancado vence (verificar vs plano -> plano)"
echo "=========================================="
T4_POSIX="$BASE_POSIX/t4"; mkdir -p "$T4_POSIX"
SESSAO4="sessao-teste-04"
TRANS4="$T4_POSIX/transcript.jsonl"
escreverTranscript "$TRANS4" '{"type":"ai-title","aiTitle":"Confirmação simples","sessionId":"sessao-teste-04"}'
escreverLedger "$T4_POSIX" "$SESSAO4" '[{"slug":"fluxo-a","estagio":"verificar","aberto":"verificar","ts":1},{"slug":"fluxo-b","estagio":"plano","aberto":"plano","ts":2}]'

TRANS4_FMT="$(aformato "$TRANS4")"
rodarHook "$T4_POSIX" "prompt_input_exit" "$SESSAO4" "$TRANS4_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
RES4=$(ultimaLinhaCampo "$TRANS4")
echo "ultima linha: $RES4"
if [ "$RES4" = "custom-title [aberto: plano] Confirmação simples" ]; then
  ok=$((ok+1)); echo "  ok    'plano' (menos avancado) venceu sobre 'verificar'"
else
  falhou=$((falhou+1)); echo "  FALHA esperava 'custom-title [aberto: plano] Confirmação simples', veio '$RES4'"
fi

echo
echo "=========================================="
echo "TESTE 5: marcador antigo [ok] e trocado, sem duplicar"
echo "=========================================="
T5_POSIX="$BASE_POSIX/t5"; mkdir -p "$T5_POSIX"
SESSAO5="sessao-teste-05"
TRANS5="$T5_POSIX/transcript.jsonl"
escreverTranscript "$TRANS5" '{"type":"custom-title","customTitle":"[ok] Meu nome","sessionId":"sessao-teste-05"}'
escreverLedger "$T5_POSIX" "$SESSAO5" '[{"slug":"fluxo-cinco","estagio":"design","aberto":"design","ts":1}]'

TRANS5_FMT="$(aformato "$TRANS5")"
rodarHook "$T5_POSIX" "prompt_input_exit" "$SESSAO5" "$TRANS5_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
RES5=$(ultimaLinhaCampo "$TRANS5")
echo "ultima linha: $RES5"
if [ "$RES5" = "custom-title [aberto: design] Meu nome" ]; then
  ok=$((ok+1)); echo "  ok    marcador antigo [ok] foi trocado por [aberto: design], sem duplicar"
else
  falhou=$((falhou+1)); echo "  FALHA esperava 'custom-title [aberto: design] Meu nome', veio '$RES5'"
fi

echo
echo "=========================================="
echo "TESTE 6: /rename que comeca com [ mas nao casa a ancora fica intacto"
echo "=========================================="
T6_POSIX="$BASE_POSIX/t6"; mkdir -p "$T6_POSIX"
SESSAO6="sessao-teste-06"
TRANS6="$T6_POSIX/transcript.jsonl"
escreverTranscript "$TRANS6" '{"type":"custom-title","customTitle":"[rascunho] x","sessionId":"sessao-teste-06"}'
escreverLedger "$T6_POSIX" "$SESSAO6" '[{"slug":"fluxo-seis","estagio":"design","aberto":"design","ts":1}]'

TRANS6_FMT="$(aformato "$TRANS6")"
rodarHook "$T6_POSIX" "prompt_input_exit" "$SESSAO6" "$TRANS6_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
RES6=$(ultimaLinhaCampo "$TRANS6")
echo "ultima linha: $RES6"
if [ "$RES6" = "custom-title [aberto: design] [rascunho] x" ]; then
  ok=$((ok+1)); echo "  ok    '[rascunho] x' nao casou a ancora e ficou intacto, so prefixado"
else
  falhou=$((falhou+1)); echo "  FALHA esperava 'custom-title [aberto: design] [rascunho] x', veio '$RES6'"
fi

echo
echo "=========================================="
echo "TESTE 7: transcript sem ai-title nem custom-title -> usa o slug"
echo "=========================================="
T7_POSIX="$BASE_POSIX/t7"; mkdir -p "$T7_POSIX"
SESSAO7="sessao-teste-07"
TRANS7="$T7_POSIX/transcript.jsonl"
escreverTranscript "$TRANS7" ''
escreverLedger "$T7_POSIX" "$SESSAO7" '[{"slug":"fluxo-sete","estagio":"design","aberto":"design","ts":1}]'

TRANS7_FMT="$(aformato "$TRANS7")"
rodarHook "$T7_POSIX" "prompt_input_exit" "$SESSAO7" "$TRANS7_FMT"
echo "exit=$OUT_EXIT stdout='$OUT_STDOUT' stderr='$OUT_STDERR'"
RES7=$(ultimaLinhaCampo "$TRANS7")
echo "ultima linha: $RES7"
if [ "$RES7" = "custom-title [aberto: design] fluxo-sete" ]; then
  ok=$((ok+1)); echo "  ok    sem titulo no transcript, usou o slug do fluxo"
else
  falhou=$((falhou+1)); echo "  FALHA esperava 'custom-title [aberto: design] fluxo-sete', veio '$RES7'"
fi

echo
echo "=========================================="
echo "Resumo: $ok ok, $falhou falhas"
echo "=========================================="
[ $falhou -eq 0 ]
