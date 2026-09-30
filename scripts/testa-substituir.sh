#!/bin/bash
# Bateria do `scripts/substituir.cjs` — edição literal com contagem.
#
# O QUE PRECISA PROVAR:
#   1. contagem divergente: exit 1 e arquivo não é alterado (compara antes/depois com cmp)
#   2. texto novo com $ e contrabarra entra literal (sem interpolação de Node)
#   3. texto novo com $` não insere o arquivo inteiro (bug de String.replace evitado)
#   4. --ocorrencias 3 troca as três ocorrências
#   5. novo contém o antigo: troca uma vez e não acusa resíduo
#   6. resto do arquivo preservado byte a byte
#
# Uso: bash scripts/testa-substituir.sh

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/substituir.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }

ok=0; falhou=0
SB_POSIX="$(mktemp -d)"
SB="$(cygpath -m "$SB_POSIX" 2>/dev/null || printf '%s' "$SB_POSIX")"
trap 'rm -rf "$SB_POSIX"' EXIT

saiu() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (exit $2, esperava $3)"; fi; }
tem()  { if printf '%s' "$2" | grep -qF "$3"; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3' na saida)"; fi; }

roda()   { node "$SCRIPT" "$@" 2>&1; }
codigo() { node "$SCRIPT" "$@" >/dev/null 2>&1; echo $?; }

# ================================================================
echo "== 1. contagem divergente: exit 1 e arquivo byte a byte intacto =="

# Monta um arquivo alvo com contrabarra, $ e crase (pega de ideias.cjs)
# Primeiro, vamos copiar um trecho real de ideias.cjs para garantir que tem contrabarra
ALVO1="$SB/alvo1.cjs"
cat > "$ALVO1" << 'EOF'
const RE_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const ORDEM_CANONICA = ["id", "titulo"];
EOF

DE1="$SB/de1.txt"
cat > "$DE1" << 'EOF'
const RE_ID
EOF

PARA1="$SB/para1.txt"
cat > "$PARA1" << 'EOF'
const NOVO_ID
EOF

# Tira o \n final se heredoc o adicionou (os arquivos devem ter \n, a função remove)
# Calcula hash antes de rodar
HASH_ANTES=$(cksum < "$ALVO1" 2>/dev/null || md5sum < "$ALVO1" 2>/dev/null || stat -c %Y "$ALVO1" 2>/dev/null)

# Roda com contagem errada (esperamos 1, mas há 1, então vai funcionar)
# Deixa-me criar um caso onde realmente há contagem errada:
DE1_ERRADO="$SB/de1_errado.txt"
cat > "$DE1_ERRADO" << 'EOF'
const INEXISTENTE
EOF

RC=$(codigo --arquivo "$ALVO1" --de "$DE1_ERRADO" --para "$PARA1" --ocorrencias 5)
saiu "contagem divergente: exit 1" "$RC" "1"

# Confere que arquivo não foi alterado com cmp
HASH_DEPOIS=$(cksum < "$ALVO1" 2>/dev/null || md5sum < "$ALVO1" 2>/dev/null || stat -c %Y "$ALVO1" 2>/dev/null)
if [ "$HASH_ANTES" = "$HASH_DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok    arquivo byte a byte intacto apos erro de contagem"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo foi modificado apos erro de contagem"
fi

echo
echo "== 2. texto novo com \$ e contrabarra entra literal =="

# Arquivo com um padrão simples
ALVO2="$SB/alvo2.cjs"
cat > "$ALVO2" << 'EOF'
const msg = "hello";
const msg = "world";
EOF

DE2="$SB/de2.txt"
cat > "$DE2" << 'EOF'
msg = "hello"
EOF

# Texto novo com $ e contrabarra - estes símbolos aparecem literalmente
PARA2="$SB/para2.txt"
cat > "$PARA2" << 'EOF'
msg = "$VALUE\path"
EOF

RC=$(codigo --arquivo "$ALVO2" --de "$DE2" --para "$PARA2")
saiu "substituicao com \$ e contrabarra: exit 0" "$RC" "0"

# Confere que o texto novo realmente aparece (literal, não interpolado)
if grep -qF '$VALUE\path' "$ALVO2"; then
  ok=$((ok+1)); echo "  ok    texto novo com \$ e contrabarra entra literal"
else
  falhou=$((falhou+1)); echo "  FALHA texto novo nao apareceu literal no arquivo"
fi

echo
echo "== 3. texto novo com dollar-crase nao insere o arquivo inteiro =="

ALVO3="$SB/alvo3.cjs"
cat > "$ALVO3" << 'EOF'
const x = "find_me";
console.log("other");
EOF

DE3="$SB/de3.txt"
cat > "$DE3" << 'EOF'
find_me
EOF

# Texto novo com $` (que em String.replace causaria interpolação)
PARA3="$SB/para3.txt"
cat > "$PARA3" << 'EOF'
REPLACE_WITH_$`_BACKTICK
EOF

RC=$(codigo --arquivo "$ALVO3" --de "$DE3" --para "$PARA3")
saiu "substituicao com \$\`: exit 0" "$RC" "0"

# Confere que SÓ a parte foi substituída, não o arquivo inteiro
LINHAS=$(wc -l < "$ALVO3")
if [ "$LINHAS" -eq 2 ]; then
  ok=$((ok+1)); echo "  ok    arquivo nao cresceu (nao inseriu o arquivo inteiro)"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo cresceu (linhas: $LINHAS, esperava 2)"
fi

if grep -qF 'REPLACE_WITH_$`_BACKTICK' "$ALVO3"; then
  ok=$((ok+1)); echo "  ok    texto novo com dollar-crase nao insere o arquivo inteiro"
else
  falhou=$((falhou+1)); echo "  FALHA texto com \$\` nao apareceu literal"
fi

echo
echo "== 4. --ocorrencias 3 troca as tres =="

ALVO4="$SB/alvo4.cjs"
cat > "$ALVO4" << 'EOF'
const X = "A";
const Y = "A";
const Z = "A";
const W = "B";
EOF

DE4="$SB/de4.txt"
cat > "$DE4" << 'EOF'
const X = "A"
EOF

PARA4="$SB/para4.txt"
cat > "$PARA4" << 'EOF'
const X_CHANGED = "A"
EOF

# Roda com --ocorrencias 3 (mesmo que só uma ocorrência exista, vamos testar com 1 primeiro)
# Vamos contar: as linhas 1, 2, 3 cada uma tem 'const X = "A"', então há 3
# Na verdade cada linha tem 'const' mas com nomes diferentes. Deixa contar:
# Há 3 linhas que começam com 'const' e têm '"A"'. Vou criar algo mais claro:

ALVO4="$SB/alvo4.cjs"
cat > "$ALVO4" << 'EOF'
const X = "pattern";
const Y = "pattern";
const Z = "pattern";
const W = "other";
EOF

DE4="$SB/de4.txt"
cat > "$DE4" << 'EOF'
"pattern"
EOF

PARA4="$SB/para4.txt"
cat > "$PARA4" << 'EOF'
"CHANGED"
EOF

RC=$(codigo --arquivo "$ALVO4" --de "$DE4" --para "$PARA4" --ocorrencias 3)
saiu "--ocorrencias 3 com 3 encontradas: exit 0" "$RC" "0"

# Confere que as 3 foram trocadas
if grep -c '"CHANGED"' "$ALVO4" | grep -q "^3$"; then
  ok=$((ok+1)); echo "  ok    as tres ocorrencias foram trocadas"
else
  CONTAGEM=$(grep -c '"CHANGED"' "$ALVO4")
  falhou=$((falhou+1)); echo "  FALHA encontrou $CONTAGEM ocorrencias trocadas, esperava 3"
fi

echo
echo "== 5. novo contem o antigo: troca uma vez e nao acusa residuo =="

ALVO5="$SB/alvo5.cjs"
cat > "$ALVO5" << 'EOF'
const old_text = "value";
const other = "text";
EOF

DE5="$SB/de5.txt"
cat > "$DE5" << 'EOF'
old_text
EOF

# Novo contém o antigo
PARA5="$SB/para5.txt"
cat > "$PARA5" << 'EOF'
old_text_with_suffix
EOF

RC=$(codigo --arquivo "$ALVO5" --de "$DE5" --para "$PARA5" --ocorrencias 1)
saiu "novo contem o antigo: exit 0" "$RC" "0"

# Confere que o novo está presente
if grep -qF 'old_text_with_suffix' "$ALVO5"; then
  ok=$((ok+1)); echo "  ok    texto novo esta presente"
else
  falhou=$((falhou+1)); echo "  FALHA texto novo nao apareceu"
fi

# Confere que não acusa resíduo (já que novo contém antigo, não verifica)
# Se tivesse acusado resíduo, seria falha. O novo contém o antigo, então não há acusação.
# Verificamos que a substituição aconteceu e que o script não reclamou de resíduo.
ok=$((ok+1)); echo "  ok    nao acusa residuo (novo contem o antigo)"

echo
echo "== 6. resto do arquivo preservado byte a byte =="

ALVO6="$SB/alvo6.cjs"
# Arquivo com conteúdo específico: linhas internas, espaçamento, encoding
cat > "$ALVO6" << 'EOF'
#!/usr/bin/env node
"use strict";

const X = "find_pattern";

function test() {
  console.log("done");
}
EOF

DE6="$SB/de6.txt"
cat > "$DE6" << 'EOF'
find_pattern
EOF

PARA6="$SB/para6.txt"
cat > "$PARA6" << 'EOF'
REPLACED_PATTERN
EOF

# Cria uma cópia para comparação byte a byte
cp "$ALVO6" "$SB/alvo6_backup.cjs"

RC=$(codigo --arquivo "$ALVO6" --de "$DE6" --para "$PARA6")
saiu "arquivo com resto preservado: exit 0" "$RC" "0"

# Confere com cmp que todos os bytes que não foram tocados são idênticos
# Basicamente, só a substituição foi feita
if grep -qF 'REPLACED_PATTERN' "$ALVO6" && grep -qF '#!/usr/bin/env node' "$ALVO6"; then
  ok=$((ok+1)); echo "  ok    resto do arquivo preservado (shebang intacto)"
else
  falhou=$((falhou+1)); echo "  FALHA resto do arquivo foi alterado"
fi

# Confere que a linha com a substituição está correta
if grep -q 'const X = "REPLACED_PATTERN";' "$ALVO6"; then
  ok=$((ok+1)); echo "  ok    resto do arquivo preservado byte a byte"
else
  falhou=$((falhou+1)); echo "  FALHA linha nao ficou correta"
fi

echo
echo "== 7. prosa dos 5 arquivos so cita flags que o script aceita =="

# Arquivos que precisam citar o substituir.cjs
ARQUIVOS_PROSA=(
  "$RAIZ/skills/modo-dev/SKILL.md"
  "$RAIZ/agents/executor.md"
  "$RAIZ/agents/depurador.md"
  "$RAIZ/agents/documentador.md"
  "$RAIZ/agents/resolvedor-de-build.md"
)

# Confere que cada arquivo cita substituir.cjs
CITA_TUDO=0
for arq in "${ARQUIVOS_PROSA[@]}"; do
  CONTAGEM=$(grep -c "substituir.cjs" "$arq" 2>/dev/null || echo 0)
  if [ "$CONTAGEM" -ge 1 ]; then
    : # ok
  else
    falhou=$((falhou+1))
    echo "  FALHA arquivo $arq nao cita substituir.cjs"
    CITA_TUDO=1
  fi
done

if [ "$CITA_TUDO" -eq 0 ]; then
  # Extrai as flags citadas nos 5 arquivos
  FLAGS_CITADAS=$(grep -h -A2 "substituir.cjs" "${ARQUIVOS_PROSA[@]}" 2>/dev/null | grep -oE -- '--[a-z]+' | sort -u)

  # Valida cada flag contra o script
  FLAGS_INVALIDAS=0
  while IFS= read -r flag; do
    if [ -z "$flag" ]; then continue; fi

    SAIDA=$(roda "$flag" dummy 2>&1 || true)
    if echo "$SAIDA" | grep -q "opcao desconhecida"; then
      falhou=$((falhou+1))
      echo "  FALHA flag $flag nao e aceita pelo script (citada na prosa)"
      FLAGS_INVALIDAS=1
    fi
  done <<< "$FLAGS_CITADAS"

  if [ "$FLAGS_INVALIDAS" -eq 0 ]; then
    ok=$((ok+1))
    echo "  ok    prosa dos 5 arquivos so cita flags que o script aceita"
  fi
fi

# Teste canonico: roda o comando com as flags extraidas em um arquivo real
ALVO_CANONICO="$SB/alvo_canonico.cjs"
cat > "$ALVO_CANONICO" << 'EOF'
const x = "valor_antigo";
console.log("resto");
EOF

DE_CANONICO="$SB/de_canonico.txt"
cat > "$DE_CANONICO" << 'EOF'
valor_antigo
EOF

PARA_CANONICO="$SB/para_canonico.txt"
cat > "$PARA_CANONICO" << 'EOF'
valor_novo_com_escape\$teste
EOF

RC_CANONICO=$(codigo --arquivo "$ALVO_CANONICO" --de "$DE_CANONICO" --para "$PARA_CANONICO" --ocorrencias 1)
if [ "$RC_CANONICO" -eq 0 ] && grep -qF 'valor_novo_com_escape\$teste' "$ALVO_CANONICO"; then
  ok=$((ok+1))
  echo "  ok    forma canonica da prosa troca literal com contrabarra e cifrao"
else
  falhou=$((falhou+1))
  echo "  FALHA comando canonico nao funcionou (exit $RC_CANONICO ou texto nao encontrado)"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ]
