#!/bin/bash
# Bateria da raiz do vigias/ERROS.md (Issue #112).
#
# Ela PROVOCA os caminhos de erro do run-vigia.ps1 de verdade, com RFM_ROOT
# apontando para uma pasta de dados DIFERENTE do plugin — que e a unica
# configuracao em que o defeito aparece. Sem RFM_ROOT, $root cai no proprio
# plugin e as escritas acertam o mesmo arquivo por coincidencia: uma bateria que
# rodasse so assim ficaria verde com o defeito inteiro no lugar.
#
# Tres dos quatro caminhos de erro sao exercitados por EXECUCAO. O quarto (a
# bridge que nao sobe em 60s) dorme 60 segundos por desenho e fica coberto pela
# trava estatica do caso 3 — dito aqui porque silencio sobre cobertura parcial e
# indistinguivel de cobertura total.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

command -v powershell >/dev/null 2>&1 || { echo "FALHA powershell nao esta no PATH — esta bateria nao significaria nada"; exit 1; }
win() { cygpath -w "$1"; }

montar() {
  rm -rf "$SB/plugin" "$SB/dados"
  mkdir -p "$SB/plugin/vigias" "$SB/plugin/hooks/lib" "$SB/plugin/scripts" "$SB/dados/vigias"
  cp "$SRC/vigias/run-vigia.ps1" "$SB/plugin/vigias/run-vigia.ps1"
  # O plugin da caixa precisa de scripts/ e hooks/ inteiros: o run-vigia.ps1
  # pergunta o toggle rodando `node scripts/setup.cjs --ligado vigias`, e sem isso
  # ele para na PRIMEIRA escrita de erro — que ja era a certa. A bateria ficaria
  # verde sem nunca chegar nas tres linhas que esta issue conserta.
  cp -r "$SRC/scripts/." "$SB/plugin/scripts/"
  cp -r "$SRC/hooks/." "$SB/plugin/hooks/"
  printf '{"vigias": true}
' > "$SB/dados/config.json"
  : > "$SB/plugin/vigias/ERROS.md"
  : > "$SB/dados/vigias/ERROS.md"
  printf 'prompt de caixa\n' > "$SB/dados/vigias/sentinela-foco.md"
}

# Roda o run-vigia.ps1 da caixa com RFM_ROOT na pasta de DADOS — a configuracao
# em que as duas raizes se partem. Extras vao como argumento solto.
rodar() {
  RFM_ROOT="$(win "$SB/dados")" powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$(win "$SB/plugin/vigias/run-vigia.ps1")" -Vigia sentinela-foco ${1:-} \
    > /dev/null 2>&1
  echo $?
}

# Conta pelo marcador do vigia, nao por '^- ': o Out-File -Encoding utf8 do
# PowerShell 5.1 escreve BOM, entao a PRIMEIRA linha do arquivo nao comeca com
# '-' e some da contagem — o arquivo tinha 2 linhas e a conta dava 1.
linhas() { grep -c "\[sentinela-foco\]" "$1" 2>/dev/null; }

echo "== 1. com RFM_ROOT definido, as escritas de erro caem todas no mesmo arquivo =="
montar
# Caminho A: -Cwd que nao existe.
rodar "-Cwd $(win "$SB/nao-existe")" > /dev/null
# Caminho B: sem destino de envio -> Stop-ComErro.
rodar > /dev/null
NO_PLUGIN=$(linhas "$SB/plugin/vigias/ERROS.md")
NO_DADOS=$(linhas "$SB/dados/vigias/ERROS.md")
echo "  -- ERROS.md do plugin ($NO_PLUGIN linha(s)):"
sed 's/^/     /' "$SB/plugin/vigias/ERROS.md" | head -4
echo "  -- ERROS.md da pasta de dados ($NO_DADOS linha(s)):"
sed 's/^/     /' "$SB/dados/vigias/ERROS.md" | head -4
if [ "$NO_PLUGIN" -ge 1 ]; then
  ok=$((ok+1)); echo "  ok    o plugin recebeu as linhas de erro"
else
  falhou=$((falhou+1)); echo "  FALHA nenhum erro chegou no plugin — os caminhos nao foram provocados"
fi
igual "a pasta de dados nao recebeu erro nenhum" "$NO_DADOS" "0"
# Sem isto a bateria passa por vazio: se a caixa parar no toggle (linha 31, que
# JA estava certa), o plugin recebe linha e a pasta de dados fica zerada — verde
# sem nunca tocar as tres linhas que esta issue conserta. Aconteceu na primeira
# versao, porque o `cp -r` aninhou scripts/ dentro de scripts/.
grep -qF -- '-Cwd nao existe' "$SB/plugin/vigias/ERROS.md" && a=sim || a=nao
igual "chegou no caminho do -Cwd inexistente (era \$root)" "$a" "sim"
grep -qF -- 'sem destino de envio' "$SB/plugin/vigias/ERROS.md" && b=sim || b=nao
igual "chegou no caminho do Stop-ComErro (era \$root)" "$b" "sim"

echo
echo "== 2. sem RFM_ROOT o comportamento nao muda =="
montar
( unset RFM_ROOT; powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$(win "$SB/plugin/vigias/run-vigia.ps1")" -Vigia sentinela-foco > /dev/null 2>&1 )
igual "a pasta de dados continua sem erro" "$(linhas "$SB/dados/vigias/ERROS.md")" "0"

echo
echo "== 3. nenhuma escrita de ERROS.md usa a raiz de dados =="
# Linha de EXECUCAO, nao o arquivo inteiro: o comentario que explica a regra cita
# `Join-Path $root "vigias\ERROS.md"` de proposito, e apagar o comentario para a
# trava passar seria apagar a razao.
achou=0
for f in "$SRC"/vigias/*.ps1; do
  if grep -vE '^\s*#' "$f" | grep -F 'ERROS.md' | grep -qF '$root'; then
    achou=1; echo "        em $(basename "$f")"
  fi
done
igual "nenhuma escrita de ERROS.md colada a \$root" "$achou" "0"
# O outro sentido: a mesma string em comentario NAO pode acender a trava.
if grep -E '^\s*#' "$SRC/vigias/run-vigia.ps1" | grep -F 'ERROS.md' | grep -qF '$root'; then
  ok=$((ok+1)); echo "  ok    o comentario cita a forma errada e a trava nao acende por isso"
else
  falhou=$((falhou+1)); echo "  FALHA o comentario deveria citar a forma errada — sem isso a trava nao esta provada nos dois sentidos"
fi

echo
echo "== 4. o leitor le do plugin =="
if grep -q "lerLinhasDoPlugin('vigias/ERROS.md')" "$SRC/vigias/dados-batedor-repos.js"; then
  ok=$((ok+1)); echo "  ok    o dados-batedor-repos.js le do plugin, a mesma raiz em que se escreve"
else
  falhou=$((falhou+1)); echo "  FALHA produtor e consumidor voltaram a discordar de raiz"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
