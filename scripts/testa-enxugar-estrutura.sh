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

# 4-8. As cinco tags aparecem no documento
for tag in "apagar:" "stdlib:" "nativo:" "yagni:" "encolher:"; do
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

echo ""
echo "Casos: $PASSOU/$CASOS passaram"

if [ "$PASSOU" -eq "$CASOS" ]; then
  exit 0
else
  exit 1
fi
