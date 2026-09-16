#!/bin/bash
# Teste do REGISTRO do hook titulo-sessao-end.cjs em hooks/hooks.json.
# Uso: bash hooks/testa-titulo-sessao-registro.sh
#
# O ponto da tarefa: titulo-sessao-end.cjs precisa ser esperado antes da
# sessao fechar (por isso e SINCRONO, sem "async": true) e precisa morar num
# grupo separado do heartbeat.cjs (donos diferentes: heartbeat apaga a
# entrada da sessao em sessoes.json e grava sem lock). Este teste le o
# hooks/hooks.json REAL do repositorio, nao uma copia de fixture: o ponto e
# conferir o arquivo que o Claude Code carrega.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_JSON="$SRC/hooks/hooks.json"

ok=0; falhou=0

echo
echo "=========================================="
echo "TESTE 1: entrada de titulo-sessao-end e sincrona"
echo "=========================================="
RES1=$(node -e '
  const h = require(process.argv[1]).hooks.SessionEnd;
  const e = h.flatMap(g => g.hooks).filter(x => x.command.includes("titulo-sessao-end"));
  console.log(e.length, e[0] && e[0].async === undefined);
' "$HOOKS_JSON")
echo "resultado: $RES1"
if [ "$RES1" = "1 true" ]; then
  ok=$((ok+1)); echo "  ok    uma entrada de titulo-sessao-end, sem async"
else
  falhou=$((falhou+1)); echo "  FALHA esperava '1 true', veio '$RES1'"
fi

echo
echo "=========================================="
echo "TESTE 2: titulo-sessao-end esta em grupo diferente do heartbeat.cjs"
echo "=========================================="
RES2=$(node -e '
  const h = require(process.argv[1]).hooks.SessionEnd;
  const grupoDe = (agulha) => h.findIndex(g => g.hooks.some(x => x.command.includes(agulha)));
  const gTitulo = grupoDe("titulo-sessao-end");
  const gHeartbeat = grupoDe("heartbeat.cjs");
  console.log(gTitulo, gHeartbeat, gTitulo !== gHeartbeat && gTitulo !== -1 && gHeartbeat !== -1);
' "$HOOKS_JSON")
echo "resultado (indice titulo, indice heartbeat, sao diferentes?): $RES2"
if echo "$RES2" | grep -qE ' true$'; then
  ok=$((ok+1)); echo "  ok    titulo-sessao-end esta num grupo separado do heartbeat.cjs"
else
  falhou=$((falhou+1)); echo "  FALHA titulo-sessao-end e heartbeat.cjs estao no mesmo grupo (ou um nao foi encontrado)"
fi

echo
echo "=========================================="
echo "TESTE 3: hooks.json e JSON valido e nao perdeu hooks de outros eventos"
echo "=========================================="
RES3=$(node -e '
  const h = require(process.argv[1]).hooks;
  const contar = (evt) => (h[evt] || []).flatMap(g => g.hooks).length;
  console.log(JSON.stringify({
    SessionStart: contar("SessionStart"),
    PreToolUse: contar("PreToolUse"),
    Stop: contar("Stop"),
    UserPromptSubmit: contar("UserPromptSubmit"),
  }));
' "$HOOKS_JSON" 2>&1)
echo "contagem: $RES3"
if [ "$RES3" = '{"SessionStart":5,"PreToolUse":10,"Stop":4,"UserPromptSubmit":1}' ]; then
  ok=$((ok+1)); echo "  ok    JSON valido e contagem de SessionStart/PreToolUse/Stop/UserPromptSubmit preservada"
else
  falhou=$((falhou+1)); echo "  FALHA contagem mudou (ou JSON invalido): $RES3"
fi

echo
echo "=========================================="
echo "Resumo: $ok ok, $falhou falhas"
echo "=========================================="
[ $falhou -eq 0 ]
