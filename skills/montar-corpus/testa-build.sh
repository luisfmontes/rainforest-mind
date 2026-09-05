#!/bin/bash
# Bateria do build. Testa a construção do acervo em markdown.
# Uso: bash skills/montar-corpus/testa-build.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="node $SRC/skills/montar-corpus/build.cjs"
FIXTURE="$SRC/test/fixtures/corpus/grafo-exemplo.json"

# Array para rastrear sandboxes
SANDBOXES=()

# Cria sandbox e registra no array. Devolve pela global ULTIMA_SANDBOX, nao
# pelo stdout: `SB="$(nova_sandbox)"` rodaria a funcao numa SUBSHELL, o
# SANDBOXES+= morreria com ela e o cleanup varreria um array vazio.
ULTIMA_SANDBOX=""
nova_sandbox() {
  ULTIMA_SANDBOX="$(mktemp -d)"
  SANDBOXES+=("$ULTIMA_SANDBOX")
}

nova_sandbox; SANDBOX="$ULTIMA_SANDBOX"

cleanup() {
  # ${A[@]} com set -u estoura em bash < 4.4 quando o array esta vazio.
  for sb in ${SANDBOXES[@]+"${SANDBOXES[@]}"}; do
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
nova_sandbox; SB6="$ULTIMA_SANDBOX"
RFM_ROOT="$SB6" esperado "  exit 1" 1 $BUILD "$FIXTURE"
echo ""

# Teste 7: Arquivo grafo inválido (não existe)
echo "7. Build com arquivo grafo inexistente:"
nova_sandbox; SB7="$ULTIMA_SANDBOX"
RFM_ROOT="$SB7" esperado "  exit 1" 1 $BUILD "/inexistente/grafo.json" --corpus teste
echo ""

# Teste 8: Grafo com id contendo path traversal (../../)
echo "8. Build com id contendo path traversal (../../):"
nova_sandbox; SB8="$ULTIMA_SANDBOX"
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
nova_sandbox; SB9="$ULTIMA_SANDBOX"
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
nova_sandbox; SB10="$ULTIMA_SANDBOX"
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
nova_sandbox; SB11="$ULTIMA_SANDBOX"
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
nova_sandbox; SB12="$ULTIMA_SANDBOX"
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

# Teste 13: escape nao pode valer so para o titulo. resumo, id, caminho e tipo
# de aresta tambem vem do grafo, que e entrada nao confiavel.
echo "13. Build com resumo, id e caminho hostis (escape vale para todo campo):"
nova_sandbox; SB13="$ULTIMA_SANDBOX"
GRAFO_CAMPOS="$SRC/test/fixtures/corpus/grafo-campos-hostis.json"
RFM_ROOT="$SB13" esperado "  exit 0" 0 $BUILD "$GRAFO_CAMPOS" --corpus campos
NO13="$SB13/acervo/campos/cra\`se.md"
# resumo escapado: o <script> nao pode sair cru
if grep -q 'Resumo com \\<script\\>' "$NO13" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   resumo escapado"
else
  falhou=$((falhou+1)); echo "  FALHA resumo saiu cru"
  grep -n "Resumo com" "$NO13" 2>/dev/null | sed 's/^/         /'
fi
# id com crase nao pode fechar o span de codigo: cerca tem que ser dupla
if grep -q '^\*\*ID:\*\* ``cra`se``$' "$NO13" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   id com crase cercado por crase dupla"
else
  falhou=$((falhou+1)); echo "  FALHA id com crase quebra o span de codigo"
  grep -n '^\*\*ID:\*\*' "$NO13" 2>/dev/null | sed 's/^/         /'
fi
# caminho com crase, mesma coisa
if grep -q '^\*\*Caminho:\*\* ``wiki/a`b.md``$' "$NO13" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   caminho com crase cercado por crase dupla"
else
  falhou=$((falhou+1)); echo "  FALHA caminho com crase quebra o span de codigo"
  grep -n '^\*\*Caminho:\*\*' "$NO13" 2>/dev/null | sed 's/^/         /'
fi
# tipo de aresta tambem e texto do grafo
if grep -q 'rela\\<cao\\>' "$SB13/acervo/campos/INDEX.md" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   tipo de aresta escapado"
else
  falhou=$((falhou+1)); echo "  FALHA tipo de aresta saiu cru"
  grep -n 'relacionado\|rela' "$SB13/acervo/campos/INDEX.md" 2>/dev/null | sed 's/^/         /'
fi
echo ""

# Teste 14: quebra de linha em campo de texto nao pode abrir bloco markdown.
# O acervo e lido por agente: bloco injetado passa por conteudo legitimo.
echo "14. Build com \\n em titulo e resumo (nao pode virar heading):"
nova_sandbox; SB14="$ULTIMA_SANDBOX"
GRAFO_NL="$SRC/test/fixtures/corpus/grafo-quebra-de-linha.json"
RFM_ROOT="$SB14" esperado "  exit 0" 0 $BUILD "$GRAFO_NL" --corpus nl
# O arquivo do no so pode ter DOIS headings: o titulo (#) e o Resumo (##).
NHEAD=$(grep -c '^#' "$SB14/acervo/nl/vitima.md" 2>/dev/null || echo 99)
if [ "$NHEAD" = "2" ]; then
  ok=$((ok+1)); echo "  ok   nenhum heading injetado (2 headings, os legitimos)"
else
  falhou=$((falhou+1)); echo "  FALHA $NHEAD headings, esperava 2 — bloco injetado"
  grep -n '^#' "$SB14/acervo/nl/vitima.md" 2>/dev/null | sed 's/^/         /'
fi
# O texto injetado tem que continuar visivel, so que na mesma linha.
if grep -q 'texto normal  # INSTRUCAO INJETADA' "$SB14/acervo/nl/vitima.md" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   texto preservado, achatado numa linha"
else
  falhou=$((falhou+1)); echo "  FALHA texto do resumo nao saiu achatado como esperado"
fi
# '#' no id tem que sair percent-encoded no alvo do link.
if grep -q -- '](\./nota%231\.md)' "$SB14/acervo/nl/INDEX.md" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   '#' do id sai como %23 no alvo do link"
else
  falhou=$((falhou+1)); echo "  FALHA '#' do id nao foi percent-encoded"
  grep -n -- '](' "$SB14/acervo/nl/INDEX.md" 2>/dev/null | sed 's/^/         /'
fi
echo ""

# Teste 15: ':' no id grava num Alternate Data Stream do NTFS — arquivo some
# da listagem e o no vai junto, sem erro. Tem que recusar.
echo "15. Build com id contendo ':' (Alternate Data Stream):"
nova_sandbox; SB15="$ULTIMA_SANDBOX"
GRAFO_INV="$SRC/test/fixtures/corpus/grafo-nome-invalido.json"
SAIDA15=$( { RFM_ROOT="$SB15" $BUILD "$GRAFO_INV" --corpus inv 2>&1; } )
EXIT15=$?
if [ "$EXIT15" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   exit 1 (exit $EXIT15)"
else
  falhou=$((falhou+1)); echo "  FALHA exit $EXIT15, esperava 1"
  echo "$SAIDA15" | sed 's/^/         /' | tail -3
fi
if echo "$SAIDA15" | grep -q "caractere inválido"; then
  ok=$((ok+1)); echo "  ok   recusa nomeada"
else
  falhou=$((falhou+1)); echo "  FALHA sem mensagem de recusa"
  echo "$SAIDA15" | sed 's/^/         /' | head -3
fi
if [ -z "$(ls -A "$SB15/acervo/inv" 2>/dev/null)" ]; then
  ok=$((ok+1)); echo "  ok   nada escrito"
else
  falhou=$((falhou+1)); echo "  FALHA escreveu mesmo recusando"
  ls -1 "$SB15/acervo/inv" | sed 's/^/         /'
fi
echo ""

# Teste 16: NTFS nao distingue caixa. Dois ids diferentes pelo schema viram o
# mesmo arquivo e o segundo apaga o primeiro sem aviso.
echo "16. Build com dois ids que colidem no sistema de arquivos:"
nova_sandbox; SB16="$ULTIMA_SANDBOX"
GRAFO_COL="$SRC/test/fixtures/corpus/grafo-colisao-de-nome.json"
SAIDA16=$( { RFM_ROOT="$SB16" $BUILD "$GRAFO_COL" --corpus col 2>&1; } )
EXIT16=$?
if [ "$EXIT16" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok   exit 1 (exit $EXIT16)"
else
  falhou=$((falhou+1)); echo "  FALHA exit $EXIT16, esperava 1 — no perdido em silencio"
  echo "$SAIDA16" | sed 's/^/         /' | tail -3
fi
# A recusa tem que nomear OS DOIS ids, senao nao da para achar o problema.
if echo "$SAIDA16" | grep -q '"Foo"' && echo "$SAIDA16" | grep -q '"foo"'; then
  ok=$((ok+1)); echo "  ok   recusa nomeia os dois ids"
else
  falhou=$((falhou+1)); echo "  FALHA recusa nao nomeia os dois ids"
  echo "$SAIDA16" | sed 's/^/         /' | head -3
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
