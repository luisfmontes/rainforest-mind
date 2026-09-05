#!/bin/bash
# Bateria do build. Testa a construção do acervo em markdown.
# Uso: bash skills/montar-corpus/testa-build.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="node $SRC/skills/montar-corpus/build.cjs"
FIXTURE="$SRC/test/fixtures/corpus/grafo-exemplo.json"
SANDBOX="$(mktemp -d)"
SANDBOX_FAIL=""
SANDBOX_FAIL2=""
SANDBOX_TRAVERSAL=""

cleanup() {
  rm -rf "$SANDBOX" "$SANDBOX_FAIL" "$SANDBOX_FAIL2" "$SANDBOX_TRAVERSAL"
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
SANDBOX_FAIL="$(mktemp -d)"
RFM_ROOT="$SANDBOX_FAIL" esperado "  exit 1" 1 $BUILD "$FIXTURE"
echo ""

# Teste 7: Arquivo grafo inválido (não existe)
echo "7. Build com arquivo grafo inexistente:"
SANDBOX_FAIL2="$(mktemp -d)"
RFM_ROOT="$SANDBOX_FAIL2" esperado "  exit 1" 1 $BUILD "/inexistente/grafo.json" --corpus teste
echo ""

# Teste 8: Grafo com id contendo path traversal (../../)
echo "8. Build com id contendo path traversal:"
SANDBOX_TRAVERSAL="$(mktemp -d)"
GRAFO_TRAVERSAL="$SRC/test/fixtures/corpus/grafo-travessia.json"
RFM_ROOT="$SANDBOX_TRAVERSAL" esperado "  exit 1" 1 $BUILD "$GRAFO_TRAVERSAL" --corpus teste
# Verifica que nenhum arquivo foi criado fora de acervo/teste/
if find "$SANDBOX_TRAVERSAL" -name "fora-do-acervo-poc.md" 2>/dev/null | grep -q .; then
  falhou=$((falhou+1)); echo "  FALHA arquivo criado fora do confinamento"
else
  ok=$((ok+1)); echo "  ok   nenhum arquivo fora de acervo/teste/"
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
