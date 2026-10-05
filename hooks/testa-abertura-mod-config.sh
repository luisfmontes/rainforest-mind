#!/bin/bash
# Bateria do lib/abertura-mod.cjs + abertura-mod.json — a configuracao fixa da abertura do mod.
# Uso: bash hooks/testa-abertura-mod-config.sh
#
# O que precisa provar, nesta ordem de importancia:
#   1. o JSON REAL do repo passa e a lib devolve os numeros do plano (alarme falso
#      numa configuracao correta e pior que trava nenhuma);
#   2. copia adulterada cuja soma das partes passa do total e RECUSADA, dizendo o
#      campo. As copias sao feitas para que SO a checagem de soma as pegue (todo o
#      resto da copia e valido) — senao a mutacao dessa linha nao mudaria nada;
#   3. regra sem arquivo e RECUSADA, dizendo o campo e a regra;
#   4. as demais recusas (orcamento das regras, total acima da soma, JSON ruim).
#
# A mutacao (inverter `if (soma > cfg.orcamentoTotalBytes) throw new Error(`) e
# rodada por `scripts/conferir-mutacao.cjs`; o caso 2 precisa ficar vermelho.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$SRC/hooks/lib/abertura-mod.cjs"
JSON_REAL="$SRC/hooks/abertura-mod.json"

SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

TMP_POSIX="$(novo_sandbox)"
TMP="$(cygpath -m "$TMP_POSIX" 2>/dev/null || printf '%s' "$TMP_POSIX")"

ok=0; falhou=0
passa() { ok=$((ok+1)); echo "  ok    $1"; }
falha() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# Driver: carrega o JSON dado pela lib; imprime `OK <json>` ou `RECUSA <mensagem>`.
rodar() {
  node -e "
const lib = require(process.argv[1]);
try { console.log('OK ' + JSON.stringify(lib.carregar(process.argv[2]))); }
catch (e) { console.log('RECUSA ' + e.message); }
" "$LIB" "$1"
}

# Copia do JSON real com um campo alterado: adulterar <arquivo> <expressao JS sobre c>.
adulterar() {
  node -e "
const fs = require('fs');
const c = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
$2
fs.writeFileSync(process.argv[2], JSON.stringify(c));
" "$JSON_REAL" "$3"
}

campo() { node -e "const r=JSON.parse(process.argv[1].slice(3));const v=process.argv[2].split('.').reduce((a,k)=>a[k],r);console.log(JSON.stringify(v))" "$1" "$2"; }

echo "1. o JSON real do repo passa"
SAIDA="$(rodar "$JSON_REAL")"
case "$SAIDA" in OK\ *) passa "o JSON real e aceito" ;; *) falha "o JSON real foi recusado: $SAIDA" ;; esac
[ "$(campo "$SAIDA" elaboracoes 2>/dev/null)" = "[16,12,11,17]" ] && passa "elaboracoes = [16,12,11,17]" || falha "elaboracoes diferente de [16,12,11,17]"
for par in regras:40960 foco:12288 memoria:8192 total:61440 elaboracoesBytes:31651 nucleoBytes:5914; do
  k="${par%%:*}"; v="${par##*:}"
  [ "$(campo "$SAIDA" "$k" 2>/dev/null)" = "$v" ] && passa "$k = $v" || falha "$k diferente de $v (veio $(campo "$SAIDA" "$k" 2>/dev/null))"
done
[ "$(campo "$SAIDA" regrasBytes 2>/dev/null)" = "37565" ] && passa "nucleo + elaboracoes = 37565 B, cabe em regras" || falha "regrasBytes diferente de 37565"
for n in 16 12 11 17; do
  arq="$(campo "$SAIDA" "arquivos.$n" 2>/dev/null | tr -d '"')"
  base="$(basename "$arq")"
  if [ "$base" = "regra-$n.md" ] && [ -f "$SRC/skills/rainforest-mind/references/$base" ]; then
    passa "regra $n resolve para $base, que existe"
  else
    falha "regra $n nao resolve para um regra-$n.md existente (veio '$arq')"
  fi
done

echo
echo "2. partes somam mais que o total declarado e recusado"
adulterar x "c.orcamentoTotalBytes = 61439;" "$TMP/soma-passa.json"
SAIDA="$(rodar "$TMP/soma-passa.json")"
case "$SAIDA" in
  RECUSA*orcamentoTotalBytes*) passa "partes somam mais que o total declarado e recusado, dizendo orcamentoTotalBytes" ;;
  *) falha "soma acima do total nao foi recusada pela checagem de soma: $SAIDA" ;;
esac

echo
echo "3. regra sem arquivo e recusada"
adulterar x "c.elaboracoes = [16, 12, 11, 99];" "$TMP/regra-sem-arquivo.json"
SAIDA="$(rodar "$TMP/regra-sem-arquivo.json")"
case "$SAIDA" in
  RECUSA*elaboracoes*99*) passa "regra 99 sem arquivo e recusada, dizendo elaboracoes e a regra" ;;
  *) falha "regra sem arquivo nao foi recusada com campo e regra: $SAIDA" ;;
esac

echo
echo "4. demais recusas"
adulterar x "c.orcamentoRegrasBytes = 30000; c.orcamentoTotalBytes = 30000 + c.orcamentoFocoBytes + c.orcamentoMemoriaBytes;" "$TMP/regras-estoura.json"
SAIDA="$(rodar "$TMP/regras-estoura.json")"
case "$SAIDA" in
  RECUSA*orcamentoRegrasBytes*) passa "nucleo + elaboracoes acima de orcamentoRegrasBytes e recusado" ;;
  *) falha "estouro do orcamento das regras nao recusado: $SAIDA" ;;
esac
adulterar x "c.orcamentoTotalBytes = 70000;" "$TMP/total-folga.json"
SAIDA="$(rodar "$TMP/total-folga.json")"
case "$SAIDA" in
  RECUSA*orcamentoTotalBytes*) passa "total acima da soma das partes e recusado" ;;
  *) falha "total com folga nao recusado: $SAIDA" ;;
esac
adulterar x "delete c.orcamentoFocoBytes;" "$TMP/sem-foco.json"
SAIDA="$(rodar "$TMP/sem-foco.json")"
case "$SAIDA" in
  RECUSA*orcamentoFocoBytes*) passa "campo ausente e recusado, dizendo o campo" ;;
  *) falha "campo ausente nao recusado: $SAIDA" ;;
esac
adulterar x "c.elaboracoes = [];" "$TMP/sem-elaboracoes.json"
SAIDA="$(rodar "$TMP/sem-elaboracoes.json")"
case "$SAIDA" in
  RECUSA*elaboracoes*) passa "elaboracoes vazia e recusada" ;;
  *) falha "elaboracoes vazia nao recusada: $SAIDA" ;;
esac
printf '{ nao e json' > "$TMP/quebrado.json"
SAIDA="$(rodar "$TMP/quebrado.json")"
case "$SAIDA" in
  RECUSA*) passa "JSON quebrado e recusado" ;;
  *) falha "JSON quebrado nao recusado: $SAIDA" ;;
esac

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
if [ "$falhou" = "0" ]; then echo "bateria passou"; else exit 1; fi
