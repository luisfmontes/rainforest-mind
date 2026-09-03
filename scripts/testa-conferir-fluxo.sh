#!/bin/bash
# Bateria do `conferir-fluxo.cjs` e da trava de fechamento do `estado.cjs`.
# Uso: bash scripts/testa-conferir-fluxo.sh
#
# Tarefa 3 do plano `docs/rainforest/planos/decisao-que-evapora-na-esteira.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR, e por que quase todo caso e' negativo:
# uma checagem so vista PASSANDO nao foi verificada. Em 2026-08-13, tres entregas
# seguidas neste mesmo fluxo mostraram apenas o lado verde e as tres estavam
# erradas — uma delas com uma assercao que passava identica contra o codigo antigo.
# Por isso aqui cada recusa tem caso proprio: se a checagem parar de recusar, a
# bateria cai, e nao ha como isso passar despercebido.
#
# Fixture: o design e o plano REAIS deste trabalho, mutilados de um jeito por vez.
# Usar os reais e' de proposito — fixture sintetico envelhece separado do formato
# e para de medir o que o formato virou.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECADOR="$RAIZ/scripts/conferir-fluxo.cjs"
ESTADO="$RAIZ/scripts/estado.cjs"
REAL_D="$RAIZ/docs/rainforest/design/decisao-que-evapora-na-esteira.md"
REAL_P="$RAIZ/docs/rainforest/planos/decisao-que-evapora-na-esteira.md"
NOVO_D="$RAIZ/docs/rainforest/design/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.md"
NOVO_P="$RAIZ/docs/rainforest/planos/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.md"

for f in "$CHECADOR" "$ESTADO" "$REAL_D" "$REAL_P" "$NOVO_D" "$NOVO_P"; do
  [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }
done

ok=0; falhou=0
S="$(mktemp -d)"; W="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/docs/rainforest/design" "$S/docs/rainforest/planos"
D="$S/docs/rainforest/design/t.md"
P="$S/docs/rainforest/planos/t.md"

# `plano_no_formato <origem> <destino>` — copia o plano acrescentando o bloco
# `mutacao:` a cada tarefa.
#
# O plano fixture desta secao e' de 2026-08-13 e e' ANTERIOR ao campo `mutacao:`,
# que a `cobertura` passou a exigir em 2026-08-21. A injecao acontece so na
# copia: o arquivo versionado e' o registro de um trabalho ja fechado e nao se
# reescreve para agradar checagem nova.
#
# Sem isto, toda mutilacao desta secao passaria a recusar tambem por falta de
# `mutacao:`, e cada caso ficaria verde com o check que ele testa apagado — que
# e' exatamente o Achado 2 da revisao de 2026-08-13, repetido de outro jeito.
plano_no_formato(){
  awk '/^pronto quando:/ {
         print "mutacao:";
         print "  arquivo: `scripts/conferir-fluxo.cjs`";
         print "  de: a checagem que esta tarefa instala";
         print "  para: um no-op";
         print "  bateria: `bash scripts/testa-conferir-fluxo.sh`"
       } {print}' "$1" > "$2"
}
restaura(){ cp "$REAL_D" "$D"; plano_no_formato "$REAL_P" "$P"; }

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

# exige_msg <regex> <rotulo> <comando...>
# Exit code so' diz QUE recusou. Recusa que nao diz QUAL tarefa esta errada faz
# quem le abrir o plano inteiro procurando, e o atalho para isso e' desligar a
# trava. Por isso o texto da recusa tem caso proprio.
exige_msg(){
  local regex="$1" rotulo="$2"; shift 2
  local saida; saida="$("$@" 2>&1)"
  if printf '%s\n' "$saida" | grep -q "$regex"; then
    ok=$((ok+1)); printf '  ok    %s\n' "$rotulo"
  else
    falhou=$((falhou+1)); printf '  FALHA %s: saida nao casa /%s/:\n%s\n' "$rotulo" "$regex" "$saida"
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
restaura; awk '/^### 2\. /{p=1} /^### 3\. /{p=0} !p' "$REAL_P" > "$S/sem-tarefa-2.md"
plano_no_formato "$S/sem-tarefa-2.md" "$P"
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
  # `--head` PRECISA ser fixo. A versao original usava `HEAD`, e a assercao so
  # valia enquanto o HEAD do repo fosse a ponta do proprio trabalho
  # `decisao-que-evapora-na-esteira` — o primeiro trabalho seguinte a entrar na
  # branch coloca no diff arquivos que o plano dele nao declara, e o creep passa
  # a acusar CORRETAMENTE, derrubando um teste que nao tem nada a ver.
  # Aconteceu em 2026-08-14, ao integrar o fluxo do orcamento de tokens (21 ok
  # na main, 20 ok / 1 falha na branch seguinte. Mesma familia do fixture do
  # testa-saude.sh: teste que afirma sobre o estado corrente do repo envelhece
  # sozinho. `f9fe746` e o squash do PR #9, ou seja, exatamente a ponta daquele
  # trabalho — o intervalo ff1fd3c..f9fe746 e o diff dele e mais nada.
  exige 0 "diff do proprio trabalho nao conta como creep" \
    node "$CHECADOR" creep --slug decisao-que-evapora-na-esteira --base ff1fd3c --head f9fe746
else
  echo "  (pulado: commits de referencia ausentes neste clone)"
fi

echo
echo "== 4. trava do estado.cjs: fechar estagio passa pela checagem (D5) =="
E(){ RFM_ESTADO_ROOT="$W" node "$ESTADO" "$@"; }

restaura; rm -f "$S/docs/rainforest/estado/t.json"; E iniciar --slug t >/dev/null 2>&1
exige 0 "design conforme fecha" E marcar --slug t --estagio design --status aprovado
exige 0 "plano com cobertura fecha" E marcar --slug t --estagio plano --status ok
# D6 inverteu esta linha. Ate 2026-08-21 o `executar` era o unico estagio sem
# checagem no fechamento, e este caso se chamava "executar nao tem checagem". Agora
# ele tem: a catraca de mutacao. Sao tres portas em serie, e cada uma fecha um jeito
# diferente de sair verde sem prova.
MUT5='[{"tarefa":1,"resultado":"vermelho","fixture":"t1"},{"tarefa":2,"resultado":"vermelho","fixture":"t2"},{"tarefa":3,"resultado":"vermelho","fixture":"t3"},{"tarefa":4,"resultado":"n/a","motivo":"doc"},{"tarefa":5,"resultado":"n/a","motivo":"doc"}]'

# 1a porta: catraca que nunca foi armada. Quem pula o `exigir` pula a leitura do
# que a catraca cobra, e fechar assim seria fechar por desconhecimento.
exige 2 "executar SEM catraca armada recusa (D6)" E marcar --slug t --estagio executar --status ok
E exigir --slug t --estagio executar >/dev/null 2>&1
# 2a porta: catraca armada, lista ausente. "As baterias passaram" nao distingue
# bateria que testa de bateria que nao sabe falhar.
exige 2 "executar com catraca armada mas SEM lista recusa" E marcar --slug t --estagio executar --status ok
# 3a porta: lista que nao cobre o plano inteiro. Tarefa omitida e a mais barata de
# esconder, entao a lista se cruza com o plano, tarefa a tarefa.
exige 2 "lista que pula tarefa do plano recusa" E marcar --slug t --estagio executar --status ok \
  --json '{"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"t1"}]}'
exige 2 "lista com tarefa que nao existe no plano recusa" E marcar --slug t --estagio executar --status ok \
  --json "{\"mutacao\":$(printf '%s' "$MUT5" | sed 's/\]$/,{"tarefa":99,"resultado":"vermelho","fixture":"t99"}]/')}"
# Numero repetido cobriria o plano inteiro pela contagem e deixaria uma tarefa de
# fora — e a forma mais barata de satisfazer a cobertura sem ter mutado nada.
exige 2 "mesma tarefa duas vezes na lista recusa" E marcar --slug t --estagio executar --status ok \
  --json '{"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"t1"},{"tarefa":1,"resultado":"vermelho","fixture":"t1"},{"tarefa":2,"resultado":"vermelho","fixture":"t2"},{"tarefa":3,"resultado":"vermelho","fixture":"t3"},{"tarefa":4,"resultado":"n/a","motivo":"doc"}]}'
# 4a porta, acrescentada em 2026-08-28 pelo ciclo-por-maquina: `executar` e
# `verificar` so fecham com `comando` e `saida` no --json
# (ESTAGIOS_EXIGEM_EVIDENCIA em scripts/estado.cjs:110). Esta bateria nao
# acompanhou a mudanca e ficou VERMELHA na main desde entao — o caso abaixo
# pedia exit 0 de um fechamento que o estado.cjs recusa, com razao, por falta de
# evidencia. Corrigido em 2026-09-01: quem prova a catraca de mutacao passa pela
# porta da evidencia tambem.
exige 0 "executar com catraca armada e lista completa fecha" E marcar --slug t --estagio executar --status ok \
  --json "{\"tarefas_ok\":5,\"tarefas\":5,\"comando\":\"bash scripts/testa-x.sh\",\"saida\":\"ok: 5 falhou: 0\",\"mutacao\":$MUT5}"

exige 2 "revisar ok SEM base/head recusa (D4)" E marcar --slug t --estagio revisar --status ok --json '{"achados":0}'

restaura; awk '/^### 2\. /{p=1} /^### 3\. /{p=0} !p' "$REAL_P" > "$S/sem-tarefa-2.md"
plano_no_formato "$S/sem-tarefa-2.md" "$P"
rm -f "$S/docs/rainforest/estado/t.json"; E iniciar --slug t >/dev/null 2>&1
E marcar --slug t --estagio design --status aprovado >/dev/null 2>&1
exige 2 "plano com decisao orfa NAO fecha" E marcar --slug t --estagio plano --status ok

echo
echo "== 5. a trava nao pode capturar quem nao usa o fluxo =="
# Invariante do plano: projeto sem design/plano continua fechando estagio como
# antes. Sem isto, a trava deixaria de apertar quem esta no fluxo e passaria a
# tornar o fluxo obrigatorio — que e' outra coisa, e ninguem decidiu isso.
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
#
# A primeira versão DESTE caso era vazia — rodava com um slug fictício, e o
# `creep` recusava antes, na leitura do plano inexistente, sem nunca chegar na
# isenção. Dava exit 2 com a isenção escopada E com a isenção ampla: não
# discriminava nada. Achado 5, da segunda rodada da mesma revisão.
#
# Por isso aqui se monta um repositório git DE VERDADE: sem dois commits reais
# não há diff, e sem diff o `creep` não roda. Fixture que não chega no código
# alvo é fixture que mede a própria ausência.
#
# Três commits, e DOIS intervalos sobre o mesmo repositório — nada é desfeito. O
# contraste entre os dois é o que prova que a recusa vem do outro slug, e não de
# o `creep` recusar tudo que aparece.
G="$(mktemp -d)"; GW="$(cygpath -m "$G" 2>/dev/null || printf '%s' "$G")"
mkdir -p "$G/docs/rainforest/design" "$G/docs/rainforest/planos"
cp "$REAL_D" "$G/docs/rainforest/design/t.md"
cp "$REAL_P" "$G/docs/rainforest/planos/t.md"
git -C "$G" init -q . >/dev/null 2>&1
git -C "$G" config user.email t@t; git -C "$G" config user.name t
git -C "$G" add docs >/dev/null 2>&1; git -C "$G" commit -qm base >/dev/null 2>&1
BASE_G="$(git -C "$G" rev-parse HEAD 2>/dev/null)"
# commit A: mexe SÓ no design deste slug (isento)
echo "- nota" >> "$G/docs/rainforest/design/t.md"
git -C "$G" add docs >/dev/null 2>&1; git -C "$G" commit -qm so-o-proprio >/dev/null 2>&1
SO_PROPRIO="$(git -C "$G" rev-parse HEAD 2>/dev/null)"
# commit B: acrescenta o design de OUTRO slug (não isento, e nenhuma tarefa o declara)
echo "# design de outra feature" > "$G/docs/rainforest/design/outra-feature.md"
git -C "$G" add docs >/dev/null 2>&1; git -C "$G" commit -qm com-outro-slug >/dev/null 2>&1
COM_OUTRO="$(git -C "$G" rev-parse HEAD 2>/dev/null)"

if [ -n "$BASE_G" ] && [ -n "$COM_OUTRO" ] && [ "$BASE_G" != "$COM_OUTRO" ]; then
  exige 0 "design do PROPRIO slug e isento" \
    env RFM_ESTADO_ROOT="$GW" node "$CHECADOR" creep --slug t --base "$BASE_G" --head "$SO_PROPRIO"
  exige 2 "design de OUTRO slug no diff conta como creep" \
    env RFM_ESTADO_ROOT="$GW" node "$CHECADOR" creep --slug t --base "$BASE_G" --head "$COM_OUTRO"
else
  echo "  FALHA nao consegui montar o repositorio de fixture"; falhou=$((falhou+1))
fi
rm -rf "$G"

echo
echo "== 7. catraca de mutacao: toda tarefa declara o alvo (D7, D9) =="
# Fixture proprio, e proposital: o plano de 2026-08-21 nasceu ja no formato, com
# `mutacao:` nas 6 tarefas. Reaproveitar o fixture antigo — que so tem o bloco
# porque a bateria o injeta — mediria a injecao, nao o formato.
#
# O que estes casos impedem: em 2026-08-21 um agente entregou 49/49 verde com a
# trava recusando o caminho feliz sempre. A bateria nao sabia falhar, e o plano
# nao dizia o que ela deveria ter falhado. Sem alvo declarado, a integracao nao
# tem o que re-rodar e o veredito volta a ser o relato de quem implementou.
N="$(mktemp -d)"; NW="$(cygpath -m "$N" 2>/dev/null || printf '%s' "$N")"
mkdir -p "$N/docs/rainforest/design" "$N/docs/rainforest/planos"
ND="$N/docs/rainforest/design/t.md"; NP="$N/docs/rainforest/planos/t.md"
NCHK(){ RFM_ESTADO_ROOT="$NW" node "$CHECADOR" "$@"; }

cp "$NOVO_D" "$ND"; cp "$NOVO_P" "$NP"
exige 0 'plano no formato novo passa (6 tarefas com mutacao:)' NCHK cobertura --slug t

# Tira o bloco da tarefa 3 e SO' dele: a tarefa 3 atende D11, que nenhuma outra
# atende, entao mexer no `atende:` orfanaria a decisao e a recusa viria do check
# errado. Aqui o unico defeito do documento e' o bloco ausente.
cp "$NOVO_P" "$N/inteiro.md"
awk '/^### 3\./{t=1} /^### 4\./{t=0}
     {if (t && /^mutacao:/) {drop=1; next} if (t && drop) {if (/^  /) next; drop=0} print}' \
     "$N/inteiro.md" > "$NP"
exige 2 'tarefa sem bloco mutacao: recusa' NCHK cobertura --slug t
exige_msg 'tarefa 3\.' 'a recusa NOMEIA a tarefa sem bloco' NCHK cobertura --slug t

# A tarefa 6 e' de doc: nao ha comportamento a inverter, e `n/a` com motivo e'
# resposta aceita (D9). Exigir o impossivel de tarefa de doc cria o habito do
# `--forcar`, e trava que se contorna por habito nao trava mais nada.
awk '/^### 6\./{t=1}
     {if (t && /^mutacao:/) {print "mutacao: n/a"; print "  motivo: doc nao tem comportamento a inverter"; drop=1; next}
      if (t && drop) {if (/^  /) next; drop=0} print}' "$N/inteiro.md" > "$NP"
exige 0 'mutacao: n/a COM motivo passa' NCHK cobertura --slug t

# ...e o preco do escape e' o motivo escrito. Sem ele, `n/a` viraria a saida
# barata de toda tarefa.
awk '/^### 6\./{t=1}
     {if (t && /^mutacao:/) {print "mutacao: n/a"; drop=1; next}
      if (t && drop) {if (/^  /) next; drop=0} print}' "$N/inteiro.md" > "$NP"
exige 2 'mutacao: n/a SEM motivo recusa' NCHK cobertura --slug t
rm -rf "$N"

echo
echo "== 8. normalizacao de CRLF e ignorar cerca de codigo =="
# Fixture proprio para testar CRLF e cercas
O="$(mktemp -d)"; OW="$(cygpath -m "$O" 2>/dev/null || printf '%s' "$O")"
mkdir -p "$O/docs/rainforest/design" "$O/docs/rainforest/planos"
OD="$O/docs/rainforest/design/t.md"; OP="$O/docs/rainforest/planos/t.md"
OCHK(){ RFM_ESTADO_ROOT="$OW" node "$CHECADOR" "$@"; }

# Converte o arquivo para CRLF no lugar. Inline de proposito: um helper em arquivo
# separado seria um fonte a mais fora do `arquivos:` da tarefa, e a primeira versao
# desta bateria chamava um `to-crlf.js` que nunca foi commitado — a bateria morria
# com "Cannot find module" e o placar dizia 28 ok / 1 falha, nao "faltou arquivo".
para_crlf(){
  node -e "const f=require('fs'),p=process.argv[1];f.writeFileSync(p,f.readFileSync(p,'utf8').replace(/\r?\n/g,'\r\n'))" "$1"
}

# Caso 1: plano e design reais em CRLF devem passar
cp "$NOVO_D" "$OD"; cp "$NOVO_P" "$OP"
para_crlf "$OD"
para_crlf "$OP"
exige 0 "plano e design em CRLF passam" OCHK cobertura --slug t

# Caso 2: mutacao: dentro de cerca de codigo deve ser ignorado (recusa)
# Usa o design e plano reais, mas modifica tarefa 5 para por mutacao: so em cerca
cp "$NOVO_D" "$OD"; cp "$NOVO_P" "$OP.tmp"
# Modifica a tarefa 5 para deixar mutacao: so em cerca
awk '
/^### 5\. Formato/ { in_task5 = 1; print; next }
in_task5 && /^### [0-9]/ { in_task5 = 0 }
in_task5 && /^mutacao:/ {
  while (getline > 0 && /^  /) { }
  if ($0 !~ /^###/) {
    print ""
    print "Aqui tem uma cerca:"
    print ""
    print "\`\`\`"
    print "mutacao:"
    print "  arquivo: scripts/conferir-fluxo.cjs"
    print "  de: x"
    print "  para: y"
    print "  bateria: bash test.sh"
    print "\`\`\`"
    print ""
  }
  print
  next
}
{ print }
' "$OP.tmp" > "$OP"
para_crlf "$OD"
para_crlf "$OP"
exige 2 "mutacao: so em cerca (em CRLF) recusa" OCHK cobertura --slug t
exige_msg 'tarefa 5\.' 'nomeia tarefa' OCHK cobertura --slug t

# Caso 3: cabecalho de tarefa DENTRO de cerca nao e tarefa. Um plano que documenta o
# proprio formato — e este repositorio faz isso o tempo todo — tem `### 9. <nome>`
# dentro de um bloco de exemplo. Contar isso como tarefa cria uma tarefa fantasma que
# ninguem pode cumprir: `cobertura` cobra um bloco `mutacao:` dela, e o `estado.cjs`
# cobra que a lista de mutacao a cubra. As duas travas recusam entrega correta, e a
# mensagem aponta um numero que nao existe no plano.
cp "$NOVO_D" "$OD"; cp "$NOVO_P" "$OP"
cat >> "$OP" <<'CERCA'

## Anexo: o formato de uma tarefa

```markdown
### 99. Tarefa de exemplo [tipo: implementar]
atende: D1
mutacao:
  arquivo: `x`
```
CERCA
exige 0 "cabecalho de tarefa dentro de cerca nao vira tarefa" OCHK cobertura --slug t
exige_msg '10 tarefa' 'o placar conta 10 tarefas, nao 11' OCHK cobertura --slug t
if OCHK cobertura --slug t 2>&1 | grep -q '99'; then
  falhou=$((falhou+1)); echo "  FALHA a tarefa fantasma 99 apareceu no placar"
else
  ok=$((ok+1)); echo "  ok    a tarefa fantasma 99 nao aparece no placar"
fi

# ...e a MESMA leitura vale no `estado.cjs`, que e a outra trava que cruza lista de
# mutacao contra plano. Os dois liam o plano com parsers diferentes, e o do estado
# nao pulava cerca: a entrega correta era recusada com "lista nao cobre tarefa 99",
# um numero que nao existe no plano. Este caso e o que prende os dois no mesmo
# parser — sem ele, o `estado.cjs` pode voltar a ter parser proprio e a suite
# continua verde.
OE(){ RFM_ESTADO_ROOT="$OW" node "$ESTADO" "$@"; }
LISTA_10='['
for i in 1 2 3 4 5 6 7 8 9 10; do
  [ "$i" = 1 ] || LISTA_10="$LISTA_10,"
  LISTA_10="$LISTA_10{\"tarefa\":$i,\"resultado\":\"vermelho\",\"fixture\":\"t$i\"}"
done
LISTA_10="$LISTA_10]"
OE iniciar --slug t >/dev/null 2>&1
OE marcar --slug t --estagio design --status aprovado >/dev/null 2>&1
OE marcar --slug t --estagio plano  --status ok >/dev/null 2>&1
OE exigir --slug t --estagio executar >/dev/null 2>&1
exige 0 "estado.cjs tambem ignora a cerca ao cruzar a lista" OE marcar --slug t \
  --estagio executar --status ok \
  --json "{\"tarefas_ok\":10,\"tarefas\":10,\"comando\":\"bash scripts/testa-x.sh\",\"saida\":\"ok: 10 falhou: 0\",\"mutacao\":$LISTA_10}"

rm -rf "$O"


echo
echo "== 7. creep nao invoca shell: --base/--head nao executam comando (Issue #89) =="
# O defeito (achado do agente `auditor-de-seguranca` contra este proprio repo em
# 2026-08-25): a linha do diff era `execSync` com a string `git diff --name-only
# ${base}...${head}`. execSync com STRING invoca um shell de verdade, e base/head
# chegam do `--json` de quem fecha o estagio `revisar`.
#
# O caminho seguro ja existia e era abandonado no ultimo passo: o valor viaja como
# ARRAY por spawnSync em estado.cjs:552-563, e so aqui era remontado como string.
#
# A assercao NAO e sobre exit code -- o comando falha nos dois casos, porque o ref
# e invalido. E sobre o EFEITO COLATERAL: se um shell rodou, o sentinela existe.
# Testar por exit code aqui daria verde com o defeito de pe.

CAIXA_INJ="$(mktemp -d)"
# O sentinela nasce no CWD do comando (que e a RAIZ), com nome relativo, e nao num
# mktemp. Motivo medido: o `execSync` do Node no Windows chama o ComSpec (cmd.exe),
# e o caminho POSIX que o `mktemp -d` devolve (/tmp/tmp.XXXX) vira C:	mp... para o
# cmd — o redirecionamento falhava por pasta inexistente, nenhum sentinela aparecia,
# e a SABOTAGEM passava verde sem ter provado nada. Nome relativo nao precisa de
# traducao de caminho e os dois lados (bash e cmd) concordam sobre onde ele esta.
SENTINELA_NOME="sentinela-injecao-89.txt"
SENTINELA="$RAIZ/$SENTINELA_NOME"

rm -f "$SENTINELA"
node "$CHECADOR" creep --slug decisao-que-evapora-na-esteira \
  --base HEAD --head "x&echo INJETADO > $SENTINELA_NOME" >/dev/null 2>&1
if [ -f "$SENTINELA" ]; then
  falhou=$((falhou+1))
  echo "  FALHA um shell foi invocado: o sentinela existe ($SENTINELA)."
  echo "        E o sintoma de execSync com string; o certo e execFileSync com lista."
else
  ok=$((ok+1)); echo "  ok    --head com metacaractere de shell nao executou nada"
fi

# Mesma coisa pelo --base, que vem da mesma cadeia e tinha o mesmo buraco.
rm -f "$SENTINELA"
node "$CHECADOR" creep --slug decisao-que-evapora-na-esteira \
  --base "x&echo INJETADO > $SENTINELA_NOME" --head HEAD >/dev/null 2>&1
if [ -f "$SENTINELA" ]; then
  falhou=$((falhou+1)); echo "  FALHA --base tambem invoca shell"
else
  ok=$((ok+1)); echo "  ok    --base com metacaractere de shell nao executou nada"
fi

echo "  -- SABOTAGEM: devolver o execSync com string e exigir que a assercao caia"
# Trava que nunca foi vista travando nao e evidencia de nada. O mutante volta a
# montar o comando como string; se o sentinela NAO aparecer nele, este teste esta
# medindo outra coisa.
MUT_CHECADOR="$CAIXA_INJ/conferir-fluxo-mut.cjs"
cp "$CHECADOR" "$MUT_CHECADOR"
cat > "$CAIXA_INJ/sabotar-injecao.cjs" <<'SABOTA_INJ_EOF'
const fs = require('fs');
const alvo = process.argv[2];
let t = fs.readFileSync(alvo, 'utf8');
const achar = "const output = execFileSync('git', ['diff', '--name-only', `${base}...${head}`], { cwd: RAIZ, encoding: 'utf8' });";
const trocar = "const output = require('child_process').execSync(`git diff --name-only ${base}...${head}`, { cwd: RAIZ, encoding: 'utf8' });";
if (!t.includes(achar)) { console.error('ANCORA NAO BATE em ' + alvo); process.exit(1); }
fs.writeFileSync(alvo, t.replace(achar, trocar));
SABOTA_INJ_EOF
node "$CAIXA_INJ/sabotar-injecao.cjs" "$MUT_CHECADOR"
EXIT_SABOTA_INJ=$?
if [ "$EXIT_SABOTA_INJ" != "0" ]; then
  falhou=$((falhou+1)); echo "  FALHA ANCORA NAO BATE — a copia intocada nao prova nada"
else
  rm -f "$SENTINELA"
  RFM_ESTADO_ROOT="$RAIZ" node "$MUT_CHECADOR" creep --slug decisao-que-evapora-na-esteira \
    --base HEAD --head "x&echo INJETADO > $SENTINELA_NOME" >/dev/null 2>&1
  if [ -f "$SENTINELA" ]; then
    ok=$((ok+1)); echo "  ok    mutacao expos que a assercao mede a INVOCACAO DE SHELL, nao o exit code"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — voltar o execSync com string nao criou o sentinela"
  fi
fi
# O sentinela do mutante nasce na RAIZ (repo real): limpar e obrigatorio, senao a
# bateria deixa arquivo nao rastreado atras de si e o proximo git status mente.
rm -f "$SENTINELA"
rm -rf "$CAIXA_INJ"

echo
echo "== 9. reaberto_por e da maquina, e reaberto nao esta fechado (Issue #148) =="
# No fechamento do fluxo 6 (PR #147) um `marcar` recebeu `"reaberto_por": "texto"`
# pelo --json, gravou a string, e o `exigir` seguinte imprimiu 'undefined'. Pior:
# no MESMO estado o `exigir` recusava e o `marcar` fechava, porque so o `exigir`
# olhava o campo. Dois consertos, dois casos.
E9(){ RFM_ESTADO_ROOT="$W" node "$ESTADO" "$@"; }
rm -f "$S/docs/rainforest/estado/r148.json"; E9 iniciar --slug r148 >/dev/null 2>&1
exige 1 "reaberto_por pelo --json e recusado" E9 marcar --slug r148 --estagio design --status aprovado --json '{"reaberto_por":"texto livre"}'
exige_msg "Issue #148" "e a recusa diz de onde o campo vem" E9 marcar --slug r148 --estagio design --status aprovado --json '{"reaberto_por":"texto livre"}'
# Estado escrito direto no disco: executar "ok" E reaberto por reprovacao — a forma
# que a reabertura produz e que o `marcar` deixava passar como fechado.
node -e '
  const fs=require("fs"), p=process.argv[1];
  const e=JSON.parse(fs.readFileSync(p,"utf8"));
  e.design={status:"aprovado",em:"2026-09-02"}; e.plano={status:"ok",em:"2026-09-02"};
  e.executar={status:"ok",em:"2026-09-02",reaberto_por:{estagio:"verificar",data:"2026-09-02"}};
  e.revisar={status:"ok",em:"2026-09-02"};
  fs.writeFileSync(p,JSON.stringify(e,null,2));
' "$S/docs/rainforest/estado/r148.json"
L9="$(E9 listar 2>&1 | grep 'r148')"
if printf '%s' "$L9" | grep -q -- '-> executar'; then ok=$((ok+1)); echo "  ok    executar reaberto e o proximo, mesmo com status ok"; else falhou=$((falhou+1)); echo "  FALHA executar reaberto deveria ser o proximo; veio: $L9"; fi
exige 2 "verificar nao fecha por cima de executar reaberto" E9 marcar --slug r148 --estagio verificar --status ok --json '{"comando":"x","saida":"y"}'
exige 2 "e o exigir concorda com o marcar" E9 exigir --slug r148 --estagio verificar

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
