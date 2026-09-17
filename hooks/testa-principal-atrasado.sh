#!/bin/bash
# Bateria de lib/principal-atrasado.cjs — deteccao de checkout principal atrasado
# de origin/main e de worktrees linkadas ja integradas.
# Uso: bash hooks/testa-principal-atrasado.sh
#
# Esta bateria REESCREVE uma tentativa anterior que nunca commitou e era falsa
# de tres jeitos, e os tres seguem evitados aqui por construcao, nao por sorte:
#
#   1. o `require(./hooks/lib/principal-atrasado.cjs)` sem aspas era erro de
#      sintaxe JS — TODA chamada morria antes de rodar uma linha do modulo.
#      Aqui o caminho do modulo vai por `process.env.LIB_PATH` para um driver
#      em arquivo (nunca por `node -e` com string montada a mao).
#   2. o sufixo `2>/dev/null || echo "[]"` engolia esse erro e devolvia "[]" —
#      que e EXATAMENTE o valor que os casos (b), (c) e (d) esperam. Tres de
#      quatro casos ficavam verdes sem executar uma linha do modulo. Aqui o
#      exit code de cada chamada e checado explicitamente e o stderr vai pra
#      arquivo, nunca pra `|| echo`.
#   3. o caso (a) criava um diretorio chamado `aux` (nome reservado no
#      Windows — `git worktree add` sai 128 com "Invalid argument") e depois
#      dava `checkout -b feature/test` NO PROPRIO PRINCIPAL antes de linkar a
#      mesma branch num worktree, o que o git recusa (branch ja em uso por
#      outro worktree). E o commit novo em `feature/test` por definicao NAO
#      esta contido em origin/main, entao a asserção "já em origin/main"
#      nunca poderia passar. Aqui a branch do worktree e criada apontando
#      para o proprio origin/main (`git branch integrada origin/main`) sem
#      nunca dar checkout nela no principal — contida em origin/main por
#      definicao (é o mesmo commit), sem a colisão.
#
# Ordem de importancia das provas:
#   (a) principal atrasado + worktree ja integrada — o caminho feliz que a
#       Issue #214 pede, com o NUMERO de commits e os CAMINHOS resolvidos
#       pelo proprio modulo (nunca comparados contra um valor que o teste
#       mesmo escolheu — comparados contra o que `git rev-parse
#       --show-toplevel` diz que aquele caminho realmente e);
#   (b), (c), (d) — os tres jeitos de nao ter nada a avisar (sem origin, fora
#       de git, em dia) tem que devolver "[]" sem estourar;
#   (e) o hook de abertura (`foco-session-start.cjs`) precisa CARREGAR essas
#       linhas no texto injetado — modulo certo e fio desconectado do hook
#       da o mesmo resultado pratico: aviso que nunca chega a sessao nenhuma.
#
# A ultima secao (fora deste arquivo, no criterio de pronto da tarefa) e
# MUTACAO: trocar `if (atras > 0)` por `if (atras > 999999)` na lib real e
# rodar esta bateria de novo tem que dar exit != 0. Bateria que fica verde
# com essa mutacao nao prova nada.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
LIB_WIN="$SRC_WIN/hooks/lib/principal-atrasado.cjs"

RAIZ_POSIX="$(mktemp -d)"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ_POSIX)"

ok=0; falhou=0

# Driver A: devolve o JSON.stringify(linhas({cwd})) cru. O caminho do modulo e
# do cwd chegam por env var, sempre em formato C:/... — Node no Windows nao
# resolve caminho MSYS (/tmp/...), e essa conversao ja custou uma rodada
# inteira em outra bateria deste repo (ver testa-gate-worktree.sh).
cat > "$RAIZ_POSIX/driver-linhas.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
process.stdout.write(JSON.stringify(lib.linhas({ cwd: process.env.FIX_CWD })));
EOF

# Driver B: devolve a primeira linha do array que bate com FIX_REGEX, crua (sem
# aspas de JSON) — usado para extrair o caminho que o MODULO decidiu, nunca o
# caminho que o teste escolheu.
cat > "$RAIZ_POSIX/driver-linha.cjs" <<'EOF'
const lib = require(process.env.LIB_PATH);
const arr = lib.linhas({ cwd: process.env.FIX_CWD });
const re = new RegExp(process.env.FIX_REGEX);
const achou = arr.find((l) => re.test(l));
process.stdout.write(achou === undefined ? '' : achou);
EOF

rodar_linhas() { # cwd_posix, arquivo_erro -> stdout=JSON array; $? = exit do node
  local cwd_win; cwd_win="$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")"
  LIB_PATH="$LIB_WIN" FIX_CWD="$cwd_win" node "$RAIZ_POSIX/driver-linhas.cjs" 2>"$2"
}

linha_que_bate() { # cwd_posix, regex, arquivo_erro -> stdout=linha crua ou vazio
  local cwd_win; cwd_win="$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")"
  LIB_PATH="$LIB_WIN" FIX_CWD="$cwd_win" FIX_REGEX="$2" node "$RAIZ_POSIX/driver-linha.cjs" 2>"$3"
}

topo_de() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; } # canoniza um caminho de repo

checa_exit0() { # nome, exit, arquivo_erro
  if [ "$2" = "0" ]; then
    ok=$((ok+1)); echo "  ok    $1 (exit 0)"
  else
    falhou=$((falhou+1)); echo "  FALHA $1: exit=$2"
    sed 's/^/         stderr: /' "$3" 2>/dev/null | head -10
  fi
}

checa_contem() { # nome, agulha, palheiro
  if printf '%s' "$3" | grep -qF "$2"; then
    ok=$((ok+1)); echo "  ok    $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1: nao achei '$2' em: $3"
  fi
}

checa_vazio() { # nome, saida
  if [ "$2" = "[]" ]; then
    ok=$((ok+1)); echo "  ok    $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1: esperava [], veio '$2'"
  fi
}

# Monta: remoto bare local, PRINCIPAL clonado dele, 3 commits so no remoto (via
# clone auxiliar, empurrados sem o principal buscar ate o fetch explicito), e
# um worktree LINKADO numa branch que aponta pro proprio origin/main — contida
# nele por definicao, sem precisar de commit novo nem de checkout no principal.
# Devolve "PRINCIPAL WORKTREE" (caminhos posix, sem espaco) por stdout.
montar_repo_atrasado() {
  local base="$1" bare principal aux wt i
  bare="$base/repo.git"; principal="$base/principal"; aux="$base/auxiliar"; wt="$base/worktree"

  git init -q -b main --bare "$bare"
  git clone -q "$bare" "$principal"
  git -C "$principal" config user.email "t@t"
  git -C "$principal" config user.name "t"
  git -C "$principal" config commit.gpgsign false
  echo base > "$principal/arquivo.txt"
  git -C "$principal" add .
  git -C "$principal" commit -qm base
  git -C "$principal" push -q -u origin main

  git clone -q "$bare" "$aux"
  git -C "$aux" config user.email "t@t"
  git -C "$aux" config user.name "t"
  git -C "$aux" config commit.gpgsign false
  for i in 1 2 3; do
    echo "mudanca $i" >> "$aux/arquivo.txt"
    git -C "$aux" add .
    git -C "$aux" commit -qm "commit $i"
  done
  git -C "$aux" push -q

  # O principal NUNCA busca sozinho (o modulo nao faz fetch — so refs locais);
  # este fetch simula o que ja estaria em cache de uma sessao anterior.
  git -C "$principal" fetch -q origin
  # `git branch <novo> <remoto>` imprime "set up to track..." no STDOUT quando
  # branch.autoSetupMerge esta ligado (padrao) — sem o >/dev/null essa linha
  # contamina o "PRINCIPAL WORKTREE" que esta funcao devolve por stdout.
  git -C "$principal" branch integrada origin/main >/dev/null
  git -C "$principal" worktree add -q "$wt" integrada

  printf '%s %s' "$principal" "$wt"
}

echo
echo "(a) principal 3 commits atras de origin/main + worktree ja integrada"
SANDBOX_A="$RAIZ_POSIX/caso-a"; mkdir -p "$SANDBOX_A"
read -r PRINCIPAL_A WORKTREE_A <<EOF_A
$(montar_repo_atrasado "$SANDBOX_A")
EOF_A

ERRO_A="$RAIZ_POSIX/erro-a.log"
SAIDA_A="$(rodar_linhas "$WORKTREE_A" "$ERRO_A")"; EXIT_A=$?
checa_exit0   "(a) roda sem estourar"                                  "$EXIT_A" "$ERRO_A"
checa_contem  "(a) conta exatamente 3 commits atras"  "3 commit(s) atrás de origin/main" "$SAIDA_A"

ERRO_A_PULL="$RAIZ_POSIX/erro-a-pull.log"
LINHA_PULL="$(linha_que_bate "$WORKTREE_A" 'pull --ff-only' "$ERRO_A_PULL")"
CAMINHO_DA_LINHA="${LINHA_PULL#git -C }"; CAMINHO_DA_LINHA="${CAMINHO_DA_LINHA% pull --ff-only}"
TOPO_LINHA="$(topo_de "$CAMINHO_DA_LINHA")"
TOPO_PRINCIPAL="$(topo_de "$PRINCIPAL_A")"
if [ -n "$LINHA_PULL" ] && [ -n "$TOPO_LINHA" ] && [ "$TOPO_LINHA" = "$TOPO_PRINCIPAL" ]; then
  ok=$((ok+1)); echo "  ok    (a) 'git -C ... pull --ff-only' aponta pro checkout principal de verdade"
else
  falhou=$((falhou+1)); echo "  FALHA (a) linha de pull ('$LINHA_PULL') nao resolve pro principal ($PRINCIPAL_A)"
fi

ERRO_A_WT="$RAIZ_POSIX/erro-a-wt.log"
LINHA_WT="$(linha_que_bate "$WORKTREE_A" 'já em origin/main' "$ERRO_A_WT")"
CAMINHO_WT_LINHA="${LINHA_WT% já em origin/main}"
TOPO_WT_LINHA="$(topo_de "$CAMINHO_WT_LINHA")"
TOPO_WORKTREE="$(topo_de "$WORKTREE_A")"
if [ -n "$LINHA_WT" ] && [ -n "$TOPO_WT_LINHA" ] && [ "$TOPO_WT_LINHA" = "$TOPO_WORKTREE" ]; then
  ok=$((ok+1)); echo "  ok    (a) '... já em origin/main' nomeia o worktree de verdade"
else
  falhou=$((falhou+1)); echo "  FALHA (a) linha de worktree ('$LINHA_WT') nao resolve pro worktree ($WORKTREE_A)"
fi

echo
echo "(b) repo sem origin"
SANDBOX_B="$RAIZ_POSIX/caso-b"; mkdir -p "$SANDBOX_B"
git init -q -b main "$SANDBOX_B"
git -C "$SANDBOX_B" config user.email "t@t"; git -C "$SANDBOX_B" config user.name "t"
git -C "$SANDBOX_B" config commit.gpgsign false
echo x > "$SANDBOX_B/f.txt"; git -C "$SANDBOX_B" add .; git -C "$SANDBOX_B" commit -qm base
ERRO_B="$RAIZ_POSIX/erro-b.log"
SAIDA_B="$(rodar_linhas "$SANDBOX_B" "$ERRO_B")"; EXIT_B=$?
checa_exit0 "(b) roda sem estourar"       "$EXIT_B" "$ERRO_B"
checa_vazio "(b) devolve [] sem origin"   "$SAIDA_B"

echo
echo "(c) pasta fora de git"
SANDBOX_C="$RAIZ_POSIX/caso-c"; mkdir -p "$SANDBOX_C"
ERRO_C="$RAIZ_POSIX/erro-c.log"
SAIDA_C="$(rodar_linhas "$SANDBOX_C" "$ERRO_C")"; EXIT_C=$?
checa_exit0 "(c) roda sem estourar"        "$EXIT_C" "$ERRO_C"
checa_vazio "(c) devolve [] fora de git"   "$SAIDA_C"

echo
echo "(d) principal em dia com origin/main"
SANDBOX_D="$RAIZ_POSIX/caso-d"; mkdir -p "$SANDBOX_D"
BARE_D="$SANDBOX_D/repo.git"; PRINCIPAL_D="$SANDBOX_D/principal"
git init -q -b main --bare "$BARE_D"
git clone -q "$BARE_D" "$PRINCIPAL_D"
git -C "$PRINCIPAL_D" config user.email "t@t"; git -C "$PRINCIPAL_D" config user.name "t"
git -C "$PRINCIPAL_D" config commit.gpgsign false
echo x > "$PRINCIPAL_D/f.txt"; git -C "$PRINCIPAL_D" add .; git -C "$PRINCIPAL_D" commit -qm base
git -C "$PRINCIPAL_D" push -q -u origin main
ERRO_D="$RAIZ_POSIX/erro-d.log"
SAIDA_D="$(rodar_linhas "$PRINCIPAL_D" "$ERRO_D")"; EXIT_D=$?
checa_exit0 "(d) roda sem estourar"     "$EXIT_D" "$ERRO_D"
checa_vazio "(d) devolve [] em dia"     "$SAIDA_D"

echo
echo "(e) o hook de abertura injeta as linhas (foco-session-start.cjs de verdade)"
# cwd do proprio hook mora em CLAUDE_PROJECT_DIR (ou process.cwd()) — NAO em
# RFM_ROOT, que e a raiz de DADOS (FOCO.md etc.) e pode ser uma pasta fora de
# qualquer repo git. Ver o ajuste feito em foco-session-start.cjs por causa
# disso, descrito no relato final.
SANDBOX_E="$RAIZ_POSIX/caso-e"; mkdir -p "$SANDBOX_E"
read -r PRINCIPAL_E WORKTREE_E <<EOF_E
$(montar_repo_atrasado "$SANDBOX_E")
EOF_E
DADOS_E="$RAIZ_POSIX/dados-e"; mkdir -p "$DADOS_E"
DADOS_E_WIN="$(cygpath -m "$DADOS_E" 2>/dev/null || printf '%s' "$DADOS_E")"
WORKTREE_E_WIN="$(cygpath -m "$WORKTREE_E" 2>/dev/null || printf '%s' "$WORKTREE_E")"
ERRO_E="$RAIZ_POSIX/erro-e.log"
SAIDA_HOOK="$(RFM_ROOT="$DADOS_E_WIN" CLAUDE_PROJECT_DIR="$WORKTREE_E_WIN" WHATSAPP_API_BASE_URL="http://127.0.0.1:1/api" node "$SRC/hooks/foco-session-start.cjs" 2>"$ERRO_E")"
EXIT_HOOK=$?
checa_exit0 "(e) hook roda sem estourar" "$EXIT_HOOK" "$ERRO_E"

cat > "$RAIZ_POSIX/extrai-contexto.cjs" <<'EOF'
let bruto = '';
process.stdin.on('data', (d) => { bruto += d; });
process.stdin.on('end', () => {
  try {
    const j = JSON.parse(bruto);
    process.stdout.write((j.hookSpecificOutput && j.hookSpecificOutput.additionalContext) || '');
  } catch {
    process.stdout.write('');
  }
});
EOF
TEXTO_HOOK="$(printf '%s' "$SAIDA_HOOK" | node "$RAIZ_POSIX/extrai-contexto.cjs")"
checa_contem "(e) o texto injetado avisa dos commits atrasados" "3 commit(s) atrás de origin/main" "$TEXTO_HOOK"
checa_contem "(e) o texto injetado nomeia o worktree integrado" "já em origin/main"                "$TEXTO_HOOK"


echo
echo "(f) principal em dia alcancado por OUTRA GRAFIA do mesmo diretorio"
# Achado na CI, nao aqui: o caso (d) passou nesta maquina e reprovou no runner
# com `["<...>/caso-d/principal ja em origin/main"]` — o principal se listando a
# si mesmo. Mecanismo: `git rev-parse --git-common-dir` devolve `.git` RELATIVO,
# entao o caminho do principal nasce do cwd que o chamador passou, enquanto o
# `git worktree list` imprime a grafia canonica do git. Grafias diferentes do
# mesmo diretorio (8.3 curto x longo no runner; junction aqui) nao casam como
# string, e a comparacao textual deixava o principal entrar na propria lista.
# A junction reproduz o defeito de forma deterministica: sem o conserto, esta
# chamada devolve uma linha; com ele, devolve [].
SANDBOX_F="$RAIZ_POSIX/caso-f"; mkdir -p "$SANDBOX_F"
BARE_F="$SANDBOX_F/repo.git"; PRINCIPAL_F="$SANDBOX_F/principal"
git init -q -b main --bare "$BARE_F"
git clone -q "$BARE_F" "$PRINCIPAL_F"
git -C "$PRINCIPAL_F" config user.email "t@t"; git -C "$PRINCIPAL_F" config user.name "t"
git -C "$PRINCIPAL_F" config commit.gpgsign false
echo x > "$PRINCIPAL_F/f.txt"; git -C "$PRINCIPAL_F" add .; git -C "$PRINCIPAL_F" commit -qm base
git -C "$PRINCIPAL_F" push -q -u origin main

ATALHO_F="$SANDBOX_F/atalho"
CRIOU_ATALHO=0
if command -v cmd >/dev/null 2>&1; then
  ( cd "$SANDBOX_F" && cmd //c mklink //J atalho principal ) >/dev/null 2>&1 && CRIOU_ATALHO=1
elif ln -s "$PRINCIPAL_F" "$ATALHO_F" 2>/dev/null; then
  CRIOU_ATALHO=1
fi

if [ "$CRIOU_ATALHO" = "1" ]; then
  ERRO_F="$RAIZ_POSIX/erro-f.log"
  SAIDA_F="$(rodar_linhas "$ATALHO_F" "$ERRO_F")"; EXIT_F=$?
  checa_exit0 "(f) roda sem estourar pela outra grafia" "$EXIT_F" "$ERRO_F"
  checa_vazio "(f) o principal nao se lista por grafia diferente" "$SAIDA_F"
else
  echo "  PULADO (f): nao consegui criar junction nem symlink nesta maquina"
fi

echo
echo "(g) 33 worktrees linkados (15 mergeados + 15 nao + 3 detached): no maximo 4 chamadas a git"
# Issue #243 (D2 e D4 do zerar-issues-3): a versao anterior da lib fazia um
# `git symbolic-ref` por worktree e um `merge-base` por branch — 324 processos
# em 7,8 s numa maquina com 308 worktrees, acima dos 5 s que o hooks.json da ao
# hook de abertura. O que se afirma aqui e o NUMERO de chamadas externas, nunca
# tempo de relogio (tempo sob carga oscila; contagem nao). O contador e um
# preload que embrulha child_process ANTES de a lib fazer o `require`, e grava
# o total num arquivo — zero chamadas significaria que o embrulho nao pegou, e
# tambem reprova.
#
# Fixture: cada branch nasce ja no `worktree add -b <x> origin/main` (nunca
# checkout no principal, ver o cabecalho); as "nao mergeadas" ganham um commit
# proprio dentro do proprio worktree. A contagem de worktrees registrados e
# afirmada antes das asserções de conteudo: fixture que nao montou (clone em
# diretorio ocupado, `aux` reservado no Windows) nao pode passar por "as 15 nao
# aparecem" — foi exatamente o que a revisao pegou na primeira versao deste caso.
SANDBOX_G="$RAIZ_POSIX/caso-g"; mkdir -p "$SANDBOX_G"
BARE_G="$SANDBOX_G/repo.git"; PRINCIPAL_G="$SANDBOX_G/principal"
git init -q -b main --bare "$BARE_G"
git clone -q "$BARE_G" "$PRINCIPAL_G"
git -C "$PRINCIPAL_G" config user.email "t@t"; git -C "$PRINCIPAL_G" config user.name "t"
git -C "$PRINCIPAL_G" config commit.gpgsign false
echo base > "$PRINCIPAL_G/arquivo.txt"; git -C "$PRINCIPAL_G" add arquivo.txt; git -C "$PRINCIPAL_G" commit -qm base
git -C "$PRINCIPAL_G" push -q -u origin main

for i in $(seq 1 15); do
  git -C "$PRINCIPAL_G" worktree add -q "$SANDBOX_G/wt-mergeada-$i" -b "mergeada-$i" origin/main
done
for i in $(seq 1 15); do
  WT_NAO="$SANDBOX_G/wt-nao-mergeada-$i"
  git -C "$PRINCIPAL_G" worktree add -q "$WT_NAO" -b "nao-mergeada-$i" origin/main
  git -C "$WT_NAO" config user.email "t@t"; git -C "$WT_NAO" config user.name "t"
  git -C "$WT_NAO" config commit.gpgsign false
  echo "commit $i" > "$WT_NAO/g-$i.txt"; git -C "$WT_NAO" add "g-$i.txt"; git -C "$WT_NAO" commit -qm "commit $i"
done
for i in 1 2 3; do
  git -C "$PRINCIPAL_G" worktree add -q --detach "$SANDBOX_G/wt-detached-$i" HEAD
done

REGISTRADOS_G="$(git -C "$PRINCIPAL_G" worktree list --porcelain | grep -c '^worktree ')"
if [ "$REGISTRADOS_G" = "34" ]; then
  ok=$((ok+1)); echo "  ok    (g) fixture montou: 34 worktrees registrados (principal + 33)"
else
  falhou=$((falhou+1)); echo "  FALHA (g) fixture nao montou: $REGISTRADOS_G worktrees registrados (esperava 34)"
fi

# Driver C: preload que conta toda chamada sincrona a processo externo. Roda
# por `node -r` ANTES do driver A, entao a lib ja encontra child_process
# embrulhado quando faz o `require`. O total sai por arquivo (FIX_CONTAGEM),
# nao pelo stdout, que e do JSON do driver.
cat > "$RAIZ_POSIX/preload-conta.cjs" <<'EOF'
const cp = require('child_process');
let n = 0;
for (const nome of ['execFileSync', 'spawnSync', 'execSync']) {
  const orig = cp[nome];
  cp[nome] = function (...args) { n++; return orig.apply(this, args); };
}
process.on('exit', () => { require('fs').writeFileSync(process.env.FIX_CONTAGEM, String(n)); });
EOF

rodar_linhas_contando() { # cwd_posix, arquivo_erro, arquivo_contagem -> stdout=JSON array; $? = exit do node
  local cwd_win; cwd_win="$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")"
  local preload_win; preload_win="$(cygpath -m "$RAIZ_POSIX/preload-conta.cjs" 2>/dev/null || printf '%s' "$RAIZ_POSIX/preload-conta.cjs")"
  local contagem_win; contagem_win="$(cygpath -m "$3" 2>/dev/null || printf '%s' "$3")"
  LIB_PATH="$LIB_WIN" FIX_CWD="$cwd_win" FIX_CONTAGEM="$contagem_win" node -r "$preload_win" "$RAIZ_POSIX/driver-linhas.cjs" 2>"$2"
}

ERRO_G="$SANDBOX_G/erro-g.log"; CONTAGEM_G="$SANDBOX_G/contagem-g.txt"
SAIDA_G="$(rodar_linhas_contando "$PRINCIPAL_G" "$ERRO_G" "$CONTAGEM_G")"; EXIT_G=$?
checa_exit0 "(g) driver roda sem estourar com 33 worktrees" "$EXIT_G" "$ERRO_G"

CHAMADAS_G="$(cat "$CONTAGEM_G" 2>/dev/null || printf 'sem-arquivo')"
case "$CHAMADAS_G" in
  1|2|3|4) ok=$((ok+1)); echo "  ok    (g) $CHAMADAS_G chamada(s) externa(s) com 33 worktrees (teto 4)" ;;
  0)       falhou=$((falhou+1)); echo "  FALHA (g) contador registrou 0 chamadas: o preload nao embrulhou child_process" ;;
  *)       falhou=$((falhou+1)); echo "  FALHA (g) $CHAMADAS_G chamadas externas com 33 worktrees (teto 4) — voltou a pagar por worktree" ;;
esac

# Tarefa 19: o teto (MAX_WORKTREES_LISTADOS = 2) corta a lista de mergeados;
# dos 15, so 2 aparecem nomeados e o resto vira 1 linha de resumo.
MERGEADAS_LISTADAS=0
for i in $(seq 1 15); do
  if printf '%s' "$SAIDA_G" | grep -qF "wt-mergeada-$i "; then
    MERGEADAS_LISTADAS=$((MERGEADAS_LISTADAS + 1))
  fi
done
if [ "$MERGEADAS_LISTADAS" = "2" ]; then
  ok=$((ok+1)); echo "  ok    (g) so 2 dos 15 worktrees mergeados aparecem nomeados (teto)"
else
  falhou=$((falhou+1)); echo "  FALHA (g) $MERGEADAS_LISTADAS de 15 worktrees mergeados nomeados (esperava 2, teto): $SAIDA_G"
fi
checa_contem "(g) linha de resumo com os 13 excedentes" '(+13 worktree(s) já em origin/main — rode o limpar)' "$SAIDA_G"

NAO_LISTADAS=0
for i in $(seq 1 15); do
  if printf '%s' "$SAIDA_G" | grep -qF "wt-nao-mergeada-$i "; then
    NAO_LISTADAS=$((NAO_LISTADAS + 1))
  fi
done
if [ "$NAO_LISTADAS" = "0" ]; then
  ok=$((ok+1)); echo "  ok    (g) nenhum dos 15 worktrees com commit proprio aparece"
else
  falhou=$((falhou+1)); echo "  FALHA (g) $NAO_LISTADAS worktree(s) com commit proprio listados como mergeados: $SAIDA_G"
fi

DETACHED_LISTADAS=0
for i in 1 2 3; do
  if printf '%s' "$SAIDA_G" | grep -qF "wt-detached-$i "; then
    DETACHED_LISTADAS=$((DETACHED_LISTADAS + 1))
  fi
done
if [ "$DETACHED_LISTADAS" = "0" ]; then
  ok=$((ok+1)); echo "  ok    (g) nenhum dos 3 worktrees detached aparece"
else
  falhou=$((falhou+1)); echo "  FALHA (g) $DETACHED_LISTADAS worktree(s) detached listados: $SAIDA_G"
fi

echo
echo "(h) worktree registrado cujo diretorio foi apagado (prunable) nao aparece nem derruba"
SANDBOX_H="$RAIZ_POSIX/caso-h"; mkdir -p "$SANDBOX_H"
BARE_H="$SANDBOX_H/repo.git"; PRINCIPAL_H="$SANDBOX_H/principal"
git init -q -b main --bare "$BARE_H"
git clone -q "$BARE_H" "$PRINCIPAL_H"
git -C "$PRINCIPAL_H" config user.email "t@t"; git -C "$PRINCIPAL_H" config user.name "t"
git -C "$PRINCIPAL_H" config commit.gpgsign false
echo x > "$PRINCIPAL_H/h.txt"; git -C "$PRINCIPAL_H" add h.txt; git -C "$PRINCIPAL_H" commit -qm base
git -C "$PRINCIPAL_H" push -q -u origin main

# Branch em origin/main (seria listada como "ja em origin/main" se o diretorio
# existisse) — e o diretorio somem por fora do git, sem `worktree remove`.
WT_PRUNABLE="$SANDBOX_H/wt-prunable"
git -C "$PRINCIPAL_H" worktree add -q "$WT_PRUNABLE" -b sumida origin/main
rm -rf "$WT_PRUNABLE"
if git -C "$PRINCIPAL_H" worktree list --porcelain | grep -q '^prunable'; then
  ok=$((ok+1)); echo "  ok    (h) o git marca o worktree como prunable"
else
  falhou=$((falhou+1)); echo "  FALHA (h) o git nao marcou o worktree como prunable; o caso nao testa nada"
fi

ERRO_H="$SANDBOX_H/erro-h.log"
SAIDA_H="$(rodar_linhas "$PRINCIPAL_H" "$ERRO_H")"; EXIT_H=$?
checa_exit0 "(h) worktree prunable nao derruba a funcao" "$EXIT_H" "$ERRO_H"
checa_vazio "(h) worktree prunable nao e listado" "$SAIDA_H"

# Fixture para (i) e (j): repo com N worktrees linkados, todos ja mesclados em
# origin/main (cada um `worktree add -b <x> origin/main`, sem commit proprio).
# Devolve o caminho do PRINCIPAL por stdout.
montar_repo_so_mescladas() { # base, n -> stdout PRINCIPAL
  local base="$1" n="$2" bare principal i
  bare="$base/repo.git"; principal="$base/principal"
  git init -q -b main --bare "$bare"
  git clone -q "$bare" "$principal"
  git -C "$principal" config user.email "t@t"
  git -C "$principal" config user.name "t"
  git -C "$principal" config commit.gpgsign false
  echo base > "$principal/arquivo.txt"
  git -C "$principal" add .
  git -C "$principal" commit -qm base
  git -C "$principal" push -q -u origin main
  for i in $(seq 1 "$n"); do
    git -C "$principal" worktree add -q "$base/wt-$i" -b "mesclada-so-$i" origin/main
  done
  printf '%s' "$principal"
}

# Conta so os elementos do array JSON que TERMINAM em 'já em origin/main'
# (o `"` de fechamento da string vem logo depois) — a linha de resumo tambem
# contem a frase 'já em origin/main' no meio, e nao pode ser contada aqui.
conta_ja_mescladas() { # saida_json -> numero (stdout)
  printf '%s' "$1" | grep -o 'já em origin/main"' | wc -l | tr -d ' '
}

echo
echo "(i) 5 worktrees ja mesclados: 2 listados + 1 linha de resumo"
SANDBOX_I="$RAIZ_POSIX/caso-i"; mkdir -p "$SANDBOX_I"
PRINCIPAL_I="$(montar_repo_so_mescladas "$SANDBOX_I" 5)"
ERRO_I="$RAIZ_POSIX/erro-i.log"
SAIDA_I="$(rodar_linhas "$PRINCIPAL_I" "$ERRO_I")"; EXIT_I=$?
checa_exit0 "(i) roda sem estourar" "$EXIT_I" "$ERRO_I"

LISTADAS_I="$(conta_ja_mescladas "$SAIDA_I")"
if [ "$LISTADAS_I" = "2" ]; then
  ok=$((ok+1)); echo "  ok    (i) exatamente 2 linhas terminam em 'ja em origin/main'"
else
  falhou=$((falhou+1)); echo "  FALHA (i) $LISTADAS_I linhas 'ja em origin/main' (esperava 2): $SAIDA_I"
fi
checa_contem "(i) linha de resumo com o numero e o comando" '(+3 worktree(s) já em origin/main — rode o limpar)' "$SAIDA_I"

echo
echo "(j) 2 worktrees ja mesclados: as 2 linhas, sem linha de resumo"
SANDBOX_J="$RAIZ_POSIX/caso-j"; mkdir -p "$SANDBOX_J"
PRINCIPAL_J="$(montar_repo_so_mescladas "$SANDBOX_J" 2)"
ERRO_J="$RAIZ_POSIX/erro-j.log"
SAIDA_J="$(rodar_linhas "$PRINCIPAL_J" "$ERRO_J")"; EXIT_J=$?
checa_exit0 "(j) roda sem estourar" "$EXIT_J" "$ERRO_J"

LISTADAS_J="$(conta_ja_mescladas "$SAIDA_J")"
if [ "$LISTADAS_J" = "2" ]; then
  ok=$((ok+1)); echo "  ok    (j) as 2 linhas aparecem, sem corte"
else
  falhou=$((falhou+1)); echo "  FALHA (j) $LISTADAS_J linhas 'ja em origin/main' (esperava 2): $SAIDA_J"
fi
if printf '%s' "$SAIDA_J" | grep -qF 'rode o limpar'; then
  falhou=$((falhou+1)); echo "  FALHA (j) linha de resumo apareceu sem excedente: $SAIDA_J"
else
  ok=$((ok+1)); echo "  ok    (j) nenhuma linha de resumo (sem excedente)"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" = "0" ] || exit 1
