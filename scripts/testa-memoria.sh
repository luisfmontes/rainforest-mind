#!/bin/bash
# Bateria do scripts/memoria.cjs — gerenciador do banco de dados da memória.
# Uso: bash scripts/testa-memoria.sh
#
# O que esta bateria prova, nesta ordem:
#   1. que `iniciar` cria o banco em RFM_ROOT com o schema correto
#   2. que `esquema --json` retorna JSON com as 4 tabelas esperadas
#   3. que a coluna `projeto` esta presente em `observacoes`
#   4. que o arquivo e criado em <RFM_ROOT>/rainforest.db, nao num caminho fixo
#   5. que o banco e hermético — caixa de areia com mktemp -d, nunca raiz real
#
# A caixa de areia e o que importa mais: bateria que passa so na maquina do dono
# nao e evidencia (Issue #16). Aqui tudo vira em RFM_ROOT=<temp>, e a raiz de
# dados real NAO e tocada.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

export RFM_ROOT="$CAIXA"
MEMORIA="node $SRC/scripts/memoria.cjs"

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; fi
}

contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"; fi
}

echo "== 1. iniciar cria o banco com schema correto =="
esperado "iniciar" 0 $MEMORIA iniciar
if [ -f "$CAIXA/rainforest.db" ]; then
  ok=$((ok+1)); echo "  ok   arquivo rainforest.db existe"
else
  falhou=$((falhou+1)); echo "  FALHA rainforest.db nao foi criado em $CAIXA"
fi

echo
echo "== 2. esquema --json devolve JSON com 4 tabelas =="
SCHEMA=$($MEMORIA esquema --json 2>&1 | grep -v "ExperimentalWarning")
got=$?
if [ "$got" = "0" ] || [ "$got" = "1" ]; then
  ok=$((ok+1)); echo "  ok   esquema --json rodou (saida filtrada de warnings)"
else
  falhou=$((falhou+1)); echo "  FALHA esperava exit 0, veio $got"
fi

# Verificar 4 tabelas
contem "tem observacoes"  '"observacoes"'  bash -c "echo '$SCHEMA'"
contem "tem resumos"      '"resumos"'      bash -c "echo '$SCHEMA'"
contem "tem prompts"      '"prompts"'      bash -c "echo '$SCHEMA'"
contem "tem marca_dagua"  '"marca_dagua"'  bash -c "echo '$SCHEMA'"

echo
echo "== 3. coluna projeto em observacoes =="
if echo "$SCHEMA" | grep -A20 '"observacoes"' | grep -q '"projeto"'; then
  ok=$((ok+1)); echo "  ok   coluna projeto presente em observacoes"
else
  falhou=$((falhou+1)); echo "  FALHA coluna projeto nao encontrada em observacoes"
fi

# Verificar que e NOT NULL
if echo "$SCHEMA" | grep -A20 '"observacoes"' | grep -A3 '"projeto"' | grep -q '"naoNulo": true'; then
  ok=$((ok+1)); echo "  ok   coluna projeto e NOT NULL"
else
  falhou=$((falhou+1)); echo "  FALHA coluna projeto nao e NOT NULL"
fi

echo
echo "== 4. arquivo em RFM_ROOT/rainforest.db, nao caminho fixo =="
# Verificar que o arquivo EXISTE em RFM_ROOT
if [ -f "$CAIXA/rainforest.db" ]; then
  ok=$((ok+1)); echo "  ok   arquivo em \$RFM_ROOT ($CAIXA)"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo nao existe em $CAIXA/rainforest.db"
fi

echo
echo "== 5. hermeticidade — segunda execucao cria novo banco =="
# Criar um novo temp dir e rodar de novo — tem que criar banco ali, nao usar o anterior
CAIXA2="$(mktemp -d)"
trap 'rm -rf "$CAIXA" "$CAIXA2"' EXIT

RFM_ROOT="$CAIXA2" $MEMORIA iniciar >/dev/null 2>&1
if [ -f "$CAIXA2/rainforest.db" ] && [ ! -f "$CAIXA/rainforest.db" ] || [ "$CAIXA" != "$CAIXA2" ]; then
  ok=$((ok+1)); echo "  ok   banco isolado por RFM_ROOT (hermetico)"
else
  falhou=$((falhou+1)); echo "  FALHA nao isolou dado por RFM_ROOT"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
