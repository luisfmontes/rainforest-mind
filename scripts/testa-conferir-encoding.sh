#!/bin/bash
# Bateria do `scripts/conferir-encoding.cjs` — a trava que confere ENCODING de
# arquivo versionado (mojibake, BOM, CRLF) antes de virar um README ilegivel no
# GitHub por dois dias sem ninguem notar.
#
# O QUE PRECISA PROVAR:
#   1. o mojibake REAL do incidente (daee1d6:README.md, 387 linhas corrompidas)
#      reprova, e o README de hoje (limpo, ja consertado em a1433d1) passa;
#   2. BOM reprova, ausencia de BOM passa;
#   3. CRLF reprova (fixture com git proprio), arvore em LF passa;
#   4. a arvore INTEIRA do repositorio, na base, passa limpa — e o falso positivo
#      medido (vigias/run-vigia.ps1, documentando o proprio sintoma em comentario)
#      fica coberto pelo marcador `rf-encoding-exemplo`, testado aqui tambem;
#   5. MUTACAO: desligar a deteccao de mojibake tem que derrubar esta bateria.
#
# Uso: bash scripts/testa-conferir-encoding.sh

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/conferir-encoding.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }

ok=0; falhou=0
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

saiu() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (exit $2, esperava $3)"; fi; }
tem()  { if printf '%s' "$2" | grep -qF "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3')"; fi; }

roda()   { node "$SCRIPT" "$@" 2>&1; }
codigo() { node "$SCRIPT" "$@" >/dev/null 2>&1; echo $?; }

echo "== 1. mojibake real do incidente (daee1d6) reprova, README de hoje passa =="
CORROMPIDO="$SB/readme-corrompido.md"
LIMPO="$SB/readme-limpo.md"
if git -C "$RAIZ" cat-file -e daee1d6:README.md 2>/dev/null; then
  git -C "$RAIZ" show daee1d6:README.md > "$CORROMPIDO" 2>/dev/null
  S="$(roda "$CORROMPIDO")"
  saiu "README corrompido (daee1d6) reprova"    "$(codigo "$CORROMPIDO")" "2"
  tem  "e aponta mojibake"                      "$S" "mojibake"
  tem  "e aponta BOM"                           "$S" "bom"
else
  falhou=$((falhou+1)); echo "  FALHA nao consegui ler daee1d6:README.md do historico"
fi
git -C "$RAIZ" show HEAD:README.md > "$LIMPO" 2>/dev/null
saiu "README de HEAD (ja consertado) passa (exit 0)" "$(codigo "$LIMPO")" "0"

echo
echo "== 2. BOM =="
printf '\xEF\xBB\xBFtexto sem acento\n' > "$SB/com-bom.md"
printf 'texto sem acento\n' > "$SB/sem-bom.md"
S="$(roda "$SB/com-bom.md")"
saiu "arquivo com BOM reprova"    "$(codigo "$SB/com-bom.md")" "2"
tem  "e aponta [bom]"             "$S" "[bom]"
saiu "arquivo sem BOM passa"      "$(codigo "$SB/sem-bom.md")" "0"

echo
echo "== 3. CRLF (fixture com git proprio) =="
REPO_CRLF="$SB/repo-crlf"
mkdir -p "$REPO_CRLF"
(
  cd "$REPO_CRLF" || exit 1
  git init -q
  git config user.email "t@t.invalid"
  git config user.name "bateria"
  git config core.autocrlf false
  printf 'linha em LF normal\n' > lf.md
  printf 'linha em CRLF\r\nsegunda linha\r\n' > crlf.md
  git add -A
  git commit -q -m "fixture crlf"
)
S="$(cd "$REPO_CRLF" && node "$SCRIPT" 2>&1)"
C="$(cd "$REPO_CRLF" && node "$SCRIPT" >/dev/null 2>&1; echo $?)"
saiu "arvore com um arquivo CRLF reprova"  "$C" "2"
tem  "e aponta crlf.md"                    "$S" "crlf.md  [crlf]"

REPO_LF="$SB/repo-lf"
mkdir -p "$REPO_LF"
(
  cd "$REPO_LF" || exit 1
  git init -q
  git config user.email "t@t.invalid"
  git config user.name "bateria"
  git config core.autocrlf false
  printf 'linha em LF normal\n' > lf.md
  git add -A
  git commit -q -m "fixture lf"
)
C2="$(cd "$REPO_LF" && node "$SCRIPT" >/dev/null 2>&1; echo $?)"
saiu "arvore so em LF passa" "$C2" "0"

echo
echo "== 4. arvore inteira do repositorio na base — sem falso positivo =="
S="$(cd "$RAIZ" && node "$SCRIPT" 2>&1)"
C3="$(cd "$RAIZ" && node "$SCRIPT" >/dev/null 2>&1; echo $?)"
saiu "repositorio inteiro passa limpo (exit 0)" "$C3" "0"

# O falso positivo medido: sem o marcador rf-encoding-exemplo, a linha que
# documenta o sintoma em vigias/run-vigia.ps1 reprovaria. Prova que a supressao
# e' o que segura o verde, nao a ausencia do padrao.
SEM_MARCADOR="$SB/sem-marcador.ps1"
sed 's/ rf-encoding-exemplo:.*$//' "$RAIZ/vigias/run-vigia.ps1" | grep -F 'mojibake (' > "$SEM_MARCADOR" || true
if [ -s "$SEM_MARCADOR" ]; then
  saiu "sem o marcador, a mesma linha reprovaria (prova o falso positivo)" "$(codigo "$SEM_MARCADOR")" "2"
else
  falhou=$((falhou+1)); echo "  FALHA nao consegui isolar a linha do falso positivo para o teste de controle"
fi

echo
echo "== 4b. regressao do PR #69: o proprio conferidor reprovava a si mesmo =="
# CI vermelha no PR #69: `conferir-encoding.cjs` (comentario de cabecalho citando
# a assinatura em prosa) e `testa-conferir-encoding.sh` (fixture com bytes de
# mojibake literais no fonte) reprovavam CONTRA SI MESMOS quando a arvore
# mesclada com a main (#67/#68/#70/#71) entrava na varredura. Caso 4 acima ja
# prova a arvore inteira limpa; este caso nomeia os dois arquivos, para a
# regressao especifica nao voltar a se esconder atras de um "exit 0" agregado.
saiu "conferir-encoding.cjs, sozinho, nao reprova mais a si mesmo" \
     "$(codigo "$SCRIPT")" "0"
saiu "testa-conferir-encoding.sh, sozinho, nao reprova mais (fixture por escape)" \
     "$(codigo "$RAIZ/scripts/testa-conferir-encoding.sh")" "0"

echo
echo "== 4c. a supressao (rf-encoding-exemplo) nao virou cegueira geral =="
# O risco nomeado da escolha de desenho: um marcador que suprime a linha inteira
# podia esconder um mojibake REAL que caisse na mesma linha por acidente. Este
# caso planta mojibake de verdade numa linha SEM o marcador e exige que continue
# reprovando — se este caso ficar verde por engano (exit 0), a supressao parou
# de ser pontual e virou um jeito de desligar a checagem.
REPO_CEGUEIRA="$SB/repo-cegueira"
mkdir -p "$REPO_CEGUEIRA"
(
  cd "$REPO_CEGUEIRA" || exit 1
  git init -q
  git config user.email "t@t.invalid"
  git config user.name "bateria"
  git config core.autocrlf false
  printf 'texto normal, sem marcador nenhum aqui.\n' > sem-marcador.md
  printf '\xc3\x83\xc2\xa9 mojibake real, sem marcador de supressao.\n' >> sem-marcador.md
  git add -A
  git commit -q -m "fixture sem marcador"
)
C5="$(cd "$REPO_CEGUEIRA" && node "$SCRIPT" >/dev/null 2>&1; echo $?)"
saiu "mojibake real sem marcador continua reprovando (supressao e pontual)" "$C5" "2"

echo
echo "== 5. MUTACAO: desligar a deteccao de mojibake tem que derrubar a bateria =="
# Fixture SO com mojibake, sem BOM — isolado do caso 1, que reprova por DOIS
# motivos (mojibake e BOM) e por isso nao serviria para provar que o mojibake
# especificamente foi o que a mutacao desligou.
SO_MOJIBAKE="$SB/so-mojibake.md"
# Gerada por escape hexadecimal, nao por bytes literais no fonte (PR #69,
# CI vermelha): o proprio conferir-encoding.cjs reprovava ESTE arquivo,
# porque o texto corrompido literal aqui era exatamente o padrao que ele
# cata. Confirmado byte a byte identico ao literal anterior antes de trocar.
printf 'O problema n\xc3\x83\xc2\xa3o \xc3\x83\xc2\xa9 falta de ideia. \xc3\x83\xe2\x80\xb0 o que recebe luz agora.\n' > "$SO_MOJIBAKE"
saiu "fixture so-mojibake reprova antes da mutacao (controle)" "$(codigo "$SO_MOJIBAKE")" "2"
cp "$SCRIPT" "$SB/original.cjs"
node -e "
  const fs = require('fs');
  const p = process.argv[1];
  const s = fs.readFileSync(p, 'utf8');
  const alvo = 'function achaMojibake(texto) {';
  if (!s.includes(alvo)) { console.error('MUTACAO NAO APLICADA'); process.exit(1); }
  const mutado = s.replace(alvo, 'function achaMojibake(texto) { return [];');
  fs.writeFileSync(p, mutado);
" "$SCRIPT"
if [ $? -ne 0 ]; then
  falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"
else
  C4="$(codigo "$SO_MOJIBAKE")"
  if [ "$C4" = "0" ]; then
    ok=$((ok+1)); echo "  ok   com a deteccao sabotada, o fixture so-mojibake passa (exit 0) — prova que a checagem era a trava"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao aplicada mas o fixture ainda reprova (exit $C4) — a guarda nao mede o que devia"
  fi
fi
cp "$SB/original.cjs" "$SCRIPT"
saiu "restaurado, volta a reprovar o fixture so-mojibake" "$(codigo "$SO_MOJIBAKE")" "2"

echo "== 6. mojibake de codepage OEM (CP850/CP437) =="
# A SEGUNDA familia de round-trip, cega ate 2026-09-01. O `vigias/ERROS.md`
# commitado carregava esta assinatura desde 27/08 e este script saia exit 0 em
# cima dela: a deteccao so conhecia CP1252, e a tarefa agendada do Windows roda
# no codepage OEM do console.
#
# A fixture e montada por BYTES, nunca colando o caractere: e o mesmo cuidado do
# caso 5 (PR #69), e aqui ele importa em dobro porque o proprio gate cataria
# este arquivo se a assinatura estivesse literal no fonte.
#   6e = 'n'   e2 94 9c = U+251C (0xC3 lido como OEM)   c3 ba = U+00FA (0xA3)
# Ou seja: a palavra "nao" com til, depois do round-trip.
OEM="$SB/oem-mojibake.md"
printf -- '- erro: n\xe2\x94\x9c\xc3\xbao achei o FOCO.md\n' > "$OEM"
S="$(roda "$OEM")"
saiu "assinatura OEM de 2 bytes reprova"        "$(codigo "$OEM")" "2"
tem  "e aponta mojibake"                        "$S" "mojibake"

# O abridor do bloco 0xC2 (U+252C) e o par de 3 bytes (0xE2 0x80 lidos como OEM)
# tambem entram na rede. Duas entradas para o par porque o primeiro caractere
# diverge entre CP850 (U+00D4) e CP437 (U+0393).
OEM2="$SB/oem-mojibake-2.md"
printf -- 'texto \xe2\x94\xac\xc2\xa9 e travessao \xc3\x94\xc3\x87\xc3\xb6 aqui\n' > "$OEM2"
saiu "abridor do bloco 0xC2 e o par de 3 bytes tambem reprovam" "$(codigo "$OEM2")" "2"

echo
echo "== 6b. FALSO POSITIVO: arte de caixa legitima NAO pode reprovar =="
# A condicao nao e "contem U+251C" — esse caractere e legitimo em saida de
# `tree`, em diagrama e em arte ASCII. E "U+251C IMEDIATAMENTE seguido de um
# membro da tabela de round-trip". Saida de `tree` poe U+2500 depois, e U+2500
# nao esta em tabela nenhuma das duas. Sem este caso, apertar a heuristica
# depois nao teria como ser conferido.
ARTE="$SB/arte-de-caixa.md"
printf -- 'vigias/\n\xe2\x94\x9c\xe2\x94\x80\xe2\x94\x80 erros.ps1\n\xe2\x94\x9c\xe2\x94\x80\xe2\x94\x80 run-vigia.ps1\n\xe2\x94\x94\xe2\x94\x80\xe2\x94\x80 ERROS.md\n' > "$ARTE"
saiu "arte de caixa estilo tree passa (exit 0)" "$(codigo "$ARTE")" "0"
# Acentuacao portuguesa normal tambem nao pode acender nada.
PT="$SB/portugues.md"
printf -- 'A ronda nao achou o arquivo: acentuacao, coracao, versao, gestao.\nCom acento de verdade: n\xc3\xa3o, \xc3\xa9, \xc3\xba, \xc3\xa7\xc3\xa3o.\n' > "$PT"
saiu "portugues acentuado em UTF-8 valido passa (exit 0)" "$(codigo "$PT")" "0"

echo
echo "== 6c. MUTACAO: tirar a assinatura OEM tem que deixar a fixture passar =="
saiu "fixture OEM reprova antes da mutacao (controle)" "$(codigo "$OEM")" "2"
cp "$SCRIPT" "$SB/original-oem.cjs"
node -e "
  const fs = require('fs');
  const p = process.argv[1];
  const s = fs.readFileSync(p, 'utf8');
  const alvo = 'const FECHADORES_OEM = new Set([...OEM_CP850_80_BF, ...OEM_CP437_80_BF]);';
  if (!s.includes(alvo)) { console.error('MUTACAO NAO APLICADA'); process.exit(1); }
  fs.writeFileSync(p, s.replace(alvo, 'const FECHADORES_OEM = new Set([]);'));
" "$SCRIPT"
if [ $? -ne 0 ]; then
  falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao OEM"
else
  C6="$(codigo "$OEM")"
  if [ "$C6" = "0" ]; then
    ok=$((ok+1)); echo "  ok   com a tabela OEM esvaziada, a fixture passa (exit 0) — prova que ela era a trava"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao aplicada mas a fixture ainda reprova (exit $C6) — a guarda nao mede o que devia"
  fi
fi
cp "$SB/original-oem.cjs" "$SCRIPT"
saiu "restaurado, volta a reprovar a fixture OEM" "$(codigo "$OEM")" "2"
# E a prova de que a mutacao OEM nao derruba a familia CP1252 junto: as duas
# redes sao independentes, e uma nao pode estar segurando a outra. Reusa a
# fixture do caso 5 em vez de gerar outra: a primeira versao desta secao criava
# a sua propria, e os bytes literais dela faziam ESTE arquivo reprovar no gate.
saiu "a familia CP1252 continua reprovando (as duas redes sao independentes)" "$(codigo "$SO_MOJIBAKE")" "2"

echo

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
