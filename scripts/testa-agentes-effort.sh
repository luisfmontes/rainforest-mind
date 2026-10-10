#!/usr/bin/env bash
# Tarefa 1 do plano docs/rainforest/planos/effort-nos-agentes.md: cada agente
# do plugin fixa `effort:` no frontmatter, porque o Agent nao tem parametro
# effort e o subagente herdaria o da sessao. O mapa por papel vem do design
# (D1/D2): julgamento = high, mecanico = medium.
#
# Le agents/*.md por GLOB, como a testa-agentes-folha.sh: agente novo sem
# `effort:` reprova sozinho. Agente novo fora do mapa reprova tambem, para que
# a escolha do effort dele seja uma decisao, nao um esquecimento.
set -u

cd "$(dirname "$0")/.." || exit 1

ok=0
falhou=0

esperado_de() {
  case "$1" in
    revisor|tester|depurador|auditor-de-seguranca|planejador|arqueologo) echo high ;;
    executor|documentador|resolvedor-de-build) echo medium ;;
    *) echo "" ;;
  esac
}

frontmatter_de() {
  sed -n '2,/^---$/{/^---$/!p}' "$1"
}

# Retorna 0 (passa) ou 1 (reprova), com o motivo em stderr.
verifica_effort() {
  local arquivo="$1" nome esperado valor
  nome="$(basename "$arquivo" .md)"
  esperado="$(esperado_de "$nome")"
  valor="$(frontmatter_de "$arquivo" | sed -n 's/^effort: *//p' | head -1)"
  if [ -z "$valor" ]; then
    echo "$arquivo: frontmatter sem 'effort:'" >&2; return 1
  fi
  case "$valor" in low|medium|high|xhigh|max) ;; *)
    echo "$arquivo: effort '$valor' fora de low|medium|high|xhigh|max" >&2; return 1 ;;
  esac
  if [ -z "$esperado" ]; then
    echo "$arquivo: agente fora do mapa de effort do design (decida e acrescente em esperado_de)" >&2; return 1
  fi
  if [ "$valor" != "$esperado" ]; then
    echo "$arquivo: effort '$valor', o design pede '$esperado'" >&2; return 1
  fi
  return 0
}

echo "== 1. todo agents/*.md fixa o effort do seu papel =="
n=0
for arq in agents/*.md; do
  n=$((n+1))
  if verifica_effort "$arq" 2>/tmp/testa-agentes-effort-motivo.$$; then
    ok=$((ok+1)); echo "  ok   $arq"
  else
    falhou=$((falhou+1)); echo "  FALHA $(cat /tmp/testa-agentes-effort-motivo.$$)"
  fi
  rm -f /tmp/testa-agentes-effort-motivo.$$
done
if [ "$n" -eq 0 ]; then falhou=$((falhou+1)); echo "  FALHA nenhum agents/*.md achado"; fi

echo "== 2. controles: a checagem sabe falhar =="
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT
sed '/^effort:/d' agents/revisor.md > "$CAIXA/revisor.md"
if verifica_effort "$CAIXA/revisor.md" 2>/dev/null; then
  falhou=$((falhou+1)); echo "  FALHA copia sem 'effort:' passou"
else
  ok=$((ok+1)); echo "  ok   VERMELHO: copia sem 'effort:' reprova"
fi
sed 's/^effort: high$/effort: medium/' agents/revisor.md > "$CAIXA/revisor.md"
if verifica_effort "$CAIXA/revisor.md" 2>/dev/null; then
  falhou=$((falhou+1)); echo "  FALHA revisor com effort medium passou"
else
  ok=$((ok+1)); echo "  ok   VERMELHO: revisor com effort fora do mapa reprova"
fi
cp agents/executor.md "$CAIXA/agente-novo.md"
if verifica_effort "$CAIXA/agente-novo.md" 2>/dev/null; then
  falhou=$((falhou+1)); echo "  FALHA agente fora do mapa passou"
else
  ok=$((ok+1)); echo "  ok   VERMELHO: agente novo fora do mapa reprova"
fi

echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
