#!/bin/bash
# Bateria da trava "checkout principal fica na branch padrão" do estado.cjs
# (regra 11, Issue #195). Uso: bash scripts/testa-estado-principal.sh
#
# Monta um repositório git DE VERDADE numa caixa temporária (a caixa de
# testa-estado.sh não é repositório, e é assim que ela prova que fora de git
# nada muda). Tudo — repo, worktree linkado, pasta não-git — mora DENTRO da
# caixa, e um único trap apaga a caixa inteira (Issue #216: worktree criado em
# `../wt` fora da caixa sobrevivia ao trap).
#
# Cada asserção tem os dois ramos: `cmd && ok=... ; echo ok || ...` é
# tautológico (o `;` corta a cadeia e o `echo` nunca falha) — foi a forma que a
# primeira versão desta bateria tinha, e ela passava com qualquer resultado.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

# O harness exporta CLAUDE_PROJECT_DIR para hooks; se vazar para aqui, o
# estado.cjs gravaria no repositório de verdade em vez da caixa.
unset CLAUDE_PROJECT_DIR
unset GIT_DIR

REPO="$CAIXA/repo"
mkdir -p "$REPO/scripts" "$REPO/hooks/lib"
cp "$SRC/scripts/estado.cjs" "$REPO/scripts/"
cp "$SRC/hooks/lib/raiz.cjs" "$REPO/hooks/lib/"
cp "$SRC/hooks/lib/config.cjs" "$REPO/hooks/lib/"
touch "$REPO/FOCO.md"

cd "$REPO" || exit 1
echo "(caixa de areia: $CAIXA)"

git init -q -b main
git config user.email "test@<email>"
git config user.name "Bateria"
git add FOCO.md scripts/estado.cjs hooks/lib/raiz.cjs hooks/lib/config.cjs
git commit -qm "inicial"

ok=0; falhou=0
E="node $REPO/scripts/estado.cjs"
export RFM_ESTADO_ROOT="$REPO"

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}
contem() { # nome, trecho, texto
  if printf '%s' "$3" | grep -qF -- "$2"; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava conter '$2'"; printf '%s\n' "$3" | sed 's/^/         /'; fi
}
nao_contem() { # nome, trecho, texto
  if printf '%s' "$3" | grep -qF -- "$2"; then falhou=$((falhou+1)); echo "  FALHA $1: nao devia conter '$2'"
  else ok=$((ok+1)); echo "  ok   $1"; fi
}
existe() { # nome, caminho
  if [ -f "$2" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: $2 nao existe"; fi
}
nao_existe() { # nome, caminho
  if [ -f "$2" ]; then falhou=$((falhou+1)); echo "  FALHA $1: $2 existe"
  else ok=$((ok+1)); echo "  ok   $1"; fi
}

echo
echo "== a. principal em fluxo/x, sem config: iniciar recusa =="
git checkout -q -b fluxo/x
saida=$($E iniciar --slug x 2>&1); got=$?
esperado "iniciar --slug x sai 2" 2 bash -c "exit $got"
contem "mensagem diz RECUSADO" "RECUSADO" "$saida"
contem "mensagem nomeia a branch atual e a padrao" "'fluxo/x', não em 'main'" "$saida"
contem "receita: git worktree add" "git worktree add .claude/worktrees/x fluxo/x" "$saida"
contem "receita: git checkout main" "git checkout main" "$saida"
contem "receita: chave principal-livre" '"principal-livre": true' "$saida"
nao_existe "x.json nao foi gravado" "$REPO/docs/rainforest/estado/x.json"

echo
echo "== b. principal em main: iniciar passa =="
git checkout -q main
esperado "iniciar --slug y sai 0" 0 $E iniciar --slug y
existe "y.json gravado" "$REPO/docs/rainforest/estado/y.json"

echo
echo "== c. worktree linkado em fluxo/x: iniciar passa =="
git worktree add -q "$CAIXA/wt" fluxo/x
(
  cd "$CAIXA/wt" || exit 9
  export RFM_ESTADO_ROOT="$CAIXA/wt"
  node "$REPO/scripts/estado.cjs" iniciar --slug z >/dev/null 2>&1
)
got=$?
esperado "iniciar no worktree linkado sai 0" 0 bash -c "exit $got"
existe "z.json gravado no worktree" "$CAIXA/wt/docs/rainforest/estado/z.json"
# Devolve a branch ao principal: enquanto o worktree existir, `git checkout
# fluxo/x` no principal falha e os casos seguintes rodariam em main — passando
# de graca. Foi exatamente o que a primeira rodada desta bateria fez.
git worktree remove --force "$CAIXA/wt"
if git checkout -q fluxo/x; then ok=$((ok+1)); echo "  ok   principal consegue voltar a fluxo/x"
else falhou=$((falhou+1)); echo "  FALHA principal nao conseguiu voltar a fluxo/x"; fi

echo
echo "== d. principal em fluxo/x com principal-livre: true: iniciar passa =="
git checkout -q fluxo/x
mkdir -p "$REPO/.rainforest"
echo '{"principal-livre": true}' > "$REPO/.rainforest/config.json"
esperado "iniciar --slug w sai 0" 0 $E iniciar --slug w
existe "w.json gravado" "$REPO/docs/rainforest/estado/w.json"
rm -f "$REPO/.rainforest/config.json"

echo
echo "== e. pasta que nao e repositorio git: iniciar passa (comportamento antigo) =="
mkdir -p "$CAIXA/nao-git/scripts" "$CAIXA/nao-git/hooks/lib"
cp "$REPO/scripts/estado.cjs" "$CAIXA/nao-git/scripts/"
cp "$REPO/hooks/lib/raiz.cjs" "$REPO/hooks/lib/config.cjs" "$CAIXA/nao-git/hooks/lib/"
touch "$CAIXA/nao-git/FOCO.md"
(
  cd "$CAIXA/nao-git" || exit 9
  export RFM_ESTADO_ROOT="$CAIXA/nao-git"
  node scripts/estado.cjs iniciar --slug v >/dev/null 2>&1
)
got=$?
esperado "iniciar fora de git sai 0" 0 bash -c "exit $got"
existe "v.json gravado" "$CAIXA/nao-git/docs/rainforest/estado/v.json"

echo
echo "== f. principal em fluxo/x, estado y aberto: exigir passa e AVISA =="
git checkout -q fluxo/x
saida=$($E exigir --slug y --estagio design 2>&1); got=$?
esperado "exigir --estagio design sai 0" 0 bash -c "exit $got"
contem "stderr traz o aviso" "aviso: checkout principal em 'fluxo/x'" "$saida"
git checkout -q main
saida=$($E exigir --slug y --estagio design 2>&1)
nao_contem "em main nao ha aviso" "aviso: checkout principal" "$saida"

echo
echo "== g. HEAD solto (detached) no principal conta como fora da padrao =="
git checkout -q --detach main
esperado "iniciar --slug u sai 2" 2 $E iniciar --slug u
git checkout -q main

echo
echo "== h. MUTACAO: sem a comparacao de branch, o caso a deixa de recusar =="
cp scripts/estado.cjs scripts/estado-mutante.cjs
sed -i 's/if (branchAtual === padrao) return null;/if (true) return null; \/\/ MUTADO/' scripts/estado-mutante.cjs
if grep -q "MUTADO" scripts/estado-mutante.cjs; then ok=$((ok+1)); echo "  ok   mutacao aplicada"
else falhou=$((falhou+1)); echo "  FALHA mutacao nao aplicada: o trecho nao existe mais"; fi
git checkout -q fluxo/x
esperado "mutante deixa iniciar passar em fluxo/x (a trava e load-bearing)" 0 node scripts/estado-mutante.cjs iniciar --slug x-mut
rm -f scripts/estado-mutante.cjs

echo
echo "== resultado: $ok ok, $falhou falhou =="
[ "$falhou" -eq 0 ]
