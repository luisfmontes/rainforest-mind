#!/bin/bash
# Varredura de baterias: executa todos os testes automatizados do repositorio.
# Uso: bash scripts/varrer-baterias.sh [--so <caminho>]
# --so <caminho>: roda apenas uma bateria (dispensa a guarda de piso, aceita .sh e .cjs)

set -u

# Array, nao string: `for f in $baterias` sem aspas fazia word-splitting E
# globbing. Medido na revisao de 2026-09-15 -- `--so "<pasta>/*.sh"` rodava
# varias baterias e o placar dizia "bateria passou", no singular.
baterias=()
modo_solo=""

if [ $# -gt 0 ]; then
  if [ "$1" = "--so" ]; then
    if [ $# -ne 2 ]; then
      echo "FALHA --so exige exatamente um caminho. Uso: bash scripts/varrer-baterias.sh --so <caminho>"
      exit 1
    fi
    modo_solo="$2"
  else
    # Flag desconhecida nao pode cair no modo completo em silencio: `--sso x`
    # rodava a varredura inteira sem avisar que a flag nao existia.
    echo "FALHA opcao desconhecida: $1. Uso: bash scripts/varrer-baterias.sh [--so <caminho>]"
    exit 1
  fi
fi

if [ -n "$modo_solo" ]; then
  # Modo --so: roda apenas uma bateria, sem guarda de piso. O caminho tem de
  # existir e de se chamar `testa-*.sh` ou `testa-*.cjs` -- `--so` e atalho de quem esta
  # consertando uma bateria, nao um jeito de rodar script arbitrario com a
  # cara da varredura. Medido na revisao de 2026-09-15: `--so <qualquer.sh>`
  # rodava o script e imprimia "bateria passou". O caminho segue livre quanto
  # a pasta, porque a propria bateria desta varredura roda em caixa de areia.
  case "$(basename -- "$modo_solo")" in
    testa-*.sh|testa-*.cjs) ;;
    *)
      echo "FALHA --so so aceita uma bateria (testa-*.sh ou testa-*.cjs); veio: $modo_solo"
      exit 1
      ;;
  esac
  if [ ! -f "$modo_solo" ]; then
    echo "FALHA bateria nao encontrada: $modo_solo"
    exit 1
  fi
  baterias=("$modo_solo")
else
  # Modo normal: descobrir todas as baterias. Os quatro globs sao conferidos
  # SEPARADAMENTE, cada um com piso proprio.
  #
  # A versao anterior fazia `ls scripts/testa-*.sh hooks/testa-*.sh` num `ls`
  # so, com piso unico de 15. Na arvore real sao 89 em scripts/ e 27 em
  # hooks/: o piso era satisfeito por scripts/ sozinho, entao se o glob de
  # hooks/ quebrasse os 27 gates saiam da varredura e o placar dizia verde.
  # A guarda pegava so o vazio TOTAL. Medido na revisao de 2026-09-15.
  # Globbing do shell com `nullglob`, nao `ls`: dentro de `$( )` o status do
  # `ls` se perdia, e contar com `grep -c .` conta uma linha mesmo quando a
  # string esta vazia. Com array, `${#arr[@]}` conta o que existe.
  shopt -s nullglob
  de_scripts=(scripts/testa-*.sh)
  de_hooks=(hooks/testa-*.sh)
  de_scripts_cjs=(scripts/testa-*.cjs)
  de_hooks_cjs=(hooks/testa-*.cjs)
  shopt -u nullglob

  # Pisos deliberadamente baixos: a guarda existe para pegar glob quebrado e
  # arvore incompleta, nao para virar catraca de contagem. Em 17/08/2026 eram
  # 15 em scripts/ e 5 em hooks/; em 15/09/2026, 89 e 27. Em 26/09/2026,
  # .cjs: 2 em scripts/ e 16 em hooks/.
  if [ "${#de_scripts[@]}" -lt 15 ]; then
    echo "FALHA achei ${#de_scripts[@]} baterias em scripts/*.sh — esperava pelo menos 15. Glob quebrado ou arvore incompleta."
    exit 1
  fi
  if [ "${#de_hooks[@]}" -lt 5 ]; then
    echo "FALHA achei ${#de_hooks[@]} baterias em hooks/*.sh — esperava pelo menos 5. Glob quebrado ou arvore incompleta."
    exit 1
  fi
  if [ "${#de_scripts_cjs[@]}" -lt 1 ]; then
    echo "FALHA achei ${#de_scripts_cjs[@]} baterias em scripts/*.cjs — esperava pelo menos 1. Glob quebrado ou arvore incompleta."
    exit 1
  fi
  if [ "${#de_hooks_cjs[@]}" -lt 10 ]; then
    echo "FALHA achei ${#de_hooks_cjs[@]} baterias em hooks/*.cjs — esperava pelo menos 10. Glob quebrado ou arvore incompleta."
    exit 1
  fi

  baterias=("${de_scripts[@]}" "${de_hooks[@]}" "${de_scripts_cjs[@]}" "${de_hooks_cjs[@]}")
  total="${#baterias[@]}"
  echo "== $total baterias =="
fi

vermelhas=()
for f in "${baterias[@]}"; do
  echo ""
  echo "----- $f -----"
  # Detecta extensao e roda com ferramenta apropriada
  if [[ "$f" == *.cjs ]]; then
    runner="node"
  else
    runner="bash"
  fi
  if $runner "$f"; then
    echo "  >> VERDE  $f"
  else
    codigo=$?
    echo "  >> VERMELHA $f (exit $codigo)"
    vermelhas+=("$f")
  fi
done

echo ""
echo "================ placar ================"
if [ "${#vermelhas[@]}" -eq 0 ]; then
  if [ -n "$modo_solo" ]; then
    echo "bateria passou"
  else
    echo "as $total baterias passaram"
  fi
  exit 0
fi
echo "vermelhas:"
for f in "${vermelhas[@]}"; do echo "  - $f"; done
exit 1
