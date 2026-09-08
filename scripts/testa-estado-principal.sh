#!/bin/bash
# Bateria do estado.cjs iniciar + exigir — checkout principal fora da branch padrão.
# Uso: bash scripts/testa-estado-principal.sh

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

mkdir -p "$SBP/scripts" "$SBP/hooks/lib"
cp "$SRC/scripts/estado.cjs" "$SBP/scripts/"
cp "$SRC/hooks/lib/raiz.cjs" "$SBP/hooks/lib/"
cp "$SRC/hooks/lib/config.cjs" "$SBP/hooks/lib/"

cd "$SBP" || exit 1
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
E="node scripts/estado.cjs"

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}

contem() { # nome, esperado_contem, saida
  local nome="$1"
  if echo "$3" | grep -q "$2"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava conter '$2'"; fi
}

echo
echo "== a. principal em fluxo/x, sem config → iniciar sai 2 =="
git init -q -b main
git config user.email "test@test"
git config user.name "Test"
touch FOCO.md
git add . && git commit -qm "inicial"
git checkout -q -b fluxo/x
saida=$($E iniciar --slug x 2>&1); exit_val=$?
esperado "iniciar --slug x sai 2" 2 bash -c "exit $exit_val"
contem "msg: RECUSADO" "RECUSADO" "$saida"
contem "msg: git worktree add" "git worktree add" "$saida"
contem "msg: git checkout main" "git checkout main" "$saida"
contem "msg: principal-livre" "principal-livre" "$saida"
[ ! -f docs/rainforest/estado/x.json ] && ok=$((ok+1)); echo "  ok   arquivo x.json NÃO existe" || { falhou=$((falhou+1)); echo "  FALHA arquivo x.json existe"; }

echo
echo "== b. principal em main → iniciar sai 0 =="
git checkout -q main
$E iniciar --slug y >/dev/null 2>&1 && ok=$((ok+1)); echo "  ok   iniciar --slug y sai 0" || { falhou=$((falhou+1)); echo "  FALHA iniciar --slug y sai $?"; }
[ -f docs/rainforest/estado/y.json ] && ok=$((ok+1)); echo "  ok   arquivo y.json existe" || { falhou=$((falhou+1)); echo "  FALHA arquivo y.json NÃO existe"; }

echo
echo "== c. worktree linkado → iniciar sai 0 =="
git worktree add -q ../wt-test fluxo/x
( cd "$SBP/../wt-test"
  export RFM_ESTADO_ROOT="$SBP/../wt-test"
  node "$SBP/scripts/estado.cjs" iniciar --slug z >/dev/null 2>&1
)
[ $? -eq 0 ] && ok=$((ok+1)); echo "  ok   worktree linkado sai 0" || { falhou=$((falhou+1)); echo "  FALHA worktree linkado falhou"; }
git worktree remove -f ../wt-test 2>/dev/null || true

echo
echo "== d. principal em fluxo/x com principal-livre: true → sai 0 =="
git checkout -q fluxo/x
mkdir -p "$SBP/.rainforest"
echo '{"principal-livre": true}' > "$SBP/.rainforest/config.json"
$E iniciar --slug w >/dev/null 2>&1 && ok=$((ok+1)); echo "  ok   iniciar --slug w sai 0" || { falhou=$((falhou+1)); echo "  FALHA iniciar --slug w falhou"; }
[ -f docs/rainforest/estado/w.json ] && ok=$((ok+1)); echo "  ok   arquivo w.json existe" || { falhou=$((falhou+1)); echo "  FALHA arquivo w.json NÃO existe"; }

echo
echo "== e. não é repositório git → iniciar sai 0 =="
mkdir -p "$SBP/nao-git"
(
  cd "$SBP/nao-git"
  # Garantir que GIT_DIR não está setado
  unset GIT_DIR 2>/dev/null || true
  export RFM_ESTADO_ROOT="$SBP/nao-git"
  touch FOCO.md
  node "$SBP/scripts/estado.cjs" iniciar --slug v 2>&1 | head -1
  exit $?
)
exit_code=$?
if [ $exit_code -eq 0 ]; then ok=$((ok+1)); echo "  ok   pasta não-git sai 0"
else falhou=$((falhou+1)); echo "  FALHA pasta não-git sai $exit_code"; fi

echo
echo "== f. principal em fluxo/x com estado já em main → exigir passa (aviso opcional) =="
cd "$SBP"
git checkout -q fluxo/x
$E exigir --slug y --estagio design >/dev/null 2>&1 && ok=$((ok+1)); echo "  ok   exigir passa mesmo em fluxo/x" || { falhou=$((falhou+1)); echo "  FALHA exigir falhou em fluxo/x"; }

echo
echo "== 7. MUTACAO — desligar a verificação tem que quebrar o caso a =="
cp scripts/estado.cjs scripts/estado-mutante.cjs
sed -i 's/if (checkout_problema) {/if (false \&\& checkout_problema) { \/\/ MUTADO/' scripts/estado-mutante.cjs
node scripts/estado-mutante.cjs iniciar --slug x-mut >/dev/null 2>&1 && ok=$((ok+1)); echo "  ok   sem verificação, iniciar passa" || { falhou=$((falhou+1)); echo "  FALHA mutação: iniciar recusa ainda"; }

echo
echo "== Resultado: $ok ok, $falhou falhou =="
exit $(( falhou > 0 ? 1 : 0 ))
