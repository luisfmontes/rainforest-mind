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
# Achado 4 da tarefa 22: `$? depois de um pipe` media o grep, nunca o
# memoria.cjs — e a asserção ainda aceitava exit 0 OU 1, escondendo qualquer
# falha real do memoria.cjs atrás do exit code do grep de filtragem.
# PIPESTATUS não ajuda aqui: dentro de `$(cmd1 | cmd2)`, o array PIPESTATUS
# do shell externo NÃO é atualizado pelo pipeline que roda na subshell da
# substituição de comando (confirmado testando à parte: `PIPESTATUS[0]` depois
# de `x=$(f | g)` continua com o valor de antes, não o do `f` interno). A forma
# correta é não canalizar dentro do `$(...)`: captura o exit code real do
# memoria.cjs primeiro, sem pipe, e só depois filtra o texto para exibição.
RAW=$($MEMORIA esquema --json 2>&1)
got=$?
SCHEMA=$(printf '%s\n' "$RAW" | grep -v "ExperimentalWarning")
if [ "$got" = "0" ]; then
  ok=$((ok+1)); echo "  ok   esquema --json saiu 0 (saida filtrada de warnings)"
else
  falhou=$((falhou+1)); echo "  FALHA esquema --json esperava exit 0, veio $got"
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
echo "== 5. hermeticidade — segunda execucao em RFM_ROOT diferente nao toca o banco anterior =="
# Achado 3 da tarefa 22: a condicao antiga era `[ A ] && [ B ] || [ C ]`, que
# em shell avalia como `(A && B) || C`. C era `[ "$CAIXA" != "$CAIXA2" ]` —
# sempre verdadeiro, porque sao dois `mktemp -d` distintos por construcao.
# O teste passava mesmo que RFM_ROOT parasse de ser respeitado. A prova real
# de hermeticidade precisa das DUAS coisas ao mesmo tempo, em AND: (1) o
# banco novo aparece em CAIXA2, e (2) o banco em CAIXA (criado na secao 1)
# continua BYTE A BYTE igual — nao foi tocado pela segunda chamada.
cp "$CAIXA/rainforest.db" "$CAIXA/.snapshot-antes-caixa2"
CAIXA2="$(mktemp -d)"
trap 'rm -rf "$CAIXA" "$CAIXA2"' EXIT

RFM_ROOT="$CAIXA2" $MEMORIA iniciar >/dev/null 2>&1
if [ -f "$CAIXA2/rainforest.db" ] && cmp -s "$CAIXA/rainforest.db" "$CAIXA/.snapshot-antes-caixa2"; then
  ok=$((ok+1)); echo "  ok   banco isolado por RFM_ROOT (novo banco em CAIXA2, CAIXA original intocado)"
else
  falhou=$((falhou+1)); echo "  FALHA nao isolou dado por RFM_ROOT"
  echo "         CAIXA2/rainforest.db existe? $([ -f "$CAIXA2/rainforest.db" ] && echo sim || echo nao)"
  echo "         CAIXA/rainforest.db mudou?   $(cmp -s "$CAIXA/rainforest.db" "$CAIXA/.snapshot-antes-caixa2" && echo nao || echo SIM)"
fi
rm -f "$CAIXA/.snapshot-antes-caixa2"

echo
echo "== 6. buscar em banco vazio devolve array vazio =="
resultado=$($MEMORIA buscar --texto "nada" --json 2>&1)
if [ "$?" = "0" ] && echo "$resultado" | grep -q '^\[\]$'; then
  ok=$((ok+1)); echo "  ok   buscar vazio retorna exit 0 e array vazio"
else
  falhou=$((falhou+1)); echo "  FALHA buscar vazio não retornou array vazio"
fi

echo
echo "== 7. buscar num banco que não existe devolve array vazio =="
CAIXA3="$(mktemp -d)"
trap 'rm -rf "$CAIXA" "$CAIXA2" "$CAIXA3"' EXIT
resultado=$(RFM_ROOT="$CAIXA3" $MEMORIA buscar --texto "test" --json 2>&1)
if [ "$?" = "0" ] && echo "$resultado" | grep -q '^\[\]$'; then
  ok=$((ok+1)); echo "  ok   buscar em banco inexistente retorna exit 0 e array vazio"
else
  falhou=$((falhou+1)); echo "  FALHA buscar em banco inexistente não retornou array vazio"
fi

echo
echo "== 8. reindexar em banco vazio funciona =="
esperado "reindexar vazio" 0 $MEMORIA reindexar

echo
echo "== 9. a migração de marca_dagua roda UMA vez, não a cada abertura =="
# Por que esta bateria existe: `criarSchema()` é chamada em todo caminho que
# abre o banco — inclusive pelo hook que grava marca d'água, a cada gravação.
# A primeira versão da migração da tarefa 4 apagava a tabela toda vez, então a
# marca recém-escrita sumia e o `offset_processado` nunca saía de 0: a captura
# reprocessaria o mesmo transcrito para sempre, sem erro nenhum na tela.
CAIXA4="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${CAIXA4:-}"' EXIT
RFM_ROOT="$CAIXA4" $MEMORIA iniciar > /dev/null 2>&1
SOBREVIVEU=$(RFM_ROOT="$CAIXA4" node --no-warnings -e "
const { abrirBanco, criarSchema } = require('./scripts/memoria.cjs');
const caminho = process.env.RFM_ROOT + '/rainforest.db';
const db = abrirBanco(caminho);
db.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('p', 's1', 'a.jsonl', 206, 206, '2026-08-20T00:00:00Z');
criarSchema(db);                       // é isto que o hook faz a cada gravação
const n = db.prepare('SELECT count(*) c FROM marca_dagua').get().c;
const off = db.prepare('SELECT offset_processado o FROM marca_dagua').get();
db.close();
process.stdout.write(n + ':' + (off ? off.o : 'nada'));
")
if [ "$SOBREVIVEU" = "1:206" ]; then
  ok=$((ok+1)); echo "  ok   marca d'água sobrevive a criarSchema (1 linha, offset 206)"
else
  falhou=$((falhou+1)); echo "  FALHA marca d'água não sobreviveu a criarSchema: esperava '1:206', veio '$SOBREVIVEU'"
fi

echo
echo "== 10. observacao gravada aparece no buscar SEM reindexar =="
# Tarefa 1 (D24): Com conteúdo externo sincronizado por triggers, a observação
# deve aparecer em buscar() sem precisar chamar reindexar() separadamente.
# Criar banco limpo, inserir observação diretamente, buscar.
CAIXA5="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${CAIXA4:-}" "${CAIXA5:-}"' EXIT
RFM_ROOT="$CAIXA5" $MEMORIA iniciar > /dev/null 2>&1
# Inserir observação diretamente via SQL (simula caminho do observar.cjs)
RFM_ROOT="$CAIXA5" node -e "
  const { abrirBanco } = require('./scripts/memoria.cjs');
  const path = require('path');
  const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('projeto1', 'Palavra unica TRIGGER123', new Date().toISOString(), 'test-origem');
  db.close();
" 2>/dev/null
# Buscar sem chamar reindexar — deve achar a observação via FTS5 sincronizado
resultado=$(RFM_ROOT="$CAIXA5" $MEMORIA buscar --texto "TRIGGER123" --json 2>/dev/null)
if echo "$resultado" | grep -q "TRIGGER123"; then
  ok=$((ok+1)); echo "  ok   observacao aparece em buscar sem reindexar (trigger FTS5 funcionando)"
else
  falhou=$((falhou+1)); echo "  FALHA observacao nao apareceu em buscar sem reindexar"
  echo "         resultado: $resultado"
fi

echo
echo "== 11. banco legacy (FTS sem content externo) funciona apos migração =="
# Tarefa 1 (D24): Cria banco no schema ANTIGO (sem triggers, sem content externo),
# executa criarSchema novo (que deve ser idempotente), e valida que buscar funciona.
CAIXA6="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${CAIXA4:-}" "${CAIXA5:-}" "${CAIXA6:-}"' EXIT
# Criar banco legacy manualmente (sem content externo, sem triggers)
RFM_ROOT="$CAIXA6" node -e "
  const DatabaseSync = require('node:sqlite').DatabaseSync;
  const path = require('path');
  const fs = require('fs');
  fs.mkdirSync(process.env.RFM_ROOT, { recursive: true });
  const db = new DatabaseSync(path.join(process.env.RFM_ROOT, 'rainforest.db'));
  db.exec(\`
    CREATE TABLE IF NOT EXISTS observacoes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      projeto TEXT NOT NULL,
      conteudo TEXT NOT NULL,
      criada_em TEXT NOT NULL,
      origem TEXT,
      UNIQUE(projeto, origem)
    );
    CREATE VIRTUAL TABLE IF NOT EXISTS observacoes_fts USING fts5(conteudo);
    INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES ('proj', 'palavra chave LEGACY', datetime('now'), 'legacy-origem');
    INSERT INTO observacoes_fts(rowid, conteudo) VALUES (1, 'palavra chave LEGACY');
  \`);
  db.close();
" 2>/dev/null
# Executar criarSchema novo (que migra triggers, content externo, etc)
RFM_ROOT="$CAIXA6" $MEMORIA iniciar > /dev/null 2>&1
# Verificar que buscar encontra a observação
resultado=$(RFM_ROOT="$CAIXA6" $MEMORIA buscar --texto "LEGACY" --json 2>/dev/null)
if echo "$resultado" | grep -q "LEGACY"; then
  ok=$((ok+1)); echo "  ok   banco legacy migrado, buscar encontra observacao"
else
  falhou=$((falhou+1)); echo "  FALHA buscar nao encontrou observacao em banco legacy migrado"
fi

echo
echo "== 12. UPDATE e DELETE mantêm count(observacoes) == count(observacoes_fts) =="
# Tarefa 1 (D24): Triggers de UPDATE/DELETE mantêm sincronização.
# Inserir, atualizar, deletar, verificar contagem em ambas tabelas.
CAIXA7="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${CAIXA4:-}" "${CAIXA5:-}" "${CAIXA6:-}" "${CAIXA7:-}"' EXIT
RFM_ROOT="$CAIXA7" $MEMORIA iniciar > /dev/null 2>&1
resultado=$(RFM_ROOT="$CAIXA7" node -e "
  const { abrirBanco } = require('./scripts/memoria.cjs');
  const path = require('path');
  const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
  const agora = new Date().toISOString();

  // Inserir 3 observações
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('p', 'conteudo 1', agora, 'o1');
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('p', 'conteudo 2', agora, 'o2');
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('p', 'conteudo 3', agora, 'o3');

  // Atualizar primeira (trigger UPDATE: delete velho, insert novo)
  db.prepare('UPDATE observacoes SET conteudo = ? WHERE id = 1')
    .run('conteudo 1 ATUALIZADO');

  // Deletar segunda (trigger DELETE)
  db.prepare('DELETE FROM observacoes WHERE id = 2').run();

  // Contar em ambas tabelas (devem ser iguais: 2 observações após operações)
  const cntObs = db.prepare('SELECT COUNT(*) c FROM observacoes').get().c;
  const cntFts = db.prepare('SELECT COUNT(*) c FROM observacoes_fts').get().c;

  db.close();
  process.stdout.write(cntObs + ':' + cntFts);
" 2>/dev/null)
if [ "$resultado" = "2:2" ]; then
  ok=$((ok+1)); echo "  ok   UPDATE/DELETE sincronizados, contagens iguais (2:2)"
else
  falhou=$((falhou+1)); echo "  FALHA contagens divergiram ou não são (2:2), veio: $resultado"
fi

echo
echo "== 13. criarSchema idempotente — segunda execução não erra =="
# Tarefa 1 (D24): criarSchema deve ser seguro rodar duas vezes no mesmo banco.
CAIXA8="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${CAIXA4:-}" "${CAIXA5:-}" "${CAIXA6:-}" "${CAIXA7:-}" "${CAIXA8:-}"' EXIT
RFM_ROOT="$CAIXA8" $MEMORIA iniciar > /dev/null 2>&1
# Inserir observação
RFM_ROOT="$CAIXA8" node -e "
  const { abrirBanco } = require('./scripts/memoria.cjs');
  const path = require('path');
  const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('p', 'idempotencia teste', new Date().toISOString(), 'o-idem');
  db.close();
" 2>/dev/null
# Segunda execução de iniciar (que chama criarSchema de novo)
RFM_ROOT="$CAIXA8" $MEMORIA iniciar > /dev/null 2>&1
got=$?
# Verificar que a observação ainda está lá
resultado=$(RFM_ROOT="$CAIXA8" $MEMORIA buscar --texto "idempotencia" --json 2>/dev/null)
if [ "$got" = "0" ] && echo "$resultado" | grep -q "idempotencia teste"; then
  ok=$((ok+1)); echo "  ok   criarSchema idempotente, segunda execução ok"
else
  falhou=$((falhou+1)); echo "  FALHA criarSchema não foi idempotente"
  echo "         exit code: $got, resultado: $resultado"
fi

echo
echo "== 14. consolidar com 50+ observacoes de 60+ dias grava resumos e marca =="
# Tarefa 4 (D4): Criar banco com 55 observações de 60+ dias não consolidadas,
# rodar consolidar com dublê de LLM, verificar que:
# - resumos foram gravados (lotes 10→1: 55/10 = 5 lotes)
# - observações foram marcadas com consolidada_em
# - count(observacoes) antes == count depois (NUNCA apaga linha)
CAIXA9="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${CAIXA4:-}" "${CAIXA5:-}" "${CAIXA6:-}" "${CAIXA7:-}" "${CAIXA8:-}" "${CAIXA9:-}"' EXIT

# Criar dublê de LLM que retorna um resumo fixo (ou null se TESTADOR_LLM_FALHAR=1)
cat > "$CAIXA9/dubleLLM.cjs" <<'EOF'
async function chamarLLM(texto) {
  // Se env var TESTADOR_LLM_FALHAR=1, retorna null (simula falha)
  if (process.env.TESTADOR_LLM_FALHAR === '1') {
    return null;
  }
  // Simular resumo de LLM
  return "Síntese do lote: tópicos consolidados com sucesso";
}
module.exports = { chamarLLM };
EOF

# Criar banco e popular com 55 observações de 60+ dias
RFM_ROOT="$CAIXA9" $MEMORIA iniciar > /dev/null 2>&1
RESULTADO=$(RFM_ROOT="$CAIXA9" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = new Date();
const sessentiaDias = new Date(agora.getTime() - 61 * 24 * 60 * 60 * 1000).toISOString();

// Inserir 55 observações de 60+ dias atrás
for (let i = 0; i < 55; i++) {
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-test', 'Observação ' + i, sessentiaDias, 'origem-' + i);
}

const cntAntes = db.prepare('SELECT COUNT(*) c FROM observacoes').get().c;
db.close();
process.stdout.write(cntAntes.toString());
" 2>/dev/null)

cntAntes=$RESULTADO

# Rodar consolidar com dublê de LLM
RFM_ROOT="$CAIXA9" TESTADOR_CHAMAR_LLM="$CAIXA9/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

# Verificar resultados
RESULTADO=$(RFM_ROOT="$CAIXA9" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));

const cntObs = db.prepare('SELECT COUNT(*) c FROM observacoes').get().c;
const cntResumidos = db.prepare('SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL').get().c;
const cntResumosGravados = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;

db.close();
process.stdout.write(cntObs + ':' + cntResumidos + ':' + cntResumosGravados);
" 2>/dev/null)

cntObs=$(echo "$RESULTADO" | cut -d':' -f1)
cntResumidos=$(echo "$RESULTADO" | cut -d':' -f2)
cntResumosGravados=$(echo "$RESULTADO" | cut -d':' -f3)

if [ "$cntAntes" = "$cntObs" ] && [ "$cntResumidos" = "55" ] && [ "$cntResumosGravados" = "6" ]; then
  ok=$((ok+1)); echo "  ok   consolidacao: ${cntAntes} obs antes, ${cntObs} após (iguais), ${cntResumidos} marcadas, ${cntResumosGravados} resumos (55/10=5 lotes mais 1)"
else
  falhou=$((falhou+1)); echo "  FALHA consolidacao: antes=$cntAntes, obs=$cntObs, resumidos=$cntResumidos (esperava 55), resumos=$cntResumosGravados (esperava 5-6)"
fi

echo
echo "== 15. consolidar duas vezes nao gera resumo duplicado =="
# Tarefa 4 (D4): rodagem anterior já consolidou, segunda rodada não toca nada
# porque todas as observações já estão marcadas com consolidada_em.
RFM_ROOT="$CAIXA9" TESTADOR_CHAMAR_LLM="$CAIXA9/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

RESULTADO2=$(RFM_ROOT="$CAIXA9" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cntResumosApos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;
db.close();
process.stdout.write(cntResumosApos.toString());
" 2>/dev/null)

if [ "$RESULTADO2" = "$cntResumosGravados" ]; then
  ok=$((ok+1)); echo "  ok   segunda consolidacao não criou novos resumos (manteve $cntResumosGravados)"
else
  falhou=$((falhou+1)); echo "  FALHA segunda consolidacao criou resumos novos: esperava $cntResumosGravados, veio $RESULTADO2"
fi

echo
echo "== 16. consolidar com <50 observacoes nao faz nada =="
# Tarefa 4 (D4): abaixo do gatilho de 50, sai sem gravar resumo nenhum
CAIXA10="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${CAIXA4:-}" "${CAIXA5:-}" "${CAIXA6:-}" "${CAIXA7:-}" "${CAIXA8:-}" "${CAIXA9:-}" "${CAIXA10:-}"' EXIT

RFM_ROOT="$CAIXA10" $MEMORIA iniciar > /dev/null 2>&1
# Inserir apenas 30 observações de 60+ dias
RFM_ROOT="$CAIXA10" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const sessentiaDias = new Date(Date.now() - 61 * 24 * 60 * 60 * 1000).toISOString();

for (let i = 0; i < 30; i++) {
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-test', 'Obs ' + i, sessentiaDias, 'orig-' + i);
}
db.close();
" 2>/dev/null

RFM_ROOT="$CAIXA10" TESTADOR_CHAMAR_LLM="$CAIXA10/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

RESULTADO3=$(RFM_ROOT="$CAIXA10" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cntResumos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;
db.close();
process.stdout.write(cntResumos.toString());
" 2>/dev/null)

if [ "$RESULTADO3" = "0" ]; then
  ok=$((ok+1)); echo "  ok   consolidar com <50 obs não grava resumo"
else
  falhou=$((falhou+1)); echo "  FALHA consolidar com <50 obs gravou $RESULTADO3 resumo(s), esperava 0"
fi

echo
echo "== 17. criarSchema com coluna nova nao erra =="
# Tarefa 4 (D4): migração idempotente — rodar criarSchema duas vezes não causa erro
CAIXA11="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${CAIXA4:-}" "${CAIXA5:-}" "${CAIXA6:-}" "${CAIXA7:-}" "${CAIXA8:-}" "${CAIXA9:-}" "${CAIXA10:-}" "${CAIXA11:-}"' EXIT

RFM_ROOT="$CAIXA11" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA11" $MEMORIA iniciar > /dev/null 2>&1
got=$?

if [ "$got" = "0" ]; then
  ok=$((ok+1)); echo "  ok   criarSchema idempotente (duas execuções de iniciar, exit 0)"
else
  falhou=$((falhou+1)); echo "  FALHA criarSchema não foi idempotente, esperava exit 0, veio $got"
fi

echo
echo "== 18. dublê simulando falha de LLM deixa lote intacto para próxima rodada =="
# Tarefa 4 (D4): caso (d) — quando LLM falha, lote não é marcado, não são gravados resumos,
# tudo fica disponível para reconsolidação. Rodada seguinte com LLM saudável consolida normalmente.
CAIXA12="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${CAIXA4:-}" "${CAIXA5:-}" "${CAIXA6:-}" "${CAIXA7:-}" "${CAIXA8:-}" "${CAIXA9:-}" "${CAIXA10:-}" "${CAIXA11:-}" "${CAIXA12:-}"' EXIT

# Usar dublê de CAIXA9 que suporta falha via TESTADOR_LLM_FALHAR=1
RFM_ROOT="$CAIXA12" $MEMORIA iniciar > /dev/null 2>&1

# Inserir 55 observações de 60+ dias
RFM_ROOT="$CAIXA12" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const sessentiaDias = new Date(Date.now() - 61 * 24 * 60 * 60 * 1000).toISOString();

for (let i = 0; i < 55; i++) {
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-test', 'Obs ' + i, sessentiaDias, 'orig-' + i);
}
db.close();
" 2>/dev/null

# Primeira rodada: LLM falha (TESTADOR_LLM_FALHAR=1)
RFM_ROOT="$CAIXA12" TESTADOR_CHAMAR_LLM="$CAIXA9/dubleLLM.cjs" TESTADOR_LLM_FALHAR=1 $MEMORIA consolidar > /dev/null 2>&1

# Verificar que nada foi gravado/marcado
RESULTADO_FALHA=$(RFM_ROOT="$CAIXA12" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));

const cntObs = db.prepare('SELECT COUNT(*) c FROM observacoes').get().c;
const cntResumidos = db.prepare('SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL').get().c;
const cntResumos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;

db.close();
process.stdout.write(cntObs + ':' + cntResumidos + ':' + cntResumos);
" 2>/dev/null)

cntObs_falha=$(echo "$RESULTADO_FALHA" | cut -d':' -f1)
cntResumidos_falha=$(echo "$RESULTADO_FALHA" | cut -d':' -f2)
cntResumos_falha=$(echo "$RESULTADO_FALHA" | cut -d':' -f3)

# Segunda rodada: LLM saudável (TESTADOR_LLM_FALHAR não setado = null ou não existe)
RFM_ROOT="$CAIXA12" TESTADOR_CHAMAR_LLM="$CAIXA9/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

# Verificar que agora foi consolidado normalmente
RESULTADO_OK=$(RFM_ROOT="$CAIXA12" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));

const cntObs = db.prepare('SELECT COUNT(*) c FROM observacoes').get().c;
const cntResumidos = db.prepare('SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL').get().c;
const cntResumos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;

db.close();
process.stdout.write(cntObs + ':' + cntResumidos + ':' + cntResumos);
" 2>/dev/null)

cntObs_ok=$(echo "$RESULTADO_OK" | cut -d':' -f1)
cntResumidos_ok=$(echo "$RESULTADO_OK" | cut -d':' -f2)
cntResumos_ok=$(echo "$RESULTADO_OK" | cut -d':' -f3)

# Validar: falha deixa lote intacto, rodada seguinte consolida
if [ "$cntObs_falha" = "55" ] && [ "$cntResumidos_falha" = "0" ] && [ "$cntResumos_falha" = "0" ] && \
   [ "$cntObs_ok" = "55" ] && [ "$cntResumidos_ok" = "55" ] && [ "$cntResumos_ok" = "6" ]; then
  ok=$((ok+1)); echo "  ok   falha LLM lota lote intacto (obs=$cntObs_falha, resumidos=$cntResumidos_falha, resumos=$cntResumos_falha), segunda rodada consolida (marcadas=$cntResumidos_ok, resumos=$cntResumos_ok)"
else
  falhou=$((falhou+1)); echo "  FALHA rodada com falha: obs=$cntObs_falha (esp 55), resumidos=$cntResumidos_falha (esp 0), resumos=$cntResumos_falha (esp 0); rodada OK: obs=$cntObs_ok (esp 55), resumidos=$cntResumidos_ok (esp 55), resumos=$cntResumos_ok (esp 6)"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
