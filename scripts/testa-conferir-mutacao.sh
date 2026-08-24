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
# Senao, dorme 2 segundos (simula trabalho) e sai com sucesso.
if grep -q 'ERRO-MUTACAO' shell-lento.cjs; then
  exit 1
fi
sleep 2
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
echo "== 10. suspeita de corte de shell: pós-mutação desproporcionalmente curta =="
# Fixture que simula o defeito de 2026-08-24: baseline ~2s, pós-mutação morre em ~10ms
cat > "$CAIXA/shell-lento.cjs" <<'FONTE'
#!/usr/bin/env node
const valor = process.argv[2] || '';
console.log('ok');
FONTE

exige 5 "pós-mutação curta demais (< 10% baseline) dispara exit=5" \
  CHK --arquivo shell-lento.cjs --de "console.log('ok');" \
      --para "console.log('ERRO-MUTACAO'); console.log('ok');" \
      --bateria 'bash bateria-lenta-ou-falha.sh' --timeout 5000
tem "relata SUSPEITA DE CORTE DE SHELL" "SUSPEITA DE CORTE"
tem "mostra as duas duracoes" "Baseline:"
tem "diz como confirmar" "Confirme rodando"

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

exige 0 "baseline < 1s não dispara heurística mesmo com razão 0.1" \
  CHK --arquivo fonte-rapida.cjs --de "const x = 1;" --para "const x = 1; // MARCA-RÁPIDO" \
      --bateria 'bash bateria-rapida.sh' --timeout 5000
tem "aprova normalmente" "ok: bateria VERMELHA"
nao_tem "não reclama de corte" "SUSPEITA"
tem "baseline e pós no log" "Baseline:"

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

exige 2 "verde e rápida recusa por bateria VERDE (2), não por corte de shell (5)" \
  CHK --arquivo fonte-verde.cjs --de "const y = 2;" --para "const y = 2; // MARCA-VERDE-RAPIDO" \
      --bateria 'bash bateria-verde-rapida.sh' --timeout 10000
tem "acusa a bateria verde" "RECUSADO: bateria VERDE"
nao_tem "não confunde com corte de shell" "SUSPEITA DE CORTE"

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
