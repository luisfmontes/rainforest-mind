#!/usr/bin/env bash
# Tarefa 4 do plano docs/rainforest/planos/2026-09-24-revisor-folha.md: os
# agentes do plugin sao FOLHA — despachados, eles nunca despacham outro
# agente. O mecanismo e uma linha no frontmatter, `disallowedTools: Agent`
# (formato confirmado ao vivo em
# docs/rainforest/pesquisas/2026-09-24-revisor-folha-payload.md, sessao E:
# agente de plugin real, via frontmatter .md, com `disallowedTools: Agent`
# no singular — nao lista YAML, nao array).
#
# Esta bateria le a lista de agentes por GLOB de agents/*.md, nunca por lista
# fixa: um agente novo sem a linha tem que reprovar sozinho, sem precisar de
# edicao nesta bateria.
set -u

cd "$(dirname "$0")/.." || exit 1

ok=0
falhou=0

# Extrai o frontmatter (entre os dois primeiros '---') de um arquivo .md.
frontmatter_de() {
  sed -n '2,/^---$/{/^---$/!p}' "$1"
}

# Confere um arquivo: frontmatter tem 'disallowedTools' contendo 'Agent' e NAO
# tem chave 'tools:'. Retorna 0 (passa) ou 1 (reprova) — e imprime o motivo em
# stderr quando reprova, para o caso de controle poder mostrar a mensagem.
verifica_frontmatter() {
  local arquivo="$1"
  local fm
  fm="$(frontmatter_de "$arquivo")"

  if ! echo "$fm" | grep -qE '^disallowedTools:.*Agent'; then
    echo "$arquivo: frontmatter sem 'disallowedTools' contendo 'Agent'" >&2
    return 1
  fi

  if echo "$fm" | grep -qE '^tools:'; then
    echo "$arquivo: frontmatter ganhou chave 'tools:' (nao deveria)" >&2
    return 1
  fi

  return 0
}

echo "== todo agents/*.md declara disallowedTools com Agent =="
echo

AGENTES=(agents/*.md)
if [ ! -e "${AGENTES[0]}" ]; then
  falhou=$((falhou+1)); echo "  FALHA nenhum arquivo casou com agents/*.md"
else
  for arq in "${AGENTES[@]}"; do
    if verifica_frontmatter "$arq" 2>/tmp/testa-agentes-folha-motivo.$$; then
      ok=$((ok+1)); echo "  ok   $arq"
    else
      falhou=$((falhou+1)); echo "  FALHA $(cat /tmp/testa-agentes-folha-motivo.$$)"
    fi
    rm -f /tmp/testa-agentes-folha-motivo.$$
  done
  echo
  echo "  (${#AGENTES[@]} agente(s) conferido(s) via glob agents/*.md)"
fi

# ------------------------------------------------- caso de controle
# Prova que o verificador SABE reprovar: copia um agente real para uma caixa
# temporaria, tira a linha 'disallowedTools', roda o MESMO verifica_frontmatter
# contra a copia (nunca contra agents/ real) e confere que reprova.
echo
echo "== caso de controle: agente sem a linha reprova =="
echo

CAIXA="$(mktemp -d)"
trap 'rm -rf "${CAIXA:-}"' EXIT

# Registra o conteudo real ANTES do caso de controle, para provar depois que
# agents/revisor.md nao foi tocado — sem depender de `git diff` (que ja
# mostraria a mudanca desta propria tarefa, nao a do caso de controle).
ANTES_REAL="$(cat agents/revisor.md)"

grep -v '^disallowedTools:' agents/revisor.md > "$CAIXA/sem-disallowed.md"

if verifica_frontmatter "$CAIXA/sem-disallowed.md" 2>/tmp/testa-agentes-folha-controle.$$; then
  falhou=$((falhou+1)); echo "  FALHA o verificador aprovou uma copia SEM 'disallowedTools' — nao sabe reprovar"
else
  ok=$((ok+1)); echo "  ok   VERMELHO: copia sem a linha reprova ($(cat /tmp/testa-agentes-folha-controle.$$))"
fi
rm -f /tmp/testa-agentes-folha-controle.$$

# Confere que agents/revisor.md real nao foi tocado pelo caso de controle.
DEPOIS_REAL="$(cat agents/revisor.md)"
if [ "$ANTES_REAL" = "$DEPOIS_REAL" ]; then
  ok=$((ok+1)); echo "  ok   agents/revisor.md real nao foi tocado pelo caso de controle"
else
  falhou=$((falhou+1)); echo "  FALHA agents/revisor.md real foi alterado pelo caso de controle"
fi

# Segundo caso de controle: prova que a barreira de 'tools:' TAMBEM sabe
# reprovar, e nao so a de 'disallowedTools'. Copia com a chave 'tools:'
# inserida no frontmatter (nunca em agents/ real).
sed '5a tools: Read' agents/revisor.md > "$CAIXA/com-tools.md"

if verifica_frontmatter "$CAIXA/com-tools.md" 2>/tmp/testa-agentes-folha-tools.$$; then
  falhou=$((falhou+1)); echo "  FALHA o verificador aprovou uma copia COM 'tools:' — nao sabe reprovar"
else
  ok=$((ok+1)); echo "  ok   VERMELHO: copia com 'tools:' reprova ($(cat /tmp/testa-agentes-folha-tools.$$))"
fi
rm -f /tmp/testa-agentes-folha-tools.$$

DEPOIS_REAL2="$(cat agents/revisor.md)"
if [ "$ANTES_REAL" = "$DEPOIS_REAL2" ]; then
  ok=$((ok+1)); echo "  ok   agents/revisor.md real nao foi tocado pelo segundo caso de controle"
else
  falhou=$((falhou+1)); echo "  FALHA agents/revisor.md real foi alterado pelo segundo caso de controle"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
