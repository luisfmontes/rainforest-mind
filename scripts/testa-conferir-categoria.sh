#!/bin/bash
# @categoria: sensor
# Bateria do `scripts/conferir-categoria.cjs` — a trava que exige a marca
# `@categoria` (guia | sensor | dado) em toda peça de harness do plugin.
#
# O QUE PRECISA PROVAR:
#   1. o repositorio real, na base desta tarefa, passa limpo (exit 0), com as
#      41 pecas (19 hooks + 14 conferidores, este incluso + 8 vigias) e a
#      distribuicao 14 guia / 24 sensor / 3 dado;
#   2. peca REAL copiada para arvore temporaria, com a linha de marca apagada,
#      reprova (exit 1) e NOMEIA o caminho na saida;
#   3. peca REAL copiada com valor de marca fora do vocabulario (nem guia, nem
#      sensor, nem dado) reprova (exit 1) e nomeia o caminho e o valor;
#   4. MUTACAO: desligar a checagem de vocabulario tem que derrubar a bateria
#      (roda no fonte de producao, exit vermelho, reverte).
#
# Uso: bash scripts/testa-conferir-categoria.sh

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$RAIZ/scripts/conferir-categoria.cjs"
[ -f "$SCRIPT" ] || { echo "FALHA: nao achei $SCRIPT"; exit 1; }

ok=0; falhou=0; pulado=0
SB_POSIX="$(mktemp -d)"
# Caminho NATIVO para o Node no Windows resolver (ver testa-conferir-duplicacao.sh).
SB="$(cygpath -m "$SB_POSIX" 2>/dev/null || printf '%s' "$SB_POSIX")"
trap 'rm -rf "$SB_POSIX"' EXIT

saiu() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (exit $2, esperava $3)"; fi; }
tem()  { if printf '%s' "$2" | grep -qF "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3')"; fi; }

roda()   { node "$SCRIPT" "$@" 2>&1; }
codigo() { node "$SCRIPT" "$@" >/dev/null 2>&1; echo $?; }

# ---------------------------------------------------------------- helper
# Monta, em $1, uma copia da fatia da arvore que o conferidor varre: o
# manifesto de hooks, os .cjs que ele cita, todo scripts/conferir-*.cjs e todo
# vigias/*.md. Copiar so UM arquivo faria o conferidor acusar os outros 18~39
# como ausentes e confundiria qual caminho o caso esta testando.
montar_copia() {
  local destino="$1"
  mkdir -p "$destino/hooks" "$destino/scripts" "$destino/vigias"
  cp "$RAIZ/hooks/hooks.json" "$destino/hooks/hooks.json"
  cp "$RAIZ"/hooks/*.cjs "$destino/hooks/" 2>/dev/null
  cp "$RAIZ"/scripts/conferir-*.cjs "$destino/scripts/" 2>/dev/null
  cp "$RAIZ/scripts/observar.cjs" "$destino/scripts/observar.cjs"
  cp "$RAIZ"/vigias/*.md "$destino/vigias/" 2>/dev/null
}

echo "== 1. repositorio real na base — exit 0, 41 pecas, distribuicao 14/24/3 =="
S1="$(roda --raiz "$RAIZ")"
saiu "repositorio real passa (exit 0)" "$(codigo --raiz "$RAIZ")" "0"
tem  "conta as 41 pecas"               "$S1" "Total de peças varridas: 41"
N_GUIA="$(printf '%s' "$S1" | grep -cF '>  guia')"
N_SENSOR="$(printf '%s' "$S1" | grep -cF '>  sensor')"
N_DADO="$(printf '%s' "$S1" | grep -cF '>  dado')"
if [ "$N_GUIA" = "14" ] && [ "$N_SENSOR" = "24" ] && [ "$N_DADO" = "3" ]; then
  ok=$((ok+1)); echo "  ok   distribuicao 14 guia / 24 sensor / 3 dado confere"
else
  falhou=$((falhou+1)); echo "  FALHA distribuicao: guia=$N_GUIA sensor=$N_SENSOR dado=$N_DADO (esperava 14/24/3)"
fi

echo
echo "== 2. peca REAL sem a linha de marca — reprova nomeando o caminho =="
C2="$SB/c2"
montar_copia "$C2"
# hooks/gate-worktree.cjs e um guia real do conjunto — apaga so a linha
# '// @categoria: guia' da copia, deixando o resto do arquivo intacto.
sed -i '/^\/\/ @categoria: guia$/d' "$C2/hooks/gate-worktree.cjs"
if grep -q '@categoria' "$C2/hooks/gate-worktree.cjs"; then
  falhou=$((falhou+1)); echo "  FALHA nao consegui apagar a linha de marca da copia"
else
  ok=$((ok+1)); echo "  ok   linha de marca apagada da copia (controle)"
fi
S2="$(roda --raiz "$C2")"
saiu "arvore com peca sem marca reprova (exit 1)" "$(codigo --raiz "$C2")" "1"
tem  "nomeia hooks/gate-worktree.cjs na saida"     "$S2" "hooks/gate-worktree.cjs"
tem  "diz que esta sem marca"                      "$S2" "sem marca"

echo
echo "== 3. peca REAL com valor fora do vocabulario — reprova nomeando caminho e valor =="
C3="$SB/c3"
montar_copia "$C3"
sed -i 's/^<!-- @categoria: sensor -->$/<!-- @categoria: talvez -->/' "$C3/vigias/sentinela-foco.md"
if grep -q '@categoria: talvez' "$C3/vigias/sentinela-foco.md"; then
  ok=$((ok+1)); echo "  ok   valor trocado para fora do vocabulario na copia (controle)"
else
  falhou=$((falhou+1)); echo "  FALHA nao consegui trocar o valor da marca na copia"
fi
S3="$(roda --raiz "$C3")"
saiu "arvore com valor fora do vocabulario reprova (exit 1)" "$(codigo --raiz "$C3")" "1"
tem  "nomeia vigias/sentinela-foco.md na saida"               "$S3" "vigias/sentinela-foco.md"
tem  "cita o valor invalido"                                  "$S3" "talvez"

echo
echo "== 4. MUTACAO: desligar a checagem de vocabulario tem que derrubar a bateria =="
# Controle: a copia 2 (sem marca) tem que continuar reprovando antes da mutacao.
saiu "controle: copia 2 ainda reprova antes da mutacao" "$(codigo --raiz "$C2")" "1"
cp "$SCRIPT" "$SB/original.cjs"
node -e "
  const fs = require('fs');
  const p = process.argv[1];
  const s = fs.readFileSync(p, 'utf8');
  const alvo = 'else status = { ok: true, categoria: valor };';
  if (!s.includes(alvo)) { console.error('MUTACAO NAO APLICADA'); process.exit(1); }
  // Mutacao: toda peca vira 'ok', mesmo sem marca ou com valor invalido —
  // desliga exatamente o que este script existe para travar.
  const mutado = s.replace(
    'let status;\n    if (erro) status = { ok: false, motivo: erro };\n    else if (!valor) status = { ok: false, motivo: \'sem marca @categoria\' };\n    else if (!CATEGORIAS_VALIDAS.has(valor)) status = { ok: false, motivo: \`valor fora do vocabulário: \"\${valor}\"\` };\n    else status = { ok: true, categoria: valor };',
    'let status = { ok: true, categoria: valor || \'(mutado)\' };'
  );
  if (mutado === s) { console.error('MUTACAO NAO APLICADA (bloco nao encontrado)'); process.exit(1); }
  fs.writeFileSync(p, mutado);
" "$SCRIPT"
if [ $? -ne 0 ]; then
  falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"
else
  C4="$(codigo --raiz "$C2")"
  if [ "$C4" = "0" ]; then
    ok=$((ok+1)); echo "  ok   com a checagem sabotada, a copia sem marca passa (exit 0) — prova que a checagem era a trava"
  else
    falhou=$((falhou+1)); echo "  FALHA mutacao aplicada mas a copia ainda reprova (exit $C4) — a guarda nao mede o que devia"
  fi
fi
cp "$SB/original.cjs" "$SCRIPT"
saiu "restaurado, volta a reprovar a copia 2" "$(codigo --raiz "$C2")" "1"

echo
echo "== resultado: $ok ok, $falhou falha(s), $pulado pulado(s) =="
[ "$falhou" -eq 0 ] && [ "$pulado" -eq 0 ]
