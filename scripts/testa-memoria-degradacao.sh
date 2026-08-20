#!/bin/bash
# Bateria: Banco corrompido degrada graciosamente (Tarefa 21)
#
# Testa que abrirBanco() LANÇA exceção (em vez de chamar process.exit)
# permitindo que o chamador (hook de SessionStart, etc) trate o erro
# e degrade graciosamente.
#
# Prova:
# 1. abrirBanco() em arquivo corrompido lança exceção
# 2. Chamador consegue capturar e degradar (exit 0)
# 3. Sem abrirBanco(), a sessão não fica travada
#
# Uso: bash scripts/testa-memoria-degradacao.sh
# Exit: 0 se verde, 1 se vermelho

set -e

RAIZ=$(pwd)
TEMP_DIR="${RFM_ROOT:-.rainforest-teste-degradacao}"
DB_CORROMPIDO="$TEMP_DIR/rainforest-corrompido.db"
DB_VALIDO="$TEMP_DIR/rainforest-valido.db"

cleanup() {
  rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

cleanup
mkdir -p "$TEMP_DIR"

# 1. Criar banco válido (para referência)
echo "[1] Criar banco válido para referência..."
node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('$DB_VALIDO');
db.exec('CREATE TABLE teste (id INTEGER PRIMARY KEY);');
db.exec('INSERT INTO teste VALUES (1);');
db.close();
"

# 2. Criar banco corrompido (arquivo inválido)
echo "[2] Criar banco corrompido..."
printf '\x00\x01\x02\x03\xff\xfe\xfd' > "$DB_CORROMPIDO"

# 3. Testar que abrirBanco() com arquivo corrompido LANÇA exceção
echo "[3] Testar que abrirBanco() lança exceção em banco corrompido..."
LANCOU_EXCECAO=$(node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');

try {
  const db = abrirBanco('$DB_CORROMPIDO');
  console.log('nao');
  process.exit(0);
} catch (e) {
  // ESPERADO: lançou exceção
  console.log('sim');
  process.exit(0);
}
")

if [ "$LANCOU_EXCECAO" = "sim" ]; then
  echo "✓ abrirBanco() lançou exceção (correto)"
else
  echo "❌ abrirBanco() não lançou exceção"
  exit 1
fi

# 4. Testar degradação: chamador captura exceção e degrada
echo "[4] Testar degradação em hook (try/catch captura exceção)..."
DEGRADOU=$(node -e "
const { abrirBanco, criarSchema } = require('./scripts/memoria.cjs');

function simularHook(caminhoDb) {
  try {
    const conexao = abrirBanco(caminhoDb);
    criarSchema(conexao);
    console.log('nao-degradou');
    conexao.close();
  } catch (e) {
    // DEGRADAÇÃO: hook captura e continua sem banco
    console.log('degradou');
  }
}

simularHook('$DB_CORROMPIDO');
")

if [ "$DEGRADOU" = "degradou" ]; then
  echo "✓ Hook capturou exceção e degradou (correto)"
else
  echo "❌ Hook não degradou corretamente"
  exit 1
fi

# 5. Testar que abrirBanco() com arquivo VÁLIDO continua funcionando
echo "[5] Testar que abrirBanco() funciona com banco válido..."
FUNCIONOU=$(node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');

try {
  const db = abrirBanco('$DB_VALIDO');
  // Lê algo para garantir que funciona
  const resultado = db.prepare('SELECT COUNT(*) as cnt FROM teste').all();
  console.log('sim');
  db.close();
  process.exit(0);
} catch (e) {
  console.log('nao');
  process.exit(1);
}
")

if [ "$FUNCIONOU" = "sim" ]; then
  echo "✓ abrirBanco() funciona com banco válido (correto)"
else
  echo "❌ abrirBanco() falhou com banco válido"
  exit 1
fi

# 6. Testar que o erro capturado tem mensagem útil
echo "[6] Testar mensagem de erro..."
MENSAGEM=$(node -e "
const { abrirBanco } = require('./scripts/memoria.cjs');

try {
  const db = abrirBanco('$DB_CORROMPIDO');
} catch (e) {
  console.log(e.message);
}
")

if [[ "$MENSAGEM" == *"node:sqlite"* ]]; then
  echo "✓ Mensagem de erro inclui detalhes (correto)"
else
  echo "⚠ Mensagem de erro pode ser melhorada"
fi

# ---------------------------------------------------------------------------
# Checks 7 a 10: os QUATRO pontos de entrada reais, com banco corrompido.
#
# Duas coisas que a versão anterior deste bloco errava, e que juntas o tornavam
# decorativo (achado da 6ª revisão):
#
# 1. O banco corrompido morava em `rainforest-corrompido.db`, e todos os quatro
#    resolvem `$RFM_ROOT/rainforest.db`. Eles caíam no ramo "banco ausente" —
#    medido: o hook CRIAVA um rainforest.db novo de 90 KB e saía 0, sem nunca
#    ter visto o arquivo corrompido. Por isso o nome exato importa aqui.
# 2. Todo ramo de falha era um `echo "⚠"`, e a última linha era `exit 0`
#    incondicional: a bateria não tinha como reprovar. Agora conta falhas.
#
# EFICÁCIA MEDIDA (2026-08-19), para ninguém confiar nisto pelo motivo errado:
# o `memoria-marca.cjs` tem DUAS camadas de degradação — o catch da abertura do
# banco e o catch global do fim do arquivo, ambos saindo 0. Removendo só uma
# delas numa cópia, esta bateria fica VERDE, e com razão: o hook continua
# degradando, que é o comportamento que o plano exige. Removendo as duas, ela
# fica VERMELHA (`❌ 1 falha(s)`, exit 1). Ou seja: ela protege a garantia
# ("hook não quebra a sessão"), não uma implementação específica dela.
# ---------------------------------------------------------------------------
falhou=0
DB_ALVO="$TEMP_DIR/rainforest.db"
rm -f "$DB_ALVO" "$DB_ALVO-wal" "$DB_ALVO-shm"
printf '\x00\x01\x02 isto nao e um banco sqlite' > "$DB_ALVO"

# Guarda: se o arquivo deixar de ser ilegível, os quatro checks abaixo passam a
# medir um banco válido e viram teatro. Melhor a bateria morrer aqui.
if node -e 'const d = new (require("node:sqlite").DatabaseSync)(process.argv[1]); d.exec("PRAGMA journal_mode = WAL"); d.close();' "$DB_ALVO" >/dev/null 2>&1; then
  echo "  FALHA o arquivo plantado abriu como banco válido — os checks 7-10 não mediriam corrupção"
  exit 1
fi

echo "[7] SessionStart hook com banco corrompido..."
SESSION_CODE=0
SESSION_RESULT=$(echo '{}' | RFM_ROOT="$TEMP_DIR" timeout 30 node "$RAIZ/hooks/memoria-session-start.cjs" 2>&1) || SESSION_CODE=$?
if [ "$SESSION_CODE" = "0" ] && [[ "$SESSION_RESULT" == *"additionalContext"* ]]; then
  echo "  ok   SessionStart degradou: exit 0 e additionalContext emitido"
else
  falhou=$((falhou+1))
  echo "  FALHA SessionStart: exit $SESSION_CODE, saida: $(echo "$SESSION_RESULT" | head -2)"
fi

echo "[8] memoria-marca.cjs (modo normal) com banco corrompido..."
# O transcrito existe só para o payload ser o mesmo que o harness manda. Ele NÃO
# é o que leva o hook até o banco: `resolverTranscrito` (memoria-marca.cjs:57)
# devolve `evento.transcript_path` sem checar `existsSync`, e medindo com o hook
# mutado o resultado é idêntico nos dois casos (exit 1, alcançando `abrirBanco`)
# com o arquivo presente ou ausente. Uma versão anterior deste comentário dizia
# o contrário — a causa do check ficar verde era outra, e está logo acima.
printf '%s\n' '{"type":"user","message":{"role":"user","content":"oi"}}' > "$TEMP_DIR/teste.jsonl"
EVENTO_MARCA='{"session_id":"teste-degradacao","transcript_path":"'"$TEMP_DIR"'/teste.jsonl","cwd":"'"$TEMP_DIR"'"}'
MARCA_NORMAL_CODE=0
echo "$EVENTO_MARCA" | RFM_ROOT="$TEMP_DIR" timeout 30 node "$RAIZ/hooks/memoria-marca.cjs" >/dev/null 2>&1 || MARCA_NORMAL_CODE=$?
if [ "$MARCA_NORMAL_CODE" = "0" ]; then
  echo "  ok   memoria-marca.cjs (normal) degradou: exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA memoria-marca.cjs (normal): exit $MARCA_NORMAL_CODE"
fi

echo "[9] memoria-marca.cjs --recover com banco corrompido..."
MARCA_RECOVER_CODE=0
echo '{}' | RFM_ROOT="$TEMP_DIR" timeout 30 node "$RAIZ/hooks/memoria-marca.cjs" --recover >/dev/null 2>&1 || MARCA_RECOVER_CODE=$?
if [ "$MARCA_RECOVER_CODE" = "0" ]; then
  echo "  ok   memoria-marca.cjs --recover degradou: exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA memoria-marca.cjs --recover: exit $MARCA_RECOVER_CODE"
fi

echo "[10] observar.cjs sem argumentos com banco corrompido..."
OBSERVAR_CODE=0
RFM_ROOT="$TEMP_DIR" timeout 30 node "$RAIZ/scripts/observar.cjs" >/dev/null 2>&1 </dev/null || OBSERVAR_CODE=$?
if [ "$OBSERVAR_CODE" = "0" ]; then
  echo "  ok   observar.cjs (sem argumentos, o modo do hooks.json) degradou: exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA observar.cjs sem argumentos: exit $OBSERVAR_CODE"
fi

# O banco corrompido continua no lugar: se algum dos quatro tiver criado um
# banco novo por cima, é porque não viu a corrupção — e o check acima mediu
# outra coisa.
if node -e 'const d = new (require("node:sqlite").DatabaseSync)(process.argv[1]); d.exec("PRAGMA journal_mode = WAL"); d.close();' "$DB_ALVO" >/dev/null 2>&1; then
  falhou=$((falhou+1))
  echo "  FALHA algum dos quatro substituiu o banco corrompido por um válido — os checks 7-10 nao mediram corrupcao"
fi

if [ "$falhou" -ne 0 ]; then
  echo ""
  echo "❌ Tarefa 21/23: $falhou falha(s) na degradação com banco corrompido"
  exit 1
fi

echo "✅ Tarefa 21/23 PASSOU: banco corrompido degrada graciosamente em todos os 4 arquivos"
exit 0
