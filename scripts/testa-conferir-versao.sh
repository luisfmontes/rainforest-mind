#!/bin/bash
# Bateria do scripts/conferir-versao.cjs. Monta repositorios git de verdade, com
# historico de bump de verdade, e confere a CONTAGEM e o exit code.
#
# O que esta bateria precisa provar:
#   1. que a contagem de commits desde o bump esta CERTA — nao so que saiu um
#      numero. A primeira versao do script usava a pickaxe `-S` e devolveu 271
#      em vez de 18: numero plausivel, commit errado. Caso `-S` vs `-G` abaixo.
#   2. que o teto decide o exit code nas duas direcoes;
#   3. que o que nao da para medir NAO trava (falha aberta).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECADOR="$SRC/scripts/conferir-versao.cjs"
# Caminho NATIVO, nao o /tmp/... do Git Bash: o Node no Windows nao resolve
# caminho MSYS, o git falha e o checador cai no ramo "nao da para medir" — a
# bateria passaria verde testando o fallback, nunca o mecanismo.
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

ok=0; falhou=0

# Monta um repo com o layout do plugin e um historico de bumps de verdade.
# $1 = pasta, $2 = quantos commits DEPOIS do ultimo bump
montar() {
  local R="$1" depois="$2" i
  mkdir -p "$R/.claude-plugin" "$R/scripts"
  git init -q "$R"
  git -C "$R" config user.email t@t; git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
  cp "$CHECADOR" "$R/scripts/conferir-versao.cjs"
  git -C "$R" add scripts; git -C "$R" commit -qm "andaime"

  # Tres bumps, para o script ter que achar o ULTIMO e nao o primeiro. O commit
  # de trabalho vem ANTES do bump — que e a ordem real (trabalha-se, depois
  # solta a versao) e que deixa o ultimo bump como o ultimo commit do andaime.
  # Na primeira versao deste arquivo o trabalho vinha DEPOIS, sobrava 1 commit
  # apos o bump final, e tres assercoes falhavam por off-by-one MEU — o script
  # estava certo. Andaime errado reprova entrega correta.
  for v in 0.1.0 0.2.0 0.3.0; do
    echo "$v" > "$R/trabalho-$v.txt"
    git -C "$R" add "trabalho-$v.txt"; git -C "$R" commit -qm "trabalho antes de $v"
    printf '{\n  "name": "p",\n  "version": "%s"\n}\n' "$v" > "$R/.claude-plugin/plugin.json"
    git -C "$R" add .claude-plugin/plugin.json
    git -C "$R" commit -qm "Versao $v"
  done

  # o ultimo bump ja passou; agora os commits que o script tem que contar
  for ((i=1; i<=depois; i++)); do
    echo "$i" > "$R/depois-$i.txt"
    git -C "$R" add "depois-$i.txt"; git -C "$R" commit -qm "entrega $i"
  done
}

# $1 nome, $2 exit esperado, $3 contagem esperada (ou "-"), $4... args
checa() {
  local nome="$1" esp_exit="$2" esp_n="$3"; shift 3
  local saida n rc
  saida=$(node "$@" --json 2>&1); rc=$?
  n=$(printf '%s' "$saida" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const o=JSON.parse(s);console.log(o.medivel?o.commits:"-")}catch{console.log("?")}})')
  local bom=1
  [ "$rc" = "$esp_exit" ] || bom=0
  [ "$esp_n" = "-" ] || [ "$n" = "$esp_n" ] || bom=0
  if [ "$bom" = 1 ]; then
    ok=$((ok+1)); echo "  ok   $nome (exit $rc, commits=$n)"
  else
    falhou=$((falhou+1))
    echo "  FALHA $nome: esperava exit $esp_exit / commits=$esp_n, veio exit $rc / commits=$n"
    printf '%s\n' "$saida" | sed 's/^/         /' | head -6
  fi
}

R7="$RAIZ/sete";  montar "$R7" 7
R2="$RAIZ/dois";  montar "$R2" 2
R0="$RAIZ/zero";  montar "$R0" 0

echo
echo "== a contagem tem que estar CERTA, nao so plausivel =="
# O andaime deixa 3 bumps + 3 commits de trabalho entre eles. Contar do ULTIMO
# bump da exatamente `depois`; contar de qualquer outro lugar da mais.
checa "7 commits depois do ultimo bump conta 7"   2 7 "$R7/scripts/conferir-versao.cjs"
checa "2 commits depois do ultimo bump conta 2"   0 2 "$R2/scripts/conferir-versao.cjs"
checa "0 commits depois do ultimo bump conta 0"   0 0 "$R0/scripts/conferir-versao.cjs"

echo
echo "== -S vs -G: o defeito da primeira versao =="
# Com `-S"version"` a pickaxe nao ve o bump (a contagem da string nao muda) e
# cai no commit do andaime, contando TODOS os 6 commits intermediarios + os 2.
# Este caso e o que separa o mecanismo certo do numero plausivel.
esperado=2
real=$(node "$R2/scripts/conferir-versao.cjs" --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{console.log(JSON.parse(s).commits)})')
if [ "$real" = "$esperado" ]; then
  ok=$((ok+1)); echo "  ok   conta do ULTIMO bump, nao do primeiro commit do manifesto ($real)"
else
  falhou=$((falhou+1)); echo "  FALHA contou $real onde o ultimo bump deixa $esperado — pickaxe achando o commit errado"
fi

echo
echo "== o teto decide, nas duas direcoes =="
checa "teto 8 com 7 commits: passa"               0 7 "$R7/scripts/conferir-versao.cjs" --teto 8
checa "teto 7 com 7 commits: recusa (>=)"         2 7 "$R7/scripts/conferir-versao.cjs" --teto 7
checa "teto 1 com 2 commits: recusa"              2 2 "$R2/scripts/conferir-versao.cjs" --teto 1
checa "teto 1 com 0 commits: passa"               0 0 "$R0/scripts/conferir-versao.cjs" --teto 1

echo
echo "== --base aponta para outro commit =="
checa "--base no proprio bump conta 0"            0 0 "$R7/scripts/conferir-versao.cjs" --base HEAD~7

echo
echo "== o que nao da para medir NAO trava (falha aberta) =="
FORA="$RAIZ/sem-git"; mkdir -p "$FORA/.claude-plugin" "$FORA/scripts"
cp "$CHECADOR" "$FORA/scripts/conferir-versao.cjs"
printf '{"name":"p","version":"9.9.9"}\n' > "$FORA/.claude-plugin/plugin.json"
saida=$(node "$FORA/scripts/conferir-versao.cjs" 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s' "$saida" | grep -qF "nao deu para medir"; then
  ok=$((ok+1)); echo "  ok   pasta sem git sai 0 e diz o motivo"
else
  falhou=$((falhou+1)); echo "  FALHA pasta sem git: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

RM="$RAIZ/manifesto-ruim"; montar "$RM" 9
printf 'isto nao e json\n' > "$RM/.claude-plugin/plugin.json"
saida=$(node "$RM/scripts/conferir-versao.cjs" 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s' "$saida" | grep -qF "nao deu para medir"; then
  ok=$((ok+1)); echo "  ok   manifesto ilegivel sai 0 e diz o motivo"
else
  falhou=$((falhou+1)); echo "  FALHA manifesto ilegivel: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

SB="$RAIZ/sem-bump"
mkdir -p "$SB/.claude-plugin" "$SB/scripts"
git init -q "$SB"; git -C "$SB" config user.email t@t; git -C "$SB" config user.name t
git -C "$SB" config commit.gpgsign false
cp "$CHECADOR" "$SB/scripts/conferir-versao.cjs"
echo x > "$SB/a.txt"; git -C "$SB" add .; git -C "$SB" commit -qm "sem manifesto nenhum"
printf '{"name":"p","version":"0.1.0"}\n' > "$SB/.claude-plugin/plugin.json"
saida=$(node "$SB/scripts/conferir-versao.cjs" 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  ok=$((ok+1)); echo "  ok   manifesto nao commitado sai 0 (exit $rc)"
else
  falhou=$((falhou+1)); echo "  FALHA manifesto nao commitado: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

echo
echo "== a mensagem de recusa ensina o conserto =="
saida=$(node "$R7/scripts/conferir-versao.cjs" 2>&1)
for termo in "plugins/cache" "claude plugin marketplace update" "janela NOVA" "--teto"; do
  if printf '%s' "$saida" | grep -qF -- "$termo"; then
    ok=$((ok+1)); echo "  ok   recusa cita '$termo'"
  else
    falhou=$((falhou+1)); echo "  FALHA recusa nao cita '$termo'"
  fi
done

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
