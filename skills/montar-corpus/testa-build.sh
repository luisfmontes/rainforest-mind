#!/bin/bash
# Bateria do build. Testa a construção do acervo em markdown.
# Uso: bash skills/montar-corpus/testa-build.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="node $SRC/skills/montar-corpus/build.cjs"
FIXTURE="$SRC/test/fixtures/corpus/grafo-exemplo.json"

# Array para rastrear sandboxes
SANDBOXES=()

# Função para criar sandbox e garantir limpeza
nova_sandbox() {
  local sb="$(mktemp -d)"
  SANDBOXES+=("$sb")
  echo "$sb"
}

SANDBOX="$(nova_sandbox)"

cleanup() {
  for sb in "${SANDBOXES[@]}"; do
    rm -rf "$sb"
  done
}
trap 'cleanup' EXIT

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    echo "$saida" | sed 's/^/         /' | tail -5
  fi
}

arquivoexiste() { # nome, caminho
  local nome="$1" cam="$2"
  if [ -f "$cam" ]; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: arquivo nao encontrado: $cam"; fi
}

arquivosvazios() { # nome, pasta
  local nome="$1" pasta="$2"
  if [ -d "$pasta" ] && [ -n "$(find "$pasta" -type f)" ]; then
    ok=$((ok+1)); echo "  ok   $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: pasta vazia ou inexistente: $pasta"
  fi
}

# ---------------------------------------------------------------- cenarios

echo "Bateria do build:"
echo ""

# Teste 1: Build com corpus válido
echo "1. Build com grafo válido e --corpus:"
RFM_ROOT="$SANDBOX" esperado "  exit 0" 0 $BUILD "$FIXTURE" --corpus exemplo
echo ""

# Teste 2: Verifica que INDEX.md foi criado
echo "2. Verifica criação do INDEX.md:"
arquivoexiste "  INDEX.md criado" "$SANDBOX/acervo/exemplo/INDEX.md"
echo ""

# Teste 3: Verifica que arquivo .md foi criado por nó
echo "3. Verifica criação de .md por nó:"
# Conta quantos .md existem na pasta (minus o INDEX.md)
count=$(find "$SANDBOX/acervo/exemplo" -maxdepth 1 -name "*.md" -type f | grep -v INDEX | wc -l)
expected=6  # fixture tem 6 nós
if [ "$count" = "$expected" ]; then
  ok=$((ok+1)); echo "  ok   $count arquivos .md criados (esperado $expected)"
else
  falhou=$((falhou+1)); echo "  FALHA esperado $expected .md, encontrou $count"
fi
echo ""

# Teste 4: Verifica que INDEX.md não está vazio
echo "4. Verifica que INDEX.md não está vazio:"
if [ -s "$SANDBOX/acervo/exemplo/INDEX.md" ]; then
  ok=$((ok+1)); echo "  ok   INDEX.md tem conteúdo"
else
  falhou=$((falhou+1)); echo "  FALHA INDEX.md vazio"
fi
echo ""

# Teste 5: Verifica que um nó específico existe e tem conteúdo
echo "5. Verifica conteúdo de um nó:"
if grep -q "Conceito Principal" "$SANDBOX/acervo/exemplo/conceito-1.md" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   conceito-1.md contém título esperado"
else
  falhou=$((falhou+1)); echo "  FALHA conceito-1.md não contém título esperado"
fi
echo ""

# Teste 6: Falta de --corpus deve falhar
echo "6. Build sem --corpus deve falhar:"
SB6="$(nova_sandbox)"
RFM_ROOT="$SB6" esperado "  exit 1" 1 $BUILD "$FIXTURE"
echo ""

# Teste 7: Arquivo grafo inválido (não existe)
echo "7. Build com arquivo grafo inexistente:"
SB7="$(nova_sandbox)"
RFM_ROOT="$SB7" esperado "  exit 1" 1 $BUILD "/inexistente/grafo.json" --corpus teste
echo ""

# Teste 8: Grafo com id contendo path traversal (../../)
echo "8. Build com id contendo path traversal (../../):"
SB8="$(nova_sandbox)"
GRAFO_TRAVERSAL="$SRC/test/fixtures/corpus/grafo-travessia.json"
RFM_ROOT="$SB8" esperado "  exit 1" 1 $BUILD "$GRAFO_TRAVERSAL" --corpus teste
# Verifica que nenhum arquivo foi criado fora de acervo/teste/
if find "$SB8" -name "fora-do-acervo-poc.md" 2>/dev/null | grep -q .; then
  falhou=$((falhou+1)); echo "  FALHA arquivo criado fora do confinamento"
else
  ok=$((ok+1)); echo "  ok   nenhum arquivo fora de acervo/teste/"
fi
echo ""

# Teste 9: Grafo com id tentando sobrescrever corpus vizinho
echo "9. Build com id tentando invadir corpus vizinho:"
SB9="$(nova_sandbox)"
# Cria corpus vizinho com INDEX.md original
mkdir -p "$SB9/acervo/teste-vizinho"
CONTEUDO_ORIGINAL="# Corpus Vizinho Original - $(date +%s)"
echo "$CONTEUDO_ORIGINAL" > "$SB9/acervo/teste-vizinho/INDEX.md"
HASH_ANTES=$(md5sum "$SB9/acervo/teste-vizinho/INDEX.md" | cut -d' ' -f1)
# Tenta atacar com grafo que escreve em ../teste-vizinho/INDEX
GRAFO_VIZINHO="$SRC/test/fixtures/corpus/grafo-vizinho-attack.json"
RFM_ROOT="$SB9" esperado "  exit 1 (não sobrescreve vizinho)" 1 $BUILD "$GRAFO_VIZINHO" --corpus teste
# Verifica que arquivo do vizinho não foi alterado
HASH_DEPOIS=$(md5sum "$SB9/acervo/teste-vizinho/INDEX.md" | cut -d' ' -f1)
if [ "$HASH_ANTES" = "$HASH_DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok   arquivo vizinho intacto"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo vizinho foi alterado"
fi
echo ""

# Teste 10: B2 - Corpus com path traversal relativo (../x) — vizinho FORA de acervo
echo "10. Build com --corpus ../corpus-vizinho/x (fora de acervo):"
SB10="$(nova_sandbox)"
# Cria corpus vizinho FORA de acervo (é onde o ataque resolverá)
mkdir -p "$SB10/corpus-vizinho"
echo "# Vizinho Original" > "$SB10/corpus-vizinho/INDEX.md"
HASH10_ANTES=$(md5sum "$SB10/corpus-vizinho/INDEX.md" | cut -d' ' -f1)
# Tenta atacar com --corpus ../corpus-vizinho/x (resolve para $SB10/corpus-vizinho/x)
SAIDA10=$( { RFM_ROOT="$SB10" $BUILD "$FIXTURE" --corpus "../corpus-vizinho/x" 2>&1; } )
EXIT10=$?
if [ "$EXIT10" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   exit 1 (exit $EXIT10)"
else
  falhou=$((falhou+1)); echo "  FALHA exit $EXIT10, esperava 1"
  echo "$SAIDA10" | sed 's/^/         /' | tail -3
fi
# Verifica recusa nomeada (não crash silencioso)
if echo "$SAIDA10" | grep -q "path traversal\|não é possível validar confinamento"; then
  ok=$((ok+1)); echo "  ok   recusa nomeada (path traversal)"
else
  falhou=$((falhou+1)); echo "  FALHA sem mensagem de recusa"
fi
# Verifica que vizinho não foi alterado
HASH10_DEPOIS=$(md5sum "$SB10/corpus-vizinho/INDEX.md" | cut -d' ' -f1)
if [ "$HASH10_ANTES" = "$HASH10_DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok   arquivo vizinho intacto"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo vizinho foi alterado"
fi
echo ""

# Teste 11: B2 - Corpus com caminho absoluto (deve ser recusado com mensagem)
echo "11. Build com --corpus <absoluto> (deve recusar):"
SB11="$(nova_sandbox)"
SAIDA11=$( { RFM_ROOT="$SB11" $BUILD "$FIXTURE" --corpus "/tmp/ataque" 2>&1; } )
EXIT11=$?
if [ "$EXIT11" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   exit 1 (exit $EXIT11)"
else
  falhou=$((falhou+1)); echo "  FALHA exit $EXIT11, esperava 1"
  echo "$SAIDA11" | sed 's/^/         /' | tail -3
fi
# Verifica recusa nomeada (não stack trace de ENOENT)
if echo "$SAIDA11" | grep -q "path traversal\|não é possível validar confinamento"; then
  ok=$((ok+1)); echo "  ok   recusa nomeada (não stack trace)"
else
  falhou=$((falhou+1)); echo "  FALHA sem mensagem de recusa"
  echo "$SAIDA11" | sed 's/^/         /' | head -3
fi
# Verifica que nada foi criado
if ! find "$SB11" -type f -name "*.md" 2>/dev/null | grep -q .; then
  ok=$((ok+1)); echo "  ok   nenhum arquivo criado"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo foi criado"
fi
echo ""

# Teste 12: C4 - Escape de caracteres especiais em título
echo "12. Build com título contendo caracteres especiais (<, >, [, ], (, )):"
SB12="$(nova_sandbox)"
GRAFO_ESPECIAL="$SRC/test/fixtures/corpus/grafo-escape.json"
RFM_ROOT="$SB12" esperado "  exit 0" 0 $BUILD "$GRAFO_ESPECIAL" --corpus escape
# Verifica que caracteres foram escapados no INDEX.md
if grep -q '\\<' "$SB12/acervo/escape/INDEX.md" && grep -q '\\>' "$SB12/acervo/escape/INDEX.md"; then
  ok=$((ok+1)); echo "  ok   < e > foram escapados"
else
  falhou=$((falhou+1)); echo "  FALHA caracteres especiais não foram escapados"
fi
# Verifica que caracteres foram escapados no arquivo do nó
if grep -q '\\]' "$SB12/acervo/escape/teste-c4.md" && grep -q '\\(' "$SB12/acervo/escape/teste-c4.md"; then
  ok=$((ok+1)); echo "  ok   [ e ( foram escapados"
else
  falhou=$((falhou+1)); echo "  FALHA caracteres não escapados no arquivo do nó"
fi
echo ""
echo ""

# Teste 11: B2 - Corpus com caminho absoluto (deve ser recusado)
echo "11. Build com --corpus <absoluto> (deve recusar):"
SANDBOX_ABSOLUTO="$(mktemp -d)"
# Tenta com caminho absoluto
RFM_ROOT="$SANDBOX_ABSOLUTO" esperado "  exit 1 (recusa absoluto)" 1 $BUILD "$FIXTURE" --corpus "/tmp/ataque"
# Verifica que nada foi criado
if ! find "$SANDBOX_ABSOLUTO" -type f -name "*.md" 2>/dev/null | grep -q .; then
  ok=$((ok+1)); echo "  ok   nenhum arquivo criado"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo foi criado"
fi
echo ""

# ---------------------------------------------------------------- placar
echo "========================================"
echo "$ok ok   $falhou falha(s)"
echo "========================================"

if [ "$falhou" -gt 0 ]; then
  exit 1
else
  exit 0
fi
