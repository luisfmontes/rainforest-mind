#!/bin/bash
# Bateria do caminho leve (#430, tarefa 1): `estado.cjs leve --motivo` e o leitor
# hooks/lib/caminho-leve.cjs.
# Uso: timeout 600 bash scripts/testa-estado-leve.sh
#
# Repositórios git REAIS em sandbox (mktemp -d, apagado por trap). Cada bloco é uma
# afirmação do "pronto quando" da tarefa 1 do plano fluxo-pulado-bloqueio, e toda
# asserção tem os dois ramos (ok / FALHOU). Não há caminho de skip: o placar sai com
# skipped: 0 porque nenhum caso pode ser pulado.
#
# A mutação de hooks/lib/caminho-leve.cjs (a linha de leveValido) é provada por
# scripts/conferir-mutacao.cjs: o caso que tem de ficar vermelho é
# "registro de leve com motivo vazio gravado a mao nao libera a branch".

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SANDBOXES=()
novo_sandbox() { local d; d=$(mktemp -d); SANDBOXES+=("$d"); printf -v "$1" '%s' "$d"; }
cleanup() { for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done; }
trap cleanup EXIT

# No Git Bash, /c/... e /tmp/... não atravessam o node pelo ambiente: cygpath -m dá C:/...
misto() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
SRC_M="$(misto "$SRC")"
novo_sandbox SBX0
SBX="$(misto "$SBX0")"

# Isolamento: a sessão pode trazer CLAUDE_PROJECT_DIR, e RAIZ a prefere ao cwd.
unset CLAUDE_PROJECT_DIR RFM_ESTADO_ROOT
export HOME="$SBX/home" USERPROFILE="$SBX/home"
mkdir -p "$SBX/home" "$SBX/aux"

cat > "$SBX/aux/ler-leve.cjs" <<'EOF'
const { leveDaBranch } = require(process.argv[2]);
console.log(JSON.stringify(leveDaBranch({ gitTop: process.argv[3], branch: process.argv[4] })));
EOF

cat > "$SBX/aux/resolver.cjs" <<'EOF'
const { resolver } = require(process.argv[2]);
console.log(JSON.stringify(resolver({ cwd: process.argv[3] })));
EOF

cat > "$SBX/aux/novo-fluxo.cjs" <<'EOF'
// Grava um estado de fluxo real (novo() do estado.cjs) e diz se o leitor o toma por so-leve.
const fs = require('fs');
const { novo } = require(process.argv[2]);
const { soLeve } = require(process.argv[3]);
const e = novo(process.argv[5], 'teste');
fs.writeFileSync(process.argv[4], JSON.stringify(e, null, 2) + '\n');
console.log(JSON.stringify({ soLeve: soLeve(e) }));
EOF

OK=0
FALHOU=0
afirma() { # $1 = o que se afirma, $2 = esperado, $3 = obtido
  if [ "$2" = "$3" ]; then
    OK=$((OK + 1)); echo "ok      $1"
  else
    FALHOU=$((FALHOU + 1)); echo "FALHOU  $1 (esperado: [$2] obtido: [$3])"
  fi
}
tem() { # $1 = texto, $2 = trecho; imprime 1 se contém, 0 se não
  case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac
}
arquivos_json() { # $1 = repo; quantos .json há em docs/rainforest/estado
  if [ -d "$1/docs/rainforest/estado" ]; then
    find "$1/docs/rainforest/estado" -maxdepth 1 -name '*.json' | wc -l | tr -d ' '
  else
    echo 0
  fi
}
porcelain() { (cd "$1" && git status --porcelain); }
est() { # $1 = repo; o resto são os argumentos do estado.cjs
  local r="$1"; shift
  (cd "$r" && RFM_ESTADO_ROOT="$r" node "$SRC_M/scripts/estado.cjs" "$@")
}
ler_leve() { # $1 = repo, $2 = branch; imprime o JSON de leveDaBranch
  node "$SBX/aux/ler-leve.cjs" "$SRC_M/hooks/lib/caminho-leve.cjs" "$1" "$2"
}
novo_repo() { # $1 = nome; repositório git real em main com um commit; caminho em REPO
  REPO="$SBX/$1"
  mkdir -p "$REPO"
  (cd "$REPO" && git init -q && git symbolic-ref HEAD refs/heads/main \
    && git config user.email "test@<email>" && git config user.name "Test" \
    && echo base > base.txt && git add . && git commit -qm inicial)
}
novo_rf() { # repositório com trilho rainforest (docs/rainforest/estado/) versionado
  novo_repo "$1"
  (cd "$REPO" && mkdir -p docs/rainforest/estado && touch docs/rainforest/estado/.gitkeep \
    && git add . && git commit -qm "trilho rainforest")
}
novo_pr() { # repositório com trilho protheus (só docs/plans/*.gates.json) versionado
  novo_repo "$1"
  (cd "$REPO" && mkdir -p docs/plans && echo '{}' > docs/plans/a.gates.json \
    && git add . && git commit -qm "trilho protheus")
}

DATA=$(date +%Y-%m-%d)

echo "(sandbox: $SBX)"
echo ""

# ---------------------------------------------------------------- A. leve na branch
echo "== A. trilho rainforest: leve na branch de trabalho"
novo_rf rfa
(cd "$REPO" && git checkout -qb fluxo/x)
OUT=$(est "$REPO" leve --motivo "hotfix mecanico" 2>"$SBX/err"); RC=$?
afirma "A1 leve na branch fluxo/x sai 0" 0 "$RC"
afirma "A2 grava um arquivo de estado da branch (<data>-x.json)" 1 \
  "$([ -f "$REPO/docs/rainforest/estado/$DATA-x.json" ] && echo 1 || echo 0)"
afirma "A3 leveDaBranch devolve o motivo para fluxo/x" 1 \
  "$(tem "$(ler_leve "$REPO" fluxo/x)" '"motivo":"hotfix mecanico"')"
afirma "A4 o registro leve traz a data" 1 \
  "$(tem "$(ler_leve "$REPO" fluxo/x)" '"data":"')"
afirma "A5 leveDaBranch nao devolve para fluxo/y" null "$(ler_leve "$REPO" fluxo/y)"
OUT=$(est "$REPO" leve --motivo "segunda declaracao" 2>"$SBX/err"); RC=$?
afirma "A6 segundo leve na mesma branch sai 0" 0 "$RC"
afirma "A7 segundo leve substitui o motivo, sem segundo arquivo" 1 \
  "$(tem "$(ler_leve "$REPO" fluxo/x)" '"motivo":"segunda declaracao"')"
afirma "A8 segundo leve nao cria segundo arquivo" 1 "$(arquivos_json "$REPO")"
echo ""

# ---------------------------------------------------------------- B. recusas
echo "== B. recusas: exit 2 e nada gravado"
novo_rf rfb
(cd "$REPO" && git checkout -qb fluxo/x)
OUT=$(est "$REPO" leve --motivo "" 2>"$SBX/err"); RC=$?
afirma "B1 --motivo vazio sai 2" 2 "$RC"
afirma "B1 --motivo vazio nao grava nada" 0 "$(arquivos_json "$REPO")"
OUT=$(est "$REPO" leve --motivo "   " 2>"$SBX/err"); RC=$?
afirma "B2 --motivo so com espacos sai 2" 2 "$RC"
afirma "B2 --motivo so com espacos nao grava nada" 0 "$(arquivos_json "$REPO")"
OUT=$(est "$REPO" leve 2>"$SBX/err"); RC=$?
afirma "B3 --motivo ausente sai 2" 2 "$RC"
afirma "B3 --motivo ausente nao grava nada" 0 "$(arquivos_json "$REPO")"
OUT=$(est "$REPO" leve --motivo x --foo y 2>"$SBX/err"); RC=$?
afirma "B4 flag desconhecida sai 1 antes de gravar" 1 "$RC"
afirma "B4 flag desconhecida nao grava nada" 0 "$(arquivos_json "$REPO")"
(cd "$REPO" && git checkout -q --detach)
OUT=$(est "$REPO" leve --motivo x 2>"$SBX/err"); RC=$?
afirma "B5 HEAD destacado sai 2" 2 "$RC"
afirma "B5 HEAD destacado nao grava nada" 0 "$(arquivos_json "$REPO")"

novo_rf rfm
OUT=$(est "$REPO" leve --motivo x 2>"$SBX/err"); RC=$?
ERR=$(cat "$SBX/err")
afirma "B6 branch padrao (main) sai 2" 2 "$RC"
afirma "B6 branch padrao cita a regra 11 no stderr" 1 "$(tem "$ERR" 'regra 11')"
afirma "B6 branch padrao nao grava nada" 0 "$(arquivos_json "$REPO")"
afirma "B6 branch padrao deixa a arvore limpa" "" "$(porcelain "$REPO")"
echo ""

# ---------------------------------------------------------------- C. trilho protheus
echo "== C. trilho protheus: mapa sob o git-common-dir"
novo_pr prc
(cd "$REPO" && git checkout -qb fluxo/p)
OUT=$(est "$REPO" leve --motivo "hotfix" 2>"$SBX/err"); RC=$?
afirma "C1 trilho protheus sai 0" 0 "$RC"
afirma "C2 a arvore de trabalho fica limpa" "" "$(porcelain "$REPO")"
afirma "C3 o mapa fica sob o .git" 1 \
  "$([ -f "$REPO/.git/rainforest-leve.json" ] && echo 1 || echo 0)"
afirma "C4 o mapa tem a branch fluxo/p" 1 \
  "$(tem "$(cat "$REPO/.git/rainforest-leve.json")" '"fluxo/p"')"
afirma "C5 leveDaBranch le o trilho protheus" 1 \
  "$(tem "$(ler_leve "$REPO" fluxo/p)" '"motivo":"hotfix"')"
afirma "C6 leveDaBranch nao devolve para outra branch" null "$(ler_leve "$REPO" fluxo/q)"
(cd "$REPO" && git checkout -q main)
OUT=$(est "$REPO" leve --motivo "na padrao" 2>"$SBX/err"); RC=$?
afirma "C7 trilho protheus aceita a branch padrao, sai 0" 0 "$RC"
afirma "C7 e a arvore continua limpa" "" "$(porcelain "$REPO")"
afirma "C7 leveDaBranch le o leve da branch padrao" 1 \
  "$(tem "$(ler_leve "$REPO" main)" '"motivo":"na padrao"')"
echo ""

# ---------------------------------------------------------------- D. listar, concluido, resolver
echo "== D. registro so de leve nao vira fluxo aberto"
novo_rf rfd
(cd "$REPO" && git checkout -qb fluxo/x)
est "$REPO" leve --motivo d >/dev/null 2>&1
OUT=$(est "$REPO" listar 2>"$SBX/err"); RC=$?
afirma "D1 listar sai 0" 0 "$RC"
afirma "D1 listar nao mostra o registro como trabalho" "(nenhum trabalho em andamento)" "$OUT"
OUT=$(est "$REPO" concluido 2>"$SBX/err"); RC=$?
afirma "D2 concluido (sem slug) sai 0 com so-leve" 0 "$RC"
afirma "D2 concluido (sem slug) nao lista o registro" "" "$OUT"
OUT=$(est "$REPO" concluido --slug "$DATA-x" 2>"$SBX/err"); RC=$?
afirma "D3 concluido --slug sai 0 com so-leve" 0 "$RC"
OUT=$(est "$REPO" proximo --slug "$DATA-x" 2>"$SBX/err"); RC=$?
afirma "D4 proximo nao quebra ao ler so-leve" 0 "$RC"
afirma "D4 proximo diz completo, como um fluxo sem estagio aberto" "completo" "$OUT"
afirma "D5 resolver devolve null na branch so com leve" null \
  "$(node "$SBX/aux/resolver.cjs" "$SRC_M/hooks/lib/estagio-ativo.cjs" "$REPO")"

novo_rf rfe
(cd "$REPO" && git checkout -qb fluxo/x)
SOLEVE=$(node "$SBX/aux/novo-fluxo.cjs" "$SRC_M/scripts/estado.cjs" "$SRC_M/hooks/lib/caminho-leve.cjs" \
  "$REPO/docs/rainforest/estado/$DATA-x.json" "$DATA-x")
afirma "D6 um estado novo() de fluxo nao e so-leve (conferencia de chaves)" '{"soLeve":false}' "$SOLEVE"
afirma "D6 resolver devolve o fluxo aberto" 1 \
  "$(tem "$(node "$SBX/aux/resolver.cjs" "$SRC_M/hooks/lib/estagio-ativo.cjs" "$REPO")" '"estagio":"design"')"
OUT=$(est "$REPO" leve --motivo z 2>"$SBX/err"); RC=$?
afirma "D6 leve sobre fluxo aberto sai 0" 0 "$RC"
afirma "D6 leve sobre fluxo aberto nao cria segundo arquivo" 1 "$(arquivos_json "$REPO")"
afirma "D6 listar segue mostrando o fluxo aberto" 1 "$(tem "$(est "$REPO" listar)" '-> design')"

novo_rf rfa2
(cd "$REPO" && git checkout -qb fluxo/x && echo '{}' > docs/rainforest/estado/x.json \
  && echo '{}' > docs/rainforest/estado/"$DATA"-x.json)
OUT=$(est "$REPO" leve --motivo ambiguo 2>"$SBX/err"); RC=$?
ERR=$(cat "$SBX/err")
afirma "D7 dois arquivos casam com a branch: sai 2" 2 "$RC"
afirma "D7 o stderr diz que e ambiguo" 1 "$(tem "$ERR" 'mais de um')"
afirma "D7 continuam so os 2 arquivos que ja existiam, nenhum criado" 2 "$(arquivos_json "$REPO")"
echo ""

# ---------------------------------------------------------------- E. registro gravado a mao
echo "== E. registro gravado a mao: so motivo valido libera"
novo_rf rfh
(cd "$REPO" && git checkout -qb fluxo/v)
printf '%s\n' "{\"slug\":\"v\",\"leve\":{\"motivo\":\"\",\"data\":\"$DATA\"}}" > "$REPO/docs/rainforest/estado/$DATA-v.json"
(cd "$REPO" && git checkout -qb fluxo/w)
printf '%s\n' "{\"slug\":\"w\",\"leve\":{\"motivo\":\"   \",\"data\":\"$DATA\"}}" > "$REPO/docs/rainforest/estado/$DATA-w.json"
(cd "$REPO" && git checkout -qb fluxo/u)
printf '%s\n' "{\"slug\":\"u\",\"leve\":{\"motivo\":5,\"data\":\"$DATA\"}}" > "$REPO/docs/rainforest/estado/$DATA-u.json"
(cd "$REPO" && git checkout -qb fluxo/ok)
printf '%s\n' "{\"slug\":\"ok\",\"leve\":{\"motivo\":\"valido\",\"data\":\"$DATA\"}}" > "$REPO/docs/rainforest/estado/$DATA-ok.json"
afirma "registro de leve com motivo vazio gravado a mao nao libera a branch" null "$(ler_leve "$REPO" fluxo/v)"
afirma "registro de leve com motivo so de espacos nao libera a branch" null "$(ler_leve "$REPO" fluxo/w)"
afirma "registro de leve com motivo nao-texto nao libera a branch" null "$(ler_leve "$REPO" fluxo/u)"
afirma "controle: registro de leve com motivo valido gravado a mao libera" 1 \
  "$(tem "$(ler_leve "$REPO" fluxo/ok)" '"motivo":"valido"')"

novo_pr prh
(cd "$REPO" && git checkout -qb fluxo/e && echo '{"fluxo/e":{"motivo":"","data":"x"}}' > .git/rainforest-leve.json)
afirma "mapa protheus com motivo vazio gravado a mao nao libera a branch" null "$(ler_leve "$REPO" fluxo/e)"
echo ""

# ---------------------------------------------------------------- F. iniciar sobre so-leve
echo "== F. iniciar sobre registro so de leve abre o fluxo e preserva o leve"
novo_rf rff
(cd "$REPO" && git checkout -qb fluxo/z)
est "$REPO" leve --motivo f >/dev/null 2>&1
(cd "$REPO" && git checkout -q main)
OUT=$(est "$REPO" iniciar --slug "$DATA-z" 2>"$SBX/err"); RC=$?
afirma "F1 iniciar sobre so-leve sai 0" 0 "$RC"
afirma "F1 o arquivo ganha o bloco de design" 1 \
  "$(tem "$(cat "$REPO/docs/rainforest/estado/$DATA-z.json")" '"design"')"
afirma "F1 o arquivo preserva o leve" 1 \
  "$(tem "$(cat "$REPO/docs/rainforest/estado/$DATA-z.json")" '"motivo": "f"')"
OUT=$(est "$REPO" iniciar --slug "$DATA-z" 2>"$SBX/err"); RC=$?
afirma "F2 iniciar sobre fluxo ja aberto continua recusando (sai 1)" 1 "$RC"
echo ""

echo "ok: $OK   falhou: $FALHOU   skipped: 0"
if [ "$FALHOU" -ne 0 ]; then
  exit 1
fi
exit 0
