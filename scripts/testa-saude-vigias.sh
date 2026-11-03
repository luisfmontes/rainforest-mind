#!/bin/bash
# Bateria do estado das tarefas de vigia em scripts/saude.cjs (tarefasDeVigia + checarVigias).
#
# O defeito que ela pega: tarefasDeVigia() so lia NextRunTime. Tarefa Disabled tem
# NextRunTime preenchido, entao o /saude dizia "todas com proxima execucao" com as
# quatro desabilitadas. Aqui o PowerShell e um executavel falso (so em bateria,
# RFM_TEST=1) que entrega cenarios prontos. O que se afirma e a SAIDA do saude.cjs
# real, nao o parser isolado.
#
# Sandbox proprio em mktemp: nada aqui toca o Agendador. O unico PowerShell real
# que roda e o do caso "escape", e ele so le.

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

# Caminho para o node no Windows: o Git Bash nao converte caminho que vai por variavel de ambiente.
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

RAIZ="$SBP/raiz"
mkdir -p "$RAIZ/scripts/lib" "$RAIZ/hooks/lib"
cp "$SRC/scripts/saude.cjs" "$RAIZ/scripts/saude.cjs"
cp "$SRC/hooks/lib/resolver-executavel.cjs" "$RAIZ/hooks/lib/resolver-executavel.cjs"
cp "$SRC/scripts/lib/impressao-falha.cjs" "$RAIZ/scripts/lib/impressao-falha.cjs"
# setup.cjs falso sai 0: o toggle de vigias fica ligado.
printf 'process.exit(0);\n' > "$RAIZ/scripts/setup.cjs"

# Executavel falso do PowerShell. Grava o marcador (se houver) ao rodar, e so
# assim o caso "escape" prova que o falso NAO foi chamado. Se a consulta pedir
# $_.State, devolve nome, proxima e estado; se nao pedir, devolve so nome e proxima.
cat > "$RAIZ/ps-falso.cjs" <<'JS'
const fs = require('fs');
if (process.env.RFM_FALSO_MARCADOR) fs.writeFileSync(process.env.RFM_FALSO_MARCADOR, 'chamado\n');
const script = process.argv[process.argv.length - 1];
const pedeEstado = script.includes('$_.State');
const cenario = JSON.parse(fs.readFileSync(process.env.RFM_FALSO_CENARIO, 'utf8'));
for (const t of cenario) {
  process.stdout.write(pedeEstado ? `${t.nome}\t${t.proxima}\t${t.estado}\n` : `${t.nome}\t${t.proxima}\n`);
}
JS

PSW="$(w "$RAIZ/ps-falso.cjs")"
MARC_W="$(w "$SBP/marcador")"

# $1 = RFM_TEST ("1" ou vazio); $2 = cenario JSON (caminho POSIX).
saude() {
  RFM_TEST="$1" RFM_VIGIAS_PS="$PSW" RFM_FALSO_CENARIO="$(w "$2")" RFM_FALSO_MARCADOR="$MARC_W" \
    node "$RAIZ/scripts/saude.cjs" 2>&1
}

ok=0
falhou=0

echo "== desabilitada com proxima preenchida =="
cat > "$SBP/c1.json" <<'JSON'
[{"nome":"sentinela-foco","proxima":"2026-11-03T09:00:00","estado":"Disabled"}]
JSON
OUT="$(saude 1 "$SBP/c1.json")"
if printf '%s\n' "$OUT" | grep -qF 'aviso vigias' \
   && printf '%s\n' "$OUT" | grep -qF '1 de 1 tarefa(s) desabilitada(s): sentinela-foco' \
   && printf '%s\n' "$OUT" | grep -qF -- '--desligar vigias' \
   && ! printf '%s\n' "$OUT" | grep -qF 'todas com proxima execucao'; then
  ok=$((ok+1)); echo "  ok   C1. desabilitada com proxima: aviso vigias, nome, --desligar vigias, sem 'todas com proxima execucao'"
else
  falhou=$((falhou+1)); echo "  FALHA C1: esperava aviso vigias com sentinela-foco e sem 'todas com proxima execucao'. Saida:"; printf '%s\n' "$OUT" | grep -A1 'vigias'
fi

echo "== ready com proxima =="
cat > "$SBP/c2.json" <<'JSON'
[{"nome":"batedor-repos","proxima":"2026-11-04T08:00:00","estado":"Ready"}]
JSON
OUT="$(saude 1 "$SBP/c2.json")"
if printf '%s\n' "$OUT" | grep -qF 'todas com proxima execucao' \
   && ! printf '%s\n' "$OUT" | grep -qF 'aviso vigias'; then
  ok=$((ok+1)); echo "  ok   C2. ready com proxima: 'todas com proxima execucao' e nenhum aviso vigias"
else
  falhou=$((falhou+1)); echo "  FALHA C2: esperava 'todas com proxima execucao' e nenhum aviso vigias. Saida:"; printf '%s\n' "$OUT" | grep -A1 'vigias'
fi

echo "== ready sem proxima =="
cat > "$SBP/c3.json" <<'JSON'
[{"nome":"morta-x","proxima":"","estado":"Ready"}]
JSON
OUT="$(saude 1 "$SBP/c3.json")"
if printf '%s\n' "$OUT" | grep -qF 'ALERTA  vigias' \
   && printf '%s\n' "$OUT" | grep -qF 'morta-x' \
   && ! printf '%s\n' "$OUT" | grep -qF 'desabilitada'; then
  ok=$((ok+1)); echo "  ok   C3. ready sem proxima: ALERTA vigias com morta-x, sem 'desabilitada'"
else
  falhou=$((falhou+1)); echo "  FALHA C3: esperava ALERTA vigias com morta-x e sem 'desabilitada'. Saida:"; printf '%s\n' "$OUT" | grep -A1 'vigias'
fi

echo "== mistura: desabilitada com proxima, ready com proxima, ready sem proxima =="
cat > "$SBP/c4.json" <<'JSON'
[{"nome":"dis-y","proxima":"2026-11-03T09:00:00","estado":"Disabled"},
 {"nome":"viva-z","proxima":"2026-11-04T08:00:00","estado":"Ready"},
 {"nome":"morta-w","proxima":"","estado":"Ready"}]
JSON
OUT="$(saude 1 "$SBP/c4.json")"
ALERTA_L="$(printf '%s\n' "$OUT" | grep -F 'ALERTA  vigias')"
AVISO_L="$(printf '%s\n' "$OUT" | grep -F 'aviso vigias')"
if printf '%s\n' "$ALERTA_L" | grep -qF 'morta-w' \
   && ! printf '%s\n' "$ALERTA_L" | grep -qF 'dis-y' \
   && printf '%s\n' "$AVISO_L" | grep -qF '1 de 3 tarefa(s) desabilitada(s): dis-y' \
   && ! printf '%s\n' "$AVISO_L" | grep -qF 'morta-w' \
   && ! printf '%s\n' "$OUT" | grep -qF 'todas com proxima execucao'; then
  ok=$((ok+1)); echo "  ok   C4. mistura: alerta so com morta-w, aviso so com dis-y, sem 'todas com proxima execucao'"
else
  falhou=$((falhou+1)); echo "  FALHA C4: esperava alerta so com morta-w e aviso so com dis-y. Saida:"; printf '%s\n' "$OUT" | grep -A1 'vigias'
fi

echo "== nome com tab: a<TAB>b, Ready, com data =="
cat > "$SBP/c5.json" <<'JSON'
[{"nome":"a\tb","proxima":"2026-11-04T08:00:00","estado":"Ready"}]
JSON
OUT="$(saude 1 "$SBP/c5.json")"
if printf '%s\n' "$OUT" | grep -qF 'todas com proxima execucao' \
   && ! printf '%s\n' "$OUT" | grep -qF 'ALERTA  vigias' \
   && ! printf '%s\n' "$OUT" | grep -qF 'aviso vigias'; then
  ok=$((ok+1)); echo "  ok   C5. nome com tab: nao vira morta nem desabilitada"
else
  falhou=$((falhou+1)); echo "  FALHA C5: nome com tab nao devia virar alerta nem aviso. Saida:"; printf '%s\n' "$OUT" | grep -A1 'vigias'
fi

echo "== escape so em bateria: sem RFM_TEST=1 o falso NAO e chamado =="
cat > "$SBP/c6.json" <<'JSON'
[{"nome":"batedor-repos","proxima":"2026-11-04T08:00:00","estado":"Ready"}]
JSON
# Controle positivo: com RFM_TEST=1 o falso roda e grava o marcador.
saude 1 "$SBP/c6.json" >/dev/null
CONTROLE=nao; [ -e "$SBP/marcador" ] && CONTROLE=sim
rm -f "$SBP/marcador"
# Sem RFM_TEST=1: o caminho do PowerShell real. O marcador NAO pode aparecer.
saude "" "$SBP/c6.json" >/dev/null
ESCAPE=sim; [ ! -e "$SBP/marcador" ] && ESCAPE=nao
if [ "$CONTROLE" = sim ] && [ "$ESCAPE" = nao ]; then
  ok=$((ok+1)); echo "  ok   C6. escape: com RFM_TEST=1 o falso roda (controle=$CONTROLE); sem ele nao roda (chamado=$ESCAPE)"
else
  falhou=$((falhou+1)); echo "  FALHA C6: esperava controle=sim e chamado=nao, veio controle=$CONTROLE chamado=$ESCAPE"
fi

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
