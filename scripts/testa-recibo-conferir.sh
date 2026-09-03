#!/bin/bash
# Bateria de testes para `recibo.cjs conferir`.
# Uso: bash scripts/testa-recibo-conferir.sh
#
# Tarefa 4 do plano `docs/rainforest/planos/2026-09-02-fluxo-7-recibo.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR:
#
#   1. Que `conferir` ignore entregáveis ausentes. Arquivo que sumiu depois da
#      gravação precisa ser reportado.
#
#   2. Que `conferir` aprove um arquivo que mudou de conteúdo. Troca de caractere
#      por outro do mesmo tamanho é a mutação mais fácil de cometer sem querer,
#      e deve ser detectada pelo hash mesmo com bytes iguais.
#
#   3. Que `conferir` saia com sucesso quando não há recibo. Ausência de recibo é
#      pré-condição impeditiva — não é "tudo bem, continue".

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECIBO="$RAIZ/scripts/recibo.cjs"
FIX="$RAIZ/test/fixtures/recibo"

[ -f "$RECIBO" ] || { echo "FALHA: nao achei $RECIBO"; exit 1; }

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/docs/rainforest/estado" "$S/docs/rainforest/colheita"

afirma() {
  local nome="$1" cond="$2"
  if [ "$cond" = "1" ]; then echo "  ok   $nome"; ok=$((ok+1));
  else echo "  FALHA $nome"; falhou=$((falhou+1)); fi
}

# Roda o recibo.cjs numa raiz-sandbox. `cd "$RAIZ"` de proposito: o confinamento
# por realpath usa RAIZ REAL, e e' assim que roda em producao — o script nao muda
# o cwd de quem o chamou.
rec() { (cd "$RAIZ" && RFM_ESTADO_ROOT="$S" node "$RECIBO" "$@" 2>&1); }

echo "== T4a. sem recibo gravado: exit 2, stderr contem 'nada para conferir' =="
cat > "$S/docs/rainforest/estado/sem-recibo.json" <<FIM
{
  "slug": "sem-recibo",
  "plano": {}
}
FIM
SAIDA="$(rec conferir sem-recibo)"; C=$?
afirma "T4a1. exit 2" "$([ "$C" -eq 2 ] && echo 1 || echo 0)"
afirma "T4a2. stderr contem 'nada para conferir'" \
  "$(printf '%s' "$SAIDA" | grep -q "nada para conferir" && echo 1 || echo 0)"

echo "== T4b. recibo gravado, entregaveis intactos: exit 0, stdout contem 'intacto' =="
mkdir -p "$S/docs/a-gravar"
echo "conteudo arquivo um" > "$S/docs/a-gravar/um.md"
echo "conteudo arquivo dois com mais texto" > "$S/docs/a-gravar/dois.cjs"

cat > "$S/docs/rainforest/estado/intacto.json" <<FIM
{
  "slug": "intacto",
  "plano": {
    "entregaveis": ["docs/a-gravar/um.md", "docs/a-gravar/dois.cjs"]
  }
}
FIM

# Primeiro, grava o recibo
SAIDA_GRAVA="$(rec gravar --slug intacto --nao-provado '["revisao visual","comportamento em producao"]')"; C_GRAVA=$?
afirma "T4b1. gravar retorna exit 0" "$([ "$C_GRAVA" -eq 0 ] && echo 1 || echo 0)"

# Depois, confere
SAIDA="$(rec conferir intacto)"; C=$?
afirma "T4b2. conferir exit 0" "$([ "$C" -eq 0 ] && echo 1 || echo 0)"
afirma "T4b3. stdout contem 'intacto'" \
  "$(printf '%s' "$SAIDA" | grep -q "intacto" && echo 1 || echo 0)"

echo "== T4c. entregavel editado, mesmo tamanho: exit 1, stderr nomeia arquivo e tamanho IDENTICO =="
# Cria arquivo com mesmo tamanho mas conteúdo diferente
# Original: "conteudo arquivo um" = 20 bytes
# Novo:     "conbexdo arquivo vm." = 20 bytes (trocando c,u,d,um por x,v,.)
printf "conbexdo arquivo um." > "$S/docs/a-gravar/um.md"

SAIDA="$(rec conferir intacto)"; C=$?
afirma "T4c1. exit 1" "$([ "$C" -eq 1 ] && echo 1 || echo 0)"
afirma "T4c2. stderr nomeia arquivo" \
  "$(printf '%s' "$SAIDA" | grep -q "docs/a-gravar/um.md" && echo 1 || echo 0)"
afirma "T4c3. stderr menciona 'tamanho IDENTICO'" \
  "$(printf '%s' "$SAIDA" | grep -q "tamanho IDENTICO" && echo 1 || echo 0)"
afirma "T4c4. stderr menciona hash diferente" \
  "$(printf '%s' "$SAIDA" | grep -q "hash diferente" && echo 1 || echo 0)"

# Restaura para próximo teste
echo "conteudo arquivo um" > "$S/docs/a-gravar/um.md"

echo "== T4d. entregavel removido apos gravacao: exit 1, stderr nomeia arquivo =="
# Remove um arquivo depois da gravação
rm "$S/docs/a-gravar/um.md"

SAIDA="$(rec conferir intacto)"; C=$?
afirma "T4d1. exit 1" "$([ "$C" -eq 1 ] && echo 1 || echo 0)"
afirma "T4d2. stderr nomeia arquivo removido" \
  "$(printf '%s' "$SAIDA" | grep -q "docs/a-gravar/um.md" && echo 1 || echo 0)"
afirma "T4d3. stderr menciona que nao existe" \
  "$(printf '%s' "$SAIDA" | grep -q "nao existe" && echo 1 || echo 0)"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
