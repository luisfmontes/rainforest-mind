#!/bin/bash
# Bateria do gate-publicacao-destino.cjs. Monta repo e worktree git de verdade e
# alimenta o hook com payloads reais de PreToolUse, conferindo exit code.
# Uso: bash hooks/testa-gate-publicacao-destino.sh
#
# O que esta bateria precisa provar:
#   1. arquivo versionado + conteúdo com telefone/JID → barrado (exit 2)
#   2. arquivo gitignorado + mesmo conteúdo → passa (exit 0)
#   3. fora de repo git → passa (exit 0)
#   4. conteúdo limpo em arquivo versionado → passa (exit 0)
#   5. escape (RAINFOREST_GATE_OFF=1) → passa mesmo com conteúdo sujo (exit 0)
#   6. progress.jsonl versionado recebendo JID → barrado (exit 2)
#   7. marcador "rainforest-gate: dados-de-exemplo" dispensa conferência (exit 0)
#   8. sem marcador, conteúdo sujo é barrado — marcador não vaza para vizinhos (exit 2)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SRC/hooks/gate-publicacao-destino.cjs"
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0
gate() { # nome, exit esperado, json
  local nome="$1" esp="$2" json="$3"
  local saida; saida=$(printf '%s' "$json" | node "$GATE" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -10; fi
}

# Prepara repo com git
R="$RAIZ/principal"
git init -q "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
echo "v1" > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm base

# Prepare diretórios para testes fora de repo
FORA="$RAIZ/sem-git"; mkdir -p "$FORA"

esc() { printf '%s' "$1" | sed 's|\\|/|g'; }

# Helper para montar payload de Write
write() {
  local arquivo="$1" conteudo="$2" cwd="${3:-$(esc "$R")}"
  printf '{"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":%s}}' \
    "$cwd" "$(esc "$arquivo")" "$(printf '%s' "$conteudo" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | jq -Rs .)"
}

# Helper para montar payload de Edit
edit() {
  local arquivo="$1" novo="$2" cwd="${3:-$(esc "$R")}"
  printf '{"cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"old","new_string":%s}}' \
    "$cwd" "$(esc "$arquivo")" "$(printf '%s' "$novo" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | jq -Rs .)"
}

echo "== Preparação: dados sensíveis para testes =="
JID_REAL="5547991234567@s.whatsapp.net"
TEL_REAL="(47) 99123-4567"
EMAIL_REAL="teste@example.com"
CONTEUDO_LIMPO="arquivo normal sem dados sensíveis"

echo "  JID: $JID_REAL"
echo "  Tel: $TEL_REAL"
echo "  Email: $EMAIL_REAL"

echo
echo "== CASO 1: arquivo versionado + conteúdo com JID → barrado (exit 2) =="
git -C "$R" add -A 2>/dev/null || true
gate "Write em arquivo versionado com JID" 2 "$(write "$R/test-jid.txt" "contato: $JID_REAL")"

echo
echo "== CASO 2: arquivo gitignorado + conteúdo com JID → passa (exit 0) =="
mkdir -p "$R/.gitignore.d"
printf '%s\n' '*.ignored' >> "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "add gitignore" || true
gate "Write em arquivo gitignorado com JID" 0 "$(write "$R/test.ignored" "contato: $JID_REAL")"

echo
echo "== CASO 3: fora de repo git → passa (exit 0) =="
gate "Write fora de repo com JID" 0 "$(write "$FORA/arquivo.txt" "contato: $JID_REAL" "$(esc "$FORA")")"

echo
echo "== CASO 4: conteúdo limpo em arquivo versionado → passa (exit 0) =="
gate "Write em versionado com conteúdo limpo" 0 "$(write "$R/limpo.txt" "$CONTEUDO_LIMPO")"

echo
echo "== CASO 5: escape RAINFOREST_GATE_OFF=1 → passa mesmo com conteúdo sujo (exit 0) =="
saida=$(printf '%s' "$(write "$R/escape.txt" "contato: $JID_REAL")" | RAINFOREST_GATE_OFF=1 node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok=$((ok+1)); echo "  ok   RAINFOREST_GATE_OFF=1 libera com conteúdo sujo (exit 0)"
else falhou=$((falhou+1)); echo "  FALHA RAINFOREST_GATE_OFF não liberou (exit $rc)"; echo "$saida" | sed 's/^/         /' | head -5; fi

echo
echo "== CASO 6: progress.jsonl versionado com JID → barrado (exit 2) =="
# Reproduz o caso real da Issue #83
mkdir -p "$R/_reversa_forward/004-teste"
PROGRESS="$R/_reversa_forward/004-teste/progress.jsonl"
PROGRESS_CONTEUDO=$(printf '{"status":"smoke test","contato":"%s","resultado":"ok"}\n' "$JID_REAL")
gate "progress.jsonl versionado com JID (Issue #83)" 2 "$(write "$PROGRESS" "$PROGRESS_CONTEUDO")"

echo
echo "== FALSIFICAÇÃO 1: Desligar o gate e deixar passar conteúdo sujo =="
echo "Esperado: com conteúdo sujo, exit 2 (barrado)"
msg=$(printf '%s' "$(write "$R/fake-test.txt" "contato: $JID_REAL")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" != 0 ]; then
  ok=$((ok+1))
  echo "  ok   conteúdo sujo foi BARRADO (exit $rc)"
  echo "  Mensagem de bloqueio:"
  printf '%s' "$msg" | sed 's/^/    /' | head -15
else
  falhou=$((falhou+1))
  echo "  FALHA conteúdo sujo passou (exit $rc) — gate não funciona!"
fi

echo
echo "== FALSIFICAÇÃO 2: Telefone sem JID também é detectado =="
echo "Esperado: exit 2 (barrado por padrão 'telefone')"
msg=$(printf '%s' "$(write "$R/fake-tel.txt" "telefone do cliente: $TEL_REAL")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" != 0 ]; then
  ok=$((ok+1))
  echo "  ok   telefone foi BARRADO (exit $rc)"
  echo "  Mensagem menciona padrão:"
  if printf '%s' "$msg" | grep -q "telefone\|phone"; then
    ok=$((ok+1))
    echo "    ✓ mensagem menciona 'telefone'"
  else
    falhou=$((falhou+1))
    echo "    ✗ mensagem NÃO menciona o padrão"
  fi
else
  falhou=$((falhou+1))
  echo "  FALHA telefone passou (exit $rc) — gate não funciona!"
fi

echo
echo "== Teste de escape com .rainforest-gate-off =="
touch "$R/.rainforest-gate-off"
msg=$(printf '%s' "$(write "$R/escape-arquivo.txt" "contato: $JID_REAL")" | node "$GATE" 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  ok=$((ok+1))
  echo "  ok   .rainforest-gate-off libera gate (exit 0)"
else
  falhou=$((falhou+1))
  echo "  FALHA .rainforest-gate-off não liberou (exit $rc)"
fi
rm "$R/.rainforest-gate-off"

echo
echo "== Teste do marcador: Edit em arquivo com marcador em disco ===="
# Arquivo com marcador EM DISCO passa, mesmo se new_string não o tem
gate "Edit no scripts/testa-conferir-publicacao.sh (marcador em disco) + JID → passa (exit 0)" 0 "$(printf '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"scripts/testa-conferir-publicacao.sh\",\"old_string\":\"x\",\"new_string\":\"jid=\\\"5547991234567@s.whatsapp.net\\\"\"}}' | sed 's|scripts/|'"$(esc "$SRC")"'/scripts/|')"

echo
echo "== Teste do marcador: Write de arquivo novo com marcador no conteúdo =="
# Write de arquivo novo: marcador NO CONTEÚDO, mas NÃO EM DISCO = barrado
gate "Write arquivo novo (sem em disco) com marcador no conteúdo + JID → barrado (exit 2)" 2 "$(write "$R/arquivo-com-marcador.sh" "# rainforest-gate: dados-de-exemplo
jid=\"5547991234567@s.whatsapp.net\"")"

echo
echo "== Verificação: gate-staging-total continua verde =="
echo "Rodando: bash hooks/testa-gate-staging-total.sh"
if bash "$SRC/hooks/testa-gate-staging-total.sh" > /tmp/test-staging.log 2>&1; then
  ok=$((ok+1))
  echo "  ok   gate-staging-total passou"
else
  falhou=$((falhou+1))
  echo "  FALHA gate-staging-total falhou"
  tail -20 /tmp/test-staging.log | sed 's/^/    /'
fi

echo
echo "== Verificação: conferir-publicacao.sh continua verde =="
echo "Rodando: bash scripts/testa-conferir-publicacao.sh"
if bash "$SRC/scripts/testa-conferir-publicacao.sh" > /tmp/test-conferir.log 2>&1; then
  ok=$((ok+1))
  echo "  ok   conferir-publicacao passou"
else
  falhou=$((falhou+1))
  echo "  FALHA conferir-publicacao falhou"
  tail -20 /tmp/test-conferir.log | sed 's/^/    /'
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
