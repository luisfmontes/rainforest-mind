#!/bin/bash
# Bateria dos subcomandos `decidir` e `decididos` do scripts/estado.cjs (D4 e D5 do
# design 2026-10-13-executar-autonomo).
# Uso: bash scripts/testa-estado-decididos.sh
#
# Cada cenario roda numa caixa nova (mktemp -d, fora do worktree): repo git com
# `origin` bare, branch fluxo/x, plano e o fluxo aberto. O `estado.cjs` que roda e a
# copia real; cada caso confere o JSON gravado em disco (`docs/rainforest/estado/`),
# nunca o texto do fonte. Recusa conferida pelo exit e pelo arquivo intacto (cksum).
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOXES=()
cleanup() { for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done; }
trap cleanup EXIT

# GIT_* herdado (de um hook, de outro repo) apontaria as caixas para o repo errado.
for v in $(env | grep -o '^GIT_[A-Z_]*'); do unset "$v"; done
unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID

ok=0; falhou=0
SLUG=2026-10-13-decididos-teste

igual() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi
}
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}

# J <expressao>: le JSON da entrada padrao e imprime a expressao sobre `j`.
J() {
  node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));const v=(new Function("j","return "+process.argv[1]))(j);console.log(typeof v==="string"?v:JSON.stringify(v===undefined?null:v));' "$1"
}

# Cria uma caixa nova com o fluxo aberto em `design` (design e plano ainda pendentes).
caixa_nova() {
  CX="$(mktemp -d)"; SANDBOXES+=("$CX")
  ORIG="$(mktemp -d)"; SANDBOXES+=("$ORIG")
  W="$(cygpath -m "$CX" 2>/dev/null || printf '%s' "$CX")"
  export HOME="$CX/casa" USERPROFILE="$CX/casa" CLAUDE_CONFIG_DIR="$CX/casa/.claude-personal"
  mkdir -p "$HOME" "$CX/scripts/lib" "$CX/hooks/lib" "$CX/docs/rainforest/planos" "$CX/docs/rainforest/estado"
  cp "$SRC/scripts/estado.cjs" "$SRC/scripts/conferir-fluxo.cjs" "$CX/scripts/"
  cp "$SRC/scripts/lib/camadas.cjs" "$SRC/scripts/lib/primeiro-prompt-jsonl.cjs" "$SRC/scripts/lib/extrair-veredito.cjs" "$CX/scripts/lib/"
  for lib in raiz config trava-jsonl pastas-docs resolver-executavel contar-ocorrencias caminho-leve teto-despachos; do
    cp "$SRC/hooks/lib/$lib.cjs" "$CX/hooks/lib/"
  done
  touch "$CX/FOCO.md"
  mkdir -p "$CX/.rainforest" && printf '{"principal-livre": true}
' > "$CX/.rainforest/config.json"   # a caixa e um clone dedicado em fluxo/x
  export RFM_ESTADO_ROOT="$W"

  git init -q --bare "$ORIG/origin.git"
  git -C "$CX" init -q -b main
  git -C "$CX" config user.email "teste@exemplo.invalid"
  git -C "$CX" config user.name "teste"
  git -C "$CX" remote add origin "$ORIG/origin.git"
  printf '# teste\n' > "$CX/LEIA.md"
  git -C "$CX" add -- LEIA.md
  git -C "$CX" commit -q -m "base"
  git -C "$CX" push -q origin main
  git -C "$CX" checkout -q -b fluxo/x

  cat > "$CX/docs/rainforest/planos/$SLUG.md" <<'EOF'
# Plano: teste de decididos

## Tarefas

### 1. Primeira [tipo: implementar]
arquivos: `a.txt`
depende de: nenhuma
prova: `true`
EOF

  cd "$CX" || exit 1
  $E iniciar --slug "$SLUG" >/dev/null 2>"$CX/err.txt" || { echo "FALHA preparo: iniciar"; cat "$CX/err.txt"; exit 1; }
}

E="node scripts/estado.cjs"
ARQ="docs/rainforest/estado/$SLUG.json"
D1_PERG="Q2 veredito no cartao"
D1_ESC="no resumo"
D1_PORQ="revisar julga a branch"

echo "== decidir grava um item completo =="
caixa_nova
esperado "decidir com os quatro campos sai 0" 0 $E decidir --slug "$SLUG" --pergunta "$D1_PERG" --escolha "$D1_ESC" --porque "$D1_PORQ"
igual "decididos tem 1 item" "1" "$(J 'j.decididos.length' < "$ARQ")"
igual "item tem pergunta" "$D1_PERG" "$(J 'j.decididos[0].pergunta' < "$ARQ")"
igual "item tem escolha" "$D1_ESC" "$(J 'j.decididos[0].escolha' < "$ARQ")"
igual "item tem porque" "$D1_PORQ" "$(J 'j.decididos[0].porque' < "$ARQ")"
igual "estagio e o aberto (proximo)" "$($E proximo --slug "$SLUG" 2>/dev/null)" "$(J 'j.decididos[0].estagio' < "$ARQ")"
igual "estagio e design no fluxo novo" "design" "$(J 'j.decididos[0].estagio' < "$ARQ")"
igual "em e data-hora ISO" "ok" "$(J 'j.decididos[0].em' < "$ARQ" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' && echo ok || echo ruim)"

echo "== segunda chamada acumula sem sobrescrever =="
caixa_nova
$E decidir --slug "$SLUG" --pergunta "Q1" --escolha "A" --porque "p1" >/dev/null 2>&1
esperado "segunda decisao sai 0" 0 $E decidir --slug "$SLUG" --pergunta "Q2" --escolha "B" --porque "p2"
igual "decididos tem 2 itens" "2" "$(J 'j.decididos.length' < "$ARQ")"
igual "primeiro item preservado" "Q1" "$(J 'j.decididos[0].pergunta' < "$ARQ")"
igual "segundo item na ordem" "Q2" "$(J 'j.decididos[1].pergunta' < "$ARQ")"

echo "== decidir depois de design aprovado grava o estagio novo =="
caixa_nova
$E marcar --slug "$SLUG" --estagio design --status aprovado >/dev/null 2>&1
esperado "decidir com design aprovado sai 0" 0 $E decidir --slug "$SLUG" --pergunta "Q3" --escolha "C" --porque "p3"
igual "estagio passa a plano" "plano" "$(J 'j.decididos[0].estagio' < "$ARQ")"

echo "== decididos imprime a secao e uma linha por item =="
caixa_nova
$E decidir --slug "$SLUG" --pergunta "Q1" --escolha "A" --porque "p1" >/dev/null 2>&1
$E decidir --slug "$SLUG" --pergunta "Q2" --escolha "B" --porque "p2" >/dev/null 2>&1
saida=$($E decididos --slug "$SLUG" 2>&1); rc=$?
igual "decididos sai 0" "0" "$rc"
igual "primeira linha e a secao" "## Decidido sem você" "$(echo "$saida" | head -n 1)"
igual "uma linha por item (2 linhas de lista)" "2" "$(echo "$saida" | grep -c '^- ')"
igual "linha 1 tem pergunta, escolha e porque" "- Q1 → A. Porquê: p1" "$(echo "$saida" | sed -n 2p)"
igual "linha 2 tem pergunta, escolha e porque" "- Q2 → B. Porquê: p2" "$(echo "$saida" | sed -n 3p)"

echo "== decididos com lista vazia nao imprime nada e sai 0 =="
caixa_nova
saida=$($E decididos --slug "$SLUG" 2>&1); rc=$?
igual "decididos vazio sai 0" "0" "$rc"
igual "decididos vazio nao imprime" "" "$saida"

echo "== decidir sem porque recusa e nao grava =="
caixa_nova
antes=$(cksum < "$ARQ")
esperado "decidir sem --porque sai 2" 2 $E decidir --slug "$SLUG" --pergunta "Q" --escolha "E"
igual "arquivo intacto sem --porque" "$antes" "$(cksum < "$ARQ")"
igual "sem chave decididos" "null" "$(J 'j.decididos ?? null' < "$ARQ")"
antes=$(cksum < "$ARQ")
esperado "decidir com --porque vazio sai 2" 2 $E decidir --slug "$SLUG" --pergunta "Q" --escolha "E" --porque ""
igual "arquivo intacto com --porque vazio" "$antes" "$(cksum < "$ARQ")"
esperado "decidir com --porque so espaco sai 2" 2 $E decidir --slug "$SLUG" --pergunta "Q" --escolha "E" --porque "   "
igual "arquivo intacto com --porque so espaco" "$antes" "$(cksum < "$ARQ")"
esperado "decidir com --pergunta vazia sai 2" 2 $E decidir --slug "$SLUG" --pergunta "" --escolha "E" --porque "p"
igual "arquivo intacto com --pergunta vazia" "$antes" "$(cksum < "$ARQ")"

echo "== recusas de slug e de flag =="
caixa_nova
esperado "decidir sem estado sai 1" 1 $E decidir --slug "2026-10-13-nao-existe" --pergunta "Q" --escolha "E" --porque "p"
esperado "decididos sem estado sai 1" 1 $E decididos --slug "2026-10-13-nao-existe"
esperado "flag fora da tabela sai 1" 1 $E decidir --slug "$SLUG" --pergunta "Q" --escolha "E" --porque "p" --tudo "x"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
