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
# Idioma da Tarefa 10 (docs/rainforest/planos/zerar-issues.md): cada sandbox
# criada com `mktemp -d` entra em SANDBOXES e o trap de EXIT varre todas —
# substitui a cadeia de 15 `trap ... EXIT` que este arquivo reatribuia a cada
# CAIXAn nova, sempre listando de novo TODAS as anteriores com `${VAR:-}`.
SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

CAIXA="$(novo_sandbox)"

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
CAIXA2="$(novo_sandbox)"

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
CAIXA3="$(novo_sandbox)"
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
CAIXA4="$(novo_sandbox)"
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
CAIXA5="$(novo_sandbox)"
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
echo "== 11. banco legacy (FTS sem content=) migra de verdade: termo NUNCA indexado vira achavel =="
# C1: a versão anterior deste teste inseria o termo NA PRÓPRIA FTS legada — o
# buscar achava a linha mesmo sem migração nenhuma, e o teste passava com o
# defeito presente (CREATE VIRTUAL TABLE IF NOT EXISTS é no-op sobre a tabela
# antiga, que fica para sempre sem content= e sem o termo). Aqui a observação
# entra SÓ em observacoes, nunca na FTS: sem a migração real (DROP + recriação
# com content='observacoes' + rebuild), o buscar não tem como achá-la.
# Duas asserções: (i) o DDL novo tem content='observacoes'; (ii) buscar acha o termo.
CAIXA6="$(novo_sandbox)"
# Criar banco legacy manualmente (FTS sem content=, e a observação FORA dela)
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
  \`);
  db.close();
" 2>/dev/null
# Executar a migração (iniciar chama criarSchema, que detecta o DDL sem content=)
RFM_ROOT="$CAIXA6" $MEMORIA iniciar > /dev/null 2>&1
# (i) o DDL da observacoes_fts agora aponta para o conteúdo externo
DDL_FTS=$(RFM_ROOT="$CAIXA6" node --no-warnings -e "
  const { abrirBancoSomenteLeitura } = require('./scripts/memoria.cjs');
  const path = require('path');
  const db = abrirBancoSomenteLeitura(path.join(process.env.RFM_ROOT, 'rainforest.db'));
  const r = db.prepare(\"SELECT sql FROM sqlite_master WHERE type='table' AND name='observacoes_fts'\").all();
  db.close();
  process.stdout.write((r[0] && r[0].sql) || '');
" 2>/dev/null)
if echo "$DDL_FTS" | grep -q "content='observacoes'"; then
  ok=$((ok+1)); echo "  ok   DDL da observacoes_fts migrado para content='observacoes'"
else
  falhou=$((falhou+1)); echo "  FALHA DDL da FTS continua legado: $DDL_FTS"
fi
# (ii) buscar acha o termo que NUNCA entrou na FTS legada — só o rebuild real explica
resultado=$(RFM_ROOT="$CAIXA6" $MEMORIA buscar --texto "LEGACY" --json 2>/dev/null)
if echo "$resultado" | grep -q "LEGACY"; then
  ok=$((ok+1)); echo "  ok   buscar acha o termo que nunca foi indexado na FTS legada (rebuild real)"
else
  falhou=$((falhou+1)); echo "  FALHA buscar nao achou o termo apos a migração do FTS legado"
fi

echo
echo "== 12. UPDATE e DELETE mantêm count(observacoes) == count(observacoes_fts) =="
# Tarefa 1 (D24): Triggers de UPDATE/DELETE mantêm sincronização.
# Inserir, atualizar, deletar, verificar contagem em ambas tabelas.
CAIXA7="$(novo_sandbox)"
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
CAIXA8="$(novo_sandbox)"
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
echo "== 14. consolidar com grupo de 30+ dias grava resumos e marca =="
# Tarefa 4 (D7): 55 observações de uma MESMA sessao (sqlGrupoDeOrigem agrupa
# por sessao quando origem é 'sessao:<id>:offset:<n>'), com 31 dias — acima
# de DIAS_CONSOLIDACAO (30). Um grupo só, fatiado em pedaços de até
# TETO_POR_GRUPO (30): 55 => 30 + 25 = 2 pedaços = 2 resumos.
CAIXA9="$(novo_sandbox)"

# Criar dublê de LLM que retorna um resumo fixo (ou null se TESTADOR_LLM_FALHAR=1)
cat > "$CAIXA9/dubleLLM.cjs" <<'EOF'
async function chamarLLM(texto) {
  // Se env var TESTADOR_LLM_FALHAR=1, retorna null (simula falha)
  if (process.env.TESTADOR_LLM_FALHAR === '1') {
    return null;
  }
  // Simular resumo de LLM
  return "Síntese do grupo: tópicos consolidados com sucesso";
}
module.exports = { chamarLLM };
EOF

# Criar banco e popular com 55 observações de uma mesma sessao, 31 dias atras
RFM_ROOT="$CAIXA9" $MEMORIA iniciar > /dev/null 2>&1
RESULTADO=$(RFM_ROOT="$CAIXA9" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const trintaEUmDias = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();

for (let i = 0; i < 55; i++) {
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-test', 'Observação ' + i, trintaEUmDias, 'sessao:11111111-1111-1111-1111-111111111111:offset:' + i);
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

if [ "$cntAntes" = "$cntObs" ] && [ "$cntResumidos" = "55" ] && [ "$cntResumosGravados" = "2" ]; then
  ok=$((ok+1)); echo "  ok   consolidacao: ${cntAntes} obs antes, ${cntObs} após (iguais), ${cntResumidos} marcadas, ${cntResumosGravados} resumos (55 = 30+25, 2 pedaços)"
else
  falhou=$((falhou+1)); echo "  FALHA consolidacao: antes=$cntAntes, obs=$cntObs, resumidos=$cntResumidos (esperava 55), resumos=$cntResumosGravados (esperava 2)"
fi

echo
echo "== 15. consolidar duas vezes nao gera resumo duplicado =="
# Tarefa 4 (D7): rodagem anterior já consolidou, segunda rodada não toca nada
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
echo "== 16. grupo com 1 observacao nao consolida =="
# Tarefa 4 (D7): grupo mínimo é 2 — resumo de uma observação só não sintetiza
# nada. Uma sessao com uma única observação, 31 dias, não gera resumo.
CAIXA10="$(novo_sandbox)"

RFM_ROOT="$CAIXA10" $MEMORIA iniciar > /dev/null 2>&1
cat > "$CAIXA10/dubleLLM.cjs" <<'EOF'
async function chamarLLM(texto) {
  return "Síntese que não deveria existir para grupo de 1";
}
module.exports = { chamarLLM };
EOF
RFM_ROOT="$CAIXA10" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const trintaEUmDias = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
  .run('proj-test', 'Observacao solitaria', trintaEUmDias, 'sessao:22222222-2222-2222-2222-222222222222:offset:0');
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
  ok=$((ok+1)); echo "  ok   grupo de 1 observacao nao grava resumo"
else
  falhou=$((falhou+1)); echo "  FALHA grupo de 1 observacao gravou $RESULTADO3 resumo(s), esperava 0"
fi

echo
echo "== 17. criarSchema com coluna nova nao erra =="
# Tarefa 4 (D7): migração idempotente — rodar criarSchema duas vezes não causa erro
CAIXA11="$(novo_sandbox)"

RFM_ROOT="$CAIXA11" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA11" $MEMORIA iniciar > /dev/null 2>&1
got=$?

if [ "$got" = "0" ]; then
  ok=$((ok+1)); echo "  ok   criarSchema idempotente (duas execuções de iniciar, exit 0)"
else
  falhou=$((falhou+1)); echo "  FALHA criarSchema não foi idempotente, esperava exit 0, veio $got"
fi

echo
echo "== 18. dublê simulando falha de LLM deixa grupo intacto para próxima rodada =="
# Tarefa 4 (D7): caso (d) — quando a LLM falha, o pedaço não é marcado, nenhum
# resumo é gravado, tudo fica disponível para a próxima rodada. Rodada
# seguinte com LLM saudável consolida normalmente.
CAIXA12="$(novo_sandbox)"

RFM_ROOT="$CAIXA12" $MEMORIA iniciar > /dev/null 2>&1

# Inserir 55 observações de uma mesma sessao, 31 dias atras
RFM_ROOT="$CAIXA12" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const trintaEUmDias = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();

for (let i = 0; i < 55; i++) {
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-test', 'Obs ' + i, trintaEUmDias, 'sessao:33333333-3333-3333-3333-333333333333:offset:' + i);
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

# Validar: falha deixa grupo intacto, rodada seguinte consolida
if [ "$cntObs_falha" = "55" ] && [ "$cntResumidos_falha" = "0" ] && [ "$cntResumos_falha" = "0" ] && \
   [ "$cntObs_ok" = "55" ] && [ "$cntResumidos_ok" = "55" ] && [ "$cntResumos_ok" = "2" ]; then
  ok=$((ok+1)); echo "  ok   falha LLM deixa grupo intacto (obs=$cntObs_falha, resumidos=$cntResumidos_falha, resumos=$cntResumos_falha), segunda rodada consolida (marcadas=$cntResumidos_ok, resumos=$cntResumos_ok)"
else
  falhou=$((falhou+1)); echo "  FALHA rodada com falha: obs=$cntObs_falha (esp 55), resumidos=$cntResumidos_falha (esp 0), resumos=$cntResumos_falha (esp 0); rodada OK: obs=$cntObs_ok (esp 55), resumidos=$cntResumidos_ok (esp 55), resumos=$cntResumos_ok (esp 2)"
fi

echo
echo "== 19. grupo de exatamente 30 observacoes vira UM resumo (fronteira do teto por grupo) =="
# TETO_POR_GRUPO = 30: grupo NO teto não fatia (1 resumo com as 30).
CAIXA13="$(novo_sandbox)"

cat > "$CAIXA13/dubleLLM.cjs" <<'EOF'
async function chamarLLM(texto) {
  return "Síntese de grupo no teto exato";
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA13" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA13" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const trintaEUmDias = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();
for (let i = 0; i < 30; i++) {
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-fronteira', 'Obs ' + i, trintaEUmDias, 'sessao:44444444-4444-4444-4444-444444444444:offset:' + i);
}
db.close();
" 2>/dev/null

RFM_ROOT="$CAIXA13" TESTADOR_CHAMAR_LLM="$CAIXA13/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

RESULTADO_30=$(RFM_ROOT="$CAIXA13" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cntResumos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;
const cntMarcadas = db.prepare('SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL').get().c;
db.close();
process.stdout.write(cntResumos + ':' + cntMarcadas);
" 2>/dev/null)

if [ "$RESULTADO_30" = "1:30" ]; then
  ok=$((ok+1)); echo "  ok   grupo de 30 obs exatas: 1 resumo, 30 marcadas (nao fatia no teto exato)"
else
  falhou=$((falhou+1)); echo "  FALHA grupo de 30 obs exatas: esperava resumos:marcadas = 1:30, veio $RESULTADO_30"
fi

echo
echo "== 20. grupo de 45 observacoes vira dois resumos, nao um =="
# TETO_POR_GRUPO = 30: grupo de 45 fatia em 30 + 15, dois resumos — nenhum
# deles passa do teto, e os dois vêm do mesmo grupo (critério 1 do plano).
CAIXA14="$(novo_sandbox)"

RFM_ROOT="$CAIXA14" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA14" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const trintaEUmDias = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();
for (let i = 0; i < 45; i++) {
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-fronteira', 'Obs ' + i, trintaEUmDias, 'sessao:55555555-5555-5555-5555-555555555555:offset:' + i);
}
db.close();
" 2>/dev/null

RFM_ROOT="$CAIXA14" TESTADOR_CHAMAR_LLM="$CAIXA13/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

# 45 obs no teto de 30 por grupo = 2 pedaços (30 + 15) = 2 resumos, 45 marcadas
RESULTADO_45=$(RFM_ROOT="$CAIXA14" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cntResumos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;
const cntMarcadas = db.prepare('SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL').get().c;
db.close();
process.stdout.write(cntResumos + ':' + cntMarcadas);
" 2>/dev/null)

if [ "$RESULTADO_45" = "2:45" ]; then
  ok=$((ok+1)); echo "  ok   grupo de 45 obs: fatiado em dois pedacos (2 resumos, 30+15=45 marcadas)"
else
  falhou=$((falhou+1)); echo "  FALHA grupo de 45 obs: esperava resumos:marcadas = 2:45, veio $RESULTADO_45"
fi

echo
echo "== 21. C4: falha na marcacao desfaz o resumo junto (transacao atomica) =="
# C4: antes da transação única, o resumo era gravado ANTES da marcação — se a
# marcação falhasse, ficava resumo órfão no banco e as observações voltavam a
# ser consolidadas na rodada seguinte (resumo duplicado). A injeção aqui é um
# gatilho BEFORE UPDATE OF consolidada_em que aborta a marcação: com a
# transação atômica, nem o resumo nem a marca podem sobreviver à falha.
CAIXA15="$(novo_sandbox)"

RFM_ROOT="$CAIXA15" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA15" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const trintaEUmDias = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();
for (let i = 0; i < 45; i++) {
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-atomico', 'Obs ' + i, trintaEUmDias, 'sessao:66666666-6666-6666-6666-666666666666:offset:' + i);
}
// Injeção de falha: qualquer tentativa de marcar consolidada_em aborta.
db.exec(\`
  CREATE TRIGGER falha_injetada_na_marca BEFORE UPDATE OF consolidada_em ON observacoes
  BEGIN
    SELECT RAISE(ABORT, 'falha injetada na marcacao');
  END;
\`);
db.close();
" 2>/dev/null

# LLM saudável (dublê de CAIXA13): a falha vem SÓ da marcação
RFM_ROOT="$CAIXA15" TESTADOR_CHAMAR_LLM="$CAIXA13/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

RESULTADO_ATOMICO=$(RFM_ROOT="$CAIXA15" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cntResumos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;
const cntMarcadas = db.prepare('SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL').get().c;
db.close();
process.stdout.write(cntResumos + ':' + cntMarcadas);
" 2>/dev/null)

if [ "$RESULTADO_ATOMICO" = "0:0" ]; then
  ok=$((ok+1)); echo "  ok   marcacao falhou e o ROLLBACK levou o resumo junto (resumos=0, marcadas=0)"
else
  falhou=$((falhou+1)); echo "  FALHA transacao vazou: esperava resumos:marcadas = 0:0, veio $RESULTADO_ATOMICO (resumo orfao = reconsolidacao dupla)"
fi

# Controle: removida a injeção, o MESMO banco consolida normal — prova que a
# falha acima veio do gatilho, não de outro defeito que deixaria tudo em 0:0.
RFM_ROOT="$CAIXA15" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
db.exec('DROP TRIGGER falha_injetada_na_marca;');
db.close();
" 2>/dev/null
RFM_ROOT="$CAIXA15" TESTADOR_CHAMAR_LLM="$CAIXA13/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

RESULTADO_CONTROLE=$(RFM_ROOT="$CAIXA15" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cntResumos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;
const cntMarcadas = db.prepare('SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL').get().c;
db.close();
process.stdout.write(cntResumos + ':' + cntMarcadas);
" 2>/dev/null)

if [ "$RESULTADO_CONTROLE" = "2:45" ]; then
  ok=$((ok+1)); echo "  ok   controle: sem a injecao o mesmo banco consolida (2 resumos, 45 marcadas)"
else
  falhou=$((falhou+1)); echo "  FALHA controle: esperava 2:45 apos remover a injecao, veio $RESULTADO_CONTROLE"
fi

echo
echo "== 22. migracao 6: banco legado ganha substituida_por e reconciliada_em =="
# Tarefa 1 (D3, D6): duas colunas novas em observacoes (substituida_por,
# reconciliada_em), migração idempotente no molde exato da Migração 4.
# Banco legado (sem as duas colunas) ganha as duas via `iniciar`, e nenhuma
# linha se perde — mesmo padrão do caso 11 (FTS legado): a tabela é criada
# À MÃO, sem as colunas novas, para provar que é a migração real (ALTER
# TABLE) que as adiciona, não o CREATE TABLE IF NOT EXISTS do schema atual.
CAIXA16="$(novo_sandbox)"
RFM_ROOT="$CAIXA16" node -e "
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
      consolidada_em TEXT,
      UNIQUE(projeto, origem)
    );
  \`);
  for (let i = 0; i < 5; i++) {
    db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
      .run('proj-legado', 'Obs legado ' + i, new Date().toISOString(), 'orig-legado-' + i);
  }
  db.close();
" 2>/dev/null
CNT_ANTES_MIG6=$(RFM_ROOT="$CAIXA16" node --no-warnings -e "
const { abrirBancoSomenteLeitura } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBancoSomenteLeitura(path.join(process.env.RFM_ROOT, 'rainforest.db'));
process.stdout.write(String(db.prepare('SELECT COUNT(*) n FROM observacoes').get().n));
" 2>/dev/null)
RFM_ROOT="$CAIXA16" $MEMORIA iniciar > /dev/null 2>&1
RESULTADO_MIG6=$(RFM_ROOT="$CAIXA16" node --no-warnings -e "
const { abrirBancoSomenteLeitura } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBancoSomenteLeitura(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cols = db.prepare('PRAGMA table_info(observacoes)').all().map(c => c.name);
const cnt = db.prepare('SELECT COUNT(*) n FROM observacoes').get().n;
process.stdout.write(cols.includes('substituida_por') + ':' + cols.includes('reconciliada_em') + ':' + cnt);
" 2>/dev/null)
if [ "$RESULTADO_MIG6" = "true:true:$CNT_ANTES_MIG6" ]; then
  ok=$((ok+1)); echo "  ok   migracao 6: banco legado ganha substituida_por e reconciliada_em (colunas presentes, ${CNT_ANTES_MIG6} linhas preservadas)"
else
  falhou=$((falhou+1)); echo "  FALHA migracao 6: banco legado ganha substituida_por e reconciliada_em: esperava true:true:$CNT_ANTES_MIG6, veio $RESULTADO_MIG6"
fi

echo
echo "== 23. buscar --texto exclui observacao substituida (filtroVivas) =="
# Tarefa 3 (D3): o ramo COM --texto de cmdBuscar usa filtroVivas('o.'). Termo
# "SOMENTESUBSTITUIDAS" só existe em observações marcadas substituida_por —
# se o filtro não funcionar, o buscar acha o termo mesmo assim.
CAIXA17="$(novo_sandbox)"
RFM_ROOT="$CAIXA17" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA17" node -e "
  const { abrirBanco } = require('./scripts/memoria.cjs');
  const path = require('path');
  const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-subst', 'termo SOMENTESUBSTITUIDAS aqui', new Date().toISOString(), 'subst-a');
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-subst', 'termo SOMENTESUBSTITUIDAS tambem', new Date().toISOString(), 'subst-b');
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-subst', 'termo VIVOBUSCA presente', new Date().toISOString(), 'subst-c');
  db.prepare(\"UPDATE observacoes SET substituida_por = 999, reconciliada_em = datetime('now') WHERE origem IN ('subst-a','subst-b')\").run();
  db.close();
" 2>/dev/null
RESULTADO_BUSCA_SUBST=$(RFM_ROOT="$CAIXA17" $MEMORIA buscar --texto "SOMENTESUBSTITUIDAS" --json 2>/dev/null)
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --texto SOMENTESUBSTITUIDAS --json"
echo "  saida: $RESULTADO_BUSCA_SUBST"
if [ "$(echo "$RESULTADO_BUSCA_SUBST" | tr -d '[:space:]')" = "[]" ]; then
  ok=$((ok+1)); echo "  ok   buscar --texto: termo que só as substituídas contêm devolve []"
else
  falhou=$((falhou+1)); echo "  FALHA buscar --texto devolveu resultado para termo só de substituídas: $RESULTADO_BUSCA_SUBST"
fi
RESULTADO_BUSCA_VIVA=$(RFM_ROOT="$CAIXA17" $MEMORIA buscar --texto "VIVOBUSCA" --json 2>/dev/null)
if echo "$RESULTADO_BUSCA_VIVA" | grep -q "VIVOBUSCA"; then
  ok=$((ok+1)); echo "  ok   buscar --texto: observação viva com termo próprio continua achável (ramo não quebrou)"
else
  falhou=$((falhou+1)); echo "  FALHA buscar --texto deixou de achar observação viva: $RESULTADO_BUSCA_VIVA"
fi

echo
echo "== 24. buscar sem --texto (recentes) exclui observacao substituida =="
# Tarefa 3 (D3): o ramo SEM --texto de cmdBuscar (listagem de recentes) usa
# filtroVivas() ancorado em WHERE 1=1. Mesma caixa 17: 1 viva + 2 substituídas.
RESULTADO_RECENTES=$(RFM_ROOT="$CAIXA17" $MEMORIA buscar --projeto "proj-subst" --limite 10 --json 2>/dev/null)
echo "  comando: RFM_ROOT=<sandbox> node scripts/memoria.cjs buscar --projeto proj-subst --limite 10 --json"
echo "  saida: $RESULTADO_RECENTES"
if echo "$RESULTADO_RECENTES" | grep -q "SOMENTESUBSTITUIDAS"; then
  falhou=$((falhou+1)); echo "  FALHA buscar sem --texto trouxe observação substituída"
else
  ok=$((ok+1)); echo "  ok   buscar sem --texto: nenhuma observação substituída na listagem de recentes"
fi
if echo "$RESULTADO_RECENTES" | grep -q "VIVOBUSCA"; then
  ok=$((ok+1)); echo "  ok   buscar sem --texto: observação viva continua na listagem"
else
  falhou=$((falhou+1)); echo "  FALHA buscar sem --texto perdeu a observação viva: $RESULTADO_RECENTES"
fi

echo
echo "== 25. consolidar nao seleciona observacao substituida (filtroVivas) =="
# Tarefa 3 (D3) + Tarefa 4 (D7): cmdConsolidar filtra substituida_por nas duas
# consultas (a contagem por HAVING e a leitura do grupo). Discriminador: 12
# observações de uma mesma sessao, das quais 11 substituídas — SEM o filtro,
# 12 >= 2 consolidaria; COM o filtro, sobra 1 viva (<2) e o comando não deve
# consolidar nada.
CAIXA18="$(novo_sandbox)"
cat > "$CAIXA18/dubleLLM.cjs" <<'EOF'
async function chamarLLM(texto) {
  return "Síntese que não deveria existir (so 1 observacao viva)";
}
module.exports = { chamarLLM };
EOF
RFM_ROOT="$CAIXA18" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA18" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const trintaEUmDias = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();
for (let i = 0; i < 12; i++) {
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run('proj-consol-subst', 'Observação ' + i, trintaEUmDias, 'sessao:77777777-7777-7777-7777-777777777777:offset:' + i);
}
// Marca as 11 primeiras como substituídas — sobra 1 viva, abaixo do minimo de 2.
db.prepare(\"UPDATE observacoes SET substituida_por = 999, reconciliada_em = ? WHERE projeto = 'proj-consol-subst' AND origem IN (\" + Array.from({length:11}, (_,i)=>\"'sessao:77777777-7777-7777-7777-777777777777:offset:\"+i+\"'\").join(',') + \")\").run(trintaEUmDias);
db.close();
" 2>/dev/null
SAIDA_CONSOL_SUBST=$(RFM_ROOT="$CAIXA18" TESTADOR_CHAMAR_LLM="$CAIXA18/dubleLLM.cjs" $MEMORIA consolidar 2>&1)
echo "  comando: RFM_ROOT=<sandbox> TESTADOR_CHAMAR_LLM=<mock> node scripts/memoria.cjs consolidar"
echo "  saida: $SAIDA_CONSOL_SUBST"
if echo "$SAIDA_CONSOL_SUBST" | grep -q "nenhum grupo com 2+"; then
  ok=$((ok+1)); echo "  ok   consolidar: 12 obs com 11 substituídas (1 viva) NÃO dispara consolidação"
else
  falhou=$((falhou+1)); echo "  FALHA consolidar disparou apesar de só 1 observação viva no grupo"
fi
CNT_CONSOL_SUBST=$(RFM_ROOT="$CAIXA18" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const c = db.prepare(\"SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL\").get().c;
db.close();
process.stdout.write(String(c));
" 2>/dev/null)
if [ "$CNT_CONSOL_SUBST" = "0" ]; then
  ok=$((ok+1)); echo "  ok   nenhuma observação (viva ou substituída) ficou marcada consolidada_em ($CNT_CONSOL_SUBST)"
else
  falhou=$((falhou+1)); echo "  FALHA $CNT_CONSOL_SUBST observação(ões) foram consolidadas apesar do grupo abaixo do minimo"
fi

echo
echo "== 26. TETO_GRUPOS limita quantos pedacos sao consolidados por execucao =="
# Tarefa 4 (D7): sem este teto, a primeira execução dispararia uma chamada de
# LLM por grupo elegível de uma vez (medição do plano: ~340 no acervo real).
# 15 sessões distintas, 2 observações cada (30 no total) — cada sessão é um
# grupo que cabe inteiro num resumo só (2 <= TETO_POR_GRUPO). Com
# TETO_GRUPOS=10, a primeira execução consolida só 10 grupos (20 obs, 10
# resumos); os outros 5 ficam pendentes. A segunda execução consolida o resto.
CAIXA19="$(novo_sandbox)"
cat > "$CAIXA19/dubleLLM.cjs" <<'EOF'
async function chamarLLM(texto) {
  return "Síntese de grupo pequeno";
}
module.exports = { chamarLLM };
EOF
RFM_ROOT="$CAIXA19" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA19" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const base = Date.now() - 31 * 24 * 60 * 60 * 1000;
for (let g = 0; g < 15; g++) {
  const sessao = 'grupo-teto-' + String(g).padStart(2, '0');
  for (let i = 0; i < 2; i++) {
    // ordem cronologica entre grupos: grupo g mais velho que g+1, para o
    // teto processar sempre os mesmos 10 primeiros de forma deterministica.
    const quando = new Date(base - (15 - g) * 1000 + i).toISOString();
    db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
      .run('proj-teto', 'Obs g' + g + ' i' + i, quando, 'sessao:' + sessao + ':offset:' + i);
  }
}
db.close();
" 2>/dev/null

RFM_ROOT="$CAIXA19" TESTADOR_CHAMAR_LLM="$CAIXA19/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

RESULTADO_1A=$(RFM_ROOT="$CAIXA19" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cntResumos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;
const cntMarcadas = db.prepare('SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL').get().c;
db.close();
process.stdout.write(cntResumos + ':' + cntMarcadas);
" 2>/dev/null)

if [ "$RESULTADO_1A" = "10:20" ]; then
  ok=$((ok+1)); echo "  ok   primeira execucao: TETO_GRUPOS=10 grupos consolidados (10 resumos, 20 obs marcadas), 5 grupos ficam pendentes"
else
  falhou=$((falhou+1)); echo "  FALHA primeira execucao: esperava resumos:marcadas = 10:20, veio $RESULTADO_1A"
fi

RFM_ROOT="$CAIXA19" TESTADOR_CHAMAR_LLM="$CAIXA19/dubleLLM.cjs" $MEMORIA consolidar > /dev/null 2>&1

RESULTADO_2A=$(RFM_ROOT="$CAIXA19" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const cntResumos = db.prepare('SELECT COUNT(*) c FROM resumos').get().c;
const cntMarcadas = db.prepare('SELECT COUNT(*) c FROM observacoes WHERE consolidada_em IS NOT NULL').get().c;
db.close();
process.stdout.write(cntResumos + ':' + cntMarcadas);
" 2>/dev/null)

if [ "$RESULTADO_2A" = "15:30" ]; then
  ok=$((ok+1)); echo "  ok   segunda execucao: os 5 grupos pendentes sao consolidados (15 resumos total, 30 obs marcadas)"
else
  falhou=$((falhou+1)); echo "  FALHA segunda execucao: esperava resumos:marcadas = 15:30, veio $RESULTADO_2A"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
