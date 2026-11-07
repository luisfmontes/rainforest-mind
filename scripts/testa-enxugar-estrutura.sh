#!/bin/bash
# Teste estrutural da skill enxugar
# Verifica: frontmatter, nome, tags, fronteira de escopo, unicidade

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="$REPO_ROOT/skills/enxugar/SKILL.md"
CASOS=0
PASSOU=0

# 1. Arquivo existe
if [ -f "$SKILL_FILE" ]; then
  echo "✓ Arquivo skill existe"
  ((PASSOU++))
fi
((CASOS++))

# 2. name: enxugar no frontmatter
if head -10 "$SKILL_FILE" | grep -q '^name: enxugar$'; then
  echo "✓ Frontmatter tem name: enxugar"
  ((PASSOU++))
fi
((CASOS++))

# 3. description: presente
if head -10 "$SKILL_FILE" | grep -q '^description:'; then
  echo "✓ Frontmatter tem description:"
  ((PASSOU++))
fi
((CASOS++))

# 4-9. As seis tags aparecem no documento
for tag in "apagar:" "stdlib:" "nativo:" "yagni:" "duplicar:" "encolher:"; do
  if grep -q "^### \`$tag\`" "$SKILL_FILE"; then
    echo "✓ Tag \`$tag\` presente"
    ((PASSOU++))
  fi
  ((CASOS++))
done

# 9-11. Fronteira de escopo documentada
if grep -q "Fora de escopo" "$SKILL_FILE"; then
  echo "✓ Seção 'Fora de escopo' presente"
  ((PASSOU++))
fi
((CASOS++))

if grep -q "Correção, segurança e performance" "$SKILL_FILE"; then
  echo "✓ Escopo: correção/segurança/performance fora"
  ((PASSOU++))
fi
((CASOS++))

if grep -q "Nenhum check executável" "$SKILL_FILE"; then
  echo "✓ Escopo: check executável protegido"
  ((PASSOU++))
fi
((CASOS++))

# 12. Nenhuma outra skill tem name: enxugar
OUTRAS=$(find "$REPO_ROOT/skills" -name 'SKILL.md' ! -path '*/enxugar/*' -exec grep -l '^name: enxugar$' {} \; | wc -l)
if [ "$OUTRAS" -eq 0 ]; then
  echo "✓ Nenhuma outra skill é enxugar"
  ((PASSOU++))
fi
((CASOS++))

# 13. Exemplos ❌ e ✅ presentes
if grep -q "❌" "$SKILL_FILE" && grep -q "✅" "$SKILL_FILE"; then
  echo "✓ Exemplos bons/ruins documentados"
  ((PASSOU++))
fi
((CASOS++))

# 14. Formato de achado documentado
if grep -q '<arquivo>:L' "$SKILL_FILE"; then
  echo "✓ Formato <arquivo>:L<n>: documentado"
  ((PASSOU++))
fi
((CASOS++))

# 15. Seção de Ranking
if grep -q "^## Ranking" "$SKILL_FILE" && grep -q 'maior corte primeiro' "$SKILL_FILE"; then
  echo "✓ Ranking por maior corte"
  ((PASSOU++))
fi
((CASOS++))

# 16. Trava contra falsos positivos: wrapper vs. reimplementação
if grep -q 'o trecho chama a função da biblioteca' "$SKILL_FILE"; then
  echo "✓ Trava contra falsos positivos (wrapper vs. reimplementação)"
  ((PASSOU++))
fi
((CASOS++))

# 17. Seção "Os seis tipos"
if grep -q '^## Os seis tipos' "$SKILL_FILE"; then
  echo "✓ Seção 'Os seis tipos' presente"
  ((PASSOU++))
fi
((CASOS++))

# 18. Cada tag tem seção Trava contra falsos positivos ou exemplo
if grep -q 'Trava contra falsos positivos:' "$SKILL_FILE"; then
  echo "✓ Existe seção 'Trava contra falsos positivos'"
  ((PASSOU++))
fi
((CASOS++))

# 19. Duplicar tag tem definição
if grep -q 'Reimplementação de módulo do próprio repositório' "$SKILL_FILE"; then
  echo "✓ Tag duplicar: tem definição clara"
  ((PASSOU++))
fi
((CASOS++))

# 20. Duplicar tag menciona exemplo de cópia vs wrapper
if grep -q 'Cópia byte-idêntica' "$SKILL_FILE"; then
  echo "✓ Tag duplicar: diferencia cópia de wrapper"
  ((PASSOU++))
fi
((CASOS++))

# 21-30. Passada de duplicata semântica (design lgpd-e-duplicata, D6, D8, D9, D10)
# Restrito ao bloco da passada: o resto da skill também fala de `duplicar:`.
PASSADA="$(sed -n '/^### Passada de duplicata semântica/,/^## /p' "$SKILL_FILE")"
REF_FILE="$REPO_ROOT/skills/enxugar/references/duplicata-semantica.md"
caso() { # caso <rotulo> <condicao-ja-avaliada: 0|1>
  if [ "$2" -eq 0 ]; then echo "✓ $1"; ((PASSOU++)); else echo "✗ $1"; fi
  ((CASOS++))
}
tem_na() { printf '%s' "$1" | grep -qF -- "$2"; }

# modo 2 tem a passada de duplicata semântica com as cinco fases
fases_ok=1
if [ -n "$PASSADA" ]; then
  # as cinco fases, na ordem: listar < haiku < separar < sonnet < conferir
  ordem="$(printf '%s\n' "$PASSADA" | grep -nE '^[1-5]\. ' | cut -d: -f1 | tr '\n' ' ')"
  l1="$(printf '%s\n' "$PASSADA" | grep -n 'catalogo-funcoes.cjs listar' | head -1 | cut -d: -f1)"
  l2="$(printf '%s\n' "$PASSADA" | grep -n 'agente \*\*haiku\*\*' | head -1 | cut -d: -f1)"
  l3="$(printf '%s\n' "$PASSADA" | grep -n 'catalogo-funcoes.cjs separar' | head -1 | cut -d: -f1)"
  l4="$(printf '%s\n' "$PASSADA" | grep -n 'agente \*\*sonnet\*\*' | head -1 | cut -d: -f1)"
  l5="$(printf '%s\n' "$PASSADA" | grep -n 'catalogo-funcoes.cjs conferir' | head -1 | cut -d: -f1)"
  if [ -n "$l1" ] && [ -n "$l2" ] && [ -n "$l3" ] && [ -n "$l4" ] && [ -n "$l5" ] \
     && [ "$l1" -lt "$l2" ] && [ "$l2" -lt "$l3" ] && [ "$l3" -lt "$l4" ] && [ "$l4" -lt "$l5" ] \
     && [ "$(echo $ordem | wc -w)" -eq 5 ]; then fases_ok=0; fi
fi
caso "modo 2 tem a passada de duplicata semântica com as cinco fases" "$fases_ok"

# D8: haiku categoriza e sonnet compara — não o contrário
tem_na "$(printf '%s\n' "$PASSADA" | grep -E '^2\. ')" "haiku"; r1=$?
tem_na "$(printf '%s\n' "$PASSADA" | grep -E '^4\. ')" "sonnet"; r2=$?
[ $r1 -eq 0 ] && [ $r2 -eq 0 ]; caso "D8: haiku na fase de categorizar, sonnet na de comparar" $?

# D9: só HIGH/MEDIUM com CONSOLIDATE vira duplicar:, INVESTIGATE à parte, KEEP_SEPARATE some
tem_na "$PASSADA" "**HIGH ou MEDIUM com \`CONSOLIDATE\`** vira linha \`duplicar:\`"; caso "D9: HIGH/MEDIUM CONSOLIDATE vira duplicar:" $?
tem_na "$PASSADA" "**\`INVESTIGATE\`** vai para uma seção **investigar**"; caso "D9: INVESTIGATE vai para investigar" $?
tem_na "$PASSADA" "**\`KEEP_SEPARATE\`** não aparece"; caso "D9: KEEP_SEPARATE não aparece" $?
tem_na "$PASSADA" "derruba o grupo"; caso "D9: conferência derruba grupo com função inexistente" $?

# D6: a passada nomeia o aviso-duplicata como cobertura de mesmo nome
tem_na "$PASSADA" "hooks/aviso-duplicata.cjs"; caso "D6: cita o aviso-duplicata para mesmo nome" $?

# D10: maiores arquivos como contexto, fora do líquido
MODO2="$(sed -n '/^### Modo 2/,/^### Passada de duplicata semântica/p' "$SKILL_FILE" | tr '\n' ' ' | tr -s ' ')"
tem_na "$MODO2" "catalogo-funcoes.cjs maiores"; r1=$?
tem_na "$MODO2" "não vira tag nem entra no \`líquido:\`"; r2=$?
[ $r1 -eq 0 ] && [ $r2 -eq 0 ]; caso "D10: modo 2 abre com os maiores arquivos, fora do líquido" $?

# D7 (complexidade-por-funcao): complexas depois do maiores, aproximado, fora do líquido, não medido lido
TRECHO2="$(sed -n '/^### Modo 2/,/^### Passada de duplicata semântica/p' "$SKILL_FILE")"
lm="$(printf '%s\n' "$TRECHO2" | grep -n 'catalogo-funcoes.cjs maiores' | head -1 | cut -d: -f1)"
lc="$(printf '%s\n' "$TRECHO2" | grep -n 'catalogo-funcoes.cjs complexas --raiz <repo> --top 10' | head -1 | cut -d: -f1)"
r1=1; [ -n "$lm" ] && [ -n "$lc" ] && [ "$lc" -gt "$lm" ] && r1=0
tem_na "$MODO2" "**aproximada**"; r2=$?
tem_na "$MODO2" "função ler primeiro, não vira tag nem entra no \`líquido:\`"; r3=$?
tem_na "$MODO2" "\`não medido:\` se leem"; r4=$?
[ $r1 -eq 0 ] && [ $r2 -eq 0 ] && [ $r3 -eq 0 ] && [ $r4 -eq 0 ]; caso "D7: modo 2 roda complexas depois do maiores, fora do líquido" $?

# D6 (complexidade-no-diff): modo 1 abre com variacao, base do revisor, fora do líquido
MODO1="$(sed -n '/^### Modo 1/,/^### Modo 2/p' "$SKILL_FILE" | tr '\n' ' ' | tr -s ' ')"
tem_na "$MODO1" "catalogo-funcoes.cjs variacao --raiz <repo>"; r1=$?
tem_na "$MODO1" "a mesma do revisor"; r2=$?
tem_na "$MODO1" "mais subiu é onde ler primeiro"; r3=$?
tem_na "$MODO1" "não vira tag nem entra no \`líquido:\`"; r4=$?
[ $r1 -eq 0 ] && [ $r2 -eq 0 ] && [ $r3 -eq 0 ] && [ $r4 -eq 0 ]; caso "D6 (complexidade-no-diff): modo 1 abre com variacao, fora do líquido" $?

# references: os dois prompts e o formato JSON dos grupos
if [ -f "$REF_FILE" ]; then
  REF="$(cat "$REF_FILE")"
  tem_na "$REF" "## Fase 2 — categorizar (agente haiku)"; r1=$?
  tem_na "$REF" "## Fase 4 — comparar (um agente sonnet por categoria)"; r2=$?
  [ $r1 -eq 0 ] && [ $r2 -eq 0 ]; caso "references traz os prompts de categorizar e comparar" $?
  ok_json=0
  for campo in '"intent"' '"confidence"' '"functions"' '"file"' '"name"' '"line"' '"notes"' '"differences"' '"recommendation"' '"action"' '"survivor"' '"reason"'; do
    tem_na "$REF" "$campo" || ok_json=1
  done
  caso "references traz o formato JSON dos grupos" $ok_json
else
  caso "references/duplicata-semantica.md existe" 1
fi

echo ""
echo "Casos: $PASSOU/$CASOS passaram"

if [ "$PASSOU" -eq "$CASOS" ]; then
  exit 0
else
  exit 1
fi
