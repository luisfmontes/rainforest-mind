#!/bin/bash
# Bateria do hooks/lib/folga.cjs — o módulo que avalia folga contra teto de
# orçamento. Prova que a lógica de estados e mensagens funciona como especificado.
#
# O que ela precisa provar, em ordem:
#
#   1. estouro: valor acima do teto leva a estado 'estouro'
#   2. dentro da banda avisa sem reprovar: folga abaixo do limiar mas >= 0 vira 'aviso'
#   3. folga real: folga acima do limiar vira 'ok'
#   4. a mensagem de aviso contém as alternativas passadas e não contém "reduz"
#   5. fronteira exata: folga === limiar é 'ok', folga === limiar - 1 é 'aviso'

set -u

ok=0; falhou=0
tem()     { if echo "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

# ------------------------------------------------- 1. estouro
echo; echo "1. estouro: valor acima do teto"
SAIDA="$(node -e "const {avaliarFolga}=require('./hooks/lib/folga.cjs'); console.log(avaliarFolga(14462, 14000).estado)")"
igual "avaliarFolga(14462, 14000) retorna 'estouro'" "$SAIDA" "estouro"

# ------------------------------------------------- 2. dentro da banda avisa sem reprovar
echo; echo "2. dentro da banda avisa sem reprovar"
SAIDA2="$(node -e "const {avaliarFolga}=require('./hooks/lib/folga.cjs'); console.log(avaliarFolga(5589, 5600).estado)")"
igual "avaliarFolga(5589, 5600) retorna 'aviso'" "$SAIDA2" "aviso"

# ------------------------------------------------- 3. folga real
echo; echo "3. folga real: folga acima do limiar"
SAIDA3="$(node -e "const {avaliarFolga}=require('./hooks/lib/folga.cjs'); console.log(avaliarFolga(13096, 14000).estado)")"
igual "avaliarFolga(13096, 14000) retorna 'ok'" "$SAIDA3" "ok"

# ------------------------------------------------- 4. mensagem de aviso
echo; echo "4. mensagem de aviso contém alternativas e não contém 'reduz'"
SAIDA4="$(node -e "const {avaliarFolga}=require('./hooks/lib/folga.cjs'); const r=avaliarFolga(5589, 5600, {nome:'nucleos', alternativas:['tirar do FOCO', 'subir o agregado']}); console.log(r.mensagem)")"
tem "mensagem contém primeira alternativa" "$SAIDA4" "tirar do FOCO"
tem "mensagem contém segunda alternativa" "$SAIDA4" "subir o agregado"
nao_tem "mensagem não contém 'reduz'" "$SAIDA4" "reduz"

# ------------------------------------------------- 5. fronteira exata
echo; echo "5. fronteira exata"
# Teste 5a: folga === limiar deve ser 'ok'
# Para teto 5600, banda 0.05 (padrão), limiar = Math.round(5600 * 0.05) = 280
# Então valor = 5600 - 280 = 5320, folga = 280 (exatamente igual ao limiar)
SAIDA5A="$(node -e "const {avaliarFolga}=require('./hooks/lib/folga.cjs'); console.log(avaliarFolga(5320, 5600).estado)")"
igual "folga === limiar (280) é 'ok'" "$SAIDA5A" "ok"

# Teste 5b: folga === limiar - 1 deve ser 'aviso'
# valor = 5600 - 279 = 5321, folga = 279 (uma unidade abaixo do limiar)
SAIDA5B="$(node -e "const {avaliarFolga}=require('./hooks/lib/folga.cjs'); console.log(avaliarFolga(5321, 5600).estado)")"
igual "folga === limiar - 1 (279) é 'aviso'" "$SAIDA5B" "aviso"

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
