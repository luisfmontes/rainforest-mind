#!/bin/bash
# Bateria da chave `foco` na statusline (2.0.0, D6): o prazo e a jornada so saem
# com `"foco": true` no config.json da pasta de dados. Roda o segmento de verdade
# (statusline/statusline.py) numa caixa mktemp -d, com RFM_ROOT, HOME, USERPROFILE e
# TEMP apontando para ela: o ~/.rainforest e o TEMP reais nunca sao lidos nem escritos.
#
# O relogio (HHhMM) segue sempre: a chave tira so o prazo e a jornada. A jornada usada
# aqui e "8h9": o relogio nunca tem essa forma, entao o grep nao confunde os dois.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PY=""
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
    PY="$cand"; break
  fi
done
if [ -z "$PY" ]; then
  echo "PULADA: esta bateria precisa de Python 3 (python3 ou python no PATH)" >&2
  exit 3
fi

# Caminho que o Python do Windows entende (C:/...), quando o bash e o Git Bash.
winpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT
RAIZ="$CAIXA/dados"
CASA="$CAIXA/casa"
TMPX="$CAIXA/temp"
mkdir -p "$RAIZ" "$CASA/.rainforest" "$TMPX"
echo "(caixa de areia: $CAIXA)"

# Um prazo que vence hoje, no FOCO.md da casa falsa, e uma jornada de 8h9 no cache.
printf '## Compromissos com prazo\n- Entrega ate %s\n' "$(date +%d/%m)" > "$CASA/.rainforest/FOCO.md"
printf '8h9' > "$TMPX/claude-statusline-jornada.txt"

CASA_W="$(winpath "$CASA")"
RAIZ_W="$(winpath "$RAIZ")"
TMP_W="$(winpath "$TMPX")"
CAIXA_W="$(winpath "$CAIXA")"

# Roda a statusline com a config dada (vazia = sem config.json) e devolve a linha sem cor.
linha_com() {
  rm -f "$RAIZ/config.json"
  if [ -n "$1" ]; then printf '%s' "$1" > "$RAIZ/config.json"; fi
  printf '{"cwd": "%s"}' "$CAIXA_W" | \
    HOME="$CASA_W" USERPROFILE="$CASA_W" TEMP="$TMP_W" RFM_ROOT="$RAIZ_W" \
    RAINFOREST_VERSAO_URL="http://127.0.0.1:1/x" \
    "$PY" "$SRC/statusline/statusline.py" | sed 's/\x1b\[[0-9;]*m//g'
}

tem_texto() { printf '%s' "$1" | grep -q -- "$2"; }
sem_texto() { ! printf '%s' "$1" | grep -q -- "$2"; }

ok=0; falhou=0
afirma() {
  local nome="$1"; shift
  if "$@"; then
    ok=$((ok + 1)); echo "ok    $nome"
  else
    falhou=$((falhou + 1)); echo "FALHA $nome"
  fi
}

echo
# Caso 1: sem config.json, nada de prazo nem de jornada; o relogio segue.
S=$(linha_com "")
echo "       saida: $S"
afirma "sem foco na config, a linha não tem prazo nem jornada" sem_texto "$S" "prazo"
afirma "sem foco na config, a linha não tem prazo nem jornada (jornada)" sem_texto "$S" "8h9"
afirma "sem foco na config, o relógio segue na linha" tem_texto "$S" "[0-9][0-9]h[0-9][0-9]"

# Caso 2: config sem a chave `foco` (so a escada): mesmo resultado.
S=$(linha_com '{"escada-intensidade": "enxuto"}')
echo "       saida: $S"
afirma "config sem a chave foco, a linha não tem prazo nem jornada" sem_texto "$S" "prazo"
afirma "config sem a chave foco, a linha não tem prazo nem jornada (jornada)" sem_texto "$S" "8h9"

# Caso 3: `foco` false gravado: o mesmo que ausente.
S=$(linha_com '{"foco": false}')
echo "       saida: $S"
afirma "foco false gravado, a linha não tem prazo nem jornada" sem_texto "$S" "prazo"

# Caso 4: config ilegivel: qualquer erro conta como desligado.
S=$(linha_com '{"foco": tru')
echo "       saida: $S"
afirma "config quebrada, a linha não tem prazo nem jornada" sem_texto "$S" "prazo"

# Caso 5: com `{"foco": true}`, a linha tem o prazo e a jornada, como hoje.
S=$(linha_com '{"foco": true}')
echo "       saida: $S"
afirma "com foco true, a linha tem o prazo de hoje" tem_texto "$S" "prazo hoje"
afirma "com foco true, a linha tem a jornada" tem_texto "$S" "8h9"

# Casos 6 a 8: a config do PROJETO, como no config.cjs (achado 1 da revisao). O projeto
# e um repo git na caixa; a janela roda de um subdiretorio dele, e o config.json do
# projeto mora na raiz (o checkout principal), nao no cwd.
PROJ="$CAIXA/proj"
mkdir -p "$PROJ/sub/fundo" "$PROJ/.rainforest"
git -C "$PROJ" init -q 2>/dev/null
SUB_W="$(winpath "$PROJ/sub/fundo")"
linha_proj() {
  rm -f "$RAIZ/config.json" "$PROJ/.rainforest/config.json"
  if [ -n "$1" ]; then printf '%s' "$1" > "$PROJ/.rainforest/config.json"; fi
  if [ -n "$2" ]; then printf '%s' "$2" > "$RAIZ/config.json"; fi
  printf '{"cwd": "%s"}' "$SUB_W" | \
    HOME="$CASA_W" USERPROFILE="$CASA_W" TEMP="$TMP_W" RFM_ROOT="$RAIZ_W" \
    RAINFOREST_VERSAO_URL="http://127.0.0.1:1/x" \
    "$PY" "$SRC/statusline/statusline.py" | sed 's/\x1b\[[0-9;]*m//g'
}

S=$(linha_proj '{"foco": true}' "")
echo "       saida: $S"
afirma "foco true so no projeto, a linha tem o prazo (subdiretorio le a raiz do repo)" tem_texto "$S" "prazo hoje"

S=$(linha_proj '{"foco": false}' '{"foco": true}')
echo "       saida: $S"
afirma "projeto false vence usuario true: a linha não tem prazo" sem_texto "$S" "prazo"

S=$(linha_proj '{"escada-intensidade": "enxuto"}' '{"foco": true}')
echo "       saida: $S"
afirma "projeto sem a chave cai no usuario true: a linha tem o prazo" tem_texto "$S" "prazo hoje"

echo
TOTAL=$((ok + falhou))
if [ "$falhou" -ne 0 ]; then
  echo "FALHA: $falhou de $TOTAL casos do foco na statusline reprovaram" >&2
  exit 1
fi
echo "os $TOTAL casos do foco na statusline passaram"
