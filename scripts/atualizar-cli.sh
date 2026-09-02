#!/bin/bash
# Atualiza a CLI do Claude via WinGet, com rollback automatico e um backup so.
#
# Resolve a pasta do pacote, le a versao atual, renomeia o exe para liberar o
# caminho com sessoes vivas, roda winget upgrade, e confere se a versao subiu.
# Versao que nao subiu faz rollback automatico — renomear de volta e sair diferente
# de zero, porque um PATH apontando para pasta sem executavel e o pior estado possivel.
# Mantém exatamente um backup (a versao anterior) e apaga os mais antigos.
#
# Modo --conferir lista o que faria e sai sem mudar nada.
# Destinado a ser rodado a mao pela janela principal — trocar executavel de 300 MB
# por baixo de sessoes vivas e acao irreversivel o suficiente para pedir intencao.

set -e -u

# Pasta do pacote do WinGet, substituivel por variavel de ambiente. A raiz sai
# do HOME de quem roda: ter um nome chumbado no DEFAULT faz o script funcionar
# so na maquina de quem o escreveu, e a variavel de escape vira obrigatoria em
# vez de opcional — que e o oposto do que "substituivel" quer dizer.
PACOTE="${ATUALIZAR_CLI_PACOTE:-$(cd ~ 2>/dev/null && pwd || echo "$HOME")/AppData/Local/Microsoft/WinGet/Packages/Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe}"

# Nome do executavel winget, substituivel por variavel de ambiente (facilita teste).
WINGET_CMD="${ATUALIZAR_CLI_WINGET:-winget}"

# Modo conferir: so imprime o que faria, nao muda nada.
CONFERIR=0

# Parse de argumentos.
while [ $# -gt 0 ]; do
  case "$1" in
    --conferir)
      CONFERIR=1
      shift
      ;;
    *)
      printf "Uso: %s [--conferir]\n" "$(basename "$0")" >&2
      exit 1
      ;;
  esac
done

# Passo 0: Conferir que a pasta existe. Pasta inexistente = sai != 0 sem tocar nada.
if [ ! -d "$PACOTE" ]; then
  printf "Erro: pasta do pacote nao existe: %s\n" "$PACOTE" >&2
  exit 1
fi

# Localiza o executavel da CLI.
CLAUDE_EXE="$PACOTE/claude.exe"

# Passo 0.5: Auto-cura do estado interrompido.
#
# O trap de emergencia cobre o script morrendo por sinal, mas nao cobre
# SIGKILL nem queda de energia — nenhum script bash cobre. Se a maquina morrer
# entre o rename e a instalacao, sobra so o .bak, sem claude.exe: e o pior
# estado possivel que a decisao D2 nomeia, com o PATH apontando para uma pasta
# sem executavel. Sem isto, a proxima execucao apenas dizia "executavel nao
# encontrado" e saia, deixando a maquina sem CLI ate alguem descobrir sozinho
# que bastava renomear o .bak — que e justamente o conhecimento que este
# script existe para guardar.
#
# Restaura so quando ha exatamente UM backup. Com dois ou mais, qual e o bom
# vira adivinhacao, e adivinhar qual binario de 300 MB promover e pior que
# parar e perguntar.
if [ ! -f "$CLAUDE_EXE" ]; then
  BAKS=$(find "$PACOTE" -maxdepth 1 -name "claude-*.exe.bak" -type f | sort -V)
  BAKS_N=$(echo "$BAKS" | grep -c . || true)

  if [ "$BAKS_N" -eq 1 ]; then
    if [ $CONFERIR -eq 1 ]; then
      printf "Estado interrompido: claude.exe ausente, um backup presente.\n"
      printf "  Restauraria: %s -> claude.exe\n" "$(basename "$BAKS")"
      printf "  (modo --conferir: nada foi mudado)\n"
      exit 0
    fi
    printf "Estado interrompido detectado: claude.exe ausente, um backup presente.\n" >&2
    if ! mv "$BAKS" "$CLAUDE_EXE"; then
      printf "Erro: nao consegui restaurar %s\n" "$(basename "$BAKS")" >&2
      exit 1
    fi
    printf "Auto-cura: %s -> claude.exe\n" "$(basename "$BAKS")" >&2

  elif [ "$BAKS_N" -gt 1 ]; then
    printf "Erro: claude.exe ausente e %d backups na pasta — nao da para\n" "$BAKS_N" >&2
    printf "adivinhar qual promover. Escolha um e renomeie a mao:\n" >&2
    echo "$BAKS" | while read -r b; do printf "  %s\n" "$(basename "$b")" >&2; done
    exit 1

  else
    printf "Erro: executavel nao encontrado: %s\n" "$CLAUDE_EXE" >&2
    exit 1
  fi
fi

# Passo 1: Ler a versao atual executando o binario. Execucao, nao metadado.
# Binario pode imprimir "X.Y.Z (Claude Code)" ou outro formato — extrair so o N.N.N.

VERSAO_ATUAL_RAW=$("$CLAUDE_EXE" --version 2>/dev/null || echo "")
if [ -z "$VERSAO_ATUAL_RAW" ]; then
  printf "Erro: nao consegui ler a versao atual\n" >&2
  exit 1
fi

# Extrair apenas o padrão N.N.N (ex.: "2.1.231" de "2.1.231 (Claude Code)").
VERSAO_ATUAL=$(echo "$VERSAO_ATUAL_RAW" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
if [ -z "$VERSAO_ATUAL" ]; then
  printf "Erro: versao nao e um numero valido (N.N.N): %s\n" "$VERSAO_ATUAL_RAW" >&2
  exit 1
fi

printf "Versao atual: %s\n" "$VERSAO_ATUAL"

# Modo --conferir: lista o que faria e sai sem mudar nada.
if [ $CONFERIR -eq 1 ]; then
  printf "\nModo --conferir (sem mudar nada):\n"
  printf "  Renomear: %s -> claude-%s.exe.bak\n" "$(basename "$CLAUDE_EXE")" "$VERSAO_ATUAL"
  printf "  Comando winget: %s upgrade Anthropic.ClaudeCode --accept-source-agreements --accept-package-agreements --disable-interactivity\n" "$WINGET_CMD"
  printf "  Conferir versao nova executando: claude.exe --version\n"
  printf "  Se nao subiu numericamente, rollback automatico\n"
  printf "  Limpeza: manter exatamente um .bak, apagar os mais antigos\n"
  exit 0
fi

# Passo 2: Preparar rollback — guardar o caminho do backup a ser criado.
CLAUDE_BAK="$PACOTE/claude-$VERSAO_ATUAL.exe.bak"

# Trap para rollback de emergencia. Se o script morrer com set -e enquanto
# claude.exe nao existe e .bak existe, renomeia de volta — evita deixar PATH
# apontando para pasta vazia (o pior estado possivel).
trap_rollback_emergencia() {
  # So entra aqui se o script saiu diferente de zero.
  if [ ! -f "$CLAUDE_EXE" ] && [ -f "$CLAUDE_BAK" ]; then
    # Executavel desapareceu enquanto .bak existe — situacao anormal.
    printf "Emergencia: claude.exe desapareceu, restaurando de backup\n" >&2
    if mv "$CLAUDE_BAK" "$CLAUDE_EXE" 2>/dev/null; then
      printf "Rollback de emergencia: claude-%s.exe.bak -> claude.exe\n" "$VERSAO_ATUAL" >&2
    else
      printf "Erro: nao consegui restaurar de emergencia\n" >&2
    fi
  fi
}
trap trap_rollback_emergencia EXIT

# Passo 3: Renomear o exe para liberar o caminho. No Windows, nao da para APAGAR
# um exe em uso, mas da para MOVER, e os processos vivos seguem lendo o arquivo movido.
# Isto que libera o caminho para winget instalar.
if [ -f "$CLAUDE_BAK" ]; then
  printf "Aviso: backup da versao anterior ja existe: %s\n" "$CLAUDE_BAK" >&2
fi

mv "$CLAUDE_EXE" "$CLAUDE_BAK"
printf "Renomeado: claude.exe -> claude-%s.exe.bak\n" "$VERSAO_ATUAL"

# Passo 4: Rodar winget upgrade. Se isso falhar, rollback e sair != 0.
printf "Executando winget upgrade...\n"
if ! "$WINGET_CMD" upgrade Anthropic.ClaudeCode --accept-source-agreements --accept-package-agreements --disable-interactivity; then
  printf "Erro: winget upgrade falhou\n" >&2
  # Rollback: renomear de volta.
  mv "$CLAUDE_BAK" "$CLAUDE_EXE"
  printf "Rollback: claude-%s.exe.bak -> claude.exe\n" "$VERSAO_ATUAL"
  exit 1
fi

# Passo 5: Conferir que o novo exe existe e ler a versao nova.
if [ ! -f "$CLAUDE_EXE" ]; then
  printf "Erro: novo executavel nao foi instalado\n" >&2
  # Rollback.
  mv "$CLAUDE_BAK" "$CLAUDE_EXE"
  printf "Rollback: claude-%s.exe.bak -> claude.exe\n" "$VERSAO_ATUAL"
  exit 1
fi

VERSAO_NOVA_RAW=$("$CLAUDE_EXE" --version 2>/dev/null || echo "")
if [ -z "$VERSAO_NOVA_RAW" ]; then
  printf "Erro: nao consegui ler a versao do novo executavel\n" >&2
  # Rollback.
  mv "$CLAUDE_BAK" "$CLAUDE_EXE"
  printf "Rollback: claude-%s.exe.bak -> claude.exe\n" "$VERSAO_ATUAL"
  exit 1
fi

# Extrair apenas o padrão N.N.N (ex.: "2.1.239" de "2.1.239 (Claude Code)").
VERSAO_NOVA=$(echo "$VERSAO_NOVA_RAW" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
if [ -z "$VERSAO_NOVA" ]; then
  printf "Erro: versao nova nao e um numero valido (N.N.N): %s\n" "$VERSAO_NOVA_RAW" >&2
  # Rollback.
  mv "$CLAUDE_BAK" "$CLAUDE_EXE"
  printf "Rollback: claude-%s.exe.bak -> claude.exe\n" "$VERSAO_ATUAL"
  exit 1
fi

printf "Versao nova: %s\n" "$VERSAO_NOVA"

# Passo 6: Comparar versoes numericamente por componente (N.N.N).
# Funcao auxiliar: compara duas versoes no formato X.Y.Z.
# Retorna 0 se versao_nova > versao_atual, 1 caso contrario.
version_subiu() {
  local atual="$1"
  local nova="$2"

  # Extrai os componentes numericos.
  local atual_major=$(echo "$atual" | cut -d. -f1)
  local atual_minor=$(echo "$atual" | cut -d. -f2)
  local atual_patch=$(echo "$atual" | cut -d. -f3)

  local nova_major=$(echo "$nova" | cut -d. -f1)
  local nova_minor=$(echo "$nova" | cut -d. -f2)
  local nova_patch=$(echo "$nova" | cut -d. -f3)

  # Comparacao por componente: major, depois minor, depois patch.
  if [ "$nova_major" -gt "$atual_major" ]; then
    return 0
  elif [ "$nova_major" -lt "$atual_major" ]; then
    return 1
  fi

  if [ "$nova_minor" -gt "$atual_minor" ]; then
    return 0
  elif [ "$nova_minor" -lt "$atual_minor" ]; then
    return 1
  fi

  if [ "$nova_patch" -gt "$atual_patch" ]; then
    return 0
  elif [ "$nova_patch" -lt "$atual_patch" ]; then
    return 1
  fi

  # Versoes iguais = versao nao subiu.
  return 1
}

if ! version_subiu "$VERSAO_ATUAL" "$VERSAO_NOVA"; then
  printf "Erro: versao nao subiu (esperava > %s, obtive %s)\n" "$VERSAO_ATUAL" "$VERSAO_NOVA" >&2
  # Rollback.
  mv "$CLAUDE_BAK" "$CLAUDE_EXE"
  printf "Rollback: claude-%s.exe.bak -> claude.exe\n" "$VERSAO_ATUAL"
  exit 1
fi

printf "Sucesso: versao subiu de %s para %s\n" "$VERSAO_ATUAL" "$VERSAO_NOVA"

# Passo 7: Limpeza de backups antigos. Manter exatamente UM .bak (o da versao
# imediatamente anterior = o que acabou de ser criado). Apagar os mais antigos.
# 265 MB por release acumulando em silencio e vazamento de disco.
BACKUPS=$(find "$PACOTE" -maxdepth 1 -name "claude-*.exe.bak" -type f | sort -V)
# `grep -c .` ja imprime 0 com entrada vazia — so sai com status 1 nesse caso,
# e um `|| echo 0` depois disso DUPLICARIA a linha ("0\n0"), fazendo o teste
# numerico abaixo estourar com "integer expression expected". Por isso o
# resultado e capturado e so entao usado. A bateria ao lado ja documentava
# este gotcha na sua propria funcao contar_bak, sem ter conferido o alvo.
# O `|| true` fica DENTRO da substituicao, e nao depois: `grep -c` sai 1 com
# entrada vazia, e com `set -e` ligado isso mataria o script no assinalamento.
# Dentro, ele so zera o status — a saida "0" que o grep ja imprimiu e mantida.
BACKUP_COUNT=$(echo "$BACKUPS" | grep -c . || true)

if [ "$BACKUP_COUNT" -gt 1 ]; then
  # Manter apenas o mais novo (que e o que acabou de ser renomeado).
  # Apagar todos os outros.
  echo "$BACKUPS" | head -n -1 | while read -r backup_antigo; do
    # Tenta apagar. Se nao conseguir (arquivo em uso), avisa e segue.
    if rm "$backup_antigo" 2>/dev/null; then
      printf "Limpeza: removido backup antigo: %s\n" "$(basename "$backup_antigo")"
    else
      printf "Aviso: nao consegui remover backup antigo (em uso?): %s\n" "$(basename "$backup_antigo")" >&2
    fi
  done
fi

printf "\nAtualizacao concluida: %s -> %s\n" "$VERSAO_ATUAL" "$VERSAO_NOVA"
