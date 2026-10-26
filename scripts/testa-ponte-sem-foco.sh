#!/bin/bash
# Bateria da ponte sem as regras de foco (2.0.0, tarefa 3).
# Uso: bash scripts/testa-ponte-sem-foco.sh
#
# Na 2.0.0 o foco nasce desligado, então a ponte sai SEMPRE sem as regras 3, 8 e 17
# (as de foco), sem olhar a chave `foco` de quem gera. O que importa aqui é o efeito:
#   1. a ponte gerada NAO tem as regras 3, 8 e 17, e tem a 1 e a 16 com o numero de sempre
#   2. o conferir-ponte aceita essa geração como verde
#   3. uma ponte gerada antes da 2.0.0 (com as três regras) sai como DESATUALIZADA,
#      não como "editado à mão" nem como erro de formato
# A ponte antiga e simulada numa copia do plugin em que a linha do nucleo volta a
# ser a de antes (sem semRegrasDeFoco). Nada aqui toca a configuração real.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIXA="$(mktemp -d)"
trap 'rm -rf "$CAIXA"' EXIT

# Copia do PLUGIN, mesma forma de scripts/testa-ponte.sh: a ponte resolve o proprio
# caminho por __dirname, entao a arvore precisa ter a mesma forma.
PLUG="$CAIXA/plugin"
mkdir -p "$PLUG/scripts" "$PLUG/hooks/lib" "$PLUG/skills/rainforest-mind"
cp "$SRC/scripts/ponte.cjs" "$PLUG/scripts/"
cp "$SRC/hooks/lib/contexto-sessao.cjs" "$SRC/hooks/lib/raiz.cjs" "$SRC/hooks/lib/config.cjs" "$SRC/hooks/lib/projetos.cjs" "$SRC/hooks/lib/ponte-corpo.cjs" "$SRC/hooks/lib/bytes.cjs" "$SRC/hooks/lib/resolver-executavel.cjs" "$PLUG/hooks/lib/"
cp "$SRC/scripts/setup.cjs" "$PLUG/scripts/"
cp "$SRC/scripts/conferir-ponte.cjs" "$PLUG/scripts/"
cp "$SRC/skills/rainforest-mind/SKILL.md" "$PLUG/skills/rainforest-mind/"

# Pasta de DADOS propria: nada aqui toca a configuracao real do usuario.
DADOS="$CAIXA/dados"; mkdir -p "$DADOS"; printf '' > "$DADOS/ideias.jsonl"
export RFM_ROOT="$(cygpath -m "$DADOS" 2>/dev/null || printf '%s' "$DADOS")"
PONTE="node $PLUG/scripts/ponte.cjs"
CONFERIR="node $PLUG/scripts/conferir-ponte.cjs"

ALVO="$CAIXA/repo-de-outra-pessoa"; mkdir -p "$ALVO"
ALVO_WIN="$(cygpath -m "$ALVO" 2>/dev/null || printf '%s' "$ALVO")"
ALVO_ANT="$CAIXA/repo-com-ponte-antiga"; mkdir -p "$ALVO_ANT"
ALVO_ANT_WIN="$(cygpath -m "$ALVO_ANT" 2>/dev/null || printf '%s' "$ALVO_ANT")"

ok=0; falhou=0
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /' | tail -6; fi
}
prova() { # nome, comando de teste (bash -c)
  local nome="$1"; shift
  if bash -c "$1" >/dev/null 2>&1; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome"; fi
}
contem() { # nome, agulha, comando...
  local nome="$1" txt="$2"; shift 2
  if "$@" 2>&1 | grep -q -- "$txt"; then ok=$((ok+1)); echo "  ok   $nome"
  else falhou=$((falhou+1)); echo "  FALHA $nome: nao achei '$txt'"; fi
}

echo "== 1. a ponte gerada nao tem as regras 3, 8 e 17 =="
esperado "ponte aplica num repo de outra pessoa" 0 $PONTE --alvo "$ALVO_WIN" --agente codex --aplicar
prova "sem a regra 3"  "! grep -q '^\*\*3\.' '$ALVO/AGENTS.md'"
prova "sem a regra 8"  "! grep -q '^\*\*8\.' '$ALVO/AGENTS.md'"
prova "sem a regra 17" "! grep -q '^\*\*17\.' '$ALVO/AGENTS.md'"
prova "a regra 1 com o numero de sempre"  "grep -q '^\*\*1\.' '$ALVO/AGENTS.md'"
prova "a regra 16 com o numero de sempre" "grep -q '^\*\*16\.' '$ALVO/AGENTS.md'"

echo
echo "== 2. o conferir-ponte aceita a geracao atual =="
esperado "conferir da ponte recem-gerada e verde" 0 $CONFERIR "$ALVO/AGENTS.md"

echo
echo "== 3. ponte de antes da 2.0.0 sai como desatualizada =="
# A copia antiga do gerador: a unica diferenca e o nucleo sem o filtro de foco.
# Asserção de contagem: a linha tem que aparecer exatamente uma vez, senão o sed não prova nada.
prova "a linha do nucleo aparece uma vez em ponte.cjs" "[ \$(grep -c 'lib.semRegrasDeFoco(lib.filtrarRegras(skill))' '$PLUG/scripts/ponte.cjs') -eq 1 ]"
sed 's/lib.semRegrasDeFoco(lib.filtrarRegras(skill))/lib.filtrarRegras(skill)/' "$PLUG/scripts/ponte.cjs" > "$PLUG/scripts/ponte-antigo.cjs"
esperado "ponte antiga gera (com as tres regras)" 0 node "$PLUG/scripts/ponte-antigo.cjs" --alvo "$ALVO_ANT_WIN" --agente codex --aplicar
prova "a ponte antiga traz a regra 3" "grep -q '^\*\*3\.' '$ALVO_ANT/AGENTS.md'"
esperado "conferir recusa a ponte antiga (exit 2)" 2 $CONFERIR "$ALVO_ANT/AGENTS.md"
contem "  ... e diz que e de antes da 2.0.0" "gerada antes da 2.0.0" $CONFERIR "$ALVO_ANT/AGENTS.md"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
