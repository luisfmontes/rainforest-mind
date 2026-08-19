#!/bin/bash
# Bateria ponta a ponta para os 3 críticos — prova cada um com mutação
# Usa payload realista: transcript_path (sem project)
#
# Crítico 1: Hook resolve transcrito por evento.project, deveria usar transcript_path
# Crítico 2: observar.cjs lê de offset_visto até EOF (vazio), deveria ler [offset_processado, offset_visto]
# Crítico 3: Ninguém avança offset_processado — fica eternamente em 0

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_MARCA="$SRC/hooks/memoria-marca.cjs"
SCRIPT_OBSERVAR="$SRC/scripts/observar.cjs"
SCRIPT_MEMORIA="$SRC/scripts/memoria.cjs"

# Sandbox
RAIZ_POSIX="$(mktemp -d)"
RAIZ=$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")
trap 'rm -rf "$RAIZ_POSIX"' EXIT

ok=0; falhou=0

echo "=== PONTA A PONTA: 3 Críticos do rainforest-mind ==="
echo "(caixa de areia: $RAIZ)"

# Setup
RFM_ROOT="$RAIZ" node "$SCRIPT_MEMORIA" iniciar > /dev/null 2>&1
ok=$((ok+1)); echo "ok    banco criado"

# Criar transcrito realista (schema real do Claude Code)
SESSAO="sessao-real-001"
PROJETO="projeto-real"
TRANSCRITO="$RAIZ/projects/$PROJETO/$SESSAO.jsonl"
mkdir -p "$(dirname "$TRANSCRITO")"

cat > "$TRANSCRITO" << 'EOF'
{"type":"user","message":{"role":"user","content":"Oi"},"timestamp":"2026-08-19T10:00:00Z","sessionId":"sessao-real-001","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Olá!"}]},"timestamp":"2026-08-19T10:00:01Z","sessionId":"sessao-real-001","version":"2.1.0","cwd":"test"}
EOF

# ============================================================================
# Crítico 1: TESTE SEM MUTAÇÃO — deve usar transcript_path
# ============================================================================

echo
echo "== CRÍTICO 1: transcript_path primária ==="

EVENTO='{"session_id":"'$SESSAO'","transcript_path":"'$TRANSCRITO'","cwd":"'$RAIZ'"}'
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

MARCA_ARQ=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT arquivo FROM marca_dagua WHERE sessao=\\'$SESSAO\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].arquivo : '');
db.close();
" 2>/dev/null)

if [ "$MARCA_ARQ" = "$TRANSCRITO" ]; then
  ok=$((ok+1)); echo "ok    Crítico 1 OK: marca em caminho correto"
else
  falhou=$((falhou+1)); echo "FALHA    Crítico 1: marca em caminho errado"
  echo "  Esperado: $TRANSCRITO"
  echo "  Obtido: $MARCA_ARQ"
fi

echo
echo "Crítico 1 — PROVA COM MUTAÇÃO (deve falhar)"

# Backup
HOOK_BACKUP="$(mktemp)"
cp "$HOOK_MARCA" "$HOOK_BACKUP"

# Mutação: ignorar transcript_path
sed -i 's/if (evento.transcript_path)/if (false) \/\/ MUTAÇÃO C1/' "$HOOK_MARCA"

SESSAO_MUT1="sessao-mut-c1"
TRANSCRITO_MUT1="$RAIZ/projects/$PROJETO/$SESSAO_MUT1.jsonl"
mkdir -p "$(dirname "$TRANSCRITO_MUT1")"
echo '{"type":"test"}' > "$TRANSCRITO_MUT1"

EVENTO_MUT1='{"session_id":"'$SESSAO_MUT1'","transcript_path":"'$TRANSCRITO_MUT1'","cwd":"'$RAIZ'"}'
echo "$EVENTO_MUT1" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

MARCA_ARQ_MUT1=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT arquivo FROM marca_dagua WHERE sessao=\\'$SESSAO_MUT1\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].arquivo : 'NULL');
db.close();
" 2>/dev/null)

if [ "$MARCA_ARQ_MUT1" = "NULL" ]; then
  ok=$((ok+1)); echo "ok    Crítico 1: mutação acionou saída vermelha (marca=NULL)"
else
  falhou=$((falhou+1)); echo "FALHA    Crítico 1: mutação não acionou (ainda gravou: $MARCA_ARQ_MUT1)"
fi

# Revert
cp "$HOOK_BACKUP" "$HOOK_MARCA"
rm -f "$HOOK_BACKUP"

# ============================================================================
# Crítico 2+3: TESTE SEM MUTAÇÃO — deve ler janela correta e avançar offset_processado
# ============================================================================

echo
echo "== CRÍTICO 2+3: janela correta + avanço offset_processado ==="

# Crescer transcrito (schema real)
cat >> "$TRANSCRITO" << 'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"test","id":"tool_123","input":{}}]},"timestamp":"2026-08-19T10:00:02Z","sessionId":"sessao-real-001","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"resultado"}]},"timestamp":"2026-08-19T10:00:03Z","sessionId":"sessao-real-001","version":"2.1.0","cwd":"test"}
EOF

# Reobservar marca
EVENTO='{"session_id":"'$SESSAO'","transcript_path":"'$TRANSCRITO'","cwd":"'$RAIZ'"}'
echo "$EVENTO" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

# Criar mock LLM que funciona. Ecoa o texto de entrada na observação para que
# cada chamada produza conteúdo distinto — observacoes tem UNIQUE(projeto,
# conteudo), e um retorno fixo colidiria entre as várias sessões deste teste.
cat > "$RAIZ/mock-llm-ok.cjs" << 'MOCK_EOF'
module.exports.chamarLLM = async (texto) => {
  if (texto.length > 0) {
    return 'Observação gerada com sucesso: ' + texto;
  }
  return null;
};
MOCK_EOF

# Rodar observar
OBSERVAR_OUT=$(cd "$SRC" && \
  TESTADOR_CHAMAR_LLM="$RAIZ/mock-llm-ok.cjs" \
  RFM_ROOT="$RAIZ" \
  node "$SCRIPT_OBSERVAR" --sessao "$SESSAO" --projeto "$PROJETO" 2>&1)

# Verificar marca após processamento
MARCA_ESTADO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COALESCE(offset_processado, 0) as offset_processado FROM marca_dagua WHERE sessao=\\'$SESSAO\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset_processado : '0');
db.close();
" 2>/dev/null)

if [ "$MARCA_ESTADO" -gt "0" ]; then
  ok=$((ok+1)); echo "ok    Críticos 2+3 OK: offset_processado avançou para $MARCA_ESTADO"
else
  falhou=$((falhou+1)); echo "FALHA    Críticos 2+3: offset_processado não avançou (=$MARCA_ESTADO)"
  echo "  Saída observar: $OBSERVAR_OUT"
fi

# Verificar observação foi gravada
OBS_COUNT=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes WHERE projeto=\\'$PROJETO\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].cnt : '0');
db.close();
" 2>/dev/null)

if [ "$OBS_COUNT" -gt "0" ]; then
  ok=$((ok+1)); echo "ok    Observação foi gravada ($OBS_COUNT)"
else
  falhou=$((falhou+1)); echo "FALHA    Nenhuma observação foi gravada"
fi

# ============================================================================
# Ponto 4 do contrato: rodar de novo sem o transcrito crescer NÃO reprocessa
# ============================================================================

echo
echo "== PONTO 4: rodar de novo sem crescer não reprocessa =="

OBSERVAR_OUT_2=$(cd "$SRC" && \
  TESTADOR_CHAMAR_LLM="$RAIZ/mock-llm-ok.cjs" \
  RFM_ROOT="$RAIZ" \
  node "$SCRIPT_OBSERVAR" --sessao "$SESSAO" --projeto "$PROJETO" 2>&1)

if echo "$OBSERVAR_OUT_2" | grep -q "nenhum evento"; then
  ok=$((ok+1)); echo "ok    2ª passada não achou evento novo (janela vazia)"
else
  falhou=$((falhou+1)); echo "FALHA    2ª passada reprocessou (deveria estar vazia)"
  echo "  Saída: $OBSERVAR_OUT_2"
fi

OBS_COUNT_2=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes WHERE projeto=\\'$PROJETO\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].cnt : '0');
db.close();
" 2>/dev/null)

if [ "$OBS_COUNT_2" = "$OBS_COUNT" ]; then
  ok=$((ok+1)); echo "ok    contagem de observações não duplicou ($OBS_COUNT_2)"
else
  falhou=$((falhou+1)); echo "FALHA    contagem de observações mudou: $OBS_COUNT -> $OBS_COUNT_2"
fi

echo
echo "Críticos 2+3 — PROVA COM MUTAÇÃO (deve falhar)"

# Backup
OBSERVAR_BACKUP="$(mktemp)"
cp "$SCRIPT_OBSERVAR" "$OBSERVAR_BACKUP"

# Mutação: forçar ler de offset_visto em vez de offset_processado
sed -i 's/const offsetProcessado = marca.offset_processado || 0;/const offsetProcessado = marca.offset; \/\/ MUTAÇÃO C2/' "$SCRIPT_OBSERVAR"

SESSAO_MUT2="sessao-mut-c23"
TRANSCRITO_MUT2="$RAIZ/projects/$PROJETO/$SESSAO_MUT2.jsonl"
mkdir -p "$(dirname "$TRANSCRITO_MUT2")"

cat > "$TRANSCRITO_MUT2" << 'EOF'
{"type":"event1"}
{"type":"event2"}
EOF

# Marcar
EVENTO_MUT2='{"session_id":"'$SESSAO_MUT2'","transcript_path":"'$TRANSCRITO_MUT2'","cwd":"'$RAIZ'"}'
echo "$EVENTO_MUT2" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

# NÃO crescer o transcrito depois de marcar: com a mutação, o código passa a
# ler a partir de offset_visto (== fim do arquivo neste ponto) até EOF, que é
# exatamente onde já estamos — a leitura fica vazia e é isso que expõe o bug.
# (Se o arquivo crescesse aqui, a leitura mutada ainda acharia o texto novo e
# a mutação não seria pega — foi o defeito do desenho original deste teste.)

# Rodar observar com mutação — vai ler de offset_visto até EOF (vazio)
OBSERVAR_MUT_OUT=$(cd "$SRC" && \
  TESTADOR_CHAMAR_LLM="$RAIZ/mock-llm-ok.cjs" \
  RFM_ROOT="$RAIZ" \
  node "$SCRIPT_OBSERVAR" --sessao "$SESSAO_MUT2" --projeto "$PROJETO" 2>&1)

# Com mutação, deve dizer "nenhum evento novo"
if echo "$OBSERVAR_MUT_OUT" | grep -q "nenhum evento"; then
  ok=$((ok+1)); echo "ok    Críticos 2+3: mutação acionou saída vermelha (nenhum evento)"
else
  falhou=$((falhou+1)); echo "FALHA    Críticos 2+3: mutação não acionou (saída não menciona 'nenhum evento')"
  echo "  Saída: $OBSERVAR_MUT_OUT"
fi

# Revert
cp "$OBSERVAR_BACKUP" "$SCRIPT_OBSERVAR"
rm -f "$OBSERVAR_BACKUP"

# ============================================================================
# Crítico 3 ISOLADO — PROVA COM MUTAÇÃO (deve falhar)
# Mutação distinta da C2: eventos SÃO encontrados, observação É gravada,
# mas offset_processado NÃO avança (grava sem persistir a UPDATE).
# ============================================================================

echo
echo "Crítico 3 ISOLADO — PROVA COM MUTAÇÃO (deve falhar)"

OBSERVAR_BACKUP_C3="$(mktemp)"
cp "$SCRIPT_OBSERVAR" "$OBSERVAR_BACKUP_C3"

# Mutação: desativa a escrita real do UPDATE, mas a função ainda retorna true
# (a mensagem de sucesso continua saindo — só o banco não muda).
sed -i 's/stmt.run(offsetProcessado, projeto, sessao);/\/\/ MUTAÇÃO C3: stmt.run(offsetProcessado, projeto, sessao);/' "$SCRIPT_OBSERVAR"

SESSAO_MUT3="sessao-mut-c3"
TRANSCRITO_MUT3="$RAIZ/projects/$PROJETO/$SESSAO_MUT3.jsonl"
mkdir -p "$(dirname "$TRANSCRITO_MUT3")"

cat > "$TRANSCRITO_MUT3" << 'EOF'
{"type":"user","message":{"role":"user","content":"eventoA"},"timestamp":"2026-08-19T10:00:00Z","sessionId":"sessao-mut-c3","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"eventoB"}]},"timestamp":"2026-08-19T10:00:01Z","sessionId":"sessao-mut-c3","version":"2.1.0","cwd":"test"}
EOF

EVENTO_MUT3='{"session_id":"'$SESSAO_MUT3'","transcript_path":"'$TRANSCRITO_MUT3'","cwd":"'$RAIZ'"}'
echo "$EVENTO_MUT3" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

OBSERVAR_MUT3_OUT=$(cd "$SRC" && \
  TESTADOR_CHAMAR_LLM="$RAIZ/mock-llm-ok.cjs" \
  RFM_ROOT="$RAIZ" \
  node "$SCRIPT_OBSERVAR" --sessao "$SESSAO_MUT3" --projeto "$PROJETO" 2>&1)

MARCA_OFFSET_PROC_MUT3=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COALESCE(offset_processado, 0) as op FROM marca_dagua WHERE sessao=\\'$SESSAO_MUT3\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].op : '0');
db.close();
" 2>/dev/null)

# Com a mutação, a observação foi gravada (mensagem de sucesso sai), mas
# offset_processado real no banco continua em 0 — a mentira do log é o ponto.
if [ "$MARCA_OFFSET_PROC_MUT3" = "0" ]; then
  ok=$((ok+1)); echo "ok    Crítico 3: mutação acionou saída vermelha (offset_processado real ficou em 0)"
  echo "  Saída do observar (mensagem de sucesso, mas banco não mudou): $OBSERVAR_MUT3_OUT"
else
  falhou=$((falhou+1)); echo "FALHA    Crítico 3: mutação não acionou (offset_processado=$MARCA_OFFSET_PROC_MUT3)"
fi

# Revert
cp "$OBSERVAR_BACKUP_C3" "$SCRIPT_OBSERVAR"
rm -f "$OBSERVAR_BACKUP_C3"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
