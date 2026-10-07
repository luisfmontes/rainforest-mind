#!/bin/bash
# Teste: o heartbeat grava o PID da sessão lido de <config dir>/sessions/<pid>.json,
# e o relógio do mod (scripts/relogio-sessoes.cjs) deixa de mostrar janela cujo
# processo morreu. Incidente 2026-10-07: janela do Canassa fechada no X aparecia
# "parada há 3h31" no relógio da outra conta.
# Uso: bash hooks/testa-heartbeat-pid.sh
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA_POSIX="$(mktemp -d)"
CAIXA="$(cygpath -m "$CAIXA_POSIX" 2>/dev/null || printf '%s' "$CAIXA_POSIX")"
trap 'rm -rf "$CAIXA_POSIX"' EXIT
RAIZ="$CAIXA/raiz"; CFG="$CAIXA/cfg"
mkdir -p "$CAIXA_POSIX/raiz" "$CAIXA_POSIX/cfg/sessions"
echo '{}' > "$CAIXA_POSIX/raiz/sessoes.json"
ok=0; falhou=0
checa() { if [ "$2" = "$3" ]; then echo "ok   $1"; ok=$((ok+1)); else echo "FALHA $1: esperado [$3], veio [$2]"; falhou=$((falhou+1)); fi; }

MORTO=$(node -e 'const c=require("child_process");console.log(c.spawnSync(process.execPath,["-e",""]).pid)')
# processo vivo durante o teste: um node em segundo plano que grava o proprio pid
node -e "require('fs').writeFileSync(process.argv[1],String(process.pid));setTimeout(()=>{},30000)" "$CAIXA/vivo.pid" &
SONO=$!
trap 'kill $SONO 2>/dev/null; rm -rf "$CAIXA_POSIX"' EXIT
for _ in $(seq 50); do [ -s "$CAIXA_POSIX/vivo.pid" ] && break; node -e "setTimeout(()=>{},100)"; done
VIVO=$(cat "$CAIXA_POSIX/vivo.pid")
# a sessao 'morta' tem registro com pid morto; a 'viva' aponta para este shell
printf '{"pid":%s,"sessionId":"morta"}' "$MORTO" > "$CAIXA_POSIX/cfg/sessions/$MORTO.json"
printf '{"pid":%s,"sessionId":"viva"}' "$VIVO" > "$CAIXA_POSIX/cfg/sessions/$VIVO.json"

hb() { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$2" | RFM_ROOT="$RAIZ" CLAUDE_CONFIG_DIR="$CFG" node "$SRC/hooks/heartbeat.cjs" "$3"; }
hb morta 'C:/x/Canassa' prompt; hb morta 'C:/x/Canassa' stop
hb viva 'C:/x/outra' prompt; hb viva 'C:/x/outra' stop
hb semregistro 'C:/x/codex' prompt; hb semregistro 'C:/x/codex' stop

campo() { node -e "const s=require('$RAIZ/sessoes.json');console.log(String((s['$1']||{}).pid))"; }
checa "pid da sessao morta gravado" "$(campo morta)" "$MORTO"
checa "pid da sessao viva gravado" "$(campo viva)" "$VIVO"
checa "sem registro fica sem pid" "$(campo semregistro)" "undefined"

# relogio: com ociosidade 0, so as janelas vivas (viva, semregistro) aparecem
node -e "const f='$RAIZ/sessoes.json',s=require(f);for(const k in s){s[k].stop_ts-=3600e3;s[k].prompt_ts-=3600e3;}require('fs').writeFileSync(f,JSON.stringify(s))"
SAIDA=$(RFM_ROOT="$RAIZ" node "$SRC/scripts/relogio-sessoes.cjs" --cwd "$CAIXA" --sessao eu); EXIT=$?
checa "relogio-sessoes exit" "$EXIT" "0"
PASTAS=$(printf '%s' "$SAIDA" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).janelas.map(j=>j.cwd.split(/[\\/]/).pop()).sort().join(',')))")
checa "relogio nao mostra janela de processo morto" "$PASTAS" "codex,outra"

echo "placar: $ok ok, $falhou falha(s)"
[ "$falhou" -eq 0 ]
