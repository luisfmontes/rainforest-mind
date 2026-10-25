#!/bin/bash
# Bateria da leitura do placar pela catraca de mutacao (conferir-mutacao.cjs:
# extrairPlacar e mediuEFalhou) — Issue #589 e a forma `falha(s)` das baterias do repo.
# Uso: bash scripts/testa-conferir-mutacao-placar.sh
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR. A catraca le o placar que a bateria imprime.
# Se le errado, ou nao le, erra para os dois lados:
#
#   1. vermelho legitimo lido como corte de shell (#589: cargo test, 12 mutacoes
#      legitimas sairam `pulada (suspeita de corte de shell)` e travaram o verificar);
#   2. colapso lido como vermelho (bateria que morre sem placar, na forma `falha(s)`,
#      aprovada como mutacao pega).
#
# Os casos 1 a 6 chamam extrairPlacar e mediuEFalhou direto (o modulo exporta os dois).
# Os casos 7 a 9 rodam o conferir-mutacao.cjs de verdade, numa caixa de areia.

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

# PLACAR <texto>: imprime "ok falhou" ou "null", pelo extrairPlacar do modulo.
PLACAR(){ node -e 'const m = require(process.argv[1]); const p = m.extrairPlacar(process.argv[2]); process.stdout.write(p === null ? "null" : p.ok + " " + p.falhou);' "$SCRIPT" "$1"; }
# MEDIU <texto>: imprime true/false, pelo mediuEFalhou do modulo.
MEDIU(){ node -e 'const m = require(process.argv[1]); process.stdout.write(String(m.mediuEFalhou(process.argv[2])));' "$SCRIPT" "$1"; }

# conf <rotulo> <esperado> <obtido>
conf(){
  if [ "$2" = "$3" ]; then ok=$((ok+1)); printf '  ok    %s (%s)\n' "$1" "$3"
  else falhou=$((falhou+1)); printf '  FALHA %s: esperava [%s], veio [%s]\n' "$1" "$2" "$3"; fi
}

echo "== 1. formas do repo: caixa livre, falha(s), falhas, vírgula opcional, igual =="
conf "== resultado: 3 ok, 2 falha(s) == é lido como ok 3 falhou 2" "3 2" "$(PLACAR '== resultado: 3 ok, 2 falha(s) ==')"
conf "Resumo: 3 ok, 2 falhas" "3 2" "$(PLACAR 'Resumo: 3 ok, 2 falhas')"
conf "Resultado: 3 OK, 2 FALHA" "3 2" "$(PLACAR 'Resultado: 3 OK, 2 FALHA')"
conf "== Resultado: 3 ok   2 falha(s) == (sem vírgula)" "3 2" "$(PLACAR '== Resultado: 3 ok   2 falha(s) ==')"
conf "ok=3 falhou=2" "3 2" "$(PLACAR 'ok=3 falhou=2')"

echo "== 2. formas que já eram lidas continuam lidas =="
conf "ok: 3   falhou: 2" "3 2" "$(PLACAR 'ok: 3   falhou: 2')"
conf "3 ok, 2 falhou" "3 2" "$(PLACAR '3 ok, 2 falhou')"

echo "== 3. a última ocorrência por posição, qualquer forma =="
conf "ok: 9 falhou: 0 no meio, 1 ok, 4 falha(s) na última" "1 4" "$(PLACAR $'ok: 9   falhou: 0\nsub-bateria\n1 ok, 4 falha(s)')"
conf "1 ok, 4 falha(s) no meio, ok=2 falhou=0 na última" "2 0" "$(PLACAR $'1 ok, 4 falha(s)\nsub-bateria\nok=2 falhou=0')"

echo "== 4. libtest do Rust: soma dos passed e dos failed =="
conf "duas linhas test result: ok. 7 passed e FAILED. 0 passed; 1 failed" "7 1" "$(PLACAR $'test result: ok. 7 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\ntest result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out')"
conf "placar do repo vence o libtest quando os dois aparecem" "2 0" "$(PLACAR $'test result: ok. 9 passed; 0 failed\n== resultado: 2 ok, 0 falha(s) ==')"

echo "== 5. sem placar nenhum =="
conf "saída sem placar" "null" "$(PLACAR 'quebrou antes de qualquer placar')"
conf "saída vazia" "null" "$(PLACAR '')"

echo "== 6. mediuEFalhou: prova de que a bateria chegou a medir =="
conf "libtest com 1 failed mede (#589)" "true" "$(MEDIU 'test result: FAILED. 0 passed; 1 failed; 0 ignored')"
conf "placar do repo com falha(s) mede" "true" "$(MEDIU '== resultado: 0 ok, 1 falha(s) ==')"
conf "placar do repo sem falha não mede" "false" "$(MEDIU '== resultado: 3 ok, 0 falha(s) ==')"
conf "libtest sem falha não mede" "false" "$(MEDIU 'test result: ok. 3 passed; 0 failed; 0 ignored')"
conf "crash sem placar não mede" "false" "$(MEDIU 'ReferenceError: x is not defined')"

# ------------------------------------------------------------------ a caixa
# Rodadas reais do conferir-mutacao.cjs. Fonte de uma linha; a mutacao so acrescenta
# um comentario com uma marca, e a bateria le a marca no fonte que ela ve.
cat > "$CAIXA/fonte-589.cjs" <<'FONTE'
const w = 4;
FONTE
cp "$CAIXA/fonte-589.cjs" "$S/fonte-589.pristino"
cat > "$CAIXA/fonte-falha.cjs" <<'FONTE'
const w = 4;
FONTE
cp "$CAIXA/fonte-falha.cjs" "$S/fonte-falha.pristino"
cat > "$CAIXA/fonte-col.cjs" <<'FONTE'
const w = 4;
FONTE
cp "$CAIXA/fonte-col.cjs" "$S/fonte-col.pristino"

CHK(){ node "$SCRIPT" --raiz "$WCAIXA" "$@"; }

# exige <esperado> <rotulo> <alvo> <pristino> <comando...>
# Confere o exit e que o fonte foi restaurado (um fonte deixado mutado envenena o caso seguinte).
exige(){
  local esperado="$1" rotulo="$2" alvo="$3" pristino="$4"; shift 4
  "$@" > "$SAIDA" 2>&1
  local got=$?
  if [ "$got" -eq "$esperado" ]; then ok=$((ok+1)); printf '  ok    %s (exit=%s)\n' "$rotulo" "$got"
  else falhou=$((falhou+1)); printf '  FALHA %s: esperado exit=%s, veio exit=%s\n' "$rotulo" "$esperado" "$got"
    sed 's/^/        | /' "$SAIDA" | tail -6
  fi
  if ! cmp -s "$CAIXA/$alvo" "$S/$pristino"; then
    falhou=$((falhou+1)); printf '  FALHA %s: o fonte NAO foi restaurado\n' "$rotulo"
    cp "$S/$pristino" "$CAIXA/$alvo"
  fi
}
tem(){ if grep -q -- "$2" "$SAIDA"; then ok=$((ok+1)); printf '  ok    %s\n' "$1";
       else falhou=$((falhou+1)); printf '  FALHA %s: nao achei %s na saida\n' "$1" "$2"; fi; }
nao_tem(){ if grep -q -- "$2" "$SAIDA"; then falhou=$((falhou+1)); printf '  FALHA %s: achei %s na saida\n' "$1" "$2";
           else ok=$((ok+1)); printf '  ok    %s\n' "$1"; fi; }

# ------------------------------------------------------------------ casos de ponta a ponta
echo
echo "== 7. #589: baseline lento e libtest nos dois lados, pós-mutação rápida com FAILED =="
# Espelha o cargo test do NEXO: o baseline demora (>= 1 s, o piso da suspeita) e imprime
# o placar do libtest; a pos-mutacao e' rapida e imprime o vermelho do libtest. Com o
# extrairPlacar antigo o baseline nao tinha placar, nao havia colapso, e a suspeita de
# corte pegava a mutacao legitima (exit 5). Com o placar lido, sai vermelha (exit 0).
cat > "$CAIXA/bateria-589.sh" <<'BAT'
#!/bin/bash
if grep -q 'MUTADA-589' fonte-589.cjs; then
  echo "test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.23s"
  exit 101
fi
sleep 8
echo "test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 8.00s"
exit 0
BAT
exige 0 "libtest vermelho legítimo com baseline lento sai vermelho, não corte" \
  fonte-589.cjs fonte-589.pristino \
  CHK --arquivo fonte-589.cjs --de 'const w = 4;' --para 'const w = 4; // MUTADA-589' --bateria 'bash bateria-589.sh'
tem "diz VERMELHA" "VERMELHA"
nao_tem "não chama de corte de shell" "suspeita de corte"

echo
echo "== 8. colapso na forma falha(s): mutada morre sem placar, baseline com placar =="
cat > "$CAIXA/bateria-col.sh" <<'BAT'
#!/bin/bash
if grep -q 'CRASH-FALHA-S' fonte-col.cjs; then
  echo "node:internal/modules/cjs/loader: ReferenceError: x is not defined"
  exit 1
fi
echo "== resultado: 2 ok, 0 falha(s) =="
exit 0
BAT
exige 6 "crash sem placar com baseline em falha(s) é colapso" \
  fonte-col.cjs fonte-col.pristino \
  CHK --arquivo fonte-col.cjs --de 'const w = 4;' --para 'const w = 4; // CRASH-FALHA-S' --bateria 'bash bateria-col.sh'
tem "informa o colapso" "a bateria colapsou"
tem "diz que o placar sumiu" "placar ausente"

echo
echo "== 9. vermelho legítimo na forma falha(s) com baseline lento sai vermelho =="
cat > "$CAIXA/bateria-falha.sh" <<'BAT'
#!/bin/bash
if grep -q 'MUTADA-FALHA' fonte-falha.cjs; then
  echo "== resultado: 0 ok, 1 falha(s) =="
  exit 1
fi
sleep 8
echo "== resultado: 1 ok, 0 falha(s) =="
exit 0
BAT
exige 0 "vermelho com placar em falha(s) e baseline lento sai vermelho, não corte" \
  fonte-falha.cjs fonte-falha.pristino \
  CHK --arquivo fonte-falha.cjs --de 'const w = 4;' --para 'const w = 4; // MUTADA-FALHA' --bateria 'bash bateria-falha.sh'
tem "diz VERMELHA" "VERMELHA"

echo "-----------------------------------------"
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
