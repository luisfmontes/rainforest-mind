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

# ============ Teste 14: modo producao — SEM argumentos ============
# Achado 6 da tarefa 22: esta bateria so exercitava
# `observar.cjs --sessao X --projeto Y`, mas hooks/hooks.json chama
# `node observar.cjs` SEM argumento nenhum, tanto em SessionStart quanto em
# SessionEnd — o modo que roda em producao era justamente o que nao tinha
# bateria nenhuma. Sem --sessao/--projeto, processarSessao() cai no modo 2:
# le TODAS as marcas com pendencia (offset > offset_processado) e processa
# cada uma.
echo
echo "14. Modo producao: observar.cjs SEM argumentos processa marcas pendentes"

node <<'LIMPA14' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
db.exec('DELETE FROM observacoes');
db.exec('DELETE FROM marca_dagua');
db.close();
LIMPA14

TRANSCRITO_SEMARG="$RFM_ROOT/projects/proj-teste/sessao-semarg.jsonl"
cat > "$TRANSCRITO_SEMARG" <<'EOF'
{"type":"user","message":{"role":"user","content":"Qual eh a capital do Japao?"},"timestamp":"2026-08-19T10:02:00Z","sessionId":"sessao-semarg","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"A capital eh Toquio"}]},"timestamp":"2026-08-19T10:02:01Z","sessionId":"sessao-semarg","version":"2.1.0","cwd":"test"}
EOF

node <<CRIA_MARCA_SEMARG 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const fs = require('fs');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare(\`INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?, ?, ?, ?, ?, ?)\`);
const caminhoTranscrito = path.join(process.env.RFM_ROOT, 'projects', 'proj-teste', 'sessao-semarg.jsonl');
const tamanho = fs.statSync(caminhoTranscrito).size;
stmt.run('proj-teste', 'sessao-semarg', caminhoTranscrito, tamanho, 0, new Date().toISOString());
db.close();
CRIA_MARCA_SEMARG

export TESTADOR_CHAMAR_LLM="$DUBLIADOR_OK"
SAIDA_SEMARG=$(node "$OBSERVADOR" 2>&1)
EXIT_SEMARG=$?

if [ $EXIT_SEMARG -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    observador sem argumentos (modo producao) saiu 0"
else
  falhou=$((falhou+1)); echo "  FALHA observador sem argumentos saiu $EXIT_SEMARG"
  echo "$SAIDA_SEMARG" | sed 's/^/         /'
fi

CONTA_SEMARG=$(node <<'CONTA_SEMARG' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes WHERE projeto=?');
const rows = stmt.all('proj-teste');
console.log(rows[0].cnt);
db.close();
CONTA_SEMARG
)

if [ "$CONTA_SEMARG" -eq 1 ]; then
  ok=$((ok+1)); echo "  ok    modo producao (sem args) processou a marca pendente e gravou 1 observacao"
else
  falhou=$((falhou+1)); echo "  FALHA modo producao (sem args) nao processou: $CONTA_SEMARG observacoes (esperado 1)"
fi

# ---- Mutacao: prova que o Teste 14 pega regressao no modo 2 (numa COPIA) ----
# Se o modo "sem argumentos" quebrar (o unico que hooks.json realmente chama),
# esta bateria tinha zero chance de perceber antes do achado 6. A mutacao
# desliga o modo 2 numa copia de observar.cjs — nunca no arquivo rastreado —
# e confirma que o Teste 14 vira vermelho.
MUT14_DIR="$(mktemp -d)"
cp -r "$SRC/hooks" "$MUT14_DIR/hooks"
cp -r "$SRC/scripts" "$MUT14_DIR/scripts"
MUT14_OBSERVAR="$MUT14_DIR/scripts/observar.cjs"

cat > "$MUT14_DIR/muta-modo2.cjs" <<'MUTEOF'
const fs = require('fs');
const alvo = process.env.ALVO;
const original = fs.readFileSync(alvo, 'utf8');
const trecho = "      console.log(`encontradas ${marcas.length} marca(s) com pendencia`);";
if (!original.includes(trecho)) {
  console.error('TRECHO_NAO_ENCONTRADO');
  process.exit(1);
}
// MUTACAO: modo 2 (sem argumentos) para de processar — como se o "else" de
// processarSessao() nunca existisse. E exatamente o modo que hooks.json chama.
fs.writeFileSync(alvo, original.replace(trecho, trecho + '\n      return; // MUTACAO: modo sem argumentos nunca processa'));
console.log('MUTADO');
MUTEOF

MUTA14_OUT=$(ALVO="$MUT14_OBSERVAR" node "$MUT14_DIR/muta-modo2.cjs" 2>&1)
if echo "$MUTA14_OUT" | grep -q "^MUTADO$"; then
  ok=$((ok+1)); echo "  ok    mutacao aplicada na copia (modo sem argumentos desligado)"
else
  falhou=$((falhou+1)); echo "  FALHA nao consegui mutar a copia — o texto de observar.cjs pode ter mudado"
  echo "$MUTA14_OUT" | sed 's/^/         /'
fi

# Novo transcrito+marca pendente, banco limpo, mesma sandbox de dados
node <<'LIMPA14B' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
db.exec('DELETE FROM observacoes');
db.exec('DELETE FROM marca_dagua');
db.close();
LIMPA14B

TRANSCRITO_MUT14="$RFM_ROOT/projects/proj-teste/sessao-mut14.jsonl"
cat > "$TRANSCRITO_MUT14" <<'EOF'
{"type":"user","message":{"role":"user","content":"Qual eh a capital da China?"},"timestamp":"2026-08-19T10:03:00Z","sessionId":"sessao-mut14","version":"2.1.0","cwd":"test"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"A capital eh Pequim"}]},"timestamp":"2026-08-19T10:03:01Z","sessionId":"sessao-mut14","version":"2.1.0","cwd":"test"}
EOF

node <<CRIA_MARCA_MUT14 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const fs = require('fs');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare(\`INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?, ?, ?, ?, ?, ?)\`);
const caminhoTranscrito = path.join(process.env.RFM_ROOT, 'projects', 'proj-teste', 'sessao-mut14.jsonl');
const tamanho = fs.statSync(caminhoTranscrito).size;
stmt.run('proj-teste', 'sessao-mut14', caminhoTranscrito, tamanho, 0, new Date().toISOString());
db.close();
CRIA_MARCA_MUT14

SAIDA_MUT14=$(node "$MUT14_OBSERVAR" 2>&1)

CONTA_MUT14=$(node <<'CONTA_MUT14' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes WHERE projeto=?');
const rows = stmt.all('proj-teste');
console.log(rows[0].cnt);
db.close();
CONTA_MUT14
)

if [ "$CONTA_MUT14" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    mutacao pegou: modo sem argumentos desligado nao gravou observacao nenhuma (o Teste 14 real acima acusaria isso)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao nao reproduziu o bug: $CONTA_MUT14 observacoes gravadas (esperava 0)"
fi

rm -rf "$MUT14_DIR"

# ============ Fatiamento por teto de argumento (tarefa 6) ============
# Esta seção não existia, e a entrega da tarefa 6 foi commitada afirmando que
# esta bateria passava: `git diff 1a1dae5..ad79433 -- scripts/testa-observar.sh`
# devolvia ZERO linhas. O comportamento funcionava — provado à mão —, mas nada
# no CI segurava uma regressão. O modo de falha que isso deixaria passar é caro
# e silencioso: transcrito grande (o caso comum) estoura `ENAMETOOLONG`, nenhuma
# observação é gravada, e não há erro na tela — para sempre, a cada sessão.
echo
echo "== 8. trecho maior que o teto vira N chamadas, e a marca avanca por fatia =="

FATIA_DIR="$(mktemp -d)"
CONTA_LOG="$FATIA_DIR/chamadas.log"
: > "$CONTA_LOG"

# Dublê que registra o tamanho de cada chamada recebida.
cat > "$FATIA_DIR/duble-conta.cjs" <<'DUBLE_CONTA'
const fs = require('fs');
module.exports.chamarLLM = async (texto) => {
  fs.appendFileSync(process.env.DUBLE_CONTA_LOG, texto.length + '\n');
  return 'resumo da fatia de ' + texto.length + ' caracteres';
};
DUBLE_CONTA

mkdir -p "$FATIA_DIR/projects/proj-fatia"
TRANSCRITO_GRANDE="$FATIA_DIR/projects/proj-fatia/sgrande.jsonl"
TRANSCRITO_GRANDE="$TRANSCRITO_GRANDE" node --no-warnings <<'GERA_GRANDE'
const fs = require('fs');
const alvo = process.env.TRANSCRITO_GRANDE;
const linhas = [];
// 60 pares pergunta/resposta de ~300 caracteres cada: ~57 kB, mais de 3x o teto.
for (let i = 1; i <= 60; i++) {
  linhas.push(JSON.stringify({type:'user',message:{role:'user',content:'Pergunta '+i+': '+'x'.repeat(300)},timestamp:'2026-08-20T05:00:00Z',sessionId:'sgrande',version:'2.1.0',cwd:'test'}));
  linhas.push(JSON.stringify({type:'assistant',message:{role:'assistant',content:[{type:'text',text:'Resposta '+i+': '+'y'.repeat(300)}]},timestamp:'2026-08-20T05:00:01Z',sessionId:'sgrande',version:'2.1.0',cwd:'test'}));
}
fs.writeFileSync(alvo, linhas.join('\n') + '\n');
GERA_GRANDE
TAM_GRANDE=$(wc -c < "$TRANSCRITO_GRANDE")

RFM_ROOT="$FATIA_DIR" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
(cd "$SRC" && RFM_ROOT="$FATIA_DIR" TRANSCRITO_GRANDE="$TRANSCRITO_GRANDE" TAM_GRANDE="$TAM_GRANDE" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco(process.env.RFM_ROOT + '/rainforest.db');
db.prepare('INSERT INTO marca_dagua (projeto,sessao,arquivo,offset,offset_processado,processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-fatia','sgrande',process.env.TRANSCRITO_GRANDE,Number(process.env.TAM_GRANDE),0,'2026-08-20T05:00:00Z');
db.close();
")

RFM_ROOT="$FATIA_DIR" DUBLE_CONTA_LOG="$CONTA_LOG" TESTADOR_CHAMAR_LLM="$FATIA_DIR/duble-conta.cjs" \
  node "$SRC/scripts/observar.cjs" > /dev/null 2>&1
SAIDA_FATIA=$?

TETO=$(grep -o 'TETO_ARGUMENTO = [0-9]*' "$SRC/scripts/observar.cjs" | grep -o '[0-9]*')
NUM_CHAMADAS=$(grep -c . "$CONTA_LOG")
MAIOR_FATIA=$(sort -n "$CONTA_LOG" | tail -1)

if [ "$SAIDA_FATIA" -eq 0 ] && [ "$NUM_CHAMADAS" -gt 1 ]; then
  ok=$((ok+1)); echo "  ok    transcrito de $TAM_GRANDE bytes virou $NUM_CHAMADAS chamadas"
else
  falhou=$((falhou+1)); echo "  FALHA esperava mais de 1 chamada, veio $NUM_CHAMADAS (exit $SAIDA_FATIA)"
fi

if [ -n "$MAIOR_FATIA" ] && [ "$MAIOR_FATIA" -le "$TETO" ]; then
  ok=$((ok+1)); echo "  ok    nenhuma fatia passou do teto (maior: $MAIOR_FATIA de $TETO)"
else
  falhou=$((falhou+1)); echo "  FALHA fatia de $MAIOR_FATIA passou do teto de $TETO"
fi

# A marca tem que chegar ao fim do arquivo, e o número de observações tem que
# bater com o número de fatias — é isso que prova avanço POR fatia, e não um
# único avanço no fim.
ESTADO_FATIA=$(cd "$SRC" && RFM_ROOT="$FATIA_DIR" node --no-warnings -e "
const { abrirBancoSomenteLeitura } = require('./scripts/memoria.cjs');
const db = abrirBancoSomenteLeitura(process.env.RFM_ROOT + '/rainforest.db');
const m = db.prepare('SELECT offset_processado o FROM marca_dagua').get();
const n = db.prepare('SELECT count(*) c FROM observacoes').get().c;
db.close();
process.stdout.write((m ? m.o : 'sem-marca') + ':' + n);
")
if [ "$ESTADO_FATIA" = "$TAM_GRANDE:$NUM_CHAMADAS" ]; then
  ok=$((ok+1)); echo "  ok    marca em $TAM_GRANDE e $NUM_CHAMADAS observacoes gravadas (uma por fatia)"
else
  falhou=$((falhou+1)); echo "  FALHA esperava '$TAM_GRANDE:$NUM_CHAMADAS', veio '$ESTADO_FATIA'"
fi

echo
echo "  8.b — FALSIFICACAO: sem fatiamento, a chamada unica estoura o teto"
# A mutação é o teto artificialmente alto — o mesmo caminho de código, sem o
# corte. Se a chamada única NÃO passar do teto real medido, o fixture não é
# grande o bastante e a prova acima não vale nada.
: > "$CONTA_LOG"
CAIXA_MUT="$(mktemp -d)"; mkdir -p "$CAIXA_MUT/projects/proj-fatia"
cp "$TRANSCRITO_GRANDE" "$CAIXA_MUT/projects/proj-fatia/sgrande.jsonl"
RFM_ROOT="$CAIXA_MUT" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
(cd "$SRC" && RFM_ROOT="$CAIXA_MUT" TAM_GRANDE="$TAM_GRANDE" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco(process.env.RFM_ROOT + '/rainforest.db');
db.prepare('INSERT INTO marca_dagua (projeto,sessao,arquivo,offset,offset_processado,processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-fatia','sgrande',process.env.RFM_ROOT + '/projects/proj-fatia/sgrande.jsonl',Number(process.env.TAM_GRANDE),0,'2026-08-20T05:00:00Z');
db.close();
")
# A cópia leva `scripts/` E `hooks/`: o `memoria.cjs` faz require de
# `../hooks/lib/raiz.cjs`, então copiar só `scripts/` deixa a cópia sem resolver
# módulo e o teste "passaria" com zero chamadas — vacuidade pela porta dos fundos.
ARVORE_MUT="$CAIXA_MUT/arvore"
mkdir -p "$ARVORE_MUT"
cp -r "$SRC/scripts" "$ARVORE_MUT/scripts"
cp -r "$SRC/hooks" "$ARVORE_MUT/hooks"
sed -i 's/^const TETO_ARGUMENTO = [0-9]*;/const TETO_ARGUMENTO = 9999999;/' "$ARVORE_MUT/scripts/observar.cjs"
RFM_ROOT="$CAIXA_MUT" DUBLE_CONTA_LOG="$CONTA_LOG" TESTADOR_CHAMAR_LLM="$FATIA_DIR/duble-conta.cjs" \
  node "$ARVORE_MUT/scripts/observar.cjs" > /dev/null 2>&1
CHAMADAS_MUT=$(grep -c . "$CONTA_LOG")
MAIOR_MUT=$(sort -n "$CONTA_LOG" | tail -1)

if [ "$CHAMADAS_MUT" = "1" ] && [ -n "$MAIOR_MUT" ] && [ "$MAIOR_MUT" -gt "$TETO" ]; then
  ok=$((ok+1)); echo "  ok    VERMELHO: com teto alto vira 1 chamada de $MAIOR_MUT caracteres, acima do teto de $TETO"
else
  falhou=$((falhou+1)); echo "  FALHA falsificacao nao vale: $CHAMADAS_MUT chamada(s), maior de $MAIOR_MUT, teto $TETO"
fi

echo
echo "  8.c — orcamento de tempo: para no meio e deixa a marca no que ja processou"
# Por que: o hook tem teto de 120 s e uma chamada pode levar até 65 s. Com N
# fatias sequenciais, o harness mataria o processo no meio. O orçamento faz a
# passada parar sozinha e devolver o resto para a próxima sessão — o que só é
# seguro porque a marca avança POR fatia.
ORC_DIR="$(mktemp -d)"; mkdir -p "$ORC_DIR/projects/proj-fatia"
cp "$FATIA_DIR/projects/proj-fatia/sgrande.jsonl" "$ORC_DIR/projects/proj-fatia/sgrande.jsonl" 2>/dev/null
cat > "$ORC_DIR/duble-lento.cjs" <<'DUBLE_LENTO'
module.exports.chamarLLM = async (texto) => {
  // Mais lento que o orçamento do teste, para estourar já na primeira fatia.
  await new Promise((r) => setTimeout(r, 250));
  return 'resumo lento de ' + texto.length;
};
DUBLE_LENTO
RFM_ROOT="$ORC_DIR" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
(cd "$SRC" && RFM_ROOT="$ORC_DIR" TAM_GRANDE="$TAM_GRANDE" node --no-warnings -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const db = abrirBanco(process.env.RFM_ROOT + '/rainforest.db');
db.prepare('INSERT INTO marca_dagua (projeto,sessao,arquivo,offset,offset_processado,processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-fatia','sgrande',process.env.RFM_ROOT + '/projects/proj-fatia/sgrande.jsonl',Number(process.env.TAM_GRANDE),0,'2026-08-20T05:00:00Z');
db.close();
")
SAIDA_ORC=$(RFM_ROOT="$ORC_DIR" TESTADOR_ORCAMENTO_MS=100 TESTADOR_CHAMAR_LLM="$ORC_DIR/duble-lento.cjs" \
  node "$SRC/scripts/observar.cjs" 2>&1)
ESTADO_ORC=$(cd "$SRC" && RFM_ROOT="$ORC_DIR" node --no-warnings -e "
const { abrirBancoSomenteLeitura } = require('./scripts/memoria.cjs');
const db = abrirBancoSomenteLeitura(process.env.RFM_ROOT + '/rainforest.db');
const m = db.prepare('SELECT offset_processado o FROM marca_dagua').get();
const n = db.prepare('SELECT count(*) c FROM observacoes').get().c;
db.close();
process.stdout.write((m ? m.o : 'sem-marca') + ':' + n);
")
OFFSET_ORC="${ESTADO_ORC%%:*}"; OBS_ORC="${ESTADO_ORC##*:}"

# O que prova o orçamento: parou ANTES do fim (menos observações que fatias) e
# a marca ficou num ponto INTERMEDIÁRIO — nem 0 (não perdeu o que fez) nem o
# fim do arquivo (não fingiu ter terminado).
if echo "$SAIDA_ORC" | grep -q "orcamento de 100ms atingido"; then
  ok=$((ok+1)); echo "  ok    a passada anunciou a parada por orcamento"
else
  falhou=$((falhou+1)); echo "  FALHA nao houve parada por orcamento: $(echo "$SAIDA_ORC" | tail -1)"
fi

if [ "$OBS_ORC" -ge 1 ] && [ "$OBS_ORC" -lt "$NUM_CHAMADAS" ] && [ "$OFFSET_ORC" -gt 0 ] && [ "$OFFSET_ORC" -lt "$TAM_GRANDE" ]; then
  ok=$((ok+1)); echo "  ok    parou no meio: $OBS_ORC de $NUM_CHAMADAS fatias, marca em $OFFSET_ORC de $TAM_GRANDE"
else
  falhou=$((falhou+1)); echo "  FALHA esperava parada intermediaria, veio $OBS_ORC observacao(oes) e marca em $OFFSET_ORC de $TAM_GRANDE"
fi

rm -rf "$FATIA_DIR" "$CAIXA_MUT" "$ORC_DIR"

# ============ Teste 15: --help imprime sem tocar no banco ============
echo
echo "15. --help imprime ajuda, exit 0, sem tocar no banco"

node <<'LIMPA15' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
db.exec('DELETE FROM observacoes');
db.exec('DELETE FROM marca_dagua');
db.close();
LIMPA15

# Criar um banco vazio e medir antes de chamar --help
BANCO_ANTES=$(ls -l "$CAIXA/rainforest/rainforest.db" 2>/dev/null | awk '{print $5":"$6":"$7":"$8}' || echo 'naexiste')
SAIDA_HELP=$(node "$OBSERVADOR" --help 2>&1)
EXIT_HELP=$?
BANCO_DEPOIS=$(ls -l "$CAIXA/rainforest/rainforest.db" 2>/dev/null | awk '{print $5":"$6":"$7":"$8}' || echo 'naexiste')

if [ $EXIT_HELP -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    --help saiu com exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA --help saiu com exit $EXIT_HELP"
fi

if echo "$SAIDA_HELP" | grep -q "Passada de LLM"; then
  ok=$((ok+1)); echo "  ok    --help imprime descrição"
else
  falhou=$((falhou+1)); echo "  FALHA --help não imprimiu descrição esperada"
fi

if echo "$SAIDA_HELP" | grep -q "\-\-seco"; then
  ok=$((ok+1)); echo "  ok    --help menciona --seco"
else
  falhou=$((falhou+1)); echo "  FALHA --help não menciona --seco"
fi

if [ "$BANCO_ANTES" = "$BANCO_DEPOIS" ]; then
  ok=$((ok+1)); echo "  ok    banco intacto (não foi alterado por --help)"
else
  falhou=$((falhou+1)); echo "  FALHA banco foi alterado: antes=$BANCO_ANTES, depois=$BANCO_DEPOIS"
fi

# ============ Teste 16: --seco lista pendentes sem LLM ============
echo
echo "16. --seco lista marcas pendentes sem chamar LLM"

node <<'LIMPA16' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
db.exec('DELETE FROM observacoes');
db.exec('DELETE FROM marca_dagua');
db.close();
LIMPA16

# Criar transcrito e marca pendente
TRANSCRITO_SECO="$RFM_ROOT/projects/proj-teste/sessao-seco.jsonl"
cat > "$TRANSCRITO_SECO" <<'EOF'
{"type":"user","message":{"role":"user","content":"Teste seco"},"timestamp":"2026-08-19T10:00:00Z","sessionId":"sessao-seco","version":"2.1.0","cwd":"test"}
EOF

OFFSET_SECO=$(wc -c < "$TRANSCRITO_SECO")

node <<CRIA_MARCA_SECO 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare(\`INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?, ?, ?, ?, ?, ?)\`);
stmt.run('proj-teste', 'sessao-seco', '$TRANSCRITO_SECO', $OFFSET_SECO, 0, new Date().toISOString());
db.close();
CRIA_MARCA_SECO

# Criar dublê que registra se foi chamado
DUBLE_SECO_DIR="$(mktemp -d)"
# O sentinela do duble NAO pode ser um caminho `/tmp/...`: para o Node no Windows
# `/tmp` e `C:\tmp\`, e para o bash e outra pasta. Medido em 2026-08-25, na
# integracao da #86 — o arquivo era escrito em C:\tmp e o `[ ! -f /tmp/llm-foi-chamado ]`
# daqui NUNCA o encontrava. A assercao "nao chamou LLM" passava VAZIA, e teria passado
# igual se o --seco chamasse o LLM a cada marca. Caminho por env, em pasta que os dois
# lados enxergam, e convertido com cygpath para o Node.
DUBLE_SECO_DIR_WIN="$(cygpath -m "$DUBLE_SECO_DIR" 2>/dev/null || printf '%s' "$DUBLE_SECO_DIR")"
SENTINELA_LLM="$DUBLE_SECO_DIR/llm-foi-chamado"
cat > "$DUBLE_SECO_DIR/duble-seco.cjs" <<'DUBLE_SECO'
const fs = require('fs');
module.exports.chamarLLM = async (texto) => {
  fs.writeFileSync(process.env.TESTADOR_SENTINELA_LLM, 'sim');
  return 'resumo';
};
DUBLE_SECO

rm -f "$SENTINELA_LLM"
SAIDA_SECO=$(TESTADOR_CHAMAR_LLM="$DUBLE_SECO_DIR_WIN/duble-seco.cjs" TESTADOR_SENTINELA_LLM="$DUBLE_SECO_DIR_WIN/llm-foi-chamado" node "$OBSERVADOR" --seco 2>&1)
EXIT_SECO=$?

if [ $EXIT_SECO -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    --seco saiu com exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA --seco saiu com exit $EXIT_SECO"
fi

if echo "$SAIDA_SECO" | grep -q "encontradas.*marca"; then
  ok=$((ok+1)); echo "  ok    --seco listou marcas pendentes"
else
  falhou=$((falhou+1)); echo "  FALHA --seco não listou marcas: [$SAIDA_SECO]"
fi

if [ ! -f "$SENTINELA_LLM" ]; then
  ok=$((ok+1)); echo "  ok    --seco não chamou LLM"
else
  falhou=$((falhou+1)); echo "  FALHA --seco chamou LLM (encontrado $SENTINELA_LLM)"
fi

# Verificar que nenhuma observação foi gravada
CONTA_SECO=$(node <<'CONTA_SECO' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT COUNT(*) as cnt FROM observacoes');
const rows = stmt.all();
console.log(rows[0].cnt);
db.close();
CONTA_SECO
)

if [ "$CONTA_SECO" = "0" ]; then
  ok=$((ok+1)); echo "  ok    --seco não gravou observações"
else
  falhou=$((falhou+1)); echo "  FALHA --seco gravou $CONTA_SECO observações (esperado 0)"
fi

# Verificar que marca não avancou
MARCA_SECO=$(node <<'MARCA_SECO' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const stmt = db.prepare('SELECT offset_processado FROM marca_dagua WHERE sessao=?');
const rows = stmt.all('sessao-seco');
console.log(rows.length > 0 && rows[0].offset_processado !== null ? rows[0].offset_processado : '0');
db.close();
MARCA_SECO
)

if [ "$MARCA_SECO" = "0" ]; then
  ok=$((ok+1)); echo "  ok    --seco não avançou a marca"
else
  falhou=$((falhou+1)); echo "  FALHA marca avançou para $MARCA_SECO (esperado 0)"
fi

rm -rf "$DUBLE_SECO_DIR"

echo
echo "  16.b — MUTACAO: fazer --seco cair no caminho que PROCESSA, e exigir que o 16 acuse"
# A versao anterior desta secao nao mutava nada: mandava um heredoc pelo STDIN do
# proprio observar.cjs, nunca reescrevia arquivo nenhum, e creditava `ok`
# incondicionalmente. Passava verde sem ter executado mutacao -- exatamente a familia
# de defeito que a Issue #61 descreve. Reescrita em 2026-08-25, na integracao da #86.
#
# A mutacao de verdade: tirar o `return` do ramo do `--seco`, para que ele siga para
# `processarSessao`. Se as assercoes do Teste 16 tiverem dente, o mutante chama o LLM
# -- e e isso que se prova aqui.
#
# CAIXA PROPRIA, e isso nao e zelo: a primeira tentativa reusou o sandbox das secoes
# anteriores e o mutante nao achou marca pendente nenhuma para processar, entao a
# mutacao "nao teve efeito" por falta de fixture, nao por falta de defeito -- que e
# o mesmo modo de falha que esta secao existe para pegar, um nivel acima.

MUT_CAIXA="$(mktemp -d)"
MUT_DIR="$(mktemp -d)"
MUT_DIR_WIN="$(cygpath -m "$MUT_DIR" 2>/dev/null || printf '%s' "$MUT_DIR")"
mkdir -p "$MUT_CAIXA/rainforest/projects/proj-mut"
cp -r "$SRC/scripts" "$MUT_DIR/scripts"
cp -r "$SRC/hooks" "$MUT_DIR/hooks"

RFM_ROOT="$MUT_CAIXA/rainforest" node "$SRC/scripts/memoria.cjs" iniciar >/dev/null 2>&1
MUT_TRANSCRITO="$MUT_CAIXA/rainforest/projects/proj-mut/s-mut.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"evento de fixture"},"timestamp":"2026-08-19T10:00:00Z","sessionId":"s-mut","version":"2.1.0","cwd":"x"}' > "$MUT_TRANSCRITO"
MUT_OFFSET="$(wc -c < "$MUT_TRANSCRITO")"
MUT_TRANSCRITO_WIN="$(cygpath -m "$MUT_TRANSCRITO" 2>/dev/null || printf '%s' "$MUT_TRANSCRITO")"

RFM_ROOT="$MUT_CAIXA/rainforest" node -e '
const { abrirBanco } = require(process.argv[1] + "/scripts/memoria.cjs");
const path = require("path");
const db = abrirBanco(path.join(process.env.RFM_ROOT, "rainforest.db"));
db.prepare("INSERT INTO marca_dagua (projeto,sessao,arquivo,offset,offset_processado,processada_em) VALUES (?,?,?,?,?,?)")
  .run("proj-mut", "s-mut", process.argv[2], Number(process.argv[3]), 0, new Date().toISOString());
db.close();
' "$SRC" "$MUT_TRANSCRITO_WIN" "$MUT_OFFSET" 2>/dev/null

cat > "$MUT_DIR/sabotar-seco.cjs" <<'SABOTA_SECO_EOF'
const fs = require('fs');
const alvo = process.argv[2];
let t = fs.readFileSync(alvo, 'utf8');
const achar = "  if (temArg('seco')) {\n    modoSeco();\n    return;\n  }";
const trocar = "  if (temArg('seco')) {\n    modoSeco();\n  }";
if (!t.includes(achar)) { console.error('ANCORA NAO BATE em ' + alvo); process.exit(1); }
fs.writeFileSync(alvo, t.replace(achar, trocar));
SABOTA_SECO_EOF

node "$MUT_DIR/sabotar-seco.cjs" "$MUT_DIR/scripts/observar.cjs"
EXIT_SABOTA_SECO=$?
if [ "$EXIT_SABOTA_SECO" != "0" ]; then
  falhou=$((falhou+1))
  echo "  FALHA ANCORA NAO BATE na mutacao do --seco — a copia intocada nao prova nada"
else
  # O sentinela vai para um caminho que os DOIS lados enxergam, e o caminho chega por
  # env. O duble do Teste 16 escrevia em `/tmp/llm-foi-chamado`: para o Node no
  # Windows isso e `C:\tmp\`, e para o bash e outra pasta -- entao o `[ ! -f /tmp/... ]`
  # NUNCA achava o arquivo, e a assercao "nao chamou LLM" passava vazia. Medido em
  # 2026-08-25, na integracao da #86.
  cat > "$MUT_DIR/duble-mut.cjs" <<'DUBLE_MUT_EOF'
const fs = require('fs');
module.exports.chamarLLM = async () => {
  fs.writeFileSync(process.env.TESTADOR_SENTINELA_LLM, 'sim');
  return 'resumo do duble';
};
DUBLE_MUT_EOF

  MUT_SENTINELA="$MUT_DIR/llm-foi-chamado"
  rm -f "$MUT_SENTINELA"
  RFM_ROOT="$MUT_CAIXA/rainforest" \
    TESTADOR_CHAMAR_LLM="$MUT_DIR_WIN/duble-mut.cjs" \
    TESTADOR_SENTINELA_LLM="$MUT_DIR_WIN/llm-foi-chamado" \
    node "$MUT_DIR/scripts/observar.cjs" --seco >/dev/null 2>&1

  if [ -f "$MUT_SENTINELA" ]; then
    ok=$((ok+1)); echo "  ok    mutacao expos o dente do Teste 16: sem o return, o --seco chama o LLM"
  else
    falhou=$((falhou+1))
    echo "  FALHA mutacao sem efeito — tirar o return do ramo --seco nao fez o mutante processar."
    echo "        Sem isto, as assercoes do Teste 16 nao estao provadas: podem estar passando"
    echo "        porque nada acontece, nao porque o --seco se contem."
  fi
fi
rm -rf "$MUT_DIR" "$MUT_CAIXA"


# ============ Teste 17: evento único acima do teto não trava a marca d'água ============
# Causa raiz das 34 pendências de 21-31/08: um tool output maior que
# TETO_ARGUMENTO gerava fatia de 1 evento acima do teto, chamarLLM devolvia
# null pelo guarda, e a marca nunca avançava — retentado e re-falhado a cada
# sessão. A passada agora TRUNCA o texto (transcrito em disco intacto).
echo
echo "17. evento unico acima do teto e truncado, observacao gravada e marca avanca"

GORDO_DIR=$(mktemp -d)
export RFM_ROOT="$GORDO_DIR"
node "$MEMORIA" iniciar >/dev/null 2>&1
mkdir -p "$GORDO_DIR/projects/proj-gordo"
TRANSCRITO_GORDO="$GORDO_DIR/projects/proj-gordo/sessao-gorda.jsonl"
node <<'CRIA_GORDO' 2>/dev/null
const fs = require('fs');
const path = require('path');
const caminho = path.join(process.env.RFM_ROOT, 'projects', 'proj-gordo', 'sessao-gorda.jsonl');
// Um único evento com ~20000 caracteres de texto — acima do TETO_ARGUMENTO (16000)
const gordo = 'PALAVRAGORDA '.repeat(1600);
const linhas = [
  JSON.stringify({type:'user',message:{role:'user',content:'inicio ' + gordo},timestamp:'2026-08-19T10:00:00Z',sessionId:'sessao-gorda',version:'2.1.0',cwd:'test'}),
];
fs.writeFileSync(caminho, linhas.join('\n') + '\n');
CRIA_GORDO
node <<'CRIA_MARCA_GORDA' 2>/dev/null
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const caminho = path.join(process.env.RFM_ROOT, 'projects', 'proj-gordo', 'sessao-gorda.jsonl');
db.prepare('INSERT OR REPLACE INTO marca_dagua (projeto, sessao, arquivo, offset, processada_em) VALUES (?, ?, ?, ?, ?)')
  .run('proj-gordo', 'sessao-gorda', caminho, 0, new Date().toISOString());
db.close();
CRIA_MARCA_GORDA

export TESTADOR_CHAMAR_LLM="$DUBLIADOR_OK"
SAIDA_GORDA=$(node "$OBSERVADOR" --sessao sessao-gorda --projeto proj-gordo 2>&1)
EXIT_GORDO=$?
OBS_GORDA=$(node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');
const path = require('path');
const db = abrirBanco(path.join(process.env.RFM_ROOT, 'rainforest.db'));
const r = db.prepare(\"SELECT count(*) c FROM observacoes WHERE projeto='proj-gordo'\").get();
const m = db.prepare(\"SELECT offset, COALESCE(offset_processado,0) op FROM marca_dagua WHERE sessao='sessao-gorda'\").get();
console.log(r.c + ' ' + (m ? m.op : 'sem-marca'));
db.close();
" 2>/dev/null)
CONTAGEM_GORDA=$(echo "$OBS_GORDA" | cut -d' ' -f1)
OFFSET_GORDO=$(echo "$OBS_GORDA" | cut -d' ' -f2)

if [ "$EXIT_GORDO" -eq 0 ] && [ "$CONTAGEM_GORDA" -ge 1 ] && [ "$OFFSET_GORDO" -gt 0 ]; then
  ok=$((ok+1)); echo "  ok    evento gordo truncado: observacao gravada ($CONTAGEM_GORDA) e marca avancou (offset_processado=$OFFSET_GORDO)"
else
  falhou=$((falhou+1)); echo "  FALHA evento gordo travou: exit=$EXIT_GORDO obs=$CONTAGEM_GORDA offset_processado=$OFFSET_GORDO"
  echo "$SAIDA_GORDA" | tail -3
fi
unset TESTADOR_CHAMAR_LLM
rm -rf "$GORDO_DIR"

# ============ Resultado final ============
echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
