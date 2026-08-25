#!/bin/bash
# Bateria do `conferir-livro-de-repos.cjs` — a catraca do vocabulário de
# veredito por trilha, com a anistia de D8 (data de corte) do design
# `docs/rainforest/design/2026-08-25-regua-do-batedor-enxertar.md`.
#
# Uso: bash scripts/testa-conferir-livro-de-repos.sh
#
# Cada fixture nasce em `mktemp -d` e morre no `trap` — nenhuma delas toca o
# `vigias/livro-de-repos.md` real, exceto o caso de integração no fim, que
# LÊ (nunca escreve) o livro de verdade para provar que a régua nova não
# rejulga as 40 linhas existentes.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/conferir-livro-de-repos.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }

ok=0; falhou=0
S="$(mktemp -d)"
W="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")"
trap 'rm -rf "$S"' EXIT

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"
    echo "$saida" | sed 's/^/         /' | tail -20
  fi
}
contem() { # nome, texto, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -qi -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt' na saida"; fi
}
conta() { # nome, texto, N esperado, comando...
  local nome="$1" txt="$2" n="$3"; shift 3
  local got; got=$("$@" 2>&1 | grep -ci -- "$txt")
  if [ "$got" = "$n" ]; then ok=$((ok+1)); echo "  ok   $nome ($got ocorrencia(s))"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava $n ocorrencia(s) de '$txt', veio $got"; fi
}

# Monta um livro-fixture com as linhas dadas, uma por argumento, no formato
# "repo|data|veredito". Reprovou-em e Ultimo-push ficam fixos em "—".
livro() { # arquivo, linha1, linha2, ...
  local arq="$1"; shift
  {
    echo "# livro fixture"
    echo
    echo "## Avaliados"
    echo
    echo "| Repo | Data | Veredito | Reprovou em | Último push visto |"
    echo "|---|---|---|---|---|"
    for l in "$@"; do
      IFS='|' read -r repo data veredito <<< "$l"
      echo "| \`$repo\` | $data | $veredito | 1 | — |"
    done
  } > "$arq"
}

echo "== critério de sucesso da tarefa 3: fixture de quatro linhas =="
F_CRITERIO="$S/criterio-4-linhas.md"
livro "$F_CRITERIO" \
  "fixture/valido-pos-corte|2026-08-26|Instalar → Enxertar: enxerta" \
  "fixture/inventado-pos-corte|2026-08-26|Instalar → Enxertar: meio-termo" \
  "fixture/inventado-pre-corte|2026-08-20|olhar de perto" \
  "fixture/trilha-ausente-pos-corte|2026-08-26|não acopla, tem peça forte"

esperado "quatro linhas: recusa (veredito invalido + trilha ausente), nenhuma pre-corte" 3 \
  node "$SCRIPT" --arquivo "$F_CRITERIO" --corte 2026-08-25
conta "  ... exatamente 1 recusa de veredito fora do vocabulario" "VEREDITO FORA DO VOCAB" 1 \
  node "$SCRIPT" --arquivo "$F_CRITERIO" --corte 2026-08-25
conta "  ... exatamente 1 recusa de trilha ausente" "TRILHA AUSENTE (1)" 1 \
  node "$SCRIPT" --arquivo "$F_CRITERIO" --corte 2026-08-25
esperado "  ... a linha pre-corte NUNCA aparece nas recusas" 0 \
  bash -c "node '$SCRIPT' --arquivo '$F_CRITERIO' --corte 2026-08-25 2>&1 | grep -qi 'inventado-pre-corte' && exit 1 || exit 0"

echo
echo "== cada exit code isolado =="

F_OK="$S/so-validas.md"
livro "$F_OK" \
  "fixture/instalar-passa|2026-08-26|Instalar: instala" \
  "fixture/enxertar-passa|2026-08-26|Instalar → Enxertar: enxerta" \
  "fixture/ler-passa|2026-08-26|Instalar → Enxertar → Ler: vale voltar" \
  "fixture/terminal|2026-08-26|fora da ancora"
esperado "so linhas validas pos-corte -> aprovado (exit 0)" 0 \
  node "$SCRIPT" --arquivo "$F_OK" --corte 2026-08-25

F_VEREDITO="$S/so-veredito-invalido.md"
livro "$F_VEREDITO" \
  "fixture/veredito-ruim|2026-08-26|Enxertar: passa com ressalva"
esperado "so veredito fora do vocabulario -> exit 2" 2 \
  node "$SCRIPT" --arquivo "$F_VEREDITO" --corte 2026-08-25
contem "  ... e nomeia o vocabulario esperado da trilha" "vocabul.*enxertar" \
  node "$SCRIPT" --arquivo "$F_VEREDITO" --corte 2026-08-25

F_AUSENTE="$S/so-trilha-ausente.md"
livro "$F_AUSENTE" \
  "fixture/sem-trilha|2026-08-26|candidato, não avaliado"
esperado "so trilha ausente -> exit 3" 3 \
  node "$SCRIPT" --arquivo "$F_AUSENTE" --corte 2026-08-25
contem "  ... e diz que nenhum caminho de cascata foi declarado" "nenhum caminho de cascata declarado" \
  node "$SCRIPT" --arquivo "$F_AUSENTE" --corte 2026-08-25

F_AUSENTE_COM_DOIS_PONTOS="$S/trilha-ausente-com-dois-pontos.md"
livro "$F_AUSENTE_COM_DOIS_PONTOS" \
  "fixture/rotulo-invencionice|2026-08-26|Referência de estrutura: sim"
esperado "celula com ':' mas sem nenhuma trilha reconhecivel antes dele -> exit 3 tambem" 3 \
  node "$SCRIPT" --arquivo "$F_AUSENTE_COM_DOIS_PONTOS" --corte 2026-08-25
contem "  ... e nomeia que nenhuma trilha foi reconhecida no caminho" "nenhuma trilha reconhec" \
  node "$SCRIPT" --arquivo "$F_AUSENTE_COM_DOIS_PONTOS" --corte 2026-08-25

F_MALFORMADO="$S/so-caminho-malformado.md"
livro "$F_MALFORMADO" \
  "fixture/caminho-invertido|2026-08-26|Ler → Instalar: instala"
esperado "so caminho de cascata malformado (ordem invertida) -> exit 4" 4 \
  node "$SCRIPT" --arquivo "$F_MALFORMADO" --corte 2026-08-25
contem "  ... e nomeia a ordem fixa esperada" "ordem fixa" \
  node "$SCRIPT" --arquivo "$F_MALFORMADO" --corte 2026-08-25

F_SALTO="$S/caminho-com-salto.md"
livro "$F_SALTO" \
  "fixture/pula-enxertar|2026-08-26|Instalar → Ler: vale voltar"
esperado "caminho pulando Enxertar -> exit 4 tambem" 4 \
  node "$SCRIPT" --arquivo "$F_SALTO" --corte 2026-08-25

F_DEGRAU_DESCONHECIDO="$S/degrau-desconhecido.md"
livro "$F_DEGRAU_DESCONHECIDO" \
  "fixture/degrau-fantasma|2026-08-26|Instalar → Comprar: sim"
esperado "degrau desconhecido no meio do caminho -> exit 4" 4 \
  node "$SCRIPT" --arquivo "$F_DEGRAU_DESCONHECIDO" --corte 2026-08-25

echo
echo "== bordas de data e comparação (D8, corte estritamente exclusivo) =="

F_NO_CORTE="$S/data-igual-ao-corte.md"
livro "$F_NO_CORTE" \
  "fixture/no-dia-do-corte|2026-08-25|olhar de perto"
esperado "data IGUAL ao corte passa sem ser olhada (nao e 'posterior')" 0 \
  node "$SCRIPT" --arquivo "$F_NO_CORTE" --corte 2026-08-25

F_UM_DIA_DEPOIS="$S/um-dia-depois.md"
livro "$F_UM_DIA_DEPOIS" \
  "fixture/um-dia-depois|2026-08-26|olhar de perto"
esperado "data um dia DEPOIS do corte ja e checada e reprova" 3 \
  node "$SCRIPT" --arquivo "$F_UM_DIA_DEPOIS" --corte 2026-08-25

echo
echo "== erros de uso e estrutura (exit 1) =="

esperado "arquivo inexistente -> exit 1" 1 \
  node "$SCRIPT" --arquivo "$S/nao-existe-de-verdade.md"

F_SEM_SECAO="$S/sem-secao-avaliados.md"
printf '# livro sem a secao\n\nnada aqui.\n' > "$F_SEM_SECAO"
esperado "arquivo sem secao ## Avaliados -> exit 1" 1 \
  node "$SCRIPT" --arquivo "$F_SEM_SECAO"
contem "  ... e diz que a secao nao foi encontrada" "Avaliados.*encontrada" \
  node "$SCRIPT" --arquivo "$F_SEM_SECAO"

F_LINHA_QUEBRADA="$S/linha-quebrada.md"
{
  echo "# livro fixture quebrado"
  echo
  echo "## Avaliados"
  echo
  echo "| Repo | Data | Veredito | Reprovou em | Último push visto |"
  echo "|---|---|---|---|---|"
  echo "| \`fixture/linha-sem-colunas\` |"
} > "$F_LINHA_QUEBRADA"
esperado "linha da tabela sem as colunas minimas -> exit 1" 1 \
  node "$SCRIPT" --arquivo "$F_LINHA_QUEBRADA"

F_DATA_ILEGIVEL="$S/data-ilegivel.md"
livro "$F_DATA_ILEGIVEL" \
  "fixture/data-quebrada|25 de agosto de 2026|enxerta"
esperado "data que nao bate AAAA-MM-DD -> exit 1" 1 \
  node "$SCRIPT" --arquivo "$F_DATA_ILEGIVEL"

echo
echo "== --corte customizado por flag, e o formato dele e validado =="

esperado "--corte em formato invalido -> exit 1 (erro de uso)" 1 \
  node "$SCRIPT" --arquivo "$F_OK" --corte "25/08/2026"

F_CORTE_CUSTOM="$S/corte-customizado.md"
livro "$F_CORTE_CUSTOM" \
  "fixture/entre-os-dois-cortes|2026-08-10|olhar de perto"
esperado "com corte customizado bem anterior, linha de 2026-08-10 passa a ser checada e reprova" 3 \
  node "$SCRIPT" --arquivo "$F_CORTE_CUSTOM" --corte 2000-01-01
esperado "  ... com o corte padrao, a MESMA linha fica isenta" 0 \
  node "$SCRIPT" --arquivo "$F_CORTE_CUSTOM"

echo
echo "== acentuação e caixa não importam na comparação do vocabulário =="

F_ACENTO="$S/acento-e-caixa.md"
livro "$F_ACENTO" \
  "fixture/nao-acentuado|2026-08-26|instalar: NÃO INSTALA" \
  "fixture/terminal-maiusculo|2026-08-26|FORA DA ANCORA"
esperado "veredito com acento/caixa diferente do padrao ainda bate -> aprovado" 0 \
  node "$SCRIPT" --arquivo "$F_ACENTO" --corte 2026-08-25

echo
echo "== integração: o LIVRO REAL passa com o corte padrão (sem --arquivo, sem --corte) =="
esperado "vigias/livro-de-repos.md real -> aprovado com a regua nova (D8 nao rejulga as 40 linhas)" 0 \
  node "$SCRIPT"
contem "  ... e as 40 linhas ficam todas isentas (nenhuma data e posterior a hoje)" "ignoradas" \
  node "$SCRIPT"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
