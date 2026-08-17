#!/bin/bash

# Script de teste para memoria.cjs — critério de sucesso do plano.
# CONFIRMA: 1. Iniciar banco com RFM_ROOT temp
#           2. Esquema retorna JSON com chaves esperadas
#           3. Arquivo está em <RFM_ROOT>/rainforest.db
#           4. Coluna 'projeto' presente em 'observacoes'

set -e

TMPDIR=$(mktemp -d)
echo "Teste em: $TMPDIR"
echo

# 1. Iniciar o banco
echo "=== 1. Iniciar banco ==="
RFM_ROOT="$TMPDIR" node scripts/memoria.cjs iniciar
RESULT=$?
echo "Exit code: $RESULT"
echo

# 2. Obter schema em JSON
echo "=== 2. Schema em JSON ==="
RFM_ROOT="$TMPDIR" node scripts/memoria.cjs esquema --json
RESULT=$?
echo
echo "Exit code: $RESULT"
echo

# 3. Verificar arquivo
echo "=== 3. Verificar arquivo ==="
if [ -f "$TMPDIR/rainforest.db" ]; then
  echo "✓ Arquivo encontrado: $TMPDIR/rainforest.db"
  ls -lh "$TMPDIR/rainforest.db"
else
  echo "✗ Arquivo NÃO encontrado em $TMPDIR/rainforest.db"
  exit 1
fi
echo

# 4. Verificar coluna 'projeto' em 'observacoes'
echo "=== 4. Verificar coluna 'projeto' ==="
RFM_ROOT="$TMPDIR" node -e "
const { abrirBanco, extrairSchema } = require('./scripts/memoria.cjs');
const path = require('path');
const conexao = abrirBanco('$TMPDIR/rainforest.db');
const schema = extrairSchema(conexao);
conexao.close();

const temObservacoes = 'observacoes' in schema;
const temProjeto = temObservacoes && 'projeto' in schema.observacoes;

console.log('Schema tem tabelas:', Object.keys(schema).join(', '));
console.log('observacoes existe?', temObservacoes);
console.log('observacoes.projeto existe?', temProjeto);

if (!temProjeto) {
  console.error('✗ FALHA: coluna projeto não encontrada');
  process.exit(1);
}
console.log('✓ Coluna projeto presente em observacoes');
"

echo
echo "=== Cleanup ==="
rm -rf "$TMPDIR"
echo "✓ Teste concluído com sucesso"
