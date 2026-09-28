#!/bin/bash
# Trava de gatilho sob demanda para a suite de `claude plugin eval` da issue
# #302 (design docs/rainforest/design/zerar-issues-11.md, D2-D4; plano
# docs/rainforest/planos/zerar-issues-11.md, tarefa 2).
#
# Nunca roda no CI (D5): a suite paga custa por rodada, e o script existe
# para rodar SOB DEMANDA, com a decisao de gasto na mao de quem chama.
# Nenhum modo aqui embute credencial nem endereco de rede — quem decide o
# executavel e CLAUDE_BIN (padrao: "claude" do PATH).
#
# Uso:
#   bash scripts/eval-gatilho.sh trava [--case <glob>] [--rodadas N] [--max-cost-usd X]
#   bash scripts/eval-gatilho.sh mutacao <skill> [--rodadas N]
#   bash scripts/eval-gatilho.sh baseline [--case <glob>]
#
# trava:    descobre os casos em evals/*/case.yaml (filtrados por --case,
#           padrao todos), roda cada um N vezes (padrao 3, --rodadas muda) com
#           `claude plugin eval . --trust-plugin --no-publish --ablation none
#           --runs 1 --threshold 1.0 --case <nome exato>`, e decide por
#           MAIORIA das rodadas (D3). Sai 1 se algum caso reprovar, 0 se todos
#           passarem. Exit 2 do CLI (teto de custo) aborta a trava na hora.
#
# mutacao:  sabota a `description:` de skills/<skill>/SKILL.md numa copia
#           temporaria dos arquivos rastreados (`git ls-files`) e roda a
#           trava so nos positivos dessa skill (gatilho-<skill>-vs-*-pos*).
#           A arvore real nunca muda. Sai 0 quando a trava fica vermelha
#           (mutacao pega), 3 quando fica verde (mutacao nao percebida).
#
# baseline: uma chamada unica com `--ablation with-without --runs 1`, sem
#           decisao de maioria — relatorio para o "acrescenta / peso morto".
#
# CLAUDE_BIN: executavel do CLI (padrao: claude). Sem executavel resolvivel,
# sai 127.

set -u

CLAUDE_BIN="${CLAUDE_BIN:-claude}"

uso() {
  cat <<'EOF'
uso: bash scripts/eval-gatilho.sh <modo> [opcoes]

modos:
  trava [--case <glob>] [--rodadas N] [--max-cost-usd X]
  mutacao <skill> [--rodadas N]
  baseline [--case <glob>]

variaveis de ambiente:
  CLAUDE_BIN  executavel do CLI `claude` (padrao: claude)
EOF
}

# Sem executavel resolvivel, nao ha nada a rodar -- recusa cedo, antes de
# descobrir casos ou copiar arvore nenhuma.
verificar_claude_bin() {
  if ! command -v -- "$CLAUDE_BIN" >/dev/null 2>&1; then
    echo "erro: CLAUDE_BIN nao resolve para um executavel: $CLAUDE_BIN" >&2
    echo "  defina CLAUDE_BIN com o caminho do CLI, ou instale 'claude' no PATH." >&2
    exit 127
  fi
}

# Le o campo `name:` de cada evals/*/case.yaml (relativo ao cwd de quem
# chama -- normal roda da raiz do repo; mutacao cd's para a copia antes de
# chamar isto) e imprime um nome por linha, filtrado pelo glob de --case
# (padrao "*", que casa tudo). O glob e' casado com `case`, igual ao
# `--case` do proprio CLI (confirmado em evals/README.md secao 1).
descobrir_casos() {
  local glob="${1:-*}"
  local arquivo nome
  shopt -s nullglob
  for arquivo in evals/*/case.yaml; do
    nome=$(grep -m1 '^name:' "$arquivo" | sed 's/^name:[[:space:]]*//')
    [ -n "$nome" ] || continue
    case "$nome" in
      $glob) printf '%s\n' "$nome" ;;
    esac
  done
  shopt -u nullglob
}

# ============================================================== trava

cmd_trava() {
  local glob="*"
  local rodadas=3
  local max_cost=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --case) glob="${2:?--case exige um glob}"; shift 2 ;;
      --rodadas) rodadas="${2:?--rodadas exige um numero}"; shift 2 ;;
      --max-cost-usd) max_cost="${2:?--max-cost-usd exige um valor}"; shift 2 ;;
      *) echo "erro: opcao desconhecida para trava: $1" >&2; exit 1 ;;
    esac
  done
  if ! [[ "$rodadas" =~ ^[0-9]+$ ]] || [ "$rodadas" -lt 1 ]; then
    echo "erro: --rodadas precisa ser um inteiro positivo, veio: $rodadas" >&2
    exit 1
  fi

  local casos
  casos=$(descobrir_casos "$glob")
  if [ -z "$casos" ]; then
    echo "FALHA nenhum caso casou com --case $glob em evals/*/case.yaml" >&2
    exit 1
  fi

  local algum_reprovou=0 nome ok_rodadas rodada exit_cli args
  while IFS= read -r nome; do
    [ -n "$nome" ] || continue
    ok_rodadas=0
    for ((rodada = 1; rodada <= rodadas; rodada++)); do
      args=(plugin eval . --trust-plugin --no-publish --ablation none --runs 1 --threshold 1.0 --case "$nome")
      if [ -n "$max_cost" ]; then
        args+=(--max-cost-usd "$max_cost")
      fi
      "$CLAUDE_BIN" "${args[@]}" >/dev/null 2>&1
      exit_cli=$?

      # Teto de custo: nao ha "resto de rodada" que valha a pena rodar depois
      # disto -- aborta a trava inteira, nao so o caso corrente.
      if [ "$exit_cli" -eq 2 ]; then
        echo "FALHA teto de custo atingido (exit 2) rodando $nome, rodada $rodada/$rodadas -- abortando a trava" >&2
        exit 2
      fi

      if [ "$exit_cli" -eq 0 ]; then
        ok_rodadas=$((ok_rodadas + 1))
      fi
    done

    # A decisao de maioria (D3): mais da metade das rodadas em exit 0. Esta
    # linha e' o alvo da mutacao declarada na tarefa 2 do plano -- a catraca
    # de mutacao (scripts/conferir-mutacao.cjs) troca o `if` por `if true`
    # e exige que a bateria fique vermelha.
    if [ $((ok_rodadas * 2)) -gt "$rodadas" ]; then
      echo "ok $nome ($ok_rodadas/$rodadas)"
    else
      echo "FALHA $nome ($ok_rodadas/$rodadas)"
      algum_reprovou=1
    fi
  done <<< "$casos"

  if [ "$algum_reprovou" -ne 0 ]; then
    exit 1
  fi
  exit 0
}

# ============================================================== mutacao

cmd_mutacao() {
  local skill="${1:-}"
  [ -n "$skill" ] || { echo "erro: mutacao exige <skill>" >&2; exit 1; }
  shift

  local rodadas=3
  while [ $# -gt 0 ]; do
    case "$1" in
      --rodadas) rodadas="${2:?--rodadas exige um numero}"; shift 2 ;;
      *) echo "erro: opcao desconhecida para mutacao: $1" >&2; exit 1 ;;
    esac
  done

  local skill_md="skills/$skill/SKILL.md"
  if [ ! -f "$skill_md" ]; then
    echo "erro: nao encontrei $skill_md (rode da raiz do repositorio)" >&2
    exit 1
  fi

  local antes depois
  antes=$(git status --porcelain 2>&1)

  # Copia SO os arquivos rastreados -- nunca a arvore de trabalho inteira, que
  # incluiria sujeira nao commitada e o proprio .git. `git ls-files -z` para
  # sobreviver a nomes com espaco.
  local tmp
  tmp=$(mktemp -d) || { echo "erro: mktemp -d falhou" >&2; exit 1; }
  local falhou_copia=0
  while IFS= read -r -d '' f; do
    mkdir -p "$tmp/$(dirname -- "$f")" || { falhou_copia=1; break; }
    cp -- "$f" "$tmp/$f" || { falhou_copia=1; break; }
  done < <(git ls-files -z)
  if [ "$falhou_copia" -ne 0 ]; then
    echo "erro: falha copiando arquivos rastreados para $tmp" >&2
    rm -rf "$tmp"
    exit 1
  fi

  if [ ! -f "$tmp/$skill_md" ]; then
    echo "erro: $skill_md nao esta rastreado pelo git (git ls-files nao o listou)" >&2
    rm -rf "$tmp"
    exit 1
  fi

  # Sabota a description: uma linha, description neutra, marcada para o
  # `claude` (real ou dublê) reprovar por nao reconhecer a skill mais.
  sed -i "s|^description:.*|description: SABOTADA-PARA-MUTACAO -- description neutra sem relacao com o gatilho original, para provar que a trava sabe falhar.|" "$tmp/$skill_md"

  local exit_trava
  ( cd "$tmp" && cmd_trava --case "gatilho-$skill-vs-*-pos*" --rodadas "$rodadas" )
  exit_trava=$?

  rm -rf "$tmp"

  depois=$(git status --porcelain 2>&1)
  if [ "$antes" != "$depois" ]; then
    echo "erro: a arvore real mudou durante a mutacao -- isto nunca deveria acontecer" >&2
    echo "antes:  $antes" >&2
    echo "depois: $depois" >&2
    exit 1
  fi

  if [ "$exit_trava" -eq 0 ]; then
    echo "FALHA mutacao NAO detectada: a trava ficou verde em skills/$skill (exit $exit_trava)"
    exit 3
  fi
  echo "ok mutacao detectada: a trava ficou vermelha em skills/$skill (exit $exit_trava)"
  exit 0
}

# ============================================================== baseline

cmd_baseline() {
  local glob=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --case) glob="${2:?--case exige um glob}"; shift 2 ;;
      *) echo "erro: opcao desconhecida para baseline: $1" >&2; exit 1 ;;
    esac
  done

  local args=(plugin eval . --trust-plugin --no-publish --ablation with-without --runs 1)
  if [ -n "$glob" ]; then
    args+=(--case "$glob")
  fi
  "$CLAUDE_BIN" "${args[@]}"
  exit $?
}

# ============================================================== dispatch

main() {
  local modo="${1:-}"
  case "$modo" in
    trava)
      shift
      verificar_claude_bin
      cmd_trava "$@"
      ;;
    mutacao)
      shift
      verificar_claude_bin
      cmd_mutacao "$@"
      ;;
    baseline)
      shift
      verificar_claude_bin
      cmd_baseline "$@"
      ;;
    -h|--help)
      uso
      exit 0
      ;;
    "")
      uso >&2
      exit 1
      ;;
    *)
      echo "erro: modo desconhecido: $modo" >&2
      uso >&2
      exit 1
      ;;
  esac
}

main "$@"
