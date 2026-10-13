#!/bin/bash
# Bateria das camadas do plano: `scripts/lib/camadas.cjs`, o subcomando
# `conferir-fluxo.cjs camadas` e a recusa por camada da `cobertura`.
# Uso: bash scripts/testa-camadas.sh
#
# Fixture: planos e designs REAIS de docs/rainforest/, copiados para um repo-caixa
# (mktemp -d, fora do worktree) e alterados uma tarefa por vez. Cada recusa tem
# caso proprio, e cada aceite tambem: uma checagem so vista passando nao foi
# verificada.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECADOR="$RAIZ/scripts/conferir-fluxo.cjs"
PLANO_FECHAR="$RAIZ/docs/rainforest/planos/2026-10-13-fechar-push-merge.md"
DESIGN_FECHAR="$RAIZ/docs/rainforest/design/2026-10-13-fechar-push-merge.md"
PLANO_FLAKY="$RAIZ/docs/rainforest/planos/2026-10-10-flaky-teto.md"
DESIGN_FLAKY="$RAIZ/docs/rainforest/design/2026-10-10-flaky-teto.md"

for f in "$CHECADOR" "$PLANO_FECHAR" "$DESIGN_FECHAR" "$PLANO_FLAKY" "$DESIGN_FLAKY"; do
  [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }
done

ok=0; falhou=0
# Sandboxes com mktemp -d; o trap de EXIT varre todas, mesmo se a bateria morrer no meio.
SANDBOXES=()
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

TMP="$(mktemp -d)"; SANDBOXES+=("$TMP")
OUT="$TMP/out"; ERR="$TMP/err"

# Editor de plano: troca a linha `campo:` dentro da tarefa N (ou falha se não achar).
cat > "$TMP/editar.cjs" <<'EOF'
const fs = require('fs');
const [arquivo, numero, campo, valor] = process.argv.slice(2);
const linhas = fs.readFileSync(arquivo, 'utf8').split('\n');
const ini = linhas.findIndex((l) => l.startsWith('### ' + numero + '. '));
if (ini < 0) { console.error('tarefa ' + numero + ' nao achada'); process.exit(3); }
let fim = linhas.findIndex((l, i) => i > ini && (l.startsWith('### ') || l.startsWith('## ')));
if (fim < 0) fim = linhas.length;
const k = linhas.findIndex((l, i) => i > ini && i < fim && l.startsWith(campo + ':'));
if (k < 0) { console.error('campo ' + campo + ' nao achado na tarefa ' + numero); process.exit(4); }
linhas[k] = campo + ': ' + valor;
fs.writeFileSync(arquivo, linhas.join('\n'));
EOF

# `caixa <plano> <design>`: repo-caixa com o plano e o design como slug `s`.
# Devolve em CX o caminho POSIX e em W o caminho Windows (o node lê W).
caixa() {
  CX="$(mktemp -d)"; SANDBOXES+=("$CX")
  mkdir -p "$CX/docs/rainforest/planos" "$CX/docs/rainforest/design"
  cp "$1" "$CX/docs/rainforest/planos/s.md"
  cp "$2" "$CX/docs/rainforest/design/s.md"
  W="$(cygpath -m "$CX" 2>/dev/null || printf '%s' "$CX")"
}
plano() { printf '%s/docs/rainforest/planos/s.md' "$W"; }
EDITAR="$(cygpath -m "$TMP/editar.cjs" 2>/dev/null || printf '%s' "$TMP/editar.cjs")"
editar() { node "$EDITAR" "$(plano)" "$@" || { echo "FALHA: editar $*"; falhou=$((falhou+1)); }; }

# `esperar <rotulo> <exit> <regex-stdout|-> <regex-stderr|-> <cmd...>`
esperar() {
  local rotulo="$1" esperado="$2" rout="$3" rerr="$4"; shift 4
  "$@" >"$OUT" 2>"$ERR"; local got=$?
  local motivo=""
  [ "$got" -eq "$esperado" ] || motivo="exit $got (esperado $esperado)"
  if [ "$rout" != "-" ] && ! grep -qE -- "$rout" "$OUT"; then motivo="$motivo; stdout nao casa /$rout/"; fi
  if [ "$rerr" != "-" ] && ! grep -qE -- "$rerr" "$ERR"; then motivo="$motivo; stderr nao casa /$rerr/"; fi
  if [ -z "$motivo" ]; then
    ok=$((ok+1))
  else
    falhou=$((falhou+1))
    echo "  FALHA $rotulo:$motivo"
    echo "  stdout: $(head -c 400 "$OUT")"
    echo "  stderr: $(head -c 400 "$ERR")"
  fi
}

camadas() { RFM_ESTADO_ROOT="$W" node "$CHECADOR" camadas --slug s "$@"; }
cobertura() { RFM_ESTADO_ROOT="$W" node "$CHECADOR" cobertura --slug s; }

echo "== camadas: calculo"
caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 2 "depende de" nenhuma
editar 2 arquivos '`hooks/testa-camadas-b.sh`'
esperar "1 e 2 sem dependencia, 3 depende das duas: [[1,2],[3]]" 0 '"camadas":\[\[1,2\],\[3\]\]' - camadas

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
esperar "dependencia so em 1: [[1],[2],[3]]" 0 '"camadas":\[\[1\],\[2\],\[3\]\]' - camadas

echo "== camadas: recusas"
# ciclo 1->2->1 recusa nomeando as duas
caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 1 "depende de" 2
esperar "ciclo 1->2->1 recusa nomeando as duas" 2 - 'ciclo.*tarefa 1.*tarefa 2' camadas

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 3 "depende de" "1, 9"
esperar "depende de: 9 inexistente recusa nomeando o 9" 2 - 'tarefa 3 depende de: 9' camadas

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 2 "depende de" nenhuma
esperar "1 e 2 na mesma camada com arquivo em comum recusa" 2 '"conflitos":\[\{"camada":1,"a":1,"b":2,"arquivo":"hooks/lib/config.cjs"\}\]' 'compartilham arquivos: hooks/lib/config.cjs' camadas

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 2 "depende de" nenhuma
editar 2 arquivos '`hooks/lib/*.cjs`, `hooks/testa-gate-merge-auto.sh`'
esperar "glob na tarefa 2 casa o literal da tarefa 1: recusa" 2 - 'compartilham arquivos: hooks/lib/config.cjs' camadas

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 2 "depende de" nenhuma
editar 1 arquivos '`hooks/lib/*.cjs`'
esperar "glob na tarefa 1 casa o literal da tarefa 2: recusa" 2 - 'compartilham arquivos: hooks/lib/\*.cjs ~ hooks/lib/config.cjs' camadas

echo "== cobertura"
caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
esperar "cobertura aceita o fechar-push-merge real como esta" 0 'ok: cobertura' - cobertura

caixa "$PLANO_FLAKY" "$DESIGN_FLAKY"
esperar "cobertura aceita o flaky-teto real como esta" 0 'ok: cobertura' - cobertura

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
sed -i '/^paralela:/d' "$CX/docs/rainforest/planos/s.md"
esperar "cobertura aceita plano sem nenhum paralela:" 0 'ok: cobertura' - cobertura

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 2 paralela sim
esperar "cobertura aceita paralela: sim em tarefa dependente, com aviso" 0 'ok: cobertura' 'aviso: tarefa 2' cobertura

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 1 "depende de" 2
esperar "cobertura recusa ciclo nomeando as duas" 2 - 'ciclo.*tarefa 1.*tarefa 2' cobertura

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 3 "depende de" "1, 9"
esperar "cobertura recusa depende de: 9 inexistente" 2 - 'depende de: 9' cobertura

caixa "$PLANO_FECHAR" "$DESIGN_FECHAR"
editar 2 "depende de" nenhuma
esperar "cobertura recusa arquivo em comum na mesma camada" 2 - 'compartilham arquivos: hooks/lib/config.cjs' cobertura

echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
