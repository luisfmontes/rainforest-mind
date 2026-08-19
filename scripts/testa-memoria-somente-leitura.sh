#!/bin/bash
# Bateria que prova a decisao D16: a fase 1 (leitura) da memoria do rainforest
# e inteiramente reversivel. Uso: bash scripts/testa-memoria-somente-leitura.sh
#
# D16 hoje e uma AFIRMACAO do design; esta bateria a transforma em prova
# executavel. "Abertura de sessao completa" aqui e SEMPRE os dois hooks reais
# de SessionStart, na ordem do hooks.json (foco-session-start.cjs, depois
# memoria-session-start.cjs) — nunca uma simulacao.
#
# O que esta bateria precisa provar, nesta ordem:
#   1. banco AUSENTE: uma abertura completa NAO cria o rainforest.db. Esta e a
#      armadilha do plano — `memoria.cjs iniciar` E ESCRITA, e `abrirBanco()`
#      cria o arquivo se ele nao existir (confirmado abaixo, secao 4). Se
#      algum hook de abertura chamar `abrirBanco` sem checar a ausencia
#      primeiro, a fase 1 deixa de ser somente-leitura mesmo saindo exit 0 e
#      devolvendo bloco vazio — o defeito e invisivel no exit code e no
#      payload, so aparece no sistema de arquivos.
#   2. banco PRESENTE com dado real: hash do arquivo identico antes e depois
#      de uma abertura completa, e nenhum -wal/-shm sobra no disco.
#   3. apagar o banco depois de ele existir devolve a maquina ao estado
#      anterior: os hooks rodam de novo, saem 0, sem stack trace em nenhuma
#      saida, e o banco continua ausente (nao e recriado por engano).
#   4. MUTACAO — prova que as secoes 1 e 3 pegam de verdade. Uma COPIA do
#      hook de memoria, com a guarda de ausencia removida, tem que fazer os
#      sensores de "o banco nao foi criado" acusarem. Sem isto, "o banco
#      continua ausente" e uma afirmacao vazia — pode estar passando porque
#      ninguem checou o sistema de arquivos, nao porque o codigo protege.
#
# Hermetica: toda raiz de dados usada aqui vem de mktemp -d + RFM_ROOT. O
# ~/.rainforest real (meses de decisao do usuario) nunca e tocado — nem para
# leitura, porque os dois hooks resolvem a raiz via RFM_ROOT (nivel 1 da
# cadeia, vence tudo, ver hooks/lib/raiz.cjs).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

ok=0; falhou=0

limpar() {
  rm -rf "${DADOS_POSIX:-}" "${MUT_CODIGO_POSIX:-}" "${MUT_DADOS_POSIX:-}"
}
trap limpar EXIT

# --- sandbox de dados desta bateria ---
DADOS_POSIX="$(mktemp -d)"
DADOS="$(cygpath -m "$DADOS_POSIX" 2>/dev/null || printf '%s' "$DADOS_POSIX")"
echo "(caixa de areia: $DADOS)"

DB="$DADOS_POSIX/rainforest.db"

hash_db() {
  if [ -f "$DB" ]; then sha256sum "$DB" | cut -d' ' -f1; else echo "(ausente)"; fi
}

sidecars_db() {
  # -wal/-shm sobrando e residuo que o hash do arquivo principal nao pega.
  local n=0
  [ -f "$DB-wal" ] && n=$((n+1))
  [ -f "$DB-shm" ] && n=$((n+1))
  echo "$n"
}

tem_stack_trace() { # texto
  # Stack trace de node: linhas "    at algumaCoisa (arquivo:linha:coluna)".
  # O aviso experimental do node:sqlite NAO casa com este padrao.
  printf '%s' "$1" | grep -qE '^\s*at .+:[0-9]+:[0-9]+'
}

# Roda a abertura de sessao completa de verdade: todos os hooks de SessionStart
# DERIVADOS do hooks.json, na ordem declarada. Preenche variaveis globais:
# OUT_1, EXIT_1, ERR_1 para o 1o hook (foco); OUT_2, EXIT_2, ERR_2 para o 2o (memoria);
# OUT_3, EXIT_3, ERR_3 para o 3o (memoria-marca); OUT_4, EXIT_4, ERR_4 para o 4o (observar).
# HOOKS_COUNT = total de hooks rodados.
rodar_abertura() { # raiz [caminho_do_hook_de_memoria]
  local raiz="$1"
  local hook_memoria="${2:-$SRC_WIN/hooks/memoria-session-start.cjs}"

  # Avaliar script que exporta variaveis de cada hook
  eval "$(RFM_ROOT="$raiz" node "$SRC_WIN/scripts/exporta-hooks-sessao-start.cjs" "$raiz" 2>&1)"

  # Para compatibilidade com codigo antigo que usava OUT_FOCO, OUT_MEM:
  # mapeamos OUT_1 -> OUT_FOCO, OUT_2 -> OUT_MEM (os dois primeiros hooks)
  OUT_FOCO="${OUT_1:-}"
  EXIT_FOCO="${EXIT_1:-1}"
  ERR_FOCO="${ERR_1:-}"

  # Se hook_memoria foi passado (mutacao no teste 4), reavaliar apenas esse hook
  if [ "$hook_memoria" != "$SRC_WIN/hooks/memoria-session-start.cjs" ]; then
    OUT_MEM="$(RFM_ROOT="$raiz" node "$hook_memoria" 2>"$DADOS_POSIX/.err-mem")"
    EXIT_MEM=$?
    ERR_MEM="$(cat "$DADOS_POSIX/.err-mem" 2>/dev/null || true)"
  else
    # Caso normal: usar o segundo hook da lista (memoria-session-start.cjs)
    OUT_MEM="${OUT_2:-}"
    EXIT_MEM="${EXIT_2:-1}"
    ERR_MEM="${ERR_2:-}"
  fi
}

checa() { # nome, condicao(0=ok)
  local nome="$1" cond="$2"
  if [ "$cond" = "0" ]; then
    ok=$((ok+1)); echo "  ok    $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome"
  fi
}

echo
echo "1. BANCO AUSENTE — abertura completa nao cria o rainforest.db"
if [ -e "$DB" ]; then
  falhou=$((falhou+1)); echo "  FALHA setup: rainforest.db ja existia antes do teste comecar"
else
  ok=$((ok+1)); echo "  ok    setup: nenhum rainforest.db na caixa de areia"
fi

rodar_abertura "$DADOS"

[ "$EXIT_FOCO" = "0" ]; checa "foco-session-start.cjs sai 0"    "$?"
[ "$EXIT_MEM"  = "0" ]; checa "memoria-session-start.cjs sai 0" "$?"

tem_stack_trace "$ERR_FOCO$OUT_FOCO"; [ "$?" != "0" ]; checa "foco: nenhuma saida tem stack trace" "$?"
tem_stack_trace "$ERR_MEM$OUT_MEM";   [ "$?" != "0" ]; checa "memoria: nenhuma saida tem stack trace" "$?"

# A prova central desta secao: banco ausente ANTES, banco ausente DEPOIS.
if [ ! -e "$DB" ]; then
  ok=$((ok+1)); echo "  ok    rainforest.db CONTINUA ausente depois da abertura completa"
else
  falhou=$((falhou+1)); echo "  FALHA rainforest.db foi CRIADO pela abertura — a fase 1 escreveu (armadilha do 'iniciar')"
fi

echo "$OUT_MEM" | grep -qF '"additionalContext":""'
checa "bloco de memoria vem vazio (banco ausente = degradacao graciosa)" "$?"

echo
echo "2. BANCO PRESENTE COM DADO REAL — hash identico antes e depois"
# Cria o banco de verdade via `memoria.cjs iniciar` (o unico caminho de escrita
# desta bateria) e grava uma observacao fixture direto pelo driver, para que o
# SELECT do hook tenha algo real para ler — testar so contra tabela vazia nao
# provaria que o caminho de leitura funciona, so que ele nao explode.
INICIAR_SAIDA="$(RFM_ROOT="$DADOS" node "$SRC_WIN/scripts/memoria.cjs" iniciar 2>&1)"
if [ -f "$DB" ]; then
  ok=$((ok+1)); echo "  ok    setup: rainforest.db criado por 'memoria.cjs iniciar'"
else
  falhou=$((falhou+1)); echo "  FALHA setup: 'iniciar' nao criou o banco"
  echo "$INICIAR_SAIDA" | sed 's/^/         /'
fi

# Inserir observação fixture via script adaptador (D8 — driver isolado)
RFM_ROOT="$DADOS" node "$SRC_WIN/scripts/insere-observacao-fixture.cjs" "teste-somente-leitura" "FIXTURE-OBSERVACAO-DE-TESTE" > "$DADOS_POSIX/.insere-out" 2>&1
if [ "$?" = "0" ]; then
  ok=$((ok+1)); echo "  ok    setup: observacao fixture inserida"
else
  falhou=$((falhou+1)); echo "  FALHA setup: nao consegui inserir a fixture"
  cat "$DADOS_POSIX/.insere-out" | sed 's/^/         /'
fi

[ "$(sidecars_db)" = "0" ]
checa "setup: sem -wal/-shm residual antes de medir o baseline" "$?"

HASH_ANTES="$(hash_db)"
echo "  --- hash antes: $HASH_ANTES"

rodar_abertura "$DADOS"

[ "$EXIT_FOCO" = "0" ]; checa "foco-session-start.cjs sai 0 (banco presente)"    "$?"
[ "$EXIT_MEM"  = "0" ]; checa "memoria-session-start.cjs sai 0 (banco presente)" "$?"

echo "$OUT_MEM" | grep -qF 'FIXTURE-OBSERVACAO-DE-TESTE'
checa "o hook leu a observacao real do banco (nao so tabela vazia)" "$?"

HASH_DEPOIS="$(hash_db)"
echo "  --- hash depois: $HASH_DEPOIS"

[ "$HASH_ANTES" = "$HASH_DEPOIS" ]
checa "hash do rainforest.db identico antes e depois da abertura" "$?"

[ "$(sidecars_db)" = "0" ]
checa "nenhum -wal/-shm sobrou depois da abertura (leitura nao escreve)" "$?"

# Repete a abertura mais duas vezes: uma unica leitura sem efeito nao descarta
# drift que so aparece ao reabrir o banco varias vezes (ex.: checkpoint
# automatico do WAL disparando por tamanho, ou reordenacao de pagina).
for i in 2 3; do
  rodar_abertura "$DADOS"
  H="$(hash_db)"
  [ "$H" = "$HASH_ANTES" ]
  checa "hash continua identico na abertura #$i" "$?"
done

echo
echo "3. APAGAR O BANCO DEVOLVE O ESTADO ANTERIOR, SEM ERRO EM NENHUM HOOK"
rm -f "$DB" "$DB-wal" "$DB-shm"
if [ ! -e "$DB" ]; then
  ok=$((ok+1)); echo "  ok    setup: rainforest.db apagado"
else
  falhou=$((falhou+1)); echo "  FALHA setup: nao consegui apagar o banco"
fi

rodar_abertura "$DADOS"

[ "$EXIT_FOCO" = "0" ]; checa "foco-session-start.cjs sai 0 apos apagar o banco"    "$?"
[ "$EXIT_MEM"  = "0" ]; checa "memoria-session-start.cjs sai 0 apos apagar o banco" "$?"

tem_stack_trace "$ERR_FOCO$OUT_FOCO"; [ "$?" != "0" ]; checa "foco: sem stack trace apos apagar o banco"    "$?"
tem_stack_trace "$ERR_MEM$OUT_MEM";   [ "$?" != "0" ]; checa "memoria: sem stack trace apos apagar o banco" "$?"

echo "$OUT_MEM" | grep -qF '"additionalContext":""'
checa "bloco de memoria volta a vazio (degradacao graciosa, nao erro)" "$?"

if [ ! -e "$DB" ]; then
  ok=$((ok+1)); echo "  ok    rainforest.db CONTINUA ausente — a maquina voltou ao estado anterior"
else
  falhou=$((falhou+1)); echo "  FALHA rainforest.db foi RECRIADO so por rodar a abertura de novo"
fi

echo
echo "4. MUTACAO — prova que as secoes 1 e 3 pegam de verdade"
# hooks/memoria-session-start.cjs so nao cria o banco por causa de UMA guarda:
# `if (!fs.existsSync(caminhoDb)) { return []; }` ANTES de chamar abrirBanco().
# `abrirBanco` usa `new DatabaseSync(caminhoDb)`, que CRIA o arquivo se ele
# nao existir (confirmado nesta bateria: rodar abrirBanco isolado contra um
# caminho ausente deixa um rainforest.db de 4096 B para tras). Sem a guarda,
# o SELECT subsequente falha com "no such table: observacoes" — capturado
# pelo try/catch externo, que devolve bloco vazio e exit 0 do mesmo jeito.
# O defeito fica INVISIVEL no exit code e no payload; so aparece no disco.
# Esta secao copia o hook, remove so essa guarda, e prova que desta vez o
# banco E criado — provando que a secao 1 (e a 3) tinham algo real para
# pegar, e nao estavam so lendo um "true" que nunca falharia.
MUT_CODIGO_POSIX="$(mktemp -d)"
cp -r "$SRC/hooks" "$MUT_CODIGO_POSIX/hooks"
cp -r "$SRC/scripts" "$MUT_CODIGO_POSIX/scripts"
MUT_CODIGO="$(cygpath -m "$MUT_CODIGO_POSIX" 2>/dev/null || printf '%s' "$MUT_CODIGO_POSIX")"

cat > "$MUT_CODIGO_POSIX/muta-guarda.cjs" <<'EOF'
const fs = require('fs');
const alvo = process.env.ALVO;
const original = fs.readFileSync(alvo, 'utf8');
const guarda = `    // Se o banco não existe, array vazio é o resultado esperado.
    if (!fs.existsSync(caminhoDb)) {
      return [];
    }

`;
if (!original.includes(guarda)) {
  console.error('GUARDA_NAO_ENCONTRADA');
  process.exit(1);
}
fs.writeFileSync(alvo, original.replace(guarda, ''));
console.log('MUTADO');
EOF

ALVO="$MUT_CODIGO_POSIX/hooks/memoria-session-start.cjs" node "$MUT_CODIGO_POSIX/muta-guarda.cjs" > "$MUT_CODIGO_POSIX/.muta-out" 2>&1
if [ "$?" = "0" ] && grep -q "^MUTADO$" "$MUT_CODIGO_POSIX/.muta-out"; then
  ok=$((ok+1)); echo "  ok    a guarda de ausencia foi removida da copia"
else
  falhou=$((falhou+1)); echo "  FALHA nao consegui remover a guarda — o texto da fonte pode ter mudado"
  echo "         (secao 4 depende do texto exato do guard-clause em memoria-session-start.cjs)"
  cat "$MUT_CODIGO_POSIX/.muta-out" | sed 's/^/         /'
fi

MUT_DADOS_POSIX="$(mktemp -d)"
MUT_DADOS="$(cygpath -m "$MUT_DADOS_POSIX" 2>/dev/null || printf '%s' "$MUT_DADOS_POSIX")"
MUT_DB="$MUT_DADOS_POSIX/rainforest.db"

if [ -e "$MUT_DB" ]; then
  falhou=$((falhou+1)); echo "  FALHA setup: banco ja existia na caixa de areia da mutacao"
else
  ok=$((ok+1)); echo "  ok    setup: caixa de areia da mutacao sem banco nenhum"
fi

rodar_abertura "$MUT_DADOS" "$MUT_CODIGO/hooks/memoria-session-start.cjs"

# O bug mutado NAO aparece no exit code nem no payload — e o ponto do teste.
[ "$EXIT_MEM" = "0" ]
checa "MUTACAO: o hook quebrado ainda sai 0 (o bug e silencioso por fora)" "$?"
echo "$OUT_MEM" | grep -qF '"additionalContext":""'
checa "MUTACAO: o payload ainda vem vazio (o bug nao aparece no conteudo)" "$?"

# A prova: sem a guarda, o banco E criado. Se isto nao acusar, a secao 1/3
# desta bateria nao estava provando nada — estava so confirmando um "true".
if [ -e "$MUT_DB" ]; then
  ok=$((ok+1)); echo "  ok    MUTACAO: sem a guarda, o rainforest.db FOI criado (o sensor pega o bug)"
else
  falhou=$((falhou+1)); echo "  FALHA MUTACAO SEM EFEITO — o banco continuou ausente mesmo sem a guarda,"
  echo "         o que quer dizer que a secao 1/3 desta bateria nao esta testando nada"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
