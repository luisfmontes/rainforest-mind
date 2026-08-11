#!/bin/bash
# Bateria do jornada.cjs. Roda numa caixa de areia com transcripts SINTETICOS,
# montados aqui — nada depende dos transcripts reais do Luis (que mudam a cada
# sessao e nao servem de fixture estavel). Uso: bash scripts/testa-jornada.sh
#
# O teste que importa e o de mutacao, no bloco final: ele desliga o filtro de
# mensagem humana (a armadilha #1 do cabecalho de jornada.py/jornada.cjs) e
# exige que a contagem exploda. Sem ele, os demais provariam so que o caminho
# feliz funciona — um filtro que nunca foi visto filtrando nao e evidencia de
# nada (regra 12).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)/sandbox"
trap 'rm -rf "$(dirname "$SB")"' EXIT
mkdir -p "$SB"
cd "$SB" || exit 1

# Caminho em forma WINDOWS: o node nativo (fora do Git Bash) nao resolve
# "/c/Projetos/..." — precisa de "C:/Projetos/...". So importa para o bloco 3
# (USERPROFILE), mas fica calculado aqui uma vez.
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
SB_WIN="$(cygpath -m "$SB" 2>/dev/null || printf '%s' "$SB")"

JORNADA="node $SRC_WIN/scripts/jornada.cjs"

ok=0; falhou=0
checa() { # nome, comando-completo-como-string (roda em bash -c), padrao grep esperado no stdout+stderr
  local nome="$1" padrao="$2" cmd="$3"
  local saida; saida=$(bash -c "$cmd" 2>&1)
  if echo "$saida" | grep -q -- "$padrao"
  then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome (esperava conter: $padrao)"; echo "$saida" | sed 's/^/         /'
  fi
}
naocheca() { # nome, padrao que NAO pode aparecer, comando
  local nome="$1" padrao="$2" cmd="$3"
  local saida; saida=$(bash -c "$cmd" 2>&1)
  if echo "$saida" | grep -q -- "$padrao"
  then falhou=$((falhou+1)); echo "  FALHA $nome (nao devia conter: $padrao)"; echo "$saida" | sed 's/^/         /'
  else ok=$((ok+1)); echo "  ok   $nome"
  fi
}

echo "== 1. filtro de mensagem humana: toolUseResult nao conta =="
cat > tool.jsonl <<'EOF'
{"type":"user","timestamp":"2026-08-11T10:00:00.000Z","message":{"role":"user"}}
{"type":"user","toolUseResult":{"ok":true},"timestamp":"2026-08-11T10:01:00.000Z"}
{"type":"user","timestamp":"2026-08-11T10:10:00.000Z","message":{"role":"user"}}
EOF
checa "so as 2 mensagens humanas contam (toolUseResult descartado)" '"mensagens":2' \
  "$JORNADA --transcript tool.jsonl --json"

echo
echo "== 2. filtro de mensagem humana: isMeta e isCompactSummary nao contam =="
cat > meta.jsonl <<'EOF'
{"type":"user","timestamp":"2026-08-11T10:00:00.000Z","message":{"role":"user"}}
{"type":"user","isMeta":true,"timestamp":"2026-08-11T10:01:00.000Z"}
{"type":"user","timestamp":"2026-08-11T10:10:00.000Z","message":{"role":"user"}}
EOF
checa "isMeta descartado (mensagens=2)" '"mensagens":2' "$JORNADA --transcript meta.jsonl --json"

cat > resumo.jsonl <<'EOF'
{"type":"user","timestamp":"2026-08-11T10:00:00.000Z","message":{"role":"user"}}
{"type":"user","isCompactSummary":true,"timestamp":"2026-08-11T10:01:00.000Z"}
{"type":"assistant","timestamp":"2026-08-11T10:05:00.000Z"}
{"type":"user","timestamp":"2026-08-11T10:10:00.000Z","message":{"role":"user"}}
EOF
checa "isCompactSummary e type!=user descartados (mensagens=2)" '"mensagens":2' \
  "$JORNADA --transcript resumo.jsonl --json"

echo
echo "== 3. carimbo Z vira hora LOCAL antes de qualquer comparacao (virada do dia) =="
# Referencia: meia-noite LOCAL de 2026-01-15, calculada pelo proprio relogio da
# maquina (nao hardcoded em -03:00) - e onde a conversao UTC->local pode empurrar
# uma mensagem para o dia ERRADO se for feita tarde demais ou nunca.
BOUNDARY_MS=$(node -e "console.log(new Date(2026,0,15,0,0,0).getTime())")
# Duas mensagens de cada lado (nao uma so): com 1 mensagem so no escopo do dia,
# jornada.py (e por parity o .cjs) tentam isoformat() num "ultimo" None e
# lancam excecao - bug PRE-EXISTENTE no original, fora do escopo desta tarefa
# (o port preserva os mesmos numeros, inclusive esse). Duas mensagens por lado
# evita pisar nessa lacuna conhecida e mantem o teste focado so na conversao
# UTC->local.
TS_ANTES=$(node -e "console.log(new Date($BOUNDARY_MS - 3600000).toISOString())")   # 1h antes da meia-noite local -> dia 14
TS_ANTES2=$(node -e "console.log(new Date($BOUNDARY_MS - 7200000).toISOString())")  # 2h antes -> dia 14 tambem
TS_DEPOIS=$(node -e "console.log(new Date($BOUNDARY_MS + 3600000).toISOString())")  # 1h depois -> dia 15
TS_DEPOIS2=$(node -e "console.log(new Date($BOUNDARY_MS + 7200000).toISOString())") # 2h depois -> dia 15 tambem
echo "  (meia-noite local de 2026-01-15 = ${BOUNDARY_MS}ms UTC; antes=$TS_ANTES/$TS_ANTES2 depois=$TS_DEPOIS/$TS_DEPOIS2)"

mkdir -p "$SB/fakehome/.claude/projects/proj1"
cat > "$SB/fakehome/.claude/projects/proj1/sessao.jsonl" <<EOF
{"type":"user","timestamp":"$TS_ANTES2","message":{"role":"user"}}
{"type":"user","timestamp":"$TS_ANTES","message":{"role":"user"}}
{"type":"user","timestamp":"$TS_DEPOIS","message":{"role":"user"}}
{"type":"user","timestamp":"$TS_DEPOIS2","message":{"role":"user"}}
EOF

checa "1h/2h antes da meia-noite local caem no dia 14 (nao no 15)" '"mensagens":2' \
  "USERPROFILE='$SB_WIN/fakehome' $JORNADA --dia 2026-01-14 --json"
checa "1h/2h depois da meia-noite local caem no dia 15 (nao sobrou no 14)" '"mensagens":2' \
  "USERPROFILE='$SB_WIN/fakehome' $JORNADA --dia 2026-01-15 --json"
checa "dia 14 nao contem a mensagem de depois da virada" '"escopo":"dia 2026-01-14' \
  "USERPROFILE='$SB_WIN/fakehome' $JORNADA --dia 2026-01-14 --json"

echo
echo "== 4. lacuna acima do corte sai da conta e e listada; abaixo fica =="
cat > gaps.jsonl <<'EOF'
{"type":"user","timestamp":"2026-01-01T12:00:00.000Z","message":{"role":"user"}}
{"type":"user","timestamp":"2026-01-01T12:30:00.000Z","message":{"role":"user"}}
{"type":"user","timestamp":"2026-01-01T13:40:00.000Z","message":{"role":"user"}}
EOF
# gaps: 30 min (abaixo do corte padrao 55, fica) e 70 min (acima, descartada)
checa "corte padrao (55): efetiva conta so os 30 min" '"efetiva_min":30' \
  "$JORNADA --transcript gaps.jsonl --json"
checa "corte padrao (55): a lacuna de 70 min e listada em descartadas" '"min":70' \
  "$JORNADA --transcript gaps.jsonl --json"
checa "corte padrao (55): bruto continua ponta a ponta (100 min)" '"bruto_min":100' \
  "$JORNADA --transcript gaps.jsonl --json"
checa "corte 75: a lacuna de 70 min fica ABAIXO do corte, some da lista" '"descartadas":\[\]' \
  "$JORNADA --transcript gaps.jsonl --corte 75 --json"
checa "corte 75: efetiva agora inclui os 70 min (soma 100)" '"efetiva_min":100' \
  "$JORNADA --transcript gaps.jsonl --corte 75 --json"

echo
echo "== 5. --sem-descarte faz a efetiva igualar o bruto =="
checa "sem-descarte: efetiva=100 (igual ao bruto, a lacuna de 70 nao e descartada)" '"efetiva_min":100' \
  "$JORNADA --transcript gaps.jsonl --sem-descarte --json"
checa "sem-descarte: nenhuma lacuna listada (nada e descartado)" '"descartadas":\[\]' \
  "$JORNADA --transcript gaps.jsonl --sem-descarte --json"

echo
echo "== 6. MUTACAO: desligar o filtro de mensagem humana explode a contagem =="
# Fixture com 2 mensagens humanas de verdade e 20 toolUseResult (type "user",
# mas SEM presenca humana nenhuma) - o caso real medido no cabecalho: 377
# entradas "user", so 42 humanas.
{
  echo '{"type":"user","timestamp":"2026-08-11T09:00:00.000Z","message":{"role":"user"}}'
  for i in $(seq 1 20); do
    printf '{"type":"user","toolUseResult":{"n":%d},"timestamp":"2026-08-11T09:%02d:00.000Z"}\n' "$i" "$i"
  done
  echo '{"type":"user","timestamp":"2026-08-11T09:59:00.000Z","message":{"role":"user"}}'
} > mutacao.jsonl

checa "SEM mutante: filtro liga e conta so as 2 humanas" '"mensagens":2' \
  "$JORNADA --transcript mutacao.jsonl --json"

cp "$SRC/scripts/jornada.cjs" "$SB/mutante.cjs"
node -e '
const fs = require("fs");
const p = process.argv[1];
let s = fs.readFileSync(p, "utf-8");
const alvo = "if (Object.prototype.hasOwnProperty.call(d, \"toolUseResult\") || d.isMeta || d.isCompactSummary) {";
if (!s.includes(alvo)) { console.error("ancora da mutacao sumiu em " + p + " - o teste precisa ser reajustado"); process.exit(1); }
s = s.replace(alvo, "if (false) {");
fs.writeFileSync(p, s);
console.log("  (mutante instalado: o filtro de toolUseResult/isMeta/isCompactSummary nunca dispara)");
' "$SB_WIN/mutante.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao foi possivel instalar o mutante (ancora sumiu)"; fi

checa "COM mutante: a contagem explode (22, todas as toolUseResult contadas)" '"mensagens":22' \
  "node '$SB_WIN/mutante.cjs' --transcript mutacao.jsonl --json"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
