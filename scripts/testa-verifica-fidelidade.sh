#!/bin/bash
# Bateria do scripts/verifica-fidelidade-fixture.cjs — checador de fidelidade de fixtures
# Uso: bash scripts/testa-verifica-fidelidade.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

VERIFICADOR="node $SRC/scripts/verifica-fidelidade-fixture.cjs"

ok=0; falhou=0

echo "== 1. Teste A: Fixture com type válido (deve passar) =="
FIXTURE_A="$CAIXA/fixture-a.jsonl"
cat > "$FIXTURE_A" <<'EOF'
{"type":"user","message":{"role":"user","content":"teste"},"timestamp":"2026-08-19T10:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":"resposta"},"timestamp":"2026-08-19T10:00:01Z"}
EOF

REAL_A="$CAIXA/real-a.jsonl"
cat > "$REAL_A" <<'EOF'
{"type":"user","message":{"role":"user","content":"conteúdo real"},"timestamp":"2026-08-19T10:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":"resposta real"},"timestamp":"2026-08-19T10:00:01Z"}
EOF

$VERIFICADOR "$FIXTURE_A" --real "$REAL_A" >/dev/null 2>&1
EXIT_A=$?
if [ $EXIT_A -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    Fixture com types válidos passa (exit 0)"
else
  falhou=$((falhou+1)); echo "  FALHA Fixture com types válidos deveria passar, saiu $EXIT_A"
fi

echo
echo "== 2. Teste B: Fixture com type inválido (deve falhar) =="
FIXTURE_B="$CAIXA/fixture-b.jsonl"
cat > "$FIXTURE_B" <<'EOF'
{"type":"usuario","message":{"role":"user","content":"teste"},"timestamp":"2026-08-19T10:00:00Z"}
EOF

$VERIFICADOR "$FIXTURE_B" --real "$REAL_A" >/dev/null 2>&1
EXIT_B=$?
if [ $EXIT_B -ne 0 ]; then
  ok=$((ok+1)); echo "  ok    Fixture com type inválido falha (exit $EXIT_B)"
else
  falhou=$((falhou+1)); echo "  FALHA Fixture com type inválido deveria falhar, passou"
fi

echo
echo "== 3. Teste C: Fixture com campo extra (deve falhar) =="
FIXTURE_C="$CAIXA/fixture-c.jsonl"
cat > "$FIXTURE_C" <<'EOF'
{"type":"user","message":{"role":"user","content":"teste"},"timestamp":"2026-08-19T10:00:00Z","campo_extra":"nao existe no real"}
EOF

$VERIFICADOR "$FIXTURE_C" --real "$REAL_A" >/dev/null 2>&1
EXIT_C=$?
if [ $EXIT_C -ne 0 ]; then
  ok=$((ok+1)); echo "  ok    Fixture com campo extra falha (exit $EXIT_C)"
else
  falhou=$((falhou+1)); echo "  FALHA Fixture com campo extra deveria falhar, passou"
fi

echo
echo "== 4. Teste D: Sem transcrito real disponivel (deve falhar com aviso, NUNCA passar silencioso) =="
# Achado 5 da tarefa 22: a tarefa 16 exige que a ausencia de transcrito real
# saia 1 com aviso, nunca 0 silencioso — esse ramo (verifica-fidelidade-
# fixture.cjs:76-80) nao tinha cobertura nenhuma nesta bateria. Sem --real e
# sem CLAUDE_CONFIG_DIR apontando pra um projects/ com .jsonl, o verificador
# tem que recusar com exit != 0, nunca validar por omissao.
FIXTURE_D="$CAIXA/fixture-d.jsonl"
cat > "$FIXTURE_D" <<'EOF'
{"type":"user","message":{"role":"user","content":"teste"},"timestamp":"2026-08-19T10:00:00Z"}
EOF

CONFIG_DIR_SEM_TRANSCRITO="$CAIXA/config-dir-sem-projects"
SAIDA_D=$(CLAUDE_CONFIG_DIR="$CONFIG_DIR_SEM_TRANSCRITO" $VERIFICADOR "$FIXTURE_D" 2>&1)
EXIT_D=$?

if [ $EXIT_D -ne 0 ]; then
  ok=$((ok+1)); echo "  ok    Sem transcrito real disponivel falha (exit $EXIT_D), nunca passa silencioso"
else
  falhou=$((falhou+1)); echo "  FALHA Sem transcrito real deveria falhar, passou silenciosamente com exit 0"
fi

if echo "$SAIDA_D" | grep -q "Sem transcrito real disponivel"; then
  ok=$((ok+1)); echo "  ok    aviso explicito impresso (falha nunca silenciosa)"
else
  falhou=$((falhou+1)); echo "  FALHA nao imprimiu o aviso esperado"
  echo "$SAIDA_D" | sed 's/^/         /'
fi

echo
echo "== 5. Mutacao: prova que o Teste D pega regressao (numa COPIA, nunca no rastreado) =="
# Se alguem silenciar esse ramo (trocar o process.exit(1) por process.exit(0)
# quando nao ha transcrito real), o Teste D acima tem que virar vermelho. A
# mutacao roda numa copia em /tmp — o arquivo rastreado nunca e tocado.
MUT_DIR="$(mktemp -d)"
cp "$SRC/scripts/verifica-fidelidade-fixture.cjs" "$MUT_DIR/mutado.cjs"

cat > "$MUT_DIR/muta-sem-transcrito.cjs" <<'MUTEOF'
const fs = require('fs');
const alvo = process.env.ALVO;
const original = fs.readFileSync(alvo, 'utf8');
const trecho = "console.error('Fixture nao pode ser validado como ok sem transcrito real.');\n    process.exit(1);";
if (!original.includes(trecho)) {
  console.error('TRECHO_NAO_ENCONTRADO');
  process.exit(1);
}
const mutado = trecho.replace('process.exit(1);', 'process.exit(0); // MUTACAO: silencia a ausencia de transcrito real');
fs.writeFileSync(alvo, original.replace(trecho, mutado));
console.log('MUTADO');
MUTEOF

MUTA_OUT=$(ALVO="$MUT_DIR/mutado.cjs" node "$MUT_DIR/muta-sem-transcrito.cjs" 2>&1)
if echo "$MUTA_OUT" | grep -q "^MUTADO$"; then
  ok=$((ok+1)); echo "  ok    mutacao aplicada na copia (process.exit(1) -> process.exit(0))"
else
  falhou=$((falhou+1)); echo "  FALHA nao consegui mutar a copia — o texto do verificador pode ter mudado"
  echo "$MUTA_OUT" | sed 's/^/         /'
fi

SAIDA_D_MUTADA=$(CLAUDE_CONFIG_DIR="$CONFIG_DIR_SEM_TRANSCRITO" node "$MUT_DIR/mutado.cjs" "$FIXTURE_D" 2>&1)
EXIT_D_MUTADO=$?

if [ $EXIT_D_MUTADO -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    mutacao pegou: copia com o bug reintroduzido passa silenciosamente (exit 0) — o Teste D real acima acusaria isso"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao nao reproduziu o bug (copia mutada saiu $EXIT_D_MUTADO, esperava 0)"
fi

rm -rf "$MUT_DIR"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
