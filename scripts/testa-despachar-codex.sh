#!/bin/bash
# Bateria para despachar-codex.cjs — transporte do agente para Codex CLI
# Uso: bash scripts/testa-despachar-codex.sh
#
# Testa despachar-codex contra dublê (nunca contra Codex real — D11).

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_M="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

# Usar diretório temporário (fora do worktree para limpeza correta)
RAIZ_BASE="/tmp/test-despachar-codex-$$"
mkdir -p "$RAIZ_BASE"
RAIZ="$RAIZ_BASE"

# UM trap de EXIT para a bateria inteira
A_LIMPAR="$RAIZ_BASE"
limpa() {
  cd "$SRC" 2>/dev/null || cd /
  sleep 1
  local d
  for d in $A_LIMPAR; do
    rm -rf "$d" 2>/dev/null
  done
}
trap limpa EXIT

echo "(caixa de areia: $RAIZ)"
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
# Cria plugin mínimo na caixa de areia com agents/, hooks/lib/, scripts/

mkdir -p "$RAIZ/plugin"
PLUGIN="$RAIZ/plugin"

# Copia agente de teste
mkdir -p "$PLUGIN/agents"
cat > "$PLUGIN/agents/revisor.md" << 'AGENTEOF'
---
name: revisor
model: sonnet
---
Você é o revisor.

<!-- ponte-codex -->
Instrução de ponte: chamar /despachar-codex com flags
<!-- /ponte-codex -->

Seu trabalho é revisar.
AGENTEOF

# Copia hooks/lib/
mkdir -p "$PLUGIN/hooks/lib"
cp "$SRC/hooks/lib/cli-externo.cjs" "$PLUGIN/hooks/lib/cli-externo.cjs"
cp "$SRC/hooks/lib/codex-cota.cjs" "$PLUGIN/hooks/lib/codex-cota.cjs"
cp "$SRC/hooks/lib/config.cjs" "$PLUGIN/hooks/lib/config.cjs"
cp "$SRC/hooks/lib/raiz.cjs" "$PLUGIN/hooks/lib/raiz.cjs" 2>/dev/null || true

# Copia scripts/despachar-codex.cjs
mkdir -p "$PLUGIN/scripts/fixtures"
cp "$SRC/scripts/despachar-codex.cjs" "$PLUGIN/scripts/despachar-codex.cjs"
cp "$SRC/scripts/fixtures/codex-duble.cjs" "$PLUGIN/scripts/fixtures/codex-duble.cjs"

# Cria worktree de teste com .git isolado (gitdir)
mkdir -p "$RAIZ/wt-test/.git/worktrees/wt-isolado"
WTS="$RAIZ/wt-test"
WTE="$WTS/.claude/worktrees/agent-xyz"
mkdir -p "$WTE"
echo "gitdir: $WTS/.git/worktrees/wt-isolado" > "$WTE/.git"
cd "$WTE"
git init --quiet "$WTS"
git -C "$WTS" config user.email "test@test"
git -C "$WTS" config user.name "Test"
git -C "$WTS" checkout --quiet -b main

# Cria briefing de teste
BRIEFING="$RAIZ/briefing.md"
cat > "$BRIEFING" << 'BRIEFEOF'
## Contexto
Tarefa de teste.

## Entrega esperada
Análise completa.
BRIEFEOF

# Cria config do worktree com modelo
mkdir -p "$WTE/.rainforest"
cat > "$WTE/.rainforest/config.json" << 'CONFIGEOF'
{
  "codex-modelo-sonnet": {
    "modelo": "m-teste",
    "esforco": "low"
  }
}
CONFIGEOF

# Cria arquivo de teste de comando
DUBLE="$PLUGIN/scripts/fixtures/codex-duble.cjs"
DUBLE_M="$(cygpath -m "$DUBLE" 2>/dev/null || printf '%s' "$DUBLE")"

# ===== CASOS =====

echo "== CASO 1: --escreve false no worktree ==="
STDIN_OUT_1="$RAIZ/stdin-1.txt"
CMD_OUT_1="$RAIZ/cmd-1.txt"
SAIDA_1="$RAIZ/saida-1.txt"
STDIN_OUT_1_M="$(cygpath -m "$STDIN_OUT_1" 2>/dev/null || printf '%s' "$STDIN_OUT_1")"
CMD_OUT_1_M="$(cygpath -m "$CMD_OUT_1" 2>/dev/null || printf '%s' "$CMD_OUT_1")"
SAIDA_1_M="$(cygpath -m "$SAIDA_1" 2>/dev/null || printf '%s' "$SAIDA_1")"

DUBLE_MODO=ok \
DUBLE_STDIN_OUT="$STDIN_OUT_1_M" \
DUBLE_CMD_OUT="$CMD_OUT_1_M" \
DUBLE_SAIDA="$SAIDA_1_M" \
RFM_TEST=1 \
CODEX_CMD="node $DUBLE_M" \
testa "caso 1: --escreve false sem --add-dir" 0 \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
    --agente revisor \
    --worktree "$WTE" \
    --escreve false \
    --briefing-file "$BRIEFING" \
    --saida "$SAIDA_1_M"

# Valida caso 1
if grep -q -- '-s read-only' "$CMD_OUT_1" && \
   grep -q -- '--skip-git-repo-check' "$CMD_OUT_1" && \
   grep -q -- '-c approval_policy="never"' "$CMD_OUT_1" && \
   ! grep -q -- '--add-dir' "$CMD_OUT_1" && \
   ! grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$CMD_OUT_1" && \
   [ "$(cat $SAIDA_1)" = "RESPOSTA DO DUBLE" ]; then
  ok=$((ok + 1))
  echo "    ✓ cmd contém -s read-only, --skip-git-repo-check, approval_policy; sem --add-dir"
else
  falhou=$((falhou + 1))
  echo "    ✗ validação falhou"
  [ -f "$CMD_OUT_1" ] && echo "      cmd: $(cat $CMD_OUT_1)"
  [ -f "$SAIDA_1" ] && echo "      saida: $(cat $SAIDA_1)"
fi

echo ""
# Ate 2026-09-08 este caso exigia `--add-dir <repo>/.git` no comando. A T8 com
# Codex real derrubou a premissa: o sandbox workspace-write nega escrita em
# `.git` mesmo com --add-dir (index.lock: Permission denied), entao a flag saiu
# e o commit passou para a ponte. O caso agora garante que ela NAO volte.
echo "== CASO 2: --escreve true com gitdir → workspace-write, sem --add-dir ==="
STDIN_OUT_2="$RAIZ/stdin-2.txt"
CMD_OUT_2="$RAIZ/cmd-2.txt"
SAIDA_2="$RAIZ/saida-2.txt"
STDIN_OUT_2_M="$(cygpath -m "$STDIN_OUT_2" 2>/dev/null || printf '%s' "$STDIN_OUT_2")"
CMD_OUT_2_M="$(cygpath -m "$CMD_OUT_2" 2>/dev/null || printf '%s' "$CMD_OUT_2")"
SAIDA_2_M="$(cygpath -m "$SAIDA_2" 2>/dev/null || printf '%s' "$SAIDA_2")"

DUBLE_MODO=ok \
DUBLE_STDIN_OUT="$STDIN_OUT_2_M" \
DUBLE_CMD_OUT="$CMD_OUT_2_M" \
DUBLE_SAIDA="$SAIDA_2_M" \
RFM_TEST=1 \
CODEX_CMD="node $DUBLE_M" \
testa "caso 2: --escreve true sem --add-dir" 0 \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
    --agente revisor \
    --worktree "$WTE" \
    --escreve true \
    --briefing-file "$BRIEFING" \
    --saida "$SAIDA_2_M"

# Valida caso 2: com --escreve true, DEVE ter -s workspace-write (não read-only)
if grep -q -- '-s workspace-write' "$CMD_OUT_2" && \
   ! grep -q -- '--add-dir' "$CMD_OUT_2" && \
   ! grep -q -- '-s read-only' "$CMD_OUT_2" && \
   ! grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$CMD_OUT_2"; then
  ok=$((ok + 1))
  echo "    ✓ cmd contém -s workspace-write (não read-only) e nenhum --add-dir"
else
  falhou=$((falhou + 1))
  echo "    ✗ validação falhou"
  [ -f "$CMD_OUT_2" ] && echo "      cmd: $(cat $CMD_OUT_2)"
  [ -f "$CMD_OUT_2" ] && grep -q -- '-s read-only' "$CMD_OUT_2" && echo "      ERRO: contém -s read-only quando deveria ter -s workspace-write"
fi

echo ""
echo "== CASO 3: nunca contém --dangerously-bypass-approvals-and-sandbox ==="
if ! grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$CMD_OUT_1" && \
   ! grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$CMD_OUT_2"; then
  ok=$((ok + 1))
  echo "  ok   caso 3: --dangerously-bypass-approvals-and-sandbox ausente"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 3: flag perigosa presente"
fi

echo ""
echo "== CASO 4: stdin contém corpo sem frontmatter e sem ponte, + briefing ==="
if [ -f "$STDIN_OUT_1" ]; then
  stdin=$(cat "$STDIN_OUT_1")
  if echo "$stdin" | grep -q "Você é o revisor" && \
     ! echo "$stdin" | grep -q "model: sonnet" && \
     ! echo "$stdin" | grep -q "ponte-codex" && \
     echo "$stdin" | grep -q "Tarefa de teste"; then
    ok=$((ok + 1))
    echo "  ok   caso 4: stdin correto (corpo sem FM/ponte + briefing)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA caso 4: stdin incorreto"
    echo "$stdin" | head -20 | sed 's/^/      /'
  fi
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 4: stdin não gravado"
fi

echo ""
echo "== CASO 5: modelo mapeado por config ==="
if grep -q -- '-m "m-teste"' "$CMD_OUT_2" && \
   grep -q -- 'model_reasoning_effort="low"' "$CMD_OUT_2"; then
  ok=$((ok + 1))
  echo "  ok   caso 5: -m e model_reasoning_effort presentes"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 5: modelo não mapeado"
  [ -f "$CMD_OUT_2" ] && cat "$CMD_OUT_2" | sed 's/^/    /'
fi

echo ""
echo "== CASO 6: DUBLE_MODO=falha → exit ≠ 0 ==="
SAIDA_6="$RAIZ/saida-6.txt"
SAIDA_6_M="$(cygpath -m "$SAIDA_6" 2>/dev/null || printf '%s' "$SAIDA_6")"
saida_6=$(DUBLE_MODO=falha \
DUBLE_SAIDA="$SAIDA_6_M" \
RFM_TEST=1 \
CODEX_CMD="node $DUBLE_M" \
node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" \
  --saida "$SAIDA_6_M" 2>&1)
exit_6=$?
if [ "$exit_6" = "1" ] && echo "$saida_6" | grep -q "erro simulado"; then
  ok=$((ok + 1))
  echo "  ok   caso 6: dublê falha, exit 1 com 'erro simulado'"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 6: esperava exit 1 com 'erro simulado', veio exit $exit_6"
  echo "$saida_6" | head -5 | sed 's/^/    /'
fi

echo ""
echo "== CASO 7: DUBLE_MODO=dorme com timeout ==="
SAIDA_7="$RAIZ/saida-7.txt"
SAIDA_7_M="$(cygpath -m "$SAIDA_7" 2>/dev/null || printf '%s' "$SAIDA_7")"
saida_7=$(DUBLE_MODO=dorme \
DUBLE_SAIDA="$SAIDA_7_M" \
RFM_TEST=1 \
CODEX_CMD="node $DUBLE_M" \
node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" \
  --timeout-ms 1000 \
  --saida "$SAIDA_7_M" 2>&1)
exit_7=$?
if [ "$exit_7" = "124" ] && echo "$saida_7" | grep -q "timeout"; then
  ok=$((ok + 1))
  echo "  ok   caso 7: timeout, exit 124 com 'timeout'"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 7: esperava exit 124 com 'timeout', veio exit $exit_7"
  echo "$saida_7" | head -5 | sed 's/^/    /'
fi

echo ""
echo "== CASO 8: sem RFM_TEST o dublê não é chamado ==="
# Prova que sem RFM_TEST o script NOT tenta chamar "codex" (falharia)
# Usamos PATH fake e checamos se "codex" foi procurado
FAKE_PATH="$RAIZ/fake-bin"
mkdir -p "$FAKE_PATH"
FAKE_CODEX="$FAKE_PATH/codex"
cat > "$FAKE_CODEX" << 'EOF'
#!/bin/bash
echo "CODEX_FALSO_CHAMADO=1" >> /tmp/codex-fake-chamado-$$
exit 0
EOF
chmod +x "$FAKE_CODEX"

# Desativa RFM_TEST e CODEX_CMD, tenta rodar (vai tentar chamar codex real e falhar)
# Checa que a falha vem de "codex" real ausente, não do dublê
saida=$(PATH="$FAKE_PATH:$PATH" node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" \
  2>&1 || true)
# Se o comando no stderr começa com "codex exec" é a tentativa real
if echo "$saida" | grep -q "^comando: codex exec"; then
  ok=$((ok + 1))
  echo "  ok   caso 8: comando real tentado (sem RFM_TEST)"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 8: não tentou codex real"
  echo "$saida" | head -5 | sed 's/^/    /'
fi

echo ""
echo "== CASO 9: --dry-run desconhecida → exit 1 ==="
saida_9=$(node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" \
  --dry-run 2>&1)
exit_9=$?
if [ "$exit_9" = "1" ] && echo "$saida_9" | grep -q "flag desconhecida"; then
  ok=$((ok + 1))
  echo "  ok   caso 9: flag desconhecida, exit 1"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 9: esperava exit 1 com 'flag desconhecida', veio exit $exit_9"
  echo "$saida_9" | head -3 | sed 's/^/    /'
fi

# Caso 9b: flag desconhecida COM valor tambem e recusada. Ate 2026-09-08 o
# parser aceitava qualquer `--x y` e so tropecava em flag sem valor — o `--dry-run`
# do caso 9 passava por acidente, nao por allowlist. Exit 1, e o duble NAO roda:
# recusa vem antes de qualquer efeito.
echo "== CASO 9b: --foo bar desconhecida → exit 1, sem chamar o dublê ==="
CMD_OUT_9B="$RAIZ/cmd-9b.txt"
CMD_OUT_9B_M="$(cygpath -m "$CMD_OUT_9B" 2>/dev/null || printf '%s' "$CMD_OUT_9B")"
rm -f "$CMD_OUT_9B"
saida_9b=$(DUBLE_MODO=ok DUBLE_CMD_OUT="$CMD_OUT_9B_M" RFM_TEST=1 CODEX_CMD="node $DUBLE_M" \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" \
  --foo bar 2>&1)
exit_9b=$?
if [ "$exit_9b" = "1" ] && echo "$saida_9b" | grep -q "flag desconhecida: --foo" && [ ! -f "$CMD_OUT_9B" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 9b: flag desconhecida com valor, exit 1, dublê não chamado"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 9b: esperava exit 1 com 'flag desconhecida: --foo' e dublê ausente, veio exit $exit_9b"
  echo "$saida_9b" | head -3 | sed 's/^/    /'
fi

echo ""
# Achado 3 do revisor em Codex (2026-09-08): `--agente ../x` saia de agents/ e
# injetava qualquer arquivo no prompt. O nome tem de ser simples.
echo "== CASO 9c: --agente ../fora → exit 1, sem chamar o dublê ==="
CMD_OUT_9C="$RAIZ/cmd-9c.txt"
CMD_OUT_9C_M="$(cygpath -m "$CMD_OUT_9C" 2>/dev/null || printf '%s' "$CMD_OUT_9C")"
rm -f "$CMD_OUT_9C"
saida_9c=$(DUBLE_MODO=ok DUBLE_CMD_OUT="$CMD_OUT_9C_M" RFM_TEST=1 CODEX_CMD="node $DUBLE_M" \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente ../fora \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" 2>&1)
exit_9c=$?
if [ "$exit_9c" = "1" ] && echo "$saida_9c" | grep -q "nome simples" && [ ! -f "$CMD_OUT_9C" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 9c: agente com '..' recusado, exit 1, dublê não chamado"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 9c: esperava exit 1 com 'nome simples' e dublê ausente, veio exit $exit_9c"
  echo "$saida_9c" | head -3 | sed 's/^/    /'
fi

echo ""
# Ate a rodada 2 do revisar (2026-09-08) nenhum caso rodava SEM --saida: o
# caminho do -o temporario (criar em tmpdir, ler, apagar) nunca disparava em
# teste. O dublê em modo parecer grava no -o real que o script montou; o caso
# confere que o stdout e o conteudo do -o e que o arquivo nao fica em tmpdir.
# O ramo "unlink falha mas o texto lido sobrevive" continua coberto so por
# leitura: nao ha jeito portavel de prender um arquivo em bash.
echo "== CASO 10: sem --saida → -o temporário lido, devolvido e apagado ==="
CMD_OUT_10="$RAIZ/cmd-10.txt"
CMD_OUT_10_M="$(cygpath -m "$CMD_OUT_10" 2>/dev/null || printf '%s' "$CMD_OUT_10")"
rm -f "$CMD_OUT_10"
saida_10=$(DUBLE_MODO=parecer DUBLE_PARECER="TEXTO DO -O TEMPORARIO" DUBLE_CMD_OUT="$CMD_OUT_10_M" \
  RFM_TEST=1 CODEX_CMD="node $DUBLE_M" \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" 2>/dev/null)
exit_10=$?
O_TMP="$(sed -n 's/.* -o "\([^"]*\)".*/\1/p' "$CMD_OUT_10" 2>/dev/null | head -1)"
O_TMP_U="$(cygpath -u "$O_TMP" 2>/dev/null || printf '%s' "$O_TMP")"
if [ "$exit_10" = "0" ] && [ "$saida_10" = "TEXTO DO -O TEMPORARIO" ] && [ -n "$O_TMP" ] && [ ! -e "$O_TMP_U" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 10: stdout veio do -o temporário e o arquivo foi apagado"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 10: exit $exit_10, stdout '$saida_10', -o '$O_TMP' existe: $([ -e "$O_TMP_U" ] && echo sim || echo nao)"
fi

echo ""
# D5 de 2026-09-08-validar-ponte-codex-ao-vivo: o codex exec real sem cota sai 1
# com a causa enterrada atras do banner. O script passa a sair 75 (passageiro)
# com uma linha propria `codex sem cota: ...` logo depois de `comando:`.
echo "== CASO 11: dublê sem cota → exit 75, linha 'codex sem cota:' no stderr, -o não fica ==="
CMD_OUT_11="$RAIZ/cmd-11.txt"
CMD_OUT_11_M="$(cygpath -m "$CMD_OUT_11" 2>/dev/null || printf '%s' "$CMD_OUT_11")"
ERR_11="$RAIZ/err-11.txt"
rm -f "$CMD_OUT_11"
DUBLE_MODO=semcota DUBLE_CMD_OUT="$CMD_OUT_11_M" RFM_TEST=1 CODEX_CMD="node $DUBLE_M" \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" > /dev/null 2> "$ERR_11"
exit_11=$?
O_TMP_11="$(sed -n 's/.* -o "\([^"]*\)".*/\1/p' "$CMD_OUT_11" 2>/dev/null | head -1)"
O_TMP_11_U="$(cygpath -u "$O_TMP_11" 2>/dev/null || printf '%s' "$O_TMP_11")"
LINHA_11="$(sed -n '2p' "$ERR_11")"
if [ "$exit_11" = "75" ] && printf '%s' "$LINHA_11" | grep -q "^codex sem cota: You've hit your usage limit" && printf '%s' "$LINHA_11" | grep -q "5:41 PM" && [ -f "$CMD_OUT_11" ] && [ ! -e "$O_TMP_11_U" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 11: exit 75, 2ª linha do stderr é 'codex sem cota: ...' com a hora, dublê chamado, -o ausente"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 11: exit $exit_11; 2ª linha do stderr: '$LINHA_11'; dublê chamado: $([ -f "$CMD_OUT_11" ] && echo sim || echo nao)"
  head -4 "$ERR_11" | sed 's/^/    /'
fi

echo ""
# CRITICO 1 do revisar de 2026-09-08: a checagem de cota rodava com exit 0 e um
# parecer legitimo que citasse "usage limit" virava falso "sem cota" (exit 75,
# parecer descartado). Com exit 0 o texto e resposta do agente, ponto.
echo "== CASO 12: exit 0 com 'usage limit' no parecer → exit 0 e stdout intacto (não é cota) ==="
PARECER_12="PARECER: APROVADO — o design D5 assume que o Codex sempre hit your usage limit de forma clara"
saida_12=$(DUBLE_MODO=parecer DUBLE_PARECER="$PARECER_12" RFM_TEST=1 CODEX_CMD="node $DUBLE_M" \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" 2>/dev/null)
exit_12=$?
if [ "$exit_12" = "0" ] && [ "$saida_12" = "$PARECER_12" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 12: parecer que cita 'usage limit' com exit 0 passa intacto, exit 0"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 12: exit $exit_12, stdout '$saida_12'"
fi

echo ""
echo "== CASO 13: --saida com metacaractere de injeção (aspas) → recusado, exit 1 ==="
CMD_OUT_13="$RAIZ/cmd-13.txt"
CMD_OUT_13_M="$(cygpath -m "$CMD_OUT_13" 2>/dev/null || printf '%s' "$CMD_OUT_13")"
rm -f "$CMD_OUT_13"
saida_13=$(DUBLE_MODO=ok DUBLE_CMD_OUT="$CMD_OUT_13_M" RFM_TEST=1 CODEX_CMD="node $DUBLE_M" \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" \
  --saida 'x"; echo pwned; "' 2>&1)
exit_13=$?
if [ "$exit_13" = "1" ] && echo "$saida_13" | grep -q "valor invalido: --saida" && [ ! -f "$CMD_OUT_13" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 13: --saida com aspas recusado, exit 1, dublê não chamado"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 13: esperava exit 1 com 'valor invalido: --saida' e dublê ausente, veio exit $exit_13"
  echo "$saida_13" | head -3 | sed 's/^/    /'
fi

echo ""
echo "== CASO 14: --worktree com & → recusado, exit 1 ==="
CMD_OUT_14="$RAIZ/cmd-14.txt"
CMD_OUT_14_M="$(cygpath -m "$CMD_OUT_14" 2>/dev/null || printf '%s' "$CMD_OUT_14")"
rm -f "$CMD_OUT_14"
saida_14=$(DUBLE_MODO=ok DUBLE_CMD_OUT="$CMD_OUT_14_M" RFM_TEST=1 CODEX_CMD="node $DUBLE_M" \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$(pwd)&echo" \
  --escreve false \
  --briefing-file "$BRIEFING" 2>&1)
exit_14=$?
if [ "$exit_14" = "1" ] && echo "$saida_14" | grep -q "valor invalido: --worktree" && [ ! -f "$CMD_OUT_14" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 14: --worktree com & recusado, exit 1, dublê não chamado"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 14: esperava exit 1 com 'valor invalido: --worktree' e dublê ausente, veio exit $exit_14"
fi

echo ""
echo "== CASO 15: --saida com espaço (caminho legal) → aceito ==="
SAIDA_15="$RAIZ/dir com espaco/x.md"
mkdir -p "$(dirname "$SAIDA_15")"
SAIDA_15_M="$(cygpath -m "$SAIDA_15" 2>/dev/null || printf '%s' "$SAIDA_15")"
CMD_OUT_15="$RAIZ/cmd-15.txt"
CMD_OUT_15_M="$(cygpath -m "$CMD_OUT_15" 2>/dev/null || printf '%s' "$CMD_OUT_15")"
rm -f "$CMD_OUT_15"
saida_15=$(DUBLE_MODO=ok DUBLE_CMD_OUT="$CMD_OUT_15_M" DUBLE_SAIDA="$SAIDA_15_M" RFM_TEST=1 CODEX_CMD="node $DUBLE_M" \
  node "$PLUGIN/scripts/despachar-codex.cjs" \
  --agente revisor \
  --worktree "$WTE" \
  --escreve false \
  --briefing-file "$BRIEFING" \
  --saida "$SAIDA_15_M" 2>&1)
exit_15=$?
if [ "$exit_15" = "0" ] && [ -f "$CMD_OUT_15" ]; then
  ok=$((ok + 1))
  echo "  ok   caso 15: --saida com espaço aceito, exit 0, dublê chamado"
else
  falhou=$((falhou + 1))
  echo "  FALHA caso 15: esperava exit 0 e dublê chamado, veio exit $exit_15"
fi

echo ""
echo "== RESULTADO =="
echo "resultado: $ok ok, $falhou falha(s)"
if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
