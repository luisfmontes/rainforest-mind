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

# Cria um worktree limpo. S2 (8a revisao, rodada 10, lote 3, 2026-09-03): o
# checkout tem de ficar FORA de `.git/worktrees/<nome>` — colocar o checkout
# ALI faz o checkout e a pasta administrativa do proprio git (HEAD,
# ORIG_HEAD, commondir, gitdir, index, logs/) coincidirem no mesmo diretorio,
# um layout que `git worktree add` nunca produz sozinho e que nenhum worktree
# real deste projeto usa (os de verdade ficam em `.claude/worktrees/`,
# irmaos do repo, nunca dentro de `.git`). Confirmado na caixa: um worktree
# de verdade, com o checkout FORA de `.git/worktrees`, nunca lista nenhum
# desses nomes no porcelain.
wt_a_real="$work_a-worktrees/wt-a"
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

# Cria um worktree com sujeira (checkout fora de .git/worktrees, ver caso a)
wt_b_real="$work_b-worktrees/wt-b"
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

# Cria um worktree de verdade (checkout fora de .git/worktrees, ver caso a)
wt_c_real="$repo_c-worktrees/wt-c"
git worktree add "$wt_c_real" HEAD

# Cria um subdiretório comum (sem .git próprio) ao lado do worktree, no MESMO
# pai que `listarWorktreesDoDisco` infere do primeiro worktree registrado
subdir_comum="$repo_c-worktrees/subdir-comum"
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

# Cria dois worktrees: um limpo, um sujo (checkout fora de .git/worktrees, ver caso a)
wt_d_limpo_real="$work_d-worktrees/wt-limpo"
wt_d_sujo_real="$work_d-worktrees/wt-sujo"

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

wt_e_real="$work_e-worktrees/wt-e"
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

wt_f_real="$work_f-worktrees/wt-f"
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

wt_g_limpo_real="$work_g-worktrees/wt-g-limpo"
wt_g_sujo_real="$work_g-worktrees/wt-g-sujo"
git worktree add "$wt_g_limpo_real" HEAD
git worktree add "$wt_g_sujo_real" HEAD
cd "$wt_g_sujo_real"
echo "sujeira" > arquivo_g.txt
cd "$work_g"

# Orfao: subdiretorio comum no MESMO pai dos worktrees de verdade (checkout
# fora de .git/worktrees, ver caso a), sem .git proprio (mesmo desenho do
# caso (c), mas agora convivendo com um limpo e um sujo no mesmo --remover).
orfao_g="$work_g-worktrees/subdir-orfao-g"
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

# --- CASO (h): worktree com logs/app.log NÃO RASTREADO é 'sujo', e --remover
# NÃO o remove (arquivo continua no disco)
#
# S2 (8a revisao, rodada 10, lote 3, 2026-09-03): a lista de exclusao de
# `classificar()` filtrava a linha `?? logs/` do porcelain (achava que era
# arquivo especial do worktree) — um worktree com log de verdade, nao
# rastreado, virava "limpo" e `--remover` apagava o diretorio (e o log
# dentro dele) sem dar chance de conferir. Reproduzido na caixa antes do
# conserto: `git status --porcelain` com `logs/app.log` nao rastreado
# devolvia so `?? logs/`, que a lista excluia inteira.

teste "h" "worktree com logs/app.log não rastreado é 'sujo' e --remover não o apaga"

repo_h="$SB/repo_h"
work_h="$SB/trabalho_h"
criarRepoComCommit "$repo_h" "$work_h"

wt_h_real="$work_h-worktrees/wt-h"
git worktree add "$wt_h_real" HEAD
mkdir -p "$wt_h_real/logs"
echo "log de verdade, nao rastreado" > "$wt_h_real/logs/app.log"

saida_h=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_h" 2>&1)
if echo "$saida_h" | grep -q "sujo"; then
  ok=$((ok+1)); echo "  ok    worktree com logs/app.log não rastreado é 'sujo'"
else
  falhou=$((falhou+1)); echo "  FALHA worktree com logs/app.log não rastreado não apareceu como 'sujo'"
  echo "        Saída: $saida_h"
fi

node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_h" --remover >/dev/null 2>&1
ls_h=$(ls "$wt_h_real/logs/app.log" 2>&1)
if [ -f "$wt_h_real/logs/app.log" ]; then
  ok=$((ok+1)); echo "  ok    logs/app.log continua no disco depois do --remover (ls: $ls_h)"
else
  falhou=$((falhou+1)); echo "  FALHA logs/app.log foi removido do disco (não deveria): $ls_h"
fi

# --- CASO (i): worktree com 'index' NÃO RASTREADO na raiz é 'sujo'
#
# Mesma causa do caso (h): a lista de exclusão também filtrava a linha
# `?? index` — um arquivo de usuário chamado literalmente "index" na raiz
# do worktree (nome comum, sem relação com o admin file do git) virava
# invisível para a classificação.

teste "i" "worktree com arquivo 'index' não rastreado na raiz é 'sujo'"

repo_i="$SB/repo_i"
work_i="$SB/trabalho_i"
criarRepoComCommit "$repo_i" "$work_i"

wt_i_real="$work_i-worktrees/wt-i"
git worktree add "$wt_i_real" HEAD
echo "arquivo de usuario, nao rastreado" > "$wt_i_real/index"

saida_i=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_i" 2>&1)
if echo "$saida_i" | grep -q "sujo"; then
  ok=$((ok+1)); echo "  ok    worktree com 'index' não rastreado na raiz é 'sujo'"
else
  falhou=$((falhou+1)); echo "  FALHA worktree com 'index' não rastreado na raiz não apareceu como 'sujo'"
  echo "        Saída: $saida_i"
fi

# --- CASO (j): worktree limpo DE VERDADE (sem sujeira nenhuma) é removido
#
# Fecha o contraste com (h)/(i): sem a lista de exclusão, um worktree que
# não tem NADA no porcelain continua sendo removido normalmente.

teste "j" "worktree limpo de verdade (porcelain vazio) é removido"

repo_j="$SB/repo_j"
work_j="$SB/trabalho_j"
criarRepoComCommit "$repo_j" "$work_j"

wt_j_real="$work_j-worktrees/wt-j"
git worktree add "$wt_j_real" HEAD

node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_j" --remover >/dev/null 2>&1
lista_j=$(git -C "$work_j" worktree list --porcelain | grep -F "wt-j" || true)
if [ -z "$lista_j" ]; then
  ok=$((ok+1)); echo "  ok    worktree limpo de verdade foi removido"
else
  falhou=$((falhou+1)); echo "  FALHA worktree limpo de verdade não foi removido"
  echo "        Lista: $lista_j"
fi

# --- CASO (k): registro travado com diretorio ausente é destravado, removido e podado
#
# Tarefa 7 (lote 4): fantasma-travado — registro que existe em `git worktree
# list --porcelain` com `locked`, mas o diretório sumiu do disco. `git worktree
# prune` não limpa porque está travado; `git worktree unlock + remove --force +
# prune` limpa.

teste "k" "registro travado com diretorio ausente é destravado, removido e podado"

repo_k="$SB/repo_k"
work_k="$SB/trabalho_k"
criarRepoComCommit "$repo_k" "$work_k"

# Cria um worktree
wt_k_real="$work_k-worktrees/wt-k"
git worktree add "$wt_k_real" HEAD

# Trava o worktree
git worktree lock "$wt_k_real"

# Apaga o diretório do disco (deixando o registro travado)
rm -rf "$wt_k_real"

# Confirma que git worktree prune NÃO limpa enquanto estiver travado
git worktree prune 2>/dev/null || true
lista_k_prune=$(git worktree list --porcelain | grep -F "wt-k" || true)
if [ -n "$lista_k_prune" ]; then
  ok=$((ok+1)); echo "  ok    git worktree prune não limpa registro travado (com dir ausente)"
else
  falhou=$((falhou+1)); echo "  FALHA git worktree prune limpou registro travado"
fi

# Roda limpar-worktrees com --remover
saida_k_remover=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_k" --remover 2>&1)
exit_k=$?

# Verifica que saiu com exit 0
if [ $exit_k -eq 0 ]; then
  ok=$((ok+1)); echo "  ok    limpar-worktrees sai com exit 0"
else
  falhou=$((falhou+1)); echo "  FALHA limpar-worktrees saiu com exit $exit_k"
  echo "        Saída: $saida_k_remover"
fi

# Verifica que o registro foi removido (não aparece em git worktree list)
lista_k_after=$(git worktree list --porcelain | grep -F "wt-k" || true)
if [ -z "$lista_k_after" ]; then
  ok=$((ok+1)); echo "  ok    fantasma-travado foi destravar, remover e podar"
else
  falhou=$((falhou+1)); echo "  FALHA fantasma-travado ainda aparece em git worktree list"
  echo "        Lista: $lista_k_after"
fi

# --- CASO (l): worktree travado COM DIRETÓRIO PRESENTE continua listado após --remover
#
# Invariante crítica: --remover nunca toca em worktree vivo (com diretório
# presente), mesmo que esteja travado. Só fantasma-travado é removível.

teste "l" "worktree travado com diretorio presente continua listado após --remover"

repo_l="$SB/repo_l"
work_l="$SB/trabalho_l"
criarRepoComCommit "$repo_l" "$work_l"

# Cria um worktree
wt_l_real="$work_l-worktrees/wt-l"
git worktree add "$wt_l_real" HEAD

# Trava o worktree (mas deixa o diretório intacto)
git worktree lock "$wt_l_real"

# Roda limpar-worktrees com --remover
node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_l" --remover 2>&1 | grep -i "remov" || true

# Verifica que o worktree CONTINUA no git worktree list
lista_l=$(git worktree list --porcelain | grep -F "wt-l" || true)
if [ -n "$lista_l" ]; then
  ok=$((ok+1)); echo "  ok    worktree travado com diretório presente continua listado"
else
  falhou=$((falhou+1)); echo "  FALHA worktree travado com diretório presente foi removido"
  echo "        Lista: $lista_l"
fi

# Verifica que o diretório CONTINUA no disco
if [ -d "$wt_l_real" ]; then
  ok=$((ok+1)); echo "  ok    diretório do worktree travado continua no disco"
else
  falhou=$((falhou+1)); echo "  FALHA diretório do worktree travado foi removido do disco"
fi

# --- CASO (m): worktree limpo COM agente em voo nao e removido

# "Limpo" quer dizer "sem alteracao pendente", e agente que acabou de commitar
# deixa o worktree dele exatamente assim — ainda trabalhando. Ate a auditoria do
# lote 4, `--remover` apagava por baixo dele. O registro de `em_voo` (D16) e
# quem responde "tem alguem ai dentro?" sem heuristica de mtime nem de processo.

teste "m" "worktree limpo com agente em voo nao e removido"

repo_m="$SB/repo_m"
work_m="$SB/trabalho_m"
criarRepoComCommit "$repo_m" "$work_m"

# A resolucao de estagio casa o nome da branch com o slug sem o prefixo de data.
wt_m_real="$work_m-worktrees/wt-m"
git worktree add -b fluxo/lote-em-voo "$wt_m_real" HEAD

SLUG_M="2026-09-05-lote-em-voo"
mkdir -p "$wt_m_real/docs/rainforest/estado"
node -e '
const fs = require("fs"), [p, slug] = process.argv.slice(1);
fs.writeFileSync(p, JSON.stringify({
  slug, titulo: "Fixture do caso m", criado_em: "2026-09-05",
  arqueologia: { status: "dispensada" },
  design: { status: "aprovado", em: "2026-09-05", doc: "x" },
  plano: { status: "ok", em: "2026-09-05" },
  executar: { status: "parcial", em: "2026-09-05", em_voo: [{ agente: "rainforest-mind:executor", tarefa: 3 }] },
  revisar: { status: "pendente" },
  verificar: { status: "pendente" },
  fechar: { status: "pendente" },
}, null, 2) + "\n");
' "$wt_m_real/docs/rainforest/estado/$SLUG_M.json" "$SLUG_M"

# O estado precisa estar COMMITADO: worktree com arquivo novo nao rastreado nao
# e "limpo", e o caso mediria a sujeira em vez da consulta ao em_voo.
git -C "$wt_m_real" add docs
git -C "$wt_m_real" commit -qm "estado com agente em voo"

saida_m=$(node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_m" --remover 2>&1)

if git -C "$work_m" worktree list --porcelain | grep -qF "wt-m"; then
  ok=$((ok+1)); echo "  ok    worktree com agente em voo continua listado"
else
  falhou=$((falhou+1)); echo "  FALHA worktree com agente em voo foi removido"
fi

if printf '%s' "$saida_m" | grep -qF "em voo"; then
  ok=$((ok+1)); echo "  ok    e a saida diz por que pulou"
else
  falhou=$((falhou+1)); echo "  FALHA a saida nao explica o motivo"
  printf '%s\n' "$saida_m" | sed 's/^/        /' | head -8
fi

# Contraprova: dando baixa no em_voo, o MESMO worktree volta a ser removivel.
# Sem ela o caso acima passaria por qualquer motivo — inclusive por o script ter
# parado de remover coisa nenhuma.
node -e '
const fs = require("fs"), [p] = process.argv.slice(1);
const e = JSON.parse(fs.readFileSync(p, "utf8"));
e.executar.em_voo = [];
fs.writeFileSync(p, JSON.stringify(e, null, 2) + "\n");
' "$wt_m_real/docs/rainforest/estado/$SLUG_M.json"
git -C "$wt_m_real" add docs
git -C "$wt_m_real" commit -qm "baixa do em_voo"

node "$SRC/scripts/limpar-worktrees.cjs" --raiz "$work_m" --remover > /dev/null 2>&1
if git -C "$work_m" worktree list --porcelain | grep -qF "wt-m"; then
  falhou=$((falhou+1)); echo "  FALHA sem em_voo o worktree limpo continuou registrado"
else
  ok=$((ok+1)); echo "  ok    dada a baixa no em_voo, o mesmo worktree e removido"
fi
# --- Relatório final

echo ""
echo "== resultado: $ok ok, $falhou falha(s) =="
[ $falhou -eq 0 ] && exit 0 || exit 1
