#!/bin/bash
# Bateria do hook `memoria-manutencao-session-start.cjs` e do subcomando
# `node scripts/memoria.cjs manutencao` (Tarefa 5 do plano
# docs/rainforest/planos/2026-09-16-memoria-reconciliacao-e-consolidacao.md,
# D1/D5).
# Uso: bash hooks/testa-memoria-manutencao.sh
#
# O que esta bateria prova, nesta ordem:
#   1. iniciar cria o banco (setup)
#   2. o hook retorna em menos de 1s (o filho segue destacado depois)
#   3. a trava e por dia: a segunda sessao no mesmo dia nao dispara nada
#      (mesmo PID nas duas leituras da trava)
#   4. a trava e atomica no codigo-fonte: fs.openSync(trava, 'wx'), nunca
#      existsSync seguido de escrita
#   5. duas invocacoes disparadas SEM espera entre elas resultam numa unica
#      trava e num unico processo de manutencao (a corrida real que a trava
#      atomica existe para resolver)
#   6. `node scripts/memoria.cjs manutencao` grava a linha de reconciliar
#      ANTES da linha de consolidar no log, com TESTADOR_CHAMAR_LLM mockado
#   7. degradacao: raiz inacessivel (mkdir falha) -> exit 0 com aviso no
#      stderr, nada escrito
#   8. banco NAO migrado (sem substituida_por/reconciliada_em, como o banco
#      real do usuario esta hoje): manutencao garante o esquema sozinha,
#      completa sem "no such column", e nao perde nenhuma linha (emenda
#      2026-09-18 ao plano)
#   9. passo que falha NAO mata a passada: consolidar falha (banco corrompido
#      no meio da execucao) e o processo segue ate o fim, gravando
#      "falhou: <motivo>" e saindo 0 (emenda 2026-09-18 ao plano)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
HOOK="$SRC/hooks/memoria-manutencao-session-start.cjs"
HOOK_WIN="$SRC_WIN/hooks/memoria-manutencao-session-start.cjs"
MEMORIA="node $SRC/scripts/memoria.cjs"

SANDBOXES=()
novo_sandbox() { # devolve o caminho em forma windows (para RFM_ROOT/node)
  local tmpdir; tmpdir=$(mktemp -d)
  SANDBOXES+=("$tmpdir")
  cygpath -m "$tmpdir" 2>/dev/null || printf '%s' "$tmpdir"
}

PIDS_PARA_MATAR=()
cleanup() {
  # Rede de seguranca final: so mata pelo PID se o tasklist confirmar que
  # ainda esta vivo (PID reciclado por outro processo nao pode ser morto as
  # cegas). Nunca por nome/porta.
  for pid in "${PIDS_PARA_MATAR[@]:-}"; do
    [ -z "$pid" ] && continue
    if tasklist //FI "PID eq $pid" 2>/dev/null | grep -q "$pid"; then
      taskkill //PID "$pid" //F >/dev/null 2>&1
    fi
  done
  for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done
}
trap cleanup EXIT

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi; }
afirma() { if eval "$1"; then ok=$((ok+1)); echo "  ok   $2"; else falhou=$((falhou+1)); echo "  FALHA $2"; fi; }

payload() { # $1 = raiz (caminho windows)
  printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"%s","transcript_path":"%s/t.jsonl"}' "$1" "$1"
}

# Espera o filho identificado pela trava terminar — poll SO em
# manutencao.log (nunca por nome/porta; `kill -0` num PID nativo do Windows
# spawnado detached e' pouco confiavel neste ambiente, mesmo comentario que
# scripts/testa-poda-metricas.sh ja registra para `kill -9`), com teto de
# 10s. So chama taskkill se o `tasklist` confirmar que o PID ainda esta
# vivo — nunca incondicional, porque um PID reciclado por outro processo
# depois que o filho real ja terminou nao pode ser morto as cegas.
esperar_filho() { # $1 = caminho da trava
  local trava="$1"
  [ -f "$trava" ] || { echo ""; return; }
  local pid; pid=$(cat "$trava" 2>/dev/null)
  [ -z "$pid" ] && { echo ""; return; }
  local raiz; raiz=$(dirname "$trava")
  local i=0
  while [ "$i" -lt 100 ]; do
    if grep -q "manutencao: completa" "$raiz/manutencao.log" 2>/dev/null; then break; fi
    sleep 0.1
    i=$((i+1))
  done
  PIDS_PARA_MATAR+=("$pid")
  if tasklist //FI "PID eq $pid" 2>/dev/null | grep -q "$pid"; then
    taskkill //PID "$pid" //F >/dev/null 2>&1
  fi
  echo "$pid"
}

echo "== 1. iniciar cria o banco (setup) =="
CAIXA1="$(novo_sandbox)"
RFM_ROOT="$CAIXA1" $MEMORIA iniciar > /dev/null 2>&1
got=$?
if [ "$got" = "0" ] && [ -f "$CAIXA1/rainforest.db" ]; then
  ok=$((ok+1)); echo "  ok   banco criado"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar nao criou o banco (exit $got)"
fi

echo
echo "== 2. o hook retorna em menos de 1s =="
CAIXA2="$(novo_sandbox)"
RFM_ROOT="$CAIXA2" $MEMORIA iniciar > /dev/null 2>&1
payload "$CAIXA2" > "$CAIXA2/payload.json"
T0=$(date +%s%N)
RFM_ROOT="$CAIXA2" node "$HOOK" < "$CAIXA2/payload.json" >/dev/null 2>&1
EXIT2=$?
T1=$(date +%s%N)
MS2=$(( (T1-T0)/1000000 ))
echo "  medicao real: ${MS2} ms"
igual "hook sai 0" "0" "$EXIT2"
afirma "[ $MS2 -lt 1000 ]" "hook retornou em menos de 1000ms (${MS2}ms)"
HOJE2=$(date +%F)
esperar_filho "$CAIXA2/manutencao-$HOJE2.lock" > /dev/null

echo
echo "== 3. trava e por dia; segunda sessao no mesmo dia nao dispara a manutencao =="
CAIXA3="$(novo_sandbox)"
RFM_ROOT="$CAIXA3" $MEMORIA iniciar > /dev/null 2>&1
payload "$CAIXA3" > "$CAIXA3/payload.json"
RFM_ROOT="$CAIXA3" node "$HOOK" < "$CAIXA3/payload.json" >/dev/null 2>&1
EXIT1=$?
HOJE3=$(date +%F)
TRAVA3="$CAIXA3/manutencao-$HOJE3.lock"
PID1=$(esperar_filho "$TRAVA3")
RFM_ROOT="$CAIXA3" node "$HOOK" < "$CAIXA3/payload.json" >"$CAIXA3/stdout2.log" 2>"$CAIXA3/stderr2.log"
EXIT2b=$?
PID2=$(cat "$TRAVA3" 2>/dev/null)
echo "  comando: RFM_ROOT=<sandbox> printf '%s' '<payload>' | node hooks/memoria-manutencao-session-start.cjs; echo \"exit1=\$?\"; A=\$(cat <sandbox>/manutencao-\$(date +%F).lock); RFM_ROOT=<sandbox> printf '%s' '<payload>' | node hooks/memoria-manutencao-session-start.cjs; echo \"exit2=\$?\"; B=\$(cat <sandbox>/manutencao-\$(date +%F).lock); echo \"pid1=\$A pid2=\$B\""
echo "  saida real: exit1=$EXIT1 exit2=$EXIT2b pid1=$PID1 pid2=$PID2"
igual "exit1=0" "0" "$EXIT1"
igual "exit2=0" "0" "$EXIT2b"
afirma "[ -n \"$PID1\" ]" "pid1 nao veio vazio (senao pid1==pid2 passaria comparando dois vazios)"
igual "pid1 igual a pid2 (segunda sessao nao disparou)" "$PID1" "$PID2"
# A trava ja existir e o caminho ESPERADO (outra sessao ganhou a corrida),
# nao um erro — a segunda sessao tem que sair CALADA (sem AVISO no stderr).
# E' esta linha que prova a mutacao do catraca (`--de "if (e.code ===
# 'EEXIST') process.exit(0);"`): o codigo ja tem um process.exit(0) de
# seguranca logo depois (para erro generico), entao desabilitar SO o guarda
# do EEXIST nao chega a deixar o processo spawnar de novo — o efeito
# observavel e outro: o ramo generico (console.error + AVISO) passa a
# rodar tambem para o caso NORMAL de "trava ja tomada por outra sessao",
# que deveria sair calado. E' esse AVISO indevido no stderr que esta
# asserção pega.
if [ -s "$CAIXA3/stderr2.log" ]; then
  falhou=$((falhou+1)); echo "  FALHA segunda sessao imprimiu no stderr (deveria sair calada): $(cat "$CAIXA3/stderr2.log")"
else
  ok=$((ok+1)); echo "  ok   segunda sessao saiu calada (sem AVISO no stderr)"
fi
QTD_INICIOS3=$(grep -c "reconciliar: inicio" "$CAIXA3/manutencao.log" 2>/dev/null | tr -d ' ')
[ -z "$QTD_INICIOS3" ] && QTD_INICIOS3=0
igual "a manutencao rodou UMA vez so (1x 'reconciliar: inicio' no log, segunda sessao nao disparou de novo)" "1" "$QTD_INICIOS3"

echo
echo "== 4. a trava e atomica: fs.openSync(trava, 'wx'), nunca existsSync + escrita =="
if grep -qF "fs.openSync(trava, 'wx')" "$HOOK"; then
  ok=$((ok+1)); echo "  ok   codigo usa fs.openSync(trava, 'wx')"
else
  falhou=$((falhou+1)); echo "  FALHA codigo NAO usa fs.openSync(trava, 'wx')"
fi
if grep -qE "existsSync\(trava\)" "$HOOK"; then
  falhou=$((falhou+1)); echo "  FALHA codigo usa existsSync(trava) em algum ponto (janela de corrida)"
else
  ok=$((ok+1)); echo "  ok   codigo nao usa existsSync(trava) em nenhum ponto"
fi

echo
echo "== 5. duas invocacoes disparadas SEM espera entre elas: so uma cria processo =="
CAIXA5="$(novo_sandbox)"
RFM_ROOT="$CAIXA5" $MEMORIA iniciar > /dev/null 2>&1
payload "$CAIXA5" > "$CAIXA5/payload.json"

RFM_ROOT="$CAIXA5" node "$HOOK" < "$CAIXA5/payload.json" >/dev/null 2>&1 &
JOB1=$!
RFM_ROOT="$CAIXA5" node "$HOOK" < "$CAIXA5/payload.json" >/dev/null 2>&1 &
JOB2=$!
wait "$JOB1" "$JOB2"

HOJE5=$(date +%F)
TRAVA5="$CAIXA5/manutencao-$HOJE5.lock"
esperar_filho "$TRAVA5" > /dev/null

QTD_LOCKS=$(ls "$CAIXA5"/manutencao-*.lock 2>/dev/null | wc -l | tr -d ' ')
QTD_INICIOS=$(grep -c "reconciliar: inicio" "$CAIXA5/manutencao.log" 2>/dev/null | tr -d ' ')
[ -z "$QTD_INICIOS" ] && QTD_INICIOS=0
echo "  travas criadas: $QTD_LOCKS, processos de manutencao que rodaram: $QTD_INICIOS"
igual "exatamente uma trava do dia criada" "1" "$QTD_LOCKS"
igual "exatamente um processo de manutencao rodou (1x 'reconciliar: inicio' no log)" "1" "$QTD_INICIOS"

echo
echo "== 6. node scripts/memoria.cjs manutencao grava reconciliar ANTES de consolidar =="
CAIXA6="$(novo_sandbox)"
RFM_ROOT="$CAIXA6" $MEMORIA iniciar > /dev/null 2>&1
IDS=$(RFM_ROOT="$CAIXA6" SRC_JS="$SRC_WIN" node --no-warnings -e "
const path = require('path');
const { abrirBanco } = require(path.join(process.env.SRC_JS, 'scripts', 'memoria.cjs'));
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = Date.now();
const antigaTs = new Date(agora - 120000).toISOString();
const novaTs = new Date(agora - 60000).toISOString();
const rAntiga = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-manutencao', 'Captura parada desde 2026-09-03 por spawn EINVAL no claude.cmd', antigaTs, 'origem-antiga-manut');
const rNova = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-manutencao', 'Captura religada: #282 corrigido, PR #283 mergeado', novaTs, 'origem-nova-manut');
db.close();
process.stdout.write(rAntiga.lastInsertRowid + ':' + rNova.lastInsertRowid);
" 2>/dev/null)
ID_ANTIGA=$(echo "$IDS" | cut -d: -f1)

cat > "$CAIXA6/mock-manutencao.cjs" <<EOF
async function chamarLLM(texto) {
  return JSON.stringify({ acao: 'update', alvo_id: $ID_ANTIGA });
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA6" TESTADOR_CHAMAR_LLM="$CAIXA6/mock-manutencao.cjs" $MEMORIA manutencao > /dev/null 2>&1
GOT6=$?
LOG6="$CAIXA6/manutencao.log"
LINHA_RECONCILIAR=""
LINHA_CONSOLIDAR=""
if [ -f "$LOG6" ]; then
  LINHA_RECONCILIAR=$(grep -n "reconciliar: inicio" "$LOG6" | head -1 | cut -d: -f1)
  LINHA_CONSOLIDAR=$(grep -n "consolidar: inicio" "$LOG6" | head -1 | cut -d: -f1)
fi
echo "  comando: RFM_ROOT=<sandbox> TESTADOR_CHAMAR_LLM=<mock> node scripts/memoria.cjs manutencao && cat <sandbox>/manutencao.log"
echo "  log real:"
sed 's/^/    /' "$LOG6" 2>/dev/null
igual "manutencao sai 0" "0" "$GOT6"
afirma "[ -n \"$LINHA_RECONCILIAR\" ] && [ -n \"$LINHA_CONSOLIDAR\" ] && [ \"$LINHA_RECONCILIAR\" -lt \"$LINHA_CONSOLIDAR\" ]" "linha de reconciliar (linha $LINHA_RECONCILIAR) vem antes da linha de consolidar (linha $LINHA_CONSOLIDAR)"

# Confirma que o par realmente foi reconciliado (a antiga marcada), prova
# de que o log nao esta so relatando etapas vazias.
RESULTADO6=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare('SELECT substituida_por FROM observacoes WHERE id = ?').get(Number(process.argv[2]));
console.log(r && r.substituida_por !== null ? 'substituida' : 'intacta');
" "$CAIXA6/rainforest.db" "$ID_ANTIGA" 2>/dev/null)
igual "a antiga foi mesmo reconciliada (nao e so log vazio)" "substituida" "$RESULTADO6"

echo
echo "== 7. degradacao: raiz inacessivel (mkdir falha) -> exit 0 com aviso, nada escrito =="
CAIXA7="$(novo_sandbox)"
ARQ7="$CAIXA7/nao-e-diretorio"
node -e "require('fs').writeFileSync(process.argv[1], 'x')" "$ARQ7"
RAIZ7="$ARQ7/sub"
payload "$RAIZ7" > "$CAIXA7/payload7.json"
RFM_ROOT="$RAIZ7" node "$HOOK" < "$CAIXA7/payload7.json" > "$CAIXA7/stdout7.log" 2> "$CAIXA7/stderr7.log"
EXIT7=$?
igual "hook sai 0 mesmo com raiz inacessivel" "0" "$EXIT7"
if [ -s "$CAIXA7/stderr7.log" ]; then
  ok=$((ok+1)); echo "  ok   aviso no stderr ($(cat "$CAIXA7/stderr7.log"))"
else
  falhou=$((falhou+1)); echo "  FALHA nenhum aviso no stderr"
fi
if [ ! -e "$RAIZ7" ]; then
  ok=$((ok+1)); echo "  ok   nada foi escrito na raiz inacessivel"
else
  falhou=$((falhou+1)); echo "  FALHA algo foi escrito em $RAIZ7"
fi

echo
echo "== 8. banco nao migrado: manutencao garante o esquema sozinha =="
# Simula o banco real do usuario: uma tabela `observacoes` do esquema ANTIGO
# (sem substituida_por/reconciliada_em), criada a mao — sem rodar `iniciar`
# antes, igual ao caso 22 de scripts/testa-memoria.sh. Sem o conserto desta
# tarefa, `manutencao` sai com "no such column: substituida_por" e o log para
# em "consolidar: inicio" (process.exit(1) de cmdConsolidar matando o
# processo destacado).
CAIXA8="$(novo_sandbox)"
RFM_ROOT="$CAIXA8" node -e "
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
      .run('proj-nao-migrado', 'Obs nao migrada ' + i, new Date().toISOString(), 'orig-nao-migrada-' + i);
  }
  db.close();
" 2>/dev/null
CNT_ANTES8=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
console.log(new DatabaseSync(process.argv[1],{readOnly:true}).prepare('SELECT COUNT(*) n FROM observacoes').get().n);
" "$CAIXA8/rainforest.db" 2>/dev/null)

cat > "$CAIXA8/mock-vazio.cjs" <<'EOF'
async function chamarLLM(texto) {
  return JSON.stringify({ acao: 'skip' });
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA8" TESTADOR_CHAMAR_LLM="$CAIXA8/mock-vazio.cjs" $MEMORIA manutencao > "$CAIXA8/stdout8.log" 2> "$CAIXA8/stderr8.log"
GOT8=$?
LOG8="$CAIXA8/manutencao.log"
echo "  comando: RFM_ROOT=<sandbox> TESTADOR_CHAMAR_LLM=<mock> node scripts/memoria.cjs manutencao; echo \"exit=\$?\"; cat <sandbox>/manutencao.log"
echo "  saida real: exit=$GOT8"
echo "  log real:"
sed 's/^/    /' "$LOG8" 2>/dev/null
igual "manutencao sai 0 mesmo com banco nao migrado" "0" "$GOT8"
if grep -q "no such column" "$LOG8" "$CAIXA8/stderr8.log" 2>/dev/null; then
  falhou=$((falhou+1)); echo "  FALHA log ou stderr ainda tem 'no such column'"
else
  ok=$((ok+1)); echo "  ok   nenhum 'no such column' no log nem no stderr"
fi
if grep -q "^.*manutencao: completa$" "$LOG8" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   log chega em 'manutencao: completa' (sem falhas)"
else
  falhou=$((falhou+1)); echo "  FALHA log nao chegou em 'manutencao: completa': $(cat "$LOG8" 2>/dev/null)"
fi
RESULTADO8=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const db=new DatabaseSync(process.argv[1],{readOnly:true});
const cols=db.prepare('PRAGMA table_info(observacoes)').all().map(c=>c.name);
const cnt=db.prepare('SELECT COUNT(*) n FROM observacoes').get().n;
console.log(cols.includes('substituida_por')+':'+cols.includes('reconciliada_em')+':'+cnt);
" "$CAIXA8/rainforest.db" 2>/dev/null)
igual "esquema migrado sozinho e nenhuma linha perdida (true:true:$CNT_ANTES8)" "true:true:$CNT_ANTES8" "$RESULTADO8"

echo
echo "== 9. passo que falha nao mata a passada: consolidar falha e o processo segue e sai 0 =="
# Forca uma falha real no passo `consolidar`, sem tocar em codigo: duas
# observacoes que casam por FTS5 (mesmo projeto, termo comum) fazem
# `reconciliar` chamar a LLM mockada; o mock, como efeito colateral, sobrescreve
# o arquivo do banco com bytes que nao sao um SQLite valido. `reconciliar`
# tolera (seu try/catch nunca lanca, registra AVISO e segue) e ainda grava
# "fim". `consolidar`, ao abrir uma conexao NOVA no arquivo corrompido, lanca
# de verdade — e e essa a falha que a Tarefa 5 (emenda 2026-09-18) precisa
# capturar sem derrubar `manutencao`.
CAIXA9="$(novo_sandbox)"
RFM_ROOT="$CAIXA9" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA9" SRC_JS="$SRC_WIN" node --no-warnings -e "
const path = require('path');
const { abrirBanco } = require(path.join(process.env.SRC_JS, 'scripts', 'memoria.cjs'));
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const t1 = new Date(Date.now() - 60000).toISOString();
const t2 = new Date().toISOString();
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)').run('proj-corrupcao', 'Teste de corrupcao Alfa Bravo Charlie', t1, 'origem-corrupcao-1');
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)').run('proj-corrupcao', 'Teste de corrupcao Alfa Bravo Charlie Delta', t2, 'origem-corrupcao-2');
db.close();
" 2>/dev/null

cat > "$CAIXA9/mock-corrompe.cjs" <<'EOF'
async function chamarLLM(texto) {
  const fs = require('fs');
  const path = require('path');
  const caminho = path.join(process.env.RFM_ROOT, 'rainforest.db');
  fs.writeFileSync(caminho, 'corrompido-de-proposito');
  return JSON.stringify({ acao: 'skip' });
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA9" TESTADOR_CHAMAR_LLM="$CAIXA9/mock-corrompe.cjs" $MEMORIA manutencao > "$CAIXA9/stdout9.log" 2> "$CAIXA9/stderr9.log"
GOT9=$?
LOG9="$CAIXA9/manutencao.log"
echo "  comando: forca falha em consolidar (banco corrompido pelo mock durante reconciliar) e roda: RFM_ROOT=<sandbox> TESTADOR_CHAMAR_LLM=<mock> node scripts/memoria.cjs manutencao; echo \"exit=\$?\"; cat <sandbox>/manutencao.log"
echo "  saida real: exit=$GOT9"
echo "  log real:"
sed 's/^/    /' "$LOG9" 2>/dev/null
igual "manutencao sai 0 mesmo com consolidar falhando" "0" "$GOT9"
if grep -q "consolidar: falhou:" "$LOG9" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   log tem 'consolidar: falhou: <motivo>'"
else
  falhou=$((falhou+1)); echo "  FALHA log nao tem 'consolidar: falhou:'"
fi
if grep -q "reconciliar: fim" "$LOG9" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   passo anterior (reconciliar) chegou em 'fim' antes de consolidar quebrar"
else
  falhou=$((falhou+1)); echo "  FALHA reconciliar nao chegou em 'fim'"
fi
ULTIMA_LINHA9=$(tail -1 "$LOG9" 2>/dev/null | sed -E 's/^[^ ]+ //')
igual "linha final diz que a passada NAO completou limpa" "manutencao: completa com falhas" "$ULTIMA_LINHA9"

echo
echo "== resumo =="
echo "ok: $ok, falhou: $falhou"
if [ "$falhou" -gt 0 ]; then
  exit 1
fi
exit 0
