#!/bin/bash

# Bateria de testes para scripts/conferir-ponte.cjs
# Testa os 4 vereditos e a mutação
#
# Uso: bash scripts/testa-conferir-ponte.sh
# Saída: 0 se todas as baterias passarem, 1 se falhar

PLUGIN_DIR="C:\Projetos\rainforest-mind\.claude\worktrees\agent-aff97fb23fcc0138d"
REPO_TESTE=$(mktemp -d)
trap "rm -rf '$REPO_TESTE'" EXIT

# Inicializa repo em subshell para não sair do diretório
bash -c "
cd '$REPO_TESTE'
git init --initial-branch=main >/dev/null 2>&1
cp '$PLUGIN_DIR/skills/rainforest-mind/SKILL.md' .
git add SKILL.md
git commit -m 'inicial' >/dev/null 2>&1
"

echo "=== Bateria de testes para conferir-ponte.cjs ==="
echo ""

# CENÁRIO 1: Gerar a ponte, conferir → verde
echo "1. Gerar e conferir bloco novo → esperado verde"
node "$PLUGIN_DIR/scripts/ponte.cjs" --alvo "$REPO_TESTE" --agente claude --aplicar >/dev/null 2>&1
resultado=$(node "$PLUGIN_DIR/scripts/conferir-ponte.cjs" "$REPO_TESTE/CLAUDE.md" 2>&1)
if echo "$resultado" | grep -q "CONFERIDO"; then
  echo "   ✓ Verde conforme esperado"
else
  echo "   ✗ FALHOU: deveria ter sido verde"
  echo "$resultado"
  exit 1
fi
echo ""

# CENÁRIO 2: Editar uma linha do arquivo gerado à mão → vermelho (editado à mão)
echo "2. Editar linha do bloco gerado à mão → esperado vermelho (editado)"
sed -i 's/## O que NAO vale/## TESTE MODIFICADO/' "$REPO_TESTE/CLAUDE.md"
grep -q "TESTE MODIFICADO" "$REPO_TESTE/CLAUDE.md" || echo "AVISO: sed não funcionou como esperado"
resultado=$(node "$PLUGIN_DIR/scripts/conferir-ponte.cjs" "$REPO_TESTE/CLAUDE.md" 2>&1)
if echo "$resultado" | grep -q "editado"; then
  echo "   ✓ Vermelho conforme esperado (detectou edição à mão)"
else
  echo "   ✗ FALHOU: deveria ter detectado edição à mão"
  echo "$resultado"
  exit 1
fi
echo ""

# Restaura o arquivo
bash -c "cd '$REPO_TESTE' && git checkout SKILL.md 2>/dev/null || true"
node "$PLUGIN_DIR/scripts/ponte.cjs" --alvo "$REPO_TESTE" --agente claude --aplicar >/dev/null 2>&1

# CENÁRIO 3: Mudar regra no SKILL.md sem regerar → vermelho (ficou para trás)
echo "3. Mudar SKILL.md sem regerar → esperado vermelho (ficou para trás)"
echo "" >> "$REPO_TESTE/SKILL.md"
echo "## Uma regra nova que sumiu" >> "$REPO_TESTE/SKILL.md"
resultado=$(node "$PLUGIN_DIR/scripts/conferir-ponte.cjs" "$REPO_TESTE/CLAUDE.md" 2>&1)
if echo "$resultado" | grep -q "ficou para trás\|SKILL.md mudou"; then
  echo "   ✓ Vermelho conforme esperado (detectou SKILL.md desatualizado)"
else
  echo "   ✗ FALHOU: deveria ter detectado SKILL.md desatualizado"
  echo "$resultado"
  exit 1
fi
echo ""

# Restaura SKILL.md e CLAUDE.md
bash -c "cd '$REPO_TESTE' && git checkout SKILL.md 2>/dev/null || true"
node "$PLUGIN_DIR/scripts/ponte.cjs" --alvo "$REPO_TESTE" --agente claude --aplicar >/dev/null 2>&1

# CENÁRIO 4: Bloco legado sem hash, com conteúdo divergente → vermelho (ambíguo)
echo "4. Bloco legado sem hash, divergente → esperado vermelho (ambíguo)"
node "$PLUGIN_DIR/scripts/ponte.cjs" --alvo "$REPO_TESTE" --agente claude --aplicar >/dev/null 2>&1
sed -i 's/hash:[0-9a-f]* — //' "$REPO_TESTE/CLAUDE.md"
sed -i 's/## O que NAO vale/## Mudei isso a mano/' "$REPO_TESTE/CLAUDE.md"
resultado=$(node "$PLUGIN_DIR/scripts/conferir-ponte.cjs" "$REPO_TESTE/CLAUDE.md" 2>&1)
if echo "$resultado" | grep -q "desatualizado\|editado"; then
  echo "   ✓ Vermelho conforme esperado (não dá para distinguir)"
else
  echo "   ✗ FALHOU: deveria ter indicado ambiguidade"
  echo "$resultado"
  exit 1
fi
echo ""

# MUTAÇÃO: Sabota a comparação, verifica que o caso verde para de pegar
echo "5. Mutação: sabota a comparação no conferir-ponte.cjs"
CONFERIR_SABOTADO=$(mktemp)
cat "$PLUGIN_DIR/scripts/conferir-ponte.cjs" | \
  sed 's/if (textoIgual(conteudoAtual, conteudoEsperado))/if (false)/' > "$CONFERIR_SABOTADO"
chmod +x "$CONFERIR_SABOTADO"

bash -c "cd '$REPO_TESTE' && git checkout SKILL.md 2>/dev/null || true"
node "$PLUGIN_DIR/scripts/ponte.cjs" --alvo "$REPO_TESTE" --agente claude --aplicar >/dev/null 2>&1

resultado=$(node "$CONFERIR_SABOTADO" "$REPO_TESTE/CLAUDE.md" 2>&1) || true
if echo "$resultado" | grep -q "RECUSADO\|ficou para trás"; then
  echo "   ✓ Mutação funciona: sabotagem foi detectada"
else
  echo "   ✗ FALHOU: mutação não causou o efeito esperado"
  rm -f "$CONFERIR_SABOTADO"
  exit 1
fi
rm -f "$CONFERIR_SABOTADO"
echo ""

echo "=== Todas as 5 baterias passaram ==="
exit 0
