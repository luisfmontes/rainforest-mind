#!/bin/bash
# Bateria do destino `mod` do hook de foco (`foco-session-start.cjs --destino mod`).
# Uso: bash hooks/testa-abertura-mod-foco.sh
#
# O que precisa provar, nesta ordem de importancia:
#   1. o destino mod entrega a ELABORACAO INTEIRA das quatro regras da config e o
#      FOCO.md inteiro, sem aviso de foco que nao coube nem marca de corte, dentro
#      do teto da config, com o cabecalho dizendo quais regras vem inteiras;
#   2. SEM a flag nada muda: a saida e identica (cmp) a do commit base d5d2a203,
#      montado por `git archive`, sobre os mesmos dados e o mesmo ambiente;
#   3. config recusada pela lib (e destino desconhecido) sai com exit != 0, stderr
#      e SEM JSON parcial no stdout;
#   4. FOCO.md que nao cabe no teto do mod nao e cortado em silencio.
#
# A mutacao (trocar a linha que liga os tetos do destino mod por `const tetos = TETOS;`
# em hooks/lib/contexto-sessao.cjs) e rodada por `scripts/conferir-mutacao.cjs`; o
# caso 1 precisa ficar vermelho.
#
# Os dados sao FIXTURE deterministica (FOCO.md CRLF de ~9 KB com secao fora das
# residentes e avancos que o resumo do hook costuma omitir): o FOCO.md real muda
# todo dia e uma bateria que depende dele passa e falha sem que ninguem a toque.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_GOLDEN="d5d2a203"

SANDBOXES=()
novo_sandbox() { local tmpdir; tmpdir=$(mktemp -d); SANDBOXES+=("$tmpdir"); echo "$tmpdir"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

mixto() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

ok=0; falhou=0
passa() { ok=$((ok+1)); echo "  ok    $1"; }
falha() { falhou=$((falhou+1)); echo "  FALHA $1"; }

# ---------------------------------------------------------------- ambiente fixo
BASE_POSIX="$(novo_sandbox)"
DADOS="$BASE_POSIX/dados"; PROJ="$BASE_POSIX/proj"; CFG="$BASE_POSIX/cfg"
mkdir -p "$DADOS" "$PROJ" "$CFG"
DADOS_M="$(mixto "$DADOS")"; PROJ_M="$(mixto "$PROJ")"; CFG_M="$(mixto "$CFG")"

# FOCO.md CRLF: ~9 KB, com "Concluidos" (secao nao residente) e 6 avancos longos.
node -e "
const fs = require('fs');
const L = [];
L.push('# Foco', '', '## Ativo', '', '**Foco de fixture** \`[trabalho]\` — declarado 2026-08-06.',
  'Ociosidade maxima: 15 min.', 'Criterio de pronto: a fixture exercita o destino mod.', '', 'Avanços:');
for (let i = 1; i <= 6; i++) {
  L.push('- 2026-09-0' + i + ' (fixture): **avanco ' + i + ' com texto longo o bastante para o resumo do hook omitir.**');
  for (let j = 0; j < 5; j++) L.push('  linha ' + j + ' do avanco ' + i + ' ' + 'x'.repeat(78));
}
L.push('', '## Compromissos com prazo', '', '- **Entrega de fixture ate 2026-12-31** — compromisso residente.', '',
  '## Concluídos', '');
for (let i = 1; i <= 12; i++) L.push('- concluido ' + i + ' (fixture) ' + 'y'.repeat(90));
L.push('- ULTIMA-LINHA-DO-FOCO-FIXTURE');
fs.writeFileSync(process.argv[1], L.join('\r\n') + '\r\n');
" "$DADOS_M/FOCO.md"
ULTIMA_FOCO="ULTIMA-LINHA-DO-FOCO-FIXTURE"

# Roda um hook com o ambiente fixo; $1 = raiz do plugin (posix), demais = argumentos.
# Bridge vazia = nao declarada (sem sonda de rede); config dir isolado (sem plugins lidos).
rodar_hook() {
  local raiz="$1"; shift
  WHATSAPP_API_BASE_URL= RFM_ROOT="$DADOS_M" CLAUDE_PROJECT_DIR="$PROJ_M" \
    CLAUDE_CONFIG_DIR="$CFG_M" RFM_SETTINGS_PATH="$CFG_M/settings.json" \
    node "$(mixto "$raiz")/hooks/foco-session-start.cjs" "$@"
}

# Campo do JSON do stdout: campo <arquivo> <additionalContext|systemMessage>
campo() {
  node -e "
const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
const v = process.argv[2] === 'systemMessage' ? j.systemMessage : j.hookSpecificOutput.additionalContext;
process.stdout.write(v == null ? '' : String(v));
" "$(mixto "$1")" "$2"
}

# ------------------------------------------------------------- 1. destino mod
echo "1. destino mod entrega as regras e o foco inteiros"
OUT_MOD="$BASE_POSIX/mod.json"; ERR_MOD="$BASE_POSIX/mod.err"
rodar_hook "$SRC" --destino mod > "$OUT_MOD" 2> "$ERR_MOD"; COD_MOD=$?
campo "$OUT_MOD" additionalContext > "$BASE_POSIX/mod.txt" 2>/dev/null
TXT_MOD="$BASE_POSIX/mod.txt"
BYTES_MOD=$(wc -c < "$TXT_MOD" | tr -d ' ')
[ "$COD_MOD" = "0" ] && passa "o hook com --destino mod sai com exit 0" || falha "o hook com --destino mod saiu com exit $COD_MOD: $(head -c 300 "$ERR_MOD")"

FALTAS=$(node -e "
const fs = require('fs');
const c = fs.readFileSync(process.argv[1], 'utf8');
const faltas = [];
for (const n of [16, 12, 11, 17]) {
  const arq = process.argv[2] + '/skills/rainforest-mind/references/regra-' + String(n).padStart(2, '0') + '.md';
  const linhas = fs.readFileSync(arq, 'utf8').replace(/\r\n/g, '\n').split('\n').filter((l) => l.trim());
  if (!c.includes(linhas[0])) faltas.push('primeira linha da regra ' + n);
  if (!c.includes(linhas[linhas.length - 1])) faltas.push('ultima linha da regra ' + n);
}
const foco = fs.readFileSync(process.argv[3], 'utf8').replace(/\r\n/g, '\n').trim();
if (!c.includes(foco)) faltas.push('FOCO.md inteiro');
if (c.includes('O foco não coube')) faltas.push('aviso \"O foco nao coube\"');
if (/truncado no teto|INJEÇÃO ACIMA DO ORÇAMENTO/.test(c)) faltas.push('marca de corte');
if (Buffer.byteLength(c) > 53248) faltas.push('mais de 53248 B (' + Buffer.byteLength(c) + ')');
process.stdout.write(faltas.join('; '));
" "$(mixto "$TXT_MOD")" "$(mixto "$SRC")" "$(mixto "$DADOS/FOCO.md")" 2>&1)
if [ "$COD_MOD" = "0" ] && [ -z "$FALTAS" ]; then
  passa "destino mod entrega a elaboração inteira das quatro regras (16, 12, 11, 17), o FOCO.md inteiro e cabe em 53248 B ($BYTES_MOD B)"
else
  falha "destino mod entrega a elaboração inteira das quatro regras: faltou/sobrou -> ${FALTAS:-saida ilegivel}"
fi

CAB_MOD="$(head -n 6 "$TXT_MOD")"
case "$CAB_MOD" in
  *"Isto é o NÚCLEO"*) falha "o cabecalho do mod ainda diz \"Isto é o NÚCLEO\"" ;;
  *"regras 16, 12, 11, 17 vêm INTEIRAS"*) passa "o cabecalho nomeia as regras que vem inteiras e nao diz mais \"Isto é o NÚCLEO\"" ;;
  *) falha "o cabecalho do mod nao nomeia as regras inteiras: $(echo "$CAB_MOD" | head -c 300)" ;;
esac

# Controle (alarme falso): a fixture TEM de exercitar o desvio do resumo. Sem a flag
# o resumo omite a secao Concluidos e o ultimo avanco; se nao omitisse, o caso 1 nao
# provaria que o mod entrega "inteiro".
OUT_SEM="$BASE_POSIX/sem.json"
rodar_hook "$SRC" > "$OUT_SEM" 2>/dev/null
campo "$OUT_SEM" additionalContext > "$BASE_POSIX/sem.txt" 2>/dev/null
if grep -q "$ULTIMA_FOCO" "$BASE_POSIX/sem.txt"; then
  falha "controle: sem a flag a fixture ja traz o FOCO.md inteiro (ela nao exercita o resumo)"
else
  passa "controle: sem a flag o resumo omite o fim do FOCO.md (a fixture exercita o destino mod)"
fi

# ------------------------------------------------------- 2. sem a flag = golden
echo
echo "2. sem a flag, a saida e identica ao commit base $BASE_GOLDEN"
GOLD_POSIX="$(novo_sandbox)"
if (cd "$SRC" && git archive "$BASE_GOLDEN" hooks scripts skills) | tar -x -C "$GOLD_POSIX"; then
  passa "golden montado por git archive $BASE_GOLDEN (hooks scripts skills)"
else
  falha "nao consegui montar o golden com git archive $BASE_GOLDEN"
fi
OUT_GOLD="$BASE_POSIX/gold.json"
rodar_hook "$GOLD_POSIX" > "$OUT_GOLD" 2>/dev/null; COD_GOLD=$?
[ "$COD_GOLD" = "0" ] && passa "o hook do golden roda (exit 0)" || falha "o hook do golden saiu com exit $COD_GOLD"

# O unico texto que difere por construcao e a raiz do plugin (a abertura cita
# `<raiz>/skills/.../references`): troca-se a raiz de cada lado por <RAIZ> antes do cmp.
normalizar() {
  node -e "
const fs = require('fs');
const raiz = process.argv[2];
const formas = [raiz, raiz.replace(/\//g, '\\\\')];
// O aviso de revisao vencida tambem difere por construcao: depende do RELOGIO e
// da data de revisao de cada lado. Em 2026-10-08 o golden cruzou os 60 dias e a
// bateria ficou vermelha sozinha, na main, sem diff nenhum — sai dos dois lados.
// So ASCII no padrao: este node -e recebe o texto pela linha de comando do
// Windows, e acento ali chega trocado e o padrao nunca casa.
const semRevisao = (t) => t.replace(/\n[^\n]*A skill rainforest-mind [^\n]*\(limite: 60\)[^\n]*\n/g, '');
const norm = (v) => typeof v === 'string' ? semRevisao(formas.reduce((t, f) => t.split(f).join('<RAIZ>'), v)) : v;
const j = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
j.hookSpecificOutput.additionalContext = norm(j.hookSpecificOutput.additionalContext);
if (j.systemMessage != null) j.systemMessage = norm(j.systemMessage);
process.stdout.write(JSON.stringify(j) + '\n');
" "$(mixto "$1")" "$(mixto "$2")"
}
normalizar "$OUT_SEM" "$SRC" > "$BASE_POSIX/sem.norm"
normalizar "$OUT_GOLD" "$GOLD_POSIX" > "$BASE_POSIX/gold.norm"
if [ -s "$BASE_POSIX/sem.norm" ] && cmp -s "$BASE_POSIX/sem.norm" "$BASE_POSIX/gold.norm"; then
  passa "sem a flag o stdout do HEAD e identico (cmp) ao do $BASE_GOLDEN ($(wc -c < "$BASE_POSIX/gold.norm" | tr -d ' ') B, raiz do plugin normalizada)"
else
  falha "sem a flag o stdout difere do golden $BASE_GOLDEN: $(cmp "$BASE_POSIX/sem.norm" "$BASE_POSIX/gold.norm" 2>&1 | head -c 200)"
fi
grep -q "Elaboração inteira" "$BASE_POSIX/sem.txt" \
  && falha "sem a flag a abertura traz a secao de elaboracao inteira" \
  || passa "sem a flag a abertura nao traz a secao de elaboracao inteira"

# ------------------------------------------------------- 3. config recusada
echo
echo "3. config recusada ou destino desconhecido: exit != 0, stderr, sem JSON parcial"
COPIA_POSIX="$(novo_sandbox)"
cp -r "$SRC/hooks" "$SRC/skills" "$COPIA_POSIX/"
# controle: a copia, com a config intacta, FUNCIONA (a recusa abaixo vem da config)
rodar_hook "$COPIA_POSIX" --destino mod > "$BASE_POSIX/copia-ok.json" 2>/dev/null; COD=$?
[ "$COD" = "0" ] && [ -s "$BASE_POSIX/copia-ok.json" ] \
  && passa "controle: a copia do plugin com a config intacta entrega (exit 0)" \
  || falha "controle: a copia do plugin com a config intacta falhou (exit $COD)"
node -e "
const fs = require('fs');
const p = process.argv[1];
const c = JSON.parse(fs.readFileSync(p, 'utf8'));
c.elaboracoes = [16, 12, 11, 99];
fs.writeFileSync(p, JSON.stringify(c));
" "$(mixto "$COPIA_POSIX/hooks/abertura-mod.json")"
rodar_hook "$COPIA_POSIX" --destino mod > "$BASE_POSIX/rec.out" 2> "$BASE_POSIX/rec.err"; COD=$?
if [ "$COD" != "0" ] && [ ! -s "$BASE_POSIX/rec.out" ] && grep -q "99" "$BASE_POSIX/rec.err"; then
  passa "config recusada pela lib (regra 99 sem arquivo): exit $COD, stderr diz a regra, stdout vazio"
else
  falha "config recusada: exit=$COD, stdout $(wc -c < "$BASE_POSIX/rec.out" | tr -d ' ') B, stderr '$(head -c 200 "$BASE_POSIX/rec.err")'"
fi
rodar_hook "$SRC" --destino outro > "$BASE_POSIX/dest.out" 2> "$BASE_POSIX/dest.err"; COD=$?
if [ "$COD" != "0" ] && [ ! -s "$BASE_POSIX/dest.out" ] && [ -s "$BASE_POSIX/dest.err" ]; then
  passa "destino desconhecido: exit $COD, stderr nao vazio, stdout vazio"
else
  falha "destino desconhecido: exit=$COD, stdout $(wc -c < "$BASE_POSIX/dest.out" | tr -d ' ') B, stderr '$(head -c 200 "$BASE_POSIX/dest.err")'"
fi

# ---------------------------------------- 4. FOCO.md acima do teto nao e cortado calado
echo
echo "4. FOCO.md maior que o teto de foco do mod nao e cortado em silencio"
GRANDE_POSIX="$(novo_sandbox)"
node -e "
const fs = require('fs');
const L = ['# Foco', '', '## Ativo', '', '**Foco gigante** \`[trabalho]\`.', 'Ociosidade maxima: 15 min.', ''];
for (let i = 0; i < 400; i++) L.push('- linha ' + i + ' ' + 'z'.repeat(60));
L.push('', '## Concluídos', '', '- FIM-DO-FOCO-GIGANTE');
fs.writeFileSync(process.argv[1], L.join('\n') + '\n');
" "$(mixto "$GRANDE_POSIX")/FOCO.md"
WHATSAPP_API_BASE_URL= RFM_ROOT="$(mixto "$GRANDE_POSIX")" CLAUDE_PROJECT_DIR="$PROJ_M" \
  CLAUDE_CONFIG_DIR="$CFG_M" RFM_SETTINGS_PATH="$CFG_M/settings.json" \
  node "$(mixto "$SRC")/hooks/foco-session-start.cjs" --destino mod > "$BASE_POSIX/grande.json" 2>/dev/null; COD=$?
campo "$BASE_POSIX/grande.json" additionalContext > "$BASE_POSIX/grande.txt" 2>/dev/null
BYTES_G=$(wc -c < "$BASE_POSIX/grande.txt" | tr -d ' ')
if [ "$COD" = "0" ] && [ "$BYTES_G" -le 53248 ] && ! grep -q "FIM-DO-FOCO-GIGANTE" "$BASE_POSIX/grande.txt" \
   && grep -q "omitidas\|Fora desta injeção\|truncado\|não coube\|só ponteiros" "$BASE_POSIX/grande.txt"; then
  passa "foco que nao cabe: o fim fica de fora, a abertura avisa e fica em $BYTES_G B (<= 53248)"
else
  falha "foco que nao cabe: exit=$COD, $BYTES_G B, sem aviso de omissao ou estourou o teto"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou   skipped: 0"
if [ "$falhou" = "0" ]; then echo "bateria passou"; else exit 1; fi
