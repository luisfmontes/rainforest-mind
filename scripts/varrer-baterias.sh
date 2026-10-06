#!/bin/bash
# Varredura de baterias: executa todos os testes automatizados do repositorio.
# Uso: bash scripts/varrer-baterias.sh [--so <caminho>] [--shard i/n] [--listar]
# --so <caminho>: roda apenas uma bateria (dispensa a guarda de piso, aceita .sh e .cjs)
# --shard i/n: roda so a fatia i de n, repartida por tempo (scripts/repartir-baterias.cjs
#   com os pesos de scripts/tempos-baterias.json). E como o CI divide a suite (Issue #377).
# --listar: imprime a lista (inteira, ou a do --shard) e sai, sem rodar nada

set -u

# Array, nao string: `for f in $baterias` sem aspas fazia word-splitting E
# globbing. Medido na revisao de 2026-09-15 -- `--so "<pasta>/*.sh"` rodava
# varias baterias e o placar dizia "bateria passou", no singular.
baterias=()
modo_solo=""
shard=""
listar=0

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
    while [ $# -gt 0 ]; do
      case "$1" in
        --shard)
          if [ $# -lt 2 ]; then
            echo "FALHA --shard exige i/n (ex.: 1/2). Uso: bash scripts/varrer-baterias.sh --shard i/n"
            exit 1
          fi
          shard="$2"
          shift 2
          ;;
        --listar)
          listar=1
          shift
          ;;
        *)
          echo "FALHA opcao desconhecida: $1. Uso: bash scripts/varrer-baterias.sh [--so <caminho>] [--shard i/n] [--listar]"
          exit 1
          ;;
      esac
    done
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

  # Conferencia de baterias obrigatorias (#398): sem --so, cada obrigatoria
  # tem de estar na lista descoberta INTEIRA — antes da reparticao por shard,
  # porque o CI so roda com --shard e uma conferencia por fatia nunca rodaria
  # la. ANTES de listar ou executar.
  arquivo_obrigatorias="${RFM_BATERIAS_OBRIGATORIAS:-scripts/baterias-obrigatorias.txt}"
  # Lista ausente onde ela deveria existir e falha, nao "nada a conferir":
  # apagar ou renomear o arquivo desligava a trava em silencio (revisao da
  # zerar-issues-16). Deveria existir = apontada por RFM_BATERIAS_OBRIGATORIAS,
  # ou a varredura roda na raiz deste repositorio (tem scripts/varrer-baterias.sh).
  if [ ! -f "$arquivo_obrigatorias" ] \
     && { [ -n "${RFM_BATERIAS_OBRIGATORIAS:-}" ] || [ -f scripts/varrer-baterias.sh ]; }; then
    echo "ERRO lista de baterias obrigatorias ausente: $arquivo_obrigatorias" >&2
    exit 1
  fi
  if [ -f "$arquivo_obrigatorias" ]; then
    # Ler as obrigatorias (ignorar linhas comentadas e vazias)
    obrigatorias=()
    while IFS= read -r linha; do
      # Remove comentarios e espacos em branco
      linha="${linha%%#*}"
      linha="${linha%$'\r'}"  # checkout com CRLF
      linha="${linha%"${linha##*[![:space:]]}"}"   # todo espaco do fim
      linha="${linha#"${linha%%[![:space:]]*}"}"   # todo espaco do comeco
      if [ -n "$linha" ]; then
        obrigatorias+=("$linha")
      fi
    done < "$arquivo_obrigatorias"

    # Conferir que cada obrigatoria esta na lista descoberta
    faltou=0
    for obrigatoria in "${obrigatorias[@]}"; do
      encontrada=0
      for bateria in "${baterias[@]}"; do
        if [ "$bateria" = "$obrigatoria" ]; then
          encontrada=1
          break
        fi
      done
      if [ $encontrada -eq 0 ]; then
        echo "FALTOU $obrigatoria"
        faltou=1
      fi
    done
    [ "$faltou" = 1 ] && exit 1
  fi

  # --shard: a guarda de piso acima rodou na lista INTEIRA; so depois a lista
  # encolhe para a fatia. Fatia vazia ou repartidor quebrado e falha, nunca
  # "0 baterias passaram" verde.
  if [ -n "$shard" ]; then
    raiz_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    total_lista="${#baterias[@]}"
    if ! fatia=$(printf '%s\n' "${baterias[@]}" | node "$raiz_script/repartir-baterias.cjs" --shard "$shard"); then
      echo "FALHA a reparticao das baterias falhou (--shard $shard)"
      exit 1
    fi
    baterias=()
    while IFS= read -r linha; do
      if [ -n "$linha" ]; then baterias+=("$linha"); fi
    done <<< "$fatia"
    if [ "${#baterias[@]}" -lt 1 ]; then
      echo "FALHA o shard $shard ficou sem baterias (de $total_lista)"
      exit 1
    fi
  fi


  if [ "$listar" -eq 1 ]; then
    printf '%s\n' "${baterias[@]}"
    exit 0
  fi
  total="${#baterias[@]}"
  if [ -n "$shard" ]; then
    echo "== $total baterias (shard $shard de $total_lista) =="
  else
    echo "== $total baterias =="
  fi
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
