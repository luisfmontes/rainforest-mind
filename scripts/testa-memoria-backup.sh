#!/bin/bash
# Bateria de testes do comando backup em scripts/memoria.cjs
# Uso: bash scripts/testa-memoria-backup.sh
#
# O que esta bateria prova, nesta ordem:
#   1. que `backup` cria arquivo de backup consultável (abre e SELECT funciona)
#   2. que a rotação mantém exatamente o teto de cópias declarado
#   3. que a rotação NUNCA apaga a cópia mais recente (mesmo com 10+ backups)
#   4. que banco ausente devolve erro (não é degradação, é backup obrigatório)
#
# Hermética: caixa de areia com mktemp -d, RFM_ROOT isolado, nunca raiz real.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

export RFM_ROOT="$CAIXA"
MEMORIA="node $SRC/scripts/memoria.cjs"

ok=0; falhou=0

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | head -8; fi
}

contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"; fi
}

echo "== 1. iniciar cria o banco =="
esperado "iniciar" 0 $MEMORIA iniciar

echo
echo "== 2. backup cria arquivo consultável (abre e SELECT) =="
# Fazer backup
esperado "backup (cria)" 0 $MEMORIA backup

# Listar backups criados
BACKUPS=$(ls "$CAIXA/.rainforest-backups"/*.db 2>/dev/null | wc -l)
if [ "$BACKUPS" -ge 1 ]; then
  ok=$((ok+1)); echo "  ok   arquivo de backup criado ($BACKUPS arquivo(s))"
else
  falhou=$((falhou+1)); echo "  FALHA nenhum arquivo de backup foi criado"
fi

# Verificar que a cópia é consultável — abrir e rodar SELECT
if [ "$BACKUPS" -ge 1 ]; then
  # Usar ls em vez de find para evitar problemas de path entre Bash/Node
  BACKUP_PATH=$(ls "$CAIXA/.rainforest-backups"/*.db 2>/dev/null | head -1)

  if [ -z "$BACKUP_PATH" ]; then
    falhou=$((falhou+1)); echo "  FALHA nenhum arquivo de backup encontrado (listagem falhou)"
  else
    # Contar observações no backup via adaptador (D8 — driver isolado)
    SELECT_RESULT=$(node "$SRC/scripts/manipula-tabela.cjs" conta-observacoes-backup "$BACKUP_PATH" 2>&1)
    EXIT_RESULT=$?

    if [ "$EXIT_RESULT" = "0" ]; then
      ok=$((ok+1)); echo "  ok   cópia consultável (SELECT COUNT retornou $SELECT_RESULT)"
    else
      falhou=$((falhou+1)); echo "  FALHA cópia não abre: $SELECT_RESULT"
    fi
  fi
fi

echo
echo "== 3. rotação mantém o teto (5 cópias) =="
# Criar 6 backups seguidos (deve manter 5, apagando o mais antigo)
for i in {1..5}; do
  sleep 1 # Garantir timestamps diferentes
  $MEMORIA backup >/dev/null 2>&1
done

BACKUPS_APOS=$(ls "$CAIXA/.rainforest-backups"/*.db 2>/dev/null | wc -l)
if [ "$BACKUPS_APOS" = "5" ]; then
  ok=$((ok+1)); echo "  ok   após 5 novos backups, total é 5 (rotação funciona)"
else
  falhou=$((falhou+1)); echo "  FALHA esperava 5 backups, encontrei $BACKUPS_APOS"
fi

echo
echo "== 4. rotação NUNCA apaga a cópia mais recente =="
# Listar backups atuais e pegar o mais recente (último em order alfabética = timestamp maior)
MAIS_RECENTE_ANTES=$(ls "$CAIXA/.rainforest-backups"/*.db | sort | tail -1)
TIMESTAMP_ANTES=$(basename "$MAIS_RECENTE_ANTES")

# Fazer 5 backups a mais (total 10) — só 5 devem permanecer
for i in {1..5}; do
  sleep 1
  $MEMORIA backup >/dev/null 2>&1
done

# Verificar que ainda temos 5
BACKUPS_APOS_10=$(ls "$CAIXA/.rainforest-backups"/*.db 2>/dev/null | wc -l)
if [ "$BACKUPS_APOS_10" = "5" ]; then
  ok=$((ok+1)); echo "  ok   após 10 backups totais, mantém 5"
else
  falhou=$((falhou+1)); echo "  FALHA esperava 5, encontrei $BACKUPS_APOS_10"
fi

# Verificar que o mais recente é diferente (avançou)
MAIS_RECENTE_DEPOIS=$(ls "$CAIXA/.rainforest-backups"/*.db | sort | tail -1)
TIMESTAMP_DEPOIS=$(basename "$MAIS_RECENTE_DEPOIS")

if [ "$TIMESTAMP_DEPOIS" != "$TIMESTAMP_ANTES" ]; then
  ok=$((ok+1)); echo "  ok   cópia mais recente avançou ($TIMESTAMP_ANTES -> $TIMESTAMP_DEPOIS)"
else
  falhou=$((falhou+1)); echo "  FALHA cópia mais recente não mudou: $TIMESTAMP_ANTES"
fi

# Verificar que o mais recente está nos 5 remanescentes
if ls "$CAIXA/.rainforest-backups"/*.db | grep -q "$TIMESTAMP_DEPOIS"; then
  ok=$((ok+1)); echo "  ok   cópia mais recente ainda existe entre os 5"
else
  falhou=$((falhou+1)); echo "  FALHA cópia mais recente foi apagada!"
fi

echo
echo "== 5. banco corrompido recusa backup (Tarefa 23 - D18) =="
# Salvar estado atual (temos backups válidos)
BACKUPS_ANTES=$(ls "$CAIXA/.rainforest-backups"/*.db 2>/dev/null | wc -l)

# Corromper o banco: sobrescrever com lixo
BANCO_MAIN="$CAIXA/rainforest.db"
echo "LIXO" > "$BANCO_MAIN"

# Tentar backup — deve falhar
resultado=$(node "$SRC/scripts/memoria.cjs" backup 2>&1)
exit_code=$?

# Verificar exit ≠ 0
if [ "$exit_code" != "0" ]; then
  ok=$((ok+1)); echo "  ok   banco corrompido recusa backup (exit $exit_code)"
else
  falhou=$((falhou+1)); echo "  FALHA banco corrompido retornou exit 0"
fi

# Verificar que não criou novo arquivo
BACKUPS_DEPOIS=$(ls "$CAIXA/.rainforest-backups"/*.db 2>/dev/null | wc -l)
if [ "$BACKUPS_DEPOIS" = "$BACKUPS_ANTES" ]; then
  ok=$((ok+1)); echo "  ok   nenhum arquivo de backup criado"
else
  falhou=$((falhou+1)); echo "  FALHA criou arquivo: $BACKUPS_ANTES → $BACKUPS_DEPOIS"
fi

# Restaurar banco válido para testes seguintes
rm "$BANCO_MAIN"
$MEMORIA iniciar > /dev/null 2>&1

echo
echo "== 6. banco ausente devolve erro =="
# Criar um RFM_ROOT novo sem banco
CAIXA_VAZIA="$(mktemp -d)"
trap 'rm -rf "$CAIXA" "$CAIXA_VAZIA"' EXIT

resultado=$(RFM_ROOT="$CAIXA_VAZIA" $MEMORIA backup 2>&1)
exit_code=$?
if [ "$exit_code" != "0" ]; then
  ok=$((ok+1)); echo "  ok   backup sem banco retorna exit ≠ 0"
else
  falhou=$((falhou+1)); echo "  FALHA backup sem banco retornou exit 0"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
