#!/bin/bash
# Bateria de testes para scripts/conferir-regua.cjs
# Uso: bash scripts/testa-conferir-regua.sh
#
# Monta um repositório git de verdade em sandbox, comita um manifesto de régua,
# e testa que o conferidor detecta alterações e valida o formato.

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

SCRIPT="$SRC/scripts/conferir-regua.cjs"
REPO="$CAIXA/repo"
mkdir -p "$REPO"
cd "$REPO"

# Configura git
git init
git config user.email "test@<email>"
git config user.name "Test User"
git config commit.gpgsign false

# Cria estrutura de diretórios
mkdir -p docs/rainforest/reguas

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}

contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  local saida; saida=$("$@" 2>&1)
  if echo "$saida" | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: não achei '$txt'"; echo "$saida" | sed 's/^/         /' | tail -3; fi
}

stdout_bytes() { # comando...
  local saida; saida=$("$@" 2>/dev/null)
  echo -n "$saida" | wc -c
}

stdout_conteudo() { # comando...
  "$@" 2>/dev/null
}

echo "== 1. manifesto editado na arvore de trabalho recusa =="
# Cria um manifesto válido
cat > docs/rainforest/reguas/teste-1.md << 'EOF'
# Régua de teste

## Freios

### M1 — Primeiro mecanismo

Descrição aqui.

### M2 — Segundo mecanismo

Descrição aqui.

### M3 — Terceiro mecanismo

Descrição aqui.

### M4 — Quarto mecanismo

Descrição aqui.

### M5 — Quinto mecanismo

Descrição aqui.
EOF

git add docs/rainforest/reguas/teste-1.md
git commit -m "Adiciona manifesto de teste"

# Agora edita
echo "MODIFICADO" >> docs/rainforest/reguas/teste-1.md
esperado "detecta edição" 1 node "$SCRIPT" conferir --slug teste-1
contem "  ... menciona o arquivo na mensagem" "teste-1.md" node "$SCRIPT" conferir --slug teste-1

echo
echo "== 2. manifesto intacto sem ## Freios recusa =="
# Desfaz a edição anterior
git checkout docs/rainforest/reguas/teste-1.md

# Cria outro manifesto sem seção Freios
cat > docs/rainforest/reguas/teste-2.md << 'EOF'
# Régua de teste

### M1 — Primeiro mecanismo
### M2 — Segundo mecanismo
### M3 — Terceiro mecanismo
### M4 — Quarto mecanismo
### M5 — Quinto mecanismo
EOF

git add docs/rainforest/reguas/teste-2.md
git commit -m "Manifesto sem Freios"

esperado "rejeita sem seção Freios" 1 node "$SCRIPT" conferir --slug teste-2
contem "  ... menciona qual regra falhou" "Freios" node "$SCRIPT" conferir --slug teste-2

echo
echo "== 3. manifesto intacto com quatro M<n> recusa =="
# Cria manifesto com só 4 mecanismos
cat > docs/rainforest/reguas/teste-3.md << 'EOF'
# Régua de teste

## Freios

### M1 — Primeiro mecanismo
### M2 — Segundo mecanismo
### M3 — Terceiro mecanismo
### M4 — Quarto mecanismo
EOF

git add docs/rainforest/reguas/teste-3.md
git commit -m "Manifesto com 4 mecanismos"

esperado "rejeita com menos de 5 mecanismos" 1 node "$SCRIPT" conferir --slug teste-3
contem "  ... menciona quantidade" "4" node "$SCRIPT" conferir --slug teste-3

echo
echo "== 4. manifesto intacto, Freios + 5-7 M<n> sequenciais passa =="
# Cria manifesto válido com 6 mecanismos
cat > docs/rainforest/reguas/teste-4.md << 'EOF'
# Régua de teste

## Freios

Teto de rodadas aqui.

### M1 — Primeiro mecanismo

Conteúdo.

### M2 — Segundo mecanismo

Conteúdo.

### M3 — Terceiro mecanismo

Conteúdo.

### M4 — Quarto mecanismo

Conteúdo.

### M5 — Quinto mecanismo

Conteúdo.

### M6 — Sexto mecanismo

Conteúdo.
EOF

git add docs/rainforest/reguas/teste-4.md
git commit -m "Manifesto válido com 6 mecanismos"

esperado "aceita 6 mecanismos com Freios" 0 node "$SCRIPT" conferir --slug teste-4

echo
echo "== 5. slug inexistente sai 2 =="
esperado "slug inexistente retorna 2" 2 node "$SCRIPT" conferir --slug nao-existe
contem "  ... mensagem de arquivo não encontrado" "não encontrado\|inexistente" node "$SCRIPT" conferir --slug nao-existe

echo
echo "== 6. mostrar com manifesto editado nao imprime nada =="
# Cria um novo manifesto válido para testar edição
cat > docs/rainforest/reguas/teste-6.md << 'EOF'
# Régua de teste

## Freios

Teto aqui.

### M1 — Mecanismo 1

Descrição.

### M2 — Mecanismo 2

Descrição.

### M3 — Mecanismo 3

Descrição.

### M4 — Mecanismo 4

Descrição.

### M5 — Mecanismo 5

Descrição.
EOF

git add docs/rainforest/reguas/teste-6.md
git commit -m "Manifesto válido teste-6"

# Edita o manifesto
echo "EDITADO" >> docs/rainforest/reguas/teste-6.md

# Verifica que sai com exit 1
esperado "detecta edição no mostrar" 1 node "$SCRIPT" mostrar --slug teste-6

# Verifica que stdout tem zero bytes
bytes=$(stdout_bytes node "$SCRIPT" mostrar --slug teste-6)
if [ "$bytes" = "0" ]; then ok=$((ok+1)); echo "  ok   stdout vazio quando editado (0 bytes)"
else falhou=$((falhou+1)); echo "  FALHA stdout vazio: esperava 0 bytes, veio $bytes"; fi

echo
echo "== 7. mostrar manifesto intacto imprime conteudo da ancora =="

# Verifica que conferir passa (sanidade check)
conf_exit=0
node "$SCRIPT" conferir --slug teste-4 >/dev/null 2>&1 || conf_exit=$?
if [ "$conf_exit" = "0" ]; then echo "  ok   conferir passa (sanidade)"
else echo "  FALHA conferir: exit $conf_exit"; fi

# Captura o conteúdo esperado (do commit)
ancora=$(git log --diff-filter=A --format=%H -- docs/rainforest/reguas/teste-4.md | tail -1)
esperado_conteudo=$(MSYS_NO_PATHCONV=1 git show "$ancora":docs/rainforest/reguas/teste-4.md)

# Captura o conteúdo do mostrar
mostrar_conteudo=$(stdout_conteudo node "$SCRIPT" mostrar --slug teste-4)

# Compara byte a byte
if [ "$esperado_conteudo" = "$mostrar_conteudo" ]; then ok=$((ok+1)); echo "  ok   mostrar imprime conteudo idêntico da âncora"
else
  falhou=$((falhou+1))
  echo "  FALHA mostrar: conteúdo diverge da âncora"
  exp_len=$(echo -n "$esperado_conteudo" | wc -c)
  most_len=$(echo -n "$mostrar_conteudo" | wc -c)
  echo "         esperado: $exp_len bytes, mostrar: $most_len bytes"
fi

echo
echo "== 8. mostrar manifesto sem ## Freios nao imprime nada =="
# Edita teste-2 para remover Freios (já existe sem Freios, mas vamos verificar)
esperado "rejeita sem Freios no mostrar" 1 node "$SCRIPT" mostrar --slug teste-2

bytes2=$(stdout_bytes node "$SCRIPT" mostrar --slug teste-2)
if [ "$bytes2" = "0" ]; then ok=$((ok+1)); echo "  ok   stdout vazio quando sem Freios (0 bytes)"
else falhou=$((falhou+1)); echo "  FALHA stdout vazio sem Freios: esperava 0 bytes, veio $bytes2"; fi

echo
echo "== Resumo =="
resultado=$((ok+falhou))
if [ "$falhou" = "0" ]; then
  echo "resultado: $ok ok, 0 falha(s)"
  exit 0
else
  echo "resultado: $ok ok, $falhou falha(s)"
  exit 1
fi
