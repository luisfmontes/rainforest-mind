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
# E o motivo de o script existir, que vale como teste tambem: o comando que o Luis
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
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
