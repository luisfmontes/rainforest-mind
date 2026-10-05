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
  local arquivo="$1" crase=$'\x60'
  # Tres formas do mesmo vetor (o executavel resolvido pela busca de nome, que no
  # Windows olha a pasta atual antes do PATH):
  #  - spawn/exec*("node" ou 'node', ...)
  #  - exec/execSync com o comando inteiro numa template literal que comeca por node
  #  - cmd = "node"; (o nome guardado numa variavel que vai para o spawn); campo de
  #    objeto (resultado.stack = "node") e rotulo, nao comando, e fica de fora
  grep -nE "(spawn|spawnSync|execFile|execFileSync|exec|execSync)[[:space:]]*\([[:space:]]*(['\"]node['\"]|${crase}node[[:space:]])|(^|[^.[:alnum:]_$])[[:alpha:]_$][[:alnum:]_$]*[[:space:]]*=[[:space:]]*['\"]node['\"][[:space:]]*;" "$arquivo" || true
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
  # Pelo nome do arquivo, nao pelo caminho: um clone em pasta com "testa-" no nome
  # pulava tudo e o caso passava vazio.
  [[ "$(basename "$arquivo")" == testa-* ]] && continue

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

# =========== Caso 3: as outras formas do mesmo vetor tambem acendem ===========
echo "3. detector acende nas formas execSync(template), variavel = node e execFileSync"
echo
arquivo_formas="$SBP/teste-formas.cjs"
cat > "$arquivo_formas" <<'EOF'
const { execSync, execFileSync, spawnSync } = require('child_process');
execSync(`node "${hookPath}"`, {});
let cmd = "bash";
cmd = "node";
execFileSync("node", [x]);
const runtime = 'node-ish';
resultado.stack = "node";
EOF
n_formas="$(detectar_node_por_nome "$arquivo_formas" | wc -l | tr -d ' ')"
if [ "$n_formas" = "3" ]; then
  ok=$((ok+1))
  echo "  ok   as tres formas acendem, e os falsos parecidos nao"
else
  falhou=$((falhou+1))
  echo "  FALHA esperava 3 linhas detectadas, vieram $n_formas"
  detectar_node_por_nome "$arquivo_formas"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
