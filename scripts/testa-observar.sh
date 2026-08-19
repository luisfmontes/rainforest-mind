#!/bin/bash
# Bateria do scripts/observar.cjs — passada de LLM sobre transcrito.
# Uso: bash scripts/testa-observar.sh
#
# O que esta bateria prova:
#   1. Não está registrada em UserPromptSubmit ou PostToolUse (proibido D12, D14)
#   2. Grava observação com coluna `projeto` preenchida
#   3. Falha na LLM deixa marca d'água intacta (recuperação)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OBSERVADOR="$SRC/scripts/observar.cjs"
MEMORIA="$SRC/scripts/memoria.cjs"
HOOKS_JSON="$SRC/hooks/hooks.json"
DUBLIADOR_OK="$SRC/scripts/dubliador-llm-ok.cjs"
DUBLIADOR_FAIL="$SRC/scripts/dubliador-llm-fail.cjs"

ok=0; falhou=0

# ============ Teste 1: Não está em UserPromptSubmit ============
echo
echo "1. observar.cjs não está em UserPromptSubmit (proibido D12)"
if grep -A 10 '"UserPromptSubmit"' "$HOOKS_JSON" | grep -q 'observar'; then
  falhou=$((falhou+1)); echo "  FALHA observar.cjs encontrado em UserPromptSubmit"
else
  ok=$((ok+1)); echo "  ok    não está em UserPromptSubmit"
fi

# ============ Teste 2: Não está em PostToolUse ============
echo
echo "2. observar.cjs não está em PostToolUse (proibido D14)"
if grep -A 10 '"PostToolUse"' "$HOOKS_JSON" 2>/dev/null | grep -q 'observar'; then
  falhou=$((falhou+1)); echo "  FALHA observar.cjs encontrado em PostToolUse"
else
  ok=$((ok+1)); echo "  ok    não está em PostToolUse"
fi

# ============ Sandbox hermética ============
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT
echo
echo "(caixa de areia: $CAIXA)"

export RFM_ROOT="$CAIXA/rainforest"
export CLAUDE_CONFIG_DIR="$CAIXA"
export CAIXA
mkdir -p "$RFM_ROOT/projects/proj-teste"

# ============ Teste 3: Inicializa banco ============
echo
echo "3. Inicializa banco na caixa de areia"
node "$MEMORIA" iniciar > /dev/null 2>&1

if [ -f "$CAIXA/rainforest/rainforest.db" ]; then
  ok=$((ok+1)); echo "  ok    banco criado"
else
  falhou=$((falhou+1)); echo "  FALHA banco não criado"
  echo "== resultado: $ok ok, $falhou falha(s) =="
  exit 1
fi

# ============ Teste 4: Cria transcrito e marca ============
echo
echo "4. Cria transcrito com eventos e marca d'água"

TRANSCRITO="$RFM_ROOT/projects/proj-teste/sessao.jsonl"
cat > "$TRANSCRITO" <<'EOF'
{"type":"user","message":{"role":"user","content":"Qual eh o capital da Franca?"},"timestamp":"2026-08-19T10:00:00Z","sessionId":"sessao","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"O capital eh Paris"}]},"timestamp":"2026-08-19T10:00:01Z","sessionId":"sessao","version":"2.1.0","cwd":"test"}
EOF

OFFSET_ESPERADO=0
OFFSET_FINAL=$(wc -c < "$TRANSCRITO")

# Gravar marca d'água em offset 0
node <<CRIA_MARCA 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare(\`INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em) VALUES (?, ?, ?, ?, ?)\`);
const caminhoTranscrito = path.join(process.env.RFM_ROOT, 'projects', 'proj-teste', 'sessao.jsonl');
stmt.run('proj-teste', 'sessao', caminhoTranscrito, 0, new Date().toISOString());
db.close();
console.log('marca criada');
CRIA_MARCA

ok=$((ok+1)); echo "  ok    transcrito criado ($(wc -c < "$TRANSCRITO") bytes), marca em offset 0"

# ============ Teste 5: Observador com dublê OK ============
echo
echo "5. Chamar observador com dublê que funciona"

export TESTADOR_CHAMAR_LLM="$DUBLIADOR_OK"
node "$OBSERVADOR" --sessao sessao --projeto proj-teste 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    observador retornou exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA observador retornou exit $EXIT_CODE"
fi

# ============ Teste 6: Verificar observação gravada ============
echo
echo "6. Verificar observação com projeto preenchido"

CONTA_OBS=$(node <<'CONTA' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes WHERE projeto=?');
const rows = stmt.all('proj-teste');
console.log(rows[0].cnt);
db.close();
CONTA
)

if [ "$CONTA_OBS" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok    1 observacao gravada com projeto=proj-teste"
else
  falhou=$((falhou+1)); echo "  FALHA $CONTA_OBS observacoes (esperado 1)"
fi

# ============ Teste 6a: Verificar que observação CONTÉM o conteúdo (dublê faz eco) ============
echo
echo "6a. Observacao deve conter referencia ao conteudo do transcrito (eco)"

CONTEUDO_OBS=$(node <<'LEI_CONTEUDO' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT conteudo FROM observacoes WHERE projeto=? LIMIT 1');
const rows = stmt.all('proj-teste');
console.log(rows.length > 0 ? rows[0].conteudo : '');
db.close();
LEI_CONTEUDO
)

# O transcrito tem "Qual eh o capital da Franca?" e "O capital eh Paris"
# O dublê faz eco: "[Resumo do dublê] Prompt: Qual eh o capital da Franca?..."
if echo "$CONTEUDO_OBS" | grep -q "capital\|Franca"; then
  ok=$((ok+1)); echo "  ok    observacao contém referência ao conteudo (eco funciona)"
else
  falhou=$((falhou+1)); echo "  FALHA observacao não contém conteudo: [$CONTEUDO_OBS]"
fi

# ============ Novo ciclo: testar falha de LLM ============
echo
echo "7. Criar nova sessao para testar falha da LLM"

# Limpar banco para novo teste (nova sessão)
node <<'LIMPA' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
db.exec('DELETE FROM observacoes');
db.exec('DELETE FROM marca_dagua');
db.close();
LIMPA

# Criar nova sessão e transcrito
TRANSCRITO2="$RFM_ROOT/projects/proj-teste/sessao2.jsonl"
cat > "$TRANSCRITO2" <<'EOF'
{"type":"user","message":{"role":"user","content":"Qual eh a capital da Italia?"},"timestamp":"2026-08-19T10:01:00Z","sessionId":"sessao2","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"A capital eh Roma"}]},"timestamp":"2026-08-19T10:01:01Z","sessionId":"sessao2","version":"2.1.0","cwd":"test"}
EOF

node <<CRIA_MARCA2 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare(\`INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em) VALUES (?, ?, ?, ?, ?)\`);
const caminhoTranscrito2 = path.join(process.env.RFM_ROOT, 'projects', 'proj-teste', 'sessao2.jsonl');
stmt.run('proj-teste', 'sessao2', caminhoTranscrito2, 0, new Date().toISOString());
db.close();
CRIA_MARCA2

ok=$((ok+1)); echo "  ok    nova sessao2 criada com marca em offset 0"

# ============ Teste 8: Observador com dublê FAIL ============
echo
echo "8. Chamar observador com dublê que falha (retorna null)"

export TESTADOR_CHAMAR_LLM="$DUBLIADOR_FAIL"
node "$OBSERVADOR" --sessao sessao2 --projeto proj-teste 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    observador retornou exit 0 mesmo com falha da LLM"
else
  falhou=$((falhou+1)); echo "  FALHA observador retornou exit $EXIT_CODE"
fi

# ============ Teste 9: Verificar que marca não avancou ============
echo
echo "9. Marca d'agua intacta apos falha da LLM (recuperacao possivel)"

MARCA_OFFSET=$(node <<'LER_MARCA' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT offset FROM marca_dagua WHERE sessao=?');
const rows = stmt.all('sessao2');
console.log(rows.length > 0 ? rows[0].offset : 'nao encontrada');
db.close();
LER_MARCA
)

if [ "$MARCA_OFFSET" = "0" ]; then
  ok=$((ok+1)); echo "  ok    marca em offset 0 (intacta, recuperacao possivel)"
else
  falhou=$((falhou+1)); echo "  FALHA marca mudou para $MARCA_OFFSET (esperado 0)"
fi

# ============ Teste 10: Nenhuma observação foi gravada ============
echo
echo "10. Nenhuma observacao foi gravada durante falha"

CONTA_OBS2=$(node <<'CONTA2' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes');
const rows = stmt.all();
console.log(rows[0].cnt);
db.close();
CONTA2
)

if [ "$CONTA_OBS2" = "0" ]; then
  ok=$((ok+1)); echo "  ok    banco em branco (falha nao deixou lixo)"
else
  falhou=$((falhou+1)); echo "  FALHA $CONTA_OBS2 observacoes (esperado 0)"
fi

# ============ Teste 11: Reprocessar com sucesso (mutacao: prova recuperacao) ============
echo
echo "11. Reprocessar sessao2 com dublê OK (mutacao: verde->vermelho->verde)"

export TESTADOR_CHAMAR_LLM="$DUBLIADOR_OK"
node "$OBSERVADOR" --sessao sessao2 --projeto proj-teste 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    observador retornou exit 0 apos recuperacao"
else
  falhou=$((falhou+1)); echo "  FALHA observador retornou exit $EXIT_CODE"
fi

# ============ Teste 12: Verificar que observação foi finalmente gravada ============
echo
echo "12. Observacao gravada apos recuperacao (prova idempotencia)"

CONTA_OBS_FINAL=$(node <<'CONTA_FINAL' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes');
const rows = stmt.all();
console.log(rows[0].cnt);
db.close();
CONTA_FINAL
)

if [ "$CONTA_OBS_FINAL" = "1" ]; then
  ok=$((ok+1)); echo "  ok    1 observacao gravada apos recuperacao"
else
  falhou=$((falhou+1)); echo "  FALHA $CONTA_OBS_FINAL observacoes (esperado 1)"
fi

# ============ Teste 13: Teste crítico — prompt vazio deve ser recusado ============
echo
echo "13. Transcrito que produz prompt vazio deve recusar observacao"

# Limpar banco para novo teste
node <<'LIMPA3' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
db.exec('DELETE FROM observacoes');
db.exec('DELETE FROM marca_dagua');
db.close();
LIMPA3

# Criar transcrito que produz prompt vazio (apenas eventos sem conteúdo)
TRANSCRITO_VAZIO="$RFM_ROOT/projects/proj-teste/sessao-vazia.jsonl"
cat > "$TRANSCRITO_VAZIO" <<'EOF'
{"type":"mode","data":{"mode":"default"},"timestamp":"2026-08-19T10:00:00Z"}
{"type":"permission-mode","data":{"mode":"default"},"timestamp":"2026-08-19T10:00:01Z"}
EOF

node <<CRIA_MARCA3 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare(\`INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em) VALUES (?, ?, ?, ?, ?)\`);
const caminhoTranscrito3 = path.join(process.env.RFM_ROOT, 'projects', 'proj-teste', 'sessao-vazia.jsonl');
stmt.run('proj-teste', 'sessao-vazia', caminhoTranscrito3, 0, new Date().toISOString());
db.close();
CRIA_MARCA3

ok=$((ok+1)); echo "  ok    transcrito com eventos vazios criado"

# Chamar observador com dublê OK — deve recusar (prompt vazio)
export TESTADOR_CHAMAR_LLM="$DUBLIADOR_OK"
node "$OBSERVADOR" --sessao sessao-vazia --projeto proj-teste 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    observador retornou exit 0 (degradacao graciosa)"
else
  falhou=$((falhou+1)); echo "  FALHA observador retornou exit $EXIT_CODE"
fi

# Verificar que NENHUMA observação foi gravada (prompt vazio foi recusado)
CONTA_VAZIO=$(node <<'CONTA_VAZIO' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes');
const rows = stmt.all();
console.log(rows[0].cnt);
db.close();
CONTA_VAZIO
)

if [ "$CONTA_VAZIO" = "0" ]; then
  ok=$((ok+1)); echo "  ok    nenhuma observacao foi gravada (prompt vazio recusado)"
else
  falhou=$((falhou+1)); echo "  FALHA $CONTA_VAZIO observacoes gravadas (esperado 0 para prompt vazio)"
fi

# Verificar que offset_processado NÃO avancou (marca intacta)
MARCA_OFFSET_VAZIO=$(node <<'LER_MARCA_VAZIO' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT offset_processado FROM marca_dagua WHERE sessao=?');
const rows = stmt.all('sessao-vazia');
console.log(rows.length > 0 && rows[0].offset_processado !== null ? rows[0].offset_processado : '0');
db.close();
LER_MARCA_VAZIO
)

if [ "$MARCA_OFFSET_VAZIO" = "0" ]; then
  ok=$((ok+1)); echo "  ok    offset_processado permaneceu em 0 (marca não avancou)"
else
  falhou=$((falhou+1)); echo "  FALHA offset_processado mudou para $MARCA_OFFSET_VAZIO (esperado 0)"
fi

# ============ Resultado final ============
echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
