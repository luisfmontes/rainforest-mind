#!/bin/bash
# Bateria do scripts/limpar-worktrees.cjs: --remover só com HEAD alcançável (D5).
#
# Cobre: (1) HEAD destacado com commit próprio é arquivado em
#            refs/rainforest/arquivo/<nome> antes de sair
#        (2) worktree cujo HEAD é alcançado por branch sai sem criar ref
#        (3) sonda de alcance que falha deixa o worktree no lugar, como erro
#        (4) ref de arquivo que já aponta para outro commit não é sobrescrita:
#            arquiva em <nome>-<sha7>
#        (A) dois destacados de mesmo nome em pastas diferentes: os dois saem
#        (B) pasta recriada com o mesmo nome e outro commit: ganha o sufixo
#        (C) pasta com espaço: nome saneado, sai
#        (D) ref já apontando para o mesmo commit: reuso, sem erro

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

teste "4" "ref de arquivo já existente com outro commit: não sobrescreve, arquiva em <nome>-<sha7>"

repo_4="$SB/repo_4"
work_4="$SB/trabalho_4"
criarRepoComCommit "$repo_4" "$work_4"

wt_4="$work_4-worktrees/wt-coli"
git worktree add -q --detach "$wt_4" HEAD
(cd "$wt_4" && echo outra > outra.txt && git add outra.txt && git commit -qm "commit do destacado")
main_4=$(cd "$work_4" && git rev-parse HEAD)
sha_4=$(cd "$wt_4" && git rev-parse HEAD)
(cd "$work_4" && git update-ref refs/rainforest/arquivo/wt-coli "$main_4")

saida_4=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_4" --remover 2>&1)

ref_4=$(cd "$work_4" && git rev-parse --verify -q refs/rainforest/arquivo/wt-coli || true)
igual "4a ref existente não foi sobrescrita" "$ref_4" "$main_4"
ref_4s=$(cd "$work_4" && git rev-parse --verify -q "refs/rainforest/arquivo/wt-coli-${sha_4:0:7}" || true)
igual "4b ref com sufixo aponta para o HEAD do destacado" "$ref_4s" "$sha_4"
igual "4c worktree saiu do git worktree list" "$(worktree_registrado "$work_4" "wt-coli")" "nao"
if printf '%s' "$saida_4" | grep -qF "arquivado: refs/rainforest/arquivo/wt-coli-${sha_4:0:7}"; then
  ok=$((ok+1)); echo "  ok    4d a saída diz o nome com sufixo"
else
  falhou=$((falhou+1)); echo "  FALHA 4d a saída não diz o nome com sufixo"
  echo "        Saída: $saida_4"
fi

# --- CASO (A): dois destacados de mesmo nome em pastas diferentes, commits diferentes

teste "A" "dois worktrees 'wt' em pastas diferentes com commits diferentes: os dois saem"

repo_A="$SB/repo_A"
work_A="$SB/trabalho_A"
criarRepoComCommit "$repo_A" "$work_A"

wt_Aa="$work_A-worktrees/a/wt"
wt_Ab="$work_A-worktrees/b/wt"
git worktree add -q --detach "$wt_Aa" HEAD
git worktree add -q --detach "$wt_Ab" HEAD
(cd "$wt_Aa" && echo da-a > da-a.txt && git add da-a.txt && git commit -qm "commit de a/wt")
(cd "$wt_Ab" && echo da-b > da-b.txt && git add da-b.txt && git commit -qm "commit de b/wt")
sha_Aa=$(cd "$wt_Aa" && git rev-parse HEAD)
sha_Ab=$(cd "$wt_Ab" && git rev-parse HEAD)

saida_A=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_A" --remover 2>&1)

igual "Aa a/wt saiu do git worktree list" "$(worktree_registrado "$work_A" "a/wt")" "nao"
igual "Ab b/wt saiu do git worktree list" "$(worktree_registrado "$work_A" "b/wt")" "nao"
if printf '%s' "$saida_A" | grep -qF "erro:"; then
  falhou=$((falhou+1)); echo "  FALHA Ac a saída tem erro"
  echo "        Saída: $saida_A"
else
  ok=$((ok+1)); echo "  ok    Ac nenhum erro na saída"
fi
refs_A=$(cd "$work_A" && git for-each-ref --format='%(objectname)' refs/rainforest/arquivo | sort)
esperado_A=$(printf '%s\n%s\n' "$sha_Aa" "$sha_Ab" | sort)
igual "Ad as refs de arquivo apontam para os dois commits, cada um com a sua" "$refs_A" "$esperado_A"
igual "Ae são duas refs, uma por commit" "$(cd "$work_A" && git for-each-ref refs/rainforest/arquivo | wc -l | tr -d ' ')" "2"

# --- CASO (B): pasta recriada com o mesmo nome e outro commit ganha o sufixo

teste "B" "pasta arquivada, recriada com o mesmo nome e outro commit: sai e ganha <nome>-<sha7>"

repo_B="$SB/repo_B"
work_B="$SB/trabalho_B"
criarRepoComCommit "$repo_B" "$work_B"

wt_B="$work_B-worktrees/wt-x"
git worktree add -q --detach "$wt_B" HEAD
(cd "$wt_B" && echo x1 > x1.txt && git add x1.txt && git commit -qm "commit X")
sha_Bx=$(cd "$wt_B" && git rev-parse HEAD)
node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_B" --remover >/dev/null 2>&1
igual "B1 primeira rodada: wt-x saiu" "$(worktree_registrado "$work_B" "wt-x")" "nao"

git worktree add -q --detach "$wt_B" HEAD
(cd "$wt_B" && echo y1 > y1.txt && git add y1.txt && git commit -qm "commit Y")
sha_By=$(cd "$wt_B" && git rev-parse HEAD)

saida_B=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_B" --remover 2>&1)

igual "B2 wt-x recriada saiu do git worktree list" "$(worktree_registrado "$work_B" "wt-x")" "nao"
igual "B3 ref base continua apontando para X" "$(cd "$work_B" && git rev-parse --verify -q refs/rainforest/arquivo/wt-x || true)" "$sha_Bx"
igual "B4 ref com sufixo aponta para Y" "$(cd "$work_B" && git rev-parse --verify -q "refs/rainforest/arquivo/wt-x-${sha_By:0:7}" || true)" "$sha_By"
if printf '%s' "$saida_B" | grep -qF "erro:"; then
  falhou=$((falhou+1)); echo "  FALHA B5 a saída tem erro"
  echo "        Saída: $saida_B"
else
  ok=$((ok+1)); echo "  ok    B5 nenhum erro na saída"
fi

# --- CASO (C): pasta com espaço é arquivada com nome saneado e sai

teste "C" "pasta 'wt com espaco' é arquivada com nome saneado e removida"

repo_C="$SB/repo_C"
work_C="$SB/trabalho_C"
criarRepoComCommit "$repo_C" "$work_C"

wt_C="$work_C-worktrees/wt com espaco"
git worktree add -q --detach "$wt_C" HEAD
(cd "$wt_C" && echo c > c.txt && git add c.txt && git commit -qm "commit de C")
sha_C=$(cd "$wt_C" && git rev-parse HEAD)

saida_C=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_C" --remover 2>&1)

igual "C1 worktree com espaço saiu do git worktree list" "$(worktree_registrado "$work_C" "wt com espaco")" "nao"
igual "C2 ref com nome saneado aponta para o commit" "$(cd "$work_C" && git rev-parse --verify -q refs/rainforest/arquivo/wt-com-espaco || true)" "$sha_C"
if printf '%s' "$saida_C" | grep -qF "arquivado: refs/rainforest/arquivo/wt-com-espaco"; then
  ok=$((ok+1)); echo "  ok    C3 a saída diz o nome saneado"
else
  falhou=$((falhou+1)); echo "  FALHA C3 a saída não diz o nome saneado"
  echo "        Saída: $saida_C"
fi

# --- CASO (D): ref já apontando para o mesmo commit é reuso, não erro

teste "D" "ref de arquivo já apontando para o mesmo commit: reuso, sem erro, worktree sai"

repo_D="$SB/repo_D"
work_D="$SB/trabalho_D"
criarRepoComCommit "$repo_D" "$work_D"

wt_D="$work_D-worktrees/wt-d"
git worktree add -q --detach "$wt_D" HEAD
(cd "$wt_D" && echo d > d.txt && git add d.txt && git commit -qm "commit de D")
sha_D=$(cd "$wt_D" && git rev-parse HEAD)
(cd "$work_D" && git update-ref refs/rainforest/arquivo/wt-d "$sha_D")

saida_D=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_D" --remover 2>&1)

igual "D1 worktree saiu do git worktree list" "$(worktree_registrado "$work_D" "wt-d")" "nao"
igual "D2 ref continua apontando para o mesmo commit" "$(cd "$work_D" && git rev-parse --verify -q refs/rainforest/arquivo/wt-d || true)" "$sha_D"
if printf '%s' "$saida_D" | grep -qF "erro:"; then
  falhou=$((falhou+1)); echo "  FALHA D3 a saída tem erro"
  echo "        Saída: $saida_D"
else
  ok=$((ok+1)); echo "  ok    D3 nenhum erro na saída"
fi

echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ] && exit 0 || exit 1
