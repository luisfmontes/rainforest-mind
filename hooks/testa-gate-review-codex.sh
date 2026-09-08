#!/bin/bash
# Bateria do gate-review-codex.cjs (Stop). Testa o review gate opt-in que consulta
# Codex na resposta do Claude. Usa um dublê para simular o despacho.
#
# Uso: bash hooks/testa-gate-review-codex.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/gate-review-codex.cjs"

# Caminho NATIVO para worktree
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT

# Raiz de dados para config
export RFM_ROOT="$RAIZ/dados"; mkdir -p "$RFM_ROOT"
export RFM_TEST=1

ok=0; falhou=0

# Cria payload do Stop
pay() { # cwd, transcript_path, stop_hook_active(true|false|absent)
  local c="$1" t="$2" s="${3:-}"
  local json='{"session_id":"s1","cwd":"'"$c"'","transcript_path":"'"$t"'","hook_event_name":"Stop"'
  if [ -n "$s" ]; then
    json="$json"',"stop_hook_active":'"$s"
  fi
  json="$json"'}'
  printf '%s' "$json"
}

# ============================================================================
# Dublê que simula o revisor
# ============================================================================
DUBLE="$RAIZ/duble.cjs"
cat > "$DUBLE" << 'ENDSCRIPT'
#!/usr/bin/env node
// Dublê simples que lê stdin e responde
const modo = process.env.RFM_DUBLE_MODO || 'ALLOW: ok';
const stdin = require('fs').readFileSync(0, 'utf8');

// Grava stdin se pedido
if (process.env.RFM_DUBLE_STDIN_OUT) {
  require('fs').writeFileSync(process.env.RFM_DUBLE_STDIN_OUT, stdin);
}

// Grava sentinela se pedido
if (process.env.RFM_DUBLE_SENTINEL) {
  require('fs').writeFileSync(process.env.RFM_DUBLE_SENTINEL, 'duble-rodou\n');
}

// Imprime resposta
console.log(modo);

// Stderr se pedido (ex.: a linha `codex sem cota: ...` que o despacho real emite)
if (process.env.RFM_DUBLE_STDERR) {
  console.error(process.env.RFM_DUBLE_STDERR);
}

// Exit com código se pedido
if (process.env.RFM_DUBLE_EXIT) {
  process.exit(parseInt(process.env.RFM_DUBLE_EXIT));
}
ENDSCRIPT
chmod +x "$DUBLE"

# ============================================================================
# Fixture: repositório
# ============================================================================
R="$RAIZ/repo"
git init -q -b main "$R"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
mkdir -p "$R/.rainforest"
echo '{}' > "$R/.rainforest/config.json"

# ============================================================================
# Transcript fixture
# ============================================================================
TRANSCRIPT="$RAIZ/transcript.jsonl"
cat > "$TRANSCRIPT" << 'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"pergunta antiga"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"resposta antiga que nao queremos"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"pergunta nova"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"RESPOSTA-MARCADORA-PARA-TESTE: esta eh a ultima resposta"}]}}
EOF

echo "== Caso 1: ligado, dublê devolve BLOCK:motivo-x =>"
echo '{"gate-review-codex":true}' > "$R/.rainforest/config.json"
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_MODO="BLOCK: motivo-x" node "$HOOK" 2>&1)
if printf '%s' "$saida" | grep -qF '"decision":"block"'; then
  ok=$((ok+1)); echo "  ok   BLOCK produz decision block"
  if printf '%s' "$saida" | grep -qF "motivo-x"; then
    ok=$((ok+1)); echo "  ok   motivo-x aparece na reason"
  else
    falhou=$((falhou+1)); echo "  FALHA motivo-x não aparece: $saida" | head -1
  fi
else
  falhou=$((falhou+1)); echo "  FALHA BLOCK não bloqueou"
fi

echo
echo "== Caso 2: ligado, dublê devolve ALLOW:ok =>"
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_MODO="ALLOW: ok" node "$HOOK" 2>&1)
if [ -z "$(printf '%s' "$saida" | grep -E 'decision|reason' || true)" ]; then
  ok=$((ok+1)); echo "  ok   ALLOW libera sem decision JSON"
else
  falhou=$((falhou+1)); echo "  FALHA decision JSON emitida: $saida"
fi

echo
echo "== Caso 3: desligado => dublê NÃO chamado =>"
echo '{"gate-review-codex":false}' > "$R/.rainforest/config.json"
SENTINEL="$RAIZ/sentinel-3"
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_SENTINEL="$SENTINEL" node "$HOOK" 2>&1)
if [ ! -f "$SENTINEL" ]; then
  ok=$((ok+1)); echo "  ok   desligado libera sem chamar dublê"
else
  falhou=$((falhou+1)); echo "  FALHA dublê rodou mesmo desligado"
fi

echo
echo "== Caso 4: stop_hook_active true => anti-loop =>"
echo '{"gate-review-codex":true}' > "$R/.rainforest/config.json"
SENTINEL="$RAIZ/sentinel-4"
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "true")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_SENTINEL="$SENTINEL" node "$HOOK" 2>&1)
if [ ! -f "$SENTINEL" ]; then
  ok=$((ok+1)); echo "  ok   stop_hook_active=true libera sem dublê"
else
  falhou=$((falhou+1)); echo "  FALHA dublê rodou com stop_hook_active=true"
fi

echo
echo "== Caso 5: dublê exit 1 = falha fechada =>"
echo '{"gate-review-codex":true}' > "$R/.rainforest/config.json"
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_MODO="ALLOW: ok" RFM_DUBLE_EXIT="1" node "$HOOK" 2>&1)
if printf '%s' "$saida" | grep -qF '"decision":"block"' && printf '%s' "$saida" | grep -qF "falha fechada"; then
  ok=$((ok+1)); echo "  ok   exit 1 bloqueia com falha fechada"
else
  falhou=$((falhou+1)); echo "  FALHA exit 1 não produziu bloqueio: $saida"
fi

echo
echo "== Caso 6: resposta inválida (talvez) = falha fechada =>"
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_MODO="talvez nao sei" node "$HOOK" 2>&1)
if printf '%s' "$saida" | grep -qF '"decision":"block"' && printf '%s' "$saida" | grep -qF "falha fechada"; then
  ok=$((ok+1)); echo "  ok   resposta inválida bloqueia com falha fechada"
else
  falhou=$((falhou+1)); echo "  FALHA resposta inválida: $saida"
fi

echo
echo "== Caso 6b: despacho sem cota (exit 75) => bloqueia citando a causa e a hora =>"
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_MODO="" RFM_DUBLE_EXIT="75" RFM_DUBLE_STDERR="codex sem cota: You've hit your usage limit. Try again at 5:41 PM." node "$HOOK" 2>&1)
if printf '%s' "$saida" | grep -qF '"decision":"block"' && printf '%s' "$saida" | grep -qF "codex sem cota" && printf '%s' "$saida" | grep -qF "5:41 PM"; then
  ok=$((ok+1)); echo "  ok   sem cota bloqueia com 'codex sem cota' e a hora de retorno no reason"
else
  falhou=$((falhou+1)); echo "  FALHA sem cota deveria citar a causa: $saida"
fi

echo
# Ate o revisar de 2026-09-08 este caso esperava LIBERAR. Os dois revisores
# (Claude e Codex) apontaram a contradicao com o cabecalho "falha fechada": um
# transcript_path que o harness nao entregou, ou que rotacionou entre o Stop e
# o hook, fazia o gate inteiro sumir em silencio. Agora bloqueia com motivo; o
# stop_hook_active do turno seguinte garante que custa um turno, nao um laco.
echo "== Caso 7: transcript sem assistant => bloqueia (falha fechada) =>"
VAZIO="$RAIZ/transcript-vazio.jsonl"
echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"só user"}]}}' > "$VAZIO"
saida=$(printf '%s' "$(pay "$R" "$VAZIO" "false")" | node "$HOOK" 2>&1)
if printf '%s' "$saida" | grep -qF '"decision":"block"' && printf '%s' "$saida" | grep -qF "última resposta"; then
  ok=$((ok+1)); echo "  ok   sem assistant bloqueia com motivo"
else
  falhou=$((falhou+1)); echo "  FALHA sem assistant deveria bloquear: $saida"
fi

echo
echo "== Caso 7b: transcript_path ausente no evento => bloqueia (falha fechada) =>"
saida=$(printf '%s' '{"session_id":"s","cwd":"'"$(cygpath -m "$R" 2>/dev/null || printf '%s' "$R")"'","stop_hook_active":false}' | node "$HOOK" 2>&1)
if printf '%s' "$saida" | grep -qF '"decision":"block"' && printf '%s' "$saida" | grep -qF "transcript_path ausente"; then
  ok=$((ok+1)); echo "  ok   transcript_path ausente bloqueia com motivo"
else
  falhou=$((falhou+1)); echo "  FALHA transcript_path ausente deveria bloquear: $saida"
fi

echo
echo "== Caso 7c: nenhum briefing temporário fica para trás (ALLOW e BLOCK) =>"
ANTES=$(ls "${TMPDIR:-${TEMP:-/tmp}}" 2>/dev/null | grep -c '^rfm-review-' || true)
printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_MODO="ALLOW: ok" node "$HOOK" >/dev/null 2>&1
printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_MODO="BLOCK: teste" node "$HOOK" >/dev/null 2>&1
DEPOIS=$(ls "${TMPDIR:-${TEMP:-/tmp}}" 2>/dev/null | grep -c '^rfm-review-' || true)
if [ "$ANTES" = "$DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok   ALLOW e BLOCK apagam o briefing temporário ($ANTES antes, $DEPOIS depois)"
else
  falhou=$((falhou+1)); echo "  FALHA sobrou briefing temporário: $ANTES antes, $DEPOIS depois"
fi

echo
echo "== Caso 8: dublê recebe última resposta no briefing =>"
echo '{"gate-review-codex":true}' > "$R/.rainforest/config.json"
STDIN_OUT="$RAIZ/stdin-recebido.txt"
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_DUBLE_SCRIPT="$DUBLE" RFM_DUBLE_MODO="ALLOW: ok" RFM_DUBLE_STDIN_OUT="$STDIN_OUT" node "$HOOK" 2>&1)
if [ -f "$STDIN_OUT" ]; then
  if grep -qF "RESPOSTA-MARCADORA-PARA-TESTE" "$STDIN_OUT"; then
    ok=$((ok+1)); echo "  ok   briefing contém frase marcadora"
    if ! grep -qF "resposta antiga que nao queremos" "$STDIN_OUT"; then
      ok=$((ok+1)); echo "  ok   briefing NÃO contém resposta antiga"
    else
      falhou=$((falhou+1)); echo "  FALHA briefing contém resposta antiga"
    fi
  else
    falhou=$((falhou+1)); echo "  FALHA frase marcadora não aparece"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA stdin não gravado"
fi

echo
echo "== Caso 9: costura real hook -> despachar-codex.cjs -> dublê (sem RFM_DUBLE_SCRIPT) =>"
# Ate 2026-09-08 o modo de teste do hook pulava o despachar-codex.cjs inteiro, e uma
# flag renomeada no script so apareceria em producao. Aqui o hook segue o caminho
# de producao; quem vira duble e o `codex` la no fim, via RFM_TEST=1 + CODEX_CMD.
echo '{"gate-review-codex":true}' > "$R/.rainforest/config.json"
SRC_M="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
CMD_OUT_9="$RAIZ/cmd-9.txt"
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_TEST=1 CODEX_CMD="node \"$SRC_M/scripts/fixtures/codex-duble.cjs\"" DUBLE_MODO=parecer DUBLE_PARECER="BLOCK: via-despacho" DUBLE_CMD_OUT="$CMD_OUT_9" node "$HOOK" 2>&1)
if printf '%s' "$saida" | grep -qF '"decision":"block"' && printf '%s' "$saida" | grep -qF "via-despacho"; then
  ok=$((ok+1)); echo "  ok   BLOCK do dublê atravessa o despachar-codex.cjs até a decisão do hook"
else
  falhou=$((falhou+1)); echo "  FALHA costura: $(printf '%s' "$saida" | head -3)"
fi
if [ -f "$CMD_OUT_9" ] && grep -qF -- '-s read-only' "$CMD_OUT_9" && grep -qF -- '--skip-git-repo-check' "$CMD_OUT_9"; then
  ok=$((ok+1)); echo "  ok   comando real montado pelo despacho é read-only"
else
  falhou=$((falhou+1)); echo "  FALHA comando real: $(cat "$CMD_OUT_9" 2>/dev/null)"
fi
saida=$(printf '%s' "$(pay "$R" "$TRANSCRIPT" "false")" | RFM_TEST=1 CODEX_CMD="node \"$SRC_M/scripts/fixtures/codex-duble.cjs\"" DUBLE_MODO=parecer DUBLE_PARECER="ALLOW: tudo certo" node "$HOOK" 2>&1)
got=$?
if [ $got -eq 0 ] && [ -z "$(printf '%s' "$saida" | grep decision || true)" ]; then
  ok=$((ok+1)); echo "  ok   ALLOW do dublê atravessa o despacho e libera"
else
  falhou=$((falhou+1)); echo "  FALHA ALLOW via despacho: exit=$got $(printf '%s' "$saida" | head -2)"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
