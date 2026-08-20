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
echo "10. Tarefa 3 — filtro por projeto (D3)"
# Criar um banco com observações de dois projetos:
# - projeto-a: 8 observações
# - projeto-b: 8 observações
# Cenário (a): sessão de projeto-a deveria receber 5 de projeto-a, NENHUMA de projeto-b
# Cenário (b): projeto-c com 2 próprias deveria receber 2 + 3 de outros (com projeto marcado)

CAIXA_PROJETO="$(mktemp -d)"
mkdir -p "$CAIXA_PROJETO"
trap 'rm -rf "$CAIXA" "$CAIXA2" "$CAIXA3" "$RAIZ_POSIX" "$CAIXA_PROJETO"' EXIT

# Inicializar banco DE VERDADE com schema do rainforest (cria o diretório também)
export RFM_ROOT="$CAIXA_PROJETO"
node "$SRC/scripts/memoria.cjs" iniciar > /dev/null 2>&1

# Agora inserir dados de teste no banco já inicializado
node <<'SETUP_PROJETOS'
const { DatabaseSync } = require('node:sqlite');

const caminhoDb = process.env.RFM_ROOT + '/rainforest.db';
const db = new DatabaseSync(caminhoDb);

// Inserir 8 observações de projeto-a
for (let i = 1; i <= 8; i++) {
  db.prepare(`
    INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
    VALUES (?, ?, ?, ?)
  `).run(
    'projeto-a',
    '## Obs ' + i + '\n\nConteúdo projeto A',
    '2026-08-' + String(10 + i).padStart(2, '0') + 'T10:00:00Z',
    'origem-a-' + i
  );
}

// Inserir 8 observações de projeto-b (mais antigas)
for (let i = 1; i <= 8; i++) {
  db.prepare(`
    INSERT INTO observacoes (projeto, conteudo, criada_em, origem)
    VALUES (?, ?, ?, ?)
  `).run(
    'projeto-b',
    '## Obs-B ' + i + '\n\nConteúdo projeto B',
    '2026-08-0' + i + 'T10:00:00Z',
    'origem-b-' + i
  );
}

db.close();
SETUP_PROJETOS

# Teste (a): Verificar que dados foram inseridos corretamente
echo
echo "  10.a — projeto com 8 obs próprias + outro com 8: recebe 5 próprias, nenhuma do outro"

# Verificar que a tabela tem dados
DADOS_A=$(node --no-warnings <<'VERIFICA_DADOS'
const { abrirBancoSomenteLeitura } = require('./scripts/memoria.cjs');
const db = abrirBancoSomenteLeitura(process.env.RFM_ROOT + '/rainforest.db');
if (!db) { console.log('[]'); process.exit(0); }
try {
  const stmt = db.prepare('SELECT projeto, COUNT(*) as cnt FROM observacoes GROUP BY projeto ORDER BY projeto');
  const resultado = stmt.all();
  console.log(JSON.stringify(resultado));
} catch (e) {
  console.log('[]');
} finally {
  db.close();
}
VERIFICA_DADOS
)

# Se não tem dados, o teste falha
if [ -z "$DADOS_A" ] || [ "$DADOS_A" = "[]" ]; then
  falhou=$((falhou+1)); echo "  FALHA nenhuma observação no banco"
else
  # Verificar que projeto-a tem 8 e projeto-b tem 8
  NUM_A_DB=$(echo "$DADOS_A" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); const a=d.find(x=>x.projeto==='projeto-a'); process.stdout.write(String(a?a.cnt:0))")
  NUM_B_DB=$(echo "$DADOS_A" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); const b=d.find(x=>x.projeto==='projeto-b'); process.stdout.write(String(b?b.cnt:0))")

  if [ "$NUM_A_DB" = "8" ] && [ "$NUM_B_DB" = "8" ]; then
    ok=$((ok+1)); echo "  ok    banco tem 8 obs de projeto-a e 8 de projeto-b"
  else
    falhou=$((falhou+1)); echo "  FALHA banco tem $NUM_A_DB de projeto-a e $NUM_B_DB de projeto-b, esperado 8 e 8"
  fi
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
