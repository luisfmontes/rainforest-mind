#!/bin/bash
# Bateria do `node scripts/memoria.cjs reconciliar` — store/update/merge/skip
# contra o acervo pendente (Tarefa 2, D2/D3/D4/D6).
# Uso: bash scripts/testa-memoria-reconciliar.sh
#
# Secao 0 filtra o PATH para tirar `claude` dele ANTES de qualquer outra
# secao rodar — a bateria inteira roda sem `claude` acessivel, provando que
# nenhum caso depende do CLI real (todos usam TESTADOR_CHAMAR_LLM, e o unico
# caso que nao usa e o proprio caso de degradacao que espera cair em store).
#
# O que esta bateria prova, nesta ordem:
#   0. claude fora do PATH para o resto da bateria
#   1. iniciar cria o banco (setup)
#   2. update marca a antiga com substituida_por e nao apaga nada
#   3. resposta que nao e JSON cai em store
#   4. acao desconhecida cai em store
#   5. skip nao substitui nada
#   6. merge insere terceira observacao com origem deterministica e nao
#      duplica ao reprocessar (UNIQUE(projeto, origem) segura)
#   7. alvo_id inexistente cai no lado seguro
#   8. candidata substituida nao concorre na busca de candidatas
#   9. candidatas respeitam K_CANDIDATAS e o mesmo projeto
#  10. TETO_RECONCILIAR limita quantas observacoes sao processadas por execucao
#  11. banco ausente: reconciliar sai 0 com aviso
#  12. LLM que falha (mock retorna null) cai em store, exit 0
#  13. sem TESTADOR_CHAMAR_LLM e sem claude no PATH cai em store, exit 0
#  14. constantes exportadas com os nomes exigidos pelo plano

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

MEMORIA="node $SRC/scripts/memoria.cjs"

ok=0; falhou=0

echo "== 0. filtrando PATH para provar que claude nunca e alcancado nesta bateria =="
ANTES_CLAUDE="$(command -v claude 2>/dev/null || true)"
NOVO_PATH=""
OLDIFS="$IFS"
IFS=':'
for dir in $PATH; do
  [ -z "$dir" ] && continue
  if [ -f "$dir/claude" ] || [ -f "$dir/claude.cmd" ] || [ -f "$dir/claude.exe" ] || [ -f "$dir/claude.bat" ]; then
    continue
  fi
  if [ -z "$NOVO_PATH" ]; then NOVO_PATH="$dir"; else NOVO_PATH="$NOVO_PATH:$dir"; fi
done
IFS="$OLDIFS"
export PATH="$NOVO_PATH"
if command -v claude >/dev/null 2>&1; then
  falhou=$((falhou+1)); echo "  FALHA claude continua no PATH mesmo apos filtrar: $(command -v claude)"
else
  ok=$((ok+1)); echo "  ok   claude fora do PATH para o resto desta bateria (antes: ${ANTES_CLAUDE:-(nao estava no PATH)})"
fi

echo
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
echo "== 2. update marca a antiga com substituida_por e nao apaga nada =="
# Par real medido no acervo (docs/rainforest/planos/2026-09-16-...): a antiga
# que a captura ficou parada e a nova que corrige o mesmo incidente.
CAIXA2="$(novo_sandbox)"
RFM_ROOT="$CAIXA2" $MEMORIA iniciar > /dev/null 2>&1
IDS=$(RFM_ROOT="$CAIXA2" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = Date.now();
const antigaTs = new Date(agora - 120000).toISOString();
const novaTs = new Date(agora - 60000).toISOString();
const rAntiga = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-update', 'Captura parada desde 2026-09-03 por spawn EINVAL no claude.cmd', antigaTs, 'origem-antiga');
const rNova = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-update', 'Captura religada: #282 corrigido, PR #283 mergeado', novaTs, 'origem-nova');
db.close();
process.stdout.write(rAntiga.lastInsertRowid + ':' + rNova.lastInsertRowid);
" 2>/dev/null)
ID_ANTIGA=$(echo "$IDS" | cut -d: -f1)
ID_NOVA=$(echo "$IDS" | cut -d: -f2)

cat > "$CAIXA2/mock-update.cjs" <<EOF
async function chamarLLM(texto) {
  return JSON.stringify({ acao: 'update', alvo_id: $ID_ANTIGA });
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA2" TESTADOR_CHAMAR_LLM="$CAIXA2/mock-update.cjs" $MEMORIA reconciliar > /dev/null 2>&1
got=$?
RESULTADO=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare('SELECT COUNT(*) t, SUM(substituida_por IS NOT NULL) s, SUM(reconciliada_em IS NOT NULL) c FROM observacoes').get();
console.log(r.t,r.s,r.c);
" "$CAIXA2/rainforest.db" 2>/dev/null)
if [ "$got" = "0" ] && [ "$RESULTADO" = "2 1 2" ]; then
  ok=$((ok+1)); echo "  ok   update marca a antiga com substituida_por e nao apaga nada ($RESULTADO)"
else
  falhou=$((falhou+1)); echo "  FALHA update: esperava exit 0 e '2 1 2', veio exit=$got resultado='$RESULTADO'"
fi

APONTA=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const db=new DatabaseSync(process.argv[1],{readOnly:true});
const r=db.prepare('SELECT substituida_por FROM observacoes WHERE id = ?').get(Number(process.argv[2]));
console.log(r.substituida_por);
" "$CAIXA2/rainforest.db" "$ID_ANTIGA" 2>/dev/null)
if [ "$APONTA" = "$ID_NOVA" ]; then
  ok=$((ok+1)); echo "  ok   substituida_por da antiga aponta para o id da nova ($ID_NOVA)"
else
  falhou=$((falhou+1)); echo "  FALHA substituida_por da antiga: esperava $ID_NOVA, veio $APONTA"
fi

echo
echo "== 3. resposta que nao e JSON cai em store =="
CAIXA3="$(novo_sandbox)"
RFM_ROOT="$CAIXA3" $MEMORIA iniciar > /dev/null 2>&1
IDS3=$(RFM_ROOT="$CAIXA3" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = Date.now();
const t1 = new Date(agora - 120000).toISOString();
const t2 = new Date(agora - 60000).toISOString();
const r1 = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-naojson', 'Captura parada desde 2026-09-03 por spawn EINVAL no claude.cmd', t1, 'o1');
const r2 = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-naojson', 'Captura religada: #282 corrigido, PR #283 mergeado', t2, 'o2');
db.close();
process.stdout.write(r1.lastInsertRowid + ':' + r2.lastInsertRowid);
" 2>/dev/null)

cat > "$CAIXA3/mock-texto.cjs" <<'EOF'
async function chamarLLM(texto) {
  return "isto nao e JSON de jeito nenhum, so texto solto da LLM";
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA3" TESTADOR_CHAMAR_LLM="$CAIXA3/mock-texto.cjs" $MEMORIA reconciliar > /dev/null 2>&1
got=$?
RESULTADO3=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare('SELECT COUNT(*) t, SUM(substituida_por IS NOT NULL) s, SUM(reconciliada_em IS NOT NULL) c FROM observacoes').get();
console.log(r.t,r.s,r.c);
" "$CAIXA3/rainforest.db" 2>/dev/null)
if [ "$got" = "0" ] && [ "$RESULTADO3" = "2 0 2" ]; then
  ok=$((ok+1)); echo "  ok   resposta ilegivel cai em store ($RESULTADO3), exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA resposta nao-JSON: esperava exit 0 e '2 0 2', veio exit=$got resultado='$RESULTADO3'"
fi

echo
echo "== 4. acao desconhecida cai em store =="
CAIXA4="$(novo_sandbox)"
RFM_ROOT="$CAIXA4" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA4" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = Date.now();
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-desconhecida', 'Endpoint de faturamento agora responde em menos de 200ms', new Date(agora - 60000).toISOString(), 'o1');
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-desconhecida', 'Endpoint de faturamento com latencia alta em producao', new Date(agora - 120000).toISOString(), 'o2');
db.close();
" 2>/dev/null

cat > "$CAIXA4/mock-desconhecida.cjs" <<'EOF'
async function chamarLLM(texto) {
  return JSON.stringify({ acao: 'delete', alvo_id: 1 });
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA4" TESTADOR_CHAMAR_LLM="$CAIXA4/mock-desconhecida.cjs" $MEMORIA reconciliar > /dev/null 2>&1
got=$?
RESULTADO4=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare('SELECT COUNT(*) t, SUM(substituida_por IS NOT NULL) s, SUM(reconciliada_em IS NOT NULL) c FROM observacoes').get();
console.log(r.t,r.s,r.c);
" "$CAIXA4/rainforest.db" 2>/dev/null)
if [ "$got" = "0" ] && [ "$RESULTADO4" = "2 0 2" ]; then
  ok=$((ok+1)); echo "  ok   acao desconhecida ('delete') cai em store ($RESULTADO4)"
else
  falhou=$((falhou+1)); echo "  FALHA acao desconhecida: esperava '2 0 2', veio '$RESULTADO4' (exit $got)"
fi

echo
echo "== 5. skip nao substitui nada =="
CAIXA5="$(novo_sandbox)"
RFM_ROOT="$CAIXA5" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA5" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = Date.now();
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-skip', 'Regra de desconto por volume documentada no manual fiscal', new Date(agora - 60000).toISOString(), 'o1');
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-skip', 'Regra de desconto por volume ja documentada no manual fiscal, sem novidade', new Date(agora - 120000).toISOString(), 'o2');
db.close();
" 2>/dev/null

cat > "$CAIXA5/mock-skip.cjs" <<'EOF'
async function chamarLLM(texto) {
  return JSON.stringify({ acao: 'skip', alvo_id: null });
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA5" TESTADOR_CHAMAR_LLM="$CAIXA5/mock-skip.cjs" $MEMORIA reconciliar > /dev/null 2>&1
got=$?
RESULTADO5=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare('SELECT COUNT(*) t, SUM(substituida_por IS NOT NULL) s, SUM(reconciliada_em IS NOT NULL) c FROM observacoes').get();
console.log(r.t,r.s,r.c);
" "$CAIXA5/rainforest.db" 2>/dev/null)
if [ "$got" = "0" ] && [ "$RESULTADO5" = "2 0 2" ]; then
  ok=$((ok+1)); echo "  ok   skip nao substitui nada ($RESULTADO5)"
else
  falhou=$((falhou+1)); echo "  FALHA skip: esperava '2 0 2', veio '$RESULTADO5' (exit $got)"
fi

echo
echo "== 6. merge insere terceira observacao com origem deterministica e nao duplica ao reprocessar =="
CAIXA6="$(novo_sandbox)"
RFM_ROOT="$CAIXA6" $MEMORIA iniciar > /dev/null 2>&1
IDS_MERGE=$(RFM_ROOT="$CAIXA6" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = Date.now();
const t1 = new Date(agora - 120000).toISOString();
const t2 = new Date(agora - 60000).toISOString();
const r1 = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-merge', 'Servidor de staging usa Postgres 14 para o modulo de faturamento', t1, 'origem-merge-1');
const r2 = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-merge', 'Modulo de faturamento tambem grava auditoria no Postgres 14 de staging', t2, 'origem-merge-2');
db.close();
process.stdout.write(r1.lastInsertRowid + ':' + r2.lastInsertRowid);
" 2>/dev/null)
ID_A=$(echo "$IDS_MERGE" | cut -d: -f1)
ID_B=$(echo "$IDS_MERGE" | cut -d: -f2)
if [ "$ID_A" -lt "$ID_B" ]; then ID_MENOR=$ID_A; ID_MAIOR=$ID_B; else ID_MENOR=$ID_B; ID_MAIOR=$ID_A; fi
ORIGEM_ESPERADA="reconciliacao:${ID_MENOR}+${ID_MAIOR}"

cat > "$CAIXA6/mock-merge.cjs" <<EOF
async function chamarLLM(texto) {
  return JSON.stringify({ acao: 'merge', alvo_id: $ID_A });
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA6" TESTADOR_CHAMAR_LLM="$CAIXA6/mock-merge.cjs" $MEMORIA reconciliar > /dev/null 2>&1

RODADA1=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const d=new DatabaseSync(process.argv[1],{readOnly:true});
const t=d.prepare('SELECT COUNT(*) n FROM observacoes').get().n;
const s=d.prepare('SELECT COUNT(*) n FROM observacoes WHERE substituida_por IS NOT NULL').get().n;
const o=d.prepare('SELECT COUNT(*) n FROM observacoes WHERE origem = ?').get(process.argv[2]).n;
console.log(t, s, o);
" "$CAIXA6/rainforest.db" "$ORIGEM_ESPERADA" 2>/dev/null)
echo "  1a rodada (total substituidas linhas-com-a-origem-esperada): $RODADA1"

# Resetar A e B para forcar reprocessamento do mesmo par pela LLM.
RFM_ROOT="$CAIXA6" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
db.prepare('UPDATE observacoes SET substituida_por = NULL, reconciliada_em = NULL WHERE id IN (?, ?)').run(Number('$ID_A'), Number('$ID_B'));
db.close();
" 2>/dev/null

RFM_ROOT="$CAIXA6" TESTADOR_CHAMAR_LLM="$CAIXA6/mock-merge.cjs" $MEMORIA reconciliar > /dev/null 2>&1

RODADA2=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const d=new DatabaseSync(process.argv[1],{readOnly:true});
const t=d.prepare('SELECT COUNT(*) n FROM observacoes').get().n;
const s=d.prepare('SELECT COUNT(*) n FROM observacoes WHERE substituida_por IS NOT NULL').get().n;
const o=d.prepare('SELECT COUNT(*) n FROM observacoes WHERE origem = ?').get(process.argv[2]).n;
console.log(t, s, o);
" "$CAIXA6/rainforest.db" "$ORIGEM_ESPERADA" 2>/dev/null)
echo "  2a rodada (total substituidas linhas-com-a-origem-esperada): $RODADA2"

if [ "$RODADA1" = "3 2 1" ] && [ "$RODADA2" = "3 2 1" ]; then
  ok=$((ok+1)); echo "  ok   merge insere a terceira observacao e reprocessar o mesmo par nao duplica"
else
  falhou=$((falhou+1)); echo "  FALHA merge: esperava '3 2 1' nas duas rodadas, veio 1a='$RODADA1' 2a='$RODADA2'"
fi

echo
echo "== 7. alvo_id inexistente cai no lado seguro =="
CAIXA7="$(novo_sandbox)"
RFM_ROOT="$CAIXA7" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA7" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = Date.now();
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-alvo-invalido', 'Chave de API rotacionada para o ambiente de homologacao', new Date(agora).toISOString(), 'o1');
db.close();
" 2>/dev/null

cat > "$CAIXA7/mock-alvo-invalido.cjs" <<'EOF'
async function chamarLLM(texto) {
  return JSON.stringify({ acao: 'update', alvo_id: 999999 });
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA7" TESTADOR_CHAMAR_LLM="$CAIXA7/mock-alvo-invalido.cjs" $MEMORIA reconciliar > /dev/null 2>&1
got=$?
RESULTADO7=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare('SELECT COUNT(*) t, SUM(substituida_por IS NOT NULL) s, SUM(reconciliada_em IS NOT NULL) c FROM observacoes').get();
console.log(r.t,r.s,r.c);
" "$CAIXA7/rainforest.db" 2>/dev/null)
if [ "$got" = "0" ] && [ "$RESULTADO7" = "1 0 1" ]; then
  ok=$((ok+1)); echo "  ok   alvo_id inexistente cai no lado seguro ($RESULTADO7)"
else
  falhou=$((falhou+1)); echo "  FALHA alvo_id inexistente: esperava '1 0 1', veio '$RESULTADO7' (exit $got)"
fi

echo
echo "== 8. candidata substituida nao concorre na busca de candidatas =="
CAIXA8="$(novo_sandbox)"
RFM_ROOT="$CAIXA8" $MEMORIA iniciar > /dev/null 2>&1
RESULTADO8=$(RFM_ROOT="$CAIXA8" node --no-warnings -e "
const { abrirBanco, buscarCandidatas } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = new Date().toISOString();
const rViva = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-cand', 'Pipeline de deploy azul-verde configurado para o servico de pagamentos', agora, 'viva');
const rSubstituida = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-cand', 'Pipeline de deploy azul-verde do servico de pagamentos com bug conhecido', agora, 'substituida');
const rSonda = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-cand', 'Pipeline de deploy azul-verde do servico de pagamentos', agora, 'sonda');
db.prepare('UPDATE observacoes SET substituida_por = ? WHERE id = ?').run(rViva.lastInsertRowid, rSubstituida.lastInsertRowid);
const sonda = { id: rSonda.lastInsertRowid, projeto: 'proj-cand', conteudo: 'Pipeline de deploy azul-verde do servico de pagamentos' };
const cands = buscarCandidatas(db, sonda);
db.close();
process.stdout.write(JSON.stringify(cands.map(c => c.id)) + ':' + rViva.lastInsertRowid + ':' + rSubstituida.lastInsertRowid);
" 2>/dev/null)
IDS_CAND=$(echo "$RESULTADO8" | cut -d: -f1)
ID_VIVA8=$(echo "$RESULTADO8" | cut -d: -f2)
ID_SUBST8=$(echo "$RESULTADO8" | cut -d: -f3)
if echo "$IDS_CAND" | grep -q "$ID_VIVA8" && ! echo "$IDS_CAND" | grep -q "\[$ID_SUBST8[,\]]" ; then
  ok=$((ok+1)); echo "  ok   candidata substituida nao aparece, viva aparece (candidatas=$IDS_CAND)"
else
  falhou=$((falhou+1)); echo "  FALHA candidatas=$IDS_CAND deveria conter $ID_VIVA8 e excluir $ID_SUBST8"
fi

echo
echo "== 9. candidatas respeitam K_CANDIDATAS e o mesmo projeto =="
CAIXA9="$(novo_sandbox)"
RFM_ROOT="$CAIXA9" $MEMORIA iniciar > /dev/null 2>&1
RESULTADO9=$(RFM_ROOT="$CAIXA9" node --no-warnings -e "
const { abrirBanco, buscarCandidatas, K_CANDIDATAS } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = new Date().toISOString();
const idsP1 = [];
for (let i = 0; i < 7; i++) {
  const r = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
    .run('proj-k', 'Assunto compartilhado alfa beta gama observacao ' + i, agora, 'p1-' + i);
  idsP1.push(r.lastInsertRowid);
}
const idsP2 = [];
for (let i = 0; i < 3; i++) {
  const r = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
    .run('outro-projeto', 'Assunto compartilhado alfa beta gama observacao ' + i, agora, 'p2-' + i);
  idsP2.push(r.lastInsertRowid);
}
const sonda = { id: idsP1[0], projeto: 'proj-k', conteudo: 'Assunto compartilhado alfa beta gama observacao 0' };
const cands = buscarCandidatas(db, sonda);
db.close();
const foraDoProjeto = cands.filter(c => idsP2.includes(c.id));
process.stdout.write(cands.length + ':' + foraDoProjeto.length + ':' + K_CANDIDATAS);
" 2>/dev/null)
NUM_CAND9=$(echo "$RESULTADO9" | cut -d: -f1)
FORA_PROJETO9=$(echo "$RESULTADO9" | cut -d: -f2)
K_ESPERADO9=$(echo "$RESULTADO9" | cut -d: -f3)
if [ "$NUM_CAND9" = "$K_ESPERADO9" ] && [ "$FORA_PROJETO9" = "0" ]; then
  ok=$((ok+1)); echo "  ok   candidatas: $NUM_CAND9 (== K_CANDIDATAS=$K_ESPERADO9), 0 de outro projeto"
else
  falhou=$((falhou+1)); echo "  FALHA candidatas: $NUM_CAND9 candidatas (esperava $K_ESPERADO9), $FORA_PROJETO9 de outro projeto (esperava 0)"
fi

echo
echo "== 10. TETO_RECONCILIAR limita quantas observacoes sao processadas por execucao =="
CAIXA10="$(novo_sandbox)"
RFM_ROOT="$CAIXA10" $MEMORIA iniciar > /dev/null 2>&1
TOTAL_INSERIDAS=$(RFM_ROOT="$CAIXA10" node --no-warnings -e "
const { abrirBanco, TETO_RECONCILIAR } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const N = TETO_RECONCILIAR + 5;
const base = Date.now();
const stmt = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)');
for (let i = 0; i < N; i++) {
  stmt.run('proj-teto', 'Observacao numero ' + i + ' do teste de teto', new Date(base - (N - i) * 1000).toISOString(), 'teto-' + i);
}
db.close();
process.stdout.write(String(N));
" 2>/dev/null)

cat > "$CAIXA10/mock-teto.cjs" <<'EOF'
async function chamarLLM(texto) {
  return JSON.stringify({ acao: 'skip', alvo_id: null });
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA10" TESTADOR_CHAMAR_LLM="$CAIXA10/mock-teto.cjs" $MEMORIA reconciliar > /dev/null 2>&1
got=$?
RESULTADO10=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const db=new DatabaseSync(process.argv[1],{readOnly:true});
const processadas = db.prepare('SELECT COUNT(*) n FROM observacoes WHERE reconciliada_em IS NOT NULL').get().n;
const pendentes = db.prepare('SELECT COUNT(*) n FROM observacoes WHERE reconciliada_em IS NULL').get().n;
console.log(processadas, pendentes);
" "$CAIXA10/rainforest.db" 2>/dev/null)
PROCESSADAS10=$(echo "$RESULTADO10" | awk '{print $1}')
PENDENTES10=$(echo "$RESULTADO10" | awk '{print $2}')
ESPERADO_PENDENTES=$((TOTAL_INSERIDAS - PROCESSADAS10))
if [ "$got" = "0" ] && [ "$PROCESSADAS10" -le "$TOTAL_INSERIDAS" ] && [ "$PENDENTES10" = "5" ]; then
  ok=$((ok+1)); echo "  ok   TETO_RECONCILIAR respeitado: $PROCESSADAS10 processadas de $TOTAL_INSERIDAS inseridas, $PENDENTES10 ficaram pendentes"
else
  falhou=$((falhou+1)); echo "  FALHA teto: $PROCESSADAS10 processadas, $PENDENTES10 pendentes, de $TOTAL_INSERIDAS inseridas (esperava 5 pendentes)"
fi

echo
echo "== 11. banco ausente: reconciliar sai 0 com aviso =="
CAIXA11="$(novo_sandbox)"
SAIDA11=$(RFM_ROOT="$CAIXA11" $MEMORIA reconciliar 2>&1)
got=$?
if [ "$got" = "0" ] && echo "$SAIDA11" | grep -qi "banco não existe\|banco nao existe"; then
  ok=$((ok+1)); echo "  ok   banco ausente: reconciliar sai 0 com aviso"
else
  falhou=$((falhou+1)); echo "  FALHA banco ausente: esperava exit 0 com aviso, veio exit=$got saida=$SAIDA11"
fi

echo
echo "== 12. LLM que falha (mock retorna null) cai em store, exit 0 =="
CAIXA12="$(novo_sandbox)"
RFM_ROOT="$CAIXA12" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA12" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = Date.now();
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-llm-falha', 'Certificado TLS do gateway renovado em setembro', new Date(agora - 60000).toISOString(), 'o1');
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-llm-falha', 'Certificado TLS do gateway expira em outubro, renovar', new Date(agora - 120000).toISOString(), 'o2');
db.close();
" 2>/dev/null

cat > "$CAIXA12/mock-null.cjs" <<'EOF'
async function chamarLLM(texto) {
  return null;
}
module.exports = { chamarLLM };
EOF

RFM_ROOT="$CAIXA12" TESTADOR_CHAMAR_LLM="$CAIXA12/mock-null.cjs" $MEMORIA reconciliar > /dev/null 2>&1
got=$?
RESULTADO12=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare('SELECT COUNT(*) t, SUM(substituida_por IS NOT NULL) s, SUM(reconciliada_em IS NOT NULL) c FROM observacoes').get();
console.log(r.t,r.s,r.c);
" "$CAIXA12/rainforest.db" 2>/dev/null)
if [ "$got" = "0" ] && [ "$RESULTADO12" = "2 0 2" ]; then
  ok=$((ok+1)); echo "  ok   LLM falhando (retorna null) cai em store, exit 0 ($RESULTADO12)"
else
  falhou=$((falhou+1)); echo "  FALHA LLM falhando: esperava '2 0 2' exit 0, veio '$RESULTADO12' exit=$got"
fi

echo
echo "== 13. sem TESTADOR_CHAMAR_LLM e sem claude no PATH cai em store, exit 0 =="
# PATH ja foi filtrado na secao 0 — claude nao esta acessivel para o processo
# filho nenhum daqui em diante. Sem TESTADOR_CHAMAR_LLM, chamarLLMParaReconciliar
# cai no caminho real (spawn de `claude`), acharExecutavelClaude() retorna null,
# e a decisao cai em store — sem crashar, sem travar a sessao (D1/D8).
CAIXA13="$(novo_sandbox)"
RFM_ROOT="$CAIXA13" $MEMORIA iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA13" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const agora = Date.now();
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-sem-claude', 'Rotina de backup diario movida para as 3h da manha', new Date(agora - 60000).toISOString(), 'o1');
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)')
  .run('proj-sem-claude', 'Rotina de backup diario configurada para 3h', new Date(agora - 120000).toISOString(), 'o2');
db.close();
" 2>/dev/null

SAIDA13=$(RFM_ROOT="$CAIXA13" $MEMORIA reconciliar 2>&1)
got=$?
RESULTADO13=$(node --experimental-sqlite -e "
const{DatabaseSync}=require('node:sqlite');
const r=new DatabaseSync(process.argv[1],{readOnly:true}).prepare('SELECT COUNT(*) t, SUM(substituida_por IS NOT NULL) s, SUM(reconciliada_em IS NOT NULL) c FROM observacoes').get();
console.log(r.t,r.s,r.c);
" "$CAIXA13/rainforest.db" 2>/dev/null)
if [ "$got" = "0" ] && [ "$RESULTADO13" = "2 0 2" ] && echo "$SAIDA13" | grep -qi "não encontrei\|nao encontrei"; then
  ok=$((ok+1)); echo "  ok   sem claude no PATH: cai em store, aviso no stderr, exit 0 ($RESULTADO13)"
else
  falhou=$((falhou+1)); echo "  FALHA sem claude no PATH: esperava '2 0 2' exit 0 com aviso, veio '$RESULTADO13' exit=$got saida=$SAIDA13"
fi

echo
echo "== 14. constantes exportadas com os nomes exigidos pelo plano =="
CONST_CHECK=$(node --no-warnings -e "
const { K_CANDIDATAS, TETO_RECONCILIAR } = require('./scripts/memoria.cjs');
console.log(K_CANDIDATAS, TETO_RECONCILIAR);
" 2>/dev/null)
if [ "$CONST_CHECK" = "5 200" ]; then
  ok=$((ok+1)); echo "  ok   K_CANDIDATAS=5, TETO_RECONCILIAR=200 ($CONST_CHECK)"
else
  falhou=$((falhou+1)); echo "  FALHA constantes: esperava '5 200', veio '$CONST_CHECK'"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
