#!/bin/bash
# Bateria do `conferir-esteira.cjs` e da trava de fechamento do `estado.cjs`.
# Uso: bash scripts/testa-conferir-esteira.sh
#
# Tarefa 3 do plano `docs/rainforest/planos/decisao-que-evapora-na-esteira.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR, e por que quase todo caso e' negativo:
# uma checagem so vista PASSANDO nao foi verificada. Em 2026-08-13, tres entregas
# seguidas nesta mesma esteira mostraram apenas o lado verde e as tres estavam
# erradas — uma delas com uma assercao que passava identica contra o codigo antigo.
# Por isso aqui cada recusa tem caso proprio: se a checagem parar de recusar, a
# bateria cai, e nao ha como isso passar despercebido.
#
# Fixture: o design e o plano REAIS deste trabalho, mutilados de um jeito por vez.
# Usar os reais e' de proposito — fixture sintetico envelhece separado do formato
# e para de medir o que o formato virou.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECADOR="$RAIZ/scripts/conferir-esteira.cjs"
ESTADO="$RAIZ/scripts/estado.cjs"
REAL_D="$RAIZ/docs/rainforest/design/decisao-que-evapora-na-esteira.md"
REAL_P="$RAIZ/docs/rainforest/planos/decisao-que-evapora-na-esteira.md"

for f in "$CHECADOR" "$ESTADO" "$REAL_D" "$REAL_P"; do
  [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }
done

ok=0; falhou=0
S="$(mktemp -d)"; W="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/docs/rainforest/design" "$S/docs/rainforest/planos"
D="$S/docs/rainforest/design/t.md"
P="$S/docs/rainforest/planos/t.md"
restaura(){ cp "$REAL_D" "$D"; cp "$REAL_P" "$P"; }

# exige <exit-esperado> <rotulo> <comando...>
exige(){
  local esperado="$1" rotulo="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$esperado" ]; then
    ok=$((ok+1)); printf '  ok    %s (exit=%s)\n' "$rotulo" "$got"
  else
    falhou=$((falhou+1)); printf '  FALHA %s: esperado exit=%s, veio exit=%s\n' "$rotulo" "$esperado" "$got"
  fi
}
CHK(){ RFM_ESTADO_ROOT="$W" node "$CHECADOR" "$@"; }

echo "(caixa de areia: $W)"
echo
echo "== 1. design: forma do documento =="
restaura
exige 0 "design real passa" CHK design --slug t

restaura; sed -i 's/^## Avaliado e descartado$/## Outra coisa/' "$D"
exige 2 "secao 'Avaliado e descartado' ausente recusa" CHK design --slug t

restaura; sed -i 's/^## Fora de escopo$/## Outra coisa/' "$D"
exige 2 "secao 'Fora de escopo' ausente recusa" CHK design --slug t

restaura; sed -i 's/\*\*D5 —/**D9 —/' "$D"
exige 2 "buraco na sequencia de D recusa" CHK design --slug t

# D repetido tem de ser ACRESCENTADO, nunca renomeado. Renomear `D6` para `D5`
# cria um repetido E um buraco, e o check de buraco roda primeiro — o caso saía
# verde com o check de repetido apagado, provando nada. Achado 2 da revisão de
# 2026-08-13. Acrescentar uma linha mantém D1..D8 inteiros e deixa a duplicidade
# como a única coisa errada no documento.
restaura; awk '/^## Avaliado e descartado$/{print "- **D3 — duplicata deliberada** — porque: isolar o check de repetido"; print ""} {print}' "$REAL_D" > "$D"
exige 2 "D repetido (sem buraco junto) recusa" CHK design --slug t

echo
echo "== 2. cobertura: design x plano, nos dois sentidos (D8) =="
restaura
exige 0 "cobertura real passa" CHK cobertura --slug t

# A tarefa 2 e' a unica que atende D5; tirando ela, D5 fica orfa.
restaura; awk '/^### 2\. /{p=1} /^### 3\. /{p=0} !p' "$REAL_P" > "$P"
exige 2 "decisao sem tarefa recusa" CHK cobertura --slug t

# Os dois casos abaixo mutam a TAREFA 3 (`atende: D1, D7`) e não a primeira que
# aparecer. Motivo: D1 também está na tarefa 1, e D7 nas tarefas 1 e 5 — mexer na
# 3 não deixa decisão órfã, então o único check que pode recusar é o que o rótulo
# promete. Mutando a tarefa 1 (a única que cita D8), esvaziar o `atende:` orfanava
# D8 e o caso saía verde pelo check de "decisão sem tarefa", com o código sob
# teste apagado. Achado 2 da revisão de 2026-08-13.
restaura; sed -i '/^### 3\. /,/^pronto quando:/ s/^atende: .*/atende:/' "$P"
exige 2 "tarefa com 'atende:' vazio recusa (sem orfanar decisao)" CHK cobertura --slug t

restaura; sed -i '/^### 3\. /,/^pronto quando:/ s/^atende: .*/atende: D1, D7, D99/' "$P"
exige 2 "tarefa citando D inexistente recusa (cobertura intacta)" CHK cobertura --slug t

echo
echo "== 3. creep: diff x globs das tarefas =="
# Contra o repo real, porque creep precisa de git de verdade. `ff1fd3c` e' a base
# deste trabalho e `e1a6824` e' a anterior — o intervalo entre as duas mexeu em
# `hooks/`, que nenhuma tarefa deste plano declara.
if git -C "$RAIZ" cat-file -e e1a6824^{commit} 2>/dev/null && git -C "$RAIZ" cat-file -e ff1fd3c^{commit} 2>/dev/null; then
  exige 2 "arquivo fora de todo glob recusa" \
    node "$CHECADOR" creep --slug decisao-que-evapora-na-esteira --base e1a6824 --head ff1fd3c
  exige 0 "docs/rainforest/** nao conta como creep" \
    node "$CHECADOR" creep --slug decisao-que-evapora-na-esteira --base ff1fd3c --head HEAD
else
  echo "  (pulado: commits de referencia ausentes neste clone)"
fi

echo
echo "== 4. trava do estado.cjs: fechar estagio passa pela checagem (D5) =="
E(){ RFM_ESTADO_ROOT="$W" node "$ESTADO" "$@"; }

restaura; rm -f "$S/docs/rainforest/estado/t.json"; E iniciar --slug t >/dev/null 2>&1
exige 0 "design conforme fecha" E marcar --slug t --estagio design --status aprovado
exige 0 "plano com cobertura fecha" E marcar --slug t --estagio plano --status ok
exige 0 "executar nao tem checagem" E marcar --slug t --estagio executar --status ok
exige 2 "revisar ok SEM base/head recusa (D4)" E marcar --slug t --estagio revisar --status ok --json '{"achados":0}'

restaura; awk '/^### 2\. /{p=1} /^### 3\. /{p=0} !p' "$REAL_P" > "$P"
rm -f "$S/docs/rainforest/estado/t.json"; E iniciar --slug t >/dev/null 2>&1
E marcar --slug t --estagio design --status aprovado >/dev/null 2>&1
exige 2 "plano com decisao orfa NAO fecha" E marcar --slug t --estagio plano --status ok

echo
echo "== 5. a trava nao pode capturar quem nao usa a esteira =="
# Invariante do plano: projeto sem design/plano continua fechando estagio como
# antes. Sem isto, a trava deixaria de apertar quem esta na esteira e passaria a
# tornar a esteira obrigatoria — que e' outra coisa, e ninguem decidiu isso.
V="$(mktemp -d)"; VW="$(cygpath -m "$V" 2>/dev/null || printf '%s' "$V")"
VE(){ RFM_ESTADO_ROOT="$VW" node "$ESTADO" "$@"; }
VE iniciar --slug vazio >/dev/null 2>&1
exige 0 "sem design no disco, 'design aprovado' fecha" VE marcar --slug vazio --estagio design --status aprovado
exige 0 "sem plano no disco, 'plano ok' fecha" VE marcar --slug vazio --estagio plano --status ok
rm -rf "$V"

# O CASO MISTO, que a seção acima não pegava: plano existe, design nunca existiu.
# Aqui a trava prendia o estágio para sempre — `design aprovado` passava (sem
# design não há o que conferir) e o `plano ok` seguinte recusava com "design não
# existe", sem saída. Achado 1 da revisão de 2026-08-13. A regra que este caso
# guarda: a trava só age quando TUDO que a checagem lê existe, não só o arquivo
# do estágio que está fechando.
M="$(mktemp -d)"; MW="$(cygpath -m "$M" 2>/dev/null || printf '%s' "$M")"
mkdir -p "$M/docs/rainforest/planos"; cp "$REAL_P" "$M/docs/rainforest/planos/misto.md"
ME(){ RFM_ESTADO_ROOT="$MW" node "$ESTADO" "$@"; }
ME iniciar --slug misto >/dev/null 2>&1
ME marcar --slug misto --estagio design --status aprovado >/dev/null 2>&1
exige 0 "plano SEM design no disco nao fica preso" ME marcar --slug misto --estagio plano --status ok
rm -rf "$M"

echo
echo "== 6. isencao do creep e escopada por slug =="
# Isentar `docs/rainforest/design/**` inteiro escondia creep de verdade: o design
# de OUTRA feature entrava no diff e passava. Achado 4 da revisão de 2026-08-13.
if git -C "$RAIZ" cat-file -e ff1fd3c^{commit} 2>/dev/null; then
  exige 2 "design de OUTRO slug no diff conta como creep" \
    node "$CHECADOR" creep --slug outro-trabalho-qualquer --base ff1fd3c --head HEAD
else
  echo "  (pulado: commit de referencia ausente neste clone)"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
