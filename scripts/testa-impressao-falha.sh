#!/bin/bash
# Bateria de testes do scripts/lib/impressao-falha.cjs
#
# Cobre: fixture real (30/09), rotulo unico recorrente (n/desde/ultima), log ignorado, RESOLVIDO zera so a propria vigia,
#        normalizacao colide, uma ocorrencia so nao aparece, sem ERROS.md.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

export PATH="/c/Program Files/nodejs:/usr/bin:/usr/local/bin:/c/Windows/System32:/c/Program Files/PowerShell:$PATH"

ok=0; falhou=0
igual() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1: '$2' != '$3'"; fi; }

LIB="$SRC/scripts/lib/impressao-falha.cjs"
FIX="$SRC/scripts/fixtures/impressao-falha"

# roda(<dir de vigias>, <agora ISO>) -> JSON [[vigia,rotulo,n,desde,ultima],...]
roda() {
  RFM_VIGIAS_DIR="$1" LIB="$LIB" AGORA="$2" node -e "
    const l = require(process.env.LIB);
    console.log(JSON.stringify(l.falhasRecorrentes(new Date(process.env.AGORA)).map(r => [r.vigia, r.rotulo, r.n, r.desde, r.ultima])));
  "
}
# pasta com um ERROS.md montado a partir do stdin
pasta() { mkdir -p "$SB/$1"; cat > "$SB/$1/ERROS.md"; }

echo ""
echo "(1) real-30-09"
igual "real-30-09" "$(roda "$FIX" "2026-09-30T12:00:00")" '[["sentinela-foco","recorrente",5,"2026-09-11","2026-09-25"]]'

echo ""
echo "(2) duas-seguidas-sem-log"
pasta duas <<'EOF'
- 2026-09-28 08:00 [vigia-x]: falhou exit 2
- 2026-09-29 08:00 [vigia-x]: falhou exit 2
EOF
igual "duas-seguidas-sem-log: recorrente x2" "$(roda "$SB/duas" "2026-09-30T12:00:00")" '[["vigia-x","recorrente",2,"2026-09-28","2026-09-29"]]'

echo ""
echo "(3) resolvido-da-vigia-zera"
pasta resolvido <<'EOF'
- 2026-09-27 08:00 [vigia-x]: falhou exit 2
- 2026-09-28 08:00 [vigia-x]: falhou exit 2
- 2026-09-28 09:00 [vigia-x]: RESOLVIDO. causa achada
- 2026-09-29 08:00 [vigia-x]: falhou exit 2
EOF
igual "resolvido-da-vigia-zera" "$(roda "$SB/resolvido" "2026-09-30T12:00:00")" '[]'

echo ""
echo "(4) conferido-na-janela-principal-nao-zera"
pasta conferido <<'EOF'
- 2026-09-27 08:00 [vigia-x]: falhou exit 2
- 2026-09-28 08:00 [vigia-x]: falhou exit 2
- 2026-09-28 09:00 [conferido na janela principal]: RESOLVIDO. nao e da vigia
EOF
igual "conferido-na-janela-principal-nao-zera" "$(roda "$SB/conferido" "2026-09-30T12:00:00")" '[["vigia-x","recorrente",2,"2026-09-27","2026-09-28"]]'

echo ""
echo "(5) normalizacao-colide"
pasta colide <<'EOF'
- 2026-09-27 08:00 [vigia-x]: falhou em C:\Pasta\um\a.db (exit 2) id 3f9a1c77b2d4e8
- 2026-09-28 08:00 [vigia-x]: falhou em D:/outra/coisa/b.db (exit 17) id 9a8b7c6d5e4f3a
EOF
igual "normalizacao-colide" "$(roda "$SB/colide" "2026-09-30T12:00:00")" '[["vigia-x","recorrente",2,"2026-09-27","2026-09-28"]]'

echo ""
echo "(6) uma-so-nao-aparece"
pasta uma <<'EOF'
- 2026-09-28 08:00 [vigia-x]: falhou exit 2
EOF
igual "uma-so-nao-aparece" "$(roda "$SB/uma" "2026-09-30T12:00:00")" '[]'

echo ""
echo "(7) sem-erros-md"
mkdir -p "$SB/vazia"
igual "sem-erros-md" "$(roda "$SB/vazia" "2026-09-30T12:00:00" 2>&1)" '[]'

echo ""
echo "(8) recorrente-x2-consecutivas: duas ocorrencias seguidas"
pasta comlog <<'EOF2'
- 2026-09-28 08:01 [vigia-x]: falhou exit 2
- 2026-09-29 08:01 [vigia-x]: falhou exit 2
EOF2
igual "recorrente-x2-consecutivas" "$(roda "$SB/comlog" "2026-09-30T12:00:00")" '[["vigia-x","recorrente",2,"2026-09-28","2026-09-29"]]'

echo ""
echo "(9) so-ERROS.md-vale: caixa de areia sem RFM_VIGIAS_DIR le o ERROS.md ao lado da lib"
mkdir -p "$SB/caixa/scripts/lib" "$SB/caixa/vigias"
cp "$LIB" "$SB/caixa/scripts/lib/impressao-falha.cjs"
printf -- '- 2026-09-27 08:01 [vigia-x]: falhou exit 2
- 2026-09-28 08:01 [vigia-x]: falhou exit 2
' > "$SB/caixa/vigias/ERROS.md"
caixa="$(env -u RFM_VIGIAS_DIR LIB="$SB/caixa/scripts/lib/impressao-falha.cjs" node -e "
  const l = require(process.env.LIB);
  console.log(JSON.stringify(l.falhasRecorrentes(new Date('2026-09-30T12:00:00')).map(r => [r.vigia, r.rotulo, r.n, r.desde, r.ultima])));
")"
igual "so-ERROS.md-vale" "$caixa" '[["vigia-x","recorrente",2,"2026-09-27","2026-09-28"]]'

echo ""
echo "(10) erro-antes-do-cabecalho"
pasta antes <<'EOF2'
- 2026-09-26 08:00 [vigia-x]: sem destino de envio
- 2026-09-27 08:00 [vigia-x]: sem destino de envio
- 2026-09-28 08:00 [vigia-x]: sem destino de envio
- 2026-09-29 08:00 [vigia-x]: sem destino de envio
EOF2
igual "erro-antes-do-cabecalho: recorrente x4" "$(roda "$SB/antes" "2026-09-30T12:00:00")" '[["vigia-x","recorrente",4,"2026-09-26","2026-09-29"]]'

echo ""
echo "(11) espalhadas-na-janela: 20/09 e 29/09, mesma impressao, dias no meio sem falha"
pasta maisnovo <<'EOF2'
- 2026-09-20 08:10 [vigia-x]: falhou exit 2
- 2026-09-29 08:10 [vigia-x]: falhou exit 2
EOF2
igual "espalhadas-na-janela" "$(roda "$SB/maisnovo" "2026-09-30T12:00:00")" '[["vigia-x","recorrente",2,"2026-09-20","2026-09-29"]]'

echo ""
echo "(12) log-e-ignorado: log com ronda limpa entre as ocorrencias nao muda a saida"
pasta logign <<'EOF2'
- 2026-09-26 08:00 [vigia-x]: sem destino de envio
- 2026-09-29 08:00 [vigia-x]: sem destino de envio
EOF2
antes_log="$(roda "$SB/logign" "2026-09-30T12:00:00")"
printf '=== 2026-09-26 08:00 ===
=== 2026-09-27 08:00 ===
=== 2026-09-28 08:00 ===
=== 2026-09-29 08:00 ===
' > "$SB/logign/log-vigia-x.txt"
depois_log="$(roda "$SB/logign" "2026-09-30T12:00:00")"
igual "log-e-ignorado: sem log" "$antes_log" '[["vigia-x","recorrente",2,"2026-09-26","2026-09-29"]]'
igual "log-e-ignorado: com log de ronda limpa" "$depois_log" "$antes_log"

echo ""
echo "Placar: $ok ok, $falhou falha(s)"
[ "$falhou" -eq 0 ]
