#!/bin/bash
# Bateria do scripts/catalogo-funcoes.cjs (D7, D9, D10 do design lgpd-e-duplicata).
#
# O QUE PRECISA PROVAR, pela SAIDA dos subcomandos (nenhum caso le o texto do fonte):
#   1. dart: função de topo e método de classe entram no catálogo;
#   2. gerados (*.g.dart, .dart_tool/) e testes ficam fora; --incluir-testes traz o teste;
#   3. repo real: cmdPlantar aponta para scripts/ideias.cjs na linha que o grep devolve;
#   4. maiores em ordem decrescente, e o primeiro número casa com wc -l;
#   5. separar grava só a categoria com 3 ou mais funções;
#   6. conferir: grupo com a linha real sai 0; com a linha real+1 sai 1 e nomeia cmdPlantar.
#
# Fixture em mktemp, FORA do worktree, com git init. Arquivos e payloads montados por node,
# nunca por heredoc de conteúdo. Caminhos vão para o node em forma Windows (cygpath -m).
#
# Uso: bash scripts/testa-catalogo-funcoes.sh

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
winpath() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
[ -f "$RAIZ/scripts/catalogo-funcoes.cjs" ] || { echo "FALHA: nao achei $RAIZ/scripts/catalogo-funcoes.cjs"; exit 1; }
CAT="$(winpath "$RAIZ")/scripts/catalogo-funcoes.cjs"
RAIZN="$(winpath "$RAIZ")"

SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

ok=0; falhou=0
saiu()  { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (exit $2, esperava $3)"; fi; }
tem()   { if grep -qF -- "$3" <<<"$2"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3')"; echo "$2" | sed 's/^/         /'; fi; }
linha() { if grep -qxF -- "$3" <<<"$2"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava a linha exata '$3')"; echo "$2" | sed 's/^/         /'; fi; }
nao()   { if grep -qF -- "$3" <<<"$2"; then falhou=$((falhou+1)); echo "  FALHA $1 (nao esperava '$3')"; echo "$2" | sed 's/^/         /'; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

# Uma linha por entrada do catálogo: arquivo:linha:nome:linguagem. Lê o JSON pela entrada padrão.
tuplas() {
  node -e 'let s="";process.stdin.on("data",(d)=>{s+=d}).on("end",()=>{const c=JSON.parse(s);process.stdout.write(c.map((e)=>e.arquivo+":"+e.linha+":"+e.nome+":"+e.linguagem).join("\n")+"\n")})'
}

# Repo git de teste: caminho=conteudo (\n literal vira quebra). Tudo entra no indice (git add -A),
# inclusive os arquivos que o catalogo tem de excluir: a exclusao tem de ser do script, nao do git.
montar_repo() {
  local dir="$1"; shift
  mkdir -p "$dir"
  ( cd "$dir" && git init -q && git config user.email t@t && git config user.name Test && git config core.autocrlf false ) || return 1
  local par caminho conteudo
  for par in "$@"; do
    caminho="${par%%=*}"; conteudo="${par#*=}"
    mkdir -p "$dir/$(dirname "$caminho")"
    node -e 'require("fs").writeFileSync(process.argv[1], process.argv[2].replace(/\\n/g, "\n"))' "$(winpath "$dir/$caminho")" "$conteudo" || return 1
  done
  ( cd "$dir" && git add -A && git commit -q -m base ) || return 1
}

# Arquivo com 40 linhas. A quebra vai como "\n" LITERAL, como nos outros arquivos do
# fixture, e a linha NAO comeca com barra: argumento que comeca com "//" e convertido
# como caminho pelo MSYS do Git Bash ("\" vira "/"), e o big.js nascia com uma linha so.
BIG="$(node -e 'process.stdout.write("let linha = 1;\\n".repeat(40))')"

FIX="$SBP/fixture"
montar_repo "$FIX" \
  'lib/a.dart=void main() {\n  print(x);\n}\n\nFuture<int> carregar(int x) async {\n  return x;\n}\n\nclass Repo {\n  Future<int> buscar(int id) async {\n    return id;\n  }\n\n  void _salvar(int v) {}\n}\n' \
  'lib/a.g.dart=void gerado() {}\n' \
  '.dart_tool/x.dart=void escondido() {}\n' \
  'src/util.js=function somar(a, b) {\n  return a + b;\n}\n\nclass Calc {\n  async calcular(x) {\n    return x;\n  }\n}\n' \
  'src/app.py=def ola():\n    return 1\n' \
  'src/foo.test.js=function teste() {}\n' \
  "src/big.js=$BIG"
FIXN="$(winpath "$FIX")"

echo "== 1. dart: função de topo e método de classe entram no catálogo =="
node "$CAT" listar --raiz "$FIXN" > "$SBP/c1.json" 2> "$SBP/e1.txt"; EXIT=$?
saiu "listar do fixture sai 0" "$EXIT" 0
T1="$(tuplas < "$SBP/c1.json")"
linha "lib/a.dart:1 main (função de topo sem retorno) é dart" "$T1" "lib/a.dart:1:main:dart"
linha "lib/a.dart:5 carregar (topo com Future<int>) é dart" "$T1" "lib/a.dart:5:carregar:dart"
linha "lib/a.dart:9 Repo (classe) é dart" "$T1" "lib/a.dart:9:Repo:dart"
linha "lib/a.dart:10 buscar (método com tipo de retorno) é dart" "$T1" "lib/a.dart:10:buscar:dart"
linha "lib/a.dart:14 _salvar (método void) é dart" "$T1" "lib/a.dart:14:_salvar:dart"
linha "src/util.js:6 calcular (método JS com async) entra" "$T1" "src/util.js:6:calcular:js"
linha "src/app.py:1 ola (def de topo) entra" "$T1" "src/app.py:1:ola:py"

echo "== 2. gerados e testes ficam fora; --incluir-testes traz o teste =="
nao "lib/a.g.dart (gerado) fica fora" "$T1" "lib/a.g.dart"
nao ".dart_tool/x.dart fica fora" "$T1" ".dart_tool/"
nao "src/foo.test.js (teste) fica fora sem a flag" "$T1" "src/foo.test.js"
node "$CAT" listar --raiz "$FIXN" --incluir-testes > "$SBP/c2.json" 2> "$SBP/e2.txt"; EXIT=$?
saiu "listar com --incluir-testes sai 0" "$EXIT" 0
T2="$(tuplas < "$SBP/c2.json")"
linha "com --incluir-testes o teste aparece" "$T2" "src/foo.test.js:1:teste:js"
nao "gerado continua fora mesmo com --incluir-testes" "$T2" "lib/a.g.dart"
nao ".dart_tool continua fora mesmo com --incluir-testes" "$T2" ".dart_tool/"

echo "== 3. repo real: cmdPlantar aponta para scripts/ideias.cjs na linha do grep =="
node "$CAT" listar --raiz "$RAIZN" > "$SBP/real.json" 2> "$SBP/e3.txt"; EXIT=$?
saiu "listar do repo real sai 0" "$EXIT" 0
LINHA_GREP="$(grep -n "^function cmdPlantar" "$RAIZ/scripts/ideias.cjs" | cut -d: -f1)"
ACHADO="$(node -e 'let s="";process.stdin.on("data",(d)=>{s+=d}).on("end",()=>{const c=JSON.parse(s);const x=c.find((e)=>e.nome==="cmdPlantar");process.stdout.write(x?x.arquivo+":"+x.linha:"NENHUM")})' < "$SBP/real.json")"
igual "cmdPlantar no catálogo aponta para a linha do grep" "$ACHADO" "scripts/ideias.cjs:$LINHA_GREP"

echo "== 4. maiores em ordem decrescente; o primeiro número casa com wc -l =="
node "$CAT" maiores --raiz "$FIXN" --top 2 > "$SBP/m.txt" 2> "$SBP/e4.txt"; EXIT=$?
saiu "maiores sai 0" "$EXIT" 0
igual "maiores --top 2 devolve duas linhas" "$(wc -l < "$SBP/m.txt" | tr -d ' ')" "2"
N1="$(sed -n 1p "$SBP/m.txt" | awk '{print $1}')"
N2="$(sed -n 2p "$SBP/m.txt" | awk '{print $1}')"
CAM1="$(sed -n 1p "$SBP/m.txt" | sed 's/^[0-9]* linhas  //')"
igual "o maior arquivo é src/big.js" "$CAM1" "src/big.js"
igual "primeiro número casa com wc -l do arquivo" "$N1" "$(wc -l < "$FIX/$CAM1" | tr -d ' ')"
if [ "$N1" -ge "$N2" ]; then ok=$((ok+1)); echo "  ok   ordem decrescente ($N1 >= $N2)"; else falhou=$((falhou+1)); echo "  FALHA ordem decrescente ($N1 < $N2)"; fi

echo "== 5. separar grava só a categoria com 3 ou mais funções =="
node -e 'const f=process.argv[1]; const e=(n,c)=>({arquivo:"a.js",linha:1,nome:n,category:c}); require("fs").writeFileSync(f, JSON.stringify([e("p1","parsing"),e("p2","parsing"),e("p3","parsing"),e("u1","ui"),e("u2","ui")]))' "$(winpath "$SBP/categorizado.json")"
node "$CAT" separar --catalogo "$(winpath "$SBP/categorizado.json")" --saida "$(winpath "$SBP/separado")" --minimo 3 > "$SBP/s5.txt" 2> "$SBP/e5.txt"; EXIT=$?
saiu "separar sai 0" "$EXIT" 0
igual "imprime quantas categorias gravou" "$(cat "$SBP/s5.txt")" "categorias gravadas: 1"
igual "só parsing.json foi gravado" "$(ls "$SBP/separado")" "parsing.json"

echo "== 6. conferir: linha real sai 0; linha real+1 sai 1 e nomeia cmdPlantar =="
node -e 'const [f,l]=process.argv.slice(1); require("fs").writeFileSync(f, JSON.stringify([{intent:"plantar", confidence:"HIGH", functions:[{file:"scripts/ideias.cjs", name:"cmdPlantar", line:Number(l), notes:"ok"}], differences:"", recommendation:{action:"INVESTIGATE", survivor:"", reason:""}}]))' "$(winpath "$SBP/g-real.json")" "$LINHA_GREP"
node -e 'const [f,l]=process.argv.slice(1); require("fs").writeFileSync(f, JSON.stringify([{intent:"plantar", confidence:"HIGH", functions:[{file:"scripts/ideias.cjs", name:"cmdPlantar", line:Number(l), notes:"ok"}], differences:"", recommendation:{action:"INVESTIGATE", survivor:"", reason:""}}]))' "$(winpath "$SBP/g-errada.json")" "$((LINHA_GREP+1))"
CATREAL="$(winpath "$SBP/real.json")"
node "$CAT" conferir --catalogo "$CATREAL" --grupos "$(winpath "$SBP/g-real.json")" > "$SBP/c6a.txt" 2> "$SBP/e6a.txt"; EXIT=$?
saiu "grupo com a linha real sai 0" "$EXIT" 0
tem "grupo válido vai para stdout" "$(cat "$SBP/c6a.txt")" '"intent": "plantar"'
node "$CAT" conferir --catalogo "$CATREAL" --grupos "$(winpath "$SBP/g-errada.json")" > "$SBP/c6b.txt" 2> "$SBP/e6b.txt"; EXIT=$?
saiu "grupo com a linha real+1 sai 1" "$EXIT" 1
tem "stderr nomeia cmdPlantar na linha errada" "$(cat "$SBP/e6b.txt")" "scripts/ideias.cjs:$((LINHA_GREP+1)) cmdPlantar"
igual "stdout não traz o grupo inválido" "$(cat "$SBP/c6b.txt")" "[]"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
exit 0
