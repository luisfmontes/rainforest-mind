#!/bin/bash
# Bateria do teto de tamanho para skills. Mede linhas e bytes de cada SKILL.md
# e falha se alguma ultrapassar os limites. Depois roda auto-teste em caixa de
# areia para provar que a bateria funciona.
# Uso: bash scripts/testa-teto-skills.sh
#
# Protege contra: skills crescendo sem limite (815, 665, 548, 504 linhas no data-skills)
# Não protege contra: skill que cabe no teto mas tem conteúdo ruim

set -u
SKILLS_DIR="${SKILLS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills}"
TETO_LINHAS=500
TETO_BYTES=16384

ok=0; falhou=0

# Função para medir uma skill em um diretório
medir_skills() {
  local dir="$1"
  local locais_ok=0 locais_falhou=0

  for skill_dir in "$dir"/*; do
    [ -d "$skill_dir" ] || continue
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    local skill=$(basename "$skill_dir")
    local linhas=$(wc -l < "$skill_file")
    local bytes=$(wc -c < "$skill_file")

    if [ "$linhas" -gt "$TETO_LINHAS" ]; then
      echo "  FALHA $skill: $linhas linhas > $TETO_LINHAS"
      echo "         Mova referência para references/ ou arquivo irmão"
      locais_falhou=$((locais_falhou+1))
    elif [ "$bytes" -gt "$TETO_BYTES" ]; then
      echo "  FALHA $skill: $bytes B > $TETO_BYTES"
      echo "         Mova referência para references/ ou arquivo irmão"
      locais_falhou=$((locais_falhou+1))
    else
      echo "  ok   $skill ${linhas}L ${bytes}B"
      locais_ok=$((locais_ok+1))
    fi
  done

  ok=$((ok+locais_ok))
  falhou=$((falhou+locais_falhou))
}

echo "== Medindo teto de skills no repositório =="
medir_skills "$SKILLS_DIR"

echo
echo "== Auto-teste em caixa de areia =="
# Monta diretório temporário com skills de teste
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

# Cria skill com 501 linhas (passa limite)
mkdir -p "$RAIZ/skill-grande"
{
  echo "# Skill Grande"
  for i in $(seq 1 500); do
    echo "Linha $i"
  done
} > "$RAIZ/skill-grande/SKILL.md"

# Cria skill com 16.385 bytes (passa limite)
mkdir -p "$RAIZ/skill-pesada"
{
  echo "# Skill Pesada"
  # Gera suficiente conteúdo para passar de 16.384 bytes. Só Node: a catraca
  # testa-dependencias-de-bateria.sh recusa python/jq/rg pelo nome (Issues
  # #157-#159), e Node e a unica dependencia que o CONTRIBUTING promete.
  node -e "process.stdout.write('x'.repeat(16385))"
} > "$RAIZ/skill-pesada/SKILL.md"

# Roda a bateria na caixa de areia com contadores separados
echo "(testando com skills que excedem limites)"
ok_auto=0; falhou_auto=0
for skill_dir in "$RAIZ"/*; do
  [ -d "$skill_dir" ] || continue
  skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || continue

  skill=$(basename "$skill_dir")
  linhas=$(wc -l < "$skill_file")
  bytes=$(wc -c < "$skill_file")

  if [ "$linhas" -gt "$TETO_LINHAS" ]; then
    echo "  FALHA $skill: $linhas linhas > $TETO_LINHAS"
    echo "         Mova referência para references/ ou arquivo irmão"
    falhou_auto=$((falhou_auto+1))
  elif [ "$bytes" -gt "$TETO_BYTES" ]; then
    echo "  FALHA $skill: $bytes B > $TETO_BYTES"
    echo "         Mova referência para references/ ou arquivo irmão"
    falhou_auto=$((falhou_auto+1))
  else
    echo "  ok   $skill ${linhas}L ${bytes}B"
    ok_auto=$((ok_auto+1))
  fi
done

# Valida que o auto-teste detectou falhas
if [ "$falhou_auto" -ne 2 ]; then
  echo "  FALHA auto-teste: esperava 2 falhas, obteve $falhou_auto"
  falhou=$((falhou+1))
fi

echo
echo "Resultado: $ok OK, $falhou FALHA"
if [ "$falhou" -eq 0 ]; then
  exit 0
else
  exit 1
fi
