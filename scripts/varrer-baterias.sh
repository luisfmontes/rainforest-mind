#!/bin/bash
# Varredura de baterias: executa todos os testes automatizados do repositorio.
# Uso: bash scripts/varrer-baterias.sh [--so <caminho>]
# --so <caminho>: roda apenas uma bateria (dispensa a guarda de piso)

set -u

modo_solo=""
if [ $# -eq 2 ] && [ "$1" = "--so" ]; then
  modo_solo="$2"
fi

if [ -n "$modo_solo" ]; then
  # Modo --so: roda apenas uma bateria, sem guarda de piso
  baterias="$modo_solo"
else
  # Modo normal: descobrir todas as baterias
  baterias=$(ls scripts/testa-*.sh hooks/testa-*.sh 2>/dev/null)
  total=$(printf '%s\n' "$baterias" | grep -c . || true)

  # Guarda contra o unico jeito deste job ser verde sem provar nada: um
  # glob que nao casa com ninguem roda zero bateria e sai 0. Em 17/08/2026
  # eram 20 (15 em scripts/, 5 em hooks/); o piso e deliberadamente baixo
  # para nao virar catraca de contagem, so para pegar o vazio.
  if [ "$total" -lt 15 ]; then
    echo "FALHA achei $total baterias — esperava pelo menos 15. Glob quebrado ou arvore incompleta."
    exit 1
  fi
  echo "== $total baterias =="
fi

vermelhas=""
for f in $baterias; do
  echo ""
  echo "----- $f -----"
  if bash "$f"; then
    echo "  >> VERDE  $f"
  else
    echo "  >> VERMELHA $f (exit $?)"
    vermelhas="$vermelhas $f"
  fi
done

echo ""
echo "================ placar ================"
if [ -z "$vermelhas" ]; then
  if [ -n "$modo_solo" ]; then
    echo "bateria passou"
  else
    echo "as $total baterias passaram"
  fi
  exit 0
fi
echo "vermelhas:"
for f in $vermelhas; do echo "  - $f"; done
exit 1
