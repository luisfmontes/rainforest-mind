#!/bin/bash
# Bateria do scripts/saude.cjs — por ora, so a checagem do PLUGIN INSTALADO.
#
# Ela existe porque essa checagem ja enganou duas vezes, e nas duas o defeito foi o
# mesmo em forma diferente: o medidor respondeu com confianca uma pergunta que nao
# conseguia fazer.
#
#   1a vez (2026-08-11, manha): comparava so o COMMIT do clone. Clone no commit certo
#      com conteudo faltando passava como ok — e foi assim que tres skills novas nao
#      valiam em sessao nenhuma sem ninguem notar. Consertado olhando o CONTEUDO
#      (nome de skill presente la e aqui), que e o que o usuario ve na paleta;
#   2a vez (mesmo dia, noite): depois de o historico ser reescrito para publicar, o
#      commit do clone deixou de existir aqui. `rev-list --count` falhou e a saida
#      virou "? commit(s) atras" — muda justamente no caso em que a resposta era mais
#      util, e apontando para um `marketplace update` que NAO reconcilia historias
#      sem parentesco.
#
# As quatro situacoes que a checagem tem que separar:
#   A. clone atras         -> aviso, com a contagem
#   B. sem parentesco      -> ALERTA, e o conserto NAO e o update
#   C. commit so no clone  -> aviso, e nao "atraso": ha trabalho que o update atropela
#   D. clone em dia        -> ok
#
# O discriminador e o COMMIT RAIZ, e a primeira tentativa errou: perguntava se o
# commit do clone existia aqui, e concluia "sem parentesco" quando nao existia. Mas
# clone que fez commit proprio TAMBEM tem objeto que este repo nao conhece — e ali o
# parentesco existe. Ausencia de objeto nao e ausencia de parentesco. A raiz responde
# sem os dois lados precisarem compartilhar objeto nenhum.
#
# A ultima secao e MUTACAO: iguala as raizes e exige que B pare de ser detectado.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

ok=0; falhou=0
checa() { # nome, esperado(nivel), esperado(trecho), obtido
  if echo "$4" | grep -q "^$2" && echo "$4" | grep -qF "$3"; then
    ok=$((ok+1)); echo "  ok   $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1"; echo "       esperava $2 com '$3'"; echo "       veio: $4"
  fi
}

M="$SBP/cfg/plugins/marketplaces/$(basename "$SRC")"
mkdir -p "$SBP/cfg/plugins/marketplaces" "$SBP/dados"

ver() {
  ( cd "$SRC" && CLAUDE_CONFIG_DIR="$SBP/cfg" RFM_ROOT="$SBP/dados" \
    node "$SRC/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
      let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{
        const a=JSON.parse(d).find(x=>x.item==='plugin instalado');
        console.log(a ? a.nivel+' '+a.detalhe : 'ausente');
      })"
}
git_clone() { rm -rf "$M"; git clone -q "$SRC" "$M" 2>/dev/null; }
commit_no_clone() { git -C "$M" -c user.email=t@t -c user.name=t "$@" >/dev/null 2>&1; }

echo "== as quatro situacoes =="

git_clone && git -C "$M" reset -q --hard HEAD~3
checa "A. clone atras vira aviso com a contagem"   "aviso" "3 commit(s) atras"   "$(ver)"

# Historia paralela COM todas as skills no lugar: o parentesco tem que ser checado
# antes do conteudo, senao um clone completo porem orfao passa como saudavel.
rm -rf "$M"; mkdir -p "$M"; git init -q "$M"; cp -r "$SRC/skills" "$M/"
commit_no_clone add -A; commit_no_clone commit -qm "historia paralela"
S="$(ver)"
checa "B. sem parentesco vira ALERTA"              "alerta" "sem parentesco"     "$S"
checa "B. e diz que o update NAO resolve"          "alerta" "sem parentesco"     "$S"

git_clone && echo x > "$M/extra.txt" && commit_no_clone add extra.txt && commit_no_clone commit -qm "editado no clone"
checa "C. commit so no clone nao vira 'atraso'"    "aviso" "commit proprio"      "$(ver)"

git_clone
checa "D. clone em dia vira ok"                    "ok"    "skills do repo"      "$(ver)"

echo
echo "== a saida nunca imprime interrogacao =="
# O sintoma exato de 2026-08-11: `? commit(s) atras`. Se ele voltar, e porque alguem
# reintroduziu a contagem sem checar se ela e possivel.
rm -rf "$M"; mkdir -p "$M"; git init -q "$M"; cp -r "$SRC/skills" "$M/"
commit_no_clone add -A; commit_no_clone commit -qm p
if ver | grep -q "? commit"; then
  falhou=$((falhou+1)); echo "  FALHA a saida voltou a imprimir '? commit(s)'"
else
  ok=$((ok+1)); echo "  ok   nenhuma interrogacao na saida"
fi

echo
echo "== MUTACAO: cegar o discriminador de raiz =="
# Se as raizes forem sempre iguais, B deixa de ser detectado e volta a cair na
# contagem impossivel — que era exatamente o estado anterior ao conserto.
cp "$SRC/scripts/saude.cjs" "$SBP/original.cjs"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8'), a='raizAqui !== raizLa';
  if(!s.includes(a)) { console.error('MUTACAO NAO APLICADA'); process.exit(1); }
  fs.writeFileSync(p, s.replace(a, 'false'));
" "$SRC/scripts/saude.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"; else
  S="$(ver)"
  if echo "$S" | grep -q "sem parentesco"; then
    falhou=$((falhou+1)); echo "  FALHA com a mutacao, B continuou detectado — o teste nao prova nada"
  else
    ok=$((ok+1)); echo "  ok   cegado o discriminador, B deixa de ser detectado (era ele mesmo)"
  fi
fi
cp "$SBP/original.cjs" "$SRC/scripts/saude.cjs"
checa "e restaurado, B volta a ser ALERTA"         "alerta" "sem parentesco"     "$(ver)"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
