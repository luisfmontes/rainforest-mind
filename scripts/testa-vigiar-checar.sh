#!/bin/bash
# Bateria de vigiar-checar.cjs: a checagem de arme da skill vigiar (D2, D4, D5
# do design 2026-09-25-vigiar-whatsapp). Chave ligada/desligada, bridge da
# conta de pé ou fora, conta certa com a porta certa, caminhos resolvidos.
#
# Caixa de areia: HOME, USERPROFILE, CLAUDE_PROJECT_DIR, RFM_ROOT e
# accounts.json temporários. A bridge é um servidor falso em porta livre que
# serve o formato real do /api/status (fixtures em hooks/fixtures/vigiar/, JID
# fictício) — nunca as portas 3005/3006 das bridges reais.

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
SBP="$(mktemp -d)"
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"

export RFM_ROOT="$SB/dados-rainforest"
LAR="$SB/home-usuario"
PROJ="$SB/projeto"
MCP="$SB/whatsapp-mcp"
mkdir -p "$RFM_ROOT" "$LAR/.whatsapp-mcp" "$PROJ/.rainforest" "$MCP/scripts" "$MCP/commands"
touch "$MCP/scripts/watch_chat.py" "$MCP/commands/vigiar.md"

export HOME="$LAR"
export USERPROFILE="$LAR"
export CLAUDE_PROJECT_DIR="$PROJ"
export WHATSAPP_MCP_DIR="$MCP"
export WHATSAPP_ACCOUNTS_FILE="$LAR/.whatsapp-mcp/accounts.json"

PIDS=()
trap 'for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$SBP"' EXIT

ok=0
falhou=0
log_ok() { ok=$((ok+1)); echo "  ok   $1"; }
log_falha() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# Roda o checador com --conta <alias>; deixa a saída (stdout+stderr) em SAIDA
# e confere o exit. Sem subshell: o placar é o do processo da bateria.
checar() {
  local nome="$1" esperado="$2" conta="$3" code
  SAIDA="$(node "$SRC_WIN/scripts/vigiar-checar.cjs" --conta "$conta" 2>&1)"
  code=$?
  if [ "$code" = "$esperado" ]; then log_ok "$nome (exit $code)"
  else log_falha "$nome: esperava exit $esperado, veio $code — $SAIDA"; fi
}

contem() { # <nome> <padrão grep -E>
  if printf '%s' "$SAIDA" | grep -Eq "$2"; then log_ok "$1"
  else log_falha "$1 — saída: $SAIDA"; fi
}

linhas_da_saida() { printf '%s\n' "$SAIDA" | grep -c .; }

chave() { printf '{"integracao-whatsapp-mcp": %s}\n' "$1" > "$PROJ/.rainforest/config.json"; }

# accounts.json no formato real (~/.whatsapp-mcp/accounts.json, conferido em
# 2026-09-25): contas no topo, cada uma com dir, port e jid.
contas() { # <porta pessoal> <porta trabalho>
  cat > "$WHATSAPP_ACCOUNTS_FILE" <<EOF
{
  "pessoal": { "dir": "$SB/bridge-pessoal", "port": $1, "jid": "conta-pessoal@s.whatsapp.net" },
  "trabalho": { "dir": "$SB/bridge-trabalho", "port": $2, "jid": "conta-trabalho@s.whatsapp.net" }
}
EOF
}

# Bridge falsa: serve hooks/fixtures/vigiar/<fixture> em qualquer caminho,
# anota cada requisição em $SBP/<nome>.hits. Porta em PORTA_<nome>.
subir_servidor() { # <fixture> <nome>
  local fixture="$1" nome="$2" porta=""
  FIXTURE="$SRC_WIN/hooks/fixtures/vigiar/$fixture" SAIDA_SRV="$SB/$nome" node -e '
    const http = require("http"), fs = require("fs");
    const corpo = fs.readFileSync(process.env.FIXTURE, "utf8");
    const srv = http.createServer((req, res) => {
      fs.appendFileSync(process.env.SAIDA_SRV + ".hits", req.url + "\n");
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(corpo);
    });
    srv.listen(0, "127.0.0.1", () => fs.writeFileSync(process.env.SAIDA_SRV + ".porta", String(srv.address().port)));
  ' &
  PIDS+=($!)
  for _ in $(seq 1 50); do [ -s "$SBP/$nome.porta" ] && break; sleep 0.1; done
  porta="$(cat "$SBP/$nome.porta" 2>/dev/null)"
  [ -n "$porta" ] || { log_falha "servidor falso $nome não subiu"; porta=1; }
  printf -v "PORTA_$nome" '%s' "$porta"
}

hits() { [ -f "$SBP/$1.hits" ] && grep -c . "$SBP/$1.hits" || echo 0; }

# Porta livre sem ninguém escutando: abre e fecha um servidor.
PORTA_MORTA="$(node -e 'const s=require("net").createServer().listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})')"

subir_servidor status-conectada.json conectada
subir_servidor status-desconectada.json desconectada
subir_servidor status-conectada.json outra

echo "== vigiar-checar: checagem de arme da skill vigiar =="

echo "-- chave desligada recusa em uma linha sem consultar a bridge"
chave false
contas "$PORTA_conectada" "$PORTA_outra"
checar "chave desligada recusa" 2 pessoal
contem "diz como ligar a chave" "integracao-whatsapp-mcp"
[ "$(linhas_da_saida)" = 1 ] && log_ok "uma linha só" || log_falha "esperava uma linha, veio: $SAIDA"
[ "$(hits conectada)" = 0 ] && log_ok "bridge não foi consultada" || log_falha "bridge recebeu $(hits conectada) requisição(ões) com a chave desligada"

chave true

echo "-- bridge fora recusa nomeando conta e porta"
contas "$PORTA_MORTA" "$PORTA_outra"
checar "porta recusada recusa" 2 pessoal
contem "nomeia conta e porta (recusada)" "pessoal.*$PORTA_MORTA"
contas "$PORTA_desconectada" "$PORTA_outra"
checar "healthy:false recusa" 2 pessoal
contem "nomeia conta e porta (healthy:false)" "pessoal.*$PORTA_desconectada"
[ "$(linhas_da_saida)" = 1 ] && log_ok "uma linha só" || log_falha "esperava uma linha, veio: $SAIDA"

echo "-- conta inexistente lista as contas"
checar "conta inexistente recusa" 2 inexistente
contem "lista pessoal e trabalho" "pessoal.*trabalho|trabalho.*pessoal"

echo "-- conta de outra porta devolve status_url da porta dela"
contas "$PORTA_conectada" "$PORTA_outra"
checar "conta trabalho arma" 0 trabalho
contem "status_url na porta da conta trabalho" "\"status_url\":\"http://127.0.0.1:$PORTA_outra/api/status\""
if printf '%s' "$SAIDA" | grep -q "127.0.0.1:$PORTA_conectada"; then log_falha "saiu a porta da outra conta: $SAIDA"; else log_ok "não usa a porta da outra conta"; fi
[ "$(hits outra)" -ge 1 ] && log_ok "consultou a bridge da conta pedida" || log_falha "não consultou a bridge da conta trabalho"

echo "-- script ausente recusa"
mv "$MCP/scripts/watch_chat.py" "$MCP/scripts/watch_chat.py.fora"
checar "script ausente recusa" 2 pessoal
contem "nomeia o script" "watch_chat.py"
mv "$MCP/scripts/watch_chat.py.fora" "$MCP/scripts/watch_chat.py"

echo "-- tudo certo devolve json com os caminhos"
checar "conta pessoal arma" 0 pessoal
node -e '
  const j = JSON.parse(process.argv[1]), sb = process.argv[2], porta = Number(process.argv[3]);
  const path = require("path"), norm = (p) => path.normalize(p);
  const esperado = {
    conta: "pessoal", porta,
    status_url: `http://127.0.0.1:${porta}/api/status`,
    script: norm(`${sb}/whatsapp-mcp/scripts/watch_chat.py`),
    vigiar_md: norm(`${sb}/whatsapp-mcp/commands/vigiar.md`),
    db: norm(`${sb}/bridge-pessoal/store/messages.db`),
  };
  const errado = Object.keys(esperado).filter((k) => (k === "porta" || k === "conta" || k === "status_url" ? j[k] : norm(j[k])) !== esperado[k]);
  if (errado.length) { console.log("campos errados: " + errado.map((k) => `${k}=${j[k]}`).join(", ")); process.exit(1); }
' "$SAIDA" "$SB" "$PORTA_conectada" && log_ok "json com conta, porta, status_url, script, vigiar_md e db" || log_falha "json fora do esperado: $SAIDA"

echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = 0 ]
