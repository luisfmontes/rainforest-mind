#!/bin/bash
# Bateria para transferir-entre-contas.cjs — cópia de sessão entre contas
# Uso: bash scripts/testa-transferir-entre-contas.sh
#
# Testa transferência de transcript entre ~/.claude e ~/.claude-personal.
# Caixa de areia em mktemp -d fora do worktree, RFM_TEST=1 + RFM_HOME.

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_M="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

# Caixa de areia (fora do worktree para limpeza)
RAIZ_BASE=$(mktemp -d)
RAIZ="$RAIZ_BASE"

# Home temporária (RFM_HOME)
RFMHOME="$RAIZ/home"
mkdir -p "$RFMHOME"
RFMHOME_M="$(cygpath -m "$RFMHOME" 2>/dev/null || printf '%s' "$RFMHOME")"

# UM trap de EXIT para a bateria inteira
A_LIMPAR="$RAIZ_BASE"
limpa() {
  cd "$SRC" 2>/dev/null || cd /
  sleep 1
  local d
  for d in $A_LIMPAR; do
    rm -rf "$d" 2>/dev/null || true
  done
}
trap limpa EXIT

echo "(caixa de areia: $RAIZ)"
echo "(RFM_HOME: $RFMHOME)"
echo ""

ok=0
falhou=0

testa() {
  local nome="$1"
  local exit_esperado="$2"
  shift 2

  local saida
  saida=$("$@" 2>&1); local exit_obtido=$?

  if [ "$exit_obtido" = "$exit_esperado" ]; then
    ok=$((ok + 1))
    echo "  ok   $nome (exit $exit_obtido)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $nome: esperava exit $exit_esperado, veio $exit_obtido"
    echo "$saida" | sed 's/^/         /' | head -10
  fi
}

# ===== SETUP =====

mkdir -p "$RFMHOME/.claude/projects/test-proj"
mkdir -p "$RFMHOME/.claude-personal/projects/test-proj"

# Cria transcript de teste com primeiro cwd real
TRANSCRIPT_TRABALHO="$RFMHOME/.claude/projects/test-proj/abc-123.jsonl"
cat > "$TRANSCRIPT_TRABALHO" << 'JSONEOF'
{"type":"user","sessionId":"abc-123","cwd":"C:\\proj\\meu-proj","message":{"role":"user","content":"Primeira pergunta"}}
{"type":"assistant","sessionId":"abc-123","message":{"role":"assistant","content":"Primeira resposta"}}
{"type":"user","sessionId":"abc-123","message":{"role":"user","content":"Segunda pergunta"}}
{"type":"assistant","sessionId":"abc-123","message":{"role":"assistant","content":"Segunda resposta"}}
JSONEOF

TRANSCRIPT_PESSOAL="$RFMHOME/.claude-personal/projects/test-proj/def-456.jsonl"
cat > "$TRANSCRIPT_PESSOAL" << 'JSONEOF'
{"type":"user","sessionId":"def-456","cwd":"C:\\proj\\pessoal","message":{"role":"user","content":"Pergunta pessoal"}}
{"type":"assistant","sessionId":"def-456","message":{"role":"assistant","content":"Resposta pessoal"}}
JSONEOF

# Transcript sem cwd (para teste de erro)
TRANSCRIPT_SEM_CWD="$RFMHOME/.claude/projects/test-proj/sem-cwd-123.jsonl"
cat > "$TRANSCRIPT_SEM_CWD" << 'JSONEOF'
{"type":"user","sessionId":"sem-cwd-123","message":{"role":"user","content":"Sem cwd"}}
{"type":"assistant","sessionId":"sem-cwd-123","message":{"role":"assistant","content":"Resposta"}}
JSONEOF

# Transcript com primeiro cwd em linha não-primeira
TRANSCRIPT_PRIMEIRO_CWD_DEPOIS="$RFMHOME/.claude/projects/test-proj/cwd-depois-123.jsonl"
cat > "$TRANSCRIPT_PRIMEIRO_CWD_DEPOIS" << 'JSONEOF'
{"type":"summary","sessionId":"cwd-depois-123"}
{"type":"user","sessionId":"cwd-depois-123","cwd":"C:\\proj\\cwd-depois","message":{"role":"user","content":"Com cwd na segunda linha"}}
{"type":"assistant","sessionId":"cwd-depois-123","message":{"role":"assistant","content":"Resposta"}}
JSONEOF

# Cria pasta <id>/ com conteúdo para teste de cópia
mkdir -p "$RFMHOME/.claude/projects/test-proj/abc-123"
echo "conteudo de teste" > "$RFMHOME/.claude/projects/test-proj/abc-123/arquivo.txt"
mkdir -p "$RFMHOME/.claude/projects/test-proj/abc-123/subpasta"
echo "subconteudo" > "$RFMHOME/.claude/projects/test-proj/abc-123/subpasta/arquivo2.txt"

echo "== CASO 1: cópia trabalho→pessoal, com pasta <id>/ ==="
OUT_1="$RAIZ/out-1.txt"
ERR_1="$RAIZ/err-1.txt"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=abc-123 CLAUDE_CONFIG_DIR="" \
  node "$SRC/scripts/transferir-entre-contas.cjs" \
  > "$OUT_1" 2> "$ERR_1"
exit_1=$?

if [ "$exit_1" = "0" ] && \
   grep -F 'cd "C:\proj\meu-proj"' "$OUT_1" > /dev/null && \
   grep -F "claude-personal" "$OUT_1" > /dev/null && \
   grep -F "claude --resume abc-123" "$OUT_1" > /dev/null && \
   [ -f "$RFMHOME/.claude-personal/projects/test-proj/abc-123.jsonl" ] && \
   [ -f "$RFMHOME/.claude-personal/projects/test-proj/abc-123/arquivo.txt" ] && \
   [ -f "$RFMHOME/.claude-personal/projects/test-proj/abc-123/subpasta/arquivo2.txt" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 1: cópia trabalho→pessoal com pasta <id>/"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 1"
  echo "  exit: $exit_1"
  [ -f "$OUT_1" ] && echo "  stdout:" && cat "$OUT_1" | sed 's/^/    /'
  [ -f "$ERR_1" ] && echo "  stderr:" && cat "$ERR_1" | sed 's/^/    /'
  echo "  dest transcript: $([ -f "$RFMHOME/.claude-personal/projects/test-proj/abc-123.jsonl" ] && echo sim || echo nao)"
  echo "  dest pasta: $([ -d "$RFMHOME/.claude-personal/projects/test-proj/abc-123" ] && echo sim || echo nao)"
fi

echo ""
echo "== CASO 2: cópia pessoal→trabalho, com pasta <id>/ =="
OUT_2="$RAIZ/out-2.txt"
ERR_2="$RAIZ/err-2.txt"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=def-456 CLAUDE_CONFIG_DIR="$RFMHOME_M/.claude-personal" \
  node "$SRC/scripts/transferir-entre-contas.cjs" \
  > "$OUT_2" 2> "$ERR_2"
exit_2=$?

if [ "$exit_2" = "0" ] && \
   grep -F 'cd "C:\proj\pessoal"' "$OUT_2" > /dev/null && \
   grep -F "claude --resume def-456" "$OUT_2" > /dev/null && \
   ! grep -F "CLAUDE_CONFIG_DIR" "$OUT_2" > /dev/null && \
   [ -f "$RFMHOME/.claude/projects/test-proj/def-456.jsonl" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 2: cópia pessoal→trabalho"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 2"
  [ -f "$OUT_2" ] && cat "$OUT_2" | sed 's/^/    /'
fi

echo ""
echo "== CASO 3: origem com hash intacto ==="
ORIG_SHA=$(sha256sum "$RFMHOME/.claude/projects/test-proj/abc-123.jsonl" 2>/dev/null | cut -d' ' -f1)
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=abc-123 CLAUDE_CONFIG_DIR="" \
  node "$SRC/scripts/transferir-entre-contas.cjs" \
  > /dev/null 2>&1
ORIG_SHA_DEPOIS=$(sha256sum "$RFMHOME/.claude/projects/test-proj/abc-123.jsonl" 2>/dev/null | cut -d' ' -f1)

if [ "$ORIG_SHA" = "$ORIG_SHA_DEPOIS" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 3: origem com hash intacto"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 3: hash alterou (antes: $ORIG_SHA, depois: $ORIG_SHA_DEPOIS)"
fi

echo ""
echo "== CASO 4: destino ja tem a sessao: recusa sem --forcar e nao altera o destino =="
# Pre-seed o destino com conteúdo diferente
DEST_COLISAO="$RFMHOME/.claude-personal/projects/test-proj/abc-123.jsonl"
echo '{"type":"dummy"}' > "$DEST_COLISAO"
DEST_HASH_ANTES=$(sha256sum "$DEST_COLISAO" | cut -d' ' -f1)

OUT_4="$RAIZ/out-4.txt"
ERR_4="$RAIZ/err-4.txt"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=abc-123 CLAUDE_CONFIG_DIR="" \
  node "$SRC/scripts/transferir-entre-contas.cjs" \
  > "$OUT_4" 2> "$ERR_4"
exit_4=$?

DEST_HASH_DEPOIS=$(sha256sum "$DEST_COLISAO" | cut -d' ' -f1)

if [ "$exit_4" = "4" ] && \
   grep -q "\--forcar" "$ERR_4" && \
   [ "$DEST_HASH_ANTES" = "$DEST_HASH_DEPOIS" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 4: destino ja tem a sessao: recusa sem --forcar e nao altera o destino"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 4"
  echo "    exit: $exit_4 (esperava 4)"
  echo "    --forcar citado: $(grep -q -- --forcar "$ERR_4" && echo sim || echo nao)"
  echo "    hash preservado: $([ "$DEST_HASH_ANTES" = "$DEST_HASH_DEPOIS" ] && echo sim || echo nao)"
  cat "$ERR_4" | sed 's/^/    /'
fi

echo ""
echo "== CASO 5: colisão com --forcar sobrescreve ==="
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=abc-123 CLAUDE_CONFIG_DIR="" \
  node "$SRC/scripts/transferir-entre-contas.cjs" --forcar \
  > /dev/null 2>&1
exit_5=$?

DEST_HASH_FORCADO=$(sha256sum "$DEST_COLISAO" | cut -d' ' -f1)
ORIG_HASH=$(sha256sum "$RFMHOME/.claude/projects/test-proj/abc-123.jsonl" | cut -d' ' -f1)

if [ "$exit_5" = "0" ] && [ "$DEST_HASH_FORCADO" = "$ORIG_HASH" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 5: --forcar sobrescreve"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 5"
  echo "    exit: $exit_5"
  echo "    hash coincide: $([ "$DEST_HASH_FORCADO" = "$ORIG_HASH" ] && echo sim || echo nao)"
fi

echo ""
echo "== CASO 6: --para igual à conta atual → exit 1 ==="
OUT_6="$RAIZ/out-6.txt"
ERR_6="$RAIZ/err-6.txt"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=abc-123 CLAUDE_CONFIG_DIR="" \
  node "$SRC/scripts/transferir-entre-contas.cjs" --para trabalho \
  > "$OUT_6" 2> "$ERR_6"
exit_6=$?

if [ "$exit_6" = "1" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 6: --para igual à conta atual → exit 1"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 6: esperava exit 1, veio $exit_6"
fi

echo ""
echo "== CASO 7: sem CLAUDE_CODE_SESSION_ID → exit 1 ==="
OUT_7="$RAIZ/out-7.txt"
ERR_7="$RAIZ/err-7.txt"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  node "$SRC/scripts/transferir-entre-contas.cjs" \
  > "$OUT_7" 2> "$ERR_7"
exit_7=$?

if [ "$exit_7" = "1" ] && grep -q "CLAUDE_CODE_SESSION_ID" "$ERR_7"; then
  ok=$((ok + 1))
  echo "  ok   caso 7: sem CLAUDE_CODE_SESSION_ID → exit 1"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 7: exit $exit_7, mensagem: $(cat "$ERR_7")"
fi

echo ""
echo "== CASO 8: CLAUDE_CONFIG_DIR desconhecido → exit 1 ==="
OUT_8="$RAIZ/out-8.txt"
ERR_8="$RAIZ/err-8.txt"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=abc-123 CLAUDE_CONFIG_DIR="$RFMHOME_M/desconhecido" \
  node "$SRC/scripts/transferir-entre-contas.cjs" \
  > "$OUT_8" 2> "$ERR_8"
exit_8=$?

if [ "$exit_8" = "1" ] && grep -q "CLAUDE_CONFIG_DIR" "$ERR_8"; then
  ok=$((ok + 1))
  echo "  ok   caso 8: CLAUDE_CONFIG_DIR desconhecido → exit 1"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 8: exit $exit_8"
fi

echo ""
echo "== CASO 9: transcript sem cwd → exit 1 ==="
OUT_9="$RAIZ/out-9.txt"
ERR_9="$RAIZ/err-9.txt"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=sem-cwd-123 CLAUDE_CONFIG_DIR="" \
  node "$SRC/scripts/transferir-entre-contas.cjs" \
  > "$OUT_9" 2> "$ERR_9"
exit_9=$?

if [ "$exit_9" = "1" ] && grep -q "cwd" "$ERR_9"; then
  ok=$((ok + 1))
  echo "  ok   caso 9: transcript sem cwd → exit 1"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 9: exit $exit_9"
fi

echo ""
echo "== CASO 10: primeiro cwd em linha não-primeira ==="
OUT_10="$RAIZ/out-10.txt"
ERR_10="$RAIZ/err-10.txt"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=cwd-depois-123 CLAUDE_CONFIG_DIR="" \
  node "$SRC/scripts/transferir-entre-contas.cjs" \
  > "$OUT_10" 2> "$ERR_10"
exit_10=$?

if [ "$exit_10" = "0" ] && \
   grep -F 'cd "C:\proj\cwd-depois"' "$OUT_10" > /dev/null && \
   grep -F "claude-personal" "$OUT_10" > /dev/null && \
   grep -F "claude --resume cwd-depois-123" "$OUT_10" > /dev/null; then
  ok=$((ok + 1))
  echo "  ok   caso 10: primeiro cwd achado em linha não-primeira"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 10: exit $exit_10"
  cat "$OUT_10" | sed 's/^/    /'
fi

echo ""
echo "== CASO 11: saída com --para pessoal tem CLAUDE_CONFIG_DIR ==="
# Copia um novo transcript para pessoal para testar o --para pessoal e depois
# tentar transferir de volta
TRANSCRIPT_NOVO="$RFMHOME/.claude/projects/test-proj/novo-111.jsonl"
cat > "$TRANSCRIPT_NOVO" << 'JSONEOF'
{"type":"user","sessionId":"novo-111","cwd":"C:\\proj\\novo","message":{"role":"user","content":"Novo"}}
JSONEOF

OUT_11="$RAIZ/out-11.txt"
ERR_11="$RAIZ/err-11.txt"
env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR \
  RFM_TEST=1 RFM_HOME="$RFMHOME_M" \
  CLAUDE_CODE_SESSION_ID=novo-111 CLAUDE_CONFIG_DIR="" \
  node "$SRC/scripts/transferir-entre-contas.cjs" --para pessoal \
  > "$OUT_11" 2> "$ERR_11"
exit_11=$?

if [ "$exit_11" = "0" ]; then
  linha_resume=$(tail -1 "$OUT_11")
  if echo "$linha_resume" | grep -qE "^CLAUDE_CONFIG_DIR=.+\.claude-personal.* claude --resume novo-111"; then
    ok=$((ok + 1))
    echo "  ok   caso 11: saída com --para pessoal tem CLAUDE_CONFIG_DIR"
  else
    falhou=$((falhou + 1))
    echo "  FALHA caso 11: resume line sem CLAUDE_CONFIG_DIR correto: $linha_resume"
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 11: exit $exit_11"
  cat "$ERR_11" | sed 's/^/    /'
fi

echo ""
echo "== RESULTADO =="
echo "resultado: $ok ok, $falhou falha(s)"
if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
