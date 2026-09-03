#!/bin/bash
# Bateria para scripts/fechar-issue.cjs — testa fechamento com evidência
# Testa: (a) exit 0 e chamadas em ordem, (b) exit 1 quando comment falha, (c) arquivo de saída

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
test_ok() { ok=$((ok+1)); echo "  ok   $1"; }
test_fail() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# Criar stub gh
mkdir -p "$SBP/bin"
cat > "$SBP/bin/gh" <<'GH'
#!/bin/bash
[ -n "${GH_LOG:-}" ] && echo "CHAMADA: gh $*" >> "$GH_LOG"
[ "$1" = "issue" ] && [ "$2" = "comment" ] && [ -n "${GH_COMMENT_FAIL:-}" ] && exit 1
[ "$1" = "issue" ] && [ "$2" = "comment" ] && [ -n "${GH_LOG:-}" ] && {
  for i in "${!@}"; do
    [ "${!i}" = "--body-file" ] && [ $((i+1)) -lt ${#@} ] && {
      j=$((i+1))
      [ -f "${!j}" ] && { echo "CORPO:" >> "$GH_LOG"; cat "${!j}" >> "$GH_LOG"; echo "---" >> "$GH_LOG"; }
    }
  done
}
exit 0
GH
chmod +x "$SBP/bin/gh"

# ===== Caso (a): sucesso
echo "== (a) gh issue comment com sucesso → gh issue close é chamado, nessa ordem =="
GH_LOG="$SBP/log-a" GH_CMD="$SBP/bin/gh" node "$SRC/scripts/fechar-issue.cjs" 123 --comando "git log -1" --saida "commit abc123" >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_A="$(cat "$SBP/log-a" 2>/dev/null || echo '')"
echo "$LOG_A" | grep -q "issue comment" && test_ok "issue comment no log" || test_fail "issue comment no log"
echo "$LOG_A" | grep -q "issue close" && test_ok "issue close no log" || test_fail "issue close no log"
[ "$(echo "$LOG_A" | grep -n "issue comment" | cut -d: -f1)" -lt "$(echo "$LOG_A" | grep -n "issue close" | cut -d: -f1)" ] 2>/dev/null && test_ok "ordem correta" || test_fail "ordem"
echo "$LOG_A" | grep -q "<!-- rainforest-evidencia -->" && test_ok "marcador no corpo" || test_fail "marcador"
echo "$LOG_A" | grep -q "git log -1" && test_ok "comando no corpo" || test_fail "comando"
echo "$LOG_A" | grep -q "commit abc123" && test_ok "saída no corpo" || test_fail "saída"

# ===== Caso (b): falha
echo
echo "== (b) gh issue comment falha → gh issue close NUNCA é chamado =="
GH_LOG="$SBP/log-b" GH_CMD="$SBP/bin/gh" GH_COMMENT_FAIL=1 node "$SRC/scripts/fechar-issue.cjs" 456 --comando "echo teste" --saida "ok" >/dev/null 2>&1
[ $? -ne 0 ] && test_ok "exit != 0" || test_fail "exit code"
LOG_B="$(cat "$SBP/log-b" 2>/dev/null || echo '')"
echo "$LOG_B" | grep -q "issue comment" && test_ok "issue comment no log" || test_fail "issue comment no log"
echo "$LOG_B" | grep -q "issue close" && test_fail "issue close não deveria aparecer" || test_ok "issue close não aparece"

# ===== Caso (c): arquivo
echo
echo "== (c) corpo contém marcador, comando e saída =="
echo "resultado: sucesso" > "$SBP/arquivo.txt"
GH_LOG="$SBP/log-c" GH_CMD="$SBP/bin/gh" node "$SRC/scripts/fechar-issue.cjs" 789 --comando "bash teste.sh" --saida "$SBP/arquivo.txt" >/dev/null 2>&1
[ $? -eq 0 ] && test_ok "exit 0" || test_fail "exit code"
LOG_C="$(cat "$SBP/log-c" 2>/dev/null || echo '')"
echo "$LOG_C" | grep -q "resultado: sucesso" && test_ok "arquivo lido" || test_fail "arquivo lido"
echo "$LOG_C" | grep -q "<!-- rainforest-evidencia -->" && test_ok "marcador" || test_fail "marcador"
echo "$LOG_C" | grep -q "bash teste.sh" && test_ok "comando" || test_fail "comando"
echo "$LOG_C" | grep -q "resultado: sucesso" && test_ok "saída arquivo" || test_fail "saída arquivo"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
