#!/bin/bash
# Bateria de testes do scripts/limpar-worktrees.cjs
#
# Cobre: (a) worktree limpo listado como removível
#        (b) worktree sujo listado mas não removível
#        (c) subdir comum (órfão) listado como órfão
#        (d) --remover remove só os limpos

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# Prepend common tool paths
export PATH="/c/Program Files/nodejs:/usr/bin:/usr/local/bin:/c/Windows/System32:/c/Program Files/PowerShell:$PATH"

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1: '$2' != '$3'"; fi; }
verdade() { if [ "$2" = "sim" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1"; fi; }
teste() { echo ""; echo "($1) $2"; }

# Função auxiliar para criar repo com commit inicial
criarRepoComCommit() {
  local repo_bare="$1"
  local work_dir="$2"

  git init --bare "$repo_bare"
  git clone "$repo_bare" "$work_dir"
  cd "$work_dir"

  git config user.name "Test User"
  git config user.email "<email>"
  touch initial.txt
  git add initial.txt
  git commit -m "Initial commit"
  git push origin main 2>/dev/null || git push origin HEAD:main
}

# --- CASO (a): worktree limpo listado como removível

teste "a" "worktree limpo é listado como removível"

repo_a="$SB/repo_a"
work_a="$SB/trabalho_a"
criarRepoComCommit "$repo_a" "$work_a"

# Cria um worktree limpo
wt_a_real="$work_a/.git/worktrees/wt-a"
git worktree add "$wt_a_real" HEAD

# Lista com limpar-worktrees
saida_a=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_a" 2>&1)

# Verifica se o worktree aparece como "limpo"
if echo "$saida_a" | grep -q "limpo"; then
  ok=$((ok+1))
  echo "  ok    worktree aparece como 'limpo' na saída"
else
  falhou=$((falhou+1))
  echo "  FALHA worktree não aparece como 'limpo'"
  echo "        Saída: $saida_a"
fi

# --- CASO (b): worktree sujo listado mas não removível

teste "b" "worktree com alterações é listado como 'sujo'"

repo_b="$SB/repo_b"
work_b="$SB/trabalho_b"
criarRepoComCommit "$repo_b" "$work_b"

# Cria um worktree com sujeira
wt_b_real="$work_b/.git/worktrees/wt-b"
git worktree add "$wt_b_real" HEAD

cd "$wt_b_real"
echo "sujeira" > arquivo_sujo.txt

# Lista com limpar-worktrees
saida_b=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_b" 2>&1)

# Verifica se o worktree aparece como "sujo"
if echo "$saida_b" | grep -q "sujo"; then
  ok=$((ok+1))
  echo "  ok    worktree aparece como 'sujo' na saída"
else
  falhou=$((falhou+1))
  echo "  FALHA worktree não aparece como 'sujo'"
  echo "        Saída: $saida_b"
fi

# --- CASO (c): subdiretório comum sem .git próprio é órfão

teste "c" "subdiretório comum é listado como 'órfão'"

repo_c="$SB/repo_c"
git init "$repo_c"
cd "$repo_c"
git config user.name "Test User"
git config user.email "<email>"
touch initial.txt
git add initial.txt
git commit -m "Initial commit"

# Cria um worktree de verdade
wt_c_real="$repo_c/.git/worktrees/wt-c"
git worktree add "$wt_c_real" HEAD

# Cria um subdiretório comum (sem .git próprio) ao lado do worktree, dentro de .git/worktrees/
subdir_comum="$repo_c/.git/worktrees/subdir-comum"
mkdir -p "$subdir_comum"

# Lista com limpar-worktrees
saida_c=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$repo_c" 2>&1)

# Verifica se o subdir aparece como "órfão"
if echo "$saida_c" | grep -q "órfão"; then
  ok=$((ok+1))
  echo "  ok    subdiretório aparece como 'órfão' na saída"
else
  falhou=$((falhou+1))
  echo "  FALHA subdiretório não aparece como 'órfão'"
  echo "        Saída: $saida_c"
fi

# --- CASO (d): --remover remove só os limpos

teste "d" "--remover remove worktree limpo apenas"

repo_d="$SB/repo_d"
work_d="$SB/trabalho_d"
criarRepoComCommit "$repo_d" "$work_d"

# Cria dois worktrees: um limpo, um sujo
wt_d_limpo_real="$work_d/.git/worktrees/wt-limpo"
wt_d_sujo_real="$work_d/.git/worktrees/wt-sujo"

git worktree add "$wt_d_limpo_real" HEAD
git worktree add "$wt_d_sujo_real" HEAD

# Adiciona sujeira no sujo
cd "$wt_d_sujo_real"
echo "sujeira" > arquivo.txt
cd "$work_d"

# Debug: mostra o status do worktree sujo
debug_status=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_d" 2>&1)

# Mostra status antes de remover
echo "    Antes de remover:"
git worktree list --porcelain | grep -F "wt-limpo" | head -1 || true

# Roda limpar-worktrees com --remover
node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_d" --remover 2>&1 | grep -i "remov" || true

# Verifica que o limpo foi removido (não aparece em git worktree list)
# Usa grep -F para busca literal, sem regex
lista_after=$(git worktree list --porcelain | grep -F "wt-limpo" || true)
if [ -z "$lista_after" ]; then
  ok=$((ok+1))
  echo "  ok    worktree limpo foi removido"
else
  falhou=$((falhou+1))
  echo "  FALHA worktree limpo ainda aparece em git worktree list"
  echo "        Lista: $lista_after"
fi

# Verifica que o sujo NÃO foi removido
lista_sujo=$(git worktree list --porcelain | grep -F "wt-sujo" || true)
if [ -n "$lista_sujo" ]; then
  ok=$((ok+1))
  echo "  ok    worktree sujo não foi removido"
else
  falhou=$((falhou+1))
  echo "  FALHA worktree sujo foi removido (não deveria)"
  echo "        Debug: $debug_status"
fi

# --- Relatório final

echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ] && exit 0 || exit 1
