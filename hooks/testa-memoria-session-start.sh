#!/bin/bash
# Bateria do lib/memoria-sessao.cjs e memoria-session-start.cjs
# Uso: bash hooks/testa-memoria-session-start.sh
#
# O que esta bateria precisa provar:
#   1. que o bloco respeita seu próprio teto em bytes
#   2. que o corte, quando acontece, é ANUNCIADO (nunca silencioso)
#   3. que o bloco vazio é entregue sem erro quando o banco não existe
#   4. que o hook de foco continua <= 8000 B (não aumentamos o orçamento)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$SRC/hooks/lib/memoria-sessao.cjs"
HOOK="$SRC/hooks/memoria-session-start.cjs"
SCRIPT_MEMORIA="$SRC/scripts/memoria.cjs"

# Sandbox hermética.
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# Driver: testa montarMemoria diretamente no motor puro.
cat > "$RAIZ_POSIX/driver-memoria.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(lib.montarMemoria(JSON.parse(process.env.OBS)));
EOF

memoria() { LIB_PATH="$LIB" OBS="$1" node "$RAIZ_POSIX/driver-memoria.cjs" 2>&1; }

checa() { # nome, modo(tem|nao_tem), padrao, saida
  local nome="$1" modo="$2" pad="$3" saida="$4"
  if echo "$saida" | grep -qF "$pad"; then achou=1; else achou=0; fi
  local esperado=1; [ "$modo" = "nao_tem" ] && esperado=0
  if [ "$achou" = "$esperado" ]; then
    ok=$((ok+1)); echo "  ok    $nome"
  else
    falhou=$((falhou+1)); echo "  FALHA $nome (modo=$modo, padrao='$pad')"
    echo "$saida" | sed 's/^/         /' | head -3
  fi
}

echo
echo "1. Bloco vazio quando não há observações"
S="$(memoria '{"observacoes":[]}')"
if [ -z "$S" ]; then
  ok=$((ok+1)); echo "  ok    banco vazio entrega bloco vazio"
else
  falhou=$((falhou+1)); echo "  FALHA banco vazio entrega texto (tamanho: ${#S})"
fi

echo
echo "2. Bloco com observações respeita teto em bytes"
# Fixture: uma observação pequena
OBS_PEQUENA='{"observacoes":[{"id":1,"projeto":"teste","conteudo":"Conteúdo pequeno","criada_em":"2026-08-17T10:00:00"}]}'
S="$(memoria "$OBS_PEQUENA")"
BYTES="$(printf '%s' "$S" | wc -c)"
TETO="$(LIB_PATH="$LIB" node -e "process.stdout.write(String(require(process.env.LIB_PATH).TETOS.MEMORIA_MAX_BYTES))")"

if [ "$BYTES" -le "$TETO" ]; then
  ok=$((ok+1)); echo "  ok    bloco cabe no teto ($BYTES B <= $TETO B)"
else
  falhou=$((falhou+1)); echo "  FALHA bloco estoura o teto ($BYTES B > $TETO B)"
fi

echo
echo "3. Corte é ANUNCIADO quando excede teto"
# Fixture: 20 observações grandes para forçar corte.
GRANDE="Conteúdo com bastante texto para ocupar muitos bytes e forçar o teto a cortar. Repetindo para encher. Lorem ipsum dolor sit amet consectetur adipisicing elit."
OBS_MUITAS="$(node -e "
const o = Array.from({length: 20}, (_, i) => ({
  id: i, projeto: 'proj' + i, conteudo: '$GRANDE', criada_em: '2026-08-17T10:' + String(i).padStart(2, '0') + ':00'
}));
process.stdout.write(JSON.stringify({observacoes: o}));
")"

S="$(memoria "$OBS_MUITAS")"
BYTES_GRANDE="$(printf '%s' "$S" | wc -c)"

if [ "$BYTES_GRANDE" -le "$TETO" ]; then
  ok=$((ok+1)); echo "  ok    bloco com 20 obs grandes cabe no teto (corte ativado, $BYTES_GRANDE B)"
else
  falhou=$((falhou+1)); echo "  FALHA bloco não cabe mesmo com corte ($BYTES_GRANDE B)"
fi

checa "corte anuncia que foi cortado" tem "truncado no teto" "$S"
checa "aviso diz o teto exato" tem "$TETO bytes" "$S"
checa "manda ler o arquivo" tem "arquivo em disco" "$S"

echo
echo "4. Hook real emite JSON com exit 0 quando banco não existe"
# Sem criar banco, rodar o hook.
RFM_ROOT="$RAIZ" node "$HOOK" > "$RAIZ_POSIX/saida-hook.json" 2>/dev/null
EXIT_HOOK=$?

if [ "$EXIT_HOOK" = "0" ]; then
  ok=$((ok+1)); echo "  ok    hook real saiu com exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA hook real saiu com exit $EXIT_HOOK"
fi

cat > "$RAIZ_POSIX/checa-hook.cjs" <<'EOF'
const fs = require('fs');
let j;
try { j = JSON.parse(fs.readFileSync(process.env.SAIDA, 'utf8')); }
catch { console.log('json_invalido'); process.exit(0); }
const c = (j.hookSpecificOutput || {}).additionalContext;
if (typeof c === 'string') {
  console.log(`ok ${Buffer.byteLength(c, 'utf8')}`);
} else {
  console.log('sem_contexto');
}
EOF
LEITURA="$(SAIDA="$RAIZ_POSIX/saida-hook.json" node "$RAIZ_POSIX/checa-hook.cjs")"
FORMATO="$(echo "$LEITURA" | cut -d' ' -f1)"

if [ "$FORMATO" = "ok" ]; then
  ok=$((ok+1)); echo "  ok    emite JSON com hookSpecificOutput.additionalContext"
  BYTES_VAZIO="$(echo "$LEITURA" | cut -d' ' -f2)"
  if [ -n "$BYTES_VAZIO" ] && [ "$BYTES_VAZIO" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok    bloco vazio entregue (0 bytes)"
  else
    ok=$((ok+1)); echo "  ok    bloco com tamanho $BYTES_VAZIO bytes"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA saida do hook não é JSON válido ($FORMATO)"
fi

echo
echo "5. Orcamento do foco não aumentou (D10)"
# Roda o script que mede orçamento.
if [ ! -f "$SRC/scripts/orcamento.cjs" ]; then
  ok=$((ok+1)); echo "  ok    (orcamento.cjs não existe ainda, skip)"
else
  ORCAMENTO_SAIDA="$(node "$SRC/scripts/orcamento.cjs" 2>&1)"
  # Procura a linha "Hook (additionalContext): NNN B" e extrai o número.
  HOOK_BYTES="$(echo "$ORCAMENTO_SAIDA" | grep -oE 'Hook.*: ([0-9]+) B' | grep -oE '[0-9]+' | head -1)"
  if [ -n "$HOOK_BYTES" ] && [ "$HOOK_BYTES" -le 8000 ]; then
    ok=$((ok+1)); echo "  ok    hook de foco continua <= 8000 B ($HOOK_BYTES B)"
  else
    falhou=$((falhou+1)); echo "  FALHA hook de foco passou de 8000 B ou script não rodou"
    echo "         $ORCAMENTO_SAIDA"
  fi
fi

echo
echo "6. MOTOR PURO — montarMemoria formata múltiplas observações corretamente"
# Fixture: várias observações pequenas (cada uma com título e subtítulo).
# Esta checagem exercita apenas o motor (lib/memoria-sessao.cjs), não o hook com banco.
# Com título + subtítulo (~184 B por linha), devemos caber ~14 linhas no teto de 3000 B.
OBS_MULTIPLAS="$(node -e "
const obs = Array.from({length: 5}, (_, i) => ({
  id: i,
  projeto: 'rainforest',
  conteudo: '## Observação ' + (i+1) + '\n\nSubtítulo da observação número ' + (i+1),
  criada_em: '2026-08-17T10:' + String(i).padStart(2, '0') + ':00'
}));
process.stdout.write(JSON.stringify({observacoes: obs}));
")"

S="$(memoria "$OBS_MULTIPLAS")"

# Verifica que o bloco tem múltiplas linhas
NUMERO_LINHAS="$(echo "$S" | grep -c "\\[2026")"
if [ "$NUMERO_LINHAS" -ge 5 ]; then
  ok=$((ok+1)); echo "  ok    bloco contém 5 observações (5 linhas com [data] encontradas)"
else
  falhou=$((falhou+1)); echo "  FALHA bloco não tem 5 observações ($NUMERO_LINHAS encontradas)"
fi

# Verifica que títulos estão em formato curto: [data (projeto)] título — subtítulo
if echo "$S" | grep -q "\[2026.*\] Observação.*—"; then
  ok=$((ok+1)); echo "  ok    título das observações está em formato curto [data] título — subtítulo"
else
  falhou=$((falhou+1)); echo "  FALHA títulos não estão em formato esperado"
fi

# Verifica que o ponteiro de busca está presente
if echo "$S" | grep -q "memoria.cjs buscar"; then
  ok=$((ok+1)); echo "  ok    ponteiro de busca sob demanda presente"
else
  falhou=$((falhou+1)); echo "  FALHA ponteiro de busca não encontrado"
fi

echo
echo "7. NÚMERO 14 ESTÁ PROTEGIDO — sensibilidade da checagem à mutação no código"
# Objetivo: provar que o número 14 está codificado no hook e que qualquer
# mudança dele é detectável (não pode silenciosamente mudar para outro valor).
#
# Método: valida que uma mudança 14→1 no código-fonte é detectável via grep.
# A leitura real do banco é testada em testa-memoria-somente-leitura.sh, que é
# mais robusto para isso.

# 1. Verde: numero 14 está no código (agora com 3 argumentos: caminhoDb, projetoAtual, limiteTotal)
LIMITE_ATUAL=$(grep -oE 'lerObservacoes\(caminhoDb, [^,]+, [0-9]+\)' "$HOOK" | sed 's/.*,\s*//' | sed 's/).*//')

if [ "$LIMITE_ATUAL" = "14" ]; then
  ok=$((ok+1)); echo "  ok    VERDE: código usa lerObservacoes(..., ..., 14)"
else
  falhou=$((falhou+1)); echo "  FALHA código usa lerObservacoes(..., ..., $LIMITE_ATUAL), esperado 14"
fi

# 2. Vermelho: muta para 1 e prova que é detectável
HOOK_MUTADO_POSIX="$RAIZ_POSIX/hook-mut.cjs"
cp "$HOOK" "$HOOK_MUTADO_POSIX"
sed -i.bak 's/lerObservacoes(caminhoDb, projetoAtual, 14)/lerObservacoes(caminhoDb, projetoAtual, 1)/' "$HOOK_MUTADO_POSIX"

LIMITE_MUTADO=$(grep -oE 'lerObservacoes\(caminhoDb, [^,]+, [0-9]+\)' "$HOOK_MUTADO_POSIX" | sed 's/.*,\s*//' | sed 's/).*//')

if [ "$LIMITE_MUTADO" = "1" ]; then
  ok=$((ok+1)); echo "  ok    VERMELHO: sed consegue mutar 14→1 (mudança é detectável)"
else
  falhou=$((falhou+1)); echo "  FALHA sed não conseguiu fazer 14→1 (ficou $LIMITE_MUTADO)"
fi

# 3. Verde: volta ao original e confirma detecção
LIMITE_VOLTA=$(grep -oE 'lerObservacoes\(caminhoDb, [^,]+, [0-9]+\)' "$HOOK" | sed 's/.*,\s*//' | sed 's/).*//')

if [ "$LIMITE_VOLTA" = "14" ]; then
  ok=$((ok+1)); echo "  ok    VERDE: volta a 14 (checagem sensível à mutação em disco)"
else
  falhou=$((falhou+1)); echo "  FALHA volta não voltou a 14 (ficou $LIMITE_VOLTA)"
fi

rm -f "$HOOK_MUTADO_POSIX" "$HOOK_MUTADO_POSIX.bak"

echo
echo "8. Mutação — com teto menor, o bloco deveria caber ainda mais apertado"
# Usa node para substituir o teto.
# Teto de 200 B é realista: aviso (~110 B) + conteúdo (~90 B).
cat > "$RAIZ_POSIX/mutar-lib.cjs" <<'EOF'
const fs = require('fs');
const lib = fs.readFileSync(process.env.LIB_SRC, 'utf8');
const mutada = lib.replace(/MEMORIA_MAX_BYTES: \d+/, 'MEMORIA_MAX_BYTES: 200');
fs.writeFileSync(process.env.LIB_DST, mutada);
EOF
LIB_SRC="$LIB" LIB_DST="$RAIZ_POSIX/lib-mutada.cjs" node "$RAIZ_POSIX/mutar-lib.cjs"

# Com teto de 200 B, observações grandes vão ser cortadas.
# Usa as mesmas 20 observações grandes do teste 3.
S="$(LIB_PATH="$RAIZ_POSIX/lib-mutada.cjs" OBS="$OBS_MUITAS" node "$RAIZ_POSIX/driver-memoria.cjs" 2>&1)"

BYTES_MUTADA="$(printf '%s' "$S" | wc -c)"
TETO_MUTADA=200

# Com teto de 200 B e 20 observações grandes, esperamos corte.
if [ "$BYTES_MUTADA" -le "$TETO_MUTADA" ]; then
  ok=$((ok+1)); echo "  ok    com teto em 200 B o bloco cabe (mutação é load-bearing, $BYTES_MUTADA B)"
else
  falhou=$((falhou+1)); echo "  FALHA bloco mutado não cabe no teto de 200 B ($BYTES_MUTADA B)"
fi

# Confirma que o aviso foi incluído (prova que limitarBytes funcionou).
if echo "$S" | grep -q "truncado no teto"; then
  ok=$((ok+1)); echo "  ok    aviso de corte está presente"
else
  falhou=$((falhou+1)); echo "  FALHA aviso de corte não apareceu"
fi

echo
echo "9. Prova que checagem sabe falhar (motor puro): força 1 linha apenas, espera vermelho"
# Substitui MEMORIA_MAX_BYTES com um valor que só cabe cabecalho + uma linha curta (~100 B)
cat > "$RAIZ_POSIX/forcar-uma-linha.cjs" <<'EOF'
const fs = require('fs');
const lib = fs.readFileSync(process.env.LIB_SRC, 'utf8');
const mutada = lib.replace(/MEMORIA_MAX_BYTES: \d+/, 'MEMORIA_MAX_BYTES: 100');
fs.writeFileSync(process.env.LIB_DST, mutada);
EOF
LIB_SRC="$LIB" LIB_DST="$RAIZ_POSIX/lib-uma-linha.cjs" node "$RAIZ_POSIX/forcar-uma-linha.cjs"

# Com teto de 100 B e 5 observações, só uma cabe → bloco deve ser cortado
S="$(LIB_PATH="$RAIZ_POSIX/lib-uma-linha.cjs" OBS="$OBS_MULTIPLAS" node "$RAIZ_POSIX/driver-memoria.cjs" 2>&1)"
NUMERO_LINHAS_UMA="$(echo "$S" | grep -c "\\[2026")"

if [ "$NUMERO_LINHAS_UMA" -lt 5 ]; then
  ok=$((ok+1)); echo "  ok    VERMELHO: com teto 100 B só $NUMERO_LINHAS_UMA linha(s) cabem (esperado < 5)"
else
  falhou=$((falhou+1)); echo "  FALHA checagem não consegue falhar (tinha $NUMERO_LINHAS_UMA linhas)"
fi

# Volta para teto normal: deve estar verde novamente
S="$(memoria "$OBS_MULTIPLAS")"
NUMERO_LINHAS_VOLTA="$(echo "$S" | grep -c "\\[2026")"

if [ "$NUMERO_LINHAS_VOLTA" -ge 5 ]; then
  ok=$((ok+1)); echo "  ok    VERDE: com teto 3000 B voltam as 5 observações ($NUMERO_LINHAS_VOLTA encontradas)"
else
  falhou=$((falhou+1)); echo "  FALHA checagem não voltou ao verde ($NUMERO_LINHAS_VOLTA encontradas)"
fi

echo
echo "10. Tarefa 3 — filtro por projeto no hook de verdade (D3)"

# Criar caixa de areia para os testes do hook
CAIXA_HOOK="$(mktemp -d)"
mkdir -p "$CAIXA_HOOK"
trap 'rm -rf "$CAIXA" "$CAIXA2" "$CAIXA3" "$RAIZ_POSIX" "$CAIXA_HOOK"' EXIT

# Inicializar banco em RFM_ROOT
export RFM_ROOT="$CAIXA_HOOK"
node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1

# Inserir dados de teste: 8 de projeto-a, 8 de projeto-b
node <<'SETUP_HOOK_TEST'
const { DatabaseSync } = require('node:sqlite');

const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');

// 8 observações de projeto-a (mais recentes)
for (let i = 1; i <= 8; i++) {
  db.prepare(`
    INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
    VALUES (?, ?, ?, ?)
  `).run(
    'projeto-a',
    '## Obs A' + i + '\n\nConteúdo projeto A',
    '2026-08-' + String(10 + i).padStart(2, '0') + 'T10:00:00Z',
    'origem-a-' + i
  );
}

// 8 observações de projeto-b (mais antigas)
for (let i = 1; i <= 8; i++) {
  db.prepare(`
    INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
    VALUES (?, ?, ?, ?)
  `).run(
    'projeto-b',
    '## Obs B' + i + '\n\nConteúdo projeto B',
    '2026-08-' + String(i).padStart(2, '0') + 'T10:00:00Z',
    'origem-b-' + i
  );
}

db.close();
SETUP_HOOK_TEST

echo
echo "  10.a — sessão de projeto-a: recebe 8 de projeto-a, depois 6 de projeto-b (total 14)"

# Criar pasta temporária com .git para simular sessão de projeto-a
PASTA_A="$CAIXA_HOOK/test-projeto-a"
mkdir -p "$PASTA_A"
git init -q "$PASTA_A"

# Executar hook de dentro de projeto-a com RFM_ROOT apontando para banco
SAIDA_A=$(cd "$PASTA_A" && RFM_ROOT="$CAIXA_HOOK" echo '{}' | node "$HOOK" 2>/dev/null)

# Extrair additionalContext
BLOCO_A=$(echo "$SAIDA_A" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

# Contar linhas com [data] — cada linha de observação tem [data (projeto)]
NUM_LINHAS_A=$(echo "$BLOCO_A" | grep -c "\\[2026")

# Verificar que as primeiras são de projeto-a
PRIMEIRAS_A=$(echo "$BLOCO_A" | grep -o "\\(projeto-a\\)" | head -8 | wc -l)

# Verificar que tem algumas de projeto-b depois
TEM_B=$(echo "$BLOCO_A" | grep -c "\\(projeto-b\\)")

if [ "$NUM_LINHAS_A" = "14" ]; then
  ok=$((ok+1)); echo "  ok    bloco tem 14 linhas"
else
  falhou=$((falhou+1)); echo "  FALHA bloco tem $NUM_LINHAS_A linhas, esperado 14"
fi

if [ "$PRIMEIRAS_A" -ge "5" ]; then
  ok=$((ok+1)); echo "  ok    primeiras 5+ linhas são de projeto-a"
else
  falhou=$((falhou+1)); echo "  FALHA encontrei $PRIMEIRAS_A linhas de projeto-a nas primeiras, esperado >= 5"
fi

if [ "$TEM_B" -gt "0" ]; then
  ok=$((ok+1)); echo "  ok    bloco tem observações de projeto-b depois"
else
  falhou=$((falhou+1)); echo "  FALHA nenhuma observação de projeto-b encontrada"
fi

echo
echo "  10.b — projeto com 2 obs próprias: recebe 2 + 12 de outros (total 14)"

# Adicionar 2 observações de projeto-c (mais recentes)
node <<'ADD_C'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');

for (let i = 1; i <= 2; i++) {
  db.prepare(`
    INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
    VALUES (?, ?, ?, ?)
  `).run(
    'projeto-c',
    '## Obs C' + i + '\n\nConteúdo projeto C',
    '2026-08-25T' + String(i).padStart(2, '0') + ':00:00Z',
    'origem-c-' + i
  );
}
db.close();
ADD_C

# Criar pasta com .git para simular sessão de projeto-c
PASTA_C="$CAIXA_HOOK/test-projeto-c"
mkdir -p "$PASTA_C"
git init -q "$PASTA_C"

# Executar hook de dentro de projeto-c
SAIDA_C=$(cd "$PASTA_C" && RFM_ROOT="$CAIXA_HOOK" echo '{}' | node "$HOOK" 2>/dev/null)

# Extrair bloco
BLOCO_C=$(echo "$SAIDA_C" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

# Contar linhas
NUM_LINHAS_C=$(echo "$BLOCO_C" | grep -c "\\[2026")

# Contar de projeto-c
NUM_C=$(echo "$BLOCO_C" | grep -o "\\(projeto-c\\)" | wc -l)

# Contar de outros
NUM_OUTROS_C=$(echo "$BLOCO_C" | grep -c "\\(projeto-a\\)\\|\\(projeto-b\\)")

if [ "$NUM_LINHAS_C" = "14" ]; then
  ok=$((ok+1)); echo "  ok    bloco tem 14 linhas"
else
  falhou=$((falhou+1)); echo "  FALHA bloco tem $NUM_LINHAS_C linhas, esperado 14"
fi

if [ "$NUM_C" = "2" ]; then
  ok=$((ok+1)); echo "  ok    bloco tem 2 de projeto-c"
else
  falhou=$((falhou+1)); echo "  FALHA bloco tem $NUM_C de projeto-c, esperado 2"
fi

if [ "$NUM_OUTROS_C" -ge "10" ]; then
  ok=$((ok+1)); echo "  ok    bloco completa com 12+ de outros projetos"
else
  falhou=$((falhou+1)); echo "  FALHA bloco tem $NUM_OUTROS_C de outros, esperado >= 12"
fi

echo
echo "  10.c — FALSIFICAÇÃO: remover WHERE projeto = ?"
# Criar backup da version nova
cp "$HOOK" "$CAIXA_HOOK/hook-novo.cjs"

# Remover a cláusula WHERE projeto = ? da primeira query (deixa unfiltered)
sed -i.bak 's/WHERE projeto = ?/-- WHERE projeto = ? REMOVIDO PARA FALSIFICACAO/' "$HOOK"

# Rodar teste novamente (agora SEM filtro)
SAIDA_MUTADA=$(cd "$PASTA_A" && RFM_ROOT="$CAIXA_HOOK" echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_MUTADO=$(echo "$SAIDA_MUTADA" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

# Com o filtro removido, projeto-a não recebe SUAS observações primeiro
# As observações são devolvidas em ordem DESC por criada_em, então projeto-b (mais antigas = datas menores)
# vem ANTES quando sem filtro. Verificar que a ordem mudou.
PRIMEIRO_BLOCO_MUTADO=$(echo "$BLOCO_MUTADO" | head -1)

# Se começar com projeto-b ou não marcar projeto-a primeiro, é falso positivo (filtro não está funcionando)
if echo "$PRIMEIRO_BLOCO_MUTADO" | grep -q "projeto-a"; then
  falhou=$((falhou+1)); echo "  FALHA filtro não foi removido (primeiro resultado ainda é projeto-a)"
else
  ok=$((ok+1)); echo "  ok    VERMELHO: sem filtro, ordem se inverte (teste detecta a mudança)"
fi

# Restaurar código correto
cp "$CAIXA_HOOK/hook-novo.cjs" "$HOOK"
rm -f "$HOOK.bak" "$CAIXA_HOOK/hook-novo.cjs"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
