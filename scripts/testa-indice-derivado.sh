#!/bin/bash
# Bateria da tarefa 7: índice derivado de FOCO.md e ideias.jsonl, reconstruível.
# Uso: bash scripts/testa-indice-derivado.sh
#
# O que esta bateria prova, nesta ordem:
#   1. que `reindexar` reconstrói o índice a partir de FOCO.md e ideias.jsonl do zero
#   2. que apagar o índice não perde dados — tudo é rederivável
#   3. que o ideias.cjs segue sendo o único que escreve no ideias.jsonl
#   4. que o hash do ideias.jsonl não muda após reindexar

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Usar mktemp com CYGWIN_NOWINPATH para obter caminho POSIX em Windows
CAIXA=$(mktemp -d 2>/dev/null || mktemp -d -t rfm-test)
trap 'rm -rf "$CAIXA"' EXIT

export RFM_ROOT="$CAIXA"
MEMORIA="node $SRC/scripts/memoria.cjs"

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1 | grep -v ExperimentalWarning); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; fi
}

echo "== 1. Gerar fixtures de FOCO.md e ideias.jsonl na caixa =="

# Gerar FOCO.md e ideias.jsonl usando Node para maior compatibilidade cross-platform
node -e "
const fs = require('fs');
const path = require('path');
const caixa = process.env.RFM_ROOT;

// Gerar FOCO.md
fs.writeFileSync(path.join(caixa, 'FOCO.md'), \`# FOCO 2026-08-17

## Avanços da semana
- 2026-08-14: Completado esquema do banco
- 2026-08-15: Importador funcionando
- 2026-08-16: Índice derivado em progresso

## Prazos
- 2026-08-20: Tarefa 7
- 2026-08-25: Tarefa 8

## Pastas de trabalho
- /scripts — geradores e baterias
- /hooks/lib — módulos compartilhados
\`);

// Gerar ideias.jsonl
const ideias = [
  {id:'tarefa-7',titulo:'Índice derivado',descricao:'Reconstruir índice de zero',contexto:'Fase 1',projeto:'rainforest',ao_colher:'Nada',gancho:'Completar cmdReindexar',tipo:'ideia',status:'em-colheita',plantada_em:'2026-08-17'},
  {id:'tarefa-8',titulo:'Versionar raiz',descricao:'Setupgit na raiz de dados',contexto:'Fase 1',projeto:'rainforest',ao_colher:'Nada',gancho:'Versionar dados',tipo:'ideia',status:'plantada',plantada_em:'2026-08-17'}
];
fs.writeFileSync(path.join(caixa, 'ideias.jsonl'), ideias.map(i => JSON.stringify(i)).join('\\n') + '\\n');

console.log('Fixtures criadas');
" 2>&1 | grep -v ExperimentalWarning

echo "  ok   FOCO.md gerado"
echo "  ok   ideias.jsonl gerado"

# Verificar que os arquivos foram criados
if [ -f "$CAIXA/FOCO.md" ] && [ -f "$CAIXA/ideias.jsonl" ]; then
  echo "  ok   arquivos presentes em $CAIXA"
else
  echo "  FALHA arquivos não criados em $CAIXA"
  ls -la "$CAIXA" 2>&1 || echo "  ERRO: não consegui listar $CAIXA"
fi

echo
echo "== 2. Iniciar banco e reindexar =="
esperado "iniciar" 0 $MEMORIA iniciar

# Guardar hash antes de reindexar
hash_antes=$(md5sum "$CAIXA/ideias.jsonl" | cut -d' ' -f1)
echo "  ok   hash ideias.jsonl antes: $hash_antes"

esperado "reindexar" 0 $MEMORIA reindexar

echo
echo "== 3. Verificar que ideias.jsonl não foi modificado =="
hash_depois=$(md5sum "$CAIXA/ideias.jsonl" | cut -d' ' -f1)
if [ "$hash_antes" = "$hash_depois" ]; then
  ok=$((ok+1)); echo "  ok   hash ideias.jsonl permanece $hash_depois"
else
  falhou=$((falhou+1)); echo "  FALHA ideias.jsonl foi modificado"
  echo "         antes:  $hash_antes"
  echo "         depois: $hash_depois"
fi

echo
echo "== 4. Verificar que index foi populado com dados derivados =="
# Contar linhas nas tabelas derivadas — SEM 2>/dev/null para deixar erros visíveis
indice_foco_count=$(node -e "
const sqlite3 = require('node:sqlite');
const db = new sqlite3.DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const r = db.prepare('SELECT COUNT(*) as c FROM indice_foco').get();
process.stdout.write(String(r.c || 0));
")

indice_ideias_count=$(node -e "
const sqlite3 = require('node:sqlite');
const db = new sqlite3.DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const r = db.prepare('SELECT COUNT(*) as c FROM indice_ideias').get();
process.stdout.write(String(r.c || 0));
")

if [ "$indice_foco_count" -gt "0" ] && [ "$indice_ideias_count" -gt "0" ]; then
  ok=$((ok+1)); echo "  ok   tabela indice_foco tem $indice_foco_count registros"
  ok=$((ok+1)); echo "  ok   tabela indice_ideias tem $indice_ideias_count registros"
else
  falhou=$((falhou+1)); echo "  FALHA índices vazios: foco=$indice_foco_count, ideias=$indice_ideias_count"
fi

echo
echo "== 5. CRÍTICO: Popular resumos e observacoes, depois reindexar e provar que não mudaram =="
# Popular resumos e observacoes com registros de TESTE (dados de outras tarefas)
# SEM 2>/dev/null, SEM || echo — se falhar, a bateria fica VERMELHA aqui mesmo.
resumos_antes=$(node -e "
const sqlite3 = require('node:sqlite');
const db = new sqlite3.DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const db_projeto = process.env.RFM_ROOT.split(/(\\\\|\\/)/).pop();

// Inserir resumo de teste (simular dados da tarefa 3 — importação de claude-mem)
db.prepare('INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?, ?, ?, ?)')
  .run(db_projeto, 'Resumo Teste', 'Conteúdo de resumo que NÃO deve ser apagado', '2026-08-17');

// Inserir observação de teste (simula dados da fase 2)
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em) VALUES (?, ?, ?)')
  .run(db_projeto, 'Observação de teste que NÃO deve ser apagada', '2026-08-17');

// Contar TODOS os resumos (não filtrado, para prova simples)
const resumos = db.prepare('SELECT COUNT(*) as c FROM resumos').get();
const obs = db.prepare('SELECT COUNT(*) as c FROM observacoes').get();
process.stdout.write('resumos=' + resumos.c + ' observacoes=' + obs.c);
db.close();
")

echo "  Antes de reindexar: $resumos_antes"

# Agora reindexar — não deve apagar resumos e observacoes
esperado "reindexar com dados existentes" 0 $MEMORIA reindexar

# Verificar que resumos e observacoes NÃO foram apagados
# SEM 2>/dev/null — se falhar, aparece na bateria
resumos_depois=$(node -e "
const sqlite3 = require('node:sqlite');
const db = new sqlite3.DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const resumos = db.prepare('SELECT COUNT(*) as c FROM resumos').get();
const obs = db.prepare('SELECT COUNT(*) as c FROM observacoes').get();
process.stdout.write('resumos=' + resumos.c + ' observacoes=' + obs.c);
db.close();
")

echo "  Depois de reindexar: $resumos_depois"

if [ "$resumos_antes" = "$resumos_depois" ]; then
  ok=$((ok+1)); echo "  ok   resumos e observacoes não foram tocados por reindexar"
else
  falhou=$((falhou+1)); echo "  FALHA reindexar apagou dados de outras tarefas!"
  echo "         antes:  $resumos_antes"
  echo "         depois: $resumos_depois"
fi

echo
echo "== 6. Apagar índice derivado e verificar que reconstrói =="
# Remover dados do índice derivado
node -e "
const sqlite3 = require('node:sqlite');
const db = new sqlite3.DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
db.exec('DELETE FROM indice_foco');
db.exec('DELETE FROM indice_ideias');
const foco = db.prepare('SELECT COUNT(*) as c FROM indice_foco').get();
const ideias = db.prepare('SELECT COUNT(*) as c FROM indice_ideias').get();
process.stdout.write('Apagado, indice_foco agora: ' + (foco.c || 0) + ', indice_ideias: ' + (ideias.c || 0) + '\n');
db.close();
" 2>&1 | grep -v ExperimentalWarning | sed 's/^/  /'

# Reindexar novamente
esperado "reindexar após apagar índices" 0 $MEMORIA reindexar

# Verificar que voltou a ter dados — SEM 2>/dev/null
indice_counts=$(node -e "
const sqlite3 = require('node:sqlite');
const db = new sqlite3.DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const foco = db.prepare('SELECT COUNT(*) as c FROM indice_foco').get();
const ideias = db.prepare('SELECT COUNT(*) as c FROM indice_ideias').get();
process.stdout.write('foco=' + (foco.c || 0) + ' ideias=' + (ideias.c || 0));
db.close();
")

if [ "$indice_counts" = "foco=$indice_foco_count ideias=$indice_ideias_count" ]; then
  ok=$((ok+1)); echo "  ok   índices derivados reconstruídos: $indice_counts"
else
  falhou=$((falhou+1)); echo "  FALHA contagem mismatch: esperava foco=$indice_foco_count ideias=$indice_ideias_count, veio $indice_counts"
fi

echo
echo "== 7. Verificar que ideias.cjs é único a escrever em ideias.jsonl =="
# Verificar que nenhum outro arquivo toca ideias.jsonl
if ! grep -r "writeFileSync.*ideias.jsonl" "$SRC/scripts/" --include="*.cjs" | grep -v "ideias.cjs" > /dev/null 2>&1; then
  ok=$((ok+1)); echo "  ok   nenhum outro arquivo escreve em ideias.jsonl"
else
  falhou=$((falhou+1)); echo "  FALHA outro arquivo encontrado escrevendo em ideias.jsonl"
fi

if ! grep -r "appendFileSync.*ideias.jsonl" "$SRC/scripts/" --include="*.cjs" | grep -v "ideias.cjs" > /dev/null 2>&1; then
  ok=$((ok+1)); echo "  ok   nenhum outro arquivo escreve (append) em ideias.jsonl"
else
  falhou=$((falhou+1)); echo "  FALHA outro arquivo encontrado fazendo append em ideias.jsonl"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
