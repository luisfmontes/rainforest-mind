#!/bin/bash
# Nenhum script ENTREGUE pode ter caminho de home com nome de pessoa chumbado.
#
# POR QUE ESTA BATERIA EXISTE. Em 2026-09-02, ao varrer a arvore antes de tornar
# o repositorio publico, quatro scripts entregues tinham o home do autor escrito
# no codigo:
#
#   statusline/statusline-jornada.sh   sem variavel de escape NENHUMA
#   statusline/statusline-command.sh   o nome como DEFAULT do CACHE_ROOT
#   scripts/instalar-statusline.sh     o nome como DEFAULT do CACHE_ROOT
#   scripts/atualizar-cli.sh           o nome como DEFAULT do PACOTE
#
# O checklist de ir a publico, escrito em 2026-08-28, tinha visto isso e
# classificou como "nada grave (sem segredo, sem e-mail pessoal)". A avaliacao
# estava certa sobre PRIVACIDADE e errada sobre FUNCIONAMENTO: na maquina de
# qualquer outra pessoa o glob nao casa, e o `statusline-jornada.sh` — que nao
# tinha escape — saia 0 em silencio. Statusline que nao aparece e a falha mais
# facil de nao notar que existe: nada quebra, so nao aparece.
#
# Nome chumbado no DEFAULT e pior que nome chumbado sem escape, e vale dizer por
# que: com escape, o script PARECE configuravel. A variavel existe, o comentario
# diz "substituivel", e quem le acredita. Mas o default e o caminho que roda em
# 100% das instalacoes que nao souberem que precisam configurar — ou seja, todas.
#
# O QUE ESTA BATERIA NAO E: uma checagem de privacidade. O nome do autor esta na
# linha de autor de todos os commits e vai continuar la — o repositorio e dele e
# assinado por ele. Isto aqui e sobre o codigo funcionar na maquina dos outros.
# Por isso ela olha CODIGO ENTREGUE, e nao docs: prosa com caminho de exemplo em
# `docs/` nao roda em lugar nenhum.
#
# NENHUM CAMINHO LITERAL NESTE ARQUIVO. O gate de publicacao barrou a primeira
# versao dele — o comentario acima citava o caminho de verdade, e os fixtures
# traziam a forma completa. Estava certo: arquivo versionado nao ganha excecao
# por ser o teste do proprio assunto. Os fixtures sao montados em tempo de
# execucao a partir de pedacos, e por isso a forma completa nao existe em disco.
set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SRC" || exit 1

ok=0; falhou=0

# Montado, nunca escrito: `U s e r s` inteiro seguido de barra e nome e
# exatamente o que este arquivo nao pode conter.
SEG="Us""ers"

# Nomes que NAO sao pessoa: placeholder, usuario de CI, fixture de teste.
PLACEHOLDERS='<user>|<usuario>|<nome>|<home>|Fulano|RUNNER~1|runneradmin|runner|USUARIO|usuario|test|teste|%USERNAME%|\$USER|\$\{USER\}'

PADRAO="([A-Za-z]:[\\\\/]|/[a-z]/)[Uu]${SEG:1}[\\\\/][A-Za-z0-9._-]+"
ISENTO="[Uu]${SEG:1}[\\\\/]($PLACEHOLDERS)"

# So codigo que EXECUTA. `docs/` e `relatorios/` ficam de fora de proposito:
# caminho em prosa e ilustracao, nao comportamento.
ALVOS=$(git ls-files 'scripts/*.sh' 'scripts/*.cjs' 'scripts/*.py' \
                     'statusline/*' 'hooks/*.cjs' 'hooks/*.sh' \
                     'vigias/*.ps1' 'vigias/*.js' 2>/dev/null)

echo "== nenhum caminho de home com nome de pessoa em script entregue =="

achados=""
for f in $ALVOS; do
  [ -f "$f" ] || continue
  # Baterias podem conter nome em FIXTURE — elas se declaram no proprio nome.
  case "$f" in
    scripts/testa-*|hooks/testa-*) continue;;
  esac
  linhas=$(grep -nE "$PADRAO" "$f" 2>/dev/null || true)
  [ -n "$linhas" ] || continue
  restante=$(printf '%s\n' "$linhas" | grep -vE "$ISENTO" || true)
  [ -n "$restante" ] || continue
  achados="$achados
$f: $(printf '%s' "$restante" | head -2 | cut -c1-40)..."
done

if [ -z "$achados" ]; then
  ok=$((ok+1)); echo "  ok    nenhum script entregue tem nome de pessoa em caminho"
else
  falhou=$((falhou+1))
  echo "  FALHA script entregue com caminho de home chumbado:$achados"
  echo "        derive o home: \$(cd ~ 2>/dev/null && pwd || echo \"\$HOME\")"
  echo "        o idioma ja esta em scripts/instalar-statusline.sh"
fi

# O outro sentido, para a trava nao ser decorativa: um caminho PLANTADO tem de
# acender. Sem isto a checagem acima passaria igual com o grep quebrado — que e
# o defeito que este repositorio ja catalogou cinco vezes em 2026-09-02.
CAIXA="$(mktemp -d)"
printf 'CACHE="/c/%s/Fulaninho/.claude/plugins"\n' "$SEG" > "$CAIXA/plantado.sh"
plantado=$(grep -nE "$PADRAO" "$CAIXA/plantado.sh" | grep -vE "$ISENTO" || true)
if [ -n "$plantado" ]; then
  ok=$((ok+1)); echo "  ok    e a trava ACENDE num caminho plantado (nao e decorativa)"
else
  falhou=$((falhou+1)); echo "  FALHA a trava nao acendeu no caminho plantado — o padrao nao mede nada"
fi

# E o contrario: placeholder NAO pode acender, senao a trava vira ruido e o
# proximo a mexer aqui aprende a ignorar a saida.
printf 'CACHE="/c/%s/<user>/.claude/plugins"\n' "$SEG" > "$CAIXA/placeholder.sh"
ph=$(grep -nE "$PADRAO" "$CAIXA/placeholder.sh" | grep -vE "$ISENTO" || true)
if [ -z "$ph" ]; then
  ok=$((ok+1)); echo "  ok    e NAO acende em placeholder"
else
  falhou=$((falhou+1)); echo "  FALHA a trava acendeu num placeholder — falso positivo vira ruido"
fi
rm -rf "$CAIXA"

# Os quatro scripts do incidente resolvem o home em tempo de execucao. Nao basta
# nao ter o nome: tem de ter de onde tirar o certo.
echo
echo "== os quatro do incidente derivam o home de quem roda =="
for f in statusline/statusline-jornada.sh statusline/statusline-command.sh \
         scripts/instalar-statusline.sh scripts/atualizar-cli.sh; do
  if grep -q 'cd ~ 2>/dev/null && pwd' "$f"; then
    ok=$((ok+1)); echo "  ok    $f deriva o home"
  else
    falhou=$((falhou+1)); echo "  FALHA $f nao deriva o home de quem roda"
  fi
done

# E o `statusline-jornada.sh` ganhou a variavel de escape que nunca teve.
if grep -q 'RAINFOREST_STATUSLINE_CACHE' statusline/statusline-jornada.sh; then
  ok=$((ok+1)); echo "  ok    statusline-jornada.sh tem variavel de escape"
else
  falhou=$((falhou+1)); echo "  FALHA statusline-jornada.sh continua sem variavel de escape"
fi

echo
echo "-----------------------------------------"
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
