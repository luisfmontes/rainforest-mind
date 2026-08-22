#!/usr/bin/env bash
# Ponto de entrada da statusline instalado fora do repositorio.
#
# Acha a versao mais nova do statusline.py dentro do cache do plugin e a executa,
# passando o JSON da barra por stdin. Roda fora do repositorio porque a barra do
# harness precisa disso sempre, mesmo quando o plugin nao esta instalado.

set -u

# A raiz de busca sai da variavel RAINFOREST_STATUSLINE_CACHE, com default que
# cobre as duas pastas de configuracao (trabalho e pessoal). A variavel existe
# para a bateria poder provar as tres bordas sem depender do plugin instalado.
# Recebe a raiz (sem curinga de versao); a busca acrescenta o nivel de versao.
CACHE_ROOT="${RAINFOREST_STATUSLINE_CACHE:-/c/Users/Luis/.claude*/plugins/cache/rainforest-mind/rainforest-mind}"

# Escolhe o statusline.py com mtime mais novo. Se a ordenacao do ls -1t sobre
# o diretorio nao der isso de forma confiavel (edge cases de cache de disco ou
# fuso), ordene pelo mtime do proprio statusline.py.
STATUSLINE=$(ls -1t $CACHE_ROOT/*/statusline/statusline.py 2>/dev/null | head -1)

if [ -z "$STATUSLINE" ]; then
  # Nao achou nada: sai 0 em silencio, sem imprimir nada e sem mensagem de erro.
  # Barra vazia e ruim; barra que trava ou suja o harness e pior.
  exit 0
fi

# Achou: exec python preservando stdin, porque o harness manda o JSON da barra
# por stdin.
# Conferir que o interpretador existe. Se nao existir, sair 0 em silencio,
# como no caso "nenhum casamento" — barra vazia e ruim; barra que trava ou suja
# o harness e pior.
if ! command -v python >/dev/null 2>&1; then
  exit 0
fi
exec python "$STATUSLINE"
