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

# --- CASO (e): --raiz com barras invertidas não deixa a raiz principal escapar

teste "e" "--raiz com barras invertidas não lista a raiz principal como candidata"

repo_e="$SB/repo_e"
work_e="$SB/trabalho_e"
criarRepoComCommit "$repo_e" "$work_e"

wt_e_real="$work_e/.git/worktrees/wt-e"
git worktree add "$wt_e_real" HEAD

# Converte a raiz para o formato Windows com barra invertida (C:\...)
work_e_win=$(cygpath -w "$work_e" 2>/dev/null || echo "$work_e")

saida_e=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_e_win" 2>&1)

# A raiz principal não deve aparecer como linha da tabela. A saída sempre
# imprime o caminho normalizado por `path.resolve` (backslash no Windows,
# work_e_win), nunca a forma posix crua (work_e) — por isso o alvo do grep
# tem de ser work_e_win, com duas espacos (padEnd da tabela) para não casar
# como PREFIXO do caminho mais longo do próprio worktree linkado (wt-e).
if echo "$saida_e" | grep -qF "$work_e_win  "; then
  falhou=$((falhou+1))
  echo "  FALHA raiz principal apareceu na listagem"
  echo "        Saída: $saida_e"
else
  ok=$((ok+1))
  echo "  ok    raiz principal não aparece na listagem"
fi

# E --remover não deve tentar remover a raiz principal
saida_e_remover=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_e_win" --remover 2>&1)
if echo "$saida_e_remover" | grep -qi "removendo $work_e_win"; then
  falhou=$((falhou+1))
  echo "  FALHA --remover tentou remover a raiz principal"
  echo "        Saída: $saida_e_remover"
else
  ok=$((ok+1))
  echo "  ok    --remover não tenta remover a raiz principal"
fi

# --- CASO (f): letra de drive em caixa diferente não deixa a raiz escapar

teste "f" "--raiz com letra de drive em caixa diferente não lista a raiz principal"

repo_f="$SB/repo_f"
work_f="$SB/trabalho_f"
criarRepoComCommit "$repo_f" "$work_f"

wt_f_real="$work_f/.git/worktrees/wt-f"
git worktree add "$wt_f_real" HEAD

# Alterna a caixa da letra de drive (ex.: C:\... -> c:\...)
work_f_win=$(cygpath -w "$work_f" 2>/dev/null || echo "$work_f")
if [ "$work_f_win" != "$work_f" ]; then
  drive_letra="${work_f_win:0:1}"
  if [[ "$drive_letra" =~ [A-Z] ]]; then
    drive_alt=$(echo "$drive_letra" | tr 'A-Z' 'a-z')
  else
    drive_alt=$(echo "$drive_letra" | tr 'a-z' 'A-Z')
  fi
  work_f_altcase="${drive_alt}${work_f_win:1}"

  saida_f=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_f_altcase" 2>&1)

  # Mesma ressalva do caso (e): a tabela imprime o caminho com a caixa
  # ORIGINAL (a do disco, via `git worktree list`/path.resolve), não a
  # caixa alternada passada em --raiz — por isso o alvo é work_f_win.
  if echo "$saida_f" | grep -qF "$work_f_win  "; then
    falhou=$((falhou+1))
    echo "  FALHA raiz principal apareceu na listagem (caixa de drive alternada)"
    echo "        Saída: $saida_f"
  else
    ok=$((ok+1))
    echo "  ok    raiz principal não aparece com letra de drive em caixa alternada"
  fi
else
  echo "  (pulado: cygpath não retornou caminho Windows nesta máquina)"
fi

# --- CASO (g): --remover com limpo+sujo+orfao juntos: remove SO o limpo
#
# N2 (revisor, 2026-09-03): ate esta rodada nenhum caso desta bateria testava
# --remover com um orfao PRESENTE ao lado do limpo/sujo. Mutacao descrita:
# trocar `item.classificacao.status === "limpo"` (limpar-worktrees.cjs:338)
# por `!== "sujo"` fazia --remover apagar tambem os orfaos (e qualquer "erro"),
# e a bateria continuava verde porque nenhum caso tinha um orfao no MESMO lote
# que um --remover de verdade. Este caso fecha essa lacuna.

teste "g" "--remover com limpo+sujo+orfao juntos: remove so o limpo"

repo_g="$SB/repo_g"
work_g="$SB/trabalho_g"
criarRepoComCommit "$repo_g" "$work_g"

wt_g_limpo_real="$work_g/.git/worktrees/wt-g-limpo"
wt_g_sujo_real="$work_g/.git/worktrees/wt-g-sujo"
git worktree add "$wt_g_limpo_real" HEAD
git worktree add "$wt_g_sujo_real" HEAD
cd "$wt_g_sujo_real"
echo "sujeira" > arquivo_g.txt
cd "$work_g"

# Orfao: subdiretorio comum dentro de .git/worktrees, sem .git proprio (mesmo
# desenho do caso (c), mas agora convivendo com um limpo e um sujo no mesmo
# --remover).
orfao_g="$work_g/.git/worktrees/subdir-orfao-g"
mkdir -p "$orfao_g"

# Antes de remover: confirma que o orfao aparece listado
saida_g_lista=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_g" 2>&1)
if echo "$saida_g_lista" | grep -q "órfão"; then
  ok=$((ok+1)); echo "  ok    orfao aparece listado antes de remover"
else
  falhou=$((falhou+1)); echo "  FALHA orfao nao aparece listado antes de remover"
  echo "        Saída: $saida_g_lista"
fi

# Roda --remover com os tres presentes, CAPTURANDO a saida: o `git worktree
# remove` de um diretorio que nao e worktree registrado ja falha sozinho, entao
# "continua no disco" seria verdade nos dois lados (com ou sem a mutacao) e não
# prova nada — o que a linha mutada de fato controla é se o codigo TENTA
# remover o orfao (a mensagem "removendo <path>..." sai incondicionalmente
# para cada item da lista de "limpos", antes do spawnSync que tenta apagar).
saida_g_remover=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_g" --remover 2>&1)
if echo "$saida_g_remover" | grep -qi "removendo.*subdir-orfao-g"; then
  falhou=$((falhou+1)); echo "  FALHA tentou remover o órfão (nem deveria tentar)"
  echo "        Saída: $saida_g_remover"
else
  ok=$((ok+1)); echo "  ok    não tentou remover o órfão"
fi

# O limpo sumiu do git worktree list
lista_g_limpo=$(git worktree list --porcelain | grep -F "wt-g-limpo" || true)
if [ -z "$lista_g_limpo" ]; then
  ok=$((ok+1)); echo "  ok    worktree limpo foi removido (com orfao presente)"
else
  falhou=$((falhou+1)); echo "  FALHA worktree limpo não foi removido"
  echo "        Lista: $lista_g_limpo"
fi

# O sujo continua registrado
lista_g_sujo=$(git worktree list --porcelain | grep -F "wt-g-sujo" || true)
if [ -n "$lista_g_sujo" ]; then
  ok=$((ok+1)); echo "  ok    worktree sujo continua (não removido)"
else
  falhou=$((falhou+1)); echo "  FALHA worktree sujo foi removido (não deveria)"
fi

# O orfao continua NO DISCO
if [ -d "$orfao_g" ]; then
  ok=$((ok+1)); echo "  ok    diretório órfão continua no disco (não removido)"
else
  falhou=$((falhou+1)); echo "  FALHA diretório órfão foi removido do disco (não deveria)"
fi

# E continua LISTADO depois do --remover (nao some da tabela so por --remover
# ter rodado)
saida_g_depois=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_g" 2>&1)
if echo "$saida_g_depois" | grep -q "órfão"; then
  ok=$((ok+1)); echo "  ok    órfão continua listado depois do --remover"
else
  falhou=$((falhou+1)); echo "  FALHA órfão sumiu da listagem depois do --remover"
  echo "        Saída: $saida_g_depois"
fi

# --- Relatório final

echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ] && exit 0 || exit 1
