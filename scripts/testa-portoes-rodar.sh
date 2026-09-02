#!/bin/bash
# Bateria do modo `rodar` de `scripts/portoes.cjs`.
# Uso: bash scripts/testa-portoes-rodar.sh
#
# Tarefa 3 do plano `docs/rainforest/planos/2026-09-02-fluxo-6-portoes.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR, em ordem de gravidade:
#
#   1. Que "cumprido" caia para "exit 0". O design exige exit 0 E match do
#      marcador, os dois. So exit 0 aceita script que morre feliz sem ter medido
#      nada — que e' exatamente o defeito que os portoes existem para fechar, e
#      por isso R6 tem fixture proprio (exit-zero-sem-marcador).
#
#   2. Que abandono vire conclusao. `ABANDONA:` tem de forcar exit 1 com
#      DEVOLUCAO OBRIGATORIA MESMO com todos os outros portoes cumpridos. Se um
#      exit 0 escapasse por ali, a desistencia ficaria enterrada e o fluxo
#      seguiria como completo — caso R8.
#
#   3. Que o output bruto vaze para o arquivo versionado. A evidencia guarda
#      fingerprint; saida de sucesso carrega caminho de maquina e as vezes nome
#      de cliente. Caso R11.
#
# Os fixtures rodam sempre sobre uma COPIA no temp, nunca sobre o versionado: o
# `rodar` ESCREVE no arquivo, e uma bateria que muta seu proprio fixture passa
# na primeira execucao e mente na segunda.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$RAIZ/scripts/portoes.cjs"
FIX="$RAIZ/test/fixtures/portoes"
FIXN="$(cygpath -m "$FIX" 2>/dev/null || printf '%s' "$FIX")"

for f in "$P" "$FIX/portoes-ok.md" "$FIX/portoes-falha.md" \
         "$FIX/portoes-exit-zero-sem-marcador.md" "$FIX/portoes-crlf-saida.md" "$FIX/portoes-saida-com-segredo.md" \
         "$FIX/portoes-timeout.md" "$FIX/portoes-abandona.md" \
         "$FIX/portoes-sentinela.md"; do
  [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }
done

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT

afirma() {
  local nome="$1" cond="$2"
  if [ "$cond" = "1" ]; then echo "  ok   $nome"; ok=$((ok+1));
  else echo "  FALHA $nome"; falhou=$((falhou+1)); fi
}

# `roda <fixture> [flags...]` — copia para o temp, roda, deixa saida em $SAIDA,
# exit em $CODIGO e o caminho da copia em $COPIA.
roda() {
  local fixture="$1"; shift
  COPIA="$S/$(basename "$fixture")"
  cp "$FIX/$fixture" "$COPIA"
  SAIDA="$(cd "$RAIZ" && node "$P" rodar "$COPIA" "$@" 2>&1)"; CODIGO=$?
}

echo "== caminho feliz =="
roda portoes-ok.md
# portoes-ok.md tem um portao MANUAL (P2), que nunca fecha sozinho — de proposito.
afirma "R1. com portao manual pendente, rodar sai 1" "$([ "$CODIGO" -eq 1 ] && echo 1 || echo 0)"
afirma "R2. o portao executavel fecha como CUMPRIDO" \
  "$(printf '%s' "$SAIDA" | grep -q 'P1: CUMPRIDO' && echo 1 || echo 0)"
afirma "R3. o portao manual e' nomeado como manual, nao como falha muda" \
  "$(printf '%s' "$SAIDA" | grep -q 'P1: CUMPRIDO' && printf '%s' "$SAIDA" | grep -q 'MANUAL' && echo 1 || echo 0)"
afirma "R4. o checkbox do portao cumprido virou [x] no arquivo" \
  "$(grep -q '^\- \[x\] P1' "$COPIA" && echo 1 || echo 0)"
afirma "R5. a EVIDENCIA gravada traz shell, exit e fingerprint" \
  "$(grep -q '"shell"' "$COPIA" && grep -q '"fingerprint"' "$COPIA" && echo 1 || echo 0)"

echo "== A ASSERCAO CENTRAL: cumprido exige exit 0 E match =="
roda portoes-exit-zero-sem-marcador.md
afirma "R6. exit 0 sem o marcador NAO cumpre o portao" "$([ "$CODIGO" -eq 1 ] && echo 1 || echo 0)"
afirma "R7. ...e o arquivo continua com o checkbox vazio" \
  "$(grep -q '^\- \[ \] P1' "$COPIA" && echo 1 || echo 0)"

echo "== abandono nunca e' conclusao =="
roda portoes-abandona.md
afirma "R8. com ABANDONA, sai 1 mesmo com os outros portoes cumpridos" \
  "$([ "$CODIGO" -eq 1 ] && printf '%s' "$SAIDA" | grep -q 'P1: CUMPRIDO' && echo 1 || echo 0)"
afirma "R9. e imprime DEVOLUCAO OBRIGATORIA com a razao" \
  "$(printf '%s' "$SAIDA" | grep -q 'DEVOLUCAO OBRIGATORIA' && printf '%s' "$SAIDA" | grep -q 'decisao humana' && echo 1 || echo 0)"
afirma "R10. o CHECK do portao abandonado nao foi executado" \
  "$(printf '%s' "$SAIDA" | grep -q 'P2: ABANDONADO' && echo 1 || echo 0)"

echo "== a evidencia nao vaza output bruto =="
# O fixture imprime o marcador E uma linha a mais. Procurar pelo marcador seria
# tautologico — ele e' o ESPERA declarado e esta no arquivo por definicao. Quem
# denuncia vazamento e' a linha EXTRA, que so existe no stdout.
roda portoes-saida-com-segredo.md
afirma "R11. o portao fecha (o marcador casou)" "$([ "$CODIGO" -eq 0 ] && echo 1 || echo 0)"
afirma "R12. a linha extra do stdout NAO foi para o arquivo" \
  "$(grep -q 'SEGREDO-QUE-NAO-PODE-VAZAR' "$COPIA" && echo 0 || echo 1)"
afirma "R13. a EVIDENCIA nao tem campo de saida bruta" \
  "$(grep -q '"saida"' "$COPIA" && echo 0 || echo 1)"
afirma "R14. mas TEM o fingerprint, que e' o substituto" \
  "$(grep -q '"fingerprint"' "$COPIA" && echo 1 || echo 0)"

echo "== CHECK que reprova =="
roda portoes-falha.md
afirma "R15. CHECK com exit 1 nao cumpre" "$([ "$CODIGO" -eq 1 ] && echo 1 || echo 0)"
afirma "R16. e o motivo nomeia o exit" \
  "$(printf '%s' "$SAIDA" | grep -q 'exit 1' && echo 1 || echo 0)"

echo "== CRLF na saida do CHECK =="
roda portoes-crlf-saida.md
afirma "R17. marcador cercado de CRLF casa mesmo assim" \
  "$([ "$CODIGO" -eq 0 ] && echo 1 || echo 0)"

echo "== timeout mata, nao pendura =="
# NAO usar o helper `roda` aqui: ele nao passa a env, e o fixture cairia no teto
# padrao de 120 s. A primeira versao desta bateria tinha um `roda portoes-timeout.md`
# antes desta linha, inutil porque a chamada abaixo o sobrescrevia — custava 60 s
# de espera por execucao, medidos na catraca de mutacao (baseline 65 s).
#
# PORTOES_TIMEOUT_MS baixo: se o timeout nao funcionasse, esta bateria travaria
# 60 s no fixture `devagar.cjs` em vez de falhar.
COPIA="$S/portoes-timeout.md"; cp "$FIX/portoes-timeout.md" "$COPIA"
SAIDA="$(cd "$RAIZ" && PORTOES_TIMEOUT_MS=1500 node "$P" rodar "$COPIA" 2>&1)"; CODIGO=$?
afirma "R18. CHECK que pendura e' morto e conta como nao cumprido" \
  "$([ "$CODIGO" -eq 1 ] && echo 1 || echo 0)"
afirma "R19. e o motivo diz que foi timeout, nao 'exit null'" \
  "$(printf '%s' "$SAIDA" | grep -q 'timeout' && echo 1 || echo 0)"

echo "== --reverificar =="
roda portoes-ok.md
SAIDA2="$(cd "$RAIZ" && node "$P" rodar "$COPIA" 2>&1)"
afirma "R20. sem a flag, portao ja cumprido e' pulado" \
  "$(printf '%s' "$SAIDA2" | grep -q 'pulado' && echo 1 || echo 0)"
SAIDA3="$(cd "$RAIZ" && node "$P" rodar "$COPIA" --reverificar 2>&1)"
afirma "R21. com --reverificar, ele roda de novo" \
  "$(printf '%s' "$SAIDA3" | grep -q 'P1: CUMPRIDO' && echo 1 || echo 0)"

echo "== PROVA CRUZADA: rodar DEVE criar a sentinela =="
# Esta e' a outra metade da prova de nao-execucao das tarefas 1 e 2. La afirmamos
# que a sentinela NAO existe; aqui, que ela EXISTE. Sem este caso, aquelas duas
# baterias passariam com um fixture quebrado.
ALVO="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")/sentinela-rodar"
sed "s|SENTINELA_ALVO|$ALVO|" "$FIX/portoes-sentinela.md" > "$S/sentinela.md"
rm -f "$ALVO"
(cd "$RAIZ" && node "$P" rodar "$S/sentinela.md" >/dev/null 2>&1)
afirma "R22. rodar EXECUTOU o CHECK e a sentinela existe" \
  "$([ -e "$ALVO" ] && echo 1 || echo 0)"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
