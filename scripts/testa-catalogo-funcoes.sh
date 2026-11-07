#!/bin/bash
# Bateria do scripts/catalogo-funcoes.cjs (D7, D9, D10 do design lgpd-e-duplicata).
#
# O QUE PRECISA PROVAR, pela SAIDA dos subcomandos (nenhum caso le o texto do fonte):
#   1. dart: função de topo e método de classe entram no catálogo;
#   2. gerados (*.g.dart, .dart_tool/) e testes ficam fora; --incluir-testes traz o teste;
#   3. repo real: cmdPlantar aponta para scripts/ideias.cjs na linha que o grep devolve;
#   4. maiores em ordem decrescente, e o primeiro número casa com wc -l;
#   5. separar grava só a categoria com 3 ou mais funções;
#   6. conferir: grupo com a linha real sai 0; com a linha real+1 sai 1 e nomeia cmdPlantar;
#   7. chamada solta não é definição: Dart sem tipo de retorno, JS with/setTimeout(function;
#   8. conferir recusa grupo de uma função só ou repetida, e rebaixa survivor fora do grupo;
#   9. separar junta categoria por caixa, conta entrada sem categoria e recusa pasta suja.
#  10. complexas: valores exatos de cognitiva e ciclomática (fila x ninho, sequências, ?, strings,
#      JSX, objeto, closure, Dart), python como não medido, última linha de aproximação;
#  11. complexas no repo real: ordem, começo igual ao do listar, contribuições dentro da função.
#  12. complexas (revisão 1): JSX com </tag> e />, seta com tipo de retorno, corpo de expressão,
#      estilo sem ;, .catch( de promessa, função comentada, else/switch/case/catch, mãe em Dart.
#  13. complexas (revisão 2): regex depois de =>, JSX de uma linha sem ;, ++, [ na linha de baixo,
#      if dentro de try/finally/do/switch, p?.catch(, seta dentro de genérico do tipo de retorno.
#  14. complexas: corpo de topo que atravessa outra função de topo sai como não medido.
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
  'src/solto.js=function envolve(o) {
  with (o) {
    x = 1;
  }
  setTimeout(function () {
    x = 2;
  }, 10);
}
' \n  'lib/b.dart=setState(() {});
print(1);
yield carregar(1);
' \n  'src/app.py=def ola():\n    return 1\n' \
  'src/foo.test.js=function teste() {}\n' \
  "src/big.js=$BIG"
FIXN="$(winpath "$FIX")"

echo "== 1. dart: função de topo e método de classe entram no catálogo =="
node "$CAT" listar --raiz "$FIXN" > "$SBP/c1.json" 2> "$SBP/e1.txt"; EXIT=$?
saiu "listar do fixture sai 0" "$EXIT" 0
T1="$(tuplas < "$SBP/c1.json")"
nao "main (ponto de entrada) fica fora do catálogo" "$T1" ":main:dart"
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
CATREAL="$(winpath "$SBP/real.json")"
# Segunda função real do mesmo arquivo, tirada do catálogo do caso 3: duplicata pede duas.
SEG="$(node -e 'let s="";process.stdin.on("data",(d)=>{s+=d}).on("end",()=>{const x=JSON.parse(s).find((e)=>e.arquivo==="scripts/ideias.cjs"&&e.nome!=="cmdPlantar");process.stdout.write(x?x.nome+" "+x.linha:"")})' < "$SBP/real.json")"
NOME2="${SEG% *}"; LINHA2="${SEG#* }"
# grupo <saida> <linha de cmdPlantar> <nome2> <linha2> <action> <survivor> <repetir cmdPlantar com barra trocada: sim|nao>
grupo() { node -e 'const [f,l,n2,l2,acao,surv,dup]=process.argv.slice(1); const fn=[{file:"scripts/ideias.cjs",name:"cmdPlantar",line:Number(l),notes:""}]; if(dup==="sim") fn.push({file:"scripts"+String.fromCharCode(92)+"ideias.cjs",name:"cmdPlantar",line:Number(l),notes:""}); if(n2) fn.push({file:"scripts/ideias.cjs",name:n2,line:Number(l2),notes:""}); require("fs").writeFileSync(f, JSON.stringify([{intent:"plantar",confidence:"HIGH",functions:fn,differences:"",recommendation:{action:acao,survivor:surv,reason:""}}]))' "$@"; }
grupo "$(winpath "$SBP/g-real.json")" "$LINHA_GREP" "$NOME2" "$LINHA2" INVESTIGATE "" nao
grupo "$(winpath "$SBP/g-errada.json")" "$((LINHA_GREP+1))" "$NOME2" "$LINHA2" INVESTIGATE "" nao
node "$CAT" conferir --catalogo "$CATREAL" --grupos "$(winpath "$SBP/g-real.json")" > "$SBP/c6a.txt" 2> "$SBP/e6a.txt"; EXIT=$?
saiu "grupo com a linha real sai 0" "$EXIT" 0
tem "grupo válido vai para stdout" "$(cat "$SBP/c6a.txt")" '"intent": "plantar"'
node "$CAT" conferir --catalogo "$CATREAL" --grupos "$(winpath "$SBP/g-errada.json")" > "$SBP/c6b.txt" 2> "$SBP/e6b.txt"; EXIT=$?
saiu "grupo com a linha real+1 sai 1" "$EXIT" 1
tem "stderr nomeia cmdPlantar na linha errada" "$(cat "$SBP/e6b.txt")" "scripts/ideias.cjs:$((LINHA_GREP+1)) cmdPlantar"
igual "stdout não traz o grupo inválido" "$(cat "$SBP/c6b.txt")" "[]"

echo "== 7. chamada solta não é definição =="
nao "setState( na coluna zero do Dart não entra" "$T1" ":setState:"
nao "print( na coluna zero do Dart não entra" "$T1" ":print:"
nao "nenhuma linha de lib/b.dart (setState, print, yield) vira definição" "$T1" "lib/b.dart:"
linha "a função que contém o with entra" "$T1" "src/solto.js:1:envolve:js"
nao "with (o) { não vira método" "$T1" ":with:js"
nao "setTimeout(function () { não vira método" "$T1" ":setTimeout:js"

echo "== 8. conferir recusa grupo de uma função só ou repetida; rebaixa survivor fora do grupo =="
grupo "$(winpath "$SBP/g-um.json")" "$LINHA_GREP" "" "" CONSOLIDATE cmdPlantar nao
node "$CAT" conferir --catalogo "$CATREAL" --grupos "$(winpath "$SBP/g-um.json")" > "$SBP/c8a.txt" 2> "$SBP/e8a.txt"; EXIT=$?
saiu "grupo de uma função só sai 1" "$EXIT" 1
tem "stderr diz que duplicata pede 2 ou mais" "$(cat "$SBP/e8a.txt")" "duplicata pede 2 ou mais"
grupo "$(winpath "$SBP/g-dup.json")" "$LINHA_GREP" "" "" CONSOLIDATE cmdPlantar sim
node "$CAT" conferir --catalogo "$CATREAL" --grupos "$(winpath "$SBP/g-dup.json")" > "$SBP/c8b.txt" 2> "$SBP/e8b.txt"; EXIT=$?
saiu "a mesma função com barra trocada sai 1" "$EXIT" 1
grupo "$(winpath "$SBP/g-surv.json")" "$LINHA_GREP" "$NOME2" "$LINHA2" CONSOLIDATE outraCoisa nao
node "$CAT" conferir --catalogo "$CATREAL" --grupos "$(winpath "$SBP/g-surv.json")" > "$SBP/c8c.txt" 2> "$SBP/e8c.txt"; EXIT=$?
saiu "duas funções reais com survivor fora do grupo sai 0" "$EXIT" 0
tem "survivor fora do grupo vira INVESTIGATE" "$(cat "$SBP/c8c.txt")" '"action": "INVESTIGATE"'
tem "stderr avisa o rebaixamento" "$(cat "$SBP/e8c.txt")" "rebaixado para INVESTIGATE"
grupo "$(winpath "$SBP/g-ok.json")" "$LINHA_GREP" "$NOME2" "$LINHA2" CONSOLIDATE cmdPlantar nao
node "$CAT" conferir --catalogo "$CATREAL" --grupos "$(winpath "$SBP/g-ok.json")" > "$SBP/c8d.txt" 2> "$SBP/e8d.txt"; EXIT=$?
saiu "survivor do grupo sai 0" "$EXIT" 0
tem "survivor do grupo mantém CONSOLIDATE" "$(cat "$SBP/c8d.txt")" '"action": "CONSOLIDATE"'

echo "== 9. separar: caixa, entrada sem categoria e pasta suja =="
node -e 'const f=process.argv[1]; const e=(n,c)=>({arquivo:"a.js",linha:1,nome:n,category:c}); require("fs").writeFileSync(f, JSON.stringify([e("a1","Auth"),e("a2","auth"),e("a3","AUTH"),{arquivo:"a.js",linha:2,nome:"semcat"}]))' "$(winpath "$SBP/caixa.json")"
node "$CAT" separar --catalogo "$(winpath "$SBP/caixa.json")" --saida "$(winpath "$SBP/sep-caixa")" --minimo 3 > "$SBP/s9.txt" 2> "$SBP/e9.txt"; EXIT=$?
saiu "separar com caixas misturadas sai 0" "$EXIT" 0
igual "Auth, auth e AUTH viram uma categoria só" "$(cat "$SBP/s9.txt")" "categorias gravadas: 1"
igual "o arquivo leva as três funções" "$(node -e 'console.log(require(process.argv[1]).length)' "$(winpath "$SBP/sep-caixa/Auth.json")")" "3"
tem "stderr conta a entrada sem categoria" "$(cat "$SBP/e9.txt")" "sem categoria: 1"
node "$CAT" separar --catalogo "$(winpath "$SBP/caixa.json")" --saida "$(winpath "$SBP/sep-caixa")" --minimo 3 > "$SBP/s9b.txt" 2> "$SBP/e9b.txt"; EXIT=$?
saiu "separar na mesma pasta de novo sai 1" "$EXIT" 1
tem "stderr diz que a pasta já tem .json" "$(cat "$SBP/e9b.txt")" "já tem 1 .json"
node -e 'const f=process.argv[1]; const e=(n,c)=>({arquivo:"a.js",linha:1,nome:n,category:c}); require("fs").writeFileSync(f, JSON.stringify([e("x1","aaa"),e("x2","aaa"),e("x3","aaa"),e("p1","parse/io"),e("p2","parse/io"),e("p3","parse/io"),e("q1","parse io"),e("q2","parse io"),e("q3","parse io")]))' "$(winpath "$SBP/colide.json")"
node "$CAT" separar --catalogo "$(winpath "$SBP/colide.json")" --saida "$(winpath "$SBP/sep-colide")" --minimo 3 > "$SBP/s9c.txt" 2> "$SBP/e9c.txt"; EXIT=$?
saiu "duas categorias com o mesmo nome de arquivo saem 1" "$EXIT" 1
tem "stderr nomeia a colisão" "$(cat "$SBP/e9c.txt")" "viram o mesmo arquivo parse-io.json"
igual "a colisão não deixa arquivo gravado" "$(ls "$SBP/sep-colide" 2>/dev/null | wc -l | tr -d ' ')" "0"

echo "== 10. complexas: aninhamento pesa mais que ramos em fila =="
# Fixture escrita por node: aspas, crases e barras ficam fora do quoting do bash.
FX10="$SBP/cx"
mkdir -p "$FX10"
node -e '
const fs = require("fs"), p = require("path"), d = process.argv[1];
const Q = String.fromCharCode(39), B = String.fromCharCode(92), C = String.fromCharCode(96);
const w = (f, s) => fs.writeFileSync(p.join(d, f), s);
w("a.js", [
  "function fila(a, b) {", "  if (a) {", "    x();", "  }", "  if (b) {", "    y();", "  }", "}",
  "function ninho(a, b) {", "  if (a) {", "    if (b) {", "      y();", "    }", "  }", "}",
  "function seqIgual(a, b, c) { return a && b && c; }",
  "function seqTroca(a, b, c) { return a && b || c; }",
  "function textos() {",
  "  const s = " + Q + "if (x)" + Q + ";",
  "  // if (y)",
  "  /* if (z) */",
  "  const t = " + C + "if (w) ${ {a: 1}.a }" + C + ";",
  "  const r = /if " + B + "(x" + B + ")/;",
  "  return 1;", "}",
  "function objeto(a) {", "  const o = { b: { c: 1 } };", "  if (a) {", "    g();", "  }", "}",
  "function mae(xs) {", "  xs.forEach((x) => {", "    if (x) {", "      g();", "    }", "  });", "}",
  ""].join("\n"));
w("b.ts", [
  "function nulos(x?: number) {", "  const y = a?.b;", "  const z = a ?? b;", "  return c ? 1 : 2;", "}", ""].join("\n"));
w("c.tsx", [
  "function Aviso() {", "  return <p>Don" + Q + "t</p>;", "}",
  "function depoisDoJsx(a) {", "  if (a) {", "    return 1;", "  }", "}", ""].join("\n"));
w("d.dart", [
  "void dartF(String? s) {",
  "  final a = " + Q + Q + Q, "if (x) {", Q + Q + Q + ";",
  "  final b = r" + Q + "if (y)" + Q + ";",
  "  final c = " + Q + "${s ?? \"if (z)\"}" + Q + ";",
  "  if (s != null) {", "    for (final x in xs) {", "      print(x);", "    }", "  }", "}",
  "class A {", "  int dartMetodo(int v) {", "    return v > 0 ? 1 : 2;", "  }", "}", ""].join("\n"));
w("e.py", "def solto():\n    if x:\n        pass\n");
' "$(winpath "$FX10")"
( cd "$FX10" && git init -q && git config user.email t@t && git config user.name Test && git config core.autocrlf false && git add -A && git commit -q -m base )
SAI10="$(node "$CAT" complexas --raiz "$(winpath "$FX10")" --top 50)"; EXIT=$?
saiu "complexas na fixture sai 0" "$EXIT" 0
linha "dois if em fila dão cognitiva 2" "$SAI10" "2 cognitiva  3 ciclomática  a.js:L1 fila"
linha "o mesmo par aninhado dá cognitiva 3" "$SAI10" "3 cognitiva  3 ciclomática  a.js:L9 ninho"
linha "a && b && c conta uma vez" "$SAI10" "1 cognitiva  3 ciclomática  a.js:L16 seqIgual"
linha "a && b || c conta duas" "$SAI10" "2 cognitiva  3 ciclomática  a.js:L17 seqTroca"
linha "if em string, comentário, template e regex não conta" "$SAI10" "0 cognitiva  1 ciclomática  a.js:L18 textos"
linha "objeto literal não aprofunda" "$SAI10" "1 cognitiva  2 ciclomática  a.js:L26 objeto"
linha "closure aprofunda e soma na mãe" "$SAI10" "2 cognitiva  2 ciclomática  a.js:L32 mae"
linha "x?: T, ?. e ?? não contam; c ? 1 : 2 conta" "$SAI10" "1 cognitiva  2 ciclomática  b.ts:L1 nulos"
linha "apóstrofo de texto JSX não cega a função seguinte" "$SAI10" "1 cognitiva  2 ciclomática  c.tsx:L4 depoisDoJsx"
linha "Dart: string tripla, crua e interpolação não contam; for dentro de if pesa 2" "$SAI10" "3 cognitiva  3 ciclomática  d.dart:L1 dartF"
linha "Dart: método de classe medido, ternário conta" "$SAI10" "1 cognitiva  2 ciclomática  d.dart:L14 dartMetodo"
tem "contribuição traz linha e profundidade" "$SAI10" "    +2 L11 if (profundidade 1)"
linha "python sai como não medido" "$SAI10" "não medido: 1 função(ões) py — linguagem sem chaves"
nao "o if da closure não vira função à parte" "$SAI10" "a.js:L33"
igual "a última linha diz que é aproximação" "$(tail -1 <<<"$SAI10")" "medida aproximada (leitura de texto, sem parser): confira no código antes de concluir"

echo "== 12. complexas: JSX, seta, sem ponto e vírgula, controle, mãe e comentário (revisão 1) =="
FX12="$SBP/cx12"
mkdir -p "$FX12"
node -e '
const fs = require("fs"), p = require("path"), d = process.argv[1];
const Q = String.fromCharCode(39), C = String.fromCharCode(96);
const w = (f, s) => fs.writeFileSync(p.join(d, f), s);
w("j.tsx", [
  "export function SoFechamento({ xs }) {",
  "  return <ul>{xs.map((x) => <li key={x}>{x}</li>)}</ul>;",
  "}",
  "export function Silencioso({ a, xs }) {",
  "  if (a) {",
  "    const x = <div><b>x</b>{a && <i>y</i>}</div>;",
  "    if (xs) {",
  "      return x;",
  "    }",
  "  }",
  "  return null;",
  "}",
  "function SoPelaChave(xs) {",
  "  if (xs) {",
  "    return foo({ k: xs.map((x) => <Item id={x} />) });",
  "  }",
  "}",
  ""].join("\n"));
w("s.ts", [
  "const tipado = (a: number): { x: number } => {",
  "  if (a) {",
  "    if (a > 1) {",
  "      return { x: 1 };",
  "    }",
  "  }",
  "  return { x: 2 };",
  "};",
  "const estilo = (t) => t.dark ? { c: 1 } : { c: 2 };",
  "const outro = (a, b, c) => a && b || c ? { d: 1 } : null;",
  "const dobra = (a) => a ? 1 : 2",
  "function g2(x) {",
  "  if (x) {",
  "    if (x > 1) {",
  "      y()",
  "    }",
  "  }",
  "}",
  "function promessa(u) {",
  "  return fetch(u).then((r) => r).catch((e) => e);",
  "}",
  "/*",
  "function velha(a) { if (a) { return 1; } }",
  "*/",
  "function real(b) {",
  "  if (b) {",
  "    return 1;",
  "  }",
  "}",
  "function noObjeto(c) {",
  "  const o = { b: { e: c ? 1 : 2 } };",
  "  return o;",
  "}",
  "function regexComIf(s) {",
  "  return /if (x)/.test(s);",
  "}",
  "function templateAninhado(b) {",
  "  return " + C + "a ${ " + C + "if (b)" + C + " } c" + C + ";",
  "}",
  "function senao(a, b) {",
  "  if (a) {",
  "    return 1;",
  "  } else if (b) {",
  "    return 2;",
  "  } else {",
  "    return 3;",
  "  }",
  "}",
  "function escolha(x) {",
  "  switch (x) {",
  "    case 1: return 1;",
  "    case 2: return 2;",
  "    default: return 0;",
  "  }",
  "}",
  "function lacos(a) {",
  "  while (a) {",
  "    try {",
  "      g();",
  "    } catch (e) {",
  "      h();",
  "    }",
  "  }",
  "}",
  ""].join("\n"));
w("m.dart", [
  "void externa(bool a) {",
  "  void interna() {",
  "    if (a) {",
  "      print(1);",
  "    }",
  "  }",
  "  final s = " + Q + "${a ? " + Q + "if (z)" + Q + " : " + Q + "n" + Q + "}" + Q + ";",
  "}",
  ""].join("\n"));
w("k.py", "class Coisa:\n    pass\n\ndef solta():\n    pass\n");
' "$(winpath "$FX12")"
( cd "$FX12" && git init -q && git config user.email t@t && git config user.name Test && git config core.autocrlf false && git add -A && git commit -q -m base )
SAI12="$(node "$CAT" complexas --raiz "$(winpath "$FX12")" --top 50)"; EXIT=$?
saiu "complexas na fixture 12 sai 0" "$EXIT" 0
linha "JSX: </li>) não vira regex e o corpo fecha" "$SAI12" "0 cognitiva  1 ciclomática  j.tsx:L1 SoFechamento"
linha "JSX: </b> e </i> não engolem a chave" "$SAI12" "4 cognitiva  4 ciclomática  j.tsx:L4 Silencioso"
linha "JSX: /> depois de } não vira regex" "$SAI12" "1 cognitiva  2 ciclomática  j.tsx:L13 SoPelaChave"
nao "nenhuma função de JSX fica sem fechar" "$SAI12" "corpo não fechou"
linha "seta com tipo de retorno literal: o corpo é o bloco depois da seta" "$SAI12" "3 cognitiva  3 ciclomática  s.ts:L1 tipado"
linha "corpo de expressão com objeto: o ternário conta" "$SAI12" "1 cognitiva  2 ciclomática  s.ts:L9 estilo"
linha "corpo de expressão: && || e ternário contam" "$SAI12" "3 cognitiva  4 ciclomática  s.ts:L10 outro"
linha "sem ponto e vírgula: a seta para na quebra de linha" "$SAI12" "1 cognitiva  2 ciclomática  s.ts:L11 dobra"
linha "sem ponto e vírgula: a função seguinte é medida" "$SAI12" "3 cognitiva  3 ciclomática  s.ts:L12 g2"
linha ".catch( de promessa não conta" "$SAI12" "0 cognitiva  1 ciclomática  s.ts:L19 promessa"
nao "função dentro de comentário não é medida" "$SAI12" "velha"
linha "a função depois do comentário é medida" "$SAI12" "1 cognitiva  2 ciclomática  s.ts:L25 real"
linha "ternário dentro de objeto fica na profundidade 0" "$SAI12" "1 cognitiva  2 ciclomática  s.ts:L30 noObjeto"
linha "if dentro de regex não conta" "$SAI12" "0 cognitiva  1 ciclomática  s.ts:L34 regexComIf"
linha "if dentro de template aninhado não conta" "$SAI12" "0 cognitiva  1 ciclomática  s.ts:L37 templateAninhado"
linha "else if e else somam 1 cada, sem profundidade" "$SAI12" "3 cognitiva  3 ciclomática  s.ts:L40 senao"
linha "switch soma 1; cada case soma na ciclomática" "$SAI12" "1 cognitiva  3 ciclomática  s.ts:L49 escolha"
linha "catch dentro de while pesa 2" "$SAI12" "3 cognitiva  3 ciclomática  s.ts:L56 lacos"
linha "Dart: função interna soma na mãe; aspas dentro de \${} não contam" "$SAI12" "3 cognitiva  3 ciclomática  m.dart:L1 externa"
nao "Dart: a função interna não sai à parte" "$SAI12" "m.dart:L2"
linha "python: classe não conta como função" "$SAI12" "não medido: 1 função(ões) py — linguagem sem chaves"

echo "== 13. complexas: regex depois de =>, JSX sem ;, ++, [ na linha de baixo, controle aninhado (revisão 2) =="
FX13="$SBP/cx13"
mkdir -p "$FX13"
node -e '
const fs = require("fs"), p = require("path"), d = process.argv[1];
const C = String.fromCharCode(96);
const w = (f, s) => fs.writeFileSync(p.join(d, f), s);
const g = (n) => ["function " + n + "(x) {", "  if (x) {", "    if (x > 1) {", "      return 1", "    }", "  }", "  return 0", "}"];
w("r.js", [
  "function f(ts) {",
  "  if (ts.some((x) => /[$" + C + "()@]/.test(x))) {",
  "    return 1;",
  "  }",
  "  return 0;",
  "}",
  ...g("gA"),
  "const ehChave = (s) => /[{]/.test(s);",
  ...g("gB"),
  "const inc = () => counter++",
  ...g("gD"),
  "function fArr(a) {",
  "  if (a) {",
  "    h()",
  "  }",
  "}",
  "[1, 2].forEach(h)",
  ...g("gE"),
  "function opcional(p) {",
  "  return p?.catch((e) => e);",
  "}",
  "function ninhos(a, b) {",
  "  try {", "    if (a) {", "      b()", "    }",
  "  } finally {", "    if (b) {", "      a()", "    }", "  }",
  "  do {", "    if (a) {", "      b()", "    }", "  } while (b)",
  "  switch (a) {", "    case 1:", "      if (b) {", "        return 1", "      }", "  }",
  "}",
  ""].join("\n"));
w("t.tsx", [
  "const A = () => <div>hi</div>",
  ...g("gC"),
  "const comGenerico = async (a): Promise<() => void> => {",
  "  if (a) {",
  "    return () => {}",
  "  }",
  "  return () => {}",
  "};",
  ""].join("\n"));
' "$(winpath "$FX13")"
( cd "$FX13" && git init -q && git config user.email t@t && git config user.name Test && git config core.autocrlf false && git add -A && git commit -q -m base )
SAI13="$(node "$CAT" complexas --raiz "$(winpath "$FX13")" --top 50)"; EXIT=$?
saiu "complexas na fixture 13 sai 0" "$EXIT" 0
linha "regex com crase depois de => não abre template" "$SAI13" "1 cognitiva  2 ciclomática  r.js:L1 f"
linha "a função depois da regex com crase é medida" "$SAI13" "3 cognitiva  3 ciclomática  r.js:L7 gA"
linha "regex com { depois de => não abre chave" "$SAI13" "0 cognitiva  1 ciclomática  r.js:L15 ehChave"
linha "a função depois da regex com { é medida" "$SAI13" "3 cognitiva  3 ciclomática  r.js:L16 gB"
linha "counter++ sem ; termina a seta" "$SAI13" "0 cognitiva  1 ciclomática  r.js:L24 inc"
linha "a função depois de counter++ é medida" "$SAI13" "3 cognitiva  3 ciclomática  r.js:L25 gD"
linha "[ na linha de baixo não emenda na chave que fechou" "$SAI13" "1 cognitiva  2 ciclomática  r.js:L33 fArr"
linha "a função depois do [ é medida" "$SAI13" "3 cognitiva  3 ciclomática  r.js:L39 gE"
linha "p?.catch( não conta" "$SAI13" "0 cognitiva  1 ciclomática  r.js:L47 opcional"
linha "if dentro de try, finally, do e switch pesa 2 cada" "$SAI13" "10 cognitiva  7 ciclomática  r.js:L50 ninhos"
linha "JSX de uma linha sem ; termina a seta" "$SAI13" "0 cognitiva  1 ciclomática  t.tsx:L1 A"
linha "a função depois do JSX sem ; é medida" "$SAI13" "3 cognitiva  3 ciclomática  t.tsx:L2 gC"
linha "seta dentro de genérico do tipo de retorno não é a seta do corpo" "$SAI13" "1 cognitiva  2 ciclomática  t.tsx:L10 comGenerico"
nao "nada da fixture 13 fica sem fechar" "$SAI13" "corpo não fechou"

echo "== 14. complexas: corpo que atravessa outra função de topo vira lacuna declarada =="
FX14="$SBP/cx14"
mkdir -p "$FX14"
# Regex depois de `<` é lida como divisão (limite conhecido: `<` fica fora do ANTES_DE_REGEX por
# causa do JSX): a `{` dela abre bloco e a `}` da regex de hT fecha. Sem a trava, fT engole gT
# calada; com ela, fT sai como não medido. Até a 2.5.0 este caso provocava a leitura errada com
# regex depois do `)` do if, que o D6 do design branch-datada-e-componentes consertou.
node -e '
const fs = require("fs"), p = require("path"), d = process.argv[1];
fs.writeFileSync(p.join(d, "s.js"), [
  "function fT(s) {", "  return 0 < /[{]/.exec(s).index", "}",
  "function gT(x) {", "  if (x) {", "    if (x > 1) {", "      return 1", "    }", "  }", "  return 0", "}",
  "function hT(s) {", "  return 0 < /[}]/.exec(s).index", "}", ""].join("\n"));
' "$(winpath "$FX14")"
( cd "$FX14" && git init -q && git config user.email t@t && git config user.name Test && git config core.autocrlf false && git add -A && git commit -q -m base )
SAI14="$(node "$CAT" complexas --raiz "$(winpath "$FX14")" --top 50)"; EXIT=$?
saiu "complexas na fixture 14 sai 0" "$EXIT" 0
linha "a mãe que atravessou gT sai como não medido" "$SAI14" "não medido: s.js:L1 fT — corpo passou por gT (L4): leitura errada"
linha "a função atravessada é medida" "$SAI14" "3 cognitiva  3 ciclomática  s.js:L4 gT"
nao "a mãe não sai com nota" "$SAI14" "ciclomática  s.js:L1 fT"

echo "== 15. complexas: componente React tipado e envolvido (#648) =="
# Até a 2.5.0 a regra `topo` só via `const x = (` e `const x = async`: os quatro primeiros ficavam
# fora do catálogo, sem medida e sem "não medido". Cada um tem um if dentro de outro (3 e 3).
FX15="$SBP/cx15"
mkdir -p "$FX15"
node -e '
const fs = require("fs"), p = require("path"), d = process.argv[1];
const corpo = ["  if (a) {", "    if (a > 1) {", "      return 1", "    }", "  }", "  return 0"];
fs.writeFileSync(p.join(d, "c.tsx"), [
  "const Foo: React.FC<Props> = ({ a }) => {", ...corpo, "}",
  "export const Bar = React.memo(function Bar(a) {", ...corpo, "})",
  "export const Baz = forwardRef<HTMLDivElement, P>((a, ref) => {", ...corpo, "})",
  "const f: (a: number) => void = (a) => {", ...corpo, "}",
  "const total = soma(a, b)",
  ""].join("\n"));
' "$(winpath "$FX15")"
( cd "$FX15" && git init -q && git config user.email t@t && git config user.name Test && git config core.autocrlf false && git add -A && git commit -q -m base )
SAI15="$(node "$CAT" complexas --raiz "$(winpath "$FX15")" --top 50)"; EXIT=$?
saiu "complexas na fixture 15 sai 0" "$EXIT" 0
linha "React.FC tipado é medido" "$SAI15" "3 cognitiva  3 ciclomática  c.tsx:L1 Foo"
linha "React.memo(function ...) é medido pelo corpo de dentro" "$SAI15" "3 cognitiva  3 ciclomática  c.tsx:L9 Bar"
linha "forwardRef<T>((...) => ...) é medido pelo corpo de dentro" "$SAI15" "3 cognitiva  3 ciclomática  c.tsx:L17 Baz"
linha "seta com tipo de função na anotação é medida" "$SAI15" "3 cognitiva  3 ciclomática  c.tsx:L25 f"
nao "chamada solta não entra" "$SAI15" "total"
nao "nada da fixture 15 vira lacuna" "$SAI15" "não medido: c.tsx"

echo "== 16. complexas: limites da leitura (#648) =="
FX16="$SBP/cx16"
mkdir -p "$FX16"
node -e '
const fs = require("fs"), p = require("path"), d = process.argv[1];
const Q = String.fromCharCode(39);
const w = (f, s) => fs.writeFileSync(p.join(d, f), s);
const g = (n) => ["function " + n + "(x) {", "  if (x) {", "    if (x > 1) {", "      return 1", "    }", "  }", "  return 0", "}"];
// (a) método cujo } fica escondido pelo apóstrofo do texto JSX atravessa o método vizinho
w("m.tsx", [
  "class Lista {",
  "  render(a) { return <p>Don" + Q + "t</p> }",
  "  outro(x) {",
  "    if (x) {",
  "      return 1",
  "    }",
  "  }",
  "}",
  ""].join("\n"));
w("r.js", [
  // (b) regex depois do ) da condição
  "function rx(s) {", "  if (s) /[}]/.test(s)", "  if (s) {", "    return 1", "  }", "  return 0", "}",
  ...g("gR"),
  // (c) } antes de / em texto JSX
  "function Pag({ page, pages, a }) {", "  return <span>{page}/{pages}{a ? 1 : 2}</span>", "}",
  // (d) if sem chave e sem ;, objeto na instrução seguinte
  "function semChave(x, y) {", "  if (x) return", "  const o = { a: y ? 1 : 2 }", "  return o", "}",
  // (e) const com parênteses que não é função
  "const total = (a + b) * c",
  ...g("gS"),
  ""].join("\n"));
// (f) sobrecarga TS sem ;  (g) } seguida de {, |, & e [ no tipo de retorno
w("t.ts", [
  "function sob(a: string): string",
  "function sob(a: number): number",
  "function sob(a: any): any {", "  if (a) {", "    return a", "  }", "  return 0", "}",
  "function t1(x): { a: number } {", "  if (x) { return 1 }", "  return 2", "}",
  "function t2(x): { a: 1 } | null {", "  if (x) { return 1 }", "  return 2", "}",
  "function t3(x): { a: 1 } & B {", "  if (x) { return 1 }", "  return 2", "}",
  "function t4(x): { a: 1 }[] {", "  if (x) { return 1 }", "  return 2", "}",
  ""].join("\n"));
// IIFE continua medida: é lógica de verdade, só não tem nome de função
w("i.js", ["const RAIZ = (() => {", "  if (x) {", "    return 1", "  }", "  return 0", "})();", ""].join("\n"));
// revisão 1: apelido memo(Inner), função chamada memo, função depois de || e memo(x => ...)
w("w.tsx", [
  "const Wrapped = memo(Inner);",
  "describe(" + Q + "W" + Q + ", () => { if (x) { if (y) { g() } } });",
  "export function memo(fn) {", "  if (fn) {", "    if (fn.a) {", "      return 1", "    }", "  }", "}",
  "const noop = (opts && opts.noop) || function (a) {", "  if (a) {", "    return 1", "  }", "}",
  "const Seta = memo(props => {", "  if (props) {", "    return 1", "  }", "})",
  ""].join("\n"));
// troca de mãe: f1 atravessa k e f3; k não é função, e f3 tem de ser medida sem tirar f0
w("x.js", [
  "function f0(x) { if (x) { return 1 } return 0 }",
  "function f1(s) {", "  return 0 < /[{]/.exec(s).index", "}",
  "const k = (a + b) * c",
  "function f3(x) {", "  if (x) {", "    return 1", "  }", "  return 0", "}",
  "function f4(s) {", "  return 0 < /[}]/.exec(s).index", "}",
  ""].join("\n"));
' "$(winpath "$FX16")"
( cd "$FX16" && git init -q && git config user.email t@t && git config user.name Test && git config core.autocrlf false && git add -A && git commit -q -m base )
SAI16="$(node "$CAT" complexas --raiz "$(winpath "$FX16")" --top 50)"; EXIT=$?
saiu "complexas na fixture 16 sai 0" "$EXIT" 0
linha "(a) método que atravessa o vizinho sai como não medido" "$SAI16" "não medido: m.tsx:L2 render — corpo passou por outro (L3): leitura errada"
linha "(a) o método vizinho é medido" "$SAI16" "1 cognitiva  2 ciclomática  m.tsx:L3 outro"
linha "(b) regex depois do ) do if não fecha o corpo cedo" "$SAI16" "2 cognitiva  3 ciclomática  r.js:L1 rx"
linha "(b) a função seguinte é medida certa" "$SAI16" "3 cognitiva  3 ciclomática  r.js:L8 gR"
linha "(c) {page}/{pages} não esconde o ternário" "$SAI16" "1 cognitiva  2 ciclomática  r.js:L16 Pag"
linha "(d) if sem chave não aprofunda o objeto seguinte" "$SAI16" "2 cognitiva  3 ciclomática  r.js:L19 semChave"
nao "(e) const com parênteses que não é função não sai" "$SAI16" "r.js:L24"
linha "(e) IIFE continua medida" "$SAI16" "2 cognitiva  2 ciclomática  i.js:L1 RAIZ"
nao "apelido memo(Inner) não vira função nem lacuna" "$SAI16" "w.tsx:L1 "
linha "função chamada memo é medida pelos próprios parâmetros" "$SAI16" "3 cognitiva  3 ciclomática  w.tsx:L3 memo"
linha "função depois de || continua medida" "$SAI16" "1 cognitiva  2 ciclomática  w.tsx:L10 noop"
linha "memo(x => ...) sem parênteses no parâmetro é medido" "$SAI16" "1 cognitiva  2 ciclomática  w.tsx:L15 Seta"
linha "(e) a função depois dele é medida" "$SAI16" "3 cognitiva  3 ciclomática  r.js:L25 gS"
nao "(f) sobrecarga sem ; não vira leitura errada" "$SAI16" "não medido: t.ts"
linha "(f) a implementação depois da sobrecarga sem ; é medida" "$SAI16" "1 cognitiva  2 ciclomática  t.ts:L3 sob"
linha "(g) } seguida de { no tipo de retorno" "$SAI16" "1 cognitiva  2 ciclomática  t.ts:L9 t1"
linha "(g) } seguida de |" "$SAI16" "1 cognitiva  2 ciclomática  t.ts:L13 t2"
linha "(g) } seguida de &" "$SAI16" "1 cognitiva  2 ciclomática  t.ts:L17 t3"
linha "(g) } seguida de [" "$SAI16" "1 cognitiva  2 ciclomática  t.ts:L21 t4"
linha "troca de mãe: f1 sai como não medido" "$SAI16" "não medido: x.js:L2 f1 — corpo passou por k (L5): leitura errada"
linha "troca de mãe: f0 continua medida" "$SAI16" "1 cognitiva  2 ciclomática  x.js:L1 f0"
linha "troca de mãe: f3 é medida" "$SAI16" "1 cognitiva  2 ciclomática  x.js:L6 f3"
igual "troca de mãe: f1 aparece uma vez só como lacuna" "$(grep -c "x.js:L2 f1" <<<"$SAI16")" "1"
nao "nenhuma leitura errada fora de render e f1" "$(grep -v "L2 render\|L2 f1" <<<"$SAI16")" "leitura errada"

echo "== 11. complexas no repo real: ordem, linha de começo e contribuições dentro da função =="
node "$CAT" complexas --raiz "$RAIZN" --top 5 > "$SBP/cx-real.txt"; EXIT=$?
saiu "complexas no repo real sai 0" "$EXIT" 0
node "$CAT" listar --raiz "$RAIZN" --contexto 0 > "$SBP/cx-cat.json"
CONF11="$(node -e '
const fs = require("fs");
const linhas = fs.readFileSync(process.argv[1], "utf8").split("\n");
const cat = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const blocos = []; let erro = "";
for (const l of linhas) {
  const m = /^(\d+) cognitiva  (\d+) ciclomática  (.+):L(\d+) (\S+)$/.exec(l);
  if (m) { blocos.push({ c: +m[1], arq: m[3], linha: +m[4], nome: m[5], contrib: [] }); continue; }
  const k = /^    \+(\d+) L(\d+) /.exec(l);
  if (k && blocos.length) blocos[blocos.length - 1].contrib.push(+k[2]);
}
if (blocos.length !== 5) erro += "blocos=" + blocos.length + " ";
for (let i = 1; i < blocos.length; i++) if (blocos[i].c > blocos[i - 1].c) erro += "ordem ";
for (const b of blocos) {
  if (!cat.some((e) => e.arquivo === b.arq && e.linha === b.linha && e.nome === b.nome)) erro += "fora do catalogo:" + b.arq + ":" + b.linha + " ";
  if (b.contrib.some((x) => x < b.linha)) erro += "contribuicao antes da funcao:" + b.nome + " ";
}
process.stdout.write(erro || "ok");
' "$(winpath "$SBP/cx-real.txt")" "$(winpath "$SBP/cx-cat.json")")"
igual "5 blocos em ordem, cada um no começo que o listar dá, contribuições depois do começo" "$CONF11" "ok"

echo
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
exit 0
