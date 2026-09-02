#!/bin/bash
# Bateria do modo `lint` de `scripts/portoes.cjs`.
# Uso: bash scripts/testa-portoes-lint.sh
#
# Tarefa 2 do plano `docs/rainforest/planos/2026-09-02-fluxo-6-portoes.md`.
#
# O QUE ESTA BATERIA EXISTE PARA IMPEDIR. O `rodar` prova que o oraculo declarado
# rodou e devolveu o prometido — e para nisso. Ele nao tem como saber se o
# oraculo mede alguma coisa: `CHECK: echo ok` / `ESPERA: ok` satisfaz o `rodar`
# perfeitamente e nao prova nada. O `lint` e' a unica peca que audita a AUTORIA
# do portao, e portanto a unica cujo silencio e' perigoso.
#
# Por isso quase todo caso aqui e' NEGATIVO: cada detector tem um fixture que ele
# TEM de reprovar. Um detector so visto passando nao foi verificado — e um
# detector que parou de detectar e' indistinguivel de um arquivo limpo.
#
# Os fixtures de aviso aparecem DUAS vezes: sem `--strict` (exit 0, aviso
# impresso) e com `--strict` (exit 1). E' o par que prova que a flag faz algo —
# testar so um dos lados deixaria `--strict` livre para ser no-op.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$RAIZ/scripts/portoes.cjs"
FIX="$RAIZ/test/fixtures/portoes"
FIXN="$(cygpath -m "$FIX" 2>/dev/null || printf '%s' "$FIX")"

for f in "$P" "$FIX/portoes-ok.md" "$FIX/portoes-echo.md" \
         "$FIX/portoes-titulo-atividade.md" "$FIX/portoes-espera-trivial.md" \
         "$FIX/portoes-espera-substring-erro.md" "$FIX/portoes-espera-numero-cru.md" \
         "$FIX/portoes-grep.md" "$FIX/portoes-contagem-zerada.md" "$FIX/portoes-sentinela.md" \
         "$FIX/portoes-malformado-id-duplicado.md"; do
  [ -f "$f" ] || { echo "FALHA: nao achei $f"; exit 1; }
done

ok=0; falhou=0
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT

# `caso <nome> <exit-esperado> <arquivo> [trecho] [--strict]`
caso() {
  local nome="$1" esperado="$2" arq="$3" trecho="${4:-}" flag="${5:-}"
  local saida codigo
  saida="$(cd "$RAIZ" && node "$P" lint "$arq" $flag 2>&1)"; codigo=$?
  if [ "$codigo" -ne "$esperado" ]; then
    echo "  FALHA $nome: exit $codigo, esperava $esperado"
    echo "    saida: $(printf '%s' "$saida" | tr '\n' '|')"
    falhou=$((falhou+1)); return
  fi
  if [ -n "$trecho" ] && ! printf '%s' "$saida" | grep -q "$trecho"; then
    echo "  FALHA $nome: saida nao contem '$trecho'"
    echo "    saida: $(printf '%s' "$saida" | tr '\n' '|')"
    falhou=$((falhou+1)); return
  fi
  echo "  ok   $nome"
  ok=$((ok+1))
}

echo "== o caminho limpo =="
caso "L1. fixture bem autorado passa" 0 "$FIX/portoes-ok.md" "LINT OK"
caso "L2. fixture bem autorado passa tambem com --strict" 0 "$FIX/portoes-ok.md" "LINT OK" "--strict"

echo "== ERRO: reprova com ou sem --strict =="
caso "L3. CHECK de saida fixa (echo) reprova" 1 "$FIX/portoes-echo.md" "saída fixa"
caso "L4. ...e reprova tambem com --strict" 1 "$FIX/portoes-echo.md" "saída fixa" "--strict"
caso "L5. titulo que nomeia atividade reprova" 1 "$FIX/portoes-titulo-atividade.md" "ATIVIDADE"
caso "L6. ESPERA trivial reprova" 1 "$FIX/portoes-espera-trivial.md" "trivial"

echo "== AVISO: passa sozinho, reprova com --strict =="
caso "L7. ESPERA com termo de erro passa sem --strict" 0 \
     "$FIX/portoes-espera-substring-erro.md" "AVISO"
caso "L8. ...e reprova com --strict" 1 \
     "$FIX/portoes-espera-substring-erro.md" "LINT REPROVADO" "--strict"
caso "L9. ESPERA numero solto passa sem --strict" 0 \
     "$FIX/portoes-espera-numero-cru.md" "sem rótulo"
caso "L10. ...e reprova com --strict" 1 \
     "$FIX/portoes-espera-numero-cru.md" "LINT REPROVADO" "--strict"
caso "L11. CHECK com ferramenta Unix passa sem --strict" 0 \
     "$FIX/portoes-grep.md" "ferramenta Unix"
caso "L12. ...e reprova com --strict" 1 \
     "$FIX/portoes-grep.md" "LINT REPROVADO" "--strict"

echo "== contagem ZERADA nao e mensagem de erro =="
# Achado ao submeter os portoes DESTE fluxo ao proprio lint: o formato canonico
# de bateria desta casa e' `== resultado: N ok, 0 falha(s) ==`, e o detector de
# termo de erro disparava contra ele — quatro avisos nos quatro portoes que
# apontam para uma bateria. Detector que acusa o padrao CORRETO do repositorio
# nao e' rigoroso: e' ruido, e a primeira coisa que ruido ensina e' a ignorar o
# detector. `0 falha(s)` nao e' mensagem de erro, e' AFIRMACAO DE AUSENCIA dele.
caso "L16. '0 falha(s)' nao levanta aviso — e afirmacao de ausencia" 0 \
     "$FIX/portoes-contagem-zerada.md" "0 aviso"
caso "L17. ...nem mesmo com --strict" 0 \
     "$FIX/portoes-contagem-zerada.md" "LINT OK" "--strict"

echo "== malformado nao vira veredito de lint =="
# exit 2 e' "nao consegui ler", nao "reprovei". Confundir os dois foi o modo de
# falha do guarda do Issue #142: responder com confianca sobre o que nao mediu.
caso "L13. arquivo malformado sai 2, nao 1" 2 \
     "$FIX/portoes-malformado-id-duplicado.md" "duplicado"

echo "== o lint NUNCA executa CHECK =="
ALVO="$(cygpath -m "$S" 2>/dev/null || printf '%s' "$S")/sentinela-lint"
sed "s|SENTINELA_ALVO|$ALVO|" "$FIX/portoes-sentinela.md" > "$S/sentinela.md"
rm -f "$ALVO"
(cd "$RAIZ" && node "$P" lint "$S/sentinela.md" >/dev/null 2>&1)
if [ -e "$ALVO" ]; then
  echo "  FALHA L14: A SENTINELA EXISTE — o \`lint\` executou o CHECK do portao."
  falhou=$((falhou+1))
else
  echo "  ok   L14. lint nao criou a sentinela — nao executou o CHECK"
  ok=$((ok+1))
fi

# Controle honesto: node->node, a mesma ponte que um lint defeituoso usaria.
# Ver o comentario equivalente em testa-portoes-parser.sh — com bash->node o
# controle exercita a ponta que funciona e nao prova nada.
rm -f "$ALVO"
(cd "$RAIZ" && node -e "
  require('child_process').spawnSync(process.execPath,
    ['$FIXN/scripts/sentinela.cjs', '$ALVO'], {shell: false});
" >/dev/null 2>&1)
if [ -e "$ALVO" ]; then
  echo "  ok   L15. o script de sentinela realmente cria o arquivo (L14 mede algo)"
  ok=$((ok+1))
else
  echo "  FALHA L15: sentinela nao criada pela ponte node->node — L14 e tautologico"
  falhou=$((falhou+1))
fi

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ] || exit 1
