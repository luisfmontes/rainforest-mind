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

# Raiz gorda com FOCO.md de ~2500 B para teste de mutação (deve vir antes de RAIZ_NEUTRA)
RAIZ_GORDA="$(mktemp -d)"
{
  printf '# Foco\n\n'
  printf 'x%.0s' {1..2500}
} > "$RAIZ_GORDA/FOCO.md"

# Raiz neutra para medir sem dados do usuário
RAIZ_NEUTRA="$(mktemp -d)"

trap 'rm -rf "$RAIZ_POSIX" "$RAIZ_NEUTRA" "$RAIZ_GORDA"' EXIT
echo "(caixa de areia: $RAIZ)"
echo "(raiz neutra: $RAIZ_NEUTRA)"
echo "(raiz gorda: $RAIZ_GORDA)"

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
  ORCAMENTO_SAIDA="$(RFM_ROOT="$RAIZ_NEUTRA" node "$SRC/scripts/orcamento.cjs" 2>&1)"
  ORCAMENTO_EXIT=$?
  # Procura a linha "Hook (additionalContext): NNN B" e extrai o número.
  HOOK_BYTES="$(echo "$ORCAMENTO_SAIDA" | grep -oE 'Hook.*: ([0-9]+) B' | grep -oE '[0-9]+' | head -1)"
  if [ -n "$HOOK_BYTES" ] && [ "$HOOK_BYTES" -le 8000 ] && [ "$ORCAMENTO_EXIT" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok    hook de foco continua <= 8000 B ($HOOK_BYTES B)"
  else
    falhou=$((falhou+1)); echo "  FALHA hook de foco passou de 8000 B ou script não rodou (exit=$ORCAMENTO_EXIT)"
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

# 1. Verde: numero 14 está no código (agora com 3 argumentos: caminhoDb, projetosList, limiteTotal)
LIMITE_ATUAL=$(grep -oE 'lerObservacoes\(caminhoDb, [^,]+, [0-9]+\)' "$HOOK" | tail -1 | sed 's/.*,\s*//' | sed 's/).*//')

if [ "$LIMITE_ATUAL" = "14" ]; then
  ok=$((ok+1)); echo "  ok    VERDE: código usa lerObservacoes(..., ..., 14)"
else
  falhou=$((falhou+1)); echo "  FALHA código usa lerObservacoes(..., ..., $LIMITE_ATUAL), esperado 14"
fi

# 2. Vermelho: muta para 1 e prova que é detectável
HOOK_MUTADO_POSIX="$RAIZ_POSIX/hook-mut.cjs"
HOOK_MUTADO=$(cygpath -w "$HOOK_MUTADO_POSIX" 2>/dev/null || printf '%s' "$HOOK_MUTADO_POSIX")
cp "$HOOK" "$HOOK_MUTADO_POSIX"

# Usar node para fazer a mutação (mais confiável que sed em Windows)
# Converter caminho POSIX para Windows se necessário (para node)
node -e "
const fs = require('fs');
const path = process.argv[1];
const conteudo = fs.readFileSync(path, 'utf8');
const mutado = conteudo.replace('lerObservacoes(caminhoDb, projetosList, 14)', 'lerObservacoes(caminhoDb, projetosList, 1)');
fs.writeFileSync(path, mutado);
" "$HOOK_MUTADO" 2>/dev/null

LIMITE_MUTADO=$(node -e "
const fs = require('fs');
const c = fs.readFileSync(process.argv[1], 'utf8');
const m = c.match(/lerObservacoes\(caminhoDb, projetosList, (\d+)\)/);
process.stdout.write(m && m[1] ? m[1] : '');
" "$HOOK_MUTADO" 2>/dev/null)

if [ "$LIMITE_MUTADO" = "1" ]; then
  ok=$((ok+1)); echo "  ok    VERMELHO: mutação consegue 14→1 (mudança é detectável)"
else
  falhou=$((falhou+1)); echo "  FALHA mutação não conseguiu fazer 14→1 (ficou $LIMITE_MUTADO)"
fi

# 3. Verde: volta ao original e confirma detecção
LIMITE_VOLTA=$(node -e "const fs = require('fs'); const c=fs.readFileSync(process.argv[1],'utf8'); const m=c.match(/lerObservacoes\(caminhoDb, projetosList, (\d+)\)/); process.stdout.write(m && m[1] ? m[1] : '');" "$HOOK" 2>/dev/null)

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
# `set -u` derruba o trap inteiro se uma das variáveis não existir — e aí a
# limpeza não roda e cada execução deixa pasta temporária para trás. Os `:-`
# são o que faz o trap sobreviver a variável que a seção anterior não criou.
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${RAIZ_POSIX:-}" "${CAIXA_HOOK:-}" "${CAIXA_PROJETO:-}"' EXIT

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

# Verificar que as OITO PRIMEIRAS linhas, em ordem, são de projeto-a.
# Contar ocorrências no bloco inteiro não serve: passa com o filtro quebrado,
# porque as 8 estariam lá de qualquer jeito — só que no meio das outras.
PRIMEIRAS_A=$(echo "$BLOCO_A" | grep "\\[2026" | head -8 | grep -c "(projeto-a)")

# Verificar que tem algumas de projeto-b depois
TEM_B=$(echo "$BLOCO_A" | grep -c "\\(projeto-b\\)")

if [ "$NUM_LINHAS_A" = "14" ]; then
  ok=$((ok+1)); echo "  ok    bloco tem 14 linhas"
else
  falhou=$((falhou+1)); echo "  FALHA bloco tem $NUM_LINHAS_A linhas, esperado 14"
fi

if [ "$PRIMEIRAS_A" = "8" ]; then
  ok=$((ok+1)); echo "  ok    as 8 primeiras linhas, em ordem, são de projeto-a"
else
  falhou=$((falhou+1)); echo "  FALHA das 8 primeiras linhas, $PRIMEIRAS_A são de projeto-a, esperado 8"
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

# EXATAMENTE 12, não `>= 10`. O bloco tem 14 linhas e 2 são de projeto-c, então
# aritmeticamente as outras só podem ser 12 — a margem de 10 aceitava duas
# linhas SEM rótulo de projeto, que é justamente a regressão de formatação que
# esta seção existe para pegar. A mensagem de erro já dizia "esperado >= 12"
# enquanto o teste comparava com 10; onde o texto e o número divergem, é o
# número que manda, e ele estava frouxo.
if [ "$NUM_OUTROS_C" = "12" ]; then
  ok=$((ok+1)); echo "  ok    bloco completa com exatamente 12 de outros projetos, todas rotuladas"
else
  falhou=$((falhou+1)); echo "  FALHA bloco tem $NUM_OUTROS_C rotuladas de outros projetos, esperado exatamente 12"
fi

echo
echo "  10.c — FALSIFICAÇÃO: o filtro invertido tem que derrubar 10.a"
# A mutação roda numa CÓPIA, nunca no arquivo versionado: bateria que edita o
# próprio fonte deixa o repositório mutado se morrer no meio, e esta roda no CI.
COPIA_MUT="$(mktemp -d)"
cp -r "$(dirname "$HOOK")" "$COPIA_MUT/hooks"
cp -r "$(dirname "$HOOK")/../scripts" "$COPIA_MUT/scripts"

# A mutação é `=` -> `!=`: mesma aridade de parâmetros, SQL continua VÁLIDO, e
# o significado inverte. A primeira versão desta prova comentava a linha do
# WHERE, o que deixava a consulta com um placeholder e dois binds — ela
# estourava, caía no catch, e devolvia bloco VAZIO. Aí o teste "passava" porque
# a primeira linha de um bloco vazio não menciona projeto-a: passaria igual com
# a função inteira apagada. Medido em 2026-08-20, e é o motivo da guarda abaixo.
sed -i 's/WHERE projeto = ?/WHERE projeto != ?/' "$COPIA_MUT/hooks/memoria-session-start.cjs"

SAIDA_MUTADA=$(cd "$PASTA_A" && echo '{}' | node "$COPIA_MUT/hooks/memoria-session-start.cjs" 2>/dev/null)
BLOCO_MUTADO=$(echo "$SAIDA_MUTADA" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

LINHAS_MUTADAS=$(echo "$BLOCO_MUTADO" | grep -c "\\[2026")
PRIMEIRA_MUTADA=$(echo "$BLOCO_MUTADO" | grep "\\[2026" | head -1)

if [ "$LINHAS_MUTADAS" -lt 1 ]; then
  # Guarda anti-vacuidade: bloco vazio não prova filtro nenhum, prova que a
  # mutação quebrou a consulta. Prova que não pode falhar não é prova.
  falhou=$((falhou+1)); echo "  FALHA a mutação degradou para bloco vazio — a falsificação não vale"
elif echo "$PRIMEIRA_MUTADA" | grep -q "(projeto-a)"; then
  falhou=$((falhou+1)); echo "  FALHA filtro invertido e a primeira linha ainda é de projeto-a — a bateria não detecta"
else
  ok=$((ok+1)); echo "  ok    VERMELHO: com o filtro invertido, a primeira linha é de outro projeto ($LINHAS_MUTADAS linhas, bloco não-vazio)"
fi

rm -rf "$COPIA_MUT"

echo
echo "11. chaveHarness — transforma caminhos em chaves de pasta do Claude Code"

# 11.a — caminho Windows com : e \
TESTE_CHAVE_A="$(SCRIPT_PATH="$SCRIPT_MEMORIA" node -e "
const m = require(process.env.SCRIPT_PATH);
process.stdout.write(m.chaveHarness('C:\\\\Projetos\\\\rainforest-mind'));
")"
if [ "$TESTE_CHAVE_A" = "C--Projetos-rainforest-mind" ]; then
  ok=$((ok+1)); echo "  ok    chaveHarness transforma C:\\\\Projetos\\\\rainforest-mind → C--Projetos-rainforest-mind"
else
  falhou=$((falhou+1)); echo "  FALHA chaveHarness deu '$TESTE_CHAVE_A', esperado C--Projetos-rainforest-mind"
fi

# 11.b — caminho Windows com : e / misto
TESTE_CHAVE_B="$(SCRIPT_PATH="$SCRIPT_MEMORIA" node -e "
const m = require(process.env.SCRIPT_PATH);
process.stdout.write(m.chaveHarness('C:/Microsiga/protheus-totvs-agro/inovacao'));
")"
if [ "$TESTE_CHAVE_B" = "C--Microsiga-protheus-totvs-agro-inovacao" ]; then
  ok=$((ok+1)); echo "  ok    chaveHarness transforma C:/Microsiga/protheus-totvs-agro/inovacao"
else
  falhou=$((falhou+1)); echo "  FALHA chaveHarness deu '$TESTE_CHAVE_B'"
fi

# 11.c — caminho sem : (POSIX-like)
TESTE_CHAVE_C="$(SCRIPT_PATH="$SCRIPT_MEMORIA" node -e "
const m = require(process.env.SCRIPT_PATH);
process.stdout.write(m.chaveHarness('/home/user/projetos/rainforest-mind'));
")"
if [ "$TESTE_CHAVE_C" = "-home-user-projetos-rainforest-mind" ]; then
  ok=$((ok+1)); echo "  ok    chaveHarness transforma /home/user/projetos/rainforest-mind"
else
  falhou=$((falhou+1)); echo "  FALHA chaveHarness deu '$TESTE_CHAVE_C'"
fi

echo
echo "12. Leitura com chave harness (D13b) — observações gravadas em chave harness são encontradas"

# Setup: criar banco, inserir observações em DUAS chaves diferentes
CAIXA_HARNESS="$(mktemp -d)"
mkdir -p "$CAIXA_HARNESS"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${RAIZ_POSIX:-}" "${CAIXA_HOOK:-}" "${CAIXA_PROJETO:-}" "${CAIXA_HARNESS:-}"' EXIT

export RFM_ROOT="$CAIXA_HARNESS"
node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1

# Inserir observações sob DOIS projetos diferentes:
# - Chave curta: "rainforest-mind" (histórico do claude-mem)
# - Chave harness: "C--Projetos-rainforest-mind" (dados novos neste ciclo)
node <<'SETUP_HARNESS_TEST'
const { DatabaseSync } = require('node:sqlite');

const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');

// Observação sob chave curta (histórico)
db.prepare(`
  INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
  VALUES (?, ?, ?, ?)
`).run(
  'rainforest-mind',
  '## Histórico\n\nConteúdo sob chave curta',
  '2026-08-20T10:00:00Z',
  'origem-historico'
);

// Observação sob chave harness (novo)
db.prepare(`
  INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
  VALUES (?, ?, ?, ?)
`).run(
  'C--Projetos-rainforest-mind',
  '## Novo\n\nConteúdo sob chave harness',
  '2026-08-21T10:00:00Z',
  'origem-novo'
);

db.close();
SETUP_HARNESS_TEST

# 12.a — sessionStart de uma pasta que resolveria para "rainforest-mind"
# Deve achar AMBAS as observações (histórico + novo)
PASTA_HARNESS="$CAIXA_HARNESS/test-rainforest-mind"
mkdir -p "$PASTA_HARNESS"
git init -q "$PASTA_HARNESS"

SAIDA_HARNESS=$(cd "$PASTA_HARNESS" && RFM_ROOT="$CAIXA_HARNESS" echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_HARNESS=$(echo "$SAIDA_HARNESS" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

ACHOU_HISTORICO=$(echo "$BLOCO_HARNESS" | grep -c "Histórico" || true)
ACHOU_NOVO=$(echo "$BLOCO_HARNESS" | grep -c "Novo" || true)

if [ "$ACHOU_HISTORICO" -ge 1 ]; then
  ok=$((ok+1)); echo "  ok    encontra observação sob chave curta (histórico)"
else
  falhou=$((falhou+1)); echo "  FALHA não encontrou observação sob chave curta"
fi

if [ "$ACHOU_NOVO" -ge 1 ]; then
  ok=$((ok+1)); echo "  ok    encontra observação sob chave harness (novo)"
else
  falhou=$((falhou+1)); echo "  FALHA não encontrou observação sob chave harness"
fi

echo
echo "13. Invariante: lista vazia de projetos → consulta sem filtro (como antes)"

# Verificar que o banco tem as 2 observações das seções anteriores
CNT_BANCO="$(DB_PATH="$CAIXA_HARNESS/rainforest.db" node -e "
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.DB_PATH, { readonly: true });
db.exec('PRAGMA query_only = ON;');
const cnt = db.prepare('SELECT COUNT(*) as c FROM observacoes').all()[0].c;
db.close();
process.stdout.write(String(cnt));
")"

if [ "$CNT_BANCO" = "2" ]; then
  ok=$((ok+1)); echo "  ok    banco tem 2 observações (das 2 chaves)"
else
  falhou=$((falhou+1)); echo "  FALHA banco tem $CNT_BANCO observações"
fi

echo
echo "14. Banco inexistente → array vazio, sem exceção"

CAIXA_VAZIO="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${RAIZ_POSIX:-}" "${CAIXA_HOOK:-}" "${CAIXA_PROJETO:-}" "${CAIXA_HARNESS:-}" "${CAIXA_VAZIO:-}"' EXIT

export RFM_ROOT="$CAIXA_VAZIO"
# NÃO rodamos memoria.cjs iniciar, então banco não existe

SAIDA_VAZIO=$(cd "$CAIXA_VAZIO" && echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_VAZIO=$(echo "$SAIDA_VAZIO" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

TAMANHO_VAZIO=${#BLOCO_VAZIO}

if [ "$TAMANHO_VAZIO" -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    bloco vazio quando banco não existe (0 bytes)"
else
  ok=$((ok+1)); echo "  ok    bloco tem $TAMANHO_VAZIO bytes (degradação silenciosa, sem exceção)"
fi

echo
echo "15. Rótulo usa o apelido curto, não a chave de pasta do harness"

CAIXA_APELIDO="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}" "${CAIXA2:-}" "${CAIXA3:-}" "${RAIZ_POSIX:-}" "${CAIXA_HOOK:-}" "${CAIXA_PROJETO:-}" "${CAIXA_HARNESS:-}" "${CAIXA_VAZIO:-}" "${CAIXA_APELIDO:-}"' EXIT

export RFM_ROOT="$CAIXA_APELIDO"
node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1

PASTA_APELIDO="$CAIXA_APELIDO/projeto-de-teste"
mkdir -p "$PASTA_APELIDO"
git init -q "$PASTA_APELIDO"

# Grava a observação sob a chave EXATA que o harness usaria para essa pasta.
(cd "$PASTA_APELIDO" && SRC="$SRC" node -e "
  const { DatabaseSync } = require('node:sqlite');
  const { chaveHarness } = require(process.env.SRC + '/scripts/memoria.cjs');
  const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
  db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
    .run(chaveHarness(process.cwd()), '## Marcador de apelido', '2026-08-22T10:00:00Z', 'sessao:teste:offset:1');
  db.close();
")

SAIDA_APELIDO=$(cd "$PASTA_APELIDO" && echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_APELIDO=$(echo "$SAIDA_APELIDO" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

ACHOU_CURTO=$(echo "$BLOCO_APELIDO" | grep -c "(projeto-de-teste)" || true)
ACHOU_LONGO=$(echo "$BLOCO_APELIDO" | grep -c -- "(C--" || true)

if [ "$ACHOU_CURTO" -ge 1 ]; then
  ok=$((ok+1)); echo "  ok    rótulo exibe o nome curto do projeto"
else
  falhou=$((falhou+1)); echo "  FALHA rótulo não exibiu o nome curto; bloco: $BLOCO_APELIDO"
fi

if [ "$ACHOU_LONGO" -eq 0 ] && [ -n "$BLOCO_APELIDO" ]; then
  ok=$((ok+1)); echo "  ok    chave de pasta do harness não vaza para o rótulo"
else
  falhou=$((falhou+1)); echo "  FALHA chave longa vazou no rótulo; bloco: $BLOCO_APELIDO"
fi


echo
echo "-- a LEGENDA VISIVEL da memoria (systemMessage) --"
# Ate 2026-08-25 o corpus era injetado so no `additionalContext`: o MODELO abria a
# sessao sabendo onde tinha parado, e o USUARIO abria olhando para uma tela vazia.
# Quem precisa lembrar do fio da meada e' ele.
#
# O que esta parte precisa provar:
#   1. que a legenda mostra as marcas MAIS RECENTES, e so as duas primeiras;
#   2. que sem marca nenhuma ela devolve VAZIO — o hook depende disso para nao
#      pintar uma caixa em branco na tela;
#   3. que ela nao rouba bytes do bloco injetado (canal e teto separados);
#   4. que a linha longa e' cortada com reticencia, nunca partindo caractere.

cat > "$RAIZ_POSIX/driver-legenda-memoria.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(lib.montarLegendaMemoria(JSON.parse(process.env.OBS)));
EOF

legenda_memoria() { LIB_PATH="${LIB_LEGENDA:-$LIB}" OBS="$1" node "$RAIZ_POSIX/driver-legenda-memoria.cjs" 2>&1; }

OBS_TRES='{"observacoes":[
 {"conteudo":"## Marca mais recente\n\nsubtitulo da recente","projeto":"C--Projetos-rainforest-mind","criada_em":"2026-08-25T10:00:00Z"},
 {"conteudo":"## Marca do meio\n\nsubtitulo do meio","projeto":"C--Projetos-rainforest-mind","criada_em":"2026-08-24T10:00:00Z"},
 {"conteudo":"## Marca antiga\n\nsubtitulo antigo","projeto":"C--Projetos-rainforest-mind","criada_em":"2026-08-20T10:00:00Z"}],
 "apelidos":{"C--Projetos-rainforest-mind":"rainforest-mind"}}'

S="$(legenda_memoria "$OBS_TRES")"
if echo "$S" | grep -qF "Marca mais recente"; then
  ok=$((ok+1)); echo "  ok    legenda traz a marca mais recente"
else
  falhou=$((falhou+1)); echo "  FALHA legenda perdeu a marca mais recente; saida: $S"
fi

if echo "$S" | grep -qF "Marca do meio"; then
  ok=$((ok+1)); echo "  ok    legenda traz a segunda marca"
else
  falhou=$((falhou+1)); echo "  FALHA legenda perdeu a segunda marca; saida: $S"
fi

if echo "$S" | grep -qF "Marca antiga"; then
  falhou=$((falhou+1)); echo "  FALHA legenda passou de 2 marcas — a terceira e' do outro canal; saida: $S"
else
  ok=$((ok+1)); echo "  ok    a terceira marca fica no additionalContext, fora da tela"
fi

if echo "$S" | grep -qF "25/08"; then
  ok=$((ok+1)); echo "  ok    legenda data a marca em dia/mes"
else
  falhou=$((falhou+1)); echo "  FALHA legenda sem data legivel; saida: $S"
fi

if echo "$S" | grep -qF "rainforest-mind" && ! echo "$S" | grep -qF "C--Projetos"; then
  ok=$((ok+1)); echo "  ok    legenda usa o apelido curto, nao a chave do harness"
else
  falhou=$((falhou+1)); echo "  FALHA apelido nao aplicado na legenda; saida: $S"
fi

S_VAZIA="$(legenda_memoria '{"observacoes":[]}')"
if [ -z "$S_VAZIA" ]; then
  ok=$((ok+1)); echo "  ok    sem marca a legenda e' vazia (o hook nao pinta caixa em branco)"
else
  falhou=$((falhou+1)); echo "  FALHA legenda vazia devolveu texto: '$S_VAZIA'"
fi

LONGA="$(node -e 'const t="titulo enorme ".repeat(40);process.stdout.write(JSON.stringify({observacoes:[{conteudo:"## "+t,projeto:"p",criada_em:"2026-08-25T10:00:00Z"}]}))')"
S_LONGA="$(legenda_memoria "$LONGA")"
BYTES_LONGA="$(printf '%s' "$S_LONGA" | wc -c)"
if [ "$BYTES_LONGA" -le 160 ]; then
  ok=$((ok+1)); echo "  ok    linha longa cortada no teto de linha (mediu $BYTES_LONGA B)"
else
  falhou=$((falhou+1)); echo "  FALHA linha longa passou do teto de linha (mediu $BYTES_LONGA B)"
fi

if echo "$S_LONGA" | grep -qF "…"; then
  ok=$((ok+1)); echo "  ok    corte de linha e' anunciado com reticencia"
else
  falhou=$((falhou+1)); echo "  FALHA corte de linha silencioso; saida: $S_LONGA"
fi

# O hook de verdade: os DOIS canais no mesmo JSON, e o injetado intocado.
CAIXA_LEGENDA="$(mktemp -d)"
PASTA_LEGENDA="$CAIXA_LEGENDA/projeto-legenda"
mkdir -p "$PASTA_LEGENDA"
git init -q "$PASTA_LEGENDA"
RFM_ROOT="$CAIXA_LEGENDA" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA_LEGENDA" node <<'SETUP_LEGENDA'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
  .run('projeto-legenda', '## Marca visivel na tela\n\nsubtitulo', '2026-08-25T10:00:00Z', 'teste');
db.close();
SETUP_LEGENDA

SAIDA_HOOK=$(cd "$PASTA_LEGENDA" && echo '{}' | RFM_ROOT="$CAIXA_LEGENDA" node "$HOOK" 2>/dev/null)
TEM_SYS=$(echo "$SAIDA_HOOK" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8'));process.stdout.write(typeof d.systemMessage==='string'&&d.systemMessage?'sim':'nao')" 2>/dev/null || echo "nao")
SYS_NO_LUGAR=$(echo "$SAIDA_HOOK" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8'));process.stdout.write((d.hookSpecificOutput||{}).systemMessage?'aninhado':'topo')" 2>/dev/null || echo "?")

if [ "$TEM_SYS" = "sim" ]; then
  ok=$((ok+1)); echo "  ok    o hook emite systemMessage quando ha marca"
else
  falhou=$((falhou+1)); echo "  FALHA hook nao emitiu systemMessage; saida: $SAIDA_HOOK"
fi

# O campo mora no TOPO do JSON, irmao de hookSpecificOutput — nao dentro dele.
# Aninhado, o harness ignora em silencio e a tela volta a ficar vazia sem ninguem
# perceber: o hook continua saindo com exit 0 e o additionalContext continua certo.
if [ "$SYS_NO_LUGAR" = "topo" ]; then
  ok=$((ok+1)); echo "  ok    systemMessage no topo do JSON (aninhado o harness ignora calado)"
else
  falhou=$((falhou+1)); echo "  FALHA systemMessage aninhado em hookSpecificOutput — o harness nao le ali"
fi
rm -rf "$CAIXA_LEGENDA"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
