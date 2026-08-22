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

# 3b: O CASO QUE JUSTIFICA A GUARDA. A bateria esta vermelha por conta propria e
# o padrao nao casa: sem a guarda o script sairia 0 e o agente colaria "mutei,
# ficou vermelho" com a mutacao nunca tendo acontecido.
exige 3 "padrao inexistente recusa MESMO com a bateria ja vermelha" \
  CHK --arquivo fonte.cjs --de 'process.exit(7);' --para 'process.exit(0);' --bateria 'bash bateria-quebrada.sh'
tem "e diz que a bateria nem rodou" "NAO foi executada"

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
  CHK --arquivo fonte.cjs --de 'process.exit(2);' --para 'process.exit(0);' --bateria 'bash bateria-stdin.sh'
tem "a bateria chegou ao fim do stdin" "li o stdin ate o fim"

exige 1 "bateria que estoura o teto nao vira veredito" \
  CHK --arquivo fonte.cjs --de 'process.exit(2);' --para 'process.exit(0);' \
      --bateria 'bash bateria-lenta.sh' --timeout 2000
tem "diz que ficou sem veredito" "SEM VEREDITO"
nao_tem "e nao aprova por estouro" "ok: bateria VERMELHA"

echo
echo "== 7. erro de uso: nunca silencioso, nunca 0 =="
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
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
