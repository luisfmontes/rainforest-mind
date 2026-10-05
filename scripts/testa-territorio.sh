#!/bin/bash
# Bateria do scripts/territorio.cjs — descoberta do territorio e bloco do estagio.
# Uso: bash scripts/testa-territorio.sh
#
# Monta um CLAUDE_CONFIG_DIR temporario cujo installed_plugins.json aponta para uma
# copia do territorio sintetico (inventado; extensao .abc). Zero casos pulados.
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$SRC/test/fixtures/territorio"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

total=0
vermelhas=""
caso() { # nome, 0=ok
  total=$((total + 1))
  if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FALHA $1"; vermelhas="$vermelhas\"$1\","; fi
}

monta_config() { # dir-config dir-plugin
  mkdir -p "$1/plugins"
  # No Git Bash o caminho de mktemp e estilo MSYS; o node (e o JSON) precisam do nativo.
  local p="$2"; command -v cygpath >/dev/null 2>&1 && p="$(cygpath -m "$2")"
  printf '{"version":2,"plugins":{"sintetico@teste":[{"scope":"user","installPath":"%s"}]}}' "$p" > "$1/plugins/installed_plugins.json"
}

PLUG="$TMP/plugin"; cp -r "$FIX/sintetico" "$PLUG"
CFG="$TMP/cfg"; monta_config "$CFG" "$PLUG"
T() { CLAUDE_CONFIG_DIR="$CFG" node "$SRC/scripts/territorio.cjs" "$@"; }

out=$(T estagio revisar --raiz "$FIX/repo-abc" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qx 'modo: soma' && echo "$out" | grep -qx 'agente: sintetico:revisor obrigatorio=false mcp=orquestrador'
caso "estagio revisar em repo-abc mostra modo soma e o agente" $?

out=$(T estagio revisar --raiz "$FIX/repo-vazio" 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = "sem territorio" ]
caso "repo-vazio imprime sem territorio e sai 0" $?

R3="$TMP/repo-apontado"; mkdir -p "$R3/.rainforest"; echo "x" > "$R3/LEIAME.txt"; echo "sintetico" > "$R3/.rainforest/territorio"
out=$(T estagio revisar --raiz "$R3" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qx 'territorio: sintetico'
caso "apontamento do repo vence a deteccao" $?

R4="$TMP/repo-inexistente"; mkdir -p "$R4/.rainforest"; echo "fantasma" > "$R4/.rainforest/territorio"
out=$(T estagio revisar --raiz "$R4" 2>&1); rc=$?
[ $rc = 2 ] && echo "$out" | grep -q 'fantasma'
caso "apontamento para nome inexistente sai 2 nomeando" $?

PLUG5="$TMP/plugin5"; cp -r "$FIX/sintetico" "$PLUG5"
sed -i 's/"versao_contrato": 0/"versao_contrato": 1/' "$PLUG5/territorio.json"
CFG5="$TMP/cfg5"; monta_config "$CFG5" "$PLUG5"
out=$(CLAUDE_CONFIG_DIR="$CFG5" node "$SRC/scripts/territorio.cjs" estagio revisar --raiz "$FIX/repo-abc" 2>&1); rc=$?
[ $rc = 2 ] && echo "$out" | grep -q 'sintetico'
caso "versao_contrato diferente de 0 sai 2" $?

out=$(T estagio brainstorm --raiz "$FIX/repo-abc" 2>&1); rc=$?
[ $rc = 0 ] && echo "$out" | grep -qx 'mcp: mcp__srv__consulta quem=orquestrador obrigatorio=false'
caso "mcp sem campo quem sai como quem=orquestrador" $?

echo "total=$total vermelhas:[${vermelhas%,}]"
[ -z "$vermelhas" ]
