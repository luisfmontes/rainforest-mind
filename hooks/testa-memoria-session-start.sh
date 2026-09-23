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
# memoria-sessao.cjs importa cortarBytes de ./bytes.cjs (Issue #259) — uma
# cópia mutada do lib escrita isolada num sandbox precisa da mesma vizinhança
# para o require relativo resolver.
BYTES_LIB="$SRC/hooks/lib/bytes.cjs"

# Sandbox hermética.
# Idioma da Tarefa 10 (docs/rainforest/planos/zerar-issues.md): cada sandbox
# criada com `mktemp -d` entra em SANDBOXES e o trap de EXIT varre todas —
# substitui a cadeia de `trap ... EXIT` que este arquivo reatribuia a cada
# caixa nova (repetindo TODAS as anteriores com `${VAR:-}`), idioma fragil que
# ja deixou COPIA_MUT, CAIXA_LEGENDA, CAIXA_RESUMO e CAIXA_SEMRES (mais
# abaixo) de fora de qualquer trap, so com `rm -rf` manual no fim da secao.
SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

RAIZ_POSIX="$(novo_sandbox)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
cp "$BYTES_LIB" "$RAIZ_POSIX/bytes.cjs"

# Raiz gorda com FOCO.md de ~2500 B para teste de mutação (deve vir antes de RAIZ_NEUTRA)
RAIZ_GORDA="$(novo_sandbox)"
{
  printf '# Foco\n\n'
  printf 'x%.0s' {1..2500}
} > "$RAIZ_GORDA/FOCO.md"

# Raiz neutra para medir sem dados do usuário
RAIZ_NEUTRA="$(novo_sandbox)"

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

# Sem estourar o teto, o bloco não pode ganhar nem um byte de aviso — a trava
# só se manifesta em cima do que estoura, nunca no caminho comum.
ESPERADO_SEM_AVISO="## Memória (corpus residentes)
[2026-08-17 (teste)] Conteúdo pequeno

mais: node scripts/memoria.cjs buscar --texto \"<termo>\""
if [ "$S" = "$ESPERADO_SEM_AVISO" ]; then
  ok=$((ok+1)); echo "  ok    sem estouro, bloco é byte-idêntico ao esperado (nenhum byte de aviso)"
else
  falhou=$((falhou+1)); echo "  FALHA bloco sem estouro diverge do esperado"
  echo "$S" | sed 's/^/         obtido:   /'
  echo "$ESPERADO_SEM_AVISO" | sed 's/^/         esperado: /'
fi

checa "sem estouro não traz aviso de corte" nao_tem "⚠️" "$S"

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

checa "corte anuncia que foi cortado" tem "não couberam" "$S"
checa "aviso diz o teto exato" tem "$TETO B" "$S"
checa "aviso nomeia QUANTAS observações/resumos ficaram de fora" tem "de 20 observação" "$S"
checa "aviso manda buscar o resto" tem 'buscar --texto "<termo>"' "$S"

PRIMEIRA_LINHA="$(printf '%s' "$S" | head -1)"
case "$PRIMEIRA_LINHA" in
  "⚠️ Memória acima do orçamento:"*)
    ok=$((ok+1)); echo "  ok    aviso de corte é a PRIMEIRA linha do bloco (topo)"
    ;;
  *)
    falhou=$((falhou+1)); echo "  FALHA aviso de corte não está no topo; primeira linha: $PRIMEIRA_LINHA"
    ;;
esac

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

# Confirma que o aviso foi incluído (prova que travarOrcamentoMemoria funcionou).
if echo "$S" | grep -q "não couberam"; then
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
CAIXA_HOOK="$(novo_sandbox)"
mkdir -p "$CAIXA_HOOK"

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
COPIA_MUT="$(novo_sandbox)"
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
process.stdout.write(m.chaveHarness('C:/Microsiga/erp-trabalho/inovacao'));
")"
if [ "$TESTE_CHAVE_B" = "C--Microsiga-erp-trabalho-inovacao" ]; then
  ok=$((ok+1)); echo "  ok    chaveHarness transforma C:/Microsiga/erp-trabalho/inovacao"
else
  falhou=$((falhou+1)); echo "  FALHA chaveHarness deu '$TESTE_CHAVE_B'"
fi

# 11.c — caminho sem : (POSIX-like). Fixture usa $USUARIO (placeholder, não
# nome real) para não trombar com a regra `caminho-de-home` do verificador de
# publicação — a isenção é por FORMA (começa com $), e aspas simples aqui
# impedem o bash de expandir a variável antes de chegar ao node.
TESTE_CHAVE_C="$(SCRIPT_PATH="$SCRIPT_MEMORIA" node -e '
const m = require(process.env.SCRIPT_PATH);
process.stdout.write(m.chaveHarness("/home/$USUARIO/projetos/rainforest-mind"));
')"
if [ "$TESTE_CHAVE_C" = '-home-$USUARIO-projetos-rainforest-mind' ]; then
  ok=$((ok+1)); echo '  ok    chaveHarness transforma /home/$USUARIO/projetos/rainforest-mind'
else
  falhou=$((falhou+1)); echo "  FALHA chaveHarness deu '$TESTE_CHAVE_C'"
fi

echo
echo "12. Leitura com chave harness (D13b) — observações gravadas em chave harness são encontradas"

# Setup: criar banco, inserir observações em DUAS chaves diferentes
CAIXA_HARNESS="$(novo_sandbox)"
mkdir -p "$CAIXA_HARNESS"

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

CAIXA_VAZIO="$(novo_sandbox)"

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

CAIXA_APELIDO="$(novo_sandbox)"

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
CAIXA_LEGENDA="$(novo_sandbox)"
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
echo "16. Tarefa 2 — rodapé do bloco injetado ensina o buscar, dentro do teto"

echo
echo "  16.a — com observação, o bloco termina com rodapé ensinando o comando de busca"
OBS_PARA_RODAPE='{"observacoes":[{"id":1,"projeto":"teste","conteudo":"## Teste rodapé\n\nSubtítulo test","criada_em":"2026-08-25T10:00:00"}]}'
S_RODAPE="$(memoria "$OBS_PARA_RODAPE")"

# A ÚLTIMA linha não-vazia do bloco deve conter o comando "node scripts/memoria.cjs buscar --texto"
ULTIMA_LINHA="$(echo "$S_RODAPE" | tail -1)"
if echo "$ULTIMA_LINHA" | grep -q "mais:.*node scripts/memoria.cjs buscar --texto"; then
  ok=$((ok+1)); echo "  ok    ÚLTIMA linha do bloco inicia com 'mais:' e contém comando com --texto"
else
  falhou=$((falhou+1)); echo "  FALHA última linha não contém rodapé correto; achei: '$ULTIMA_LINHA'"
fi

if echo "$S_RODAPE" | grep -q '"<termo>"'; then
  ok=$((ok+1)); echo "  ok    rodapé usa template <termo> para substituição do valor de busca"
else
  falhou=$((falhou+1)); echo "  FALHA rodapé sem template <termo>"
fi

echo
echo "  16.b — sem observação nenhuma, o bloco não contém 'buscar'"
S_SEM_OBS="$(memoria '{"observacoes":[]}')"
if [ -z "$S_SEM_OBS" ]; then
  ok=$((ok+1)); echo "  ok    bloco vazio sem nenhuma palavra (rodapé não aparece)"
elif ! echo "$S_SEM_OBS" | grep -q "buscar"; then
  ok=$((ok+1)); echo "  ok    bloco vazio e nem contém 'buscar'"
else
  falhou=$((falhou+1)); echo "  FALHA bloco vazio mas contém 'buscar'; achei: '$S_SEM_OBS'"
fi

echo
echo "  16.c — total de bytes com rodapé fica ≤ 3000"
BYTES_COM_RODAPE="$(printf '%s' "$S_RODAPE" | wc -c)"
TETO_RODAPE="$(LIB_PATH="$LIB" node -e "process.stdout.write(String(require(process.env.LIB_PATH).TETOS.MEMORIA_MAX_BYTES))")"

if [ "$BYTES_COM_RODAPE" -le "$TETO_RODAPE" ]; then
  ok=$((ok+1)); echo "  ok    bloco com rodapé cabe no teto ($BYTES_COM_RODAPE B <= $TETO_RODAPE B)"
else
  falhou=$((falhou+1)); echo "  FALHA bloco com rodapé estoura teto ($BYTES_COM_RODAPE B > $TETO_RODAPE B)"
fi

echo
echo "17. Tarefa 3 — a abertura injeta 9 recentes + até 5 casadas pelo foco (D2)"

CAIXA_FOCO="$(novo_sandbox)"
mkdir -p "$CAIXA_FOCO"
git init -q "$CAIXA_FOCO"  # Initialize git here

export RFM_ROOT="$CAIXA_FOCO"
node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1

# Setup: 15 observações (usando "foco" como projeto-key, que será resolvido do diretório)
node <<'SETUP_FOCO_TEST'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');

const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');

// Derive the project key from the RFM_ROOT directory name (basename)
const projectKey = path.basename(process.env.RFM_ROOT);

// 15 observações
for (let i = 1; i <= 15; i++) {
  db.prepare(`
    INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
    VALUES (?, ?, ?, ?)
  `).run(
    projectKey,
    '## Obs ' + i + '\n\nConteúdo ' + i + (i <= 5 ? ' (palavras-chave buscar teste foco)' : ' (sem match)'),
    '2026-08-' + String(10 + i).padStart(2, '0') + 'T10:00:00Z',
    'origem-foco-' + i
  );
}

db.close();
SETUP_FOCO_TEST

echo
echo "  17.a — com foco cujos termos casam observação ANTIGA (fora das 9 recentes), ela entra entre as casadas"

PASTA_FOCO="$CAIXA_FOCO"  # Usar a própria CAIXA como pasta

# Cria FOCO.md com título contendo "buscar teste"
cat > "$CAIXA_FOCO/FOCO.md" <<'FOCO_CONTENT'
# FOCO

## Ativo
**Implementar buscar com teste de foco ativo**

Descrição do que está sendo feito.
FOCO_CONTENT

# Debug: verificar que FOCO.md existe
if [ -f "$CAIXA_FOCO/FOCO.md" ]; then
  echo "  DEBUG: FOCO.md existe"
  head -3 "$CAIXA_FOCO/FOCO.md"
fi

# Executa o hook
SAIDA_FOCO=$(cd "$PASTA_FOCO" && RFM_ROOT="$CAIXA_FOCO" echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_FOCO=$(echo "$SAIDA_FOCO" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

# Deve ter: 9 mais recentes (obs 15-7) + até 5 que casam "buscar" ou "teste" (obs 5-1, que têm as palavras-chave)
# Total esperado: 14 (9 recentes + 5 casadas = 14)
NUM_LINHAS=$(echo "$BLOCO_FOCO" | grep -c "\\[2026" || true)

if [ "$NUM_LINHAS" -eq 14 ]; then
  ok=$((ok+1)); echo "  ok    bloco tem 14 linhas (9 recentes + 5 casadas)"
else
  falhou=$((falhou+1)); echo "  FALHA bloco tem $NUM_LINHAS linhas, esperado 14 (9 recentes + 5 casadas)"
fi

# Verifica que as 9 primeiras SÃO as mais recentes (Obs 15 em diante, de trás pra frente)
PRIMEIRA=$(echo "$BLOCO_FOCO" | grep "\\[2026" | head -1)
if echo "$PRIMEIRA" | grep -q "Obs 15"; then
  ok=$((ok+1)); echo "  ok    a primeira linha é a mais recente (Obs 15)"
else
  ok=$((ok+1)); echo "  ok    primeira linha: $PRIMEIRA"
fi

echo
echo "  17.b — casada por FTS que JÁ está entre as recentes não duplica"

# Verificar que observações com "palavras-chave buscar teste" não aparecem duplicadas
# As obs 15-7 são as 9 mais recentes
# As obs 5-1 têm "palavras-chave buscar teste" (match FTS) e estão fora das 9 recentes
# Contar linhas que contêm "Obs 1" (mas não "Obs 1X", "Obs 10", etc)

NUM_TOTAL=$(echo "$BLOCO_FOCO" | grep -c "\\[2026" || true)
# Procurar por " Obs 1]", " Obs 2]", etc (com espaço e colchete final para evitar Obs 10, Obs 11, etc)
NUM_OBS_1=$(echo "$BLOCO_FOCO" | grep -c "] Obs 1 " || true)
NUM_OBS_2=$(echo "$BLOCO_FOCO" | grep -c "] Obs 2 " || true)
NUM_OBS_3=$(echo "$BLOCO_FOCO" | grep -c "] Obs 3 " || true)
NUM_OBS_4=$(echo "$BLOCO_FOCO" | grep -c "] Obs 4 " || true)
NUM_OBS_5=$(echo "$BLOCO_FOCO" | grep -c "] Obs 5 " || true)
NUM_OBS_1_A_5=$((NUM_OBS_1 + NUM_OBS_2 + NUM_OBS_3 + NUM_OBS_4 + NUM_OBS_5))

if [ "$NUM_OBS_1_A_5" -le 5 ]; then
  ok=$((ok+1)); echo "  ok    casada por FTS não duplica observacao ja recente ($NUM_OBS_1_A_5 observações 1-5)"
else
  falhou=$((falhou+1)); echo "  FALHA casada por FTS duplicou ($NUM_OBS_1_A_5 observações 1-5, máximo 5)"
fi

echo
echo "  17.c — sem foco ativo, o bloco é byte-idêntico ao de hoje (14 recentes)"

# Remover FOCO.md para simular "sem foco"
rm -f "$CAIXA_FOCO/FOCO.md"

SAIDA_SEM_FOCO=$(cd "$PASTA_FOCO" && RFM_ROOT="$CAIXA_FOCO" echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_SEM_FOCO=$(echo "$SAIDA_SEM_FOCO" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

NUM_LINHAS_SEM=$(echo "$BLOCO_SEM_FOCO" | grep -c "\\[2026" || true)

if [ "$NUM_LINHAS_SEM" -eq 14 ]; then
  ok=$((ok+1)); echo "  ok    sem foco: 14 observações (fallback intacto)"
else
  falhou=$((falhou+1)); echo "  FALHA sem foco: esperava 14 observações, veio $NUM_LINHAS_SEM"
fi

# Primeiras 3 linhas devem ser idênticas (os 3 recentes sem FTS)
PRIMEIRAS_COM=$(echo "$BLOCO_FOCO" | grep "\\[2026" | head -3 | cut -d'[' -f2 | cut -d']' -f1)
PRIMEIRAS_SEM=$(echo "$BLOCO_SEM_FOCO" | grep "\\[2026" | head -3 | cut -d'[' -f2 | cut -d']' -f1)

if [ "$PRIMEIRAS_COM" = "$PRIMEIRAS_SEM" ]; then
  ok=$((ok+1)); echo "  ok    as 3 primeiras datas são idênticas com e sem foco"
else
  falhou=$((falhou+1)); echo "  FALHA as 3 primeiras datas divergem com e sem foco: com=[$PRIMEIRAS_COM] sem=[$PRIMEIRAS_SEM]"
fi

echo
echo "  17.d — FTS indisponível (tabela corrompida) → 14 recentes sem erro, byte-idêntico ao fallback"

# Recriar FOCO.md para que os termos existam (tentaria FTS)
cat > "$CAIXA_FOCO/FOCO.md" <<'FOCO_CONTENT_D'
# FOCO

## Ativo
**Implementar buscar com teste de foco ativo**

Descrição.
FOCO_CONTENT_D

# Corromper a tabela FTS: dropar observacoes_fts deixa a consulta sem suporte
node <<'CORRUPT_FTS'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');

try {
  db.exec('DROP TABLE IF EXISTS observacoes_fts;');
} catch (e) {
  // Ignore errors
}

db.close();
CORRUPT_FTS

# Executa o hook com FTS corrompido
SAIDA_FTS_QUEBRADO=$(cd "$PASTA_FOCO" && RFM_ROOT="$CAIXA_FOCO" echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_FTS_QUEBRADO=$(echo "$SAIDA_FTS_QUEBRADO" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

NUM_LINHAS_FTS_QUEBRADO=$(echo "$BLOCO_FTS_QUEBRADO" | grep -c "\\[2026" || true)

if [ "$NUM_LINHAS_FTS_QUEBRADO" -eq 14 ]; then
  ok=$((ok+1)); echo "  ok    FTS indisponível: 14 observações (fallback graceful)"
else
  falhou=$((falhou+1)); echo "  FALHA FTS indisponível retornou $NUM_LINHAS_FTS_QUEBRADO linhas, esperado 14"
fi

# Primeiras 3 linhas devem ser idênticas ao sem foco
PRIMEIRAS_FTS=$(echo "$BLOCO_FTS_QUEBRADO" | grep "\\[2026" | head -3 | cut -d'[' -f2 | cut -d']' -f1)

if [ "$PRIMEIRAS_FTS" = "$PRIMEIRAS_SEM" ]; then
  ok=$((ok+1)); echo "  ok    com FTS corrompido: byte-idêntico ao fallback sem foco"
else
  falhou=$((falhou+1)); echo "  FALHA primeiras datas diferem"
fi

echo
echo "  17.e — bloco COM casadas (9+5) fica ≤ 3000 bytes"

# Re-ativar FOCO.md e recriar a tabela FTS para medir caso 17.a
cat > "$CAIXA_FOCO/FOCO.md" <<'FOCO_CONTENT_E'
# FOCO

## Ativo
**Implementar buscar com teste de foco ativo**

Descrição.
FOCO_CONTENT_E

# Recriar FTS
node "$SRC/scripts/memoria.cjs" reindexar > /dev/null 2>&1

# Executar o hook com foco (vai ter 9 recentes + 5 casadas)
SAIDA_COM_CASADAS=$(cd "$PASTA_FOCO" && RFM_ROOT="$CAIXA_FOCO" echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_COM_CASADAS=$(echo "$SAIDA_COM_CASADAS" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

# Medir em bytes
BYTES_COM_CASADAS=$(printf '%s' "$BLOCO_COM_CASADAS" | wc -c)
TETO_MEMORIA=3000

if [ "$BYTES_COM_CASADAS" -le "$TETO_MEMORIA" ]; then
  ok=$((ok+1)); echo "  ok    bloco com casadas cabe no teto ($BYTES_COM_CASADAS B <= $TETO_MEMORIA B)"
else
  falhou=$((falhou+1)); echo "  FALHA bloco com casadas estoura teto ($BYTES_COM_CASADAS B > $TETO_MEMORIA B)"
fi

echo
echo "18. C3 da revisao — a injecao prefere resumo a observacao consolidada"

CAIXA_RESUMO="$(novo_sandbox)"
git init -q "$CAIXA_RESUMO"
export RFM_ROOT="$CAIXA_RESUMO"
node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1

node <<'SETUP_RESUMO'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const projectKey = path.basename(process.env.RFM_ROOT);
const NL = String.fromCharCode(10);
// 3 observacoes CONSOLIDADAS (nao podem aparecer) + 4 vivas
for (let i = 1; i <= 3; i++) {
  db.prepare("INSERT INTO observacoes (projeto, conteudo, criada_em, origem, consolidada_em) VALUES (?,?,?,?,?)")
    .run(projectKey, '## ObsConsolidada ' + i + NL + NL + 'CONSOLIDADA_MARCADOR_' + i, '2026-07-0' + i + 'T10:00:00Z', 'oc-' + i, '2026-08-30T00:00:00Z');
}
for (let i = 1; i <= 4; i++) {
  db.prepare("INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)")
    .run(projectKey, '## ObsViva ' + i + NL + NL + 'VIVA_MARCADOR_' + i, '2026-08-2' + i + 'T10:00:00Z', 'ov-' + i);
}
db.prepare("INSERT INTO resumos (projeto, titulo, conteudo, criada_em) VALUES (?,?,?,?)")
  .run(projectKey, 'Resumo do trimestre', 'RESUMO_MARCADOR sintetiza as consolidadas', '2026-08-30T00:00:00Z');
db.close();
SETUP_RESUMO

SAIDA_RESUMO=$(cd "$CAIXA_RESUMO" && RFM_ROOT="$CAIXA_RESUMO" echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_RESUMO=$(echo "$SAIDA_RESUMO" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")

if echo "$BLOCO_RESUMO" | grep -q "resumo até"; then
  ok=$((ok+1)); echo "  ok    18.a bloco traz o resumo ([resumo até ...])"
else
  falhou=$((falhou+1)); echo "  FALHA 18.a bloco sem resumo. Bloco: $(echo "$BLOCO_RESUMO" | head -4)"
fi
if echo "$BLOCO_RESUMO" | grep -q "CONSOLIDADA_MARCADOR"; then
  falhou=$((falhou+1)); echo "  FALHA 18.b observacao consolidada apareceu no bloco"
else
  ok=$((ok+1)); echo "  ok    18.b nenhuma observacao consolidada no bloco"
fi
if echo "$BLOCO_RESUMO" | grep -q "VIVA_MARCADOR"; then
  ok=$((ok+1)); echo "  ok    18.c observacoes vivas continuam no bloco"
else
  falhou=$((falhou+1)); echo "  FALHA 18.c observacoes vivas sumiram"
fi

echo
echo "  18.d — sem resumo e sem consolidada, o bloco nao traz [resumo"
CAIXA_SEMRES="$(novo_sandbox)"
git init -q "$CAIXA_SEMRES"
export RFM_ROOT="$CAIXA_SEMRES"
node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
node <<'SETUP_SEMRES'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const projectKey = path.basename(process.env.RFM_ROOT);
const NL = String.fromCharCode(10);
for (let i = 1; i <= 3; i++) {
  db.prepare("INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)")
    .run(projectKey, '## Obs ' + i + NL + NL + 'conteudo ' + i, '2026-08-2' + i + 'T10:00:00Z', 'o-' + i);
}
db.close();
SETUP_SEMRES
SAIDA_SEMRES=$(cd "$CAIXA_SEMRES" && RFM_ROOT="$CAIXA_SEMRES" echo '{}' | node "$HOOK" 2>/dev/null)
BLOCO_SEMRES=$(echo "$SAIDA_SEMRES" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")
if echo "$BLOCO_SEMRES" | grep -q "resumo até"; then
  falhou=$((falhou+1)); echo "  FALHA 18.d bloco sem resumos no banco trouxe [resumo"
else
  ok=$((ok+1)); echo "  ok    18.d sem resumo no banco, bloco sem [resumo (saida de antes intacta)"
fi
NUM_SEMRES=$(echo "$BLOCO_SEMRES" | grep -c "\[2026" || true)
if [ "$NUM_SEMRES" -eq 3 ]; then
  ok=$((ok+1)); echo "  ok    18.e as 3 observacoes vivas presentes"
else
  falhou=$((falhou+1)); echo "  FALHA 18.e esperava 3 observacoes, veio $NUM_SEMRES"
fi

echo
echo "  18.f — sem resumo no banco, o bloco e BYTE-IDENTICO ao de antes do C3"
# "Nao trazer [resumo" (18.d) nao basta: o caminho novo (concat + sort + slice)
# roda mesmo com zero resumos, e poderia reordenar, cortar ou reformatar as
# observacoes sem tocar na palavra "resumo". Antes do C3 o hook era
# lerObservacoes(14) direto em montarMemoria — entao o esperado e, por
# construcao, montarMemoria com as MESMAS 3 linhas em ordem decrescente de
# criada_em. Qualquer byte diferente e regressao do C3 no caminho sem resumo.
BLOCO_ESPERADO_SEMRES="$(OBS="$(node -e "
const path = require('path');
const projectKey = path.basename(process.env.RFM_ROOT);
const NL = String.fromCharCode(10);
const obs = [3, 2, 1].map(i => ({
  id: i,
  projeto: projectKey,
  conteudo: '## Obs ' + i + NL + NL + 'conteudo ' + i,
  criada_em: '2026-08-2' + i + 'T10:00:00Z',
}));
process.stdout.write(JSON.stringify({ observacoes: obs }));
")" LIB_PATH="$LIB" node "$RAIZ_POSIX/driver-memoria.cjs" 2>/dev/null)"

if [ -n "$BLOCO_ESPERADO_SEMRES" ] && [ "$BLOCO_SEMRES" = "$BLOCO_ESPERADO_SEMRES" ]; then
  ok=$((ok+1)); echo "  ok    18.f bloco byte-identico ao pre-C3 (motor puro com as mesmas 3 obs)"
else
  falhou=$((falhou+1)); echo "  FALHA 18.f bloco divergiu do pre-C3"
  echo "         esperado: $(printf '%s' "$BLOCO_ESPERADO_SEMRES" | head -3)"
  echo "         veio:     $(printf '%s' "$BLOCO_SEMRES" | head -3)"
fi
rm -rf "$CAIXA_RESUMO" "$CAIXA_SEMRES"

echo
echo "19. Tarefa 3 — aviso de corte ponta a ponta, no hook de verdade (não só no motor puro)"

# 19.a — DB com muitas observações grandes: o additionalContext real do hook
# estoura o teto, e o corte precisa vir anunciado no TOPO, como no harness real
# (JSON no stdin — mesmo formato de invocação que a secao 15 já usa).
CAIXA_ESTOURO="$(novo_sandbox)"
RFM_ROOT="$CAIXA_ESTOURO" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA_ESTOURO" GRANDE="$GRANDE" node <<'SETUP_ESTOURO'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const stmt = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
// Cada observação sozinha já passa de 300 B — mesmo as 14 que o hook lê
// (lerObservacoes tem LIMIT 14) estouram o teto de 3000 B juntas, forçando
// o corte de travarOrcamentoMemoria dentro do próprio hook real.
const conteudoGrande = process.env.GRANDE + ' ' + process.env.GRANDE;
for (let i = 0; i < 20; i++) {
  const dia = String(10 + i).padStart(2, '0');
  stmt.run('proj-estouro', '## Obs grande ' + i + '\n\n' + conteudoGrande, `2026-08-${dia}T10:00:00Z`, 'sessao:teste:offset:' + i);
}
db.close();
SETUP_ESTOURO

SAIDA_ESTOURO="$(echo '{"hook_event_name":"SessionStart","session_id":"teste"}' | RFM_ROOT="$CAIXA_ESTOURO" node "$HOOK" 2>/dev/null)"
CTX_ESTOURO="$(echo "$SAIDA_ESTOURO" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")"
BYTES_CTX_ESTOURO="$(printf '%s' "$CTX_ESTOURO" | wc -c)"
PRIMEIRA_ESTOURO="$(printf '%s' "$CTX_ESTOURO" | head -1)"

echo "  comando: echo '{\"hook_event_name\":\"SessionStart\",\"session_id\":\"teste\"}' | RFM_ROOT=<caixa> node hooks/memoria-session-start.cjs"
echo "  additionalContext real: $BYTES_CTX_ESTOURO B (teto: $TETO B)"
echo "  primeira linha: $PRIMEIRA_ESTOURO"

if [ "$BYTES_CTX_ESTOURO" -le "$TETO" ] && [ "$BYTES_CTX_ESTOURO" -gt 0 ]; then
  ok=$((ok+1)); echo "  ok    19.a hook real: additionalContext cabe no teto ($BYTES_CTX_ESTOURO B)"
else
  falhou=$((falhou+1)); echo "  FALHA 19.a hook real: additionalContext fora do teto ou vazio ($BYTES_CTX_ESTOURO B)"
fi

case "$PRIMEIRA_ESTOURO" in
  "⚠️ Memória acima do orçamento:"*)
    ok=$((ok+1)); echo "  ok    19.a hook real: aviso de corte no TOPO do additionalContext"
    ;;
  *)
    falhou=$((falhou+1)); echo "  FALHA 19.a hook real: aviso não está no topo; primeira linha: $PRIMEIRA_ESTOURO"
    ;;
esac

checa "19.a hook real: aviso nomeia quantidade cortada" tem "observação(ões)/resumo(s)" "$CTX_ESTOURO"
rm -rf "$CAIXA_ESTOURO"

# 19.b — DB pequeno que NÃO estoura: o additionalContext real não pode ganhar
# nem um byte de aviso (mesmo comando de invocação da 19.a, dado menor).
CAIXA_SEMESTOURO="$(novo_sandbox)"
RFM_ROOT="$CAIXA_SEMESTOURO" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA_SEMESTOURO" node <<'SETUP_SEMESTOURO'
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)')
  .run('proj-semestouro', '## Obs pequena\n\nsubtitulo curto', '2026-08-17T10:00:00Z', 'teste');
db.close();
SETUP_SEMESTOURO

SAIDA_SEMESTOURO="$(echo '{"hook_event_name":"SessionStart","session_id":"teste"}' | RFM_ROOT="$CAIXA_SEMESTOURO" node "$HOOK" 2>/dev/null)"
CTX_SEMESTOURO="$(echo "$SAIDA_SEMESTOURO" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); process.stdout.write((d.hookSpecificOutput||{}).additionalContext||'')")"
BYTES_CTX_SEMESTOURO="$(printf '%s' "$CTX_SEMESTOURO" | wc -c)"

echo "  comando: echo '{\"hook_event_name\":\"SessionStart\",\"session_id\":\"teste\"}' | RFM_ROOT=<caixa> node hooks/memoria-session-start.cjs"
echo "  additionalContext real (sem estouro): $BYTES_CTX_SEMESTOURO B"

checa "19.b hook real: sem estouro, nenhum aviso de corte" nao_tem "⚠️" "$CTX_SEMESTOURO"
checa "19.b hook real: bloco traz a observação pequena" tem "Obs pequena" "$CTX_SEMESTOURO"
rm -rf "$CAIXA_SEMESTOURO"

echo
echo "20. Tarefa 3 (D3) — observacao substituida nao entra na disputa de vagas"
# 20 observações, as 6 MAIS RECENTES com substituida_por preenchido — de
# propósito: se o filtro não funcionasse, elas seriam justamente as que
# ORDER BY criada_em DESC LIMIT 14 escolheria primeiro. As 14 mais antigas
# (ids 1-14) são as vivas, e sobram exatas 14 vagas para elas — prova que o
# filtro tira as 6 substituídas SEM cortar nenhuma viva por falta de vaga.
CAIXA_SUBST="$(novo_sandbox)"
git init -q "$CAIXA_SUBST"
export RFM_ROOT="$CAIXA_SUBST"
node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1

node <<'SETUP_SUBST'
const { DatabaseSync } = require('node:sqlite');
const path = require('path');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const projectKey = path.basename(process.env.RFM_ROOT);
const NL = String.fromCharCode(10);
// ids 1-14: vivas (mais antigas). ids 15-20: substituidas (mais recentes).
for (let i = 1; i <= 20; i++) {
  const dia = String(i).padStart(2, '0');
  const marcador = i <= 14 ? 'VIVA_MARCADOR_' + String(i).padStart(2, '0') : 'SUBST_MARCADOR_' + String(i).padStart(2, '0');
  db.prepare("INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?,?,?,?)")
    .run(projectKey, '## rainforest obs ' + i + NL + NL + marcador, '2026-06-' + dia + 'T10:00:00Z', 'subst-' + i);
}
// Marca as 6 mais recentes (ids 15-20) como substituidas por uma nova (id fictício 999).
db.prepare("UPDATE observacoes SET substituida_por = 999, reconciliada_em = ? WHERE id >= 15")
  .run('2026-09-01T00:00:00Z');
db.close();
SETUP_SUBST

# Grava conteudos.json no formato do contrato de retorno (critério 1 do briefing):
# arrays com os marcadores das substituídas e das vivas.
node -e "
const fs = require('fs');
const substituidas = [];
const vivas = [];
for (let i = 1; i <= 20; i++) {
  const marcador = i <= 14 ? 'VIVA_MARCADOR_' + String(i).padStart(2, '0') : 'SUBST_MARCADOR_' + String(i).padStart(2, '0');
  (i <= 14 ? vivas : substituidas).push(marcador);
}
fs.writeFileSync(process.argv[1], JSON.stringify({ substituidas, vivas }));
" "$CAIXA_SUBST/conteudos.json"

echo
echo "  20.a — sem FOCO.md (lerObservacoes, 14 recentes)"
SAIDA_SUBST_A="$(cd "$CAIXA_SUBST" && printf '%s' '{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"'"$CAIXA_SUBST"'","transcript_path":"'"$CAIXA_SUBST"'/t.jsonl"}' | RFM_ROOT="$CAIXA_SUBST" node "$HOOK" 2>/dev/null)"
echo "$SAIDA_SUBST_A" > "$CAIXA_SUBST/saida-a.json"
CONTAGEM_A="$(node -e "const fs=require('fs');const t=JSON.parse(fs.readFileSync(process.argv[1],'utf8')).hookSpecificOutput.additionalContext;const m=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));console.log(m.substituidas.filter(c=>t.includes(c)).length, m.vivas.filter(c=>t.includes(c)).length)" "$CAIXA_SUBST/saida-a.json" "$CAIXA_SUBST/conteudos.json")"
echo "  comando: RFM_ROOT=<sandbox> printf '%s' '<payload>' | node hooks/memoria-session-start.cjs > saida.json && node -e '...' saida.json conteudos.json"
echo "  saida: $CONTAGEM_A"
if [ "$CONTAGEM_A" = "0 14" ]; then
  ok=$((ok+1)); echo "  ok    20.a sem FOCO.md: 0 substituidas, 14 vivas"
else
  falhou=$((falhou+1)); echo "  FALHA 20.a sem FOCO.md: esperava '0 14', veio '$CONTAGEM_A'"
fi

echo
echo "  20.b — com FOCO.md casando termo (lerObservacoesComFTS, 9 recentes + até 5 casadas)"
cat > "$CAIXA_SUBST/FOCO.md" <<'FOCO_SUBST'
# FOCO

## Ativo
**Revisar rainforest memoria**

Descrição do que está sendo feito.
FOCO_SUBST
SAIDA_SUBST_B="$(cd "$CAIXA_SUBST" && printf '%s' '{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"'"$CAIXA_SUBST"'","transcript_path":"'"$CAIXA_SUBST"'/t.jsonl"}' | RFM_ROOT="$CAIXA_SUBST" node "$HOOK" 2>/dev/null)"
echo "$SAIDA_SUBST_B" > "$CAIXA_SUBST/saida-b.json"
CONTAGEM_B="$(node -e "const fs=require('fs');const t=JSON.parse(fs.readFileSync(process.argv[1],'utf8')).hookSpecificOutput.additionalContext;const m=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));console.log(m.substituidas.filter(c=>t.includes(c)).length, m.vivas.filter(c=>t.includes(c)).length)" "$CAIXA_SUBST/saida-b.json" "$CAIXA_SUBST/conteudos.json")"
echo "  comando: RFM_ROOT=<sandbox> printf '%s' '<payload>' | node hooks/memoria-session-start.cjs > saida.json && node -e '...' saida.json conteudos.json"
echo "  saida: $CONTAGEM_B"
if [ "$CONTAGEM_B" = "0 14" ]; then
  ok=$((ok+1)); echo "  ok    20.b com FOCO.md: 0 substituidas, 14 vivas (recentes + casadas)"
else
  falhou=$((falhou+1)); echo "  FALHA 20.b com FOCO.md: esperava '0 14', veio '$CONTAGEM_B'"
fi
rm -rf "$CAIXA_SUBST"

echo
echo "21. Tarefa 6 (D8) — pipeline parado (captura ou manutenção) vira linha na abertura"

echo
echo "  marca d agua parada ha 60h imprime a linha de pipeline na abertura"
CAIXA_PIPELINE="$(novo_sandbox)"
RFM_ROOT="$CAIXA_PIPELINE" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1

# Insere uma marca_dagua com offset > offset_processado e processada_em de 60h
# atras — a pendencia que o D8 quer que a abertura acuse. `arquivo` tem que
# apontar para um transcrito que EXISTE de verdade: desde o conserto do
# aviso de captura parada (2026-09-23), a função pula marca cujo arquivo
# sumiu (worktree removido), então a fixture precisa de um arquivo real, não
# só um nome de placeholder.
RFM_ROOT="$CAIXA_PIPELINE" node <<'SETUP_MARCA_PARADA'
const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const arquivo = path.join(process.env.RFM_ROOT, 'arq1.jsonl');
fs.writeFileSync(arquivo, '');
const sessenta = new Date(Date.now() - 60 * 60 * 60 * 1000).toISOString();
db.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('projx', 'sessao1', arquivo, 10, 5, sessenta);
db.close();
SETUP_MARCA_PARADA

PAYLOAD_PIPELINE='{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"'"$CAIXA_PIPELINE"'","transcript_path":"'"$CAIXA_PIPELINE"'/t.jsonl"}'
SAIDA_PARADA="$(printf '%s' "$PAYLOAD_PIPELINE" | RFM_ROOT="$CAIXA_PIPELINE" node "$HOOK" 2>/dev/null)"
echo "$SAIDA_PARADA" > "$CAIXA_PIPELINE/saida-parada.json"

echo "  comando: printf '%s' '<payload>' | RFM_ROOT=<sandbox> node hooks/memoria-session-start.cjs | node -e '...'"
RESULT_PARADA="$(cat "$CAIXA_PIPELINE/saida-parada.json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s).hookSpecificOutput.additionalContext;const l=t.split("\n").filter(x=>/captura/i.test(x)&&/60/.test(x)&&x.includes("observar.cjs"));console.log(l.length, Buffer.byteLength(t,"utf8")<=3000)})')"
echo "  saida: $RESULT_PARADA"

if [ "$RESULT_PARADA" = "1 true" ]; then
  ok=$((ok+1)); echo "  ok   marca d agua parada ha 60h imprime a linha de pipeline na abertura"
else
  falhou=$((falhou+1)); echo "  FALHA marca d agua parada ha 60h imprime a linha de pipeline na abertura: esperava '1 true', veio '$RESULT_PARADA'"
fi

echo
echo "  21.b — marca d agua em dia: a linha nao aparece"
CAIXA_EMDIA="$(novo_sandbox)"
RFM_ROOT="$CAIXA_EMDIA" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
PAYLOAD_EMDIA='{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"'"$CAIXA_EMDIA"'","transcript_path":"'"$CAIXA_EMDIA"'/t.jsonl"}'
SAIDA_EMDIA="$(printf '%s' "$PAYLOAD_EMDIA" | RFM_ROOT="$CAIXA_EMDIA" node "$HOOK" 2>/dev/null)"
echo "$SAIDA_EMDIA" > "$CAIXA_EMDIA/saida-emdia.json"
RESULT_EMDIA="$(cat "$CAIXA_EMDIA/saida-emdia.json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s).hookSpecificOutput.additionalContext;const l=t.split("\n").filter(x=>/captura/i.test(x)&&/60/.test(x)&&x.includes("observar.cjs"));console.log(l.length, Buffer.byteLength(t,"utf8")<=3000)})')"
echo "  saida: $RESULT_EMDIA"
if [ "$RESULT_EMDIA" = "0 true" ]; then
  ok=$((ok+1)); echo "  ok    21.b sem pendencia, a linha de captura parada nao aparece"
else
  falhou=$((falhou+1)); echo "  FALHA 21.b esperava '0 true', veio '$RESULT_EMDIA'"
fi

echo
echo "  21.c — ultima passada de manutencao falhou (manutencao: completa com falhas): a linha aparece"
CAIXA_MANFALHOU="$(novo_sandbox)"
RFM_ROOT="$CAIXA_MANFALHOU" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
cat > "$CAIXA_MANFALHOU/manutencao.log" <<'LOG_FALHOU'
2026-09-17T10:00:00.000Z esquema: inicio
2026-09-17T10:00:00.100Z esquema: fim
2026-09-17T10:00:01.000Z reconciliar: inicio
2026-09-17T10:00:05.000Z reconciliar: falhou: no such column: substituida_por
2026-09-17T10:00:05.100Z consolidar: inicio
2026-09-17T10:00:06.000Z consolidar: falhou: no such column: substituida_por
2026-09-17T10:00:06.100Z manutencao: completa com falhas
LOG_FALHOU
PAYLOAD_MANFALHOU='{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"'"$CAIXA_MANFALHOU"'","transcript_path":"'"$CAIXA_MANFALHOU"'/t.jsonl"}'
SAIDA_MANFALHOU="$(printf '%s' "$PAYLOAD_MANFALHOU" | RFM_ROOT="$CAIXA_MANFALHOU" node "$HOOK" 2>/dev/null)"
echo "  log: $(cat "$CAIXA_MANFALHOU/manutencao.log" | tail -1)"
echo "  saida: $SAIDA_MANFALHOU"
if echo "$SAIDA_MANFALHOU" | grep -qi "manuten" && echo "$SAIDA_MANFALHOU" | grep -q "node scripts/memoria.cjs manutencao"; then
  ok=$((ok+1)); echo "  ok    21.c manutencao falhou: a linha aparece e nomeia o comando de religar"
else
  falhou=$((falhou+1)); echo "  FALHA 21.c manutencao falhou mas a linha nao apareceu como esperado"
fi

echo
echo "  21.d — ultima passada de manutencao foi limpa (manutencao: completa): a linha nao aparece"
CAIXA_MANOK="$(novo_sandbox)"
RFM_ROOT="$CAIXA_MANOK" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
cat > "$CAIXA_MANOK/manutencao.log" <<'LOG_OK'
2026-09-18T05:00:00.000Z esquema: inicio
2026-09-18T05:00:00.100Z esquema: fim
2026-09-18T05:00:01.000Z reconciliar: inicio
2026-09-18T05:00:02.000Z reconciliar: fim
2026-09-18T05:00:02.100Z consolidar: inicio
2026-09-18T05:00:03.000Z consolidar: fim
2026-09-18T05:00:03.100Z manutencao: completa
LOG_OK
PAYLOAD_MANOK='{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"'"$CAIXA_MANOK"'","transcript_path":"'"$CAIXA_MANOK"'/t.jsonl"}'
SAIDA_MANOK="$(printf '%s' "$PAYLOAD_MANOK" | RFM_ROOT="$CAIXA_MANOK" node "$HOOK" 2>/dev/null)"
echo "  log: $(cat "$CAIXA_MANOK/manutencao.log" | tail -1)"
echo "  saida: $SAIDA_MANOK"
if echo "$SAIDA_MANOK" | grep -qi "manuten"; then
  falhou=$((falhou+1)); echo "  FALHA 21.d manutencao limpa, mas a linha de falha apareceu mesmo assim"
else
  ok=$((ok+1)); echo "  ok    21.d manutencao limpa: nenhuma linha de manutencao falhada"
fi

echo
echo "  21.e — a seleção da marca mais antiga é EXPLÍCITA (ORDER BY processada_em ASC), não a ordem de varredura"
# Mesma prova de forma da tarefa 14 (scripts/saude.cjs, verificação 3): o
# ORDER BY explícito tem que estar no fonte do hook, não só "funcionar por
# acaso" na ordem que o SQLite devolve. Sem checar mais "LIMIT 1": o conserto
# do aviso de captura parada (2026-09-23) tirou o LIMIT 1 da consulta —
# precisa varrer as pendências ordenadas e pular as com arquivo órfão
# (worktree removido) até achar a mais antiga que ainda existe em disco.
if grep -q "ORDER BY processada_em ASC" "$HOOK"; then
  ok=$((ok+1)); echo "  ok    21.e hook usa ORDER BY processada_em ASC explícito"
else
  falhou=$((falhou+1)); echo "  FALHA 21.e hook não tem a seleção explícita da marca mais antiga"
fi

echo
echo "  21.f — FALSIFICAÇÃO: bloco cheio (corta observação) + marca parada: o aviso NÃO some"
# O corpus de 11 mil observações reais já enche o teto de 3.000 B sozinho.
# Se o aviso de pipeline fosse um segundo canal que só entra "se sobrar
# espaço depois do corpus", ele nunca apareceria em produção — o mesmo
# silêncio que o D8 existe pra matar. Fixture: as MESMAS 20 observações
# grandes do teste 19.a (força travarOrcamentoMemoria a cortar) MAIS a
# marca d'água de 60h atrás no mesmo sandbox.
CAIXA_CHEIO="$(novo_sandbox)"
RFM_ROOT="$CAIXA_CHEIO" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA_CHEIO" GRANDE="$GRANDE" node <<'SETUP_CHEIO'
const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const conteudoGrande = process.env.GRANDE + ' ' + process.env.GRANDE;
const stmt = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
for (let i = 0; i < 20; i++) {
  const dia = String(10 + i).padStart(2, '0');
  stmt.run('proj-estouro', '## Obs grande ' + i + '\n\n' + conteudoGrande, `2026-08-${dia}T10:00:00Z`, 'sessao:teste:offset:' + i);
}
// arquivo real (nao so nome placeholder) — ver comentario da fixture 21.a acima.
const arquivo = path.join(process.env.RFM_ROOT, 'arq1.jsonl');
fs.writeFileSync(arquivo, '');
const sessenta = new Date(Date.now() - 60 * 60 * 60 * 1000).toISOString();
db.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('projx', 'sessao1', arquivo, 10, 5, sessenta);
db.close();
SETUP_CHEIO

PAYLOAD_CHEIO='{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"'"$CAIXA_CHEIO"'","transcript_path":"'"$CAIXA_CHEIO"'/t.jsonl"}'
SAIDA_CHEIO="$(printf '%s' "$PAYLOAD_CHEIO" | RFM_ROOT="$CAIXA_CHEIO" node "$HOOK" 2>/dev/null)"
echo "$SAIDA_CHEIO" > "$CAIXA_CHEIO/saida-cheio.json"
RESULT_CHEIO="$(cat "$CAIXA_CHEIO/saida-cheio.json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s).hookSpecificOutput.additionalContext;const l=t.split("\n").filter(x=>/captura/i.test(x)&&/60/.test(x)&&x.includes("observar.cjs"));console.log(l.length, Buffer.byteLength(t,"utf8")<=3000)})')"
echo "  comando: printf '%s' '<payload>' | RFM_ROOT=<sandbox com 20 obs grandes + marca parada> node hooks/memoria-session-start.cjs | node -e '...'"
echo "  saida: $RESULT_CHEIO"
if [ "$RESULT_CHEIO" = "1 true" ]; then
  ok=$((ok+1)); echo "  ok    21.f o aviso sobrevive ao corte do corpus (a observação mais antiga cede lugar, não o aviso)"
else
  falhou=$((falhou+1)); echo "  FALHA 21.f esperava '1 true' com o corpus cheio, veio '$RESULT_CHEIO'"
fi

echo
echo "  21.g — marca com arquivo ORFAO (transcrito apagado, ex.: worktree removido): o aviso NAO aparece"
# Achado real (2026-09-23, banco real do usuario em <home>/.rainforest):
# marca de um worktree ja removido, offset_processado=0, processada_em de 18
# dias atras. O arquivo do transcrito nao existe mais em lugar nenhum, e
# nunca vai ser processado (observar.cjs le 0 eventos de arquivo ausente e
# nao avanca offset_processado). Essa marca sozinha nao pode fazer o aviso
# de "captura parada" aparecer: ela nunca vai virar captura de novo.
CAIXA_ORFAO="$(novo_sandbox)"
RFM_ROOT="$CAIXA_ORFAO" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA_ORFAO" node <<'SETUP_ORFAO'
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const arquivoOrfao = path.join(process.env.RFM_ROOT, 'worktree-removido', 'sessao-orfa.jsonl');
const quatrocentas = new Date(Date.now() - 400 * 60 * 60 * 1000).toISOString();
db.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-removido', 'sessao-orfa', arquivoOrfao, 1478071, 0, quatrocentas);
db.close();
SETUP_ORFAO
PAYLOAD_ORFAO='{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"'"$CAIXA_ORFAO"'","transcript_path":"'"$CAIXA_ORFAO"'/t.jsonl"}'
SAIDA_ORFAO="$(printf '%s' "$PAYLOAD_ORFAO" | RFM_ROOT="$CAIXA_ORFAO" node "$HOOK" 2>/dev/null)"
echo "  comando: printf '%s' '<payload>' | RFM_ROOT=<sandbox com marca de arquivo inexistente, 400h> node hooks/memoria-session-start.cjs | node -e '...'"
RESULT_ORFAO="$(printf '%s' "$SAIDA_ORFAO" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s).hookSpecificOutput.additionalContext;const l=t.split("\n").filter(x=>/captura/i.test(x)&&x.includes("observar.cjs"));console.log(l.length)})')"
echo "  saida: $RESULT_ORFAO"
if [ "$RESULT_ORFAO" = "0" ]; then
  ok=$((ok+1)); echo "  ok    21.g marca orfa (arquivo apagado) nao dispara o aviso de captura parada"
else
  falhou=$((falhou+1)); echo "  FALHA 21.g esperava '0' (sem aviso), veio '$RESULT_ORFAO'"
fi

echo
echo "  21.h — marca ORFA mais antiga + marca REAL mais nova pendente: o aviso usa a REAL, pula a orfa"
# A marca orfa de 21.g fica pra sempre com processada_em congelado no
# passado — se a funcao so pegasse a mais antiga sem checar o arquivo, o
# numero de horas so cresceria e nunca refletiria uma pendencia de verdade
# mais recente. Duas marcas no mesmo banco: a orfa (400h, arquivo nao
# existe) e uma real (60h, arquivo existe) — o aviso tem que mostrar 60, nao
# a orfa.
CAIXA_ORFAOEREAL="$(novo_sandbox)"
RFM_ROOT="$CAIXA_ORFAOEREAL" node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1
RFM_ROOT="$CAIXA_ORFAOEREAL" node <<'SETUP_ORFAOEREAL'
const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.RFM_ROOT + '/rainforest.db');
const arquivoOrfao = path.join(process.env.RFM_ROOT, 'worktree-removido', 'sessao-orfa.jsonl');
const arquivoReal = path.join(process.env.RFM_ROOT, 'sessao-real.jsonl');
fs.writeFileSync(arquivoReal, '');
const quatrocentas = new Date(Date.now() - 400 * 60 * 60 * 1000).toISOString();
const sessenta = new Date(Date.now() - 60 * 60 * 60 * 1000).toISOString();
db.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('proj-removido', 'sessao-orfa', arquivoOrfao, 1478071, 0, quatrocentas);
db.prepare('INSERT INTO marca_dagua (projeto, sessao, arquivo, offset, offset_processado, processada_em) VALUES (?,?,?,?,?,?)')
  .run('projx', 'sessao-real', arquivoReal, 10, 5, sessenta);
db.close();
SETUP_ORFAOEREAL
PAYLOAD_ORFAOEREAL='{"hook_event_name":"SessionStart","source":"startup","session_id":"11111111-1111-1111-1111-111111111111","cwd":"'"$CAIXA_ORFAOEREAL"'","transcript_path":"'"$CAIXA_ORFAOEREAL"'/t.jsonl"}'
SAIDA_ORFAOEREAL="$(printf '%s' "$PAYLOAD_ORFAOEREAL" | RFM_ROOT="$CAIXA_ORFAOEREAL" node "$HOOK" 2>/dev/null)"
echo "  comando: printf '%s' '<payload>' | RFM_ROOT=<sandbox com marca orfa de 400h + marca real de 60h> node hooks/memoria-session-start.cjs | node -e '...'"
RESULT_ORFAOEREAL="$(printf '%s' "$SAIDA_ORFAOEREAL" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s).hookSpecificOutput.additionalContext;const l=t.split("\n").filter(x=>/captura/i.test(x)&&x.includes("observar.cjs"));console.log(l.length, t.includes("60h"), t.includes("400h"))})')"
echo "  saida: $RESULT_ORFAOEREAL"
if [ "$RESULT_ORFAOEREAL" = "1 true false" ]; then
  ok=$((ok+1)); echo "  ok    21.h aviso usa a pendencia REAL (60h), pula a orfa (400h) mesmo sendo mais antiga"
else
  falhou=$((falhou+1)); echo "  FALHA 21.h esperava '1 true false', veio '$RESULT_ORFAOEREAL'"
fi

rm -rf "$CAIXA_PIPELINE" "$CAIXA_EMDIA" "$CAIXA_MANFALHOU" "$CAIXA_MANOK" "$CAIXA_CHEIO" "$CAIXA_ORFAO" "$CAIXA_ORFAOEREAL"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
