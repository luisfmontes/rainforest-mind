#!/bin/bash
# Bateria isolada: testes de poda only (para conferir-mutacao.cjs)
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
TEMPS=("$SBP")
trap 'rm -rf "${TEMPS[@]}"' EXIT

ok=0; falhou=0

# R1: com poda desligada, não aparece no JSON
R1_TEST="$SBP/test-poda-off"
mkdir -p "$R1_TEST/.rainforest"
printf '{"poda":false}' > "$R1_TEST/.rainforest/config.json"
R1="$( ( cd "$R1_TEST" && node "$SRC/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
  let d=''; process.stdin.on('data', c => d += c).on('end', () => {
    try {
      const a = JSON.parse(d).find(x => x.item === 'poda');
      console.log(a ? 'ENCONTRADO' : 'ausente');
    } catch { console.log('erro'); }
  });
" )"
if [ "$R1" = "ausente" ]; then
  ok=$((ok+1)); echo "  ok   R1. com poda desligado, nao aparece item"
else
  falhou=$((falhou+1)); echo "  FALHA R1. esperava ausente, veio: $R1"
fi

# R2: com poda ligada e sem pidfile, aparece aviso
R2_TEST="$SBP/test-poda-on"
mkdir -p "$R2_TEST"
R2="$( ( cd "$R2_TEST" && node "$SRC/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
  let d=''; process.stdin.on('data', c => d += c).on('end', () => {
    try {
      const a = JSON.parse(d).find(x => x.item === 'poda');
      console.log(a ? a.nivel : 'ausente');
    } catch { console.log('erro'); }
  });
" )"
if [ "$R2" = "aviso" ]; then
  ok=$((ok+1)); echo "  ok   R2. sem poda.pid, aparece aviso"
else
  falhou=$((falhou+1)); echo "  FALHA R2. esperava aviso, veio: $R2"
fi

# R3: com pidfile mas porta morta, aparece ESPECIFICAMENTE aviso (não alerta)
R3_TEST="$SBP/test-poda-dead-port"
mkdir -p "$R3_TEST/.rainforest/poda"
printf '{"pid":99999,"port":19999}' > "$R3_TEST/.rainforest/poda/poda.pid"
R3="$( ( cd "$R3_TEST" && node "$SRC/scripts/saude.cjs" --json 2>/dev/null ) | node -e "
  let d=''; process.stdin.on('data', c => d += c).on('end', () => {
    try {
      const a = JSON.parse(d).find(x => x.item === 'poda');
      if (a && a.nivel === 'aviso') console.log('AVISO_OK');
      else if (a && a.nivel === 'alerta') console.log('ALERTA_NAO');
      else console.log('AUSENTE');
    } catch { console.log('ERRO'); }
  });
" )"
if [ "$R3" = "AVISO_OK" ]; then
  ok=$((ok+1)); echo "  ok   R3. porta morta vira aviso (nao alerta)"
elif [ "$R3" = "ALERTA_NAO" ]; then
  falhou=$((falhou+1)); echo "  FALHA R3. era aviso, virou alerta — teste deveria falhar na mutacao"
else
  falhou=$((falhou+1)); echo "  FALHA R3. esperava AVISO_OK, veio: $R3"
fi

# R4: exit deve ser 0 com aviso (R4 é redundante, mas mantém para compatibilidade)
( cd "$R3_TEST" && node "$SRC/scripts/saude.cjs" --json 2>/dev/null >/dev/null )
R4_EXIT=$?
if [ "$R3" = "AVISO_OK" ] && [ $R4_EXIT -eq 0 ]; then
  ok=$((ok+1)); echo "  ok   R4. exit=0 com aviso"
elif [ "$R3" = "AVISO_OK" ] && [ $R4_EXIT -ne 0 ]; then
  falhou=$((falhou+1)); echo "  FALHA R4. exit foi $R4_EXIT, deveria ser 0 com aviso"
else
  ok=$((ok+1)); echo "  ok   R4. (skip: dependente de R3)"
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
