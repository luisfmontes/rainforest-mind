#!/bin/bash
# Bateria da chamada ao claude no run-vigia.ps1.
#
# Nasceu de 2026-09-02 -> 2026-09-28: o claudeExe do vigia.config.json apontava
# para um claude.exe que o WinGet tinha removido. O `& $claude` falhava fora do
# 2>&1, o backup rodava depois, e a tarefa agendada saia com 0 — 26 dias de
# rondas sem mensagem e sem uma linha no ERROS.md.
#
# Os quatro casos rodam o run-vigia.ps1 por EXECUCAO, numa caixa de areia, com
# um `claude` falso (.cmd) e uma porta TCP aberta por node fazendo o papel da
# bridge do WhatsApp — sem ela o script para antes, no Stop-ComErro da bridge, e
# a bateria ficaria verde sem nunca chegar na chamada que ela existe para provar.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
PID_PORTA=""
trap '[ -n "$PID_PORTA" ] && kill "$PID_PORTA" 2>/dev/null; rm -rf "$SB"' EXIT

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }
tem()   { if grep -qF -- "$2" "$3" 2>/dev/null; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (nao achei '$2' em $(basename "$3"))"; fi; }
naotem(){ if grep -qF -- "$2" "$3" 2>/dev/null; then falhou=$((falhou+1)); echo "  FALHA $1 (achei '$2' em $(basename "$3"))"; else ok=$((ok+1)); echo "  ok    $1"; fi; }

command -v powershell >/dev/null 2>&1 || { echo "FALHA powershell nao esta no PATH — esta bateria nao significaria nada"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FALHA node nao esta no PATH — o toggle e a porta falsa dependem dele"; exit 1; }
win() { cygpath -w "$1"; }

# Porta falsa da bridge: o node abre e escreve o numero num arquivo.
node -e '
const s=require("net").createServer(c=>c.end());
s.listen(0,"127.0.0.1",()=>{require("fs").writeFileSync(process.argv[1],String(s.address().port));});
' "$SB/porta" &
PID_PORTA=$!
for _ in $(seq 1 50); do [ -s "$SB/porta" ] && break; sleep 0.1; done
[ -s "$SB/porta" ] || { echo "FALHA a porta falsa da bridge nao abriu"; exit 1; }
PORTA=$(cat "$SB/porta")

montar() {
  rm -rf "$SB/plugin" "$SB/dados" "$SB/bin"
  mkdir -p "$SB/plugin/vigias" "$SB/plugin/hooks/lib" "$SB/plugin/scripts" "$SB/dados/vigias" "$SB/bin"
  cp "$SRC/vigias/run-vigia.ps1" "$SRC/vigias/erros.ps1" "$SRC/vigias/backup-estado.ps1" "$SB/plugin/vigias/"
  cp -r "$SRC/scripts/." "$SB/plugin/scripts/"
  cp -r "$SRC/hooks/." "$SB/plugin/hooks/"
  printf '{"vigias": true}\n' > "$SB/dados/config.json"
  : > "$SB/plugin/vigias/ERROS.md"
  printf 'prompt de caixa\n' > "$SB/dados/vigias/sentinela-foco.md"
  # Os tres claudes falsos. O do PATH e o que a descoberta acha quando o
  # caminho configurado nao existe.
  printf '@echo resposta-do-path\r\n@exit /b 0\r\n' > "$SB/bin/claude.cmd"
  printf '@exit /b 0\r\n'                          > "$SB/mudo.cmd"
  printf '@echo meia-resposta\r\n@exit /b 3\r\n'    > "$SB/quebra.cmd"
  printf '@echo resposta-boa\r\n@exit /b 0\r\n'     > "$SB/bom.cmd"
}

# $1 = valor de RFM_CLAUDE_EXE. Devolve o exit code do run-vigia.ps1.
rodar() {
  PATH="$SB/bin:$PATH" RFM_ROOT="$(win "$SB/dados")" RFM_CLAUDE_EXE="$1" \
  RFM_WHATSAPP_DESTINO="0@g.us" WHATSAPP_API_BASE_URL="http://127.0.0.1:$PORTA" \
    powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$(win "$SB/plugin/vigias/run-vigia.ps1")" -Vigia sentinela-foco -Teste \
    > "$SB/saida.txt" 2>&1
  echo $?
}
LOG="$SB/dados/vigias/log-sentinela-foco.txt"
ERR="$SB/plugin/vigias/ERROS.md"

echo "== 1. claudeExe configurado que nao existe: registra e cai no claude do PATH =="
montar
igual "exit da ronda" "$(rodar "$(win "$SB/sumiu/claude.exe")")" "0"
tem   "ERROS.md nomeia o caminho velho" "claudeExe configurado nao existe" "$ERR"
tem   "a ronda rodou com o claude do PATH" "resposta-do-path" "$LOG"

echo "== 2. claude que nao devolve nada: erro e exit 1 =="
montar
igual "exit da ronda" "$(rodar "$(win "$SB/mudo.cmd")")" "1"
tem   "ERROS.md registra a saida vazia" "nao devolveu nenhuma linha" "$ERR"

echo "== 3. claude que sai com exit 3: erro e exit 1, saida parcial preservada =="
montar
igual "exit da ronda" "$(rodar "$(win "$SB/quebra.cmd")")" "1"
tem   "ERROS.md registra o exit" "exit 3" "$ERR"
tem   "a saida parcial chegou ao log" "meia-resposta" "$LOG"

echo "== 4. claude saudavel: nenhuma linha de erro do claude =="
montar
igual "exit da ronda" "$(rodar "$(win "$SB/bom.cmd")")" "0"
tem    "a resposta chegou ao log" "resposta-boa" "$LOG"
naotem "ERROS.md sem erro de claude" "claude" "$ERR"

echo
echo "$ok ok, $falhou falha(s)"
[ "$falhou" -eq 0 ] || { echo "-- ultima saida do run-vigia.ps1:"; sed 's/^/   /' "$SB/saida.txt" | tail -15; }
[ "$falhou" -eq 0 ]
