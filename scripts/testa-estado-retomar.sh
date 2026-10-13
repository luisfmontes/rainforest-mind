#!/bin/bash
# Bateria do `retomar` e do campo `integradas` do scripts/estado.cjs (D4 e D5 do
# design 2026-10-13-executar-dag-painel).
# Uso: bash scripts/testa-estado-retomar.sh
#
# Cada cenario roda numa caixa nova (mktemp -d, fora do worktree): repo git com
# `origin` bare, branch fluxo/x, plano de 3 tarefas (1 e 2 sem dependencia, 3
# dependendo das duas) e `executar` aberto. Os commits levam o trailer de verdade
# (`git commit --trailer`), e o `estado.cjs` que roda e a copia real.
#
# O trailer e a sentinela de integracao: `integrada` = ha commit com o trailer do
# slug na branch. O JSON so diz o que ja foi marcado (`integradas`). Um caso que
# parece verde sem o git ter sido consultado nao prova nada, por isso cada
# cenario confere o estado depois de um commit real.
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
SLUG=2026-10-13-retomar-teste
OUTRO=2026-10-13-outro-fluxo

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

# Cria uma caixa nova com o fluxo aberto em `executar`. Deixa em CX o caminho POSIX
# e em W o caminho Windows (o node le W, como na bateria de camadas).
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
# Plano: teste de retomada

## Tarefas

### 1. Primeira [tipo: implementar]
arquivos: `a.txt`
depende de: nenhuma
prova: `true`

### 2. Segunda [tipo: implementar]
arquivos: `b.txt`
depende de: nenhuma
prova: `true`

### 3. Terceira [tipo: implementar]
arquivos: `c.txt`
depende de: 1, 2
prova: `true`
EOF

  cd "$CX" || exit 1
  $E iniciar --slug "$SLUG" >/dev/null 2>"$CX/err.txt" || { echo "FALHA preparo: iniciar"; cat "$CX/err.txt"; exit 1; }
  $E marcar --slug "$SLUG" --estagio design --status aprovado >/dev/null 2>&1 || { echo "FALHA preparo: design"; exit 1; }
  $E marcar --slug "$SLUG" --estagio plano --status ok >/dev/null 2>&1 || { echo "FALHA preparo: plano"; exit 1; }
  $E exigir --slug "$SLUG" --estagio executar >/dev/null 2>&1 || { echo "FALHA preparo: executar"; exit 1; }
}

# Commit real de uma tarefa, com o trailer do slug indicado (sem trailer se vazio).
commit_tarefa() { # arquivo, mensagem, slug#n ou ""
  printf 'x%s\n' "$RANDOM" >> "$CX/$1"
  git -C "$CX" add -- "$1"
  if [ -n "$3" ]; then
    git -C "$CX" commit -q -m "$2" --trailer "Rainforest-Tarefa: $3"
  else
    git -C "$CX" commit -q -m "$2"
  fi
}

E="node scripts/estado.cjs"
RET="$E retomar --slug $SLUG"

echo "== sem nenhum commit com trailer =="
caixa_nova
commit_tarefa "LEIA.md" "trabalho sem trailer" ""
saida=$($RET 2>&1); rc=$?
igual "retomar sai 0" "0" "$rc"
igual "3 tarefas pendentes" "pendente,pendente,pendente" "$(echo "$saida" | J 'j.tarefas.map(t=>t.estado).join()')"
igual "camadas 1,1,2" "1,1,2" "$(echo "$saida" | J 'j.tarefas.map(t=>t.camada).join()')"
igual "proxima_camada [1,2]" "[1,2]" "$(echo "$saida" | J 'j.proxima_camada')"
igual "re_marcar vazio" "[]" "$(echo "$saida" | J 'j.re_marcar')"
igual "redespachar vazio" "[]" "$(echo "$saida" | J 'j.redespachar')"

echo "== tarefa 1 integrada e marcada sai da proxima camada =="
caixa_nova
commit_tarefa "a.txt" "tarefa 1" "$SLUG#1"
esperado "marcar integradas [1] sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"integradas":[1]}'
saida=$($RET 2>&1)
igual "tarefa 1 integrada" "integrada,pendente,pendente" "$(echo "$saida" | J 'j.tarefas.map(t=>t.estado).join()')"
igual "proxima_camada [2]" "[2]" "$(echo "$saida" | J 'j.proxima_camada')"
igual "re_marcar vazio" "[]" "$(echo "$saida" | J 'j.re_marcar')"

echo "== tarefa integrada e nao marcada vai para re_marcar =="
caixa_nova
commit_tarefa "b.txt" "tarefa 2" "$SLUG#2"
saida=$($RET 2>&1)
igual "re_marcar [2]" "[2]" "$(echo "$saida" | J 'j.re_marcar')"
igual "tarefa 2 integrada pelo git" "integrada" "$(echo "$saida" | J 'j.tarefas[1].estado')"
igual "redespachar vazio" "[]" "$(echo "$saida" | J 'j.redespachar')"
igual "proxima_camada [1,2]: a 2 ainda falta marcar" "[1,2]" "$(echo "$saida" | J 'j.proxima_camada')"

echo "== em voo com trailer nao se redespacha =="
caixa_nova
esperado "marcar em_voo da tarefa 1 sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"em_voo":[{"tarefa":"1 primeira","agente":"a1"}]}'
commit_tarefa "a.txt" "tarefa 1" "$SLUG#1"
saida=$($RET 2>&1)
igual "redespachar vazio" "[]" "$(echo "$saida" | J 'j.redespachar')"
igual "re_marcar [1]" "[1]" "$(echo "$saida" | J 'j.re_marcar')"

echo "== em voo sem trailer volta para redespachar =="
caixa_nova
esperado "marcar em_voo da tarefa 3 sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"em_voo":[{"tarefa":"3 painel","agente":"a1"}]}'
saida=$($RET 2>&1)
igual "redespachar [3]" "[3]" "$(echo "$saida" | J 'j.redespachar')"
igual "tarefa 3 em_voo" "em_voo" "$(echo "$saida" | J 'j.tarefas[2].estado')"
igual "re_marcar vazio" "[]" "$(echo "$saida" | J 'j.re_marcar')"

echo "== trailer de outro slug nao conta =="
caixa_nova
commit_tarefa "b.txt" "tarefa 2 de outro fluxo" "$OUTRO#2"
saida=$($RET 2>&1)
igual "tarefa 2 segue pendente" "pendente" "$(echo "$saida" | J 'j.tarefas[1].estado')"
igual "re_marcar vazio" "[]" "$(echo "$saida" | J 'j.re_marcar')"
igual "proxima_camada [1,2]" "[1,2]" "$(echo "$saida" | J 'j.proxima_camada')"

echo "== com as 3 integradas e marcadas, nao ha proxima camada =="
caixa_nova
commit_tarefa "a.txt" "tarefa 1" "$SLUG#1"
commit_tarefa "b.txt" "tarefa 2" "$SLUG#2"
commit_tarefa "c.txt" "tarefa 3" "$SLUG#3"
esperado "marcar integradas 1,2,3 sai 0" 0 $E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"integradas":[1,2,3]}'
saida=$($RET 2>&1)
igual "proxima_camada null" "null" "$(echo "$saida" | J 'j.proxima_camada')"
igual "re_marcar vazio" "[]" "$(echo "$saida" | J 'j.re_marcar')"

echo "== integradas acumula entre marcar =="
caixa_nova
$E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"integradas":[1]}' >/dev/null 2>&1 \
  || { echo "FALHA preparo: integradas [1]"; exit 1; }
$E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"integradas":[2]}' >/dev/null 2>&1 \
  || { echo "FALHA preparo: integradas [2]"; exit 1; }
igual "integradas grava [1,2]" "[1,2]" "$(J 'j.executar.integradas' < "docs/rainforest/estado/$SLUG.json")"
saida=$($RET 2>&1)
igual "contadas sem trailer [1,2]" "[1,2]" "$(echo "$saida" | J 'j.contadas_sem_trailer')"
igual "contada sem trailer segue pendente" "pendente,pendente,pendente" "$(echo "$saida" | J 'j.tarefas.map(t=>t.estado).join()')"
igual "contada sem trailer nao sai da proxima camada" "[1,2]" "$(echo "$saida" | J 'j.proxima_camada')"

echo "== sem origin, le o trailer do historico do HEAD =="
caixa_nova
git -C "$CX" remote remove origin
commit_tarefa "a.txt" "tarefa 1" "$SLUG#1"
saida=$($RET 2>&1); rc=$?
igual "retomar sem origin sai 0" "0" "$rc"
igual "tarefa 1 integrada sem origin" "integrada" "$(echo "$saida" | J 'j.tarefas[0].estado')"

echo "== integradas invalido recusa e nao grava =="
caixa_nova
esperado "integradas com texto sai 2" 2 $E marcar --slug "$SLUG" --estagio executar --status parcial --json '{"integradas":["1"]}'
igual "integradas nao foi gravado" "null" "$(J 'j.executar.integradas' < "docs/rainforest/estado/$SLUG.json")"

echo "== recusas: slug inexistente, plano ausente, ciclo, dependencia inexistente =="
caixa_nova
esperado "slug inexistente sai 1" 1 $E retomar --slug "2026-10-13-nao-existe"
rm -f "docs/rainforest/planos/$SLUG.md"
esperado "plano ausente sai 1" 1 $RET
caixa_nova
sed -i '0,/depende de: nenhuma/s//depende de: 3/' "docs/rainforest/planos/$SLUG.md"
esperado "ciclo 1->3->1 sai 1" 1 $RET
caixa_nova
sed -i 's/depende de: 1, 2/depende de: 9/' "docs/rainforest/planos/$SLUG.md"
esperado "dependencia inexistente sai 1" 1 $RET

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
