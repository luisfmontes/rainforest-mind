#!/bin/bash
# Bateria de testes para as Tarefas 5 e 6 do plano (metricas.jsonl + contexto.json).
#
# Sobe um proxy `poda.cjs` real contra um fixture upstream SSE com valores de
# usage CONHECIDOS, e confere campo a campo o que acaba em metricas.jsonl e
# contexto.json — nunca chama a bateria de outro script para inflar "ok".

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
SBP="$(mktemp -d)"
trap 'kill_tudo' EXIT

PID_PODA=""
PID_FIXTURE=""

kill_tudo() {
  # `kill -9` do git-bash nem sempre alcança um processo Windows nativo
  # destacado (spawn detached+unref). taskkill via PID e o comando "parar" do
  # próprio poda.cjs (que usa process.kill do Node, que mapeia para
  # TerminateProcess no Windows) são as duas vias confiáveis.
  if [ -n "$PID_PODA" ]; then
    taskkill //PID "$PID_PODA" //F >/dev/null 2>&1
    kill -9 "$PID_PODA" 2>/dev/null
  fi
  [ -n "$PID_FIXTURE" ] && { taskkill //PID "$PID_FIXTURE" //F >/dev/null 2>&1; kill "$PID_FIXTURE" 2>/dev/null; }
  rm -rf "$SBP"
}

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi; }
afirma() { if eval "$1"; then ok=$((ok+1)); echo "  ok   $2"; else falhou=$((falhou+1)); echo "  FALHA $2"; fi; }

echo "(caixa de areia: $SBP)"

# ===== valores CONHECIDOS do fixture (usage) =====
INPUT_TOKENS=15723
CACHE_CREATION=842
CACHE_READ=391
OUTPUT_TOKENS_PARCIAL=1
OUTPUT_TOKENS_FINAL=257
# nome de header não-padrão (evita colidir com o cabecalho real de auth da
# Anthropic, no mesmo padrao de scripts/testa-poda.sh)
NOME_CABECALHO="x-marcador-poda-teste"
VALOR_CABECALHO="segredo-fixture-nao-e-credencial-real-789"

# ===== FIXTURE UPSTREAM (SSE com message_start aninhado + message_delta) =====
PORTA_UPSTREAM=$((10000 + RANDOM % 25000))

FIXTURE_FILE="$SBP/fixture-sse.js"
cat > "$FIXTURE_FILE" <<FIXTURE_SCRIPT
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORTA = Number(process.argv[2]);
const SBP = process.argv[3];

const evento = (tipo, dados) =>
  'event: ' + tipo + '\\n' + 'data: ' + JSON.stringify(dados) + '\\n\\n';

const SSE_RESPOSTA =
  evento('message_start', {
    type: 'message_start',
    message: {
      id: 'msg_fixture_1',
      model: 'claude-fixture',
      usage: {
        input_tokens: ${INPUT_TOKENS},
        cache_creation_input_tokens: ${CACHE_CREATION},
        cache_read_input_tokens: ${CACHE_READ},
        output_tokens: ${OUTPUT_TOKENS_PARCIAL},
      },
    },
  }) +
  evento('content_block_start', { type: 'content_block_start', index: 0 }) +
  evento('content_block_delta', { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'oi' } }) +
  evento('content_block_stop', { type: 'content_block_stop', index: 0 }) +
  evento('message_delta', {
    type: 'message_delta',
    delta: { stop_reason: 'end_turn', stop_sequence: null },
    usage: { output_tokens: ${OUTPUT_TOKENS_FINAL} },
  }) +
  evento('message_stop', { type: 'message_stop' });

let contadorResp = 0;
const NOME_CAB = '${NOME_CABECALHO}';

const server = http.createServer((req, res) => {
  let corpo = '';
  req.on('data', (c) => { corpo += c.toString(); });
  req.on('end', () => {
    contadorResp++;
    const n = contadorResp;

    // Loga o que o fixture RECEBEU (cabecalho marcador + corpo), para
    // conferencia de passthrough e do grep-negativo do lado do upstream.
    const cabecalhoRecebido = req.headers[NOME_CAB] || null;
    const log = {
      url: req.url,
      cabecalho_marcador: cabecalhoRecebido,
      body: corpo,
    };
    fs.appendFileSync(path.join(SBP, 'fixture-recebido.jsonl'), JSON.stringify(log) + '\n', 'utf8');

    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    res.end(SSE_RESPOSTA);

    // Loga o que o fixture ENVIOU, byte a byte, para hash independente do lado
    // do cliente (nunca compara consigo mesmo).
    fs.writeFileSync(path.join(SBP, 'resposta-enviada-' + n + '.txt'), SSE_RESPOSTA, 'utf8');
  });
});

server.listen(PORTA, '127.0.0.1', () => {
  fs.writeFileSync(path.join(SBP, 'fixture-ready'), 'ok', 'utf8');
});

process.on('SIGTERM', () => process.exit(0));
FIXTURE_SCRIPT

node "$FIXTURE_FILE" "$PORTA_UPSTREAM" "$SBP" &
PID_FIXTURE=$!

for i in {1..30}; do
  [ -f "$SBP/fixture-ready" ] && break
  sleep 0.1
done
afirma "[ -f '$SBP/fixture-ready' ]" "fixture upstream subiu"

# ===== RAIZ DE DADOS DA PODA E "PROJETO" (config) =====
RAIZ_DADOS="$SBP/raiz-dados"
mkdir -p "$RAIZ_DADOS"
echo "# Foco" > "$RAIZ_DADOS/FOCO.md"

PROJETO_VAZIO="$SBP/projeto-vazio"
mkdir -p "$PROJETO_VAZIO"
# Sem .git e sem docs/rainforest/estado: estagioAtivo() devolve null sempre,
# de forma determinística (nenhum "trabalho aberto" para casar com branch nenhuma).

PORTA_PODA=$((10000 + RANDOM % 25000))

echo
echo "== 0. Subir o proxy =="

RFM_ROOT="$RAIZ_DADOS" RFM_PODA_PORTA="$PORTA_PODA" RFM_PODA_UPSTREAM="http://127.0.0.1:$PORTA_UPSTREAM" \
  CLAUDE_PROJECT_DIR="$PROJETO_VAZIO" \
  node "$SRC_WIN/scripts/poda.cjs" iniciar > /dev/null 2>&1

for i in {1..30}; do
  [ -f "$RAIZ_DADOS/poda/poda.pid" ] && break
  sleep 0.1
done
afirma "[ -f '$RAIZ_DADOS/poda/poda.pid' ]" "pidfile criado"

PID_PODA=$(grep -o '"pid"[[:space:]]*:[[:space:]]*[0-9]*' "$RAIZ_DADOS/poda/poda.pid" 2>/dev/null | grep -o '[0-9]*$' || echo "")

for i in {1..30}; do
  (echo > /dev/tcp/127.0.0.1/$PORTA_PODA) 2>/dev/null && break
  sleep 0.1
done

METRICAS="$RAIZ_DADOS/poda/metricas.jsonl"
CONTEXTO="$RAIZ_DADOS/poda/contexto.json"

echo
echo "== 1. Requisicao medida: metricas.jsonl campo a campo (T5) =="

CORPO_1='{"model":"claude-fixture","messages":[{"role":"user","content":"oi"},{"role":"assistant","content":"tudo bem"}]}'
BYTES_ESPERADO=$(printf '%s' "$CORPO_1" | wc -c | tr -d ' ')

CLIENTE_RECEBIDO="$SBP/cliente-recebido-1.txt"
# Grava a resposta em arquivo DIRETO (nunca via $(...), que engole newlines
# finais e corromperia a comparação de hash byte a byte abaixo).
curl -s -X POST "http://127.0.0.1:$PORTA_PODA/v1/messages" \
  -H "Content-Type: application/json" \
  -H "${NOME_CABECALHO}: ${VALOR_CABECALHO}" \
  -d "$CORPO_1" \
  -o "$CLIENTE_RECEBIDO"

sleep 2

afirma "[ -f '$METRICAS' ]" "metricas.jsonl foi criado"
LINHAS_METRICAS=$(wc -l < "$METRICAS" 2>/dev/null || echo 0)
igual "1 linha em metricas.jsonl apos 1 requisicao medida" "1" "$LINHAS_METRICAS"

LINHA_1=$(head -1 "$METRICAS")

ler_campo() {
  node -e "
    const j = JSON.parse(process.argv[2]);
    const caminho = process.argv[1].split('.');
    let v = j;
    for (const p of caminho) v = v == null ? v : v[p];
    console.log(v === undefined ? '__UNDEFINED__' : (v === null ? '__NULL__' : v));
  " "$1" "$LINHA_1"
}

TIMESTAMP=$(ler_campo timestamp)
ESTAGIO=$(ler_campo estagio)
MENSAGENS=$(ler_campo mensagens)
BYTES_CORPO=$(ler_campo bytes_corpo)
DURACAO=$(ler_campo duracao_ms)
U_INPUT=$(ler_campo usage.input_tokens)
U_OUTPUT=$(ler_campo usage.output_tokens)
U_CACHE_READ=$(ler_campo usage.cache_read_input_tokens)
U_CACHE_CREATION=$(ler_campo usage.cache_creation_input_tokens)

afirma "[ -n '$TIMESTAMP' ] && [ '$TIMESTAMP' != '__UNDEFINED__' ]" "campo timestamp presente ($TIMESTAMP)"
igual "campo estagio (sem trabalho aberto == null)" "__NULL__" "$ESTAGIO"
igual "campo mensagens (2 blocos no body)" "2" "$MENSAGENS"
igual "campo bytes_corpo (bytes exatos do body enviado)" "$BYTES_ESPERADO" "$BYTES_CORPO"
afirma "[ '$DURACAO' != '__UNDEFINED__' ] && [ '$DURACAO' -ge 0 ] 2>/dev/null" "campo duracao_ms e numero >= 0 ($DURACAO)"

igual "usage.input_tokens == fixture" "$INPUT_TOKENS" "$U_INPUT"
igual "usage.output_tokens == valor FINAL do message_delta (nao o parcial)" "$OUTPUT_TOKENS_FINAL" "$U_OUTPUT"
igual "usage.cache_read_input_tokens == fixture" "$CACHE_READ" "$U_CACHE_READ"
igual "usage.cache_creation_input_tokens == fixture" "$CACHE_CREATION" "$U_CACHE_CREATION"

echo
echo "== 2. Passthrough continua intacto (hash independente do fixture) =="

RESPOSTA_ENVIADA="$SBP/resposta-enviada-1.txt"

HASH_ENVIADO=$(node -e "const c=require('crypto'),fs=require('fs');console.log(c.createHash('sha256').update(fs.readFileSync(process.argv[1])).digest('hex'))" "$RESPOSTA_ENVIADA")
HASH_RECEBIDO=$(node -e "const c=require('crypto'),fs=require('fs');console.log(c.createHash('sha256').update(fs.readFileSync(process.argv[1])).digest('hex'))" "$CLIENTE_RECEBIDO")
igual "hash da resposta que o fixture enviou == hash do que o cliente recebeu" "$HASH_ENVIADO" "$HASH_RECEBIDO"

echo
echo "== 3. contexto.json apos a requisicao (T6) =="

afirma "[ -f '$CONTEXTO' ]" "contexto.json foi criado"
CTX_VALIDO=$(node -e "try{JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log('sim')}catch{console.log('nao')}" "$CONTEXTO" 2>/dev/null || echo "nao")
igual "contexto.json e JSON valido" "sim" "$CTX_VALIDO"

CTX_REQ_1=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).requisicoes)" "$CONTEXTO")
igual "contexto.json.requisicoes apos 1a requisicao" "1" "$CTX_REQ_1"
CTX_INPUT_1=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).usage.input_tokens)" "$CONTEXTO")
igual "contexto.json.usage.input_tokens == usage da ultima resposta" "$INPUT_TOKENS" "$CTX_INPUT_1"

echo
echo "== 4. requisicoes incrementa a cada chamada =="

CORPO_2='{"model":"claude-fixture","messages":[{"role":"user","content":"de novo"}]}'
curl -s -X POST "http://127.0.0.1:$PORTA_PODA/v1/messages" -H "Content-Type: application/json" -d "$CORPO_2" > /dev/null
sleep 2

CTX_REQ_2=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).requisicoes)" "$CONTEXTO")
igual "contexto.json.requisicoes apos 2a requisicao" "2" "$CTX_REQ_2"

LINHAS_METRICAS_2=$(wc -l < "$METRICAS" 2>/dev/null || echo 0)
igual "2 linhas em metricas.jsonl apos 2 requisicoes" "2" "$LINHAS_METRICAS_2"

echo
echo "== 5. chave 'poda' desligada: N requisicoes nao escrevem nada =="

mkdir -p "$PROJETO_VAZIO/.rainforest"
echo '{"poda": false}' > "$PROJETO_VAZIO/.rainforest/config.json"

TAMANHO_ANTES=$(wc -c < "$METRICAS" 2>/dev/null || echo 0)
CTX_ANTES=$(cat "$CONTEXTO")

for i in 1 2 3; do
  curl -s -X POST "http://127.0.0.1:$PORTA_PODA/v1/messages" -H "Content-Type: application/json" -d "$CORPO_2" > /dev/null
done
sleep 2

TAMANHO_DEPOIS=$(wc -c < "$METRICAS" 2>/dev/null || echo 0)
igual "metricas.jsonl NAO cresce com a chave desligada" "$TAMANHO_ANTES" "$TAMANHO_DEPOIS"

CTX_DEPOIS=$(cat "$CONTEXTO")
igual "contexto.json NAO muda com a chave desligada" "$CTX_ANTES" "$CTX_DEPOIS"

echo
echo "== 6. contexto.json nunca fica pela metade sob requisicoes rapidas em sequencia =="

rm -f "$PROJETO_VAZIO/.rainforest/config.json"

INVALIDOS=0
LEITURAS=0
(
  for i in 1 2 3 4 5; do
    curl -s -X POST "http://127.0.0.1:$PORTA_PODA/v1/messages" -H "Content-Type: application/json" -d "$CORPO_2" > /dev/null &
  done
  wait
) &
BURST_PID=$!

while kill -0 "$BURST_PID" 2>/dev/null; do
  if [ -f "$CONTEXTO" ]; then
    LEITURAS=$((LEITURAS+1))
    node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$CONTEXTO" >/dev/null 2>&1
    [ $? -ne 0 ] && INVALIDOS=$((INVALIDOS+1))
  fi
done
wait "$BURST_PID" 2>/dev/null
sleep 2

afirma "[ '$LEITURAS' -gt 0 ]" "houve leituras concorrentes de contexto.json durante o burst ($LEITURAS)"
igual "zero leituras invalidas de contexto.json durante o burst" "0" "$INVALIDOS"

CTX_FINAL_VALIDO=$(node -e "try{JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log('sim')}catch{console.log('nao')}" "$CONTEXTO" 2>/dev/null || echo "nao")
igual "contexto.json ainda e JSON valido apos o burst" "sim" "$CTX_FINAL_VALIDO"

echo
echo "== 7. grep negativo: cabecalho marcador nunca aparece em metricas.jsonl nem contexto.json =="

if grep -q "$VALOR_CABECALHO" "$METRICAS" 2>/dev/null; then
  falhou=$((falhou+1)); echo "  FALHA cabecalho marcador apareceu em metricas.jsonl"
else
  ok=$((ok+1)); echo "  ok   cabecalho marcador nao aparece em metricas.jsonl"
fi

if grep -q "$VALOR_CABECALHO" "$CONTEXTO" 2>/dev/null; then
  falhou=$((falhou+1)); echo "  FALHA cabecalho marcador apareceu em contexto.json"
else
  ok=$((ok+1)); echo "  ok   cabecalho marcador nao aparece em contexto.json"
fi

# Confere que o fixture de fato RECEBEU o cabecalho (prova que o teste testa
# algo real, e nao um cabecalho que nunca chegou em lugar nenhum)
CAB_NO_FIXTURE=$(node -e "
const fs=require('fs');
const linhas=fs.readFileSync(process.argv[1],'utf8').trim().split('\n');
console.log(JSON.parse(linhas[0]).cabecalho_marcador || 'AUSENTE');
" "$SBP/fixture-recebido.jsonl")
igual "cabecalho marcador chegou no upstream (prova que o grep negativo testa algo real)" "$VALOR_CABECALHO" "$CAB_NO_FIXTURE"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
