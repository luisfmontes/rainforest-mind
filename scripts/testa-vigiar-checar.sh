#!/bin/bash
# Bateria de testes para vigiar-checar.cjs
#
# Testa a checagem de arme da skill vigiar: integração ligada, bridge acessível,
# caminhos resolvidos. Todos os casos rodam em caixa de areia isolada.

set -u

# ============================================================================
# Setup de caixa de areia
# ============================================================================

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
SBP="$(mktemp -d)"
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"

export RFM_ROOT="$SB/dados-rainforest"
LAR="$SB/home-usuario"
PROJ="$SB/projeto"
mkdir -p "$RFM_ROOT" "$LAR" "$PROJ"

# Windows: HOME e USERPROFILE precisam estar ambos em cygpath -m
export HOME="$LAR"
export USERPROFILE="$(cygpath -m "$LAR" 2>/dev/null || printf '%s' "$LAR")"
export CLAUDE_PROJECT_DIR="$(cygpath -m "$PROJ" 2>/dev/null || printf '%s' "$PROJ")"

# Pasta temporária para WhatsApp MCP
WHATSAPP_MCP_TMP="$SB/whatsapp-mcp-teste"
mkdir -p "$WHATSAPP_MCP_TMP/scripts" "$WHATSAPP_MCP_TMP/commands"
touch "$WHATSAPP_MCP_TMP/scripts/watch_chat.py"

export WHATSAPP_MCP_DIR="$(cygpath -m "$WHATSAPP_MCP_TMP" 2>/dev/null || printf '%s' "$WHATSAPP_MCP_TMP")"

trap 'rm -rf "$SBP"; kill $(jobs -p) 2>/dev/null || true' EXIT

ok=0
falhou=0

log_ok() { ok=$((ok+1)); echo "  ok   $1"; }
log_falha() { falhou=$((falhou+1)); echo "  FALHA $1"; }

teste_saida() {
  local nome="$1" esperado="$2" cmd="$3"
  local saida exit_code
  saida="$(eval "$cmd" 2>&1)"
  exit_code=$?

  if [ "$exit_code" = "$esperado" ]; then
    log_ok "$nome (exit $exit_code)"
    echo "$saida"
  else
    log_falha "$nome: esperava exit $esperado, veio $exit_code"
    echo "$saida" | head -5
  fi
  echo "$saida"
}

echo "== vigiar-checar: checagem de arme da skill vigiar =="
echo "(caixa de areia: $SB)"
echo

# ============================================================================
# Caso 1: chave desligada recusa em uma linha sem consultar a bridge
# ============================================================================

echo "== Caso 1: chave desligada recusa em uma linha sem consultar a bridge =="

# Montar config com chave desligada
mkdir -p "$PROJ/.rainforest"
echo '{"integracao-whatsapp-mcp": false}' > "$PROJ/.rainforest/config.json"

# Criar accounts.json
mkdir -p "$LAR/.whatsapp-mcp"
cat > "$LAR/.whatsapp-mcp/accounts.json" <<'EOF'
{
  "accounts": {
    "pessoal": {
      "dir": "/tmp/bridge-pessoal",
      "port": 3005,
      "jid": "test-user-pessoal:0@s.whatsapp.net"
    }
  }
}
EOF
export WHATSAPP_ACCOUNTS_FILE="$LAR/.whatsapp-mcp/accounts.json"

# Rodar sem servidor falso — não deve fazer requisição à bridge
SAIDA1=$(teste_saida "chave desligada recusa" 2 "node '$SRC_WIN/scripts/vigiar-checar.cjs' --conta pessoal")
if echo "$SAIDA1" | grep -q "integracao WhatsApp nao ligada"; then
  log_ok "mensagem de erro correta"
else
  log_falha "mensagem de erro não menciona integração"
fi

echo

# ============================================================================
# Caso 2: bridge fora recusa nomeando conta e porta
# ============================================================================

echo "== Caso 2: bridge fora recusa nomeando conta e porta =="

# Ligar a chave
echo '{"integracao-whatsapp-mcp": true}' > "$PROJ/.rainforest/config.json"

# Criar accounts com portas fictícias que ninguém está escutando
cat > "$LAR/.whatsapp-mcp/accounts.json" <<'EOF'
{
  "accounts": {
    "pessoal": {
      "dir": "/tmp/bridge-pessoal",
      "port": 29999,
      "jid": "test-user-pessoal:0@s.whatsapp.net"
    },
    "trabalho": {
      "dir": "/tmp/bridge-trabalho",
      "port": 29998,
      "jid": "test-user-trabalho:0@s.whatsapp.net"
    }
  }
}
EOF

SAIDA2=$(teste_saida "bridge fora: porta recusada" 2 "node '$SRC_WIN/scripts/vigiar-checar.cjs' --conta pessoal")
if echo "$SAIDA2" | grep -q "pessoal.*29999"; then
  log_ok "mensagem menciona conta e porta"
else
  log_falha "mensagem não menciona conta/porta corretamente"
fi

echo

# ============================================================================
# Caso 3: conta inexistente lista as contas
# ============================================================================

echo "== Caso 3: conta inexistente lista as contas =="

SAIDA3=$(teste_saida "conta inexistente lista contas" 2 "node '$SRC_WIN/scripts/vigiar-checar.cjs' --conta inexistente")
if echo "$SAIDA3" | grep -q "pessoal"; then
  log_ok "lista contém 'pessoal'"
else
  log_falha "lista não contém 'pessoal'"
fi

if echo "$SAIDA3" | grep -q "trabalho"; then
  log_ok "lista contém 'trabalho'"
else
  log_falha "lista não contém 'trabalho'"
fi

echo

# ============================================================================
# Caso 4: conta de outra porta devolve status_url da porta dela
# ============================================================================

echo "== Caso 4: conta de outra porta devolve status_url da porta dela =="

# Usar serverNode em background para servir status conectado
node -e "
const http = require('http');
const fs = require('fs');
const path = require('path');
const statusConectada = JSON.parse(fs.readFileSync('$SRC_WIN/hooks/fixtures/vigiar/status-conectada.json', 'utf8'));
const server = http.createServer((req, res) => {
  if (req.url === '/api/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(statusConectada));
  } else {
    res.writeHead(404);
    res.end();
  }
});
server.listen(0, '127.0.0.1', () => {
  const porta = server.address().port;
  const portaFile = path.join('$SB', 'porta-trabalho.txt');
  fs.writeFileSync(portaFile, String(porta));
});
" &
SERVERPID1=\$!

# Aguardar arquivo de porta
for i in $(seq 1 50); do
  if [ -f "$SBP/porta-trabalho.txt" ]; then
    break
  fi
  sleep 0.1
done

PORTA_TRABALHO=$(cat "$SBP/porta-trabalho.txt" 2>/dev/null || echo "0")

# Atualizar accounts.json com porta dinâmica para trabalho
cat > "$LAR/.whatsapp-mcp/accounts.json" <<EOF
{
  "accounts": {
    "pessoal": {
      "dir": "/tmp/bridge-pessoal",
      "port": 29999,
      "jid": "test-user-pessoal:0@s.whatsapp.net"
    },
    "trabalho": {
      "dir": "/tmp/bridge-trabalho",
      "port": $PORTA_TRABALHO,
      "jid": "test-user-trabalho:0@s.whatsapp.net"
    }
  }
}
EOF

sleep 0.2

SAIDA4=$(teste_saida "conta trabalho devolve JSON" 0 "node '$SRC_WIN/scripts/vigiar-checar.cjs' --conta trabalho")
if echo "$SAIDA4" | grep -q "\"porta\":$PORTA_TRABALHO"; then
  log_ok "JSON contém porta correta de trabalho"
else
  log_falha "JSON não contém porta correta"
fi

if echo "$SAIDA4" | grep -q "\"status_url\":\"http://127.0.0.1:$PORTA_TRABALHO"; then
  log_ok "status_url usa porta de trabalho, não 3005"
else
  log_falha "status_url não usa porta de trabalho"
fi

kill $SERVERPID1 2>/dev/null || true

echo

# ============================================================================
# Caso 5: script ausente recusa
# ============================================================================

echo "== Caso 5: script ausente recusa =="

# Remover o script vazio que criamos
rm -f "$WHATSAPP_MCP_TMP/scripts/watch_chat.py"

SAIDA5=$(teste_saida "script ausente recusa" 2 "node '$SRC_WIN/scripts/vigiar-checar.cjs' --conta trabalho")
if echo "$SAIDA5" | grep -q "script não encontrado"; then
  log_ok "mensagem menciona script não encontrado"
else
  log_falha "mensagem não menciona script não encontrado"
fi

echo

# ============================================================================
# Caso 6: tudo certo devolve json com os caminhos
# ============================================================================

echo "== Caso 6: tudo certo devolve json com os caminhos =="

# Recriar script
mkdir -p "$WHATSAPP_MCP_TMP/scripts"
touch "$WHATSAPP_MCP_TMP/scripts/watch_chat.py"

# Ligar chave e ter porta de servidor
echo '{"integracao-whatsapp-mcp": true}' > "$PROJ/.rainforest/config.json"

# Servidor conectado novamente
node -e "
const http = require('http');
const fs = require('fs');
const path = require('path');
const statusConectada = JSON.parse(fs.readFileSync('$SRC_WIN/hooks/fixtures/vigiar/status-conectada.json', 'utf8'));
const server = http.createServer((req, res) => {
  if (req.url === '/api/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(statusConectada));
  } else {
    res.writeHead(404);
    res.end();
  }
});
server.listen(0, '127.0.0.1', () => {
  const porta = server.address().port;
  const portaFile = path.join('$SB', 'porta-pessoal.txt');
  fs.writeFileSync(portaFile, String(porta));
});
" &
SERVERPID2=\$!

# Aguardar arquivo de porta
for i in $(seq 1 50); do
  if [ -f "$SBP/porta-pessoal.txt" ]; then
    break
  fi
  sleep 0.1
done

PORTA_PESSOAL=$(cat "$SBP/porta-pessoal.txt" 2>/dev/null || echo "0")

# Atualizar accounts.json
cat > "$LAR/.whatsapp-mcp/accounts.json" <<EOF
{
  "accounts": {
    "pessoal": {
      "dir": "/tmp/bridge-pessoal",
      "port": $PORTA_PESSOAL,
      "jid": "test-user-pessoal:0@s.whatsapp.net"
    }
  }
}
EOF

sleep 0.2

SAIDA6=$(teste_saida "tudo certo devolve JSON" 0 "node '$SRC_WIN/scripts/vigiar-checar.cjs' --conta pessoal")

if echo "$SAIDA6" | grep -q '"conta":"pessoal"'; then
  log_ok "JSON contém conta"
else
  log_falha "JSON não contém conta"
fi

if echo "$SAIDA6" | grep -q '"porta"'; then
  log_ok "JSON contém porta"
else
  log_falha "JSON não contém porta"
fi

if echo "$SAIDA6" | grep -q '"status_url"'; then
  log_ok "JSON contém status_url"
else
  log_falha "JSON não contém status_url"
fi

if echo "$SAIDA6" | grep -q '"script"'; then
  log_ok "JSON contém script"
else
  log_falha "JSON não contém script"
fi

if echo "$SAIDA6" | grep -q '"vigiar_md"'; then
  log_ok "JSON contém vigiar_md"
else
  log_falha "JSON não contém vigiar_md"
fi

if echo "$SAIDA6" | grep -q '"db"'; then
  log_ok "JSON contém db"
else
  log_falha "JSON não contém db"
fi

kill $SERVERPID2 2>/dev/null || true

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
