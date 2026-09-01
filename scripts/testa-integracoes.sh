#!/bin/bash
# Bateria do scripts/integracoes.cjs — checagens de whatsapp-mcp e sabia
# Uso: bash scripts/testa-integracoes.sh
#
# Casos de teste:
# (a) Servidor fixture em porta livre + WHATSAPP_API_BASE_URL apontando → checar ok
# (b) Servidor derrubado → não-ok com ação citando "suba a bridge"
# (c) Pasta com sabia.py+.venv registrada → ok "presente"
# (d) Sem .venv → não-ok citando venv/pip
# (e) Slug ausente → não-ok citando o registro

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

# Cria estrutura de teste
DADOS="$CAIXA/dados"; mkdir -p "$DADOS"
DADOS_WIN="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"
export RFM_ROOT="$DADOS_WIN"

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}
contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"; fi
}

echo "== (a) Servidor fixture em porta livre + WHATSAPP_API_BASE_URL apontando → ok =="
# Encontra porta livre
PORTA=$(shuf -i 10000-20000 -n 1)
# Inicia servidor HTTP simples
timeout 30 node - "$PORTA" <<'SERV' &
const http = require('http');
const porta = parseInt(process.argv[2], 10);
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('OK');
});
server.listen(porta, '127.0.0.1', () => {
  console.log(`SERVIDOR_PRONTO`);
});
SERV
SERVIDOR_PID=$!

# Aguarda servidor
sleep 1

# Testa com env var apontando para o servidor
test_result=$(RFM_ROOT="$DADOS_WIN" WHATSAPP_API_BASE_URL="http://127.0.0.1:$PORTA/api" node -e "
const { INTEGRACOES } = require('$SRC_WIN/hooks/lib/integracoes.cjs');
const checar = INTEGRACOES['whatsapp-mcp'].checar;
checar(process.env).then(r => {
  console.log(JSON.stringify(r));
  process.exit(r.ok ? 0 : 1);
});
" 2>&1)
test_exit=$?

if [ "$test_exit" = 0 ] && echo "$test_result" | grep -q '"ok":true'; then
  ok=$((ok+1)); echo "  ok   servidor fixture responde, checar retorna ok"
else
  falhou=$((falhou+1)); echo "  FALHA resultado nao foi ok: $test_result"
fi

# Para servidor
kill $SERVIDOR_PID 2>/dev/null || true
wait $SERVIDOR_PID 2>/dev/null || true

echo
echo "== (b) Servidor derrubado → não-ok citando 'suba a bridge' =="
# Testa COM a porta fechada
test_result=$(RFM_ROOT="$DADOS_WIN" WHATSAPP_API_BASE_URL="http://127.0.0.1:$PORTA/api" node -e "
const { INTEGRACOES } = require('$SRC_WIN/hooks/lib/integracoes.cjs');
const checar = INTEGRACOES['whatsapp-mcp'].checar;
checar(process.env).then(r => {
  console.log(JSON.stringify(r));
  process.exit(r.ok ? 0 : 1);
});
" 2>&1)
test_exit=$?

if [ "$test_exit" != 0 ] && echo "$test_result" | grep -q "suba a bridge"; then
  ok=$((ok+1)); echo "  ok   porta fechada, checar retorna not-ok com ação 'suba a bridge'"
else
  falhou=$((falhou+1)); echo "  FALHA resultado deveria ter 'suba a bridge': $test_result"
fi

echo
echo "== (c) Pasta com sabia.py+.venv registrada → ok 'presente' =="
# Cria estrutura sabia
SABIA_DIR="$CAIXA/sabia"
mkdir -p "$SABIA_DIR/.venv/Scripts"
touch "$SABIA_DIR/sabia.py"
touch "$SABIA_DIR/.venv/marker"

# Registra no projetos.json
SABIA_DIR_WIN="$(cygpath -m "$SABIA_DIR" 2>/dev/null || printf '%s' "$SABIA_DIR")"
node "$SRC_WIN/scripts/setup.cjs" --criar >/dev/null 2>&1
RFM_ROOT="$DADOS_WIN" node "$SRC_WIN/scripts/setup.cjs" --projeto sabia --caminho "$SABIA_DIR_WIN" >/dev/null 2>&1

# Testa checagem
test_result=$(RFM_ROOT="$DADOS_WIN" node -e "
const { INTEGRACOES } = require('$SRC_WIN/hooks/lib/integracoes.cjs');
const checar = INTEGRACOES['sabia'].checar;
const r = checar(process.env);
console.log(JSON.stringify(r));
process.exit(r.ok ? 0 : 1);
" 2>&1)
test_exit=$?

if [ "$test_exit" = 0 ] && echo "$test_result" | grep -q '"ok":true' && echo "$test_result" | grep -q '"detalhe":"presente"'; then
  ok=$((ok+1)); echo "  ok   com sabia.py+.venv, retorna ok com 'presente'"
else
  falhou=$((falhou+1)); echo "  FALHA resultado nao foi ok+presente: $test_result"
fi

echo
echo "== (d) Sem .venv → não-ok citando venv/pip =="
# Remove .venv
rm -rf "$SABIA_DIR/.venv"

# Testa checagem
test_result=$(RFM_ROOT="$DADOS_WIN" node -e "
const { INTEGRACOES } = require('$SRC_WIN/hooks/lib/integracoes.cjs');
const checar = INTEGRACOES['sabia'].checar;
const r = checar(process.env);
console.log(JSON.stringify(r));
process.exit(r.ok ? 0 : 1);
" 2>&1)
test_exit=$?

if [ "$test_exit" != 0 ] && echo "$test_result" | grep -q "python -m venv"; then
  ok=$((ok+1)); echo "  ok   sem .venv, retorna not-ok citando 'python -m venv'"
else
  falhou=$((falhou+1)); echo "  FALHA resultado deveria citar 'python -m venv': $test_result"
fi

echo
echo "== (e) Slug ausente → não-ok citando o registro =="
# Cria nova caixa sem projetos registrados
CAIXA_E="$CAIXA/e"; mkdir -p "$CAIXA_E"
DADOS_E="$CAIXA_E/dados"; mkdir -p "$DADOS_E"
DADOS_E_WIN="$(cygpath -m "$DADOS_E" 2>/dev/null || printf '%s' "$DADOS_E")"

# Testa checagem com projeto não registrado
test_result=$(RFM_ROOT="$DADOS_E_WIN" node -e "
const { INTEGRACOES } = require('$SRC_WIN/hooks/lib/integracoes.cjs');
const checar = INTEGRACOES['sabia'].checar;
const r = checar(process.env);
console.log(JSON.stringify(r));
process.exit(r.ok ? 0 : 1);
" 2>&1)
test_exit=$?

if [ "$test_exit" != 0 ] && echo "$test_result" | grep -q "registre o projeto"; then
  ok=$((ok+1)); echo "  ok   slug ausente, retorna not-ok citando 'registre o projeto'"
else
  falhou=$((falhou+1)); echo "  FALHA resultado deveria citar 'registre o projeto': $test_result"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
