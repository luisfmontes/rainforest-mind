#!/usr/bin/env bash
# Adota as baterias da portaria na suíte.
#
# POR QUE ESTE ARQUIVO EXISTE. As seis baterias do fluxo 9 nasceram em `.cjs`
# (`hooks/testa-portaria-*.cjs`) e o glob que define a suíte casa **só** `.sh`:
#
#   .github/workflows/baterias.yml:136 -> ls scripts/testa-*.sh hooks/testa-*.sh
#   CONTRIBUTING.md:11                 -> for t in scripts/testa-*.sh hooks/testa-*.sh
#
# Resultado: seis baterias escritas com cuidado, verdes, e **nunca executadas**
# por ninguém — nem no CI, nem no comando local. Foram escritas, commitadas, e
# desde então não travaram nada. Descoberto em 2026-09-02, ao mexer na portaria:
# rodadas à mão, as seis passavam; rodadas pelo CI, não existiam.
#
# É a quarta trava inerte do mesmo padrão neste repositório, e o padrão é sempre
# o mesmo — o instrumento não estoura, não fica em branco: ele simplesmente não
# é chamado, e o verde de quem chama os outros parece cobrir esse também.
#
# A escolha aqui foi adotar as `.cjs` num wrapper em vez de mudar o glob do CI.
# O glob tem uma guarda de piso (`total < 15` reprova) que existe justamente
# para pegar glob quebrado; mexer nele para casar `.cjs` mexeria na guarda junto
# e trocaria uma trava por outra menos testada. Um wrapper é uma linha de
# arquivo novo e nada mais precisa saber que existe.
set -u

cd "$(dirname "$0")/.." || exit 1

PISO=6

mapfile -t baterias < <(ls hooks/testa-portaria-*.cjs 2>/dev/null)
total=${#baterias[@]}

# A mesma guarda do CI, pelo mesmo motivo: um glob que não casa com ninguém roda
# zero bateria e sai 0. É exatamente assim que estas seis passaram despercebidas.
if [ "$total" -lt "$PISO" ]; then
  echo "FALHA achei $total bateria(s) da portaria — esperava pelo menos $PISO."
  echo "  Glob quebrado, ou bateria removida sem baixar o piso deste arquivo."
  exit 1
fi

ok=0
falhou=0
vermelhas=""

for f in "${baterias[@]}"; do
  echo ""
  echo "----- $f -----"
  if node "$f"; then
    ok=$((ok + 1))
  else
    falhou=$((falhou + 1))
    vermelhas="$vermelhas $f"
  fi
done

echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="

if [ "$falhou" -gt 0 ]; then
  echo "vermelhas:$vermelhas"
  exit 1
fi

exit 0
