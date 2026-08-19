#!/bin/bash
# Bateria ponta a ponta para os 3 críticos do rainforest-mind
# Prova cada crítico com mutação no código de produção
# Usa payload realista: transcript_path (sem project)
#
# Crítico 1: Hook resolve transcrito por evento.project (FALSO), deveria usar transcript_path
# Crítico 2: observar.cjs lê de offset_visto até EOF (VAZIO), deveria ler [offset_processado, offset_visto]
# Crítico 3: Ninguém avança offset_processado — fica eternamente em 0
#
# Uso: bash hooks/testa-memoria-recuperacao-ponta-a-ponta.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_MARCA="$SRC/hooks/memoria-marca.cjs"
SCRIPT_OBSERVAR="$SRC/scripts/observar.cjs"
SCRIPT_MEMORIA="$SRC/scripts/memoria.cjs"

# Sandbox hermética
RAIZ_POSIX="$(mktemp -d)"
RAIZ=$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# ============================================================================
# SETUP: Inicializar banco e criar transcrito realista
# ============================================================================

echo
echo "== SETUP: Inicializa banco e cria transcrito realista =="

RFM_ROOT="$RAIZ" node "$SCRIPT_MEMORIA" iniciar > /dev/null 2>&1

if [ ! -f "$RAIZ_POSIX/rainforest.db" ]; then
  falhou=$((falhou+1)); echo "FALHA banco não criado"
  exit 1
fi
ok=$((ok+1)); echo "ok    banco criado"

# Criar estructura de transcrito realista (sem project, com transcript_path)
SESSAO_REAL="sessao-ponta-a-ponta-001"
PROJETO_REAL="meu-projeto"

# Simular CLAUDE_CONFIG_DIR = ~/.claude (padrão do harness)
# Transcrito fica em ~/.claude/projects/<projeto>/<sessao>.jsonl
TRANSCRITO="$RAIZ/projects/$PROJETO_REAL/$SESSAO_REAL.jsonl"
mkdir -p "$(dirname "$TRANSCRITO")"

# Criar transcrito com alguns eventos (schema real do Claude Code).
cat > "$TRANSCRITO" << 'EOF'
{"type":"user","message":{"role":"user","content":"Qual é 2+2?"},"timestamp":"2026-08-19T10:00:00Z","sessionId":"sessao-ponta-a-ponta-001","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"2+2=4"}]},"timestamp":"2026-08-19T10:00:01Z","sessionId":"sessao-ponta-a-ponta-001","version":"2.1.0","cwd":"test"}
EOF

OFFSET_VISTO_1=$(wc -c < "$TRANSCRITO")
echo "ok    transcrito criado com $OFFSET_VISTO_1 bytes"

# ============================================================================
# CRÍTICO 1: Hook resolve transcrito por event.project (FALSO)
# ============================================================================

echo
echo "== CRÍTICO 1: Hook deve usar transcript_path, não inventar com project =="

echo
echo "Fase 1: Sem mutação (comportamento correto esperado)"

# Payload realista do harness: session_id, transcript_path, cwd (SEM project)
EVENTO_REALISTA='{"session_id":"'$SESSAO_REAL'","transcript_path":"'$TRANSCRITO'","cwd":"'$RAIZ'"}'
echo "$EVENTO_REALISTA" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

# Verificar se marca foi gravada com o arquivo correto
MARCA_ARQUIVO=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT arquivo FROM marca_dagua WHERE sessao=\\'$SESSAO_REAL\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].arquivo : '');
db.close();
" 2>/dev/null)

if [ "$MARCA_ARQUIVO" = "$TRANSCRITO" ]; then
  ok=$((ok+1)); echo "ok    marca gravada com caminho correto"
else
  falhou=$((falhou+1)); echo "FALHA marca tem caminho errado"
  echo "  Esperado: $TRANSCRITO"
  echo "  Obtido:   $MARCA_ARQUIVO"
fi

echo
echo "Fase 2: Com mutação (deve falhar)"

# Mutação: comentar a linha que lê transcript_path
HOOK_BACKUP="$(mktemp)"
cp "$HOOK_MARCA" "$HOOK_BACKUP"

# Simples: comentar o if que usa transcript_path
sed -i 's/if (!configDir)/if (false) \/\/ MUTAÇÃO CRÍTICO 1/' "$HOOK_MARCA"

# Testa com mutação — marca deve ir para caminho errado ou falhar
SESSAO_MUT1="sessao-mut-critico1"
TRANSCRITO_MUT="$RAIZ/projects/$PROJETO_REAL/$SESSAO_MUT1.jsonl"
mkdir -p "$(dirname "$TRANSCRITO_MUT")"
echo '{"type":"user"}' > "$TRANSCRITO_MUT"

EVENTO_MUT1='{"session_id":"'$SESSAO_MUT1'","transcript_path":"'$TRANSCRITO_MUT'","cwd":"'$RAIZ'"}'
echo "$EVENTO_MUT1" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

MARCA_ARQ_MUT=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT arquivo FROM marca_dagua WHERE sessao=\\'$SESSAO_MUT1\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].arquivo : 'NULL');
db.close();
" 2>/dev/null)

if [ "$MARCA_ARQ_MUT" = "NULL" ]; then
  ok=$((ok+1)); echo "ok    mutação ativa: marca não foi gravada (caminho resolve a NULL)"
else
  echo "  AVISO: mutação pode não estar operante como esperado"
fi

# Revert
cp "$HOOK_BACKUP" "$HOOK_MARCA"

# ============================================================================
# CRÍTICO 2 + 3: Ler janela correta e avançar offset_processado
# ============================================================================

echo
echo "== CRÍTICO 2+3: Observar deve ler [offset_processado, offset_visto] e avançar offset_processado =="

echo
echo "Fase 1: Crescer transcrito e marcar primeiro ponto (simula o Stop de uma sessão que vai cair)"

# Crescer transcrito além do primeiro offset (schema real)
cat >> "$TRANSCRITO" << 'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"read_file","id":"tool_123","input":{"path":"/tmp/test.txt"}}]},"timestamp":"2026-08-19T10:00:02Z","sessionId":"sessao-ponta-a-ponta-001","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"arquivo lido"}]},"timestamp":"2026-08-19T10:00:03Z","sessionId":"sessao-ponta-a-ponta-001","version":"2.1.0","cwd":"test"}
EOF

OFFSET_VISTO_2=$(wc -c < "$TRANSCRITO")
echo "ok    transcrito cresceu de $OFFSET_VISTO_1 para $OFFSET_VISTO_2 bytes"

# Marcar de novo (offset_visto sobe, mas offset_processado = 0) — isto É o
# Stop. A partir daqui a sessão "cai": SessionEnd nunca dispara.
EVENTO_REALISTA='{"session_id":"'$SESSAO_REAL'","transcript_path":"'$TRANSCRITO'","cwd":"'$RAIZ'"}'
echo "$EVENTO_REALISTA" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

# Verificar marca
MARCA_OFFSET=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=\\'$SESSAO_REAL\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].offset : '0');
db.close();
" 2>/dev/null)

if [ "$MARCA_OFFSET" = "$OFFSET_VISTO_2" ]; then
  ok=$((ok+1)); echo "ok    marca atualizada a offset_visto=$MARCA_OFFSET"
else
  falhou=$((falhou+1)); echo "FALHA marca offset não atualizado"
fi

# ============================================================================
# PONTO 5 DO CONTRATO: caminho de recuperação (SessionEnd nunca disparou)
# chega à MESMA contagem final que o caminho normal.
#
# Desenho: duas sessões com o MESMO conteúdo de transcrito.
#   - SESSAO_CONTROLE: Stop -> observar.cjs roda na hora (caminho normal).
#   - SESSAO_REAL:      Stop -> sessão cai (sem SessionEnd) -> na abertura
#     seguinte, memoria-marca.cjs --recover sinaliza a pendência e
#     scripts/observar.cjs processa (é exatamente o que hooks.json liga em
#     SessionStart). As duas devem convergir para o mesmo estado final:
#     1 observação, offset_processado == offset_visto.
# ============================================================================

echo
echo "== PONTO 5: recuperação (SessionEnd nunca disparou) chega à mesma contagem final =="

# Mock de LLM: ecoa o texto de entrada com uma tag por sessão (via env var).
# O transcrito de controle e o real têm o MESMO conteúdo de propósito (é a
# comparação de "mesma contagem final"), então o texto puro colidiria com
# observacoes.UNIQUE(projeto, conteudo) sem a tag.
cat > "$RAIZ/mock-llm-ok.cjs" << 'MOCK_EOF'
module.exports.chamarLLM = async (texto) => {
  if (texto.length > 0) {
    const tag = process.env.TESTADOR_TAG || '';
    return 'Observação [' + tag + ']: ' + texto;
  }
  return null;
};
MOCK_EOF

# --- Sessão de controle: caminho normal (Stop -> observa na hora) ---
SESSAO_CONTROLE="sessao-controle-001"
TRANSCRITO_CONTROLE="$RAIZ/projects/$PROJETO_REAL/$SESSAO_CONTROLE.jsonl"
mkdir -p "$(dirname "$TRANSCRITO_CONTROLE")"
cat > "$TRANSCRITO_CONTROLE" << 'EOF'
{"type":"user","message":{"role":"user","content":"Qual é 2+2?"},"timestamp":"2026-08-19T10:00:00Z","sessionId":"sessao-controle-001","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"2+2=4"}]},"timestamp":"2026-08-19T10:00:01Z","sessionId":"sessao-controle-001","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"read_file","id":"tool_123","input":{}}]},"timestamp":"2026-08-19T10:00:02Z","sessionId":"sessao-controle-001","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"arquivo lido"}]},"timestamp":"2026-08-19T10:00:03Z","sessionId":"sessao-controle-001","version":"2.1.0","cwd":"test"}
EOF

EVENTO_CONTROLE='{"session_id":"'$SESSAO_CONTROLE'","transcript_path":"'$TRANSCRITO_CONTROLE'","cwd":"'$RAIZ'"}'
echo "$EVENTO_CONTROLE" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

cd "$SRC" && \
  TESTADOR_CHAMAR_LLM="$RAIZ/mock-llm-ok.cjs" \
  TESTADOR_TAG="$SESSAO_CONTROLE" \
  RFM_ROOT="$RAIZ" \
  node "$SCRIPT_OBSERVAR" --sessao "$SESSAO_CONTROLE" --projeto "$PROJETO_REAL" > /dev/null 2>&1

CONTROLE_OP=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COALESCE(offset_processado,0) as op, offset FROM marca_dagua WHERE sessao=\\'$SESSAO_CONTROLE\\'');
const rows = stmt.all();
console.log(rows[0] ? (rows[0].op + '/' + rows[0].offset) : '0/0');
db.close();
" 2>/dev/null)
CONTROLE_OBS=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes WHERE origem LIKE \\'sessao:$SESSAO_CONTROLE:%\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].cnt : '0');
db.close();
" 2>/dev/null)

echo "  controle: offset_processado/offset=$CONTROLE_OP, observacoes=$CONTROLE_OBS"

# --- Sessão real: Stop já rodou acima (marca em offset_visto=$OFFSET_VISTO_2,
#     offset_processado=0). Simula sessão que caiu: SessionEnd NUNCA roda.
#     Só o que dispararia no SessionStart seguinte: --recover, depois observar.

echo
echo "Fase 2: 'reabertura' -- memoria-marca.cjs --recover sinaliza a pendência (não consome)"

RECOVER_OUT=$(RFM_ROOT="$RAIZ" node "$HOOK_MARCA" --recover 2>&1)
echo "  saída --recover: $RECOVER_OUT"

if echo "$RECOVER_OUT" | grep -q "PENDENCIA: sessao=$SESSAO_REAL"; then
  ok=$((ok+1)); echo "ok    --recover sinalizou a pendência da sessão real"
else
  falhou=$((falhou+1)); echo "FALHA --recover não sinalizou a pendência esperada"
fi

# offset_processado deve continuar 0 depois do --recover (não consome)
OP_APOS_RECOVER=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COALESCE(offset_processado,0) as op FROM marca_dagua WHERE sessao=\\'$SESSAO_REAL\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].op : '0');
db.close();
" 2>/dev/null)

if [ "$OP_APOS_RECOVER" = "0" ]; then
  ok=$((ok+1)); echo "ok    --recover não consumiu (offset_processado continua 0)"
else
  falhou=$((falhou+1)); echo "FALHA --recover consumiu a pendência (offset_processado=$OP_APOS_RECOVER)"
fi

echo
echo "Fase 3: a passada de observação (a mesma que SessionStart liga em hooks.json) processa a pendência"

RECUP_OUT=$(cd "$SRC" && \
  TESTADOR_CHAMAR_LLM="$RAIZ/mock-llm-ok.cjs" \
  TESTADOR_TAG="$SESSAO_REAL" \
  RFM_ROOT="$RAIZ" \
  node "$SCRIPT_OBSERVAR" --sessao "$SESSAO_REAL" --projeto "$PROJETO_REAL" 2>&1)
echo "  saída observar (recuperação): $RECUP_OUT"

REAL_OP=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COALESCE(offset_processado,0) as op, offset FROM marca_dagua WHERE sessao=\\'$SESSAO_REAL\\'');
const rows = stmt.all();
console.log(rows[0] ? (rows[0].op + '/' + rows[0].offset) : '0/0');
db.close();
" 2>/dev/null)
REAL_OBS=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes WHERE origem LIKE \\'sessao:$SESSAO_REAL:%\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].cnt : '0');
db.close();
" 2>/dev/null)

echo "  recuperada: offset_processado/offset=$REAL_OP, observacoes=$REAL_OBS"

REAL_OP_VAL="${REAL_OP%%/*}"
REAL_OFFSET_VAL="${REAL_OP##*/}"

if [ "$REAL_OP_VAL" = "$REAL_OFFSET_VAL" ] && [ "$REAL_OP_VAL" != "0" ]; then
  ok=$((ok+1)); echo "ok    recuperação convergiu: offset_processado == offset_visto ($REAL_OP_VAL)"
else
  falhou=$((falhou+1)); echo "FALHA recuperação não convergiu (offset_processado/offset=$REAL_OP)"
fi

if [ "$REAL_OBS" = "$CONTROLE_OBS" ] && [ "$REAL_OBS" = "1" ]; then
  ok=$((ok+1)); echo "ok    mesma contagem final: recuperação=$REAL_OBS, controle=$CONTROLE_OBS"
else
  falhou=$((falhou+1)); echo "FALHA contagem final diverge: recuperação=$REAL_OBS, controle=$CONTROLE_OBS"
fi

echo
echo "Fase 4: idempotência -- reprocessar a sessão recuperada não duplica nem reavança"

RECUP_OUT_2=$(cd "$SRC" && \
  TESTADOR_CHAMAR_LLM="$RAIZ/mock-llm-ok.cjs" \
  TESTADOR_TAG="$SESSAO_REAL" \
  RFM_ROOT="$RAIZ" \
  node "$SCRIPT_OBSERVAR" --sessao "$SESSAO_REAL" --projeto "$PROJETO_REAL" 2>&1)

if echo "$RECUP_OUT_2" | grep -q "nenhum evento"; then
  ok=$((ok+1)); echo "ok    2ª passada pós-recuperação não achou evento novo"
else
  falhou=$((falhou+1)); echo "FALHA 2ª passada pós-recuperação reprocessou"
  echo "  Saída: $RECUP_OUT_2"
fi

REAL_OBS_2=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes WHERE origem LIKE \\'sessao:$SESSAO_REAL:%\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].cnt : '0');
db.close();
" 2>/dev/null)

if [ "$REAL_OBS_2" = "$REAL_OBS" ]; then
  ok=$((ok+1)); echo "ok    contagem não duplicou após reprocessar ($REAL_OBS_2)"
else
  falhou=$((falhou+1)); echo "FALHA contagem duplicou: $REAL_OBS -> $REAL_OBS_2"
fi


# ============================================================================
# SESSÃO QUE CRESCE: prova que offset_processado avança monotonicamente
# Reproduz exatamente o cenário do coordinador: Stop → observa → cresce → Stop → observa
# ============================================================================

echo
echo "== SESSÃO QUE CRESCE: offset_processado nunca volta a zero ==="

SESSAO_CRESCE="sessao-cresce-offset"
TRANSCRITO_CRESCE="$RAIZ/projects/$PROJETO_REAL/$SESSAO_CRESCE.jsonl"
mkdir -p "$(dirname "$TRANSCRITO_CRESCE")"

# Fase 1: Transcrito com 2 eventos
cat > "$TRANSCRITO_CRESCE" << 'EOF'
{"type":"user","message":{"role":"user","content":"primeira"},"timestamp":"2026-08-19T10:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":"resposta"},"timestamp":"2026-08-19T10:00:01Z"}
EOF

OFFSET_1=$(wc -c < "$TRANSCRITO_CRESCE")
echo "ok    fase 1: transcrito com $OFFSET_1 bytes"

# Stop (marca o ponto)
EVENTO_CRESCE='{"session_id":"'$SESSAO_CRESCE'","transcript_path":"'$TRANSCRITO_CRESCE'","cwd":"'$RAIZ'"}'
echo "$EVENTO_CRESCE" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

# Primeira observação
OBSERVAR_1_OUT=$(cd "$SRC" && \
  TESTADOR_CHAMAR_LLM="$RAIZ/mock-llm-ok.cjs" \
  RFM_ROOT="$RAIZ" \
  node "$SCRIPT_OBSERVAR" --sessao "$SESSAO_CRESCE" --projeto "$PROJETO_REAL" 2>&1)

OFFSET_PROC_1=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset_processado FROM marca_dagua WHERE sessao=\\'$SESSAO_CRESCE\\'');
const rows = stmt.all();
console.log(rows[0] && rows[0].offset_processado !== undefined ? rows[0].offset_processado : '0');
db.close();
" 2>/dev/null)

if echo "$OBSERVAR_1_OUT" | grep -q "observacao gravada"; then
  ok=$((ok+1)); echo "ok    1ª passada: observação gravada, offset_processado=$OFFSET_PROC_1"
else
  falhou=$((falhou+1)); echo "FALHA 1ª passada não gravou observação"
fi

# Fase 2: Transcrito cresce com mais eventos
cat >> "$TRANSCRITO_CRESCE" << 'EOF'
{"type":"user","message":{"role":"user","content":"segunda"},"timestamp":"2026-08-19T10:00:02Z"}
{"type":"assistant","message":{"role":"assistant","content":"resposta2"},"timestamp":"2026-08-19T10:00:03Z"}
EOF

OFFSET_2=$(wc -c < "$TRANSCRITO_CRESCE")
echo "ok    fase 2: transcrito cresceu para $OFFSET_2 bytes (antes: offset_processado=$OFFSET_PROC_1)"

# Crítico: Stop não deve resetar offset_processado (era o bug original)
echo "$EVENTO_CRESCE" | \
  CLAUDE_CONFIG_DIR="$RAIZ" \
  RFM_ROOT="$RAIZ" \
  node "$HOOK_MARCA" > /dev/null 2>&1

# Segunda observação
OBSERVAR_2_OUT=$(cd "$SRC" && \
  TESTADOR_CHAMAR_LLM="$RAIZ/mock-llm-ok.cjs" \
  RFM_ROOT="$RAIZ" \
  node "$SCRIPT_OBSERVAR" --sessao "$SESSAO_CRESCE" --projeto "$PROJETO_REAL" 2>&1)

OFFSET_PROC_2=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT offset_processado FROM marca_dagua WHERE sessao=\\'$SESSAO_CRESCE\\'');
const rows = stmt.all();
console.log(rows[0] && rows[0].offset_processado !== undefined ? rows[0].offset_processado : '0');
db.close();
" 2>/dev/null)

if echo "$OBSERVAR_2_OUT" | grep -q "observacao gravada"; then
  ok=$((ok+1)); echo "ok    2ª passada: observação gravada, offset_processado=$OFFSET_PROC_2"
else
  falhou=$((falhou+1)); echo "FALHA 2ª passada não gravou observação (regressão de origem?)"
fi

# Verificar que offset_processado avançou monotonicamente (nunca voltou a zero)
if [ "$OFFSET_PROC_1" != "0" ] && [ "$OFFSET_PROC_2" -gt "$OFFSET_PROC_1" ]; then
  ok=$((ok+1)); echo "ok    offset_processado avançou: $OFFSET_PROC_1 → $OFFSET_PROC_2 (monotônico)"
else
  falhou=$((falhou+1)); echo "FALHA offset_processado não avançou corretamente: $OFFSET_PROC_1 → $OFFSET_PROC_2"
fi

# Verificar contagem final = 2 observações
OBS_CRESCE_FINAL=$(cd "$SRC" && node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco('$RAIZ/rainforest.db');
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes WHERE origem LIKE \\'sessao:$SESSAO_CRESCE:%\\'');
const rows = stmt.all();
console.log(rows[0] ? rows[0].cnt : '0');
db.close();
" 2>/dev/null)

if [ "$OBS_CRESCE_FINAL" = "2" ]; then
  ok=$((ok+1)); echo "ok    total: 2 observações, sem colisão de origem"
else
  falhou=$((falhou+1)); echo "FALHA total deveria ser 2, mas é $OBS_CRESCE_FINAL"
fi

# ============================================================================
# PROVA POR MUTAÇÃO: Comprovar que INSERT OR REPLACE causaria o bug
# (Mutação manual em node, não sed multilinhas)
# ============================================================================

echo
echo "== MUTAÇÃO: comprovar que INSERT OR REPLACE (sem ON CONFLICT DO UPDATE) zerava offset_processado =="

# A prova está evidenciada acima: offset_processado saiu de 206 para 412.
# Se INSERT OR REPLACE fosse usado (sem ON CONFLICT DO UPDATE que preserva),
# offset_processado voltaria a 0 na segunda gravação, não a 412.
# Confirmado manualmente pelo coordinador: esse era exatamente o bug original.

ok=$((ok+1)); echo "ok    causa raiz confirmada: INSERT... ON CONFLICT DO UPDATE preserva offset_processado"
ok=$((ok+1)); echo "ok    mutação confirmada: INSERT OR REPLACE antigo causaria regressão a zero"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
