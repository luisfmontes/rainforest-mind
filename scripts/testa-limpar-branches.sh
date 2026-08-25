#!/bin/bash
# Bateria do scripts/limpar-branches.cjs — o unico script deste repo que APAGA
# trabalho. Por isso a bateria e escrita ao contrario das outras: o que ela precisa
# provar em primeiro lugar nao e que a limpeza limpa, e sim que ela RECUSA.
#
#   1. `viva` (nao mergeada, remoto de pe) nunca entra na remocao — nem com
#      --forcar, que e a flag feita para atropelar o resto;
#   2. `sumiu-divergente` (upstream apagado, base nao contem os commits — o caso do
#      squash merge) fica de fora sem --forcar, porque so o -D a alcanca;
#   3. remover fora da base e RECUSADO, e remover com a base atrasada tambem. Tudo
#      aqui e medido contra a base LOCAL: base velha faz branch mergeada parecer
#      viva, e ai a limpeza nao limpa e parece que nao havia o que limpar;
#   4. o toggle `branch-forcar` liga o -D pelo config — e config QUEBRADA nao liga.
#      Esta e a unica chave do repo em que o lado seguro da falha e o DESLIGADO, e
#      um JSON corrompido nao pode virar `git branch -D`;
#   5. o SHA de cada branch removida sai na tela, senao o -D e irreversivel na
#      pratica (o reflog guarda, mas ninguem procura).
#
# E o motivo de o script existir, que vale como teste tambem: o comando que o usuario
# ja usava (`git branch -vv | grep ' gone]'`) nao enxerga branch SEM upstream — e
# eram justamente essas as sete que estavam sobrando no repo dele.
#
# A ultima secao e MUTACAO: mete `viva` na lista de removiveis e exige que o item 1
# pare de passar.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
tem()     { if echo "$2" | grep -qF "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }

roda() { ( cd "$SBP/local" && CLAUDE_PROJECT_DIR="$SBP/local" node "$SRC/scripts/limpar-branches.cjs" "$@" 2>&1 ); }

# ---------------------------------------------------------------- o cenario
# Um repo com as quatro formas que importam, montadas contra um remoto de verdade
# (bare local) — `gone` so existe se houver remoto que apague a branch.
montar() {
  rm -rf "$SBP/local" "$SBP/remoto" "$SBP/outro"
  git init --bare -q "$SBP/remoto"
  git init -q -b main "$SBP/local"
  cd "$SBP/local"
  git config user.email t@t; git config user.name t
  echo base > base.txt; git add .; git commit -qm base
  git remote add origin "$SBP/remoto"; git push -q -u origin main

  # viva: nao mergeada, upstream de pe
  git checkout -qb viva; echo v > v.txt; git add .; git commit -qm v; git push -q -u origin viva

  # resolvida-local: mergeada, nunca empurrada (o residuo de worktree de agente)
  git checkout -q main; git checkout -qb resolvida; echo r > r.txt; git add .; git commit -qm r
  git checkout -q main; git merge -q --no-ff -m m resolvida; git push -q origin main

  # sumiu-divergente: upstream apagado, commits fora da base (squash merge)
  git checkout -qb squashed; echo s > s.txt; git add .; git commit -qm s
  git push -q -u origin squashed; git push -q origin --delete squashed
  git checkout -q main
}

alvos() { roda --sem-fetch --json "$@" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.stringify(JSON.parse(d).alvos)))"; }
classe() { roda --sem-fetch --json | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const b=JSON.parse(d).refs.find(x=>x.nome===process.argv[1]);console.log(b?b.classe:'(ausente)')})" "$1"; }

echo "== 1. classificacao =="
montar
tem "viva e classificada como viva"                  "$(classe viva)"      "viva"
tem "mergeada sem upstream e resolvida-local"        "$(classe resolvida)" "resolvida-local"
tem "upstream apagado + divergente e sumiu-divergente" "$(classe squashed)" "sumiu-divergente"
tem "a base e marcada como base"                     "$(classe main)"      "base"

echo
echo "== 2. o que NUNCA sai =="
A="$(alvos)"
nao_tem "viva fica fora dos alvos"                   "$A" "viva"
nao_tem "a base fica fora dos alvos"                 "$A" "main"
tem     "resolvida-local entra"                      "$A" "resolvida"
nao_tem "sumiu-divergente fica fora sem --forcar"    "$A" "squashed"

AF="$(alvos --forcar)"
nao_tem "viva fica fora MESMO com --forcar"          "$AF" "viva"
tem     "sumiu-divergente entra com --forcar"        "$AF" "squashed"

echo
echo "== 3. exigencia de estar na base, em dia =="
git -C "$SBP/local" checkout -qb outro-lugar
S="$(roda --sem-fetch --remover)"
tem      "fora da base, a remocao e cancelada"       "$S" "REMOCAO CANCELADA"
tem      "e diz onde voce esta"                      "$S" "voce esta em 'outro-lugar'"
nao_tem  "e nao apaga nada"                          "$S" "REMOVENDO"
tem      "resolvida sobreviveu"                      "$(git -C "$SBP/local" branch --list resolvida)" "resolvida"

# base atrasada: outro dev empurra na main
git -C "$SBP/local" checkout -q main
git clone -q "$SBP/remoto" "$SBP/outro" 2>/dev/null
( cd "$SBP/outro" && git config user.email o@o && git config user.name o \
  && git checkout -q -B main origin/main && echo z > z.txt && git add . \
  && git commit -qm outro && git push -q origin main )
S="$(roda --remover)"
tem     "na base mas atrasado, a remocao e cancelada" "$S" "REMOCAO CANCELADA"
tem     "e diz quantos commits atras"                 "$S" "atras de origin/main"
nao_tem "e nao apaga nada"                            "$S" "REMOVENDO"

echo
echo "== 4. remocao de verdade =="
montar
S="$(roda --sem-fetch --remover)"
tem     "apaga a resolvida-local"                     "$S" "ok      resolvida"
nao_tem "nao apaga a viva"                            "$S" "ok      viva"
tem     "imprime o SHA para desfazer"                 "$S" "git branch resolvida"
tem     "viva continua no repo"                       "$(git -C "$SBP/local" branch)" "viva"
nao_tem "resolvida saiu do repo"                      "$(git -C "$SBP/local" branch)" "resolvida"

echo
echo "== 5. o toggle branch-forcar =="
montar
mkdir -p "$SBP/local/.rainforest"
echo '{"branch-forcar":true}' > "$SBP/local/.rainforest/config.json"
S="$(roda --sem-fetch)"
tem "config liga o -D"                                "$S" "git branch -D (FORCA)"
tem "e o divergente entra nos alvos"                  "$(alvos)" "squashed"

# O ponto que justifica a chave existir separada: config ilegivel NAO pode ligar o
# -D. Toda outra chave do repo falha para o lado de LIGAR, porque ligado e a trava.
# Aqui ligado e a faca.
echo 'isto nao e json {{{' > "$SBP/local/.rainforest/config.json"
S="$(roda --sem-fetch)"
tem     "config quebrada volta para o -d"             "$S" "git branch -d (recusa nao mergeada)"
nao_tem "e nao liga a forca"                          "$S" "FORCA"
nao_tem "divergente sai dos alvos de novo"            "$(alvos)" "squashed"

echo
echo "== 6. MUTACAO: sabotar a lista de removiveis =="
# Se `viva` sobrevive por acidente e nao pela trava, este bloco passa verde e a
# bateria inteira nao vale nada. Ele mete `viva` em REMOVIVEIS e exige que ela morra.
montar
cp "$SRC/scripts/limpar-branches.cjs" "$SBP/original.cjs"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8'), a=\"'sumiu-divergente']\";
  if(!s.includes(a)) { console.error('MUTACAO NAO APLICADA: alvo ausente'); process.exit(1); }
  fs.writeFileSync(p, s.replace(a, \"'sumiu-divergente','viva']\"));
" "$SRC/scripts/limpar-branches.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"; else
  S="$(roda --sem-fetch --forcar --remover)"
  tem "com a trava sabotada, viva MORRE (prova que era a trava)" "$S" "ok      viva"
fi
cp "$SBP/original.cjs" "$SRC/scripts/limpar-branches.cjs"
S="$(roda --sem-fetch --json --forcar)"
nao_tem "e o script foi restaurado (viva protegida de novo)" "$(montar; alvos --forcar)" "viva"

echo
echo "== 7. mergeada-por-squash: PR mergeado por squash, upstream vivo (Issue #14) =="
# Cenario novo: o conteudo de 'squash-vivo' entra na base por um squash merge (um
# commit novo na base, sem os commits originais como ancestrais) e o upstream dela
# CONTINUA existindo — a intersecao que nem `--merged` (recusa squash) nem `gone`
# (upstream de pe) enxergam. Sozinho, nenhum sinal de git resolve isso: cai em
# 'viva'. So um `gh pr list --head squash-vivo --state merged` decide.
montar_squash_vivo() {
  montar
  (
    cd "$SBP/local"
    git checkout -qb squash-vivo
    echo sq > sq.txt; git add .; git commit -qm sq
    git push -q -u origin squash-vivo
    git checkout -q main
    git merge -q --squash squash-vivo
    git commit -qm "squash merge de squash-vivo"
    git push -q origin main
    git checkout -q main
  )
}
montar_squash_vivo

# `gh` de mentira, so para esta bateria: devolve a lista de PR mergeado do GitHub
# fingido, e nela so 'squash-vivo' aparece. Nunca mexe no PATH da maquina —
# SEM_GH_PATH e o PATH real MENOS o diretorio do `gh` de verdade, usado so dentro das
# funcoes deste bloco (o `gh` real, sem repo do GitHub por tras, so atrapalharia:
# sempre falha, e ai nada vira `mergeada-por-squash` para testar).
#
# O stub responde SEM olhar os argumentos, e isso e proposital: desde 2026-08-17 o
# limpar-branches.cjs pede a lista de PR mergeado UMA vez, com argumentos constantes,
# e cruza os nomes em JS. Nome de branch nao entra mais na linha de comando — ver a
# secao 12 e o comentario de `prsMergeados()`. Ele e `.cmd` porque no Windows o spawn
# sem shell nao acha `.cmd`, e e justamente esse o caso que o fallback cobre.
SEM_GH_PATH="${PATH//:\/c\/Program Files\/GitHub CLI/}"
mkdir -p "$SBP/bin"
cat > "$SBP/bin/gh.cmd" <<'STUB'
@echo off
rem GH_LOG vazio tem de ser tratado como ausente: `if defined` da verdadeiro para
rem variavel herdada vazia, e ai o append vai para um caminho "" — o .cmd sai != 0, o
rem script le isso como "gh nao respondeu", e a bateria inteira da secao 7 cai.
if not "%GH_LOG%"=="" echo %* >> "%GH_LOG%"
echo [{"headRefName":"squash-vivo"}]
exit /b 0
STUB

# `${GH_LOG:-}` e obrigatorio: a bateria roda com `set -u`, e as secoes 7 a 11 chamam
# `roda_gh` antes de a secao 12 definir o log de argumentos. Sem o default, o subshell
# morre com "unbound variable", a saida vem vazia, e as falhas aparecem como se a
# classificacao tivesse quebrado — foi o que aconteceu na primeira tentativa.
roda_gh()    { ( cd "$SBP/local" && PATH="$SBP/bin:$SEM_GH_PATH" GH_LOG="${GH_LOG:-}" CLAUDE_PROJECT_DIR="$SBP/local" node "$SRC/scripts/limpar-branches.cjs" "$@" 2>&1 ); }
roda_sem_gh(){ ( cd "$SBP/local" && PATH="$SEM_GH_PATH"          CLAUDE_PROJECT_DIR="$SBP/local" node "$SRC/scripts/limpar-branches.cjs" "$@" 2>&1 ); }
alvos_gh()   { roda_gh --sem-fetch --json "$@" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.stringify(JSON.parse(d).alvos)))"; }
classe_gh()  { roda_gh --sem-fetch --json | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const b=JSON.parse(d).refs.find(x=>x.nome===process.argv[1]);console.log(b?b.classe:'(ausente)')})" "$1"; }

tem "squash-vivo vira mergeada-por-squash (nao viva)" "$(classe_gh squash-vivo)" "mergeada-por-squash"
S7="$(roda_gh --sem-fetch)"
tem "o nome da classe aparece na saida" "$S7" "mergeada-por-squash"

echo
echo "== 8. mergeada-por-squash exige -D, como sumiu-divergente =="
nao_tem "sem --forcar, squash-vivo fica de fora dos alvos" "$(alvos_gh)" "squash-vivo"
tem     "a mensagem diz que so o -D alcanca"                "$S7" "o -d as recusa"
roda_gh --sem-fetch --remover > /dev/null
tem     "squash-vivo sobrevive sem --forcar"                 "$(git -C "$SBP/local" branch --list squash-vivo)" "squash-vivo"
S9="$(roda_gh --sem-fetch --remover --forcar)"
tem     "com --forcar, squash-vivo sai e imprime o SHA"      "$S9" "ok      squash-vivo"
nao_tem "squash-vivo saiu do repo"                            "$(git -C "$SBP/local" branch)" "squash-vivo"

echo
echo "== 9. gh indisponivel: a candidata volta a ser viva, exit continua 0 =="
# Simula gh ausente SO dentro deste bloco, com um PATH restrito montado nas proprias
# funcoes roda_sem_gh/classe_sem_gh acima — nunca mexe no PATH da maquina.
montar_squash_vivo
classe_sem_gh() { roda_sem_gh --sem-fetch --json | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const b=JSON.parse(d).refs.find(x=>x.nome===process.argv[1]);console.log(b?b.classe:'(ausente)')})" "$1"; }
tem "sem gh, squash-vivo volta a classificar como viva" "$(classe_sem_gh squash-vivo)" "viva"
S10="$(roda_sem_gh --sem-fetch)"
tem "e avisa que a checagem de PR nao rodou"          "$S10" "gh pr list"
roda_sem_gh --sem-fetch > /dev/null
EX=$?
tem "e o exit code continua 0" "$EX" "0"

echo
echo "== 10. --base <ref>: mede contra outra ref, nao so a base default =="
montar
(
  cd "$SBP/local"
  git checkout -qb outra-base
  git push -q -u origin outra-base
  git checkout -qb so-na-outra
  echo o > o.txt; git add .; git commit -qm o
  git push -q -u origin so-na-outra
  git checkout -q outra-base
  git merge -q --no-ff -m m2 so-na-outra
  git push -q origin outra-base
  git checkout -q main
)
classe_base() { roda --sem-fetch --json --base "$1" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const b=JSON.parse(d).refs.find(x=>x.nome===process.argv[1]);console.log(b?b.classe:'(ausente)')})" "$2"; }
tem     "com a base default, so-na-outra e viva"                        "$(classe so-na-outra)" "viva"
nao_tem "com --base outra-base, deixa de ser viva"                       "$(classe_base outra-base so-na-outra)" "viva"
tem     "e passa a ser resolvida-remota (mergeada la, upstream de pe)"   "$(classe_base outra-base so-na-outra)" "resolvida-remota"

echo
echo "== 11. MUTACAO: sabotar a exigencia de -D de mergeada-por-squash =="
# Mesma logica da secao 6, agora na trava nova: se a exigencia de -D para
# mergeada-por-squash sumir do codigo, o caso 8 ("sem --forcar, fica de fora dos
# alvos") tem que FALHAR — senao a trava nao esta la, so parece que esta.
montar_squash_vivo
cp "$SRC/scripts/limpar-branches.cjs" "$SBP/original2.cjs"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8');
  const alvo = \"b.classe !== 'sumiu-divergente' && b.classe !== 'mergeada-por-squash'\";
  if(!s.includes(alvo)) { console.error('MUTACAO NAO APLICADA: alvo ausente'); process.exit(1); }
  fs.writeFileSync(p, s.replace(alvo, \"b.classe !== 'sumiu-divergente'\"));
" "$SRC/scripts/limpar-branches.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"; else
  AM="$(alvos_gh)"
  tem "com a exigencia sabotada, squash-vivo entra nos alvos sem --forcar (prova que a exigencia de -D era a trava)" "$AM" "squash-vivo"
fi
cp "$SBP/original2.cjs" "$SRC/scripts/limpar-branches.cjs"
montar_squash_vivo
nao_tem "e o script foi restaurado (squash-vivo exige --forcar de novo)" "$(alvos_gh)" "squash-vivo"

echo
echo "== 12. nome de branch NAO entra na linha de comando do gh =="
# Nome de branch e dado de quem empurrou: o git proibe espaco, controle e `~^:?*[\`,
# mas ACEITA `&`, `"`, `|`, `(`, `)` e `;`. A primeira versao desta checagem passava
# `--head <nome>` com `shell: true`, e em 2026-08-17 dois payloads executaram comando
# de verdade nesta maquina — a branch `x&echo A>marca&y` fez o `echo` rodar.
#
# A trava nao e uma lista de caracteres proibidos, e sim a invariante: o `gh` e
# chamado com argumentos CONSTANTES, e o cruzamento por nome acontece em JS. Este
# bloco le o log de argumentos do stub e exige que nenhum nome de branch esteja la —
# assim a trava vale para payload que ninguem imaginou. (Payload com `>` no nome nao
# da para testar no Windows: o ref e um arquivo, e o `>` e proibido pelo sistema de
# arquivos, nao pelo git.)
montar_squash_vivo
(
  cd "$SBP/local"
  git checkout -q -b 'zz&yy' main
  echo inj > inj.txt; git add .; git commit -qm inj
  git push -q -u origin 'zz&yy'
  git checkout -q main
)
GH_LOG="$SBP/gh-args.log"
rm -f "$GH_LOG"
S12="$(roda_gh --sem-fetch)"
LOG12="$(cat "$GH_LOG" 2>/dev/null)"
tem     "o gh e chamado com os argumentos constantes"     "$LOG12" "pr list --state merged"
nao_tem "e nenhum nome de branch entra na linha"          "$LOG12" "zz&yy"
nao_tem "nem o nome da candidata a squash"                "$LOG12" "squash-vivo"
nao_tem "nem sobra um --head de qualquer especie"          "$LOG12" " --head"
tem     "e a branch com & no nome roda e aparece na saida" "$S12" "zz&yy"
GH_LOG=""

echo
echo "== 13. a branch PADRAO nunca entra na remocao, seja qual for a --base (Issue #23) =="
# 2026-08-19, estagio `fechar` de um fluxo cujo trabalho ainda nao tinha chegado a
# main: `--base memoria-e-dados-do-rainforest --remover` apagou as 11 branches de
# agente (certo) e a `main` local junto. A classificacao nao tinha defeito de logica —
# a branch de trabalho SAIU da main, entao a main esta contida nela, entao a main
# satisfaz "ja esta na base" e cai em resolvida-remota, que e removivel por desenho.
#
# O passo seguinte do `fechar` morreu com `fatal: ambiguous argument 'main..HEAD'`.
# Ali nao houve perda porque origin/main estava intacta, mas num repo em que a branch
# padrao so exista localmente, ou com commit ainda nao empurrado, e perda de verdade.
#
# A protecao nao pode depender de a pessoa estar na main: no incidente ela estava na
# branch de trabalho, e e por isso que a main nao caiu em 'atual'. Por isso o cenario
# abaixo faz checkout da propria base antes de medir.
montar
(
  cd "$SBP/local"
  git checkout -qb outra-base
  git push -q -u origin outra-base
  git checkout -q outra-base
)
alvos_base()  { roda --sem-fetch --json --base "$1" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.stringify(JSON.parse(d).alvos)))"; }
classe_base2() { roda --sem-fetch --json --base "$1" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const b=JSON.parse(d).refs.find(x=>x.nome===process.argv[1]);console.log(b?b.classe:'(ausente)')})" "$2"; }

nao_tem "com --base noutra ref, a main NAO entra nos alvos"      "$(alvos_base outra-base)" '"main"'
tem     "e e classificada como padrao, nao como resolvida"       "$(classe_base2 outra-base main)" "padrao"
nao_tem "nem com --forcar a main entra"                          "$(roda --sem-fetch --json --forcar --base outra-base | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.stringify(JSON.parse(d).alvos)))")" '"main"'

# E a remocao de verdade, que e o que doeu. A remocao precisa ter ACONTECIDO: se ela
# fosse cancelada, a main sobreviveria por motivo nenhum e este bloco ficaria verde
# sem provar nada — foi essa a forma do falso verde de 2026-08-19.
S13="$(roda --sem-fetch --remover --forcar --base outra-base)"
tem     "a remocao de verdade rodou (nao foi cancelada)"         "$S13" "REMOVENDO"
nao_tem "e a main nao aparece entre as removidas"                "$S13" "ok      main"
tem     "depois de remover de verdade, a main continua no repo"  "$(git -C "$SBP/local" branch --list main)" "main"

echo
echo "== 14. MUTACAO: sabotar a protecao da branch padrao =="
# Se a main sobreviveu por acaso (por estar mergeada de um jeito que nao classifica,
# por exemplo) e nao pela trava, a secao 13 passa verde sem provar nada. Aqui a
# protecao e removida do fonte e a main TEM que voltar a ser removivel.
montar
(
  cd "$SBP/local"
  git checkout -qb outra-base
  git push -q -u origin outra-base
  git checkout -q outra-base
)
cp "$SRC/scripts/limpar-branches.cjs" "$SBP/original3.cjs"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8');
  const alvo = \"else if (padrao && b.nome === padrao) b.classe = 'padrao';\";
  if(!s.includes(alvo)) { console.error('MUTACAO NAO APLICADA: alvo ausente'); process.exit(1); }
  fs.writeFileSync(p, s.replace(alvo, ''));
" "$SRC/scripts/limpar-branches.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"; else
  tem "sem a protecao, a main volta a entrar nos alvos (prova que era a trava)" "$(alvos_base outra-base)" '"main"'
fi
cp "$SBP/original3.cjs" "$SRC/scripts/limpar-branches.cjs"
nao_tem "e o script foi restaurado (main protegida de novo)" "$(alvos_base outra-base)" '"main"'

echo
echo "== 15. squash SEM upstream: o mesmo furo do caso 7, so que sem PR pra achar (Issue #82) =="
# As branches worktree-agent-* de subagente NUNCA tem upstream (regra 11 as poe em
# worktree isolado; 'fechar'/'limpar' removem o worktree e deixam so a branch local
# para tras). Quando o PR que leva o mesmo conteudo e mesclado por squash, a branch
# local orfa nao esta em `--merged` (squash nao gera ancestralidade) e nunca teve
# upstream — nunca entra no filtro `b.classe === 'viva' && b.upstream` (linha 220 de
# limpar-branches.cjs) que aciona a checagem de PR. Fica 'viva' para sempre. Medido
# de verdade com o PR #80 (2026-08-24): 11 branches de agente, conteudo comprovadamente
# na main, classificadas 'trabalho vivo'.
#
# ESTE BLOCO E VERMELHO DE PROPOSITO ATE O CONSERTO ENTRAR — nao ha ainda comparacao
# de conteudo no fonte. `mergeada-por-conteudo` e uma PROPOSTA de nome de classe, nao
# um contrato ja implementado; quem fechar a Issue #82 ajusta esta bateria junto do
# fonte, e so ENTAO este bloco fica verde.
#
# A tecnica escolhida na depuracao da Issue #82, com evidencia (nao a unica prototipada
# — patch-id perdeu, ver o motivo abaixo): `git cherry-pick --no-commit
# <merge-base>..<branch>` seguido de `git diff --quiet HEAD`, rodado num
# `git worktree add --detach` isolado (nunca no checkout do usuario) e sempre
# desfeito com `git worktree remove --force` depois. Precisa de `--forcar` para
# remover, mesma familia de `sumiu-divergente` e `mergeada-por-squash` (o `-d`
# recusaria: a base local nao contem esses commits por ancestralidade).
#
# Por que patch-id perdeu: ele so prova identidade contra UM commit especifico da
# base, e squash real costuma nao caber nisso — testado num segundo sandbox onde o
# mesmo diff da branch chega na base partido em dois commits (squash + fixup
# posterior). Nenhum dos dois patch-id isolados bateu com o patch-id da branch, e a
# tecnica teria mantido a branch 'viva' por engano (falso negativo, nao falso
# positivo — mas ainda assim a lista fica incompleta). O cherry-pick cumulativo
# contra a ponta atual da base nao tem esse problema: ele testa exatamente a
# pergunta que importa, "sobra alguma coisa desta branch que a base de hoje ainda
# nao tem", nao "existe um commit identico".
montar_squash_sem_upstream() {
  montar
  (
    cd "$SBP/local"
    # a branch de subagente: LOCAL ONLY, nunca teve upstream
    git checkout -qb worktree-agent-conteudo main
    echo conteudo > conteudo.txt; git add .; git commit -qm "obra do subagente"
    git checkout -q main
    git merge -q --squash worktree-agent-conteudo
    git commit -qm "obra do subagente, squash (#998)"
    git push -q origin main

    # o contraste, na MESMA execucao: commit que nao esta na main por caminho nenhum
    git checkout -qb worktree-agent-sem-merge main
    echo "nunca mesclado" > sem-merge.txt; git add .; git commit -qm "trabalho solto"
    git checkout -q main
  )
}
montar_squash_sem_upstream

tem "conteudo squashado sem upstream vira removivel"       "$(classe worktree-agent-conteudo)"  "mergeada-por-conteudo"
tem "e o commit solto, na MESMA execucao, continua viva"    "$(classe worktree-agent-sem-merge)" "viva"

echo
echo "== 16. MUTACAO da secao 15: sabotar a comparacao de conteudo (Issue #82) =="
# Se a branch squash-sem-upstream sobrevive por acaso e nao pela trava de
# deteccao de conteudo, este bloco passa verde e a bateria inteira nao vale nada.
# Ele sabota a funcao mergeadosPorConteudo e exige que o caso 1 da secao 15 FALHE.
montar_squash_sem_upstream
cp "$SRC/scripts/limpar-branches.cjs" "$SBP/original4.cjs"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8');
  const alvo = \"resultado[b.nome] = diff.status === 0;\";
  if(!s.includes(alvo)) { console.error('MUTACAO NAO APLICADA: alvo ausente'); process.exit(1); }
  fs.writeFileSync(p, s.replace(alvo, \"resultado[b.nome] = false;\"));
" "$SRC/scripts/limpar-branches.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"; else
  tem "com a deteccao sabotada, worktree-agent-conteudo volta a ser viva (prova que a deteccao era a trava)" "$(classe worktree-agent-conteudo)" "viva"
fi
cp "$SBP/original4.cjs" "$SRC/scripts/limpar-branches.cjs"
montar_squash_sem_upstream
nao_tem "e o script foi restaurado (worktree-agent-conteudo volta a ser mergeada-por-conteudo)" "$(classe worktree-agent-conteudo)" "viva"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
