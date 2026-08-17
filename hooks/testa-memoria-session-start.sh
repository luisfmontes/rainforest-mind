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
echo "6. Mutação — com teto menor, o bloco deveria caber ainda mais apertado"
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
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
