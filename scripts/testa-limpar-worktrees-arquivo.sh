#!/bin/bash
# Bateria do scripts/limpar-worktrees.cjs: --remover só com HEAD alcançável (D5).
#
# Cobre: (1) HEAD destacado com commit próprio é arquivado em
#            refs/rainforest/arquivo/<nome> antes de sair
#        (2) worktree cujo HEAD é alcançado por branch sai sem criar ref
#        (3) sonda de alcance que falha deixa o worktree no lugar, como erro
#        (4) ref de arquivo que já aponta para outro commit não é sobrescrita

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

export PATH="/c/Program Files/nodejs:/usr/bin:/usr/local/bin:/c/Windows/System32:/c/Program Files/PowerShell:$PATH"

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1: '$2' != '$3'"; fi; }
verdade() { if [ "$2" = "sim" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1"; fi; }
teste() { echo ""; echo "($1) $2"; }

# Repo bare + clone de trabalho com um commit em main.
criarRepoComCommit() {
  local repo_bare="$1"
  local work_dir="$2"

  git init --bare "$repo_bare" >/dev/null
  git clone "$repo_bare" "$work_dir" >/dev/null 2>&1
  cd "$work_dir"
  git config user.name "Test User"
  git config user.email "<email>"
  touch initial.txt
  git add initial.txt
  git commit -qm "Initial commit"
  git push -q origin HEAD:main 2>/dev/null || git push -q origin HEAD:main
}

# Diz "sim" se o worktree ainda aparece em git worktree list, "nao" se saiu.
worktree_registrado() {
  (cd "$1" && git worktree list --porcelain) | grep -qF "$2" && echo sim || echo nao
}

# --- CASO (1): HEAD destacado com commit próprio é arquivado antes de sair

teste "1" "HEAD destacado com commit próprio: arquiva em refs/rainforest/arquivo e remove"

repo_1="$SB/repo_1"
work_1="$SB/trabalho_1"
criarRepoComCommit "$repo_1" "$work_1"

wt_1="$work_1-worktrees/wt-arq"
git worktree add -q --detach "$wt_1" HEAD
(cd "$wt_1" && echo propria > propria.txt && git add propria.txt && git commit -qm "commit so no destacado")
sha_1=$(cd "$wt_1" && git rev-parse HEAD)

# Pré-condição: nenhuma branch alcança o commit do destacado
alcanca_1=$(cd "$work_1" && git for-each-ref --contains "$sha_1" refs/heads refs/remotes)
igual "1a pré-condição: nenhuma branch alcança o commit do destacado" "$alcanca_1" ""

saida_1=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_1" --remover 2>&1)

ref_1=$(cd "$work_1" && git rev-parse --verify -q refs/rainforest/arquivo/wt-arq || true)
igual "1b refs/rainforest/arquivo/wt-arq aponta para o HEAD do destacado" "$ref_1" "$sha_1"

if printf '%s' "$saida_1" | grep -qF "arquivado: refs/rainforest/arquivo/wt-arq"; then
  ok=$((ok+1)); echo "  ok    1c a saída diz que arquivou"
else
  falhou=$((falhou+1)); echo "  FALHA 1c a saída não diz que arquivou"
  echo "        Saída: $saida_1"
fi

igual "1d worktree destacado saiu do git worktree list" "$(worktree_registrado "$work_1" "wt-arq")" "nao"

# --- CASO (2): HEAD alcançado por branch sai sem criar ref

teste "2" "worktree com HEAD alcançado por branch sai sem criar ref"

repo_2="$SB/repo_2"
work_2="$SB/trabalho_2"
criarRepoComCommit "$repo_2" "$work_2"

wt_2="$work_2-worktrees/wt-alcanca"
git worktree add -q --detach "$wt_2" HEAD

saida_2=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_2" --remover 2>&1)

refs_2=$(cd "$work_2" && git for-each-ref refs/rainforest)
igual "2a nenhuma ref refs/rainforest criada" "$refs_2" ""
igual "2b worktree alcançado saiu do git worktree list" "$(worktree_registrado "$work_2" "wt-alcanca")" "nao"
if printf '%s' "$saida_2" | grep -qF "arquivado:"; then
  falhou=$((falhou+1)); echo "  FALHA 2c disse que arquivou quando a branch alcança"
else
  ok=$((ok+1)); echo "  ok    2c não diz que arquivou"
fi

# --- CASO (3): sonda de alcance que falha deixa o worktree no lugar

teste "3" "sonda de alcance que falha: worktree fica como erro e não sai"

repo_3="$SB/repo_3"
work_3="$SB/trabalho_3"
criarRepoComCommit "$repo_3" "$work_3"

wt_3="$work_3-worktrees/wt-sonda"
git worktree add -q --detach "$wt_3" HEAD

# Hipótese: o HEAD do diretório administrativo aponta para a ÁRVORE do commit
# (objeto existente, mas não é commit). `for-each-ref --contains` falha sobre
# ele; `git status` talvez continue funcionando.
tree_3=$(cd "$work_3" && git rev-parse HEAD^{tree})
printf '%s\n' "$tree_3" > "$work_3/.git/worktrees/wt-sonda/HEAD"

# Pré-condição: o worktree continua classificado como limpo, senão o caso não
# exerce a sonda que falha e passaria por outro motivo.
lista_3=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_3" 2>&1)
if printf '%s' "$lista_3" | grep -qF "limpo"; then
  ok=$((ok+1)); echo "  ok    3a pré-condição: worktree continua limpo com HEAD inexistente"
else
  falhou=$((falhou+1)); echo "  FALHA 3a pré-condição: worktree não ficou limpo"
  echo "        Saída: $lista_3"
fi

saida_3=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_3" --remover 2>&1)
igual "3b worktree continua registrado" "$(worktree_registrado "$work_3" "wt-sonda")" "sim"
if printf '%s' "$saida_3" | grep -qF "não removido: sonda git de alcance do HEAD falhou"; then
  ok=$((ok+1)); echo "  ok    3c a saída diz erro com o motivo"
else
  falhou=$((falhou+1)); echo "  FALHA 3c a saída não diz erro com o motivo"
  echo "        Saída: $saida_3"
fi

# --- CASO (4): ref de arquivo que já aponta para outro commit não é sobrescrita

teste "4" "ref de arquivo já existente com outro commit: não sobrescreve, não remove"

repo_4="$SB/repo_4"
work_4="$SB/trabalho_4"
criarRepoComCommit "$repo_4" "$work_4"

wt_4="$work_4-worktrees/wt-coli"
git worktree add -q --detach "$wt_4" HEAD
(cd "$wt_4" && echo outra > outra.txt && git add outra.txt && git commit -qm "commit do destacado")
main_4=$(cd "$work_4" && git rev-parse HEAD)
(cd "$work_4" && git update-ref refs/rainforest/arquivo/wt-coli "$main_4")

saida_4=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_4" --remover 2>&1)

ref_4=$(cd "$work_4" && git rev-parse --verify -q refs/rainforest/arquivo/wt-coli || true)
igual "4a ref existente não foi sobrescrita" "$ref_4" "$main_4"
igual "4b worktree continua registrado" "$(worktree_registrado "$work_4" "wt-coli")" "sim"
if printf '%s' "$saida_4" | grep -qF "não sobrescrevo"; then
  ok=$((ok+1)); echo "  ok    4c a saída diz que não sobrescreveu"
else
  falhou=$((falhou+1)); echo "  FALHA 4c a saída não diz que não sobrescreveu"
  echo "        Saída: $saida_4"
fi

echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ] && exit 0 || exit 1
