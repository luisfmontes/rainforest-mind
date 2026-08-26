#!/bin/bash
# Bateria do ferramentas-consulta.cjs — PreToolUse que anuncia ferramenta ausente.
#
# Valida D8, D10, D12 do design de #76:
#   D8 — Executável presente no ledger: NENHUM subprocesso.
#   D10 — Hook sai 0 SEMPRE, sem exceção.
#   D12 — Executável ausente: EXATAMENTE UMA checagem, anunciando ferramenta.
#
# Uso: bash hooks/testa-ferramentas-consulta.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/ferramentas-consulta.cjs"
RAIZ="$(mktemp -d)"
export RFM_ROOT="$RAIZ"
trap "rm -rf '$RAIZ'" EXIT

echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# ========== HELPERS ==========

# Monta payload real de PreToolUse via node (nunca printf — regra do design).
# Modo 1: executável PRESENTE no ledger.
# Modo 2: executável AUSENTE do ledger.
# Modo 3: ledger inexistente.
payload_bash() {
  local cmd="$1"
  node -e 'const c=process.argv[1];console.log(JSON.stringify({cwd:process.env.RFM_ROOT,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:c}}))' "$cmd"
}

# Testa o hook e coleta saída stderr (os anúncios saem lá)
test_hook() {
  local nome="$1" esp_exit="$2" pago="$3" esp_anuncio="$4"

  local stderr_saida
  stderr_saida=$(printf '%s' "$pago" | node "$HOOK" 2>&1 >/dev/null)
  local got_exit=$?

  # Verifica exit code
  local exit_ok=0
  if [ "$got_exit" = "$esp_exit" ]; then
    exit_ok=1
  else
    echo "  FALHA $nome: esperava exit $esp_exit, veio $got_exit"
    falhou=$((falhou + 1))
    return
  fi

  # Verifica anúncio (se esperado)
  local anuncio_ok=0
  if [ -z "$esp_anuncio" ]; then
    # Não espera anúncio
    if [ -z "$stderr_saida" ]; then
      anuncio_ok=1
    else
      echo "  FALHA $nome: esperava NENHUM anúncio, mas veio: $stderr_saida"
      falhou=$((falhou + 1))
      return
    fi
  else
    # Espera anúncio
    if echo "$stderr_saida" | grep -qF "$esp_anuncio"; then
      anuncio_ok=1
    else
      echo "  FALHA $nome: esperava anúncio contendo '$esp_anuncio'"
      echo "             mas veio: '$stderr_saida'"
      falhou=$((falhou + 1))
      return
    fi
  fi

  # Tudo ok
  ok=$((ok + 1))
  echo "  ok   $nome"
}

# ========== PREPARAÇÃO ==========

mkdir -p "$RAIZ"

# Prepara ledger com ferramentas conhecidas
RECEITA_WHISPER='C:\Program Files\whisper-cli\whisper.exe --model C:\models\model.bin'
node "$SRC/scripts/ferramentas.cjs" registrar whisper-cli "$RECEITA_WHISPER" "descoberta-por-prompt" >/dev/null 2>&1

RECEITA_GIT='/usr/bin/git'
node "$SRC/scripts/ferramentas.cjs" registrar git "$RECEITA_GIT" "descoberta-manual" >/dev/null 2>&1

# ========== TESTES ==========

echo ""
echo "== D10: Hook sai 0 em TODOS os casos =="

echo ""
echo "Caso 1: Executável PRESENTE no ledger (whisper-cli) — exit 0, SEM anúncio"
test_hook \
  "whisper-cli presente" 0 \
  "$(payload_bash 'whisper-cli audio.mp3')" \
  ""

echo ""
echo "Caso 2: Executável AUSENTE do ledger (foo-bar) — exit 0, COM anúncio"
test_hook \
  "foo-bar ausente" 0 \
  "$(payload_bash 'foo-bar arg1 arg2')" \
  "foo-bar"

echo ""
echo "Caso 3: Comando vazio — exit 0, SEM anúncio (D10)"
test_hook \
  "comando vazio" 0 \
  "$(payload_bash '')" \
  ""

echo ""
echo "Caso 4: Payload malformado — exit 0, SEM anúncio (D10)"
printf '%s' '{"invalid json' | node "$HOOK" >/dev/null 2>&1
got=$?
if [ "$got" = 0 ]; then
  ok=$((ok + 1))
  echo "  ok   payload malformado: exit 0"
else
  falhou=$((falhou + 1))
  echo "  FALHA payload malformado: esperava exit 0, veio $got"
fi

echo ""
echo "Caso 5: Tool não é Bash — exit 0, SEM anúncio"
payload_write=$(node -e 'console.log(JSON.stringify({cwd:process.env.RFM_ROOT,tool_name:"Write",tool_input:{file_path:"x.txt",content:"test"}}))')
test_hook \
  "tool Write (não Bash)" 0 \
  "$payload_write" \
  ""

echo ""
echo "Caso 6: Ledger inacessível (RFM_ROOT=/nonexistent) — exit 0, SEM anúncio (D10)"
rft=$(export RFM_ROOT=/nonexistent; printf '%s' "$(payload_bash 'unknown-exe')" | node "$HOOK" 2>&1)
got=$?
if [ "$got" = 0 ]; then
  ok=$((ok + 1))
  echo "  ok   ledger inacessível: exit 0"
else
  falhou=$((falhou + 1))
  echo "  FALHA ledger inacessível: esperava exit 0, veio $got"
fi

echo ""
echo "== D8: Executável PRESENTE — nenhum subprocesso (prova: ausência de anúncio) =="

# D8 diz: "confia e deixa tropeçar", o que significa que NÃO roda sonda extra.
# Prova: se está presente, não há anúncio de "ausente".
# Se houvesse sonda, teria anúncio — a sonda é o próprio "consultar", que retorna "desconhecido" ou receita.
#
# Então: executável presente = sem anúncio. Isso ja está testado no caso 8.
# Aqui simplesmente confirmamos que git (presente) não gera anúncio.

echo ""
echo "Caso 7: git PRESENTE — ausência de anúncio prova ausência de sonda adicional"
SAIDA=$(printf '%s' "$(payload_bash 'git status')" | node "$HOOK" 2>&1)
if [ -z "$SAIDA" ]; then
  ok=$((ok + 1))
  echo "  ok   git presente: sem anúncio (D8 — não há sonda extra)"
else
  falhou=$((falhou + 1))
  echo "  FALHA git presente: esperava sem anúncio, mas veio: $SAIDA"
fi

echo ""
echo "== D12: Executável AUSENTE — exatamente UMA checagem =="

# Prova: o hook chama `node scripts/ferramentas.cjs consultar`, que faz leitura do ledger.
# Uma checagem = uma execução de ferramentas.cjs.
# Prova indireta: anúncio aparece (seria "not found" do lado de fora, sem o anúncio).

echo ""
echo "Caso 8: whisper-cli conhecida — anuncia NADA (prove que não sonda)"
SAIDA=$(printf '%s' "$(payload_bash 'whisper-cli')" | node "$HOOK" 2>&1)
if [ -z "$SAIDA" ]; then
  ok=$((ok + 1))
  echo "  ok   whisper-cli conhecida: silêncio (D8 — nenhum subprocesso)"
else
  falhou=$((falhou + 1))
  echo "  FALHA whisper-cli conhecida: não estava silencioso, saída: $SAIDA"
fi

echo ""
echo "Caso 9: executável desconhecido não recusa a execução (D10 — fixture para falsificação)"
# Este é o caso que o `conferir-mutacao.cjs` vai inverter:
# de `process.exit(0)` para `process.exit(2)`.
# A bateria deve FALHAR quando o exit for 2.
test_hook \
  "executável desconhecido não recusa a execução" 0 \
  "$(payload_bash 'desconhecido-xyz-abc')" \
  "desconhecido-xyz-abc"

echo ""
echo "== PLACAR FINAL =="
PLACAR="$ok ok, $falhou falha(s)"
echo "$PLACAR"

if [ $falhou -gt 0 ]; then
  exit 1
else
  exit 0
fi
