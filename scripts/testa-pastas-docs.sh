#!/bin/bash
# Bateria de hooks/lib/pastas-docs.cjs + scripts/pastas-docs.cjs: onde moram mapa,
# design e plano. Repo que ja tem docs/legado e docs/plans (plugin protheus) manda;
# `docs/rainforest/*` e so o padrao de repo virgem. Estado de maquina nao passa aqui.
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
RAIZ_SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
ok=0; falhou=0
igual() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$2', veio '$3')"; fi
}
cam() { node "$SRC/scripts/pastas-docs.cjs" caminho "$@" 2>&1; }

# Repo com a arqueologia e o docs/plans do plugin protheus
R1="$RAIZ_SB/r1"
mkdir -p "$R1/docs/legado" "$R1/docs/plans"
printf '# Cobertura de arqueologia\n\n| Fatia | Fontes cobertos | Demanda | Data |\n|---|---|---|---|\n| fat | A.prw | d1 | 2026-01-01 |\n' > "$R1/docs/legado/COBERTURA.md"
printf '# d\n' > "$R1/docs/plans/2026-01-01-x-design.md"

echo "== 1. repo com docs/legado e docs/plans =="
igual "mapas adota docs/legado com COBERTURA" "docs/legado" "$(cam --tipo mapas --raiz "$R1")"
igual "design adota docs/plans" "docs/plans/s-design.md" "$(cam --tipo design --slug s --raiz "$R1")"
igual "planos adota docs/plans" "docs/plans/s-plano.md" "$(cam --tipo planos --slug s --raiz "$R1")"

echo "== 2. repo vazio =="
R2="$RAIZ_SB/r2"; mkdir -p "$R2"
igual "mapas padrao" "docs/rainforest/mapas" "$(cam --tipo mapas --raiz "$R2")"
igual "design padrao" "docs/rainforest/design/s.md" "$(cam --tipo design --slug s --raiz "$R2")"
igual "planos padrao" "docs/rainforest/planos/s.md" "$(cam --tipo planos --slug s --raiz "$R2")"

echo "== 3. config.pastas =="
R3="$RAIZ_SB/r3"; mkdir -p "$R3/.rainforest"
printf '{"pastas":{"design":"doc/arq"}}' > "$R3/.rainforest/config.json"
igual "config redireciona design" "doc/arq/s-design.md" "$(cam --tipo design --slug s --raiz "$R3")"
printf '{"pastas":{"design":"../fora"}}' > "$R3/.rainforest/config.json"
igual "config com .. cai no padrao" "docs/rainforest/design/s.md" "$(cam --tipo design --slug s --raiz "$R3")"
printf '{"pastas":{"design":"/abs"}}' > "$R3/.rainforest/config.json"
igual "config absoluta cai no padrao" "docs/rainforest/design/s.md" "$(cam --tipo design --slug s --raiz "$R3")"
printf '{"pastas":{"design":"C:\\\\x"}}' > "$R3/.rainforest/config.json"
igual "config com drive cai no padrao" "docs/rainforest/design/s.md" "$(cam --tipo design --slug s --raiz "$R3")"
printf '{"pastas":{"outro":"x"}}' > "$R3/.rainforest/config.json"
igual "config com chave estranha cai no padrao" "docs/rainforest/design/s.md" "$(cam --tipo design --slug s --raiz "$R3")"
printf '{"pastas":{"design":"a\\\\b"}}' > "$R3/.rainforest/config.json"
igual "contrabarra vira /" "a/b/s-design.md" "$(cam --tipo design --slug s --raiz "$R3")"

echo "== 4. docs/plans so com README nao e adotado =="
R4="$RAIZ_SB/r4"; mkdir -p "$R4/docs/plans"; printf '# r\n' > "$R4/docs/plans/README.md"
igual "design segue o padrao" "docs/rainforest/design/s.md" "$(cam --tipo design --slug s --raiz "$R4")"

echo "== 5. uso =="
cam --tipo xis --raiz "$R2" >/dev/null; igual "tipo invalido: exit 2" "2" "$?"
cam --tipo design --raiz "$R2" >/dev/null; igual "design sem slug: exit 2" "2" "$?"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
