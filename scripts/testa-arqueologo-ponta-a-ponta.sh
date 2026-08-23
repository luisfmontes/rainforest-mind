#!/usr/bin/env bash
# Validador do mapa que a skill `arqueologia` / agente `arqueologo` produzem
# (docs/rainforest/mapas/<fatia>/<bloco>.md), e a bateria que prova que ele
# reprova nas quatro condicoes descritas na tarefa 5 do plano
# docs/rainforest/planos/2026-08-22-agente-arqueologo.md:
#
#   1. Uma afirmacao CONFIRMADO sem citacao arquivo:linha.
#   2. Uma citacao arquivo:linha para linha que nao existe no fonte, ou que
#      existe mas esta vazia (so espaco em branco).
#   3. Um arquivo de bloco passa de 40.000 caracteres (wc -c).
#   4. A pasta nao tem nenhum bloco, ou nenhum CONFIRMADO — mapa vazio nao e
#      mapa.
#
# INFERIDO e LACUNA nao exigem citacao — so CONFIRMADO promete lastro.
#
# Uso como instrumento (fora da bateria):
#   bash scripts/testa-arqueologo-ponta-a-ponta.sh --validar <pasta-mapa> <arquivo-fonte>
#
# Sem argumentos, roda a bateria com fixtures proprias em diretorio temporario
# — nao toca em docs/rainforest/mapas/ do repositorio nem em fonte nenhum dele.
set -u

cd "$(dirname "$0")/.." || exit 1

# ---------------------------------------------------------------------------
# O VALIDADOR
# ---------------------------------------------------------------------------

# escapar_regex NOME — escapa o ponto (unico metacaractere que aparece em
# nomes de fonte reais tipo "IAG67M12.prw" ou "nfesefaz.prw") para uso dentro
# de um -E do grep. Nao cobre todo metacaractere possivel — documentado como
# limite conhecido, nao lacuna escondida.
escapar_regex() {
  printf '%s' "$1" | sed -e 's/\./\\./g'
}

# verificar_linha_citada FONTE NUMERO TOTAL — regra 2 isolada numa funcao
# proposital: e o ponto exato que a mutacao do criterio de sucesso #3 troca
# por `true`.
verificar_linha_citada() {
  local fonte="$1" numero="$2" total="$3"
  if [ "$numero" -lt 1 ] || [ "$numero" -gt "$total" ]; then
    return 1
  fi
  local conteudo
  conteudo=$(sed -n "${numero}p" "$fonte" | tr -d '[:space:]')
  [ -n "$conteudo" ]
}

# validar_mapa PASTA_MAPA ARQUIVO_FONTE — imprime cada violacao encontrada
# (nao para na primeira) e devolve 0 se o mapa passa nas quatro regras, 1 caso
# contrario.
validar_mapa() {
  local pasta="$1"
  local fonte="$2"
  local nome_fonte regex_fonte
  nome_fonte="$(basename "$fonte")"
  regex_fonte="$(escapar_regex "$nome_fonte")"
  local erros=0

  if [ ! -d "$pasta" ]; then
    echo "  [regra4] pasta de mapa nao existe: $pasta"
    return 1
  fi
  if [ ! -f "$fonte" ]; then
    echo "  [erro] fonte mapeado nao existe: $fonte"
    return 1
  fi

  local blocos=()
  while IFS= read -r -d '' f; do
    blocos+=("$f")
  done < <(find "$pasta" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

  if [ "${#blocos[@]}" -eq 0 ]; then
    echo "  [regra4] pasta sem nenhum bloco .md: $pasta"
    erros=$((erros + 1))
  fi

  # regra 3 — teto de 40.000 caracteres por bloco.
  for b in "${blocos[@]:-}"; do
    [ -z "$b" ] && continue
    local tam
    tam=$(wc -c <"$b" | tr -d ' ')
    if [ "$tam" -gt 40000 ]; then
      echo "  [regra3] bloco excede 40000 caracteres ($tam): $b"
      erros=$((erros + 1))
    fi
  done

  # regra 1 e metade da regra 4 — toda linha com CONFIRMADO tem de citar
  # arquivo:linha DO FONTE PASSADO (nao qualquer string em forma de citacao).
  local total_confirmado=0
  for b in "${blocos[@]:-}"; do
    [ -z "$b" ] && continue
    while IFS= read -r linha; do
      case "$linha" in
      *CONFIRMADO*)
        total_confirmado=$((total_confirmado + 1))
        if ! printf '%s' "$linha" | grep -qE "\\b${regex_fonte}:[0-9]+\\b"; then
          echo "  [regra1] CONFIRMADO sem citacao '${nome_fonte}:linha' em $b -> $linha"
          erros=$((erros + 1))
        fi
        ;;
      esac
    done <"$b"
  done

  if [ "$total_confirmado" -eq 0 ]; then
    echo "  [regra4] nenhuma afirmacao CONFIRMADO em nenhum bloco: $pasta"
    erros=$((erros + 1))
  fi

  # regra 2 — toda citacao arquivo:linha aponta para linha real e nao vazia.
  local total_linhas_fonte
  total_linhas_fonte=$(wc -l <"$fonte" | tr -d ' ')
  for b in "${blocos[@]:-}"; do
    [ -z "$b" ] && continue
    while IFS= read -r citacao; do
      [ -z "$citacao" ] && continue
      local numero_linha="${citacao##*:}"
      if ! verificar_linha_citada "$fonte" "$numero_linha" "$total_linhas_fonte"; then
        echo "  [regra2] citacao aponta para linha invalida ou vazia ($citacao) em $b"
        erros=$((erros + 1))
      fi
    done < <(grep -ohE "\\b${regex_fonte}:[0-9]+\\b" "$b")
  done

  [ "$erros" -eq 0 ]
}

# Modo instrumento: chamado com --validar, nao roda a bateria.
if [ "${1:-}" = "--validar" ]; then
  if [ $# -lt 3 ]; then
    echo "Uso: $0 --validar <pasta-mapa> <arquivo-fonte>" >&2
    exit 2
  fi
  validar_mapa "$2" "$3"
  exit $?
fi

# ---------------------------------------------------------------------------
# A BATERIA
# ---------------------------------------------------------------------------

ok=0
# Foto do estado da arvore ANTES de qualquer caso: a prova de que a bateria nao
# deixou rastro e a COMPARACAO antes/depois. Exigir arvore limpa faz o teste
# quebrar por sujeira alheia (um estado.json nao commitado), que e falha do
# ambiente e nao da bateria.
STATUS_ANTES=$(git status --short 2>/dev/null)
falhou=0

marca() {
  if [ "$2" -eq 0 ]; then
    ok=$((ok + 1))
    echo "  ok   $1"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $1"
  fi
}

marca_vermelho_esperado() {
  # $1 = descricao, $2 = exit code obtido (esperado != 0)
  if [ "$2" -ne 0 ]; then
    ok=$((ok + 1))
    echo "  ok   VERMELHO esperado: $1 (exit $2)"
  else
    falhou=$((falhou + 1))
    echo "  FALHA $1 deveria ter reprovado e passou (exit 0)"
  fi
}

echo "== validador de mapa da arqueologia — fixtures em diretorio temporario =="
echo

CAIXA="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}"' EXIT

# --- fonte sintetico com linhas numeraveis -----------------------------
# linha 5 e so espaco em branco (regra 2, caso "vazia"); nao existe linha 99
# (regra 2, caso "inexistente"); linha 3 tem conteudo real (usada no mapa bom
# e nas citacoes validas).
FONTE="$CAIXA/fonte-teste.prw"
{
  echo "function TesteFuncao()"
  echo "    local nX := 1"
  echo "    nX := nX + 1"
  echo "    // comentario de linha 4"
  echo "   "
  echo "    Return nX"
  echo "endfunction"
  echo ""
  echo "function OutraFuncao()"
  echo "    local cY := 'abc'"
  echo "    Return cY"
  echo "endfunction"
} >"$FONTE"

MAPAS="$CAIXA/mapas"
mkdir -p "$MAPAS"

# --- mapa bom -------------------------------------------------------------
MAPA_BOM="$MAPAS/fatia-boa"
mkdir -p "$MAPA_BOM"
cat >"$MAPA_BOM/bloco-01.md" <<EOF
# Bloco 1 — fatia-boa

CONFIRMADO: TesteFuncao incrementa nX em uma unidade (fonte-teste.prw:3).

INFERIDO: o nome sugere que TesteFuncao serve so de exemplo, nao de producao.

LACUNA: nao sei por que a funcao devolve nX em vez de nX + 1 apos o incremento.

## Regras implícitas

Nenhuma identificada nesta fatia.
EOF

# --- regra 1: CONFIRMADO sem citacao arquivo:linha -------------------------
MAPA_R1="$MAPAS/fatia-ruim-1-sem-citacao"
mkdir -p "$MAPA_R1"
cat >"$MAPA_R1/bloco-01.md" <<EOF
# Bloco 1 — fatia-ruim-1

CONFIRMADO: TesteFuncao incrementa nX em uma unidade.

INFERIDO: isso e so um chute, sem citacao mesmo — o que e permitido.
EOF

# --- regra 1 (adversarial): citacao existe, mas aponta para OUTRO fonte ---
# Nao e a mesma coisa de "sem citacao" — e uma citacao com a FORMA certa que
# nao serve para provar nada sobre o fonte que esta sendo validado. Se o
# validador so checar "existe alguma coisa em forma de arquivo:linha" sem
# amarrar ao nome do fonte recebido, esse caso passaria escondido.
MAPA_R1B="$MAPAS/fatia-ruim-1b-citacao-de-outro-arquivo"
mkdir -p "$MAPA_R1B"
cat >"$MAPA_R1B/bloco-01.md" <<EOF
# Bloco 1 — fatia-ruim-1b

CONFIRMADO: TesteFuncao incrementa nX em uma unidade (outro-arquivo.prw:3).
EOF

# --- regra 2: citacao para linha que nao existe -----------------------------
MAPA_R2A="$MAPAS/fatia-ruim-2a-linha-inexistente"
mkdir -p "$MAPA_R2A"
cat >"$MAPA_R2A/bloco-01.md" <<EOF
# Bloco 1 — fatia-ruim-2a

CONFIRMADO: TesteFuncao faz algo na linha 99, que nao existe (fonte-teste.prw:99).
EOF

# --- regra 2: citacao para linha que existe mas esta vazia ------------------
MAPA_R2B="$MAPAS/fatia-ruim-2b-linha-vazia"
mkdir -p "$MAPA_R2B"
cat >"$MAPA_R2B/bloco-01.md" <<EOF
# Bloco 1 — fatia-ruim-2b

CONFIRMADO: TesteFuncao tem uma linha em branco no meio (fonte-teste.prw:5).
EOF

# --- regra 3: bloco maior que 40.000 caracteres -----------------------------
MAPA_R3="$MAPAS/fatia-ruim-3-bloco-grande"
mkdir -p "$MAPA_R3"
{
  echo "# Bloco 1 — fatia-ruim-3"
  echo
  echo "CONFIRMADO: TesteFuncao incrementa nX em uma unidade (fonte-teste.prw:3)."
  echo
  # preenchimento so para estourar o teto — nao precisa ser prosa de verdade.
  head -c 45000 /dev/zero | tr '\0' 'x'
} >"$MAPA_R3/bloco-01.md"

# --- regra 4a: pasta sem nenhum bloco ---------------------------------------
MAPA_R4A="$MAPAS/fatia-ruim-4a-pasta-vazia"
mkdir -p "$MAPA_R4A"

# --- regra 4b: pasta com blocos mas nenhum CONFIRMADO -----------------------
MAPA_R4B="$MAPAS/fatia-ruim-4b-sem-confirmado"
mkdir -p "$MAPA_R4B"
cat >"$MAPA_R4B/bloco-01.md" <<EOF
# Bloco 1 — fatia-ruim-4b

INFERIDO: TesteFuncao provavelmente incrementa nX.

LACUNA: nao confirmei nada de verdade aqui.
EOF

# --- casos --------------------------------------------------------------

validar_mapa "$MAPA_BOM" "$FONTE" >"$CAIXA/saida-bom.log" 2>&1
RESULTADO_BOM=$?
marca "mapa bem formado valida com exit 0" "$RESULTADO_BOM"
if [ "$RESULTADO_BOM" -ne 0 ]; then
  sed 's/^/       /' "$CAIXA/saida-bom.log"
fi

echo
echo "== regra 1 — CONFIRMADO sem citacao arquivo:linha =="
validar_mapa "$MAPA_R1" "$FONTE" >"$CAIXA/saida-r1.log" 2>&1
marca_vermelho_esperado "regra 1 reprova CONFIRMADO sem citacao" $?

echo
echo "== regra 1 (adversarial) — citacao com a forma certa, mas de outro arquivo =="
validar_mapa "$MAPA_R1B" "$FONTE" >"$CAIXA/saida-r1b.log" 2>&1
marca_vermelho_esperado "regra 1 reprova citacao que nao e do fonte mapeado" $?

echo
echo "== regra 2a — citacao para linha inexistente =="
validar_mapa "$MAPA_R2A" "$FONTE" >"$CAIXA/saida-r2a.log" 2>&1
marca_vermelho_esperado "regra 2 reprova citacao de linha inexistente" $?

echo
echo "== regra 2b — citacao para linha vazia =="
validar_mapa "$MAPA_R2B" "$FONTE" >"$CAIXA/saida-r2b.log" 2>&1
marca_vermelho_esperado "regra 2 reprova citacao de linha em branco" $?

echo
echo "== regra 3 — bloco acima de 40.000 caracteres =="
validar_mapa "$MAPA_R3" "$FONTE" >"$CAIXA/saida-r3.log" 2>&1
marca_vermelho_esperado "regra 3 reprova bloco grande demais" $?

echo
echo "== regra 4a — pasta sem nenhum bloco =="
validar_mapa "$MAPA_R4A" "$FONTE" >"$CAIXA/saida-r4a.log" 2>&1
marca_vermelho_esperado "regra 4 reprova pasta sem bloco" $?

echo
echo "== regra 4b — pasta com blocos mas sem nenhum CONFIRMADO =="
validar_mapa "$MAPA_R4B" "$FONTE" >"$CAIXA/saida-r4b.log" 2>&1
marca_vermelho_esperado "regra 4 reprova mapa sem nenhum CONFIRMADO" $?

echo
echo "== fora do temp, nada muda =="
# Prova de que a bateria nao escreveu nada fora do CAIXA temporario nem em
# docs/rainforest/mapas/ do repositorio.
STATUS_DEPOIS=$(git status --short 2>/dev/null)
STATUS_FORA=$(diff <(printf '%s
' "$STATUS_ANTES") <(printf '%s
' "$STATUS_DEPOIS") | grep '^>' || true)
if [ -z "$STATUS_FORA" ]; then
  ok=$((ok + 1)); echo "  ok   a bateria nao acrescentou nada ao git status"
else
  falhou=$((falhou + 1))
  echo "  FALHA a bateria acrescentou arquivo ao git status:"
  echo "$STATUS_FORA" | sed 's/^/       /'
fi

TOTAL=$((ok + falhou))
if [ "$TOTAL" -lt 8 ]; then
  falhou=$((falhou + 1))
  echo "  FALHA a bateria rodou so $TOTAL asserçoes — esperado >= 8. 'nenhuma falha' aqui seria vacuo, nao prova."
fi

echo
echo "-----------------------------------------"
echo "asserçoes: $TOTAL   ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
