#!/bin/bash
# Confere a matriz de shards da workflow `baterias` (Issue #541).
#
# Dois defeitos que o CI nao acusa sozinho:
# - o `/N` do nome do job e do `--shard i/N` do passo divergir da matriz: com
#   `shard: [1, 2, 3]` e `/2` no passo, o shard 3 sai "FALHA --shard fora da
#   faixa" e o 1 e o 2 rodam metade cada — ou, ao contrario, uma fatia some;
# - a carga estimada do shard mais pesado encostar no `timeout-minutes`: com 2
#   shards eram ~1765 s de bateria cada, a 3-7 min do teto de 35.
#
# A carga sai da mesma reparticao que o CI usa (`varrer-baterias.sh --listar`,
# que chama `repartir-baterias.cjs` com `tempos-baterias.json`). Bateria sem peso
# conta a mediana, como no repartir. Folga exigida: 10 min abaixo do teto,
# descontado o overhead de ~90 s de checkout/setup — o criterio da Issue.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF_REAL="$RAIZ/.github/workflows/baterias.yml"
ok=0; falhou=0
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT

# conferir <workflow> : 0 = coerente e dentro do teto; 2 = defeito (stderr diz qual)
conferir() {
  local wf="$1"
  local n
  n="$(node -e '
    const s = require("fs").readFileSync(process.argv[1], "utf8");
    const m = /^\s*shard:\s*\[([^\]]*)\]/m.exec(s);
    if (!m) { console.error("matriz shard: [...] nao achada"); process.exit(2); }
    const v = m[1].split(",").map((x) => Number(x.trim()));
    const n = v.length;
    if (v.some((x, i) => x !== i + 1)) { console.error(`matriz fora de 1..N: ${m[1]}`); process.exit(2); }
    const nome = /^\s*name: baterias \(node .*shard \$\{\{ matrix\.shard \}\}\/(\d+)\)/m.exec(s);
    if (!nome || Number(nome[1]) !== n) { console.error(`nome do job diz /${nome && nome[1]}, matriz tem ${n}`); process.exit(2); }
    const passos = [...s.matchAll(/--shard \$\{\{ matrix\.shard \}\}\/(\d+)/g)];
    if (!passos.length || passos.some((p) => Number(p[1]) !== n)) { console.error(`passo --shard com /${passos.map((p) => p[1]).join(",")}, matriz tem ${n}`); process.exit(2); }
    const t = /^\s*timeout-minutes:\s*(\d+)/m.exec(s);
    if (!t) { console.error("timeout-minutes nao achado"); process.exit(2); }
    console.log(`${n} ${t[1]}`);
  ' "$wf")" || return 2
  local shards="${n% *}" teto_min="${n#* }"
  local teto=$(( teto_min * 60 - 600 - 90 )) i carga max=0
  for i in $(seq 1 "$shards"); do
    carga="$(cd "$RAIZ" && bash scripts/varrer-baterias.sh --shard "$i/$shards" --listar | node -e '
      const p = require(process.argv[1]);
      const v = Object.values(p).filter(Number.isFinite).sort((a, b) => a - b);
      const med = v.length ? v[Math.floor(v.length / 2)] : 0;
      const l = require("fs").readFileSync(0, "utf8").split(/\r?\n/).filter(Boolean);
      console.log(l.reduce((a, b) => a + (Number.isFinite(p[b]) ? p[b] : med), 0));
    ' "$RAIZ/scripts/tempos-baterias.json")" || return 2
    [ "$carga" -gt "$max" ] && max="$carga"
  done
  if [ "$max" -gt "$teto" ]; then
    echo "shard mais pesado com ${max}s de bateria, acima de ${teto}s (teto ${teto_min} min - 10 min de folga - 90 s de setup)" >&2
    return 2
  fi
  echo "shards=$shards carga_max=${max}s teto=${teto}s"
  return 0
}

afirma() { # afirma <esperado> <rotulo> <workflow>
  local saida rc
  saida="$(conferir "$3" 2>&1)"; rc=$?
  if [ "$rc" -eq "$1" ]; then ok=$((ok+1)); echo "  ok    $2 (exit=$rc) $saida"
  else falhou=$((falhou+1)); echo "  FALHA $2: esperado exit=$1, veio exit=$rc: $saida"; fi
}

echo "== workflow real =="
afirma 0 "matriz, nome e passo casam e a carga cabe no teto" "$WF_REAL"

echo "== contornos (copias alteradas da workflow real) =="
sed 's/shard: \[1, 2, 3\]/shard: [1, 2]/' "$WF_REAL" > "$SANDBOX/matriz2-nome3.yml"
afirma 2 "matriz com 2 e /3 no nome diverge" "$SANDBOX/matriz2-nome3.yml"
sed -e 's/shard: \[1, 2, 3\]/shard: [1, 2]/' -e 's|}}/3|}}/2|g' "$WF_REAL" > "$SANDBOX/dois-shards.yml"
afirma 2 "2 shards coerentes nao cabem com 10 min de folga" "$SANDBOX/dois-shards.yml"
sed 's|varrer-baterias.sh --shard ${{ matrix.shard }}/3|varrer-baterias.sh --shard ${{ matrix.shard }}/2|' "$WF_REAL" > "$SANDBOX/passo2.yml"
afirma 2 "passo com /2 e matriz com 3 diverge" "$SANDBOX/passo2.yml"
sed 's/shard: \[1, 2, 3\]/shard: [1, 3, 4]/' "$WF_REAL" > "$SANDBOX/buraco.yml"
afirma 2 "matriz fora de 1..N recusa" "$SANDBOX/buraco.yml"

echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
