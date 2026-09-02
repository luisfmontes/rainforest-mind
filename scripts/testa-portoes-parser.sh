#!/bin/bash
# Bateria do parser e do modo `status` de `scripts/portoes.cjs`.
# Uso: bash scripts/testa-portoes-parser.sh
#
# Tarefa 1 do plano `docs/rainforest/planos/2026-09-02-fluxo-6-portoes.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR. Duas coisas, e a segunda é a que
# justifica o arquivo inteiro:
#
#   1. Que o parser aceite arquivo malformado. Portão com CHECK sem ESPERA, id
#      duplicado, ABANDONA sem razão — cada um tem caso próprio de RECUSA, porque
#      checagem só vista passando não foi verificada (lição de 2026-08-13, três
#      entregas seguidas com o lado verde e as três erradas).
#
#   2. Que o `status` execute o CHECK de algum portão. Esta é a asserção mais
#      importante do fluxo 6. `status` é o modo que se roda PARA DECIDIR se vale
#      executar; se ele mesmo executa, a decisão já foi tomada por baixo. A prova
#      não é ler o código — é o fixture-sentinela: um portão cujo CHECK cria um
#      arquivo. Apaga-se a sentinela, roda-se `status`, e afirma-se que ela NÃO
#      existe depois. A prova cruzada (que a sentinela funciona) está na bateria
#      do `rodar`, tarefa 3, onde ela DEVE ser criada.
#
# Sobre o fixture de CRLF: ele NÃO é versionado. O `.gitattributes` desta casa
# exige LF e o `conferir-encoding.cjs` recusa o repositório inteiro quando acha
# CRLF numa árvore de trabalho — versionar um fixture CRLF acenderia uma bateria
# vermelha permanente para testar outra. Ele é gerado aqui, na hora, a partir do
# fixture LF.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$RAIZ/scripts/portoes.cjs"
FIX="$RAIZ/test/fixtures/portoes"
# Forma NATIVA do caminho, para os casos em que NODE invoca NODE: nessa ponte
# nao ha conversao MSYS, e `/c/...` chega ao Windows como `C:\c\...`.
FIXN="$(cygpath -m "$FIX" 2>/dev/null || printf '%s' "$FIX")"

for f in "$P" "$FIX/portoes-ok.md" "$FIX/portoes-sentinela.md" \
         "$FIX/portoes-abandona.md" "$FIX/portoes-vazio.md" \
         "$FIX/portoes-inconsistente.md" \
         "$FIX/portoes-malformado-id-duplicado.md" \
         "$FIX/portoes-malformado-check-sem-espera.md" \
         "$FIX/portoes-malformado-abandona-sem-razao.md" \
         "$FIX/scripts/sentinela.cjs" "$FIX/scripts/sempre-ok.cjs"; do
  [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }
done

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT

# `caso <nome> <exit-esperado> <arquivo> [trecho-esperado-na-saida]`
caso() {
  local nome="$1" esperado="$2" arq="$3" trecho="${4:-}"
  local saida codigo
  saida="$(cd "$RAIZ" && node "$P" status "$arq" 2>&1)"; codigo=$?
  if [ "$codigo" -ne "$esperado" ]; then
    echo "  FALHA $nome: exit $codigo, esperava $esperado"
    echo "    saida: $(printf '%s' "$saida" | tr '\n' '|')"
    falhou=$((falhou+1)); return
  fi
  if [ -n "$trecho" ] && ! printf '%s' "$saida" | grep -q "$trecho"; then
    echo "  FALHA $nome: saida nao contem '$trecho'"
    echo "    saida: $(printf '%s' "$saida" | tr '\n' '|')"
    falhou=$((falhou+1)); return
  fi
  echo "  ok   $nome"
  ok=$((ok+1))
}

echo "== parse: arquivo bem formado =="
caso "P1. fixture feliz parseia e sai 0" 0 "$FIX/portoes-ok.md" "PARSE OK"
caso "P2. portao executavel comeca pendente" 0 "$FIX/portoes-ok.md" "P1: pendente"
caso "P3. portao manual (sem CHECK) tambem e pendente" 0 "$FIX/portoes-ok.md" "P2: pendente"

echo "== parse: CRLF =="
# Gerado aqui — ver cabeçalho. `awk` em vez de `sed -i`/`unix2dos` porque nem
# todo ambiente tem os dois, e o objetivo é justamente portabilidade.
awk '{ printf "%s\r\n", $0 }' "$FIX/portoes-ok.md" > "$S/crlf.md"
# A deteccao do \r e' por Node, NAO por grep, e isso e' achado desta bateria:
# o grep do Git Bash normaliza CRLF antes de casar, entao `grep -q $'\r'` diz
# "nao achou" num arquivo que o `od -c` e o `file` confirmam ser CRLF. Escrito
# com grep, este guarda ficaria PERMANENTEMENTE vermelho — e, pior, num teste
# onde a asserção fosse invertida, ficaria permanentemente verde sem medir nada.
# E' o mesmo motivo pelo qual o lint da tarefa 2 marca dependencia de grep/tail.
if node -e "process.exit(require('fs').readFileSync(process.argv[1]).includes(13)?0:1)" "$S/crlf.md"; then
  echo "  ok   P4. o fixture CRLF realmente tem \\r (o teste mede o que promete)"
  ok=$((ok+1))
else
  echo "  FALHA P4: o fixture CRLF saiu sem \\r — o caso P5 nao provaria nada"
  falhou=$((falhou+1))
fi
caso "P5. CRLF parseia igual a LF" 0 "$S/crlf.md" "PARSE OK"
caso "P6. CRLF nao vaza \\r para o id do portao" 0 "$S/crlf.md" "P1: pendente"

echo "== parse: malformado recusa com exit 2 =="
caso "P7. id duplicado" 2 "$FIX/portoes-malformado-id-duplicado.md" "duplicado"
caso "P8. CHECK sem ESPERA" 2 "$FIX/portoes-malformado-check-sem-espera.md" "sem ESPERA"
caso "P9. ABANDONA sem razao" 2 "$FIX/portoes-malformado-abandona-sem-razao.md" "sem razão"
caso "P10. arquivo sem portao nenhum" 2 "$FIX/portoes-vazio.md" "sem portão nenhum"
# Achado A1 da revisao de 2026-09-02: `gravar()` so reescreve linha que ja existe,
# entao um portao SEM linha EVIDENCIA era executado, reportado como CUMPRIDO e
# marcado `[x]` — sem nada persistir. O `status` seguinte lia isso como
# `inconsistente`, e o lint passava limpo antes disso. O arquivo VERSIONADO era
# corrompido em silencio, por um caminho que nenhum dos tres modos denunciava.
caso "P10b. portao executavel SEM linha EVIDENCIA" 2 \
     "$FIX/portoes-malformado-sem-evidencia.md" "obrigatória"
caso "P11. arquivo inexistente" 2 "$S/nao-existe.md" "não existe"

echo "== estado: abandono e inconsistencia =="
caso "P12. portao abandonado se reporta como abandonado" 0 "$FIX/portoes-abandona.md" "P2: abandonado"
caso "P13. o abandono carrega a razao na saida" 0 "$FIX/portoes-abandona.md" "decisao humana"
caso "P14. checkbox marcado sem evidencia e inconsistente, nao cumprido" 0 \
     "$FIX/portoes-inconsistente.md" "P1: inconsistente"

echo "== A ASSERCAO CENTRAL: status NUNCA executa CHECK =="
# O fixture aponta para um caminho relativo (SENTINELA_ALVO); reescrevemos para
# um caminho no temp, para não sujar a árvore nem colidir entre execuções.
# Caminho NATIVO, via cygpath — e isto foi achado, nao precaucao. Com o caminho
# MSYS (`/tmp/...`), a prova era falsa nas duas pontas: quando o bash invoca o
# node, o MSYS converte o argumento e a escrita funciona; quando o NODE invoca
# outro node (que e' o que um `status` defeituoso faria), nao ha conversao, o
# Windows resolve `/tmp/...` como `C:\tmp\...`, o diretorio nao existe e a
# escrita falha calada. Resultado: P15 passaria mesmo com o defeito presente, e
# P16 nao pegaria, porque exercita justamente a ponta que funciona.
ALVO="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")/sentinela-tocada"
sed "s|SENTINELA_ALVO|$ALVO|" "$FIX/portoes-sentinela.md" > "$S/sentinela.md"
rm -f "$ALVO"

saida="$(cd "$RAIZ" && node "$P" status "$S/sentinela.md" 2>&1)"; codigo=$?
if [ "$codigo" -ne 0 ]; then
  echo "  FALHA P15: status saiu $codigo no fixture-sentinela (esperava 0)"
  falhou=$((falhou+1))
elif [ -e "$ALVO" ]; then
  echo "  FALHA P15: A SENTINELA EXISTE — o \`status\` executou o CHECK do portao."
  echo "    Este e o defeito que esta bateria existe para impedir."
  falhou=$((falhou+1))
else
  echo "  ok   P15. status nao criou a sentinela — nao executou o CHECK"
  ok=$((ok+1))
fi

# Controle negativo do proprio caso P15: se a sentinela nunca pudesse ser criada,
# P15 passaria com o defeito presente. Aqui provamos que o script SABE criar.
#
# O controle roda NODE INVOCANDO NODE, de proposito — nao bash invocando node.
# E' a mesma ponte que um `status` defeituoso usaria, e e' a unica que prova o
# que P15 precisa. A primeira versao desta bateria usava bash->node aqui e
# passava verde enquanto P15 era tautologico (ver o comentario do ALVO acima).
rm -f "$ALVO"
(cd "$RAIZ" && node -e "
  require('child_process').spawnSync(process.execPath,
    ['$FIXN/scripts/sentinela.cjs', '$ALVO'], {shell: false});
" >/dev/null 2>&1)
if [ -e "$ALVO" ]; then
  echo "  ok   P16. o script de sentinela realmente cria o arquivo (P15 mede algo)"
  ok=$((ok+1))
else
  echo "  FALHA P16: o script de sentinela nao criou nada — P15 e tautologico"
  falhou=$((falhou+1))
fi

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
