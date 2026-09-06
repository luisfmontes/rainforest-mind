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

# Monta um par de repositorios para testar a comparacao com `origin/main`: um
# "remoto" com o manifesto na versao $2, e um local com `origin` apontando pra
# ele (fetch ja feito, entao `origin/main` resolve) e o manifesto na versao $3.
# $1 = pasta base, $2 = versao do remoto (main), $3 = versao do local
montar_com_origin() {
  local BASE="$1" ver_remota="$2" ver_local="$3"
  local REMOTO="$BASE-remoto" LOCAL="$BASE"

  mkdir -p "$REMOTO/.claude-plugin"
  git init -q "$REMOTO"
  # symbolic-ref ANTES do primeiro commit: forca o nome "main" independente do
  # `init.defaultBranch` desta maquina, sem o qual `origin/main` nao existiria.
  git -C "$REMOTO" symbolic-ref HEAD refs/heads/main
  git -C "$REMOTO" config user.email t@t; git -C "$REMOTO" config user.name t
  git -C "$REMOTO" config commit.gpgsign false
  printf '{\n  "name": "p",\n  "version": "%s"\n}\n' "$ver_remota" > "$REMOTO/.claude-plugin/plugin.json"
  git -C "$REMOTO" add .claude-plugin; git -C "$REMOTO" commit -qm "Versao $ver_remota"

  mkdir -p "$LOCAL/.claude-plugin" "$LOCAL/scripts"
  git init -q "$LOCAL"
  git -C "$LOCAL" config user.email t@t; git -C "$LOCAL" config user.name t
  git -C "$LOCAL" config commit.gpgsign false
  cp "$CHECADOR" "$LOCAL/scripts/conferir-versao.cjs"
  git -C "$LOCAL" add scripts; git -C "$LOCAL" commit -qm "andaime"
  printf '{\n  "name": "p",\n  "version": "%s"\n}\n' "$ver_local" > "$LOCAL/.claude-plugin/plugin.json"
  git -C "$LOCAL" add .claude-plugin/plugin.json
  git -C "$LOCAL" commit -qm "Versao $ver_local"

  git -C "$LOCAL" remote add origin "$REMOTO"
  git -C "$LOCAL" fetch -q origin
}

# $1 nome, $2 exit esperado, $3 contagem esperada (ou "-"), $4 script dir (se comecar com /), $5... args
checa() {
  local nome="$1" esp_exit="$2" esp_n="$3"; shift 3
  local script_dir="" saida n rc

  # Se o primeiro argumento é um caminho absoluto que não é um arquivo, é o diretório
  if [ -d "$1" ]; then
    script_dir="$1"; shift
  fi

  local saida n rc
  if [ -z "$script_dir" ]; then
    saida=$(node "$@" --json 2>&1); rc=$?
  else
    saida=$(cd "$script_dir" && node "$@" --json 2>&1); rc=$?
  fi
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
# Passa o diretório como primeiro argumento para mudar o cwd antes de rodar
checa "7 commits depois do ultimo bump conta 7"   2 7 "$R7" "scripts/conferir-versao.cjs"
checa "2 commits depois do ultimo bump conta 2"   0 2 "$R2" "scripts/conferir-versao.cjs"
checa "0 commits depois do ultimo bump conta 0"   0 0 "$R0" "scripts/conferir-versao.cjs"

echo
echo "== -S vs -G: o defeito da primeira versao =="
# Com `-S"version"` a pickaxe nao ve o bump (a contagem da string nao muda) e
# cai no commit do andaime, contando TODOS os 6 commits intermediarios + os 2.
# Este caso e o que separa o mecanismo certo do numero plausivel.
esperado=2
real=$(cd "$R2" && node "scripts/conferir-versao.cjs" --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{console.log(JSON.parse(s).commits)})')
if [ "$real" = "$esperado" ]; then
  ok=$((ok+1)); echo "  ok   conta do ULTIMO bump, nao do primeiro commit do manifesto ($real)"
else
  falhou=$((falhou+1)); echo "  FALHA contou $real onde o ultimo bump deixa $esperado — pickaxe achando o commit errado"
fi

echo
echo "== o teto decide, nas duas direcoes =="
checa "teto 8 com 7 commits: passa"               0 7 "$R7" "scripts/conferir-versao.cjs" --teto 8
checa "teto 7 com 7 commits: recusa (>=)"         2 7 "$R7" "scripts/conferir-versao.cjs" --teto 7
checa "teto 1 com 2 commits: recusa"              2 2 "$R2" "scripts/conferir-versao.cjs" --teto 1
checa "teto 1 com 0 commits: passa"               0 0 "$R0" "scripts/conferir-versao.cjs" --teto 1

echo
echo "== --base aponta para outro commit =="
checa "--base no proprio bump conta 0"            0 0 "$R7" "scripts/conferir-versao.cjs" --base HEAD~7

echo
echo "== script copiado para pasta sem git mede o repositorio do cwd =="
# Cria uma pasta temporária SEM .git, fora do repositório
FORA="$RAIZ/script-fora"; mkdir -p "$FORA/scripts"
cp "$CHECADOR" "$FORA/scripts/conferir-versao.cjs"

# Monta um repositório de plugin de fixture DENTRO de uma pasta fora do git
FIXTURE="$RAIZ/fixture-plugin"; montar "$FIXTURE" 3

# Roda o script COPIADO com o cwd no repositório de fixture
saida_fora=$(cd "$FIXTURE" && node "$FORA/scripts/conferir-versao.cjs" --json 2>&1); rc_fora=$?
n_fora=$(printf '%s' "$saida_fora" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const o=JSON.parse(s);console.log(o.medivel?o.commits:"-")}catch{console.log("?")}})')

# Roda o script ORIGINAL de dentro do repositório de fixture
saida_orig=$(cd "$FIXTURE" && node "$FIXTURE/scripts/conferir-versao.cjs" --json 2>&1); rc_orig=$?
n_orig=$(printf '%s' "$saida_orig" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const o=JSON.parse(s);console.log(o.medivel?o.commits:"-")}catch{console.log("?")}})')

# Afirma que exit e contagem são os mesmos
if [ "$rc_fora" = "$rc_orig" ] && [ "$n_fora" = "$n_orig" ]; then
  ok=$((ok+1)); echo "  ok   script copiado mede cwd ($n_fora commits), mesmo que rodado de dentro (exit $rc_orig)"
else
  falhou=$((falhou+1))
  echo "  FALHA script copiado: exit=$rc_fora/commits=$n_fora, esperado exit=$rc_orig/commits=$n_orig"
  printf '%s\n' "$saida_fora" | sed 's/^/         /' | head -3
fi

echo
echo "== repositorio git SEM .claude-plugin/plugin.json NAO e plugin =="
NPP="$RAIZ/nao-e-plugin"
mkdir -p "$NPP/scripts"
git init -q "$NPP"; git -C "$NPP" config user.email t@t; git -C "$NPP" config user.name t
git -C "$NPP" config commit.gpgsign false
cp "$CHECADOR" "$NPP/scripts/conferir-versao.cjs"
echo x > "$NPP/a.txt"; git -C "$NPP" add .; git -C "$NPP" commit -qm "repo sem plugin"
saida=$(cd "$NPP" && node "scripts/conferir-versao.cjs" 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s' "$saida" | grep -qF "nao e um plugin"; then
  ok=$((ok+1)); echo "  ok   repositorio sem plugin sai 0 e diz que nao e plugin"
else
  falhou=$((falhou+1)); echo "  FALHA repositorio sem plugin: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

echo
echo "== pasta fora de qualquer repositorio git =="
PURO="$RAIZ/puro"; mkdir -p "$PURO/scripts"
cp "$CHECADOR" "$PURO/scripts/conferir-versao.cjs"
saida=$(cd "$PURO" && node "scripts/conferir-versao.cjs" 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s' "$saida" | grep -qF "nao e repositorio git"; then
  ok=$((ok+1)); echo "  ok   pasta sem git sai 0 e diz que nao e repositorio"
else
  falhou=$((falhou+1)); echo "  FALHA pasta sem git: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

RM="$RAIZ/manifesto-ruim"; montar "$RM" 9
printf 'isto nao e json\n' > "$RM/.claude-plugin/plugin.json"
saida=$(cd "$RM" && node "scripts/conferir-versao.cjs" 2>&1); rc=$?
if [ "$rc" = 4 ] && printf '%s' "$saida" | grep -qF "nao deu para medir"; then
  ok=$((ok+1)); echo "  ok   manifesto ilegivel sai 4"
else
  falhou=$((falhou+1)); echo "  FALHA manifesto ilegivel sai 4: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

SB="$RAIZ/sem-bump"
mkdir -p "$SB/.claude-plugin" "$SB/scripts"
git init -q "$SB"; git -C "$SB" config user.email t@t; git -C "$SB" config user.name t
git -C "$SB" config commit.gpgsign false
cp "$CHECADOR" "$SB/scripts/conferir-versao.cjs"
echo x > "$SB/a.txt"; git -C "$SB" add .; git -C "$SB" commit -qm "sem manifesto nenhum"
printf '{"name":"p","version":"0.1.0"}\n' > "$SB/.claude-plugin/plugin.json"
saida=$(cd "$SB" && node "scripts/conferir-versao.cjs" 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  ok=$((ok+1)); echo "  ok   manifesto nao commitado sai 0 (exit $rc)"
else
  falhou=$((falhou+1)); echo "  FALHA manifesto nao commitado: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

echo
echo "== a mensagem de recusa ensina o conserto =="
saida=$(cd "$R7" && node "scripts/conferir-versao.cjs" 2>&1)
for termo in "plugins/cache" "claude plugin marketplace update" "janela NOVA" "--teto"; do
  if printf '%s' "$saida" | grep -qF -- "$termo"; then
    ok=$((ok+1)); echo "  ok   recusa cita '$termo'"
  else
    falhou=$((falhou+1)); echo "  FALHA recusa nao cita '$termo'"
  fi
done

echo
echo "== comparacao da versao declarada com a de origin/main =="
# --teto 999 de proposito nos tres: prova que a recusa/aprovacao veio da
# COMPARACAO DE NUMERO, nunca do teto de commits.

V_IGUAL="$RAIZ/versao-igual";  montar_com_origin "$V_IGUAL" "1.3.0" "1.3.0"
V_MENOR="$RAIZ/versao-menor";  montar_com_origin "$V_MENOR" "1.3.0" "0.9.0"
V_MAIOR="$RAIZ/versao-maior";  montar_com_origin "$V_MAIOR" "1.3.0" "1.4.0"

# Confere que a fixture TEM origin/main antes de asserir qualquer coisa — senao
# o caso mediria o ramo "nao comparou" (D5) e passaria verde sem testar nada.
for d in "$V_IGUAL" "$V_MENOR" "$V_MAIOR"; do
  if ! (cd "$d" && git rev-parse origin/main >/dev/null 2>&1); then
    falhou=$((falhou+1))
    echo "  FALHA fixture $d: origin/main nao resolve — o caso nao testaria a comparacao"
  fi
done

saida=$(cd "$V_IGUAL" && node "scripts/conferir-versao.cjs" --teto 999 2>&1); rc=$?
if [ "$rc" = 2 ] && printf '%s' "$saida" | grep -qF "1.3.0"; then
  ok=$((ok+1)); echo "  ok   versao igual a da main recusa (exit $rc)"
else
  falhou=$((falhou+1)); echo "  FALHA versao igual a da main recusa: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

saida=$(cd "$V_MENOR" && node "scripts/conferir-versao.cjs" --teto 999 2>&1); rc=$?
if [ "$rc" = 2 ] && printf '%s' "$saida" | grep -qF "0.9.0" && printf '%s' "$saida" | grep -qF "1.3.0"; then
  ok=$((ok+1)); echo "  ok   versao menor que a da main recusa (exit $rc)"
else
  falhou=$((falhou+1)); echo "  FALHA versao menor que a da main recusa: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

saida=$(cd "$V_MAIOR" && node "scripts/conferir-versao.cjs" --teto 999 2>&1); rc=$?
if [ "$rc" = 0 ]; then
  ok=$((ok+1)); echo "  ok   versao maior que a da main passa (exit $rc)"
else
  falhou=$((falhou+1)); echo "  FALHA versao maior que a da main passa: exit $rc"; printf '%s\n' "$saida" | sed 's/^/         /'
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
