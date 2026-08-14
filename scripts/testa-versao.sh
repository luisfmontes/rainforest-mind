#!/usr/bin/env bash
# A versao do plugin vive em MAIS DE UM lugar. Esta bateria existe para que os
# lugares nao divirjam em silencio.
#
# Por que ela existe, e a data importa: em 2026-08-14, ao integrar o PR #10, o
# `plugin.json` estava em 0.65.0 e o badge do README em 0.63.0 — desatualizado
# havia uma entrega inteira. Cinco rodadas de revisao independente passaram por
# cima disso sem ver, porque o criterio de pronto da tarefa que subia a versao
# era `grep '"version"' .claude-plugin/plugin.json`. Criterio que olha UM lugar
# nao prova consistencia entre lugares — ele prova que aquele lugar mudou, que e
# outra coisa. So apareceu quando o merge com a main deu conflito e obrigou
# alguem a olhar os dois.
#
# O desenho segue o mesmo principio ja usado em `scripts/orcamento.cjs`, que le
# o `ORCAMENTO_BYTES` de `hooks/lib/contexto-sessao.cjs` em vez de redigitar o
# 8000: quando um numero precisa existir em dois lugares, um deles e a FONTE e o
# outro se confere contra ela. Aqui a fonte e o `plugin.json`.
#
# Nao testa um script — testa um invariante do repositorio. Entra no laco do
# CONTRIBUTING.md:11 pela convencao de nome, como os demais.
set -u

cd "$(dirname "$0")/.." || exit 1

ok=0
falhou=0

igual() {
  if [ "$2" = "$3" ]; then
    ok=$((ok+1)); echo "  ok   $1"
  else
    falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"
  fi
}

echo "== versao do plugin coerente em todos os lugares =="
echo

FONTE=".claude-plugin/plugin.json"
VERSAO="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$FONTE" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"

echo "  fonte: $FONTE -> $VERSAO"
echo

# 1. A fonte tem que ser um semver de verdade. Sem isso as comparacoes abaixo
#    passariam comparando lixo com lixo.
if echo "$VERSAO" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  ok=$((ok+1)); echo "  ok   a versao da fonte e um semver ($VERSAO)"
else
  falhou=$((falhou+1)); echo "  FALHA a versao da fonte nao e um semver (veio '$VERSAO')"
fi

# 2. TODO semver que aparece no README tem que ser a versao corrente.
#    A varredura e cega de proposito: ela nao sabe quantas vezes a versao
#    aparece nem onde, entao um badge novo, ou um trecho de texto que cite a
#    versao, entra na checagem sozinho. Foi a ausencia disso que deixou o badge
#    envelhecer.
DIVERGENTES="$(grep -on '[0-9]\+\.[0-9]\+\.[0-9]\+' README.md | grep -v ":${VERSAO}$" || true)"
# `grep -c` conta LINHAS com ocorrencia, nao ocorrencias — e o badge tem duas na
# mesma linha (o src da imagem e o alt). Contar por linha diria "1 semver" com
# dois presentes, que e justamente o tipo de numero que engana quem le a saida.
QUANTOS="$(grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' README.md | wc -l | tr -d ' ')"

if [ -z "$DIVERGENTES" ]; then
  ok=$((ok+1)); echo "  ok   os $QUANTOS semver(s) do README estao todos em $VERSAO"
else
  falhou=$((falhou+1))
  echo "  FALHA semver no README divergindo de $VERSAO:"
  echo "$DIVERGENTES" | sed 's/^/         linha /'
fi

# 3. O badge tem que existir. Sem esta assercao, apagar o badge faria a checagem
#    2 passar por vacuidade — zero divergencia porque zero ocorrencia. Gate que
#    passa por ausencia de dado e a armadilha que ja mordeu este repo antes.
BADGE="$(grep -c "badge/vers%C3%A3o-${VERSAO}-" README.md | tr -d ' \r\n' || echo 0)"
igual "o badge de versao existe no README e aponta para $VERSAO" "$BADGE" "1"

# 4. Se o marketplace.json declarar versao um dia, ela entra na conta sozinha.
if [ -f .claude-plugin/marketplace.json ]; then
  MKT="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' .claude-plugin/marketplace.json | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  if [ -n "$MKT" ]; then
    igual "marketplace.json na mesma versao" "$MKT" "$VERSAO"
  else
    ok=$((ok+1)); echo "  ok   marketplace.json nao declara versao (nada a conferir)"
  fi
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
