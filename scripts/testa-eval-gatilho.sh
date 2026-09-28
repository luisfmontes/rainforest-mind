#!/bin/bash
# Bateria para scripts/eval-gatilho.sh -- trava de gatilho sob demanda (#302).
# Uso: bash scripts/testa-eval-gatilho.sh
#
# Roda inteiramente contra um `claude` FALSO (fixture bash criada aqui, ver
# "claude falso" abaixo) -- NUNCA contra o CLI real, e NUNCA rede, credencial
# ou custo (D4, docs/rainforest/design/zerar-issues-11.md). O falso decide o
# exit por um "roteiro" (arquivo com um exit code por linha, consumido na
# ordem das chamadas) e registra cada chamada (cwd + argumentos) num log, que
# os casos abaixo conferem.
#
# Cobre as letras (a)-(f) do "pronto quando" da tarefa 2 do plano
# docs/rainforest/planos/zerar-issues-11.md, incluindo o caso de nome exato
# "trava: caso com 1 de 3 rodadas verdes reprova" (o alvo da mutacao
# declarada: trocar a linha da decisao de maioria por `if true` tem que
# deixar exatamente este caso vermelho).

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SRC/scripts/eval-gatilho.sh"

# Caixa de areia fora do worktree (mesmo padrao de scripts/testa-despachar-codex.sh):
# nada e escrito na arvore real, e a limpeza roda uma vez so, no fim.
RAIZ_BASE="/tmp/test-eval-gatilho-$$"
mkdir -p "$RAIZ_BASE"
limpa() {
  cd "$SRC" 2>/dev/null || cd /
  rm -rf "$RAIZ_BASE" 2>/dev/null
}
trap limpa EXIT

echo "(caixa de areia: $RAIZ_BASE)"
echo ""

ok=0
falhou=0

# ============================================================ claude falso
#
# Variaveis de ambiente que ele le:
#   FAKE_CLAUDE_LOG      arquivo onde grava cada chamada (cwd + argumentos)
#   FAKE_CLAUDE_ROTEIRO   arquivo com um exit code por linha, um por chamada
#   FAKE_CLAUDE_CONTADOR  arquivo de estado (quantas chamadas ja consumiram
#                         o roteiro) -- precisa persistir entre invocacoes,
#                         porque cada chamada e' um processo novo
#   FAKE_CLAUDE_MODO      "normal" (padrao): reprova (exit 1) sozinho, sem
#                         nem olhar o roteiro, quando acha a marca
#                         SABOTADA-PARA-MUTACAO em qualquer skills/*/SKILL.md
#                         sob o cwd recebido -- e assim que o CLI real
#                         reprovaria uma description que nao dispara mais a
#                         skill (letra d). "cego": ignora a marca e segue so
#                         pelo roteiro -- simula uma trava que NAO percebe a
#                         mutacao, para testar o outro lado do contrato (exit
#                         3 de "mutacao").
FAKE_CLAUDE="$RAIZ_BASE/claude"
cat > "$FAKE_CLAUDE" << 'CLAUDEEOF'
#!/bin/bash
set -u
LOG="${FAKE_CLAUDE_LOG:?FAKE_CLAUDE_LOG nao definido}"
ROTEIRO="${FAKE_CLAUDE_ROTEIRO:?FAKE_CLAUDE_ROTEIRO nao definido}"
CONTADOR="${FAKE_CLAUDE_CONTADOR:?FAKE_CLAUDE_CONTADOR nao definido}"
MODO="${FAKE_CLAUDE_MODO:-normal}"

{
  printf 'cwd=%s' "$PWD"
  for a in "$@"; do printf ' arg=%q' "$a"; done
  printf '\n'
} >> "$LOG"

if [ "$MODO" = "normal" ]; then
  for f in skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    if grep -q 'SABOTADA-PARA-MUTACAO' "$f"; then
      echo "eval falso: description sabotada em $f, skill nao dispara mais" >&2
      exit 1
    fi
  done
fi

n=$(( $(cat "$CONTADOR" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$CONTADOR"
codigo=$(sed -n "${n}p" "$ROTEIRO")
[ -n "$codigo" ] || codigo=0
if [ "$codigo" = "2" ]; then
  echo "cost ceiling: teto de custo atingido (fake)" >&2
fi
exit "$codigo"
CLAUDEEOF
chmod +x "$FAKE_CLAUDE"

LOG="$RAIZ_BASE/log.txt"
ROTEIRO="$RAIZ_BASE/roteiro.txt"
CONTADOR="$RAIZ_BASE/contador.txt"

resetar() {
  : > "$LOG"
  : > "$ROTEIRO"
  rm -f "$CONTADOR"
}

# Um exit code por argumento, um por linha no roteiro.
escrever_roteiro() {
  : > "$ROTEIRO"
  local c
  for c in "$@"; do printf '%s\n' "$c" >> "$ROTEIRO"; done
}

rodar() {
  # rodar <sandbox> [MODO=x] -- <args do eval-gatilho.sh...>
  local sandbox="$1"; shift
  local modo="normal"
  if [ "${1:-}" = "cego" ]; then
    modo="cego"
    shift
  fi
  (
    cd "$sandbox" \
      && CLAUDE_BIN="$FAKE_CLAUDE" \
         FAKE_CLAUDE_LOG="$LOG" \
         FAKE_CLAUDE_ROTEIRO="$ROTEIRO" \
         FAKE_CLAUDE_CONTADOR="$CONTADOR" \
         FAKE_CLAUDE_MODO="$modo" \
         bash "$SCRIPT" "$@"
  )
}

contar_log() { wc -l < "$LOG" | tr -d ' '; }

# ================================================== SANDBOX1: casos genericos
# (sem git -- trava e baseline nao precisam de repositorio nenhum)
SANDBOX1="$RAIZ_BASE/sandbox1"
mkdir -p "$SANDBOX1/evals/gatilho-x-vs-y-pos1" "$SANDBOX1/evals/gatilho-x-vs-y-neg1"
cat > "$SANDBOX1/evals/gatilho-x-vs-y-pos1/case.yaml" << 'EOF'
schema_version: "1.0"
name: gatilho-x-vs-y-pos1
EOF
cat > "$SANDBOX1/evals/gatilho-x-vs-y-neg1/case.yaml" << 'EOF'
schema_version: "1.0"
name: gatilho-x-vs-y-neg1
EOF

# ============================================== SANDBOX2: repo git com a skill
# "foo" (para a letra d, mutacao) -- pos1/pos2/neg1 no par foo x bar.
SANDBOX2="$RAIZ_BASE/sandbox2"
mkdir -p "$SANDBOX2/skills/foo"
cat > "$SANDBOX2/skills/foo/SKILL.md" << 'EOF'
---
name: foo
description: Use quando o pedido for sobre foo de verdade, nunca sobre bar.
---

# Foo

Conteudo de teste, irrelevante para a bateria.
EOF
mkdir -p "$SANDBOX2/evals/gatilho-foo-vs-bar-pos1" "$SANDBOX2/evals/gatilho-foo-vs-bar-pos2" "$SANDBOX2/evals/gatilho-foo-vs-bar-neg1"
cat > "$SANDBOX2/evals/gatilho-foo-vs-bar-pos1/case.yaml" << 'EOF'
schema_version: "1.0"
name: gatilho-foo-vs-bar-pos1
EOF
cat > "$SANDBOX2/evals/gatilho-foo-vs-bar-pos2/case.yaml" << 'EOF'
schema_version: "1.0"
name: gatilho-foo-vs-bar-pos2
EOF
cat > "$SANDBOX2/evals/gatilho-foo-vs-bar-neg1/case.yaml" << 'EOF'
schema_version: "1.0"
name: gatilho-foo-vs-bar-neg1
EOF
(
  cd "$SANDBOX2" \
    && git init --quiet \
    && git config user.email "t@t" \
    && git config user.name "T" \
    && git add -A \
    && git commit --quiet -m inicial
)

# ===================================================================== CASOS

echo "== (a) trava chama o CLI 1x por caso e por rodada, com todas as flags obrigatorias =="
resetar
escrever_roteiro 0 0 0 0
saida=$(rodar "$SANDBOX1" trava --case "gatilho-x-vs-y-*" --rodadas 2 2>&1)
exit_obtido=$?
chamadas=$(contar_log)
cnt_pos1=$(grep -c 'arg=gatilho-x-vs-y-pos1' "$LOG" || true)
cnt_neg1=$(grep -c 'arg=gatilho-x-vs-y-neg1' "$LOG" || true)
if [ "$exit_obtido" = "0" ] && [ "$chamadas" = "4" ] && [ "${cnt_pos1:-0}" = "2" ] && [ "${cnt_neg1:-0}" = "2" ] \
   && grep -q -- 'arg=plugin arg=eval arg=.' "$LOG" \
   && grep -q -- 'arg=--trust-plugin' "$LOG" \
   && grep -q -- 'arg=--no-publish' "$LOG" \
   && grep -q -- 'arg=--ablation arg=none' "$LOG" \
   && grep -q -- 'arg=--runs arg=1' "$LOG" \
   && grep -q -- 'arg=--threshold arg=1.0' "$LOG"; then
  ok=$((ok + 1))
  echo "  ok   (a) 4 chamadas (2 casos x 2 rodadas), todas com as flags obrigatorias (exit $exit_obtido)"
else
  falhou=$((falhou + 1))
  echo "  FALHA (a): exit=$exit_obtido chamadas=$chamadas pos1=$cnt_pos1 neg1=$cnt_neg1"
  echo "$saida" | sed 's/^/         /' | head -10
  sed 's/^/         log: /' "$LOG" | head -10
fi

echo "== (a) sem --rodadas, o padrao e 3 =="
resetar
escrever_roteiro 0 0 0
saida=$(rodar "$SANDBOX1" trava --case "gatilho-x-vs-y-pos1" 2>&1)
exit_obtido=$?
chamadas=$(contar_log)
if [ "$exit_obtido" = "0" ] && [ "$chamadas" = "3" ]; then
  ok=$((ok + 1))
  echo "  ok   (a) sem --rodadas roda 3 vezes (padrao)"
else
  falhou=$((falhou + 1))
  echo "  FALHA (a) padrao de rodadas: exit=$exit_obtido chamadas=$chamadas"
  echo "$saida" | sed 's/^/         /' | head -10
fi

echo "== (a) --max-cost-usd e repassado ao CLI quando informado =="
resetar
escrever_roteiro 0
saida=$(rodar "$SANDBOX1" trava --case "gatilho-x-vs-y-pos1" --rodadas 1 --max-cost-usd 3.5 2>&1)
exit_obtido=$?
if [ "$exit_obtido" = "0" ] && grep -q -- 'arg=--max-cost-usd arg=3.5' "$LOG"; then
  ok=$((ok + 1))
  echo "  ok   (a) --max-cost-usd 3.5 aparece na chamada do CLI"
else
  falhou=$((falhou + 1))
  echo "  FALHA (a) --max-cost-usd: exit=$exit_obtido"
  sed 's/^/         log: /' "$LOG" | head -5
fi

echo "== (b) 2 de 3 rodadas verdes aprova o caso, trava sai 0 =="
resetar
escrever_roteiro 0 0 1
saida=$(rodar "$SANDBOX1" trava --case "gatilho-x-vs-y-pos1" --rodadas 3 2>&1)
exit_obtido=$?
if [ "$exit_obtido" = "0" ] && echo "$saida" | grep -q '^ok gatilho-x-vs-y-pos1 (2/3)$'; then
  ok=$((ok + 1))
  echo "  ok   (b) 2/3 rodadas verdes aprova (exit 0, linha 'ok gatilho-x-vs-y-pos1 (2/3)')"
else
  falhou=$((falhou + 1))
  echo "  FALHA (b) 2 de 3: exit=$exit_obtido"
  echo "$saida" | sed 's/^/         /' | head -10
fi

echo "== trava: caso com 1 de 3 rodadas verdes reprova =="
resetar
escrever_roteiro 0 1 1
saida=$(rodar "$SANDBOX1" trava --case "gatilho-x-vs-y-pos1" --rodadas 3 2>&1)
exit_obtido=$?
if [ "$exit_obtido" = "1" ] && echo "$saida" | grep -q '^FALHA gatilho-x-vs-y-pos1 (1/3)$'; then
  ok=$((ok + 1))
  echo "  ok   trava: caso com 1 de 3 rodadas verdes reprova (exit 1, linha 'FALHA gatilho-x-vs-y-pos1 (1/3)')"
else
  falhou=$((falhou + 1))
  echo "  FALHA trava: caso com 1 de 3 rodadas verdes reprova: exit=$exit_obtido"
  echo "$saida" | sed 's/^/         /' | head -10
fi

echo "== (c) exit 2 do CLI (teto de custo) aborta a trava na hora, com mensagem de teto =="
resetar
escrever_roteiro 0 2
saida=$(rodar "$SANDBOX1" trava --case "gatilho-x-vs-y-*" --rodadas 2 2>&1)
exit_obtido=$?
chamadas=$(contar_log)
if [ "$exit_obtido" = "2" ] && [ "$chamadas" = "2" ] && echo "$saida" | grep -qi 'teto'; then
  ok=$((ok + 1))
  echo "  ok   (c) aborta com exit 2 apos so 2 chamadas (nao chega a rodar as outras 2), mensagem cita teto"
else
  falhou=$((falhou + 1))
  echo "  FALHA (c): exit=$exit_obtido chamadas=$chamadas"
  echo "$saida" | sed 's/^/         /' | head -10
fi

echo "== (d) mutacao <skill>: detecta a sabotagem (trava fica vermelha), arvore real intacta, so roda positivos =="
resetar
escrever_roteiro 0 0 0
antes=$(cd "$SANDBOX2" && git status --porcelain)
saida=$(rodar "$SANDBOX2" mutacao foo --rodadas 1 2>&1)
exit_obtido=$?
depois=$(cd "$SANDBOX2" && git status --porcelain)
chamou_neg=$(grep -c 'arg=gatilho-foo-vs-bar-neg1' "$LOG" || true)
chamadas=$(contar_log)
if [ "$exit_obtido" = "0" ] && [ -z "$antes" ] && [ -z "$depois" ] && [ "${chamou_neg:-0}" = "0" ] && [ "$chamadas" = "2" ]; then
  ok=$((ok + 1))
  echo "  ok   (d) mutacao detectada (exit 0), arvore real intacta, so os 2 positivos chamados"
else
  falhou=$((falhou + 1))
  echo "  FALHA (d) deteccao: exit=$exit_obtido antes=[$antes] depois=[$depois] chamou_neg=$chamou_neg chamadas=$chamadas"
  echo "$saida" | sed 's/^/         /' | head -10
fi

echo "== (d) mutacao <skill>: quando o dible IGNORA a sabotagem, a trava fica verde e a mutacao acusa nao-deteccao (exit 3) =="
resetar
escrever_roteiro 0 0 0
antes=$(cd "$SANDBOX2" && git status --porcelain)
saida=$(rodar "$SANDBOX2" cego mutacao foo --rodadas 1 2>&1)
exit_obtido=$?
depois=$(cd "$SANDBOX2" && git status --porcelain)
if [ "$exit_obtido" = "3" ] && [ -z "$antes" ] && [ -z "$depois" ]; then
  ok=$((ok + 1))
  echo "  ok   (d) mutacao NAO detectada quando o dible ignora a sabotagem (exit 3), arvore real intacta"
else
  falhou=$((falhou + 1))
  echo "  FALHA (d) nao-deteccao: exit=$exit_obtido antes=[$antes] depois=[$depois]"
  echo "$saida" | sed 's/^/         /' | head -10
fi

echo "== (e) baseline chama o CLI 1x com --ablation with-without --runs 1 (sem --ablation none nem --threshold) =="
resetar
escrever_roteiro 0
saida=$(rodar "$SANDBOX1" baseline 2>&1)
exit_obtido=$?
chamadas=$(contar_log)
if [ "$exit_obtido" = "0" ] && [ "$chamadas" = "1" ] \
   && grep -q -- 'arg=--ablation arg=with-without' "$LOG" \
   && grep -q -- 'arg=--runs arg=1' "$LOG" \
   && ! grep -q -- 'arg=--ablation arg=none' "$LOG" \
   && ! grep -q -- 'arg=--threshold' "$LOG"; then
  ok=$((ok + 1))
  echo "  ok   (e) baseline: 1 chamada com --ablation with-without --runs 1"
else
  falhou=$((falhou + 1))
  echo "  FALHA (e) baseline flags: exit=$exit_obtido chamadas=$chamadas"
  sed 's/^/         log: /' "$LOG" | head -5
fi

echo "== (e) baseline repassa o exit code do CLI =="
resetar
escrever_roteiro 5
saida=$(rodar "$SANDBOX1" baseline 2>&1)
exit_obtido=$?
if [ "$exit_obtido" = "5" ]; then
  ok=$((ok + 1))
  echo "  ok   (e) baseline repassa exit 5 do CLI"
else
  falhou=$((falhou + 1))
  echo "  FALHA (e) passthrough: esperava exit 5, veio $exit_obtido"
fi

echo "== (f) CLAUDE_BIN sem executavel resolvivel sai 127 com mensagem =="
saida=$(cd "$SANDBOX1" && CLAUDE_BIN="$RAIZ_BASE/nao-existe-claude-xyz" bash "$SCRIPT" trava 2>&1)
exit_obtido=$?
if [ "$exit_obtido" = "127" ] && echo "$saida" | grep -qi 'nao resolve'; then
  ok=$((ok + 1))
  echo "  ok   (f) CLAUDE_BIN invalido sai 127 com mensagem"
else
  falhou=$((falhou + 1))
  echo "  FALHA (f): exit=$exit_obtido"
  echo "$saida" | sed 's/^/         /' | head -5
fi

echo ""
echo "resultado: $ok ok, $falhou falha(s)"
if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
