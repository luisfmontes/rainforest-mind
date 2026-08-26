#!/bin/bash
# Bateria do `conferir-mutacao.cjs` — a catraca de mutacao.
# Uso: bash scripts/testa-conferir-mutacao.sh
#
# Tarefa 3 do plano `docs/rainforest/planos/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.md` (D11).
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR. O script que ela cobre so tem valor
# enquanto souber dizer NAO em dois casos distintos, e o pior deles e' silencioso:
#
#   1. bateria VERDE com o comportamento invertido — o defeito medido em 10 de 18
#      entregas (obs 2026-08-17) e em 4 entregas seguidas do relatorio de
#      2026-08-19. Se este script parar de recusar aqui, ele vira carimbo.
#   2. padrao que NAO casa no fonte — a bateria pode estar vermelha por qualquer
#      outro motivo, e o resultado seria lido como prova (D11). Caso 3 abaixo e' o
#      unico lugar do repositorio onde essa confusao e' medida de proposito: a
#      bateria do fixture ja nasce vermelha, entao um script sem a guarda sairia
#      ZERO — veredito certo pelo motivo errado, que ninguem volta a olhar.
#
# Fixture PROPRIO, de proposito: os commits reais (53fa44d / 0272cdf) sao a prova
# de aceite da tarefa, e essa prova mora no registro da entrega. Aqui a bateria
# precisa rodar em qualquer maquina, em segundos, sem depender de commit nenhum
# continuar alcancavel.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/conferir-mutacao.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }

ok=0; falhou=0
S="$(mktemp -d)"; W="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")"
trap 'rm -rf "$S"' EXIT
CAIXA="$S/caixa"; WCAIXA="$W/caixa"
mkdir -p "$CAIXA"
SAIDA="$S/saida.txt"

# ------------------------------------------------------------------ o fixture
# Um fonte com UM comportamento observavel (recusar quando falta o campo) e um
# comentario. O comentario e' o alvo do caso 4: mutacao que casa e nao muda
# comportamento nenhum, que e' exatamente a forma da bateria fraca.
cat > "$CAIXA/fonte.cjs" <<'FONTE'
#!/usr/bin/env node
// Fixture: recusa quando o campo obrigatorio nao vem.
const campo = process.argv[2] || '';
if (campo === '') {
  console.error('RECUSADO: falta o campo');
  process.exit(2);
}
console.log('ok');
FONTE

# Bateria HONESTA: exige o caminho feliz E a recusa. Fica vermelha se a recusa
# virar aprovacao.
cat > "$CAIXA/bateria.sh" <<'BAT'
#!/bin/bash
f=0
node fonte.cjs valor >/dev/null 2>&1 || f=1
node fonte.cjs >/dev/null 2>&1; [ $? -eq 2 ] || f=1
echo "bateria do fixture: falhou=$f"
exit $f
BAT

# Bateria que ja nasce vermelha, sem relacao com o fonte. Serve so ao caso 3.
cat > "$CAIXA/bateria-quebrada.sh" <<'BAT'
#!/bin/bash
echo "esta bateria esta quebrada por conta propria"
exit 1
BAT

# Bateria que le stdin. Se o script herdasse o stdin do terminal, penduraria —
# incidente da secao 6 do relatorio de 2026-08-19, dez minutos perdidos.
cat > "$CAIXA/bateria-stdin.sh" <<'BAT'
#!/bin/bash
cat > /dev/null
echo "li o stdin ate o fim"
exit 1
BAT

# Bateria que espia o fonte enquanto roda: prova que o processo FILHO ve o
# arquivo ja mutado, e nao a versao original.
cat > "$CAIXA/bateria-espia.sh" <<'BAT'
#!/bin/bash
if grep -q 'MARCA-MUTADA' fonte.cjs; then echo "vi a marca"; exit 1; fi
echo "nao vi a marca"
exit 0
BAT

cat > "$CAIXA/bateria-lenta.sh" <<'BAT'
#!/bin/bash
sleep 20
exit 1
BAT

# Bateria inteligente para teste de timeout: baseline rapido, pos-mutacao lenta.
# Se arquivo tem a marca TIMEOUT-TEST-MARK, dorme e sai 1; senao sai 0 rapidamente.
cat > "$CAIXA/bateria-timeout.sh" <<'BAT'
#!/bin/bash
if grep -q 'TIMEOUT-TEST-MARK' fonte.cjs; then
  sleep 20
  exit 1
fi
exit 0
BAT

# Bateria que le stdin mas tem baseline verde: lê stdin e verifica arquivo.
# Se arquivo foi mutado (process.exit(2) desapareceu), sai 1.
# Senão sai 0. Prova que stdin é lido mesmo quando mutado.
cat > "$CAIXA/bateria-stdin-verde.sh" <<'BAT'
#!/bin/bash
cat > /dev/null  # le stdin ate EOF sem pendurar
if grep -q 'process.exit(2)' fonte.cjs; then
  echo "baseline: encontrou process.exit(2)"
  exit 0
else
  echo "mutacao detectada: process.exit(2) desapareceu"
  exit 1
fi
BAT

# Bateria que roda ~2s no baseline e morre em milissegundos quando há erro de shell.
# Usada no caso 10.
cat > "$CAIXA/bateria-lenta-ou-falha.sh" <<'BAT'
#!/bin/bash
# Se o arquivo contiver ERRO-MUTACAO (adicionada pela mutacao),
# sai quase instantaneamente com erro (simula corte de shell).
# Senao, dorme 5 segundos (simula trabalho) e sai com sucesso.
#
# Eram 2 segundos ate 2026-08-26. Subiu para 5 (#121) porque o caminho curto
# precisa ficar abaixo de 10% do baseline: com 2 s a folga era 200 ms, e spawn de
# bash + grep + exit sob carga passa disso. Com 5 s a folga e 500 ms.
if grep -q 'ERRO-MUTACAO' shell-lento.cjs; then
  exit 1
fi
sleep 5
exit 0
BAT

PRISTINO="$S/fonte.pristino"
cp "$CAIXA/fonte.cjs" "$PRISTINO"

# ----------------------------------------------------------------- utilidades
CHK(){ node "$SCRIPT" --raiz "$WCAIXA" "$@"; }

# exige <exit-esperado> <rotulo> <comando...>
# Toda chamada confere DUAS coisas: o exit code e a restauracao do fonte. A
# restauracao entra aqui, e nao em um caso proprio, porque um fonte deixado
# mutado envenena todos os casos seguintes — e no uso real envenena o commit.
# --- casos que ainda dependem de relogio -------------------------------------
# Os dois casos de ponta a ponta abaixo afirmam algo SOBRE TEMPO: um que o
# baseline ficou acima do piso, outro que ficou abaixo. Quando a maquina esta
# ocupada, o spawn de processo no Git Bash move a medida para o outro lado da
# fronteira e a afirmacao do caso deixa de ter pre-condicao — ele nao falhou,
# ele nao rodou. Reprovar ai e vermelho que nao aponta defeito nenhum, e vermelho
# assim e como se aprende a ignorar vermelho (#121).
#
# Entao: ANUNCIA, com a duracao medida e o limite, e nao conta como falha. O que
# a regra tem de fronteira ja esta provado no caso 9b, sem cronometro.
#
# O escape do anuncio esta fechado no fim do arquivo: pular OS DOIS na mesma
# execucao reprova o placar.
pulados_e2e=0
# O veredito do pulo duplo mora numa funcao para poder ser PROVADO com um numero,
# em vez de depender de a maquina estar ocupada na hora do teste. A primeira
# versao deixava isto solto no fim do arquivo e a catraca recusou, com razao:
# desligando a trava a bateria continuava verde, porque numa execucao normal
# pulados_e2e e 0 e o ramo nunca era exercitado (#121).
veredito_pulos() { [ "${1:-0}" -lt 2 ]; }
# Le "Baseline: NNNN ms" da saida do conferir-mutacao.cjs. Vazio se nao achou.
baseline_medido() { grep -oE 'Baseline: [0-9]+ ms' "$SAIDA" | grep -oE '[0-9]+' | head -1; }
# A pos-mutacao aparece em duas formas, conforme o ramo: "Mutação: NNNN ms" no
# caminho aprovado e "Pós-mutação: NNNN ms" no caminho da suspeita.
pos_medida() { grep -oE '(Mutação|Pós-mutação): [0-9]+ ms' "$SAIDA" | grep -oE '[0-9]+' | head -1; }
ultimo_pulou=0
# As assercoes que acompanham um caso e2e so fazem sentido se o caso RODOU. Se
# ele foi pulado, elas olham a saida de outro ramo e acusariam falha que nao
# existe — foi assim que a primeira versao desta entrega saiu `falhou: 3` sob
# carga, com a mesma cara do defeito que ela conserta.
tem_se_rodou()     { if [ "$ultimo_pulou" -eq 1 ]; then printf '         (assercao pulada junto: %s)
' "$1"; else tem "$@"; fi; }
nao_tem_se_rodou() { if [ "$ultimo_pulou" -eq 1 ]; then printf '         (assercao pulada junto: %s)
' "$1"; else nao_tem "$@"; fi; }
anuncia_pulo() {
  pulados_e2e=$((pulados_e2e+1))
  printf '  PULADO %s
' "$1"
  printf '         %s
' "$2"
  printf '         Isto NAO e falha: a pre-condicao de tempo do caso nao valeu.
'
  printf '         A fronteira da regra esta provada no caso 9b, sem cronometro.
'
}

# Como o `exige`, mas para os dois casos e2e de tempo: se o exit veio diferente
# do esperado E a duracao medida mostra que a pre-condicao do caso nao valeu,
# ANUNCIA em vez de contar falha. Se a pre-condicao valeu, e falha de verdade.
#   $3 = 'acima-do-piso' | 'abaixo-do-piso' — o que o caso PRECISA que tenha sido
#        verdade para a afirmacao dele fazer sentido.
exige_e2e(){
  local esperado="$1" rotulo="$2" precisa="$3"; shift 3
  ultimo_pulou=0
  "$@" > "$SAIDA" 2>&1
  local got=$? base; base="$(baseline_medido)"
  if [ "$got" -eq "$esperado" ]; then
    ok=$((ok+1)); printf '  ok    %s (exit=%s, baseline=%sms)
' "$rotulo" "$got" "${base:-?}"
  elif [ -n "$base" ] && [ "$precisa" = 'acima-do-piso' ] && [ "$base" -lt 1000 ]; then
    ultimo_pulou=1
    anuncia_pulo "$rotulo" "baseline medido ${base}ms, abaixo do piso de 1000ms — o caso precisa de baseline ACIMA"
  elif [ -n "$base" ] && [ -n "$(pos_medida)" ] && [ "$precisa" = 'acima-do-piso' ] && [ "$(( $(pos_medida) * 10 ))" -ge "$base" ]; then
    ultimo_pulou=1
    anuncia_pulo "$rotulo" "pos-mutacao $(pos_medida)ms contra baseline ${base}ms — passou dos 10%, o caso precisa de razao ABAIXO de 10%"
  elif [ -n "$base" ] && [ "$precisa" = 'abaixo-do-piso' ] && [ "$base" -ge 1000 ]; then
    ultimo_pulou=1
    anuncia_pulo "$rotulo" "baseline medido ${base}ms, no piso de 1000ms ou acima — o caso precisa de baseline ABAIXO"
  else
    falhou=$((falhou+1)); printf '  FALHA %s: esperado exit=%s, veio exit=%s (baseline=%sms)
' "$rotulo" "$esperado" "$got" "${base:-?}"
    sed 's/^/        | /' "$SAIDA" | tail -6
  fi
}

exige(){
  local esperado="$1" rotulo="$2"; shift 2
  "$@" > "$SAIDA" 2>&1
  local got=$?
  if [ "$got" -eq "$esperado" ]; then
    ok=$((ok+1)); printf '  ok    %s (exit=%s)\n' "$rotulo" "$got"
  else
    falhou=$((falhou+1)); printf '  FALHA %s: esperado exit=%s, veio exit=%s\n' "$rotulo" "$esperado" "$got"
    sed 's/^/        | /' "$SAIDA" | tail -6
  fi
  if ! cmp -s "$CAIXA/fonte.cjs" "$PRISTINO"; then
    falhou=$((falhou+1)); printf '  FALHA %s: o fonte NAO foi restaurado\n' "$rotulo"
    cp "$PRISTINO" "$CAIXA/fonte.cjs"
  else
    ok=$((ok+1)); printf '  ok    %s: fonte restaurado\n' "$rotulo"
  fi
}

tem(){ if grep -q -- "$2" "$SAIDA"; then ok=$((ok+1)); printf '  ok    %s\n' "$1";
       else falhou=$((falhou+1)); printf '  FALHA %s: nao achei %s na saida\n' "$1" "$2"; fi; }
nao_tem(){ if grep -q -- "$2" "$SAIDA"; then falhou=$((falhou+1)); printf '  FALHA %s: achei %s na saida\n' "$1" "$2";
           else ok=$((ok+1)); printf '  ok    %s\n' "$1"; fi; }

echo "(caixa de areia: $W)"

echo
echo "== 1. mutacao casou e bateria VERMELHA: o unico caminho que aprova =="
exige 0 "inverter a recusa deixa a bateria vermelha" \
  CHK --arquivo fonte.cjs --de 'process.exit(2);' --para 'process.exit(0);' --bateria 'bash bateria.sh'
tem "diz VERMELHA" "VERMELHA"
tem "conta as ocorrencias que casaram" "casou"

echo
echo "== 2. --para vazio apaga o trecho, e continua sendo mutacao =="
exige 0 "apagar a saida de recusa deixa a bateria vermelha" \
  CHK --arquivo fonte.cjs --de 'process.exit(2);' --para '' --bateria 'bash bateria.sh'

echo
echo "== 3. MUTACAO NAO APLICADA: a guarda do D11 =="
# 3a: padrao errado com bateria que passaria. Sem a guarda sairia 2 ("verde").
exige 3 "padrao inexistente recusa, com bateria verde" \
  CHK --arquivo fonte.cjs --de 'process.exit(7);' --para 'process.exit(0);' --bateria 'bash bateria.sh'
tem "usa a mensagem literal do precedente" "MUTACAO NAO APLICADA"
nao_tem "e nunca chama isso de bateria vermelha" "VERMELHA"

# 3b: O CASO QUE JUSTIFICA A GUARDA. A bateria esta vermelha por conta propria:
# com a verificacao de baseline, sai 4 (baseline nao-verde) antes de chegar ao
# padrão não-aplicado.
exige 4 "bateria ja vermelha recusa com baseline nao-verde" \
  CHK --arquivo fonte.cjs --de 'process.exit(7);' --para 'process.exit(0);' --bateria 'bash bateria-quebrada.sh'
tem "e diz que baseline nao-verde" "baseline NAO-VERDE"

echo
echo "== 4. bateria VERDE com o comportamento invertido: recusa =="
exige 2 "mutar comentario nao deixa a bateria vermelha, e isso reprova" \
  CHK --arquivo fonte.cjs --de '// Fixture: recusa quando o campo obrigatorio nao vem.' \
      --para '// Fixture: comentario trocado, comportamento identico.' --bateria 'bash bateria.sh'
tem "diz VERDE" "bateria VERDE"

echo
echo "== 5. o processo filho ve o fonte JA mutado =="
exige 0 "a bateria enxerga a marca escrita pela mutacao" \
  CHK --arquivo fonte.cjs --de '// Fixture: recusa' --para '// MARCA-MUTADA' --bateria 'bash bateria-espia.sh'
tem "a espia confirma que viu" "vi a marca"

echo
echo "== 6. stdin fechado e teto de tempo =="
exige 0 "bateria que le stdin recebe EOF em vez de pendurar" \
  CHK --arquivo fonte.cjs --de 'process.exit(2);' --para 'process.exit(0);' --bateria 'bash bateria-stdin-verde.sh'
tem "a bateria detectou a mutacao" "mutacao detectada"

exige 1 "bateria que estoura o teto nao vira veredito" \
  CHK --arquivo fonte.cjs --de 'const campo' --para 'const campo // TIMEOUT-TEST-MARK' \
      --bateria 'bash bateria-timeout.sh' --timeout 2000
tem "diz que ficou sem veredito" "SEM VEREDITO"
nao_tem "e nao aprova por estouro" "ok: bateria VERMELHA"

echo
echo "== 7. baseline não-verde: bateria que já falha no fonte íntegro =="
exige 4 "bateria que ja falha recusa com exit=4" \
  CHK --arquivo fonte.cjs --de 'process.exit(2);' --para 'process.exit(0);' --bateria 'bash bateria-quebrada.sh'
tem "diz que baseline nao-verde" "baseline NAO-VERDE"
nao_tem "e nao rodou a mutacao" "casou"

exige 3 "padrao que nao casa com bateria VERDE recusa com exit=3" \
  CHK --arquivo fonte.cjs --de 'process.exit(9);' --para 'process.exit(0);' --bateria 'bash bateria.sh'
tem "diz MUTACAO NAO APLICADA" "MUTACAO NAO APLICADA"

echo
echo "== 8. múltiplas ocorrências: padrão que casa mais de uma vez =="
# Criaremos um fixture com uma sequência que aparece exatamente duas vezes
cat > "$CAIXA/multi.cjs" <<'FONTE'
const a = 'MARK';
const b = 'MARK';
FONTE
cp "$CAIXA/multi.cjs" "$S/multi.pristino"

exige 4 "padrão que casa 2 vezes recusa com exit=4" \
  CHK --arquivo multi.cjs --de 'MARK' --para 'NOVO' --bateria 'bash bateria.sh'
tem "diz que casa multiplas vezes" "casa 2"
tem "recusa" "RECUSADO"
nao_tem "nao diz VERMELHA" "VERMELHA"

if ! cmp -s "$CAIXA/multi.cjs" "$S/multi.pristino"; then
  falhou=$((falhou+1)); printf '  FALHA: multi.cjs nao foi restaurado apos recusa\n'
  cp "$S/multi.pristino" "$CAIXA/multi.cjs"
else
  ok=$((ok+1)); printf '  ok    multi.cjs restaurado apos recusa\n'
fi

echo
echo "== 9. erro de uso: nunca silencioso, nunca 0 =="
exige 1 "sem argumento nenhum imprime o uso" node "$SCRIPT"
tem "o uso nomeia --arquivo" "--arquivo"
tem "o uso nomeia --de"      "--de "
tem "o uso nomeia --para"    "--para "
tem "o uso nomeia --bateria" "--bateria"

exige 1 "--de igual a --para recusa (nao inverte nada)" \
  CHK --arquivo fonte.cjs --de 'process.exit(2);' --para 'process.exit(2);' --bateria 'bash bateria.sh'
exige 1 "--de vazio recusa" \
  CHK --arquivo fonte.cjs --de '' --para 'x' --bateria 'bash bateria.sh'
exige 1 "arquivo inexistente recusa" \
  CHK --arquivo nao-existe.cjs --de 'a' --para 'b' --bateria 'bash bateria.sh'
exige 1 "falta --bateria recusa" \
  CHK --arquivo fonte.cjs --de 'a' --para 'b'

echo
echo "== 9b. a fronteira do piso e da razao, sem cronometro nenhum =="
# Estes casos chamam a decisao DIRETO, com numeros fixos. Existem porque os casos
# 10 e 12 abaixo dependem de relogio de parede, e relogio sob carga move o
# veredito: em 2026-08-26 duas varreduras da MESMA arvore deram placares
# diferentes, uma com esta bateria vermelha e outra com zero vermelhas (#121).
# Fronteira se prova com entrada. O que sobra de cronometro nos casos 10 e 12 e
# so a prova de que o fio inteiro liga.
# `cygpath -m` porque o node no Windows nao resolve caminho POSIX do Git Bash:
# require('/c/...') sai `Cannot find module`. O -m devolve C:/... com barra
# normal, que o node aceita e o bash nao estraga com escape.
SCRIPT_WIN="$(cygpath -m "$SCRIPT")"
puro() { node -e "process.stdout.write(String(require('$SCRIPT_WIN').suspeitaDeCorte($1, $2)))"; }
igual_puro() {
  local rotulo="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then ok=$((ok+1)); printf '  ok    %s
' "$rotulo"
  else falhou=$((falhou+1)); printf '  FALHA %s (esperava %s, veio %s)
' "$rotulo" "$want" "$got"; fi
}
igual_puro "a fronteira do piso: 1000 dispara, 999 nao (999)" "$(puro 999 50)"    "false"
igual_puro "a fronteira do piso: 1000 dispara, 999 nao (1000)" "$(puro 1000 99)"  "true"
igual_puro "a fronteira da razao: 10% exato NAO dispara"       "$(puro 1000 100)" "false"
igual_puro "a fronteira da razao: um abaixo de 10% dispara"    "$(puro 1000 99)"  "true"
igual_puro "baseline longo, pos folgada: nao dispara"          "$(puro 5000 600)" "false"
igual_puro "baseline longo, pos curtissima: dispara"           "$(puro 5000 499)" "true"
igual_puro "pos igual ao baseline: nunca dispara"              "$(puro 5000 5000)" "false"
igual_puro "baseline zero: nao dispara"                        "$(puro 0 0)"      "false"

echo
echo "== 9c. a trava do pulo duplo, provada com numero =="
for n in 0 1; do
  if veredito_pulos "$n"; then ok=$((ok+1)); printf '  ok    %s pulo(s) nao reprova
' "$n"
  else falhou=$((falhou+1)); printf '  FALHA %s pulo(s) reprovou e nao devia
' "$n"; fi
done
for n in 2 3; do
  if veredito_pulos "$n"; then falhou=$((falhou+1)); printf '  FALHA %s pulos passou e nao devia
' "$n"
  else ok=$((ok+1)); printf '  ok    %s pulos reprova
' "$n"; fi
done

echo "== 9d. o anuncio esta LIGADO nos casos e2e, e anuncia em vez de reprovar =="
# Duas provas, e as duas precisam existir.
#
# (a) COMPORTAMENTO: chamo exige_e2e com uma saida fabricada em que a
#     pre-condicao de tempo NAO vale, e exijo que ela ANUNCIE em vez de contar
#     falha. Deterministico — nao depende de a maquina estar ocupada.
#
# (b) FIACAO: confiro que os casos 10 e 12 chamam exige_e2e, e nao o exige puro.
#     Isto e grep de fonte, que normalmente nao prova nada — aqui prova a UNICA
#     coisa que (a) nao alcanca. Na primeira versao desta entrega o exige_e2e
#     ficou definido e nunca chamado: mecanismo inteiro morto, bateria verde, e
#     sob carga ela saiu `falhou: 3` com a mesma cara do defeito que conserta.
falso_conferidor() {
  # Finge o conferir-mutacao.cjs: imprime um baseline ABAIXO do piso e sai 0.
  printf 'ok: bateria VERMELHA com o comportamento invertido (exit 1).
'
  printf '    Baseline: 500 ms (exit 0) → Mutação: 40 ms (exit 1)
'
  return 0
}
antes_ok=$ok; antes_falhou=$falhou; antes_pulos=$pulados_e2e
exige_e2e 5 "fixture: baseline abaixo do piso quando o caso precisa de ACIMA" acima-do-piso falso_conferidor
if [ "$falhou" -eq "$antes_falhou" ] && [ "$pulados_e2e" -eq "$((antes_pulos+1))" ]; then
  ok=$((ok+1)); printf '  ok    anunciou em vez de reprovar, e contou o pulo
'
else
  falhou=$((falhou+1)); printf '  FALHA devia anunciar: falhou %s->%s, pulos %s->%s
' "$antes_falhou" "$falhou" "$antes_pulos" "$pulados_e2e"
fi
pulados_e2e=$antes_pulos; ultimo_pulou=0   # o fixture nao suja o contador real

for alvo in 'pós-mutação curta demais' 'baseline < 1s não dispara'; do
  if grep -F "$alvo" "$0" | grep -q '^exige_e2e '; then
    ok=$((ok+1)); printf '  ok    o caso "%s" chama exige_e2e
' "$alvo"
  else
    falhou=$((falhou+1)); printf '  FALHA o caso "%s" NAO chama exige_e2e — o anuncio esta desligado
' "$alvo"
  fi
done

echo "== 10. suspeita de corte de shell: pós-mutação desproporcionalmente curta =="
# Fixture que simula o defeito de 2026-08-24: baseline ~2s, pós-mutação morre em ~10ms
cat > "$CAIXA/shell-lento.cjs" <<'FONTE'
#!/usr/bin/env node
const valor = process.argv[2] || '';
console.log('ok');
FONTE
cp "$CAIXA/shell-lento.cjs" "$S/shell-lento.pristino"

exige_e2e 5 "pós-mutação curta demais (< 10% baseline) dispara exit=5" acima-do-piso \
  CHK --arquivo shell-lento.cjs --de "console.log('ok');" \
      --para "console.log('ERRO-MUTACAO'); console.log('ok');" \
      --bateria 'bash bateria-lenta-ou-falha.sh' --timeout 15000
tem_se_rodou "relata SUSPEITA DE CORTE DE SHELL" "SUSPEITA DE CORTE"
tem_se_rodou "mostra as duas duracoes" "Baseline:"
tem_se_rodou "diz como confirmar" "Confirme rodando"

if ! cmp -s "$CAIXA/shell-lento.cjs" "$S/shell-lento.pristino"; then
  falhou=$((falhou+1)); printf '  FALHA: shell-lento.cjs nao foi restaurado apos recusa\n'
  cp "$S/shell-lento.pristino" "$CAIXA/shell-lento.cjs"
else
  ok=$((ok+1)); printf '  ok    shell-lento.cjs restaurado apos recusa\n'
fi

echo
echo "== 12. baseline abaixo do piso absoluto (1000ms) — heurística não dispara =="
# Bateria que roda rápido (~100ms) no baseline. Mesmo que pós-mutação saia em ~10ms
# (razão 0.1 = 10%), o baseline abaixo de 1s faz a heurística NÃO disparar.
cat > "$CAIXA/bateria-rapida.sh" <<'BAT'
#!/bin/bash
# Se tem marca, sai quase instantaneamente com erro; senao, sai rápido em 100ms
if grep -q 'MARCA-RÁPIDO' fonte-rapida.cjs; then
  exit 1
fi
sleep 0.1
exit 0
BAT

cat > "$CAIXA/fonte-rapida.cjs" <<'FONTE'
#!/usr/bin/env node
const x = 1;
FONTE
cp "$CAIXA/fonte-rapida.cjs" "$S/fonte-rapida.pristino"

exige_e2e 0 "baseline < 1s não dispara heurística mesmo com razão 0.1" abaixo-do-piso \
  CHK --arquivo fonte-rapida.cjs --de "const x = 1;" --para "const x = 1; // MARCA-RÁPIDO" \
      --bateria 'bash bateria-rapida.sh' --timeout 5000
tem_se_rodou "aprova normalmente" "ok: bateria VERMELHA"
nao_tem_se_rodou "não reclama de corte" "SUSPEITA"
tem_se_rodou "baseline e pós no log" "Baseline:"

if ! cmp -s "$CAIXA/fonte-rapida.cjs" "$S/fonte-rapida.pristino"; then
  falhou=$((falhou+1)); printf '  FALHA: fonte-rapida.cjs nao foi restaurado apos mutacao\n'
  cp "$S/fonte-rapida.pristino" "$CAIXA/fonte-rapida.cjs"
else
  ok=$((ok+1)); printf '  ok    fonte-rapida.cjs restaurado apos mutacao\n'
fi

echo
echo "== 13. bateria VERDE e rápida: o 2 vence o 5, e a ordem é o que decide =="
# A heurística de corte de shell (caso 10) e a recusa por bateria verde (caso 4)
# podem disparar na MESMA execução: pós-mutação verde E desproporcionalmente
# rápida. O veredito correto é 2 — "esta bateria não mede o conserto" — porque
# bateria que aprovou o fonte invertido já está condenada, e a duração não muda
# isso. O 5 diria "a bateria saiu != 0, mas rápido demais", afirmando sobre a
# execução algo que não aconteceu.
#
# Este caso existe porque a primeira versão da heurística ficava ANTES do ramo
# do exit 2 e devolvia 5 aqui. Inverter a ordem é o conserto; sem este caso,
# alguém inverte de novo e a suíte não acusa.
cat > "$CAIXA/bateria-verde-rapida.sh" <<'BAT'
#!/bin/bash
# Com a marca (fonte mutado): sai VERDE quase instantaneamente.
# Sem a marca (baseline): sai VERDE, porém devagar — acima do piso de 1 s.
if grep -q 'MARCA-VERDE-RAPIDO' fonte-verde.cjs; then
  exit 0
fi
sleep 2
exit 0
BAT

cat > "$CAIXA/fonte-verde.cjs" <<'FONTE'
#!/usr/bin/env node
const y = 2;
FONTE
cp "$CAIXA/fonte-verde.cjs" "$S/fonte-verde.pristino"

exige 2 "verde e rápida recusa por bateria VERDE (2), não por corte de shell (5)" \
  CHK --arquivo fonte-verde.cjs --de "const y = 2;" --para "const y = 2; // MARCA-VERDE-RAPIDO" \
      --bateria 'bash bateria-verde-rapida.sh' --timeout 10000
tem "acusa a bateria verde" "RECUSADO: bateria VERDE"
nao_tem "não confunde com corte de shell" "SUSPEITA DE CORTE"

if ! cmp -s "$CAIXA/fonte-verde.cjs" "$S/fonte-verde.pristino"; then
  falhou=$((falhou+1)); printf '  FALHA: fonte-verde.cjs nao foi restaurado apos recusa\n'
  cp "$S/fonte-verde.pristino" "$CAIXA/fonte-verde.cjs"
else
  ok=$((ok+1)); printf '  ok    fonte-verde.cjs restaurado apos recusa\n'
fi

echo
# O escape do anuncio se fecha aqui. Um caso e2e pulado e a maquina ocupada; os
# DOIS pulados na mesma execucao e a maquina ocupada demais para essa medicao
# significar alguma coisa, e isso tem de parar o placar — senao "anuncia em vez
# de reprovar" vira "nunca reprova".
if ! veredito_pulos "$pulados_e2e"; then
  falhou=$((falhou+1))
  printf '  FALHA os DOIS casos e2e de tempo foram pulados na mesma execucao
'
  printf '        a maquina estava ocupada demais para esta medicao valer — rode de novo com a maquina livre
'
else
  ok=$((ok+1)); printf '  ok    pular os dois e2e na mesma execucao reprova (pulados=%s)
' "$pulados_e2e"
fi

echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
