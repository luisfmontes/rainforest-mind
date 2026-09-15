#!/bin/bash
# Teste do ledger local de fluxos por sessão (hooks/lib/ledger-fluxos.cjs),
# carimbado pelos verbos de scripts/estado.cjs (iniciar/exigir/marcar).
# Uso: bash hooks/testa-ledger-fluxos.sh
#
# Duas raízes diferentes entram em jogo, e os testes isolam as duas:
#   RFM_ESTADO_ROOT -> onde mora docs/rainforest/estado/<slug>.json (estado.cjs)
#   RFM_ROOT         -> onde mora fluxos-sessao.json, via resolverRaiz (a MESMA
#                        cadeia que hooks/heartbeat.cjs usa para sessoes.json)
# RFM_ROOT vence a cadeia de resolverRaiz mesmo sem marcador (FOCO.md /
# ideias.jsonl) — ver hooks/lib/raiz.cjs, nível 1 — então basta apontá-lo para
# a sandbox para isolar o ledger por completo, independente do que exista no
# projeto real ou no HOME de quem roda o teste.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESTADO_JS="$SRC/scripts/estado.cjs"

BASE_POSIX="$(mktemp -d)"
trap 'rm -rf "$BASE_POSIX"' EXIT
echo "(caixa de areia: $BASE_POSIX)"

ok=0; falhou=0

# Devolve o caminho no formato que o node no Windows aceita (drive letter),
# igual a testa-heartbeat-poda.sh.
aformato() {
  cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
}

lerCampos() {
  # $1 = caminho do fluxos-sessao.json, $2 = session_id
  node -e '
    const fs = require("fs");
    const l = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const e = l[process.argv[2]];
    const f = (e && e.fluxos) || [];
    console.log(f.length, f[0] && f[0].slug, f[0] && f[0].estagio);
  ' "$1" "$2" 2>&1
}

lerAberto() {
  # $1 = caminho do fluxos-sessao.json, $2 = session_id
  node -e '
    const fs = require("fs");
    const l = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const e = l[process.argv[2]];
    const f = (e && e.fluxos) || [];
    console.log(JSON.stringify(f[0] && f[0].aberto));
  ' "$1" "$2" 2>&1
}

echo
echo "=========================================="
echo "TESTE 1 (reserva): iniciar carimba slug e estagio sob CLAUDE_SESSION_ID"
echo "quando CLAUDE_CODE_SESSION_ID nao esta no ambiente"
echo "=========================================="
T1_POSIX="$BASE_POSIX/t1"; mkdir -p "$T1_POSIX"
T1="$(aformato "$T1_POSIX")"
SESSAO1="11111111-1111-1111-1111-111111111111"

# -u CLAUDE_CODE_SESSION_ID: quem roda este script pode ja ter essa variavel
# de verdade no ambiente (e o Claude Code exporta ela) — sem remove-la aqui
# este caso deixaria de testar a reserva e passaria a testar a leitura
# primaria por acidente.
OUT1=$(RFM_ESTADO_ROOT="$T1" RFM_ROOT="$T1" CLAUDE_SESSION_ID="$SESSAO1" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-carimbo --titulo "t" 2>&1)
EXIT1=$?
echo "$OUT1"
echo "(exit=$EXIT1)"

if [ "$EXIT1" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar saiu 0"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar saiu $EXIT1 (esperado 0)"
fi

LEDGER1="$T1_POSIX/fluxos-sessao.json"
if [ -f "$LEDGER1" ]; then
  RES1=$(lerCampos "$LEDGER1" "$SESSAO1")
  echo "ledger: $RES1"
  if [ "$RES1" = "1 teste-carimbo design" ]; then
    ok=$((ok+1)); echo "  ok    ledger carimbou {slug:teste-carimbo, estagio:design}"
  else
    falhou=$((falhou+1)); echo "  FALHA ledger inesperado: '$RES1' (esperado '1 teste-carimbo design')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json nao foi criado em $LEDGER1"
fi

echo
echo "=========================================="
echo "TESTE 2: sem NENHUMA variavel de sessao, nada e gravado e o verbo ainda sai 0"
echo "=========================================="
T2_POSIX="$BASE_POSIX/t2"; mkdir -p "$T2_POSIX"
T2="$(aformato "$T2_POSIX")"

OUT2=$(RFM_ESTADO_ROOT="$T2" RFM_ROOT="$T2" \
  env -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-sem-sessao --titulo "t" 2>&1)
EXIT2=$?
echo "$OUT2"
echo "(exit=$EXIT2)"

if [ "$EXIT2" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar saiu 0 mesmo sem nenhuma variavel de sessao"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar saiu $EXIT2 (esperado 0)"
fi

LEDGER2="$T2_POSIX/fluxos-sessao.json"
if [ ! -f "$LEDGER2" ]; then
  ok=$((ok+1)); echo "  ok    fluxos-sessao.json nao foi criado (sem sessao, sem gravacao)"
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json foi criado sem variavel de sessao: $(cat "$LEDGER2")"
fi

echo
echo "=========================================="
echo "TESTE 3 (reserva): exigir --estagio plano depois do iniciar atualiza a MESMA entrada"
echo "=========================================="
T3_POSIX="$BASE_POSIX/t3"; mkdir -p "$T3_POSIX"
T3="$(aformato "$T3_POSIX")"
SESSAO3="33333333-3333-3333-3333-333333333333"

RFM_ESTADO_ROOT="$T3" RFM_ROOT="$T3" CLAUDE_SESSION_ID="$SESSAO3" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-atualiza --titulo "t" > /dev/null 2>&1

# Fecha 'design' (pré-requisito de 'plano') para o 'exigir' seguinte passar.
OUT_MARCAR=$(RFM_ESTADO_ROOT="$T3" RFM_ROOT="$T3" CLAUDE_SESSION_ID="$SESSAO3" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" marcar --slug teste-atualiza --estagio design --status aprovado 2>&1)
EXIT_MARCAR=$?

OUT3=$(RFM_ESTADO_ROOT="$T3" RFM_ROOT="$T3" CLAUDE_SESSION_ID="$SESSAO3" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" exigir --slug teste-atualiza --estagio plano 2>&1)
EXIT3=$?
echo "marcar design aprovado: $OUT_MARCAR (exit=$EXIT_MARCAR)"
echo "exigir plano: $OUT3 (exit=$EXIT3)"

if [ "$EXIT_MARCAR" -eq 0 ] && [ "$EXIT3" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    marcar design + exigir plano saem 0 (pre-condicao do caso)"
else
  falhou=$((falhou+1)); echo "  FALHA marcar (exit=$EXIT_MARCAR) ou exigir (exit=$EXIT3) nao saiu 0"
fi

LEDGER3="$T3_POSIX/fluxos-sessao.json"
if [ -f "$LEDGER3" ]; then
  RES3=$(lerCampos "$LEDGER3" "$SESSAO3")
  echo "ledger: $RES3"
  if [ "$RES3" = "1 teste-atualiza plano" ]; then
    ok=$((ok+1)); echo "  ok    exigir atualizou a MESMA entrada (1 item, estagio=plano)"
  else
    falhou=$((falhou+1)); echo "  FALHA ledger inesperado: '$RES3' (esperado '1 teste-atualiza plano')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json nao existe em $LEDGER3"
fi

echo
echo "=========================================="
echo "TESTE 4: entrada de sessao com ts de 25h atras NAO e podada (janela e 30 dias,"
echo "diferente do corte de 24h do heartbeat.cjs — ver comentario no topo do arquivo);"
echo "uma entrada de 31 dias atras e que sai na escrita seguinte"
echo "=========================================="
T4_POSIX="$BASE_POSIX/t4"; mkdir -p "$T4_POSIX"
T4="$(aformato "$T4_POSIX")"

AGORA_MS=$(date +%s000)
QUASE_UM_DIA_MS=$(( $(date +%s) * 1000 - 25 * 3600 * 1000 ))
TRINTA_UM_DIAS_MS=$(( $(date +%s) * 1000 - 31 * 24 * 3600 * 1000 ))

cat > "$T4_POSIX/fluxos-sessao.json" << EOF
{
  "sessao-31-dias":  { "ts": $TRINTA_UM_DIAS_MS, "fluxos": [ { "slug": "antigo", "estagio": "design", "ts": $TRINTA_UM_DIAS_MS } ] },
  "sessao-25h":      { "ts": $QUASE_UM_DIA_MS, "fluxos": [ { "slug": "vivo",   "estagio": "design", "ts": $QUASE_UM_DIA_MS } ] },
  "sessao-recente":  { "ts": $AGORA_MS, "fluxos": [ { "slug": "novo",   "estagio": "design", "ts": $AGORA_MS } ] }
}
EOF

echo "ANTES:"
cat "$T4_POSIX/fluxos-sessao.json"

OUT4=$(RFM_ESTADO_ROOT="$T4" RFM_ROOT="$T4" CLAUDE_SESSION_ID="sessao-gatilho" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-poda --titulo "t" 2>&1)
EXIT4=$?
echo "iniciar (gatilho da poda): exit=$EXIT4"

RESULTADO4="$(cat "$T4_POSIX/fluxos-sessao.json")"
echo "DEPOIS:"
echo "$RESULTADO4"

if [ "$EXIT4" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar (gatilho) saiu 0"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar (gatilho) saiu $EXIT4"
fi

if ! echo "$RESULTADO4" | grep -q '"sessao-31-dias"'; then
  ok=$((ok+1)); echo "  ok    sessao-31-dias (fora da janela de 30 dias) foi podada"
else
  falhou=$((falhou+1)); echo "  FALHA sessao-31-dias sobreviveu a poda"
fi

if echo "$RESULTADO4" | grep -q '"sessao-25h"'; then
  ok=$((ok+1)); echo "  ok    sessao-25h sobreviveu (dentro da janela de 30 dias, diferente do heartbeat.cjs)"
else
  falhou=$((falhou+1)); echo "  FALHA sessao-25h foi podada — a janela de 30 dias nao esta valendo"
fi

if echo "$RESULTADO4" | grep -q '"sessao-recente"'; then
  ok=$((ok+1)); echo "  ok    sessao-recente sobreviveu a poda"
else
  falhou=$((falhou+1)); echo "  FALHA sessao-recente foi podada por engano"
fi

if echo "$RESULTADO4" | grep -q '"sessao-gatilho"'; then
  ok=$((ok+1)); echo "  ok    sessao-gatilho foi gravada"
else
  falhou=$((falhou+1)); echo "  FALHA sessao-gatilho nao foi gravada"
fi

echo
echo "=========================================="
echo "TESTE 4B: teto de 500 entradas — com 501 sessoes no ledger, a escrita seguinte"
echo "poda pelo TS mais antigo ate caber em 500, independente da janela de 30 dias"
echo "=========================================="
T4B_POSIX="$BASE_POSIX/t4b"; mkdir -p "$T4B_POSIX"
T4B="$(aformato "$T4B_POSIX")"

node -e '
  const fs = require("fs");
  const agora = Date.now();
  const ledger = {};
  // 501 sessoes, todas dentro da janela de 30 dias (ts decrescente: sessao-000
  // e a mais recente, sessao-500 a mais antiga), so para isolar o teto de
  // contagem da poda por idade.
  for (let i = 0; i <= 500; i++) {
    const id = "sessao-" + String(i).padStart(3, "0");
    ledger[id] = { ts: agora - i * 1000, fluxos: [ { slug: "s" + i, estagio: "design", ts: agora - i * 1000 } ] };
  }
  fs.writeFileSync(process.argv[1], JSON.stringify(ledger));
' "$T4B_POSIX/fluxos-sessao.json"

CONTAGEM_ANTES=$(node -e 'console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))).length)' "$T4B_POSIX/fluxos-sessao.json")
echo "contagem ANTES: $CONTAGEM_ANTES"

OUT4B=$(RFM_ESTADO_ROOT="$T4B" RFM_ROOT="$T4B" CLAUDE_SESSION_ID="sessao-gatilho-teto" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-teto --titulo "t" 2>&1)
EXIT4B=$?
echo "iniciar (gatilho do teto): exit=$EXIT4B"

CONTAGEM_DEPOIS=$(node -e 'console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))).length)' "$T4B_POSIX/fluxos-sessao.json")
echo "contagem DEPOIS: $CONTAGEM_DEPOIS"

if [ "$EXIT4B" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar (gatilho do teto) saiu 0"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar (gatilho do teto) saiu $EXIT4B"
fi

# 501 pre-existentes + 1 nova (sessao-gatilho-teto) = 502 antes do teto: tem
# que cair para exatamente 500 apos a poda por contagem.
if [ "$CONTAGEM_DEPOIS" = "500" ]; then
  ok=$((ok+1)); echo "  ok    teto de 500 entradas aplicado (502 -> 500)"
else
  falhou=$((falhou+1)); echo "  FALHA contagem depois foi '$CONTAGEM_DEPOIS' (esperado 500)"
fi

TEM_GATILHO=$(node -e '
  const l = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  console.log(Object.prototype.hasOwnProperty.call(l, "sessao-gatilho-teto") ? "sim" : "nao");
' "$T4B_POSIX/fluxos-sessao.json")
if [ "$TEM_GATILHO" = "sim" ]; then
  ok=$((ok+1)); echo "  ok    a sessao que acabou de carimbar (mais recente) sobreviveu ao teto"
else
  falhou=$((falhou+1)); echo "  FALHA a sessao que acabou de carimbar foi descartada pelo teto"
fi

TEM_MAIS_ANTIGA=$(node -e '
  const l = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  console.log(Object.prototype.hasOwnProperty.call(l, "sessao-500") ? "sim" : "nao");
' "$T4B_POSIX/fluxos-sessao.json")
if [ "$TEM_MAIS_ANTIGA" = "nao" ]; then
  ok=$((ok+1)); echo "  ok    a entrada mais antiga (sessao-500) foi descartada pelo teto"
else
  falhou=$((falhou+1)); echo "  FALHA sessao-500 (mais antiga) sobreviveu ao teto de 500"
fi

echo
echo "=========================================="
echo "TESTE 5 (reserva): ledger com JSON corrompido nao derruba o verbo"
echo "=========================================="
T5_POSIX="$BASE_POSIX/t5"; mkdir -p "$T5_POSIX"
T5="$(aformato "$T5_POSIX")"

printf '{ isso nao e json valido' > "$T5_POSIX/fluxos-sessao.json"
echo "ANTES (corrompido): $(cat "$T5_POSIX/fluxos-sessao.json")"

OUT5=$(RFM_ESTADO_ROOT="$T5" RFM_ROOT="$T5" CLAUDE_SESSION_ID="sessao-corrompida" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-corrompido --titulo "t" 2>&1)
EXIT5=$?
echo "$OUT5"
echo "(exit=$EXIT5)"

if [ "$EXIT5" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar sai 0 mesmo com ledger corrompido"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar saiu $EXIT5 (esperado 0) com ledger corrompido"
fi

LEDGER5="$T5_POSIX/fluxos-sessao.json"
RES5=$(lerCampos "$LEDGER5" "sessao-corrompida" 2>&1)
echo "ledger apos recuperacao: $RES5"
if [ "$RES5" = "1 teste-corrompido design" ]; then
  ok=$((ok+1)); echo "  ok    ledger se recuperou do JSON corrompido e carimbou a sessao atual"
else
  falhou=$((falhou+1)); echo "  FALHA ledger nao se recuperou: '$RES5'"
fi

echo
echo "=========================================="
echo "TESTE 6 (reserva): campo 'aberto' distingue fluxo aberto de fluxo completo (Parte A)"
echo "=========================================="
T6_POSIX="$BASE_POSIX/t6"; mkdir -p "$T6_POSIX"
T6="$(aformato "$T6_POSIX")"
SESSAO6="66666666-6666-6666-6666-666666666666"
E6="RFM_ESTADO_ROOT=$T6 RFM_ROOT=$T6 CLAUDE_SESSION_ID=$SESSAO6"

# Percorre o fluxo inteiro ate 'exigir --estagio fechar' (fluxo ainda ABERTO
# nele mesmo), depois fecha com 'marcar --estagio fechar --status ok' (fluxo
# COMPLETO) — mesma sequencia de scripts/testa-estado.sh, secao 2.
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-aberto --titulo "t" > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" marcar --slug teste-aberto --estagio design --status aprovado > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" marcar --slug teste-aberto --estagio plano --status ok > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" exigir --slug teste-aberto --estagio executar > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" marcar --slug teste-aberto --estagio executar --status ok \
  --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso-teste-1"}]}' > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" marcar --slug teste-aberto --estagio revisar --status ok > /dev/null 2>&1
RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" marcar --slug teste-aberto --estagio verificar --status ok \
  --json '{"comando":"bash test.sh","saida":"3 cases passed"}' > /dev/null 2>&1

OUT6A=$(RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" exigir --slug teste-aberto --estagio fechar 2>&1)
EXIT6A=$?
echo "exigir fechar: $OUT6A (exit=$EXIT6A)"

LEDGER6="$T6_POSIX/fluxos-sessao.json"
if [ "$EXIT6A" -eq 0 ] && [ -f "$LEDGER6" ]; then
  ABERTO6A=$(lerAberto "$LEDGER6" "$SESSAO6")
  echo "ledger apos 'exigir fechar': aberto=$ABERTO6A"
  if [ "$ABERTO6A" = '"fechar"' ]; then
    ok=$((ok+1)); echo "  ok    exigir --estagio fechar grava aberto: \"fechar\" (fluxo ainda aberto)"
  else
    falhou=$((falhou+1)); echo "  FALHA aberto inesperado apos exigir: '$ABERTO6A' (esperado '\"fechar\"')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA exigir --estagio fechar nao saiu 0 ou ledger ausente"
fi

OUT6B=$(RFM_ESTADO_ROOT="$T6" RFM_ROOT="$T6" CLAUDE_SESSION_ID="$SESSAO6" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" marcar --slug teste-aberto --estagio fechar --status ok 2>&1)
EXIT6B=$?
echo "marcar fechar ok: $OUT6B (exit=$EXIT6B)"

if [ "$EXIT6B" -eq 0 ] && [ -f "$LEDGER6" ]; then
  ABERTO6B=$(lerAberto "$LEDGER6" "$SESSAO6")
  echo "ledger apos 'marcar fechar ok': aberto=$ABERTO6B"
  if [ "$ABERTO6B" = 'null' ]; then
    ok=$((ok+1)); echo "  ok    marcar --estagio fechar --status ok grava aberto: null (fluxo completo)"
  else
    falhou=$((falhou+1)); echo "  FALHA aberto inesperado apos marcar ok: '$ABERTO6B' (esperado 'null')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA marcar --estagio fechar --status ok nao saiu 0 ou ledger ausente"
fi

echo
echo "=========================================="
echo "TESTE 7: carimba com o nome REAL da variavel, sem injetar CLAUDE_SESSION_ID"
echo "=========================================="
T7_POSIX="$BASE_POSIX/t7"; mkdir -p "$T7_POSIX"
T7="$(aformato "$T7_POSIX")"
SESSAO7="77777777-7777-7777-7777-777777777777"

# env -u CLAUDE_SESSION_ID: garante que a variavel antiga NAO esta no
# ambiente. So CLAUDE_CODE_SESSION_ID (o nome que o Claude Code realmente
# exporta, medido em 2026-09-15) fica setada.
OUT7=$(RFM_ESTADO_ROOT="$T7" RFM_ROOT="$T7" CLAUDE_CODE_SESSION_ID="$SESSAO7" \
  env -u CLAUDE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-var-real --titulo "t" 2>&1)
EXIT7=$?
echo "$OUT7"
echo "(exit=$EXIT7)"

if [ "$EXIT7" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar saiu 0 com apenas CLAUDE_CODE_SESSION_ID no ambiente"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar saiu $EXIT7 (esperado 0)"
fi

LEDGER7="$T7_POSIX/fluxos-sessao.json"
if [ -f "$LEDGER7" ]; then
  RES7=$(lerCampos "$LEDGER7" "$SESSAO7")
  echo "ledger: $RES7"
  if [ "$RES7" = "1 teste-var-real design" ]; then
    ok=$((ok+1)); echo "  ok    ledger nasceu com a chave de CLAUDE_CODE_SESSION_ID, sem CLAUDE_SESSION_ID no ambiente"
  else
    falhou=$((falhou+1)); echo "  FALHA ledger inesperado: '$RES7' (esperado '1 teste-var-real design')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json nao foi criado em $LEDGER7"
fi

echo
echo "=========================================="
echo "TESTE 8: precedencia — as duas variaveis setadas com valores DIFERENTES,"
echo "o carimbo usa o valor de CLAUDE_CODE_SESSION_ID"
echo "=========================================="
T8_POSIX="$BASE_POSIX/t8"; mkdir -p "$T8_POSIX"
T8="$(aformato "$T8_POSIX")"
SESSAO8_CODE="88888888-8888-8888-8888-888888888888"
SESSAO8_LEGADA="99999999-9999-9999-9999-999999999999"

OUT8=$(RFM_ESTADO_ROOT="$T8" RFM_ROOT="$T8" \
  CLAUDE_CODE_SESSION_ID="$SESSAO8_CODE" CLAUDE_SESSION_ID="$SESSAO8_LEGADA" \
  node "$ESTADO_JS" iniciar --slug teste-precedencia --titulo "t" 2>&1)
EXIT8=$?
echo "$OUT8"
echo "(exit=$EXIT8)"

if [ "$EXIT8" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar saiu 0 com as duas variaveis setadas"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar saiu $EXIT8 (esperado 0)"
fi

LEDGER8="$T8_POSIX/fluxos-sessao.json"
if [ -f "$LEDGER8" ]; then
  RES8_CODE=$(lerCampos "$LEDGER8" "$SESSAO8_CODE")
  RES8_LEGADA=$(lerCampos "$LEDGER8" "$SESSAO8_LEGADA")
  echo "ledger sob CLAUDE_CODE_SESSION_ID ($SESSAO8_CODE): $RES8_CODE"
  echo "ledger sob CLAUDE_SESSION_ID ($SESSAO8_LEGADA): $RES8_LEGADA"
  if [ "$RES8_CODE" = "1 teste-precedencia design" ] && [ "$RES8_LEGADA" = "0 undefined undefined" ]; then
    ok=$((ok+1)); echo "  ok    carimbo usou CLAUDE_CODE_SESSION_ID, nao CLAUDE_SESSION_ID"
  else
    falhou=$((falhou+1)); echo "  FALHA precedencia errada: code='$RES8_CODE' legada='$RES8_LEGADA'"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json nao foi criado em $LEDGER8"
fi

echo
echo "=========================================="
echo "TESTE 9: lock orfao (arquivo .lock pre-existente e velho) e tratado como"
echo "abandonado — o verbo ainda sai 0 e o carimbo acontece"
echo "=========================================="
T9_POSIX="$BASE_POSIX/t9"; mkdir -p "$T9_POSIX"
T9="$(aformato "$T9_POSIX")"
SESSAO9="sessao-lock-orfao"

LOCK9="$T9_POSIX/fluxos-sessao.json.lock"
: > "$LOCK9"
# Lock "velho": mtime bem alem do teto de orfandade (5s) do ledger-fluxos.cjs.
touch -d '1 hour ago' "$LOCK9" 2>/dev/null || touch -A -010000 "$LOCK9" 2>/dev/null
echo "lock pre-existente criado, mtime: $(node -e 'console.log(require("fs").statSync(process.argv[1]).mtimeMs)' "$LOCK9")"

OUT9=$(RFM_ESTADO_ROOT="$T9" RFM_ROOT="$T9" CLAUDE_SESSION_ID="$SESSAO9" \
  env -u CLAUDE_CODE_SESSION_ID node "$ESTADO_JS" iniciar --slug teste-lock-orfao --titulo "t" 2>&1)
EXIT9=$?
echo "$OUT9"
echo "(exit=$EXIT9)"

if [ "$EXIT9" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    iniciar saiu 0 com lock orfao pre-existente"
else
  falhou=$((falhou+1)); echo "  FALHA iniciar saiu $EXIT9 (esperado 0) com lock orfao pre-existente"
fi

LEDGER9="$T9_POSIX/fluxos-sessao.json"
if [ -f "$LEDGER9" ]; then
  RES9=$(lerCampos "$LEDGER9" "$SESSAO9")
  echo "ledger: $RES9"
  if [ "$RES9" = "1 teste-lock-orfao design" ]; then
    ok=$((ok+1)); echo "  ok    carimbo aconteceu apesar do lock orfao (lock foi destravado)"
  else
    falhou=$((falhou+1)); echo "  FALHA ledger inesperado: '$RES9' (esperado '1 teste-lock-orfao design')"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json nao foi criado em $LEDGER9 (lock ficou preso)"
fi

echo
echo "=========================================="
echo "TESTE 10: corrida — muitos processos 'iniciar' quase simultaneos contra o"
echo "mesmo RFM_ROOT/RFM_ESTADO_ROOT, cada um com sessao e slug diferentes; todas"
echo "as chaves tem que sobreviver (achado 1 da revisao de 2026-09-15: sem lock,"
echo "9 de 80 sobreviviam a 80 processos concorrentes)"
echo "=========================================="
T10_POSIX="$BASE_POSIX/t10"; mkdir -p "$T10_POSIX"
T10="$(aformato "$T10_POSIX")"
N=80

pids=""
i=1
while [ "$i" -le "$N" ]; do
  SID=$(printf 'corrida-sessao-%03d' "$i")
  # CLAUDE_CODE_SESSION_ID precisa ser setado AQUI, nao so o CLAUDE_SESSION_ID
  # legado: quem roda este script (Claude Code) ja tem a variavel real
  # exportada no ambiente, e ela vence na leitura de ledger-fluxos.cjs — sem
  # sobrescreve-la, os 80 processos herdam o MESMO id real e contendem por UMA
  # so entrada (medido: "chaves" caia para 1, nao pela corrida, mas porque so
  # havia uma chave possivel).
  ( RFM_ESTADO_ROOT="$T10" RFM_ROOT="$T10" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_SESSION_ID="$SID" \
    node "$ESTADO_JS" iniciar --slug "$SID" --titulo "t" > /dev/null 2>&1 ) &
  pids="$pids $!"
  i=$((i+1))
done
for p in $pids; do wait "$p"; done

LEDGER10="$T10_POSIX/fluxos-sessao.json"
if [ -f "$LEDGER10" ]; then
  CONTAGEM10=$(node -e "const l=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(Object.keys(l).length)" "$LEDGER10")
  echo "chaves no ledger apos $N processos concorrentes: $CONTAGEM10"
  if [ "$CONTAGEM10" = "$N" ]; then
    ok=$((ok+1)); echo "  ok    todas as $N chaves sobreviveram a corrida (lock + escrita atomica funcionando)"
  else
    PERDIDAS=$((N - CONTAGEM10))
    falhou=$((falhou+1)); echo "  FALHA so $CONTAGEM10 de $N chaves sobreviveram — perdeu $PERDIDAS"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA fluxos-sessao.json nao foi criado em $LEDGER10"
fi

echo
echo "=========================================="
echo "Resumo: $ok ok, $falhou falhas"
echo "=========================================="
[ $falhou -eq 0 ]
