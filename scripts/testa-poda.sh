#!/bin/bash
# Bateria de testes para scripts/poda.cjs — proxy passthrough e ciclo de vida.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"; jobs -p | xargs -r kill 2>/dev/null || true' EXIT

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi; }
afirma() { if eval "$1"; then ok=$((ok+1)); echo "  ok   $2"; else falhou=$((falhou+1)); echo "  FALHA $2"; fi; }

echo "(caixa de areia: $SBP)"

# ===== FIXTURE UPSTREAM =====
PORTA_UPSTREAM=$((10000 + RANDOM % 55000))

# Cria arquivo de fixture
FIXTURE_FILE="$SBP/fixture.js"
cat > "$FIXTURE_FILE" <<'FIXTURE_SCRIPT'
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORTA = Number(process.argv[2]);
const SBP = process.argv[3];

const server = http.createServer((req, res) => {
  let corpo = '';

  req.on('data', (chunk) => {
    corpo += chunk.toString();
  });

  req.on('end', () => {
    // Filtra apenas headers importantes (evita serialização de objetos complexos)
    const headersImportantes = {};
    ['content-type', 'content-length', 'x-custom-auth'].forEach(h => {
      if (req.headers[h]) headersImportantes[h] = req.headers[h];
    });

    const log = {
      method: req.method,
      url: req.url,
      headers: headersImportantes,
      body: corpo,
      timestamp: Date.now(),
    };
    fs.appendFileSync(path.join(SBP, 'fixture-log.jsonl'), JSON.stringify(log) + '\n', 'utf8');

    if (req.url === '/streaming-test') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      let count = 0;
      const timer = setInterval(() => {
        res.write('data: chunk-' + count + '\n\n');
        count++;
        if (count >= 3) {
          clearInterval(timer);
          res.end();
        }
      }, 50);
    } else {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true }) + '\n');
    }
  });
});

server.listen(PORTA, '127.0.0.1', () => {
  fs.writeFileSync(path.join(SBP, 'fixture-ready'), 'ok', 'utf8');
});

process.on('SIGTERM', () => process.exit(0));
FIXTURE_SCRIPT

node "$FIXTURE_FILE" "$PORTA_UPSTREAM" "$SBP" &
FIXTURE_PID=$!

# Aguarda fixture estar pronto
for i in {1..20}; do
  if [ -f "$SBP/fixture-ready" ]; then
    break
  fi
  sleep 0.1
done

sleep 1

echo
echo "== 1. Iniciar proxy e verificar pidfile =="

PORTA_PODA=$((10000 + RANDOM % 55000))

# Determina raiz de dados
RAIZ_FIXTURE="$SBP/raiz-fixture"
mkdir -p "$RAIZ_FIXTURE"
echo "# Foco" > "$RAIZ_FIXTURE/FOCO.md"

RFM_ROOT="$SBP/raiz-fixture" RFM_PODA_PORTA="$PORTA_PODA" RFM_PODA_UPSTREAM="http://127.0.0.1:$PORTA_UPSTREAM" \
  node "$SRC_WIN/scripts/poda.cjs" iniciar 2>&1 | head -1

sleep 5

# Verifica pidfile
PIDFILE="$SBP/raiz-fixture/poda/poda.pid"
afirma "[ -f '$PIDFILE' ]" "pidfile foi criado"

if [ -f "$PIDFILE" ]; then
  # Extrai PID usando grep e awk para evitar problemas de serialização JSON
  PID_PODA=$(grep -o '"pid"[[:space:]]*:[[:space:]]*[0-9]*' "$PIDFILE" | grep -o '[0-9]*$' || echo "")
  afirma "[ ! -z '$PID_PODA' ]" "pidfile contem PID valido"
else
  PID_PODA=""
  falhou=$((falhou+1)); echo "  FALHA pidfile contem PID valido: pidfile nao existe"
fi

echo
echo "== 2. Verificar status =="

RFM_ROOT="$SBP/raiz-fixture" RFM_PODA_PORTA="$PORTA_PODA" node "$SRC_WIN/scripts/poda.cjs" status 2>&1 > /dev/null
STATUS_EXIT=$?
if [ "$STATUS_EXIT" = 0 ]; then
  ok=$((ok+1)); echo "  ok   status retornou exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA status retornou exit $STATUS_EXIT"
fi

echo
echo "== 3. Testar passthrough de requisição =="

# Requisição com corpo JSON
CORPO_TESTE='{"messages": [{"role": "user", "content": "oi"}]}'
HEADER_AUTH="X-Custom-Auth: secret-12345"

RESPONSE=$(curl -s -X POST "http://127.0.0.1:$PORTA_PODA/v1/messages" \
  -H "Content-Type: application/json" \
  -H "$HEADER_AUTH" \
  -d "$CORPO_TESTE")

sleep 2

# Verifica log do fixture
FIXTURE_LOG="$SBP/fixture-log.jsonl"
REQUESTS_COUNT=$(wc -l < "$FIXTURE_LOG" 2>/dev/null || echo 0)

if [ "$REQUESTS_COUNT" -ge 1 ] && echo "$RESPONSE" | grep -q "ok"; then
  ok=$((ok+1)); echo "  ok   corpo repassado (resposta 200 recebida, fixture log $REQUESTS_COUNT linhas)"
else
  falhou=$((falhou+1)); echo "  FALHA corpo repassado: resposta='$RESPONSE' requests=$REQUESTS_COUNT"
fi

if [ "$REQUESTS_COUNT" -ge 1 ] && echo "$RESPONSE" | grep -q "ok"; then
  ok=$((ok+1)); echo "  ok   header repassado (requisição alcançou fixture)"
else
  falhou=$((falhou+1)); echo "  FALHA header repassado"
fi

echo
echo "== 4. Testar body não-JSON =="

curl -s -X POST "http://127.0.0.1:$PORTA_PODA/v1/completions" \
  -H "Content-Type: text/plain" \
  -d "não é json" > /dev/null 2>&1

sleep 1

if [ -f "$FIXTURE_LOG" ] && [ -s "$FIXTURE_LOG" ]; then
  COUNT_ANTES=$(wc -l < "$FIXTURE_LOG" || echo 0)
  # Se há mais de uma linha, testa a última
  if [ "$COUNT_ANTES" -ge 2 ]; then
    ULTIMA=$(tail -1 "$FIXTURE_LOG")
    CORPO=$(node -e "try { const o=JSON.parse('$ULTIMA'); process.stdout.write(o.body); } catch { process.stdout.write(''); }" 2>/dev/null || echo "")
    if [ ! -z "$CORPO" ]; then
      ok=$((ok+1)); echo "  ok   body não-JSON recebido"
    else
      falhou=$((falhou+1)); echo "  FALHA body não-JSON recebido"
    fi
  else
    falhou=$((falhou+1)); echo "  FALHA body não-JSON recebido: apenas uma requisição no log"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA body não-JSON recebido: fixture-log ausente"
fi

echo
echo "== 5. Headers de auth não aparecem em stdout/stderr =="

OUTPUT_TESTE=$({
  RFM_ROOT="$SBP/raiz-fixture" RFM_PODA_PORTA="$PORTA_PODA" node "$SRC_WIN/scripts/poda.cjs" status 2>&1
} || true)

if ! echo "$OUTPUT_TESTE" | grep -q "secret-12345"; then
  ok=$((ok+1)); echo "  ok   header auth nao apareceu em stdout/stderr"
else
  falhou=$((falhou+1)); echo "  FALHA header auth apareceu em stdout/stderr"
fi

echo
echo "== 5.1. TAREFA 3 (plano): corpo chega ao upstream byte a byte (hash sha256) =="
HASH_ENVIADO=$(printf '%s' "$CORPO_TESTE" | node -e "const c=require('crypto');let b='';process.stdin.on('data',d=>b+=d).on('end',()=>console.log(c.createHash('sha256').update(b).digest('hex')))")
SBP_WIN="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
HASH_RECEBIDO=$(node -e "
const fs=require('fs');
const linhas=fs.readFileSync('$SBP_WIN/fixture-log.jsonl','utf8').trim().split('\n');
const primeira=JSON.parse(linhas[0]);
console.log(require('crypto').createHash('sha256').update(primeira.body).digest('hex'));
")
igual "hash do corpo enviado == hash no upstream" "$HASH_ENVIADO" "$HASH_RECEBIDO"

echo
echo "== 5.2. TAREFA 3 (plano): header de auth chega INTACTO ao upstream =="
AUTH_NO_UPSTREAM=$(node -e "
const fs=require('fs');
const linhas=fs.readFileSync('$SBP_WIN/fixture-log.jsonl','utf8').trim().split('\n');
const primeira=JSON.parse(linhas[0]);
console.log(primeira.headers['x-custom-auth'] || 'AUSENTE');
")
igual "x-custom-auth no upstream" "secret-12345" "$AUTH_NO_UPSTREAM"

echo
echo "== 5.3. TAREFA 3 (plano): resposta identica byte a byte (hash) =="
CORPO_RESPOSTA_ESPERADO='{"ok":true}
'
HASH_ESPERADO=$(printf '%s' "$CORPO_RESPOSTA_ESPERADO" | node -e "const c=require('crypto');let b='';process.stdin.on('data',d=>b+=d).on('end',()=>console.log(c.createHash('sha256').update(b).digest('hex')))")
RESPOSTA_CRUA=$(curl -s -X POST "http://127.0.0.1:$PORTA_PODA/v1/messages" -H "Content-Type: application/json" -d '{"x":1}')
HASH_RESPOSTA=$(printf '%s\n' "$RESPOSTA_CRUA" | node -e "const c=require('crypto');let b='';process.stdin.on('data',d=>b+=d).on('end',()=>console.log(c.createHash('sha256').update(b).digest('hex')))")
igual "hash da resposta atraves do proxy == hash do que o fixture manda" "$HASH_ESPERADO" "$HASH_RESPOSTA"

echo
echo "== 5.4. TAREFA 3 (plano): SSE flui em STREAM, nao bufferizado =="
# O fixture /streaming-test manda 3 chunks com 50ms entre eles. Se o proxy
# faz stream, os chunks chegam ESPACADOS no cliente (spread >= 60ms). Se
# bufferiza, chegam todos juntos (spread ~0).
SPREAD=$(node -e "
const http=require('http');
const t=[];
http.get('http://127.0.0.1:$PORTA_PODA/streaming-test', res => {
  res.on('data', () => t.push(Date.now()));
  res.on('end', () => { console.log(t.length >= 2 ? t[t.length-1]-t[0] : -1); });
}).on('error', () => console.log(-2));
" )
afirma "[ \"$SPREAD\" -ge 60 ]" "chunks chegam espacados (spread=${SPREAD}ms >= 60ms) — stream real"

echo
echo "== 5.5. TAREFA 3 (plano): proxy escuta SO em 127.0.0.1 =="
BIND=$(netstat -an 2>/dev/null | grep ":$PORTA_PODA " | grep -i listen | head -1)
afirma "echo '$BIND' | grep -q '127.0.0.1'" "porta $PORTA_PODA ligada em 127.0.0.1 (netstat: $BIND)"
LOCAL_ADDR=$(echo "$BIND" | awk '{print $2}')
afirma "! echo '$LOCAL_ADDR' | grep -q '^0.0.0.0'" "endereco local nao e 0.0.0.0 (local=$LOCAL_ADDR)"

echo
echo "== 6. Parar processo =="

RFM_ROOT="$SBP/raiz-fixture" RFM_PODA_PORTA="$PORTA_PODA" \
  node "$SRC_WIN/scripts/poda.cjs" parar 2>&1 | head -1

sleep 1

afirma "[ ! -f '$PIDFILE' ]" "pidfile foi apagado"

# Verifica que processo morreu
if [ ! -z "$PID_PODA" ] && ! kill -0 "$PID_PODA" 2>/dev/null; then
  ok=$((ok+1)); echo "  ok   processo foi morto"
else
  if [ ! -z "$PID_PODA" ]; then
    falhou=$((falhou+1)); echo "  FALHA processo ainda esta vivo"
    kill -9 "$PID_PODA" 2>/dev/null || true
  fi
fi

# Mata fixture
kill $FIXTURE_PID 2>/dev/null || true

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
