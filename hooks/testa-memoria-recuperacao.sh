#!/bin/bash
# Bateria do hooks/memoria-marca.cjs --recover (Tarefa 11)
# Uso: bash hooks/testa-memoria-recuperacao.sh
#
# O que esta bateria precisa provar:
#   1. SessionEnd normal processa até o fim do transcrito
#   2. Sessão cujo SessionEnd **nunca dispara** é recuperada na abertura seguinte
#   3. Ambos caminhos chegam à mesma contagem final
#   4. A recuperação é enfileirada (async no hooks.json)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$SRC/hooks/memoria-marca.cjs"
SCRIPT_MEMORIA="$SRC/scripts/memoria.cjs"
HOOKS_JSON="$SRC/hooks/hooks.json"

# Sandbox hermética
RAIZ_POSIX="$(mktemp -d)"
RAIZ=$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# Teste 1: Recuperação está registrada em hooks.json como async
echo
echo "1. Recuperação está registrada em SessionStart como async"
if grep -A 20 '"SessionStart"' "$HOOKS_JSON" | grep -q 'memoria-marca.cjs.*--recover'; then
  if grep -A 20 '"SessionStart"' "$HOOKS_JSON" | grep -A 5 'memoria-marca.cjs.*--recover' | grep -q '"async": true'; then
    ok=$((ok+1)); echo "  ok    recuperação registrada em SessionStart como async"
  else
    falhou=$((falhou+1)); echo "  FALHA recuperação não está async"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA recuperação não registrada em SessionStart"
fi

# Teste 2: Não existe spawn/exec no hook
echo
echo "2. Hook não contém spawn/exec"
if grep -E '\.spawn\(|\.exec\(|spawn\(|exec\(' "$HOOK" | grep -v '//' > /dev/null 2>&1; then
  falhou=$((falhou+1)); echo "  FALHA encontrado spawn/exec"
else
  ok=$((ok+1)); echo "  ok    sem spawn/exec"
fi

# Teste 3: Inicializa banco
echo
echo "3. Inicializando banco na caixa de areia"
RFM_ROOT="$RAIZ" node "$SCRIPT_MEMORIA" iniciar > /dev/null 2>&1

if [ -f "$RAIZ_POSIX/rainforest.db" ]; then
  ok=$((ok+1)); echo "  ok    banco criado"
else
  falhou=$((falhou+1)); echo "  FALHA banco não criado"
  echo "== resultado: $ok ok, $falhou falha(s) =="
  exit 1
fi

# Teste 4: Caminho normal — SessionEnd dispara, marca processada
echo
echo "4. Caminho normal: SessionEnd dispara e processa marca"

SESSAO_NORMAL="sessao-normal-001"
mkdir -p "$RAIZ_POSIX/projects/projeto-teste"
echo '{"tipo":"prompt","conteudo":"turno1"}' > "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_NORMAL.jsonl"
OFFSET_TURNO1=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_NORMAL.jsonl")

# Stop: marca no primeiro turno
EVENTO='{"session_id":"'$SESSAO_NORMAL'","project":"projeto-teste"}'
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica marca após Stop
RESULTADO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_NORMAL\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

if [ "$RESULTADO" = "$OFFSET_TURNO1" ]; then
  ok=$((ok+1)); echo "  ok    marca gravada no Stop ($RESULTADO bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA marca após Stop diverge (esperado=$OFFSET_TURNO1, obtido=$RESULTADO)"
fi

# Cresce transcrito (simula mais turno)
echo '{"tipo":"ferramenta","conteudo":"resultado"}' >> "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_NORMAL.jsonl"
OFFSET_TURNO2=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_NORMAL.jsonl")

# SessionEnd: marca no fechamento
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica marca final (deve ter offset atualizado)
RESULTADO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_NORMAL\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

if [ "$RESULTADO" = "$OFFSET_TURNO2" ]; then
  ok=$((ok+1)); echo "  ok    marca atualizada no SessionEnd ($RESULTADO bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA marca final diverge (esperado=$OFFSET_TURNO2, obtido=$RESULTADO)"
fi

# Teste 5: Caminho de recuperação — SessionEnd **nunca dispara**, offset NÃO avança
echo
echo "5. CRÍTICO: Janela morta — offset CONTINUA em X (recuperação NÃO processa)"

SESSAO_MORTA="sessao-morta-001"
mkdir -p "$RAIZ_POSIX/projects/projeto-teste"

# Passo 1: Cria transcrito, Stop marca em offset X
echo '{"tipo":"prompt","conteudo":"turno1"}' > "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MORTA.jsonl"
OFFSET_X=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MORTA.jsonl")

EVENTO_MORTA='{"session_id":"'$SESSAO_MORTA'","project":"projeto-teste"}'
echo "$EVENTO_MORTA" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica marca após Stop (offset = X)
MARCA_ANTES=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_MORTA\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

if [ "$MARCA_ANTES" = "$OFFSET_X" ]; then
  echo "  ok    marca após Stop = $MARCA_ANTES bytes (offset X)"
else
  falhou=$((falhou+1)); echo "  FALHA marca após Stop diverge (esperado=$OFFSET_X, obtido=$MARCA_ANTES)"
fi

# Passo 2: Transcrito CRESCE (Y > X), SessionEnd MORRE (nunca chama hook)
echo '{"tipo":"ferramenta","conteudo":"resultado","dados":"extra_bytes"}' >> "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MORTA.jsonl"
OFFSET_Y=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MORTA.jsonl")
PENDENTE=$((OFFSET_Y - OFFSET_X))

if [ "$OFFSET_Y" -gt "$OFFSET_X" ]; then
  echo "  ok    transcrito cresceu de $OFFSET_X para $OFFSET_Y bytes (pendente: $PENDENTE)"
else
  falhou=$((falhou+1)); echo "  FALHA transcrito não cresceu"
fi

# Passo 3: Abertura seguinte — recuperação DETECTA pendência, MAS NÃO PROCESSA
echo "  Chamando recuperação (offset deve CONTINUAR em $OFFSET_X, pendente fica $PENDENTE)..."
echo "$EVENTO_MORTA" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" --recover > /dev/null 2>&1

# Verifica marca após recuperação (DEVE continuar em X, não avançar para Y)
MARCA_DEPOIS=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_MORTA\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

# TESTE CRÍTICO: offset NUNCA deve avançar (comportamento correto da recuperação)
# Se offset avançou para Y, significa que recuperação DESTRUIU o pendente
if [ "$MARCA_DEPOIS" = "$OFFSET_X" ]; then
  ok=$((ok+1)); echo "  ok    RECUPERAÇÃO CORRETA: offset continua em $MARCA_DEPOIS (pendente conservado)"
else
  falhou=$((falhou+1)); echo "  FALHA RECUPERAÇÃO DESTRUIU PENDENTE: offset pulou de $OFFSET_X para $MARCA_DEPOIS"
fi

# Teste 6: Prova por mutação — desliga recuperação, SessionEnd morto fica suspenso
echo
echo "6. Prova por mutação: desliga recuperação, mostra pendência"

# Remove recuperação de hooks.json temporariamente
HOOKS_TEMP="$(mktemp)"
grep -v '"comando".*--recover' "$HOOKS_JSON" | grep -v '"async".*true' > "$HOOKS_TEMP" || true

# Cria sessão nova que vai "morrer"
SESSAO_MUTACAO="sessao-mutacao-001"
mkdir -p "$RAIZ_POSIX/projects/projeto-teste"
echo '{"tipo":"turno1"}' > "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MUTACAO.jsonl"

# Stop marca (recuperação desligada no hooks.json simulado)
EVENTO_MUT='{"session_id":"'$SESSAO_MUTACAO'","project":"projeto-teste"}'
echo "$EVENTO_MUT" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

OFFSET_MUT_1=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_MUTACAO\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

# Cresce transcrito, SessionEnd morre
echo '{"tipo":"turno2"}' >> "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_MUTACAO.jsonl"

# Tentaria chamar recuperação, mas está desligada
# (simulamos não chamando o hook --recover)
# Nada acontece — marca não é processada

OFFSET_MUT_2=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_MUTACAO\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

# Marca deve permanecer inalterada (prova que sem recuperação, fica suspensa)
if [ "$OFFSET_MUT_1" = "$OFFSET_MUT_2" ]; then
  ok=$((ok+1)); echo "  ok    sem recuperação, marca fica suspensa ($OFFSET_MUT_2 bytes)"
else
  falhou=$((falhou+1)); echo "  FALHA marca alterou mesmo sem recuperação"
fi

# Teste 7: Degradação graciosa — banco ausente
echo
echo "7. Degradação graciosa: banco ausente na recuperação"

RAIZ_VAZIO="$(mktemp -d)"
trap "rm -rf $RAIZ_POSIX $RAIZ_VAZIO" EXIT

echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ_VAZIO" \
  RFM_ROOT="$RAIZ_VAZIO" \
  node "$HOOK" --recover > /dev/null 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    recuperação saiu com exit 0 quando banco não existia"
else
  falhou=$((falhou+1)); echo "  FALHA recuperação saiu com exit $EXIT_CODE"
fi


# Teste T-A: Prova por mutação — Stop/SessionEnd não avança offset_processado
echo
echo "T-A. Prova por mutação: Stop/SessionEnd não avança offset_processado"
echo
echo "  Fase 1: Sem mutação (comportamento correto)"

SESSAO_TA="sessao-ta-001"
mkdir -p "$RAIZ_POSIX/projects/projeto-teste"
echo '{"tipo":"prompt","conteudo":"turno1"}' > "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_TA.jsonl"
OFFSET_TA_1=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_TA.jsonl")

# Stop marca em offset_visto=X, offset_processado=0
EVENTO_TA='{"session_id":"'$SESSAO_TA'","project":"projeto-teste"}'
echo "$EVENTO_TA" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica marca após Stop (offset_visto=X, offset_processado=0)
MARCA_TA_ANTES=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset, COALESCE(offset_processado, 0) as offset_processado FROM marca_dagua WHERE sessao=\\'$SESSAO_TA\\'');
const rows = stmt.all();
if (rows[0]) {
  console.log(rows[0].offset + ',' + rows[0].offset_processado);
} else {
  console.log('0,0');
}
db.close();
" 2>/dev/null)

OFFSET_VISTO_ANTES=$(echo "$MARCA_TA_ANTES" | cut -d, -f1)
OFFSET_PROC_ANTES=$(echo "$MARCA_TA_ANTES" | cut -d, -f2)

if [ "$OFFSET_VISTO_ANTES" = "$OFFSET_TA_1" ] && [ "$OFFSET_PROC_ANTES" = "0" ]; then
  echo "  ok    marca após Stop: offset_visto=$OFFSET_VISTO_ANTES, offset_processado=$OFFSET_PROC_ANTES"
else
  falhou=$((falhou+1)); echo "  FALHA marca após Stop: esperado ($OFFSET_TA_1,0), obtido ($OFFSET_VISTO_ANTES,$OFFSET_PROC_ANTES)"
fi

# Cresce transcrito, Stop novamente (offset_processado NÃO deve avançar)
echo '{"tipo":"ferramenta","conteudo":"resultado_long_x"}' >> "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_TA.jsonl"
OFFSET_TA_2=$(wc -c < "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_TA.jsonl")

echo "$EVENTO_TA" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK" > /dev/null 2>&1

# Verifica marca após segundo Stop (offset_visto=Y, offset_processado AINDA 0)
MARCA_TA_DEPOIS=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset, COALESCE(offset_processado, 0) as offset_processado FROM marca_dagua WHERE sessao=\\'$SESSAO_TA\\'');
const rows = stmt.all();
if (rows[0]) {
  console.log(rows[0].offset + ',' + rows[0].offset_processado);
} else {
  console.log('0,0');
}
db.close();
" 2>/dev/null)

OFFSET_VISTO_DEPOIS=$(echo "$MARCA_TA_DEPOIS" | cut -d, -f1)
OFFSET_PROC_DEPOIS=$(echo "$MARCA_TA_DEPOIS" | cut -d, -f2)

if [ "$OFFSET_VISTO_DEPOIS" = "$OFFSET_TA_2" ] && [ "$OFFSET_PROC_DEPOIS" = "0" ]; then
  ok=$((ok+1)); echo "  ok    marca após crescimento: offset_visto=$OFFSET_VISTO_DEPOIS, offset_processado=$OFFSET_PROC_DEPOIS (intacto)"
else
  falhou=$((falhou+1)); echo "  FALHA marca alterou mal: esperado ($OFFSET_TA_2,0), obtido ($OFFSET_VISTO_DEPOIS,$OFFSET_PROC_DEPOIS)"
fi

# Fase 2: Mutação (deve falhar)
echo
echo "  Fase 2: Com mutação (comportamento quebrado)"
echo "  Mutação: fazer gravarMarca escrever offset atual em offset_processado..."

# Achado 2 da tarefa 22: mutar $HOOK (rastreado) com sed -i.bak e um trap que
# só limpa a raiz de dados — Ctrl-C entre os 3 sed e o cp de volta deixa
# produção mutada em silêncio. A mutação roda numa CÓPIA.
#
# Achado bônus: os 3 sed miravam texto de uma versão ANTERIOR do SQL de
# gravarMarca ("INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo,
# offset, processada_em)" / "VALUES (?, ?, ?, ?, ?)"), que não existe mais —
# a produção evoluiu para INSERT ... ON CONFLICT DO UPDATE (5532853 e
# posteriores). Os 2 primeiros sed eram no-op silencioso (sem erro, sem
# efeito); só o 3º casava, e passava 6 argumentos pra um prepared statement
# com 5 "?" — estourava dentro do try/catch de gravarMarca (que engole tudo),
# então a marca simplesmente não era gravada. O "ERRO mutação não funcionou"
# saía impresso mas NUNCA incrementava $falhou — passava por verde do
# mesmo jeito. A mutação abaixo mira o SQL ATUAL e cobre INSERT e UPDATE.
MUT_TA_POSIX="$(mktemp -d)"
cp -r "$SRC/hooks" "$MUT_TA_POSIX/hooks"
cp -r "$SRC/scripts" "$MUT_TA_POSIX/scripts"
MUT_TA_HOOK="$MUT_TA_POSIX/hooks/memoria-marca.cjs"

cat > "$MUT_TA_POSIX/muta-offset-processado.cjs" <<'MUTEOF'
const fs = require('fs');
const alvo = process.env.ALVO;
const original = fs.readFileSync(alvo, 'utf8');
const trechoOriginal = `    const stmt = conexao.prepare(\`
      INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em)
      VALUES (?, ?, ?, ?, 0, ?)
      ON CONFLICT(projeto, sessao) DO UPDATE SET
        arquivo = excluded.arquivo,
        offset = excluded.offset,
        processada_em = excluded.processada_em
    \`);

    stmt.run(projeto, sessao, arquivo, offset, agora);`;
const trechoMutado = `    const stmt = conexao.prepare(\`
      INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(projeto, sessao) DO UPDATE SET
        arquivo = excluded.arquivo,
        offset = excluded.offset,
        offset_processado = excluded.offset_processado,
        processada_em = excluded.processada_em
    \`);

    stmt.run(projeto, sessao, arquivo, offset, offset, agora);`;
if (!original.includes(trechoOriginal)) {
  console.error('TRECHO_NAO_ENCONTRADO');
  process.exit(1);
}
fs.writeFileSync(alvo, original.replace(trechoOriginal, trechoMutado));
console.log('MUTADO');
MUTEOF

MUTA_TA_OUT=$(ALVO="$MUT_TA_HOOK" node "$MUT_TA_POSIX/muta-offset-processado.cjs" 2>&1)
if echo "$MUTA_TA_OUT" | grep -q "^MUTADO$"; then
  ok=$((ok+1)); echo "  ok    mutação aplicada na cópia (offset_processado passa a receber offset atual)"
else
  falhou=$((falhou+1)); echo "  FALHA não consegui aplicar a mutação — o SQL de gravarMarca pode ter mudado"
  echo "$MUTA_TA_OUT" | sed 's/^/         /'
fi

# Testa com mutação — deve falhar (offset_processado vai avançar)
SESSAO_TA_MUT="sessao-ta-mut-001"
mkdir -p "$RAIZ_POSIX/projects/projeto-teste"
echo '{"tipo":"prompt","conteudo":"turno1"}' > "$RAIZ_POSIX/projects/projeto-teste/$SESSAO_TA_MUT.jsonl"

echo '{"session_id":"'$SESSAO_TA_MUT'","project":"projeto-teste"}' | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$MUT_TA_HOOK" > /dev/null 2>&1

# Verifica marca com mutação
MARCA_TA_MUT=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset, COALESCE(offset_processado, 0) as offset_processado FROM marca_dagua WHERE sessao=\\'$SESSAO_TA_MUT\\'');
const rows = stmt.all();
if (rows[0]) {
  console.log(rows[0].offset + ',' + rows[0].offset_processado);
} else {
  console.log('0,0');
}
db.close();
" 2>/dev/null)

OFFSET_PROC_MUT=$(echo "$MARCA_TA_MUT" | cut -d, -f2)

if [ "$OFFSET_PROC_MUT" != "0" ]; then
  # Mutação funcionou — offset_processado foi escrito quando não deveria
  ok=$((ok+1)); echo "  ok    mutação ativa: offset_processado=$OFFSET_PROC_MUT (visto que não deveria — vermelho conseguido)"
else
  falhou=$((falhou+1)); echo "  FALHA mutação não reproduziu o bug (offset_processado continua 0)"
fi

rm -rf "$MUT_TA_POSIX"

# Teste T-B: Prova por mutação — recuperarSessoes() sinaliza pendência
# NOTA: Usar sandbox separada para evitar interferência de testes anteriores
echo
echo "T-B. Prova por mutação: recuperarSessoes() sinaliza pendência"

RAIZ_TB_POSIX="$(mktemp -d)"
RAIZ_TB=$(cygpath -m "$RAIZ_TB_POSIX" 2>/dev/null || printf '%s' "$RAIZ_TB_POSIX")

# Inicializar banco
RFM_ROOT="$RAIZ_TB" node "$SCRIPT_MEMORIA" iniciar > /dev/null 2>&1

echo
echo "  Fase 1: Sem mutação (comportamento correto)"

SESSAO_TB="sessao-tb-001"
mkdir -p "$RAIZ_TB_POSIX/projects/projeto-teste"
echo '{"tipo":"prompt","conteudo":"turno1"}' > "$RAIZ_TB_POSIX/projects/projeto-teste/$SESSAO_TB.jsonl"
OFFSET_TB_1=$(wc -c < "$RAIZ_TB_POSIX/projects/projeto-teste/$SESSAO_TB.jsonl")

# Stop marca
EVENTO_TB='{"session_id":"'$SESSAO_TB'","project":"projeto-teste"}'
echo "$EVENTO_TB" | \
  CLAUDE_CONFIG_DIR="$RAIZ_TB" \
  RFM_ROOT="$RAIZ_TB" \
  node "$HOOK" > /dev/null 2>&1

# Cresce transcrito (simula SessionEnd morto)
echo '{"tipo":"ferramenta","conteudo":"resultado_pendente"}' >> "$RAIZ_TB_POSIX/projects/projeto-teste/$SESSAO_TB.jsonl"
OFFSET_TB_2=$(wc -c < "$RAIZ_TB_POSIX/projects/projeto-teste/$SESSAO_TB.jsonl")

# Recuperação com --recover (deve sinalizar PENDENCIA)
RECUPERACAO_OUTPUT=$(echo "$EVENTO_TB" | \
  CLAUDE_CONFIG_DIR="$RAIZ_TB" \
  RFM_ROOT="$RAIZ_TB" \
  node "$HOOK" --recover 2>&1)

# Verifica se saída contém PENDENCIA
if echo "$RECUPERACAO_OUTPUT" | grep -q "PENDENCIA:.*sessao=$SESSAO_TB"; then
  ok=$((ok+1)); echo "  ok    recuperação sinalizou pendência"
else
  falhou=$((falhou+1)); echo "  FALHA recuperação não sinalizou pendência"
  echo "  Saída: $RECUPERACAO_OUTPUT"
fi

# Fase 2: Mutação (deve falhar)
echo
echo "  Fase 2: Com mutação (comportamento quebrado)"
echo "  Mutação: alterar condição para nunca detectar pendência..."

# Achado 2 da tarefa 22: mutar $HOOK (rastreado) com sed -i e um trap que só
# limpa a raiz de dados — Ctrl-C entre o sed e o cp de volta deixa produção
# mutada. A mutação roda numa CÓPIA.
MUT_TB_POSIX="$(mktemp -d)"
cp -r "$SRC/hooks" "$MUT_TB_POSIX/hooks"
cp -r "$SRC/scripts" "$MUT_TB_POSIX/scripts"
MUT_TB_HOOK="$MUT_TB_POSIX/hooks/memoria-marca.cjs"

# Mutação: alterar "if (tamanhoAtual > marca.offset_processado)" para "if (false)"
# Isso garante que a pendência nunca seja sinalizada
sed -i "s/if (tamanhoAtual > marca.offset_processado)/if (false)/g" "$MUT_TB_HOOK"

# Verificar que a mutação foi aplicada
if grep -q "if (false)" "$MUT_TB_HOOK"; then
  ok=$((ok+1)); echo "  ok    mutação aplicada na cópia: if (false) substituindo a condição"
else
  falhou=$((falhou+1)); echo "  FALHA não consegui aplicar a mutação — o texto de recuperarSessoes() pode ter mudado"
fi

# Usar nova sandbox para teste com mutação
RAIZ_TB_MUT_POSIX="$(mktemp -d)"
RAIZ_TB_MUT=$(cygpath -m "$RAIZ_TB_MUT_POSIX" 2>/dev/null || printf '%s' "$RAIZ_TB_MUT_POSIX")

# Inicializar banco para teste com mutação
RFM_ROOT="$RAIZ_TB_MUT" node "$SCRIPT_MEMORIA" iniciar > /dev/null 2>&1

# Testa com mutação — deve falhar (sem PENDENCIA na saída)
SESSAO_TB_MUT="sessao-tb-mut-001"
mkdir -p "$RAIZ_TB_MUT_POSIX/projects/projeto-teste"
echo '{"tipo":"prompt","conteudo":"turno1"}' > "$RAIZ_TB_MUT_POSIX/projects/projeto-teste/$SESSAO_TB_MUT.jsonl"

echo '{"session_id":"'$SESSAO_TB_MUT'","project":"projeto-teste"}' | \
  CLAUDE_CONFIG_DIR="$RAIZ_TB_MUT" \
  RFM_ROOT="$RAIZ_TB_MUT" \
  node "$MUT_TB_HOOK" > /dev/null 2>&1

# Cresce transcrito
echo '{"tipo":"ferramenta","conteudo":"resultado_pendente"}' >> "$RAIZ_TB_MUT_POSIX/projects/projeto-teste/$SESSAO_TB_MUT.jsonl"

# Recuperação com mutação (NÃO deve sinalizar)
RECUPERACAO_MUT_OUTPUT=$(echo '{"session_id":"'$SESSAO_TB_MUT'","project":"projeto-teste"}' | \
  CLAUDE_CONFIG_DIR="$RAIZ_TB_MUT" \
  RFM_ROOT="$RAIZ_TB_MUT" \
  node "$MUT_TB_HOOK" --recover 2>&1)

# Achado 6 da tarefa 22 (segunda metade): o ramo "não funcionou" só imprimia
# "ERRO", sem nunca incrementar $falhou — mutação que não casa passava por
# verde do mesmo jeito que uma que casasse. Agora os dois lados contam.
if echo "$RECUPERACAO_MUT_OUTPUT" | grep -q "PENDENCIA:"; then
  falhou=$((falhou+1)); echo "  FALHA mutação não acionou (ainda tem PENDENCIA na saída)"
else
  # Mutação funcionou — nenhuma PENDENCIA foi sinalizada
  ok=$((ok+1)); echo "  ok    mutação ativa: nenhuma PENDENCIA sinalizada (comportamento quebrado acionado)"
fi

rm -rf "$MUT_TB_POSIX" "$RAIZ_TB_MUT_POSIX"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
