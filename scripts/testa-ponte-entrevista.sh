#!/bin/bash
# Bateria do scripts/ponte.cjs --entrevistar --varredura
# Uso: bash scripts/testa-ponte-entrevista.sh
#
# Casos de teste para varredura pura de repositório:
# (a) detecta stack Node por package.json real, com scripts.test e scripts.build
# (b) layout lista os dirs de 1º nível sem .git/node_modules
# (c) nada escrito no alvo (projeto.md inexistente depois)
# (d) alvo sem package.json → JSON com stack desconhecida, exit 0 (não explode)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

# Copia do PLUGIN, para a ponte poder resolver o próprio caminho por __dirname
PLUG="$CAIXA/plugin"
mkdir -p "$PLUG/scripts" "$PLUG/hooks/lib" "$PLUG/skills/rainforest-mind"
cp "$SRC/scripts/ponte.cjs" "$PLUG/scripts/"
cp "$SRC/hooks/lib/contexto-sessao.cjs" "$SRC/hooks/lib/raiz.cjs" "$SRC/hooks/lib/config.cjs" "$SRC/hooks/lib/projetos.cjs" "$PLUG/hooks/lib/"
cp "$SRC/scripts/setup.cjs" "$PLUG/scripts/"
cp "$SRC/skills/rainforest-mind/SKILL.md" "$PLUG/skills/rainforest-mind/"
DADOS="$CAIXA/dados"; mkdir -p "$DADOS"; printf '' > "$DADOS/ideias.jsonl"
export RFM_ROOT="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"
PONTE="node $PLUG/scripts/ponte.cjs"

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}
prova() { # nome, comando de teste (bash -c)
  local nome="$1"; shift
  if bash -c "$1" >/dev/null 2>&1; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome"; fi
}
contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"; fi
}

echo "== (a) detecta stack Node por package.json real, com scripts.test e scripts.build =="
REPO_A="$CAIXA/repo-a"
mkdir -p "$REPO_A/.github/workflows"
cat > "$REPO_A/package.json" <<'EOF'
{
  "name": "teste-a",
  "scripts": {
    "test": "node --test",
    "build": "node build.js"
  }
}
EOF
cat > "$REPO_A/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
EOF
REPO_A_WIN="$(cygpath -m "$REPO_A" 2>/dev/null || printf '%s' "$REPO_A")"
esperado "varredura roda" 0 $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"
contem "  ... nomeia node" '"stack": "node"' $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"
contem "  ... lista scripts.test literal" '"comando": "node --test"' $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"
contem "  ... lista scripts.build literal" '"comando": "node build.js"' $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"
contem "  ... lista workflows" '"ci"' $PONTE --entrevistar --varredura --alvo "$REPO_A_WIN"

echo
echo "== (b) layout lista os dirs de 1º nível sem .git/node_modules =="
REPO_B="$CAIXA/repo-b"
mkdir -p "$REPO_B/.git" "$REPO_B/node_modules" "$REPO_B/src" "$REPO_B/docs" "$REPO_B/build"
# Sem package.json neste caso
REPO_B_WIN="$(cygpath -m "$REPO_B" 2>/dev/null || printf '%s' "$REPO_B")"
contem "  ... lista src" '"src"' $PONTE --entrevistar --varredura --alvo "$REPO_B_WIN"
contem "  ... lista docs" '"docs"' $PONTE --entrevistar --varredura --alvo "$REPO_B_WIN"
contem "  ... lista build" '"build"' $PONTE --entrevistar --varredura --alvo "$REPO_B_WIN"
prova "  ... nao lista .git" "! ($PONTE --entrevistar --varredura --alvo '$REPO_B_WIN' 2>&1 | grep -q '\".git\"')"
prova "  ... nao lista node_modules" "! ($PONTE --entrevistar --varredura --alvo '$REPO_B_WIN' 2>&1 | grep -q 'node_modules')"

echo
echo "== (c) nada escrito no alvo (projeto.md inexistente depois) =="
REPO_C="$CAIXA/repo-c"
mkdir -p "$REPO_C"
cat > "$REPO_C/package.json" <<'EOF'
{
  "name": "teste-c",
  "scripts": {
    "test": "echo test"
  }
}
EOF
REPO_C_WIN="$(cygpath -m "$REPO_C" 2>/dev/null || printf '%s' "$REPO_C")"
esperado "varredura nao escreve" 0 $PONTE --entrevistar --varredura --alvo "$REPO_C_WIN"
prova "  ... projeto.md nao existe" "[ ! -e '$REPO_C/docs/rainforest/projeto.md' ]"

echo
echo "== (d) alvo sem package.json → stack desconhecida, exit 0 =="
REPO_D="$CAIXA/repo-d"
mkdir -p "$REPO_D"
esperado "varredura com stack vazia" 0 $PONTE --entrevistar --varredura --alvo "$(cygpath -m "$REPO_D" 2>/dev/null || printf '%s' "$REPO_D")"
contem "  ... stack e desconhecida" '"stack": "desconhecida"' $PONTE --entrevistar --varredura --alvo "$(cygpath -m "$REPO_D" 2>/dev/null || printf '%s' "$REPO_D")"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
