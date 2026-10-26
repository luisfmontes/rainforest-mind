#!/bin/bash
# Bateria do foco opcional (2.0.0, D2 a D4 e D9 de
# docs/rainforest/design/2026-10-25-versao-2-0-0.md; tarefa 1 do plano
# docs/rainforest/planos/2026-10-25-versao-2-0-0.md).
# Uso: bash hooks/testa-foco-opcional.sh
#
# O que precisa provar:
#   1. com `{"foco": true}` no config.json da caixa, a abertura (additionalContext e
#      systemMessage, destinos padrao e mod) e identica (cmp) a do hook de dc88603a,
#      montado por `git archive` — a referencia e o codigo de ANTES, nunca um golden
#      gravado depois da mudanca;
#   2. sem config, e com config ilegivel, a abertura nao traz nada do foco, tira as
#      regras 3, 8 e 17 sem renumerar as outras, e a legenda nao fala de foco nem de janelas;
#   3. no destino mod sem foco, a elaboracao da regra 17 nao vem.
#
# Tudo numa caixa mktemp -d com RFM_ROOT: o config.json real nunca e lido nem escrito.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_GOLDEN="dc88603a"

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
# Fora de repo a abertura ganha o aviso de #565; o projeto da caixa e um repo git.
git init -q "$PROJ"
DADOS_M="$(mixto "$DADOS")"; PROJ_M="$(mixto "$PROJ")"; CFG_M="$(mixto "$CFG")"

# FOCO.md com foco ativo, prazo e pastas; sessoes.json com uma janela parada esperando.
printf '%s\n' '# Foco' '' '## Ativo' '' '**Foco de fixture do foco opcional** `[trabalho]` — declarado 2026-10-01.' \
  'Ociosidade máxima: 15 min.' 'Pastas: C:/fixture-foco' '' '## Compromissos com prazo' '' \
  '- **Entrega de fixture até 2026-12-31** — compromisso residente.' > "$DADOS/FOCO.md"
: > "$DADOS/ideias.jsonl"
node -e "
const agora = Date.now();
require('fs').writeFileSync(process.argv[1], JSON.stringify({
  's-outra': { cwd: 'C:/fixture-outra-janela', prompt_ts: agora - 40 * 60000, stop_ts: agora - 30 * 60000 },
}));
" "$DADOS_M/sessoes.json"

config() { # <conteudo do config.json da caixa, ou - para apagar>
  if [ "$1" = "-" ]; then rm -f "$DADOS/config.json"; else printf '%s' "$1" > "$DADOS/config.json"; fi
}

# Roda um hook com o ambiente fixo; $1 = raiz do plugin (posix), demais = argumentos.
rodar_hook() {
  local raiz="$1"; shift
  WHATSAPP_API_BASE_URL= RFM_ROOT="$DADOS_M" CLAUDE_PROJECT_DIR="$PROJ_M" \
    CLAUDE_CONFIG_DIR="$CFG_M" RFM_SETTINGS_PATH="$CFG_M/settings.json" \
    node "$(mixto "$raiz")/hooks/foco-session-start.cjs" "$@"
}

campo() { # <arquivo json> <additionalContext|systemMessage>
  node -e "
const j = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
const v = process.argv[2] === 'systemMessage' ? j.systemMessage : j.hookSpecificOutput.additionalContext;
process.stdout.write(v == null ? '' : String(v));
" "$(mixto "$1")" "$2"
}

# Troca a raiz do plugin por <RAIZ> e tira o aviso de revisao da skill, que depende da data.
normalizar() { # <arquivo json> <raiz do plugin>
  node -e "
const fs = require('fs');
const raiz = process.argv[2];
const formas = [raiz, raiz.replace(/\//g, '\\\\')];
const semRevisao = (t) => t.replace(/\n\n⚠ A skill [^\n]* não é revisada há \d+ dias[^\n]*/g, '');
const norm = (v) => typeof v === 'string' ? semRevisao(formas.reduce((t, f) => t.split(f).join('<RAIZ>'), v)) : v;
const j = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
j.hookSpecificOutput.additionalContext = norm(j.hookSpecificOutput.additionalContext);
if (j.systemMessage != null) j.systemMessage = norm(j.systemMessage);
process.stdout.write(JSON.stringify(j) + '\n');
" "$(mixto "$1")" "$(mixto "$2")"
}

# ------------------------------------------------- 1. foco ligado = codigo de antes
echo "1. com foco: true, a abertura e identica (cmp) a do hook de $BASE_GOLDEN"
GOLD_POSIX="$(novo_sandbox)"
if (cd "$SRC" && git archive "$BASE_GOLDEN" hooks scripts skills) | tar -x -C "$GOLD_POSIX"; then
  # Mede o CODIGO do hook, nao o texto das regras: o skills/ do golden vira o atual.
  rm -rf "$GOLD_POSIX/skills" && cp -r "$SRC/skills" "$GOLD_POSIX/skills"
  passa "golden montado por git archive $BASE_GOLDEN (hooks scripts skills)"
else
  falha "nao consegui montar o golden com git archive $BASE_GOLDEN"
fi
config '{"foco": true}'
for destino in padrao mod; do
  args=(); [ "$destino" = "mod" ] && args=(--destino mod)
  rodar_hook "$SRC" "${args[@]}" > "$BASE_POSIX/novo-$destino.json" 2>/dev/null; c1=$?
  rodar_hook "$GOLD_POSIX" "${args[@]}" > "$BASE_POSIX/gold-$destino.json" 2>/dev/null; c2=$?
  normalizar "$BASE_POSIX/novo-$destino.json" "$SRC" > "$BASE_POSIX/novo-$destino.norm"
  normalizar "$BASE_POSIX/gold-$destino.json" "$GOLD_POSIX" > "$BASE_POSIX/gold-$destino.norm"
  if [ "$c1" = 0 ] && [ "$c2" = 0 ] && [ -s "$BASE_POSIX/gold-$destino.norm" ] \
    && cmp -s "$BASE_POSIX/novo-$destino.norm" "$BASE_POSIX/gold-$destino.norm"; then
    passa "destino $destino com foco: true identico ao $BASE_GOLDEN ($(wc -c < "$BASE_POSIX/gold-$destino.norm" | tr -d ' ') B)"
  else
    falha "destino $destino com foco: true difere do $BASE_GOLDEN (exit $c1/$c2): $(cmp "$BASE_POSIX/novo-$destino.norm" "$BASE_POSIX/gold-$destino.norm" 2>&1 | head -c 200)"
  fi
done
# Controle: a fixture exercita o foco (o golden traz o foco e a janela parada).
campo "$BASE_POSIX/gold-padrao.json" additionalContext > "$BASE_POSIX/gold.txt"
if grep -q "## Foco declarado" "$BASE_POSIX/gold.txt" && grep -q "fixture-outra-janela" "$BASE_POSIX/gold.txt"; then
  passa "controle: a abertura do golden traz o foco e a janela parada da fixture"
else
  falha "controle: a fixture nao exercita o foco (o golden nao traz foco ou janela)"
fi

# ------------------------------------------------- 2. foco desligado
sem_foco() { # <rotulo> <arquivo json>
  local rot="$1" json="$2" txt leg faltas
  txt="$(campo "$json" additionalContext)"; leg="$(campo "$json" systemMessage)"
  faltas="$(node -e "
const [c, leg] = [process.argv[1], process.argv[2]];
const f = [];
if (!c.startsWith('RAINFOREST MIND ATIVO — apoio ao desenvolvimento.')) f.push('cabecalho');
for (const t of ['## Foco declarado', 'Compromissos com prazo', 'Outras sessões', 'fixture-outra-janela', 'NÃO cobrar desvio', 'Arquivos de apoio', 'Foco de fixture'])
  if (c.includes(t)) f.push('sobrou ' + JSON.stringify(t));
for (const n of [3, 8, 17]) if (new RegExp('\\\\n\\\\*\\\\*' + n + '\\\\. ').test(c)) f.push('regra ' + n + ' presente');
for (const n of [1, 2, 4, 16]) if (!new RegExp('\\\\*\\\\*' + n + '\\\\. ').test(c)) f.push('regra ' + n + ' ausente');
if (!c.includes('Regras 3, 8 e 17 (foco) desligadas')) f.push('linha das regras desligadas');
if (!leg.includes('apoio ao desenvolvimento')) f.push('legenda sem apoio ao desenvolvimento');
if (/foco:|janelas/.test(leg)) f.push('legenda fala de foco ou janelas');
process.stdout.write(f.join('; '));
" "$txt" "$leg")"
  [ -z "$faltas" ] && passa "$rot: abertura sem foco, sem as regras 3/8/17, as outras com o numero de sempre" \
    || falha "$rot: $faltas"
}
echo
echo "2. sem a chave, a abertura nao traz o foco"
config -
rodar_hook "$SRC" > "$BASE_POSIX/sem.json" 2>/dev/null
sem_foco "sem config.json" "$BASE_POSIX/sem.json"
config '{"foco": tru'
rodar_hook "$SRC" > "$BASE_POSIX/ilegivel.json" 2>/dev/null
sem_foco "config.json ilegivel" "$BASE_POSIX/ilegivel.json"
config '{"foco": false}'
rodar_hook "$SRC" > "$BASE_POSIX/falso.json" 2>/dev/null
sem_foco "foco: false" "$BASE_POSIX/falso.json"

# ------------------------------------------------- 3. destino mod sem foco
echo
echo "3. destino mod sem foco: a elaboracao da 17 nao vem"
config -
rodar_hook "$SRC" --destino mod > "$BASE_POSIX/mod-sem.json" 2>/dev/null; c=$?
CAB="$(campo "$BASE_POSIX/mod-sem.json" additionalContext | head -n 6)"
case "$CAB" in
  *"regras 16, 12, 11 vêm INTEIRAS"*) [ "$c" = 0 ] && passa "o mod sem foco traz 16, 12 e 11 inteiras, sem a 17" || falha "o mod sem foco saiu com exit $c" ;;
  *) falha "o cabecalho do mod sem foco nao diz 16, 12, 11: $(echo "$CAB" | head -c 300)" ;;
esac

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
