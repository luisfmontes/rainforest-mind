#!/bin/bash
# Bateria de testes do scripts/lib/impressao-falha.cjs
#
# Cobre: fixture real (30/09), persistente sem log, RESOLVIDO zera so a propria vigia,
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

# roda(<dir de vigias>, <agora ISO>) -> JSON [[vigia,rotulo,n,ultima],...]
roda() {
  RFM_VIGIAS_DIR="$1" LIB="$LIB" AGORA="$2" node -e "
    const l = require(process.env.LIB);
    console.log(JSON.stringify(l.falhasRecorrentes(new Date(process.env.AGORA)).map(r => [r.vigia, r.rotulo, r.n, r.ultima])));
  "
}
# pasta com um ERROS.md montado a partir do stdin
pasta() { mkdir -p "$SB/$1"; cat > "$SB/$1/ERROS.md"; }

echo ""
echo "(1) real-30-09"
igual "real-30-09" "$(roda "$FIX" "2026-09-30T12:00:00")" '[["sentinela-foco","intermitente",5,"2026-09-25"]]'

echo ""
echo "(2) duas-seguidas-sem-log"
pasta duas <<'EOF'
- 2026-09-28 08:00 [vigia-x]: falhou exit 2
- 2026-09-29 08:00 [vigia-x]: falhou exit 2
EOF
igual "duas-seguidas-sem-log: persistente x2" "$(roda "$SB/duas" "2026-09-30T12:00:00")" '[["vigia-x","persistente",2,"2026-09-29"]]'

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
igual "conferido-na-janela-principal-nao-zera" "$(roda "$SB/conferido" "2026-09-30T12:00:00")" '[["vigia-x","persistente",2,"2026-09-28"]]'

echo ""
echo "(5) normalizacao-colide"
pasta colide <<'EOF'
- 2026-09-27 08:00 [vigia-x]: falhou em C:\Pasta\um\a.db (exit 2) id 3f9a1c77b2d4e8
- 2026-09-28 08:00 [vigia-x]: falhou em D:/outra/coisa/b.db (exit 17) id 9a8b7c6d5e4f3a
EOF
igual "normalizacao-colide" "$(roda "$SB/colide" "2026-09-30T12:00:00")" '[["vigia-x","persistente",2,"2026-09-28"]]'

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
echo "Placar: $ok ok, $falhou falha(s)"
[ "$falhou" -eq 0 ]
