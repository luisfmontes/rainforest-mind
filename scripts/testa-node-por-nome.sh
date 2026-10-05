#!/bin/bash
# Bateria de deteccao de chamadas ao node por nome em vez de process.execPath.
# Varre hooks/*.cjs, hooks/lib/*.cjs, scripts/*.cjs, scripts/lib/*.cjs
# (excluindo testa-*) procurando por spawn/spawnSync/execFile/execFileSync/exec/execSync
# que usam a string 'node' ou "node" como primeiro argumento.
# @categoria: bateria

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

ok=0
falhou=0

# Funcao auxiliar para reportar falhas
relatorio_falha() {
  local arquivo="$1"
  local linha="$2"
  echo "  FALHA $arquivo:$linha"
  falhou=$((falhou+1))
}

# Detecta spawn/exec com 'node' ou "node" como primeiro argumento
detectar_node_por_nome() {
  local arquivo="$1"
  # Procura por chamadas spawn/spawnSync/execFile/execFileSync/exec/execSync
  # cujo primeiro argumento seja a string 'node' ou "node"
  # Padrao: (spawn|spawnSync|execFile|execFileSync|exec|execSync)\s*\(\s*['"']node['"]
  grep -n "\(spawn\|spawnSync\|execFile\|execFileSync\|exec\|execSync\)\s*(\s*['\"]node['\"]" "$arquivo" || true
}

echo "== Deteccao de chamadas ao node por nome (process.execPath obrigatorio) =="
echo

# =========== Caso 1: nenhum spawn/exec de node por nome fora de bateria ===========
echo "1. nenhum spawn/exec de node por nome fora de bateria"
echo

encontrou_algum=0
lista_erros=""

for arquivo in "$SRC"/hooks/*.cjs "$SRC"/hooks/lib/*.cjs "$SRC"/scripts/*.cjs "$SRC"/scripts/lib/*.cjs; do
  # Skip files that don't exist or are test files
  [ -f "$arquivo" ] || continue
  [[ "$arquivo" == *testa-* ]] && continue

  resultado="$(detectar_node_por_nome "$arquivo")"
  if [ -n "$resultado" ]; then
    encontrou_algum=1
    while IFS= read -r linha; do
      num_linha="$(echo "$linha" | cut -d: -f1)"
      lista_erros="$lista_erros
  $(basename "$arquivo"):$num_linha"
    done <<< "$resultado"
  fi
done

if [ "$encontrou_algum" -eq 0 ]; then
  ok=$((ok+1))
  echo "  ok   nenhum spawn/exec de node por nome fora de bateria"
else
  falhou=$((falhou+1))
  echo "  FALHA encontradas chamadas de node por nome:"
  echo "$lista_erros"
fi

echo

# =========== Caso 2: detector acende com arquivo plantado ===========
echo "2. detector acende plantando spawn('node', [...]) numa pasta temporaria"
echo

SBP="$(novo_sandbox)"
arquivo_teste="$SBP/teste-node-por-nome.cjs"

# Planta um arquivo com spawn('node', [...]) para testar a deteccao
cat > "$arquivo_teste" <<'EOF'
const { spawn } = require('child_process');
spawn('node', ['script.js']);
EOF

# Confere que o arquivo plantado eh detectado
resultado_teste="$(detectar_node_por_nome "$arquivo_teste")"

if [ -n "$resultado_teste" ]; then
  ok=$((ok+1))
  echo "  ok   detector identificou spawn('node', [...]) no arquivo de teste"
  echo "       detectado em: $(echo "$resultado_teste" | sed 's/^\([^:]*\):.*/\1/')"
else
  falhou=$((falhou+1))
  echo "  FALHA detector nao identificou spawn('node', [...]) plantado no teste"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
