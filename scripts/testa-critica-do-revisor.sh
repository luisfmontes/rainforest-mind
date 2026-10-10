#!/usr/bin/env bash
# Bateria do scripts/critica-do-revisor.cjs (design
# docs/rainforest/design/2026-10-10-laco-executor-revisor.md, D6 e D9): os
# quatro caminhos que o laço lê para decidir (0, 3, 4, 69), mais o erro de uso
# e a escolha do ÚLTIMO reprovado. Cada caso roda o script de verdade, com
# RFM_ESTADO_ROOT numa caixa temporária.
set -u

cd "$(dirname "$0")/.." || exit 1

ok=0
falhou=0

CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT
# O node não lê /tmp do Git Bash: a caixa vai para o node na forma Windows.
CAIXA_W="$(cd "$CAIXA" && pwd -W 2>/dev/null || pwd)"
RAIZ_W="$(pwd -W 2>/dev/null || pwd)"
FX="$RAIZ_W/scripts/fixtures/critica-do-revisor"

# estado <slug> <json do array de vereditos>
estado() {
  mkdir -p "$CAIXA/docs/rainforest/estado"
  printf '{"revisar":{"vereditos":%s}}\n' "$2" > "$CAIXA/docs/rainforest/estado/$1.json"
}

# vered <veredito> <transcrito> <agente_id> -> um item de revisar.vereditos
vered() {
  printf '{"agente":"revisor","agente_id":"%s","veredito":"%s","em":"2026-10-10","transcrito":"%s"}' "$3" "$1" "$2"
}

# roda <slug> -> OUT (stdout), EXIT, ERR (stderr)
roda() {
  OUT="$(RFM_ESTADO_ROOT="$CAIXA_W" node scripts/critica-do-revisor.cjs --slug "$1" 2>"$CAIXA/err")"
  EXIT=$?
  ERR="$(cat "$CAIXA/err")"
}

registra() { # $1 = caso, $2 = 0 se passou, 1 se falhou
  if [ "$2" -eq 0 ]; then
    ok=$((ok+1)); echo "  ok   $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1 (exit=$EXIT)"
    echo "    stdout: $OUT"; echo "    stderr: $ERR"
  fi
}

echo "== critica-do-revisor: os caminhos que o laço lê =="

echo "-- (a) reprovado com achado comum: exit 0, sem VEREDITO: --"
estado a "[$(vered reprovado "$FX/critica-sem-linha-de-veredito.jsonl" 1)]"
roda a
if [ "$EXIT" -eq 0 ] && printf '%s' "$OUT" | grep -q 'Achado 2' && ! printf '%s' "$OUT" | grep -q 'VEREDITO:'; then r=0; else r=1; fi
registra "(a) exit 0, stdout com o achado e sem VEREDITO:" $r

echo "-- (b) achado [design]: exit 3 --"
estado b "[$(vered reprovado "$FX/achado-design.jsonl" 1)]"
roda b
if [ "$EXIT" -eq 3 ] && printf '%s' "$OUT" | grep -q '\[design\]'; then r=0; else r=1; fi
registra "(b) exit 3 e o achado [design] no stdout" $r

echo "-- (c) só ok, ou lista vazia: exit 4 --"
estado c1 "[$(vered ok "$FX/critica-sem-linha-de-veredito.jsonl" 1)]"
roda c1
if [ "$EXIT" -eq 4 ]; then r=0; else r=1; fi
registra "(c1) so ok: exit 4" $r
estado c2 "[]"
roda c2
if [ "$EXIT" -eq 4 ]; then r=0; else r=1; fi
registra "(c2) lista vazia: exit 4" $r

echo "-- (d) transcrito inexistente: exit 69 com nao-verificavel --"
estado d "[$(vered reprovado "$FX/nao-existe.jsonl" 1)]"
roda d
if [ "$EXIT" -eq 69 ] && printf '%s' "$ERR" | grep -q '^nao-verificavel: '; then r=0; else r=1; fi
registra "(d) exit 69 e stderr com nao-verificavel:" $r

echo "-- (e) sem --slug: exit 1 com uso --"
OUT="$(RFM_ESTADO_ROOT="$CAIXA_W" node scripts/critica-do-revisor.cjs 2>"$CAIXA/err")"
EXIT=$?
ERR="$(cat "$CAIXA/err")"
if [ "$EXIT" -eq 1 ] && printf '%s' "$ERR" | grep -q 'uso:'; then r=0; else r=1; fi
registra "(e) exit 1 e uso no stderr" $r

echo "-- (f) dois reprovados: vale o ÚLTIMO (comum, exit 0), não o [design] --"
estado f "[$(vered reprovado "$FX/achado-design.jsonl" 1),$(vered reprovado "$FX/critica-sem-linha-de-veredito.jsonl" 2)]"
roda f
if [ "$EXIT" -eq 0 ] && printf '%s' "$OUT" | grep -q 'Achado 1' && ! printf '%s' "$OUT" | grep -q '\[design\]'; then r=0; else r=1; fi
registra "(f) exit 0 com o achado do ultimo reprovado" $r

echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
