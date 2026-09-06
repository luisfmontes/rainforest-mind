#!/bin/bash
# Bateria do CLI. Testa montar-corpus contra wiki-minima.
# Usa sandbox com projetos.json temporário, sem alterar config do usuário.
# Uso: bash skills/montar-corpus/testa-cli.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

# Cria sandbox para RFM_ROOT temporário
SBP="$(mktemp -d)"
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
export RFM_ROOT="$SB"
trap 'rm -rf "$SBP"' EXIT

# Inicializa sandbox com projetos.json
mkdir -p "$RFM_ROOT"
touch "$RFM_ROOT/FOCO.md"
cat > "$RFM_ROOT/projetos.json" <<EOF
{
  "wiki-minima": {
    "caminho": "$SB/wiki-minima",
    "apelidos": []
  }
}
EOF

# Copia fixtures para dentro da sandbox
mkdir -p "$SB/wiki-minima"
cp -r "$SRC/test/fixtures/corpus/wiki-minima/wiki" "$SB/wiki-minima/"

CLI="node $SRC_WIN/skills/montar-corpus/cli.cjs"
TMPDIR="$SBP/output"
mkdir -p "$TMPDIR"

ok=0; falhou=0

esperado() {
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    echo "$saida" | sed 's/^/         /' | head -10
  fi
}

contem() {
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt' na saida"; fi
}

echo "Bateria do CLI montar-corpus:"
echo ""

echo "1. Sem flags, recusa com mensagem:"
esperado "  exit != 0" 1 $CLI
contem "  menciona --repo" "--repo" $CLI
contem "  menciona --corpus" "--corpus" $CLI
echo ""

echo "1b. --repo sozinho recusa, e diz por que (D9: --repo e escopo, nunca alvo):"
esperado "  exit != 0" 1 $CLI --repo "$SB"
SAIDA_REPO=$($CLI --repo "$SB" 2>&1)
if echo "$SAIDA_REPO" | grep -q -- "--corpus é obrigatório"; then
  ok=$((ok+1)); echo "  ok   recusa nomeia o --corpus como o alvo"
else
  falhou=$((falhou+1)); echo "  FALHA recusa nao nomeia o --corpus"
  echo "$SAIDA_REPO" | sed 's/^/         /' | head -3
fi
if echo "$SAIDA_REPO" | grep -q -- "--repo sozinho não gera nada"; then
  ok=$((ok+1)); echo "  ok   explica que --repo sozinho nao e alvo"
else
  falhou=$((falhou+1)); echo "  FALHA nao explica o papel do --repo"
  echo "$SAIDA_REPO" | sed 's/^/         /' | head -4
fi
# E nao pode ter gerado acervo nenhum ao recusar.
if [ ! -d "$SB/acervo" ]; then
  ok=$((ok+1)); echo "  ok   nada gerado"
else
  falhou=$((falhou+1)); echo "  FALHA gerou acervo mesmo recusando"
fi
echo ""

echo "1c. --repo COM --corpus: a raiz passa a ser o --repo:"
REPOSB="$SB/repo-proprio"
mkdir -p "$REPOSB/corpus-do-repo/wiki"
cp "$SRC/test/fixtures/corpus/wiki-minima/wiki/"*.md "$REPOSB/corpus-do-repo/wiki/"
cat > "$REPOSB/projetos.json" <<EOF
{
  "corpus-do-repo": {
    "caminho": "$SB/repo-proprio/corpus-do-repo",
    "apelidos": []
  }
}
EOF
esperado "  exit 0" 0 $CLI --repo "$REPOSB" --corpus corpus-do-repo
if [ -f "$REPOSB/acervo/corpus-do-repo/INDEX.md" ]; then
  ok=$((ok+1)); echo "  ok   acervo saiu na raiz do --repo, nao na do RFM_ROOT"
else
  falhou=$((falhou+1)); echo "  FALHA acervo nao saiu em $REPOSB/acervo/"
fi
# O corpus do --repo nao existe no projetos.json do RFM_ROOT: se tivesse ido
# para la, a resolucao teria falhado. Confere que nao vazou para o RFM_ROOT.
if [ ! -d "$SB/acervo/corpus-do-repo" ]; then
  ok=$((ok+1)); echo "  ok   nada escrito na raiz do RFM_ROOT"
else
  falhou=$((falhou+1)); echo "  FALHA escreveu tambem na raiz do RFM_ROOT"
fi
echo ""

echo "2. Corpus inexistente, recusa nomeando o slug:"
esperado "  exit != 0" 1 $CLI --corpus corpus-inexistente
contem "  nomeia o slug" "corpus-inexistente" $CLI --corpus corpus-inexistente
echo ""

echo "3. Corpus wiki-minima, sucesso:"
esperado "  exit 0" 0 $CLI --corpus wiki-minima
if [ -f "$SB/acervo/wiki-minima/INDEX.md" ]; then
  ok=$((ok+1)); echo "  ok   acervo/wiki-minima/INDEX.md existe"
else
  falhou=$((falhou+1)); echo "  FALHA acervo/wiki-minima/INDEX.md não existe"
fi
if [ -f "$SB/acervo/wiki-minima/conceito-a.md" ]; then
  ok=$((ok+1)); echo "  ok   acervo/wiki-minima/conceito-a.md existe"
else
  falhou=$((falhou+1)); echo "  FALHA acervo/wiki-minima/conceito-a.md não existe"
fi
echo ""

echo "4. Acervo foi criado com conteúdo:"
# Procura a forma exata do item de nó com tipo (concept) para não confundir com Arestas
if [ -s "$SB/acervo/wiki-minima/INDEX.md" ] && grep -q -- "- \[.*\](.*\.md) (concept)" "$SB/acervo/wiki-minima/INDEX.md"; then
  ok=$((ok+1)); echo "  ok   seção de Nós com conteúdo"
else
  falhou=$((falhou+1)); echo "  FALHA INDEX.md sem seção de Nós ou vazia"
fi
echo ""

echo "========================================"
echo "$ok ok   $falhou falha(s)"
echo "========================================"

if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
