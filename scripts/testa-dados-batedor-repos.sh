#!/bin/bash
set -e

# Teste do resolvodor de raiz de dados em vigias/dados-batedor-repos.js
# Roda em caixa de areia (HOME/USERPROFILE temporário) com ideias.jsonl fabricado.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Cria caixa de areia
SANDBOX=$(mktemp -d)
cleanup() {
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

export USERPROFILE="$SANDBOX"
export HOME="$SANDBOX"

# Limpa RFM_ROOT para testar o default (cadeia de resolução)
unset RFM_ROOT

# ==============================================================================
# TESTE 1: sem RFM_ROOT, com raiz de dados fabricada, reporta N ideias abertas
# ==============================================================================
echo "=== TESTE 1: Resolve raiz de dados sem RFM_ROOT ==="

# Cria ~/.rainforest com ideias.jsonl
mkdir -p "$SANDBOX/.rainforest"
cat > "$SANDBOX/.rainforest/ideias.jsonl" << 'EOF'
{"id":"idea-1","tipo":"ideia","status":"plantada","titulo":"Primeira ideia","projeto":"teste","plantada_em":"2026-08-20T10:00:00Z"}
{"id":"idea-2","tipo":"ideia","status":"plantada","titulo":"Segunda ideia","projeto":"teste","plantada_em":"2026-08-21T10:00:00Z"}
{"id":"obs-1","tipo":"observacao","status":"plantada","titulo":"Primeira observacao","projeto":"teste","plantada_em":"2026-08-22T10:00:00Z"}
{"id":"idea-3","tipo":"ideia","status":"colhida","titulo":"Colhida (nao conta)","projeto":"teste","colhida_em":"2026-08-23T10:00:00Z"}
EOF

SAIDA=$(node "$REPO_ROOT/vigias/dados-batedor-repos.js")
IDEIAS=$(echo "$SAIDA" | grep "^IDEIAS ABERTAS" | grep -oE '\([0-9]+\)' | grep -oE '[0-9]+')
OBS=$(echo "$SAIDA" | grep "^OBSERVACOES DA REGRA 13 ABERTAS" | grep -oE '\([0-9]+\)' | grep -oE '[0-9]+')

echo "Ideias abertas encontradas: $IDEIAS (esperado: 2)"
echo "Observacoes abertas encontradas: $OBS (esperado: 1)"

[ "$IDEIAS" = "2" ] || { echo "FALHA: esperava 2 ideias, encontrou $IDEIAS"; exit 1; }
[ "$OBS" = "1" ] || { echo "FALHA: esperava 1 observação, encontrou $OBS"; exit 1; }
echo "✓ TESTE 1 passou"
echo

# ==============================================================================
# TESTE 2: propostas de relatorio — so os 4 mais recentes, so `**Pn — titulo**`
# ==============================================================================
echo "=== TESTE 2: Propostas de relatorio (plugin FABRICADO, so os 4 mais recentes) ==="

# Ate 2026-09-04 este teste lia os relatorios REAIS do repositorio e exigia
# "nao-zero": media conteudo, nao codigo. Bastou o fluxo do lote 3 gravar dois
# handovers sem proposta para os 4 relatorios mais recentes ficarem sem
# `**Pn —**` e a bateria virar vermelha sem uma linha de codigo mudar. O script
# ancora `relatorios/` na pasta acima dele (PLUGIN), entao o que ele precisa do
# plugin (o proprio script + hooks/lib/raiz.cjs) vai para uma caixa com
# relatorios fabricados: 5 arquivos, 3 propostas nos 4 mais recentes e 2 no
# quinto, que NAO podem contar. A contagem esperada e exata, nao "nao-zero".
PLUGIN_FAKE="$SANDBOX/plugin"
mkdir -p "$PLUGIN_FAKE/vigias" "$PLUGIN_FAKE/hooks/lib" "$PLUGIN_FAKE/relatorios"
cp "$REPO_ROOT/vigias/dados-batedor-repos.js" "$PLUGIN_FAKE/vigias/"
cp "$REPO_ROOT/hooks/lib/raiz.cjs" "$PLUGIN_FAKE/hooks/lib/"
printf '%s\n' '# Um' '' '**P1 — Abrir a Issue do vetor citado**' 'texto' '**P2 — Consertar a bateria**' > "$PLUGIN_FAKE/relatorios/2026-09-05-um.md"
printf '%s\n' '# Dois' 'handover sem proposta' > "$PLUGIN_FAKE/relatorios/2026-09-04-dois.md"
printf '%s\n' '# Tres' '**P1 - Com hifen simples tambem conta**' > "$PLUGIN_FAKE/relatorios/2026-09-03-tres.md"
printf '%s\n' '# Quatro' 'P3 sem negrito nao conta' '  **P4 — indentado nao conta**' > "$PLUGIN_FAKE/relatorios/2026-09-02-quatro.md"
printf '%s\n' '# Cinco (fora dos 4 mais recentes)' '**P1 — nao pode contar**' '**P2 — nem esta**' > "$PLUGIN_FAKE/relatorios/2026-09-01-cinco.md"

SAIDA2=$(node "$PLUGIN_FAKE/vigias/dados-batedor-repos.js")
PROPOSTAS=$(echo "$SAIDA2" | grep "^PROPOSTAS NOS 4 RELATORIOS" | grep -oE '\([0-9]+\)' | grep -oE '[0-9]+') || PROPOSTAS="(linha ausente)"
echo "Propostas encontradas: $PROPOSTAS (esperado: 3)"

[ "$PROPOSTAS" = "3" ] || { echo "FALHA: esperava 3 propostas, encontrou $PROPOSTAS"; echo "$SAIDA2"; exit 1; }
if echo "$SAIDA2" | grep -q "2026-09-01-cinco"; then
  echo "FALHA: o quinto relatorio (fora dos 4 mais recentes) entrou na contagem"; exit 1
fi
echo "✓ TESTE 2 passou (3 propostas exatas, quinto relatorio ignorado)"
echo

# ==============================================================================
# TESTE 3: RFM_ROOT explícito vence a cadeia
# ==============================================================================
echo "=== TESTE 3: RFM_ROOT explícito vence a cadeia ==="

# Cria outra raiz de dados em pasta alternativa
ALT_ROOT=$(mktemp -d)
cleanup_alt() {
  rm -rf "$ALT_ROOT"
}
trap "cleanup; cleanup_alt" EXIT

mkdir -p "$ALT_ROOT"
cat > "$ALT_ROOT/ideias.jsonl" << 'EOF'
{"id":"alt-idea-1","tipo":"ideia","status":"plantada","titulo":"Idea alternativa 1","projeto":"alt","plantada_em":"2026-08-20T10:00:00Z"}
{"id":"alt-idea-2","tipo":"ideia","status":"plantada","titulo":"Idea alternativa 2","projeto":"alt","plantada_em":"2026-08-21T10:00:00Z"}
{"id":"alt-idea-3","tipo":"ideia","status":"plantada","titulo":"Idea alternativa 3","projeto":"alt","plantada_em":"2026-08-22T10:00:00Z"}
EOF

export RFM_ROOT="$ALT_ROOT"
SAIDA_ALT=$(node "$REPO_ROOT/vigias/dados-batedor-repos.js")
IDEIAS_ALT=$(echo "$SAIDA_ALT" | grep "^IDEIAS ABERTAS" | grep -oE '\([0-9]+\)' | grep -oE '[0-9]+')

echo "Ideias com RFM_ROOT alternativo: $IDEIAS_ALT (esperado: 3)"
[ "$IDEIAS_ALT" = "3" ] || { echo "FALHA: esperava 3 ideias, encontrou $IDEIAS_ALT"; exit 1; }
echo "✓ TESTE 3 passou"
echo

# ==============================================================================
# TESTE 4: raiz de dados ausente — saida marca como indisponivel, nao como zero
# ==============================================================================
echo "=== TESTE 4: Raiz de dados ausente ==="

# Limpa a caixa de areia: sem ~/.rainforest, sem projeto/.rainforest
rm -rf "$SANDBOX/.rainforest"

export HOME="$SANDBOX"
export USERPROFILE="$SANDBOX"
unset RFM_ROOT
unset CLAUDE_PROJECT_DIR

# Testa num diretorio vazio (sem .rainforest de projeto)
TEMPWORK=$(mktemp -d)
trap "rm -rf $TEMPWORK" RETURN
cd "$TEMPWORK"

SAIDA_AUSENTE=$(node "$REPO_ROOT/vigias/dados-batedor-repos.js" 2>&1)
IDEIAS_AUS=$(echo "$SAIDA_AUSENTE" | grep "^IDEIAS ABERTAS" | head -1)
OBS_AUS=$(echo "$SAIDA_AUSENTE" | grep "^OBSERVACOES DA REGRA 13 ABERTAS" | head -1)
STDERR_AUS=$(echo "$SAIDA_AUSENTE" | grep "raiz de dados nao resolveu" | head -1)

echo "Saida de IDEIAS: $IDEIAS_AUS"
echo "Saida de OBSERVACOES: $OBS_AUS"
echo "Aviso em stderr: $(test -n "$STDERR_AUS" && echo "SIM" || echo "NAO")"

# Verifica que nao diz "(0)" — diz "indisponivel"
echo "$IDEIAS_AUS" | grep -q "indisponível" || { echo "FALHA: IDEIAS_ABERTAS nao marcado como indisponivel"; exit 1; }
echo "$OBS_AUS" | grep -q "indisponível" || { echo "FALHA: OBSERVACOES nao marcado como indisponivel"; exit 1; }
[ -n "$STDERR_AUS" ] || { echo "FALHA: aviso em stderr ausente"; exit 1; }

# Verifica que nao reporta "(0)"
echo "$IDEIAS_AUS" | grep -q "(0)" && { echo "FALHA: IDEIAS reportou (0) em vez de indisponivel"; exit 1; }
echo "$OBS_AUS" | grep -q "(0)" && { echo "FALHA: OBSERVACOES reportou (0) em vez de indisponivel"; exit 1; }

echo "✓ TESTE 4 passou (raiz ausente marca como indisponível, aviso em stderr)"
echo

echo "=== Todos os testes passaram ==="
