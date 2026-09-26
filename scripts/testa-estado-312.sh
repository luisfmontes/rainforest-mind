#!/bin/bash
# Teste focado em #312 — teto do carimbo lê o arquivo do plano

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)/caixa-312"
trap 'rm -rf "$(dirname "$SBP")"' EXIT

mkdir -p "$SBP/scripts/lib" "$SBP/hooks/lib"
cp "$SRC/scripts/estado.cjs" "$SBP/scripts/"
cp "$SRC/scripts/conferir-fluxo.cjs" "$SBP/scripts/"
cp "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SBP/scripts/lib/"
cp "$SRC/scripts/lib/extrair-veredito.cjs" "$SBP/scripts/lib/"
cp "$SRC/hooks/lib/raiz.cjs" "$SBP/hooks/lib/"
cp "$SRC/hooks/lib/config.cjs" "$SBP/hooks/lib/"
cp "$SRC/hooks/lib/trava-jsonl.cjs" "$SBP/hooks/lib/"
touch "$SBP/FOCO.md"
cd "$SBP" || exit 1
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
E="node scripts/estado.cjs"
HOME_SBOX="$SBP/home"
mkdir -p "$HOME_SBOX"
export HOME="$HOME_SBOX"
export USERPROFILE="$HOME_SBOX"
export CLAUDE_CONFIG_DIR="$HOME_SBOX/.claude-personal"

echo "== (#312) carimbo de tarefa acrescentada por emenda =="
mkdir -p "$SBP/plano-arquivo"
export RFM_ESTADO_ROOT="$SBP/plano-arquivo"

# Criar arquivo de plano com tarefas 1 a 8
mkdir -p "$SBP/plano-arquivo/docs/rainforest/planos"
cat > "$SBP/plano-arquivo/docs/rainforest/planos/teste-312.md" << 'PLANOEOF'
# Plano de Teste 312

## Tarefas

### 1. Primeira tarefa
Descrição.

### 2. Segunda tarefa
Descrição.

### 3. Terceira tarefa
Descrição.

### 4. Quarta tarefa
Descrição.

### 5. Quinta tarefa
Descrição.

### 6. Sexta tarefa
Descrição.

### 7. Sétima tarefa
Descrição.

### 8. Oitava tarefa
Descrição.
PLANOEOF

# Inicializar fluxo
$E iniciar --slug teste-312 --titulo "Teste 312" >/dev/null

# Atualizar manualmente o estado para apontar para o arquivo do plano e fechar pré-requisitos
node -e '
const fs = require("fs");
const e = JSON.parse(fs.readFileSync("plano-arquivo/docs/rainforest/estado/teste-312.json", "utf8"));
e.design = { status: "ok" };
e.plano = {
  status: "ok",
  arquivo: "docs/rainforest/planos/teste-312.md",
  tarefas: 6
};
fs.writeFileSync("plano-arquivo/docs/rainforest/estado/teste-312.json", JSON.stringify(e, null, 2) + "\n");
'

# Caso 1: Carimbo da tarefa 8 GRAVA (o maior número do arquivo)
msg1=$($E marcar --slug teste-312 --estagio executar --status parcial --json "{\"carimbos\":[{\"tarefa\":8,\"hash_base\":\"abc1234\"}]}" 2>&1)
cod1=$?
if [ "$cod1" = "0" ]; then
  ok=$((ok+1)); echo "  ok   tarefa 8 (max do arquivo): carimbo grava (exit 0)"
else
  falhou=$((falhou+1)); echo "  FALHA tarefa 8: esperava exit 0, veio $cod1"; printf '%s\n' "$msg1" | sed 's/^/         /'
fi

# Caso 2: Carimbo da tarefa 9 RECUSA nomeando 1..8 (maior do arquivo)
msg2=$($E marcar --slug teste-312 --estagio executar --status parcial --json "{\"carimbos\":[{\"tarefa\":9,\"hash_base\":\"abc1234\"}]}" 2>&1)
cod2=$?
if [ "$cod2" = "2" ] && printf '%s' "$msg2" | grep -q "1..8"; then
  ok=$((ok+1)); echo "  ok   tarefa 9 (acima do arquivo): recusa, mensagem nomeia 1..8"
else
  falhou=$((falhou+1)); echo "  FALHA tarefa 9: esperava exit 2 com '1..8', veio exit=$cod2"; printf '%s\n' "$msg2" | sed 's/^/         /'
fi

# Caso 3: Sem arquivo, carimbo 7 recusa com 1..6 (do plano.tarefas)
# Remover o arquivo do plano
rm "$SBP/plano-arquivo/docs/rainforest/planos/teste-312.md"
msg3=$($E marcar --slug teste-312 --estagio executar --status parcial --json "{\"carimbos\":[{\"tarefa\":7,\"hash_base\":\"abc1234\"}]}" 2>&1)
cod3=$?
if [ "$cod3" = "2" ] && printf '%s' "$msg3" | grep -q "1..6"; then
  ok=$((ok+1)); echo "  ok   sem arquivo: carimbo 7 recusa com 1..6 (do plano.tarefas)"
else
  falhou=$((falhou+1)); echo "  FALHA sem arquivo: esperava exit 2 com '1..6', veio exit=$cod3"; printf '%s\n' "$msg3" | sed 's/^/         /'
fi

unset RFM_ESTADO_ROOT

echo "== resultado: $ok ok, $falhou falhas =="
[ "$falhou" = 0 ]
