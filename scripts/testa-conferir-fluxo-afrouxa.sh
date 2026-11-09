#!/bin/bash
# Bateria do subcomando `afrouxa` de scripts/conferir-fluxo.cjs, do campo `afrouxa:`
# da tarefa e da chamada dele no `marcar verificar ok` (plano 2026-11-09-regua-testes).
# Uso: bash scripts/testa-conferir-fluxo-afrouxa.sh
#
# Casos A: teste apagado e marcador de pulo no diff. Casos B: o escape declarado.
# Casos C: o `marcar verificar ok` de verdade, com estado e diff reais.
#
# Os marcadores de pulo e foco sao montados por concatenacao: este arquivo e um
# teste, e o diff que o criou nao pode trazer o marcador literal.
#
# Placar no formato `ok: N   falhou: M` (a catraca sabe ler).

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECADOR="$SRC/scripts/conferir-fluxo.cjs"
ESTADO="$SRC/scripts/estado.cjs"
OK=0; FALHOU=0
SANDBOXES=()
cleanup() { for d in "${SANDBOXES[@]}"; do rm -rf "$d" 2>/dev/null || true; done; }
trap cleanup EXIT
passa() { OK=$((OK + 1)); echo "  ok    $1"; }
falha() { FALHOU=$((FALHOU + 1)); echo "  FALHA $1"; [ -f "$S/saida.txt" ] && sed 's/^/         | /' "$S/saida.txt"; }
mixto() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

SK="sk""ip"; ON="on""ly"; XI="x""it"

g() { git -C "$S" -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c core.autocrlf=false "$@"; }

# escreve_plano <linha extra da tarefa 1, ou vazio> [<glob de arquivos da tarefa 1>]
escreve_plano() {
  local extra="${1:-}"
  local globs="${2:-\`scripts/testa-x.sh\`, \`scripts/testa-y.sh\`, \`src/a.test.js\`, \`src/b.js\`}"
  {
    echo "# Plano"
    echo
    echo "## Tarefas"
    echo
    echo "### 1. t [tipo: implementar]"
    echo "atende: D1"
    echo "arquivos: $globs"
    echo "depende de: nenhuma"
    [ -n "$extra" ] && echo "$extra"
    echo "mutacao: n/a"
    echo "  motivo: x"
    echo "pronto quando: x"
  } > "$S/docs/rainforest/planos/t.md"
}

# novo_repo: S (posix), SM (misto), BASE; repositorio com a bateria, o teste e o fonte.
novo_repo() {
  S=$(mktemp -d); SANDBOXES+=("$S"); SM=$(mixto "$S")
  git init -q "$S"
  mkdir -p "$S/scripts" "$S/src" "$S/docs/rainforest/design" "$S/docs/rainforest/planos"
  echo 'echo a' > "$S/scripts/testa-x.sh"
  echo 'test("a", () => {});' > "$S/src/a.test.js"
  echo 'module.exports = 1;' > "$S/src/b.js"
  cat > "$S/docs/rainforest/design/t.md" <<'EOF'
# Design

## Objetivo
Teste

## Decisões fechadas
- **D1 — teste** — porquê: teste

## Avaliado e descartado
n/a

## Fora de escopo
n/a

## Em aberto
n/a
EOF
  escreve_plano ""
  g add -A; g commit -q -m base
  BASE=$(g rev-parse HEAD)
}
commita() { g add -A; g commit -q -m mudanca; }

chk() {
  env -u CLAUDE_PROJECT_DIR RFM_ESTADO_ROOT="$SM" node "$CHECADOR" afrouxa --slug t \
    --plano "$SM/docs/rainforest/planos/t.md" --base "$BASE" --head "$(g rev-parse HEAD)" \
    > "$S/saida.txt" 2>&1 < /dev/null
  echo $?
}
cob() {
  env -u CLAUDE_PROJECT_DIR RFM_ESTADO_ROOT="$SM" node "$CHECADOR" cobertura --slug t \
    --design "$SM/docs/rainforest/design/t.md" --plano "$SM/docs/rainforest/planos/t.md" \
    > "$S/saida.txt" 2>&1 < /dev/null
  echo $?
}
tem() { grep -qF -- "$1" "$S/saida.txt"; }

echo "== A. teste apagado e marcador de pulo =="

novo_repo; g rm -q scripts/testa-x.sh; commita
c=$(chk); if [ "$c" = 2 ] && tem "RECUSADO:" && tem "apagado: scripts/testa-x.sh"; then passa "A1 bateria apagada sem afrouxa recusa"; else falha "A1 bateria apagada sem afrouxa recusa (exit $c)"; fi

novo_repo; printf 'it.%s("x", () => {});\n' "$SK" >> "$S/src/a.test.js"; commita
c=$(chk); if [ "$c" = 2 ] && tem "pulo: src/a.test.js:2 "; then passa "A2 pulo novo em teste recusa com arquivo e linha"; else falha "A2 pulo novo em teste recusa com arquivo e linha (exit $c)"; fi

novo_repo; printf 'describe.%s("x", () => {});\n%s("y", () => {});\n' "$ON" "$XI" >> "$S/src/a.test.js"; commita
c=$(chk); if [ "$c" = 2 ] && tem "pulo: src/a.test.js:2 " && tem "pulo: src/a.test.js:3 "; then passa "A3 only e o it desligado tambem recusam"; else falha "A3 only e o it desligado tambem recusam (exit $c)"; fi

novo_repo; g mv scripts/testa-x.sh scripts/testa-renomeada.sh; commita
c=$(chk); if [ "$c" = 0 ] && tem "ok: nenhum teste"; then passa "A4 renome da bateria nao conta"; else falha "A4 renome da bateria nao conta (exit $c)"; fi

novo_repo; printf '// it.%s(\n' "$SK" >> "$S/src/b.js"; commita
c=$(chk); if [ "$c" = 0 ]; then passa "A5 pulo em arquivo que nao e teste nao conta"; else falha "A5 pulo em arquivo que nao e teste nao conta (exit $c)"; fi

novo_repo; echo 'test("b", () => {});' >> "$S/src/a.test.js"; commita
c=$(chk); if [ "$c" = 0 ]; then passa "A6 edicao sem marcador passa"; else falha "A6 edicao sem marcador passa (exit $c)"; fi

novo_repo; g rm -q scripts/testa-x.sh; commita
VAZIA=$(mktemp -d); SANDBOXES+=("$VAZIA"); NODE_ABS=$(command -v node); HEAD_A7=$(g rev-parse HEAD)
env -u CLAUDE_PROJECT_DIR PATH="$VAZIA" RFM_ESTADO_ROOT="$SM" "$NODE_ABS" "$CHECADOR" afrouxa --slug t \
  --plano "$SM/docs/rainforest/planos/t.md" --base "$BASE" --head "$HEAD_A7" > "$S/saida.txt" 2>&1 < /dev/null
c=$?; if [ "$c" = 69 ] && tem "nao-verificavel:"; then passa "A7 sem git no PATH sai 69"; else falha "A7 sem git no PATH sai 69 (exit $c)"; fi

novo_repo; BASE=$(printf '%040d' 1)
c=$(chk); if [ "$c" = 1 ] && tem "erro ao rodar git diff"; then passa "A8 revisao desconhecida sai 1, nao passa"; else falha "A8 revisao desconhecida sai 1, nao passa (exit $c)"; fi

novo_repo; g mv src/a.test.js src/a.test.js.off; commita
c=$(chk); if [ "$c" = 2 ] && tem "apagado: src/a.test.js.off (renomeado de src/a.test.js)"; then passa "A9 renome de teste para fora dos padroes recusa"; else falha "A9 renome de teste para fora dos padroes recusa (exit $c)"; fi

novo_repo; printf 'it.%s(1);\n' "$SK" > "$S/src/x y.test.js"; commita
c=$(chk); if [ "$c" = 2 ] && tem "pulo: src/x y.test.js:1 "; then passa "A10 nome com espaco casa e sai sem TAB"; else falha "A10 nome com espaco casa e sai sem TAB (exit $c)"; fi

novo_repo; escreve_plano "afrouxa: motivo" "\`src/x y.test.js\`"; printf 'it.%s(1);\n' "$SK" > "$S/src/x y.test.js"; commita
c=$(chk); if [ "$c" = 0 ] && tem "afrouxa declarado: tarefa 1 (motivo): pulo: src/x y.test.js:1 "; then passa "A11 afrouxa alcanca nome com espaco"; else falha "A11 afrouxa alcanca nome com espaco (exit $c)"; fi

novo_repo
TZ="scripts/tes""ta-z.cjs"; TW="scripts/tes""ta-w.py"
for f in test_a.py a_test.go a.spec.ts "$TZ" "$TW"; do printf 'it.%s(1);\n' "$SK" > "$S/$f"; done; commita
c=$(chk); falta=""; for f in test_a.py a_test.go a.spec.ts "$TZ" "$TW"; do tem "pulo: $f:1 " || falta="$falta $f"; done
if [ "$c" = 2 ] && [ -z "$falta" ]; then passa "A12 cada padrao de arquivo de teste e visto"; else falha "A12 cada padrao de arquivo de teste e visto (exit $c, faltou:$falta)"; fi

novo_repo
T_SK="Sk""ip"; DS="x""describe"; XT="x""test"; PY="@py""test.mark.$SK"; UN="@unit""test.$SK"; DI="@Dis""abled"; IG="@Ig""nore"
MARCADORES=("it.$SK(1)" "it.$ON(1)" "it.$SK (1)" "it.$SK.each(1)" "it.$ON.each(1)" "$XI(1)" "$DS(1)" "$XT(1)" "$PY" "$UN" "t.$T_SK(1)" "t.${T_SK}f(1)" "t.${T_SK}Now()" "$DI" "$IG")
for m in "${MARCADORES[@]}"; do printf '%s\n' "$m" >> "$S/src/a.test.js"; done; commita
c=$(chk); n=$(grep -c '^  pulo: ' "$S/saida.txt")
if [ "$c" = 2 ] && [ "$n" = "${#MARCADORES[@]}" ] && tem "pulo: src/a.test.js:16 "; then passa "A13 cada marcador recusa, com a linha certa"; else falha "A13 cada marcador recusa, com a linha certa (exit $c, n=$n)"; fi

novo_repo; printf '++ x\nit.%s(1);\n' "$SK" >> "$S/src/a.test.js"; commita
c=$(chk); if [ "$c" = 2 ] && tem "pulo: src/a.test.js:3 "; then passa "A14 linha adicionada com cara de cabecalho nao troca o arquivo"; else falha "A14 linha adicionada com cara de cabecalho nao troca o arquivo (exit $c)"; fi

novo_repo; echo '*.test.js -diff' > "$S/.gitattributes"; commita; BASE=$(g rev-parse HEAD); printf 'it.%s(1);\n' "$SK" >> "$S/src/a.test.js"; commita
c=$(chk); if [ "$c" = 2 ] && tem "pulo: src/a.test.js:2 "; then passa "A15 gitattributes com -diff nao esconde o marcador"; else falha "A15 gitattributes com -diff nao esconde o marcador (exit $c)"; fi

novo_repo; g rm -q scripts/testa-x.sh; commita; BASE="--stat"
c=$(chk); if [ "$c" = 1 ] && tem "revisão inválida"; then passa "A16 revisao comecando com hifen sai 1"; else falha "A16 revisao comecando com hifen sai 1 (exit $c)"; fi

echo "== B. o escape afrouxa: =="

novo_repo; escreve_plano "afrouxa: a peca testada saiu"; g rm -q scripts/testa-x.sh; commita
c=$(chk); if [ "$c" = 0 ] && tem "afrouxa declarado: tarefa 1 (a peca testada saiu): apagado: scripts/testa-x.sh"; then passa "B1 apagado com afrouxa na tarefa do arquivo passa"; else falha "B1 apagado com afrouxa na tarefa do arquivo passa (exit $c)"; fi

novo_repo; escreve_plano "afrouxa: outro assunto" "\`src/outro.js\`"
cat >> "$S/docs/rainforest/planos/t.md" <<'EOF'

### 2. u [tipo: implementar]
atende: D1
arquivos: `scripts/testa-x.sh`
depende de: 1
mutacao: n/a
  motivo: x
pronto quando: x
EOF
g rm -q scripts/testa-x.sh; commita
c=$(chk); if [ "$c" = 2 ] && tem "apagado: scripts/testa-x.sh"; then passa "B2 afrouxa em tarefa de outro arquivo nao autoriza"; else falha "B2 afrouxa em tarefa de outro arquivo nao autoriza (exit $c)"; fi

novo_repo; escreve_plano "afrouxa:"
c=$(cob); if [ "$c" = 2 ] && tem "afrouxa: sem motivo"; then passa "B3 cobertura recusa afrouxa sem motivo"; else falha "B3 cobertura recusa afrouxa sem motivo (exit $c)"; fi

novo_repo; escreve_plano "afrouxa: a peca testada saiu"
c=$(cob); if [ "$c" = 0 ] && ! tem "campo desconhecido"; then passa "B4 cobertura aceita afrouxa com motivo"; else falha "B4 cobertura aceita afrouxa com motivo (exit $c)"; fi

echo "== C. marcar verificar ok =="

E() { env -u CLAUDE_PROJECT_DIR RFM_ESTADO_ROOT="$SM" node "$ESTADO" "$@"; }
JSON_ESTADO() { printf '%s/docs/rainforest/estado/t.json' "$SM"; }
EV='{"comando":"bash t.sh","saida":"done","sensor_externo":"bash t.sh"}'

# prep_fluxo <com revisar real: sim|nao>: leva o fluxo ate a porta do verificar.
prep_fluxo() {
  E iniciar --slug t > "$S/prep.txt" 2>&1 || return 1
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    const e = JSON.parse(fs.readFileSync(p, "utf8"));
    e.design = { status: "aprovado", em: "2026-11-09", arquivo: "docs/rainforest/design/t.md" };
    e.plano = { status: "ok", em: "2026-11-09", arquivo: "docs/rainforest/planos/t.md" };
    fs.writeFileSync(p, JSON.stringify(e, null, 2));
  ' "$(JSON_ESTADO)" || return 1
  E exigir --slug t --estagio executar >> "$S/prep.txt" 2>&1 || return 1
  E marcar --slug t --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"n/a","motivo":"x"}]}' >> "$S/prep.txt" 2>&1 || return 1
  if [ "$1" = sim ]; then
    E marcar --slug t --estagio revisar --status ok --json "{\"achados\":0,\"base\":\"$BASE\",\"head\":\"$(g rev-parse HEAD)\"}" >> "$S/prep.txt" 2>&1 || return 1
  else
    node -e '
      const fs = require("fs"); const p = process.argv[1];
      const e = JSON.parse(fs.readFileSync(p, "utf8"));
      e.revisar = { status: "ok", em: "2026-11-09" };
      fs.writeFileSync(p, JSON.stringify(e, null, 2));
    ' "$(JSON_ESTADO)" || return 1
  fi
  E exigir --slug t --estagio verificar >> "$S/prep.txt" 2>&1 || return 1
}
marca_verificar() { E marcar --slug t --estagio verificar --status ok --json "$EV" > "$S/saida.txt" 2>&1 < /dev/null; echo $?; }

novo_repo; g rm -q scripts/testa-x.sh; commita
if prep_fluxo sim; then
  cp "$S/docs/rainforest/estado/t.json" "$S/antes.json"
  c=$(marca_verificar)
  if [ "$c" = 2 ] && tem "apagado: scripts/testa-x.sh" && tem "RECUSADO: o verificar não fecha" && cmp -s "$S/antes.json" "$S/docs/rainforest/estado/t.json"; then
    passa "C1 marcar verificar ok recusa bateria apagada sem afrouxa"
  else
    falha "C1 marcar verificar ok recusa bateria apagada sem afrouxa (exit $c)"
  fi
else
  cp "$S/prep.txt" "$S/saida.txt"; falha "C1 preparo do fluxo"
fi

novo_repo; escreve_plano "afrouxa: a peca testada saiu"; g rm -q scripts/testa-x.sh; commita
if prep_fluxo sim; then
  c=$(marca_verificar)
  if [ "$c" = 0 ] && tem "afrouxa declarado: tarefa 1 ("; then
    passa "C2 com afrouxa a checagem roda e libera"
  else
    falha "C2 com afrouxa a checagem roda e libera (exit $c)"
  fi
else
  cp "$S/prep.txt" "$S/saida.txt"; falha "C2 preparo do fluxo"
fi

novo_repo; g rm -q scripts/testa-x.sh; commita
if prep_fluxo nao; then
  c=$(marca_verificar)
  if [ "$c" = 0 ] && tem "aviso: revisar sem base/head"; then
    passa "C3 revisar sem base e head avisa e segue"
  else
    falha "C3 revisar sem base e head avisa e segue (exit $c)"
  fi
else
  cp "$S/prep.txt" "$S/saida.txt"; falha "C3 preparo do fluxo"
fi

novo_repo; g rm -q scripts/testa-x.sh; commita
if prep_fluxo sim; then
  HEAD_REAL=$(g rev-parse HEAD)
  node -e '
    const fs = require("fs"); const [p, base, head] = process.argv.slice(1);
    const e = JSON.parse(fs.readFileSync(p, "utf8"));
    e.revisar.head = base; e.revisar.snapshot = { head, caminhos_sujos: [] };
    fs.writeFileSync(p, JSON.stringify(e, null, 2));
  ' "$(JSON_ESTADO)" "$BASE" "$HEAD_REAL"
  c=$(marca_verificar)
  if [ "$c" = 2 ] && tem "apagado: scripts/testa-x.sh"; then
    passa "C4 head declarado igual a base nao esvazia a checagem"
  else
    falha "C4 head declarado igual a base nao esvazia a checagem (exit $c)"
  fi
else
  cp "$S/prep.txt" "$S/saida.txt"; falha "C4 preparo do fluxo"
fi

echo
echo "ok: $OK   falhou: $FALHOU"
[ "$FALHOU" -eq 0 ] || exit 1
exit 0
