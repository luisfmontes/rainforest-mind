#!/bin/bash
# Bateria de hooks/lib/caminho-real.cjs e dos dois hooks que a usam (D6 do design 2026-10-24-apoio-ao-dev-lote-5).
#
# O QUE PRECISA PROVAR, pelo efeito (nunca pelo texto do fonte):
#   1. a lib resolve arquivo existente (caminho real), arquivo novo (pasta real + nome) e
#      pasta inexistente (o proprio p);
#   2. aviso-duplicata com cwd em nome curto 8.3 nao acusa o proprio arquivo (so win32);
#   3. aviso-fluxo com cwd em nome curto 8.3 segue isento para arquivo sob docs/, e o mesmo
#      cwd com arquivo fora de docs/ ainda bloqueia (controle: o trilho esta de fato ligado);
#   4. junction rastreada no repo: editar pelo caminho da junction nao acusa o proprio arquivo
#      (so win32; pulado se o git nao lista o arquivo pelo caminho da junction).
# Nome curto 8.3 sai de cygpath -d; se o volume nao gera 8.3, o caso e pulado e conta como ok.
#
# Repos e payloads sao montados aqui dentro: payload com node, nunca com printf.
# O config real nunca e lido (RFM_ROOT neutro).
#
# Uso: bash hooks/testa-caminho-real.sh

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAIZ_M="$(cygpath -m "$RAIZ" 2>/dev/null || printf '%s' "$RAIZ")"
LIB="$RAIZ_M/hooks/lib/caminho-real.cjs"
HOOK_DUP="$RAIZ_M/hooks/aviso-duplicata.cjs"
HOOK_FLUXO="$RAIZ_M/hooks/aviso-fluxo.cjs"
for f in "$LIB" "$HOOK_DUP" "$HOOK_FLUXO"; do [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }; done

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WIN=1 ;; *) WIN=0 ;; esac

export MSYS_NO_PATHCONV=1
unset RAINFOREST_GATE_OFF
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
export RFM_ROOT="$SBP/dados-neutros"; mkdir -p "$RFM_ROOT"

ok=0; falhou=0
saiu()  { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (exit $2, esperava $3)"; fi; }
tem()   { if grep -qF -- "$3" <<<"$2"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3')"; echo "$2" | sed 's/^/         /'; fi; }
vazio() { if [ -z "$2" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava saida vazia)"; echo "$2" | sed 's/^/         /'; fi; }
pulou() { ok=$((ok+1)); echo "  pulado: $1"; }

# Repo git de teste com os arquivos dados (caminho relativo => conteudo, \n literal vira quebra).
montar_repo() {
  local dir="$1"; shift
  mkdir -p "$dir"
  ( cd "$dir" && git init -q && git config user.email t@t && git config user.name Test && git config core.autocrlf false ) || return 1
  local par caminho conteudo
  for par in "$@"; do
    caminho="${par%%=*}"; conteudo="${par#*=}"
    mkdir -p "$dir/$(dirname "$caminho")"
    node -e 'require("fs").writeFileSync(process.argv[1], process.argv[2].replace(/\\n/g, "\n"))' "$(cygpath -m "$dir/$caminho")" "$conteudo"
    ( cd "$dir" && git add -- "$caminho" )
  done
  ( cd "$dir" && git commit -q -m base ) || return 1
}

# Payload de PostToolUse montado com node. Uso: gerar <Write|Edit> <arquivo> <cwd> <texto>
gerar() {
  node -e '
const [tool, arquivo, cwd, texto] = process.argv.slice(1).map((v) => v.replace(/\\n/g, "\n"));
const ti = tool === "Write" ? { file_path: arquivo, content: texto } : { file_path: arquivo, old_string: "x", new_string: texto };
process.stdout.write(JSON.stringify({ session_id: "s-caminho-real", hook_event_name: "PostToolUse", tool_name: tool, tool_input: ti, cwd }));
' "$@"
}

echo "== 1. lib caminho-real direto (node -e) =="
DIRL="$SBP/lib-dir"; mkdir -p "$DIRL"; : > "$DIRL/existe.txt"
DIRL_M="$(cygpath -m "$DIRL")"
RES="$(node -e '
const [lib, dir] = process.argv.slice(1);
const fs = require("fs"), path = require("path");
const { caminhoReal } = require(lib);
const real = fs.realpathSync.native(dir);
const linhas = [];
const cmp = (nome, obtido, esperado) => linhas.push(`${nome}=${obtido === esperado ? "ok" : "diferente:" + obtido + " esperado:" + esperado}`);
cmp("A:existente", caminhoReal(dir + "/./existe.txt"), path.join(real, "existe.txt"));
cmp("B:novo", caminhoReal(dir + "/./novo.txt"), path.join(real, "novo.txt"));
cmp("C:inexistente", caminhoReal(dir + "/nao-existe/x.txt"), dir + "/nao-existe/x.txt");
console.log(linhas.join("\n"));
' "$LIB" "$DIRL_M")"
tem "arquivo existente resolve para o caminho real" "$RES" "A:existente=ok"
tem "arquivo novo numa pasta existente resolve para pasta real + nome" "$RES" "B:novo=ok"
tem "pasta inexistente devolve o proprio p" "$RES" "C:inexistente=ok"

echo
echo "== 2. aviso-duplicata com cwd em nome curto 8.3 nao acusa o proprio arquivo =="
if [ "$WIN" = 1 ]; then
  PAI="$SBP/pasta-de-nome-bem-longo"
  R5="$PAI/repo"
  montar_repo "$R5" 'lib/unico.cjs=function soNesteArquivo() {}\n' 'lib/outro.js=// vazio\n'
  LONGO5="$(cygpath -m "$R5")"
  CURTO5="$(cygpath -m "$(cygpath -d "$R5")")"
  if [ "$CURTO5" = "$LONGO5" ]; then
    pulou "volume sem nome 8.3"
  else
    gerar Write "$CURTO5/lib/unico.cjs" "$CURTO5" 'function soNesteArquivo() {}\n' > "$SBP/p2.json"
    OUT="$(node "$HOOK_DUP" < "$SBP/p2.json" 2>/dev/null)"; EXIT=$?
    saiu "Write com cwd e file_path em nome curto 8.3: exit 0" "$EXIT" "0"
    vazio "o proprio arquivo (lib/unico.cjs) nao se acusa pelo nome curto" "$OUT"
  fi
else
  pulou "só win32"
fi

echo
echo "== 3. aviso-fluxo com cwd em nome curto 8.3 =="
if [ "$WIN" = 1 ]; then
  PAI3="$SBP/pasta-fluxo-de-nome-bem-longo"
  R6="$PAI3/fluxo"
  montar_repo "$R6" 'docs/exemplo.js=// doc\n' 'docs/rainforest/estado/.gitkeep=\n' 'src/base.js=// base\n'
  LONGO6="$(cygpath -m "$R6")"
  CURTO6="$(cygpath -m "$(cygpath -d "$R6")")"
  if [ "$CURTO6" = "$LONGO6" ]; then
    pulou "volume sem nome 8.3"
  else
    gerar Edit "$CURTO6/docs/exemplo.js" "$CURTO6" '// doc editado\n' > "$SBP/p3a.json"
    OUT="$(node "$HOOK_FLUXO" < "$SBP/p3a.json" 2>"$SBP/err3a.txt")"; EXIT=$?
    saiu "arquivo sob docs/ com cwd 8.3: exit 0 (isento)" "$EXIT" "0"
    vazio "arquivo sob docs/ com cwd 8.3 sai sem saida" "$OUT$(cat "$SBP/err3a.txt")"
    gerar Edit "$CURTO6/src/base.js" "$CURTO6" '// base editado\n' > "$SBP/p3b.json"
    OUT="$(node "$HOOK_FLUXO" < "$SBP/p3b.json" 2>"$SBP/err3b.txt")"; EXIT=$?
    saiu "controle: src/ com o mesmo cwd 8.3 bloqueia (exit 2, trilho ligado)" "$EXIT" "2"
  fi
else
  pulou "só win32"
fi

echo
echo "== 4. junction rastreada no repo: editar pelo caminho da junction =="
if [ "$WIN" = 1 ]; then
  R7="$SBP/junc"
  montar_repo "$R7" 'alvo/x.cjs=function soNaJunction() {}\n'
  WALVO="$(cygpath -w "$R7/alvo")"; WLINK="$(cygpath -w "$R7/jn")"
  cmd //c mklink /J "$WLINK" "$WALVO" >/dev/null 2>&1
  ( cd "$R7" && git add -A && git commit -q -m junction ) 2>/dev/null
  C7="$(cygpath -m "$R7")"
  if ! ( cd "$R7" && git ls-files ) | grep -qxF 'jn/x.cjs'; then
    pulou "git não segue a junction (jn/x.cjs fora do git ls-files)"
  else
    gerar Edit "$C7/jn/x.cjs" "$C7" 'function soNaJunction() {}\n' > "$SBP/p4.json"
    OUT="$(node "$HOOK_DUP" < "$SBP/p4.json" 2>/dev/null)"; EXIT=$?
    saiu "editar pelo caminho da junction: exit 0" "$EXIT" "0"
    vazio "editar pelo caminho da junction nao acusa o proprio arquivo (alvo/x.cjs)" "$OUT"
  fi
  cmd //c rmdir "$WLINK" >/dev/null 2>&1
else
  pulou "só win32"
fi

echo
echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
exit 0
