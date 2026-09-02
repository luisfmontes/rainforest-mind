#!/bin/bash
# Instalador da statusline versionada no plugin, e limpeza dos arquivos antigos.
#
# Substitui a copia manual dos quatro arquivos em ~/.claude por um script
# repetivel e conferivel. Copia o shim resolvedor (statusline-command.sh) do
# repositorio e remove as versoes antigas se o shim conseguir localizar a
# nova statusline.py no cache do plugin. Recusa-se a rodar se a versao nova
# ainda nao esta publicada, para nao deixar a statusline vazia.
#
# Mexe no ambiente do usuario por desenho, so deve ser rodado pela janela
# principal depois do merge. Modo --conferir e trava de seguranca impedem
# uso acidental e facilitam teste com HOME sintetico.

set -e -u

# Resolver a raiz do repositorio a partir do diretorio do script.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Destino padrao: ~/.claude, substituivel por variavel de ambiente ou flag.
DESTINO="${STATUSLINE_INSTALL_DEST:-$(cd ~ 2>/dev/null && pwd || echo "$HOME")/.claude}"
CONFERIR=0
FORCAR=0

# Arquivo a instalar (relativo a raiz do repo) e arquivos a remover.
SHIM="$REPO_ROOT/statusline/statusline-command.sh"
REMOVER=(
  "statusline.py"
  "statusline-jornada.sh"
  "testa-statusline-prazo.py"
  "statusline.py.bak-antes-prazo-20260818"
)

# Parse de argumentos.
while [ $# -gt 0 ]; do
  case "$1" in
    --conferir)
      CONFERIR=1
      shift
      ;;
    --forcar)
      FORCAR=1
      shift
      ;;
    --destino)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf "Erro: --destino exige um argumento\n" >&2
        printf "Uso: %s [--conferir] [--forcar] [--destino <dir>]\n" "$(basename "$0")" >&2
        exit 1
      fi
      DESTINO="$2"
      shift 2
      ;;
    *)
      printf "Uso: %s [--conferir] [--forcar] [--destino <dir>]\n" "$(basename "$0")" >&2
      exit 1
      ;;
  esac
done

# Conferir que o shim existe no repositorio.
if [ ! -f "$SHIM" ]; then
  printf "Erro: %s nao encontrado\n" "$SHIM" >&2
  exit 1
fi

# Lista os caminhos que serao tocados.
printf "Instalador da statusline versionada\n"
printf "\nDestino: %s\n\n" "$DESTINO"

# Modo --conferir: lista o que faria e sai sem mudar nada, sem criar o destino.
if [ $CONFERIR -eq 1 ]; then
  printf "Modo --conferir (sem mudar nada):\n\n"

  # Conferir se o destino existe.
  if [ ! -d "$DESTINO" ]; then
    printf "Aviso: destino nao existe\n"
    printf "  Instalar: %s/statusline-command.sh (novo shim resolvedor)\n" "$DESTINO"
    for arquivo in "${REMOVER[@]}"; do
      printf "  Nada: %s/%s (nao existe)\n" "$DESTINO" "$arquivo"
    done
  else
    printf "  Instalar: %s/statusline-command.sh (novo shim resolvedor)\n" "$DESTINO"
    for arquivo in "${REMOVER[@]}"; do
      if [ -f "$DESTINO/$arquivo" ]; then
        printf "  Remover: %s/%s (existe)\n" "$DESTINO" "$arquivo"
      else
        printf "  Nada: %s/%s (nao existe)\n" "$DESTINO" "$arquivo"
      fi
    done
  fi
  printf "\n"
  exit 0
fi

# Modo normal: instala o shim e remove os antigos, com trava de seguranca.

# Passo 1: Copiar o shim para um temporario, com trap para limpar.
SHIM_TEMP=$(mktemp)
trap "rm -f '$SHIM_TEMP'" EXIT
cp "$SHIM" "$SHIM_TEMP"

# Passo 2: Trava de seguranca — verifica que a statusline.py nova existe no cache.
# A mesma busca que o shim faz: acha a versao mais nova por mtime.
if [ $FORCAR -eq 0 ]; then
  printf "Verificando se a versao nova esta publicada no cache do plugin...\n"

  # Cache padrao: mesmo glob que o shim usa. A variavel recebe a raiz (sem
  # curinga de versao); a busca acrescenta o nivel de versao.
  CACHE_ROOT="${RAINFOREST_STATUSLINE_CACHE:-$(cd ~ 2>/dev/null && pwd || echo "$HOME")/.claude*/plugins/cache/rainforest-mind/rainforest-mind}"

  # Procurar statusline.py com mtime mais novo (sem aspas para o glob expandir).
  STATUSLINE=$(ls -1t $CACHE_ROOT/*/statusline/statusline.py 2>/dev/null | head -1 || true)

  # Se nao achou, nao fazer nada e sair com erro.
  if [ -z "$STATUSLINE" ] || [ ! -f "$STATUSLINE" ]; then
    printf "Erro: statusline.py nao encontrado no cache do plugin.\n" >&2
    printf "A versao nova ainda nao foi publicada. Nao foi feita nenhuma alteracao.\n" >&2
    rm "$SHIM_TEMP"
    exit 1
  fi

  printf "OK: versao nova localizada em %s\n" "$STATUSLINE"
fi

# Passo 3: Criar o destino apos trava passar (ou ser forcada). So depois disso
# e seguro garantir que nao ha estado incompleto se a instalacao falhar.
mkdir -p "$DESTINO"

# Passo 4: Trava passou (ou foi forcada). Instalar o shim de verdade.
printf "Copiando shim resolvedor...\n"
cp "$SHIM_TEMP" "$DESTINO/statusline-command.sh"
rm "$SHIM_TEMP"

# Passo 5: Remover os arquivos antigos.
printf "Removendo arquivos antigos...\n"
for arquivo in "${REMOVER[@]}"; do
  if [ -f "$DESTINO/$arquivo" ]; then
    rm "$DESTINO/$arquivo"
    printf "  Removido: %s\n" "$arquivo"
  fi
done

printf "\nInstalacao concluida.\n"
