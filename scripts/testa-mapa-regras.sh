#!/bin/bash
# Confere a secao "## Regra -> trava" de docs/travas-mecanicas.md contra as
# 17 regras de skills/rainforest-mind/SKILL.md, e roda auto-teste em caixa de
# areia para provar que a propria checagem falha quando deveria.
#
# Uso:
#   bash scripts/testa-mapa-regras.sh
#   SKILL_MD=<caminho>  sobrescreve o SKILL.md lido (default: skills/rainforest-mind/SKILL.md)
#   TRAVAS_MD=<caminho> sobrescreve o travas-mecanicas.md lido (default: docs/travas-mecanicas.md)
#
# Protege contra: regra nova (ou removida) no SKILL.md sem linha correspondente
#   na tabela; linha da tabela sem trava mecanica NEM marca "disciplina" (lida
#   como protegida sem estar); arquivo citado na coluna Trava que nao existe
#   mais em disco (renomeado ou apagado sem atualizar a tabela)
# Não protege contra: trava citada que existe em disco mas nao faz o que a
#   linha descreve — esta bateria confere presenca do arquivo, nao comportamento
#
# Por que existe (D6, docs/rainforest/design/2026-09-12-absorver-data-skills.md):
# o CLAUDE.md do plugin de dados analisado (`wildz-data`, Rootz) bania trailer
# `Co-Authored-By` e heredoc em commit, e o historico tinha 25 trailers e 2
# heredocs — regra escrita e sem trava e' regra que se viola. A lista EXPLICITA
# das regras que valem so' por disciplina impede acreditar que estao protegidas.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$SRC/scripts/testa-mapa-regras.sh"
SKILL_MD="${SKILL_MD:-$SRC/skills/rainforest-mind/SKILL.md}"
TRAVAS_MD="${TRAVAS_MD:-$SRC/docs/travas-mecanicas.md}"
# Guarda contra recursao infinita: a chamada recursiva do auto-teste (abaixo)
# roda so a checagem central, sem tentar rodar seu proprio auto-teste.
SO_CHECAGEM="${RFM_MAPA_REGRAS_SO_CHECAGEM:-}"

ok=0; falhou=0

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

if [ ! -f "$SKILL_MD" ]; then
  echo "FALHA: SKILL_MD '$SKILL_MD' nao existe"
  exit 1
fi
if [ ! -f "$TRAVAS_MD" ]; then
  echo "FALHA: TRAVAS_MD '$TRAVAS_MD' nao existe"
  exit 1
fi

echo "== Lendo regras de $SKILL_MD =="
regras_skill="$(grep -oE '^\*\*[0-9]+\.' "$SKILL_MD" | grep -oE '[0-9]+')"
n_regras="$(printf '%s\n' "$regras_skill" | grep -c '.')"
if [ "$n_regras" -eq 0 ]; then
  falhou=$((falhou+1))
  echo "  FALHA nenhuma regra lida de $SKILL_MD (regex '^\*\*([0-9]+)\.' nao casou nada)"
else
  ok=$((ok+1))
  echo "  ok $n_regras regras lidas do SKILL.md ($(printf '%s' "$regras_skill" | tr '\n' ' ' | sed 's/ $//'))"
fi

echo "== Lendo a secao 'Regra -> trava' de $TRAVAS_MD =="
secao="$(awk '
  /^## Regra/ { found=1 }
  found && /^## / && !/^## Regra/ { exit }
  found { print }
' "$TRAVAS_MD")"
if [ -z "$secao" ]; then
  falhou=$((falhou+1))
  echo "  FALHA secao '## Regra -> trava' nao encontrada em $TRAVAS_MD"
  linhas_dados=""
else
  linhas_dados="$(printf '%s\n' "$secao" | grep -E '^\| *[0-9]+ *\|')"
fi

echo "== Checagem (a): toda regra tem exatamente uma linha =="
regras_sem_linha=""
regras_duplicadas=""
for n in $regras_skill; do
  cnt="$(printf '%s\n' "$linhas_dados" | grep -cE "^\| *$n *\|")"
  if [ "$cnt" -eq 0 ]; then
    regras_sem_linha="$regras_sem_linha $n"
  elif [ "$cnt" -gt 1 ]; then
    regras_duplicadas="$regras_duplicadas $n"
  fi
done
n_linhas="$(printf '%s\n' "$linhas_dados" | grep -c '.')"
if [ -n "$regras_sem_linha" ] || [ -n "$regras_duplicadas" ]; then
  falhou=$((falhou+1))
  [ -n "$regras_sem_linha" ] && echo "  FALHA regra(s) sem linha na tabela:$regras_sem_linha"
  [ -n "$regras_duplicadas" ] && echo "  FALHA regra(s) com mais de uma linha na tabela:$regras_duplicadas"
else
  ok=$((ok+1))
  echo "  ok $n_linhas linhas na tabela, uma por regra"
fi

echo "== Checagem (b): nenhuma linha com as duas colunas vazias =="
regras_vazias=""
travas_texto=""
while IFS= read -r linha; do
  [ -z "$linha" ] && continue
  regra="$(printf '%s' "$linha" | awk -F'|' '{print $2}')"
  trava_col="$(printf '%s' "$linha" | awk -F'|' '{print $3}')"
  disc_col="$(printf '%s' "$linha" | awk -F'|' '{print $4}')"
  regra="$(trim "$regra")"
  trava_trim="$(trim "$trava_col")"
  disc_trim="$(trim "$disc_col")"
  if [ -z "$trava_trim" ] && [ -z "$disc_trim" ]; then
    regras_vazias="$regras_vazias $regra"
  fi
  travas_texto="$travas_texto
$trava_trim"
done <<EOF
$linhas_dados
EOF
if [ -n "$regras_vazias" ]; then
  falhou=$((falhou+1))
  echo "  FALHA regra(s) com Trava e 'Vale por disciplina' vazias:$regras_vazias"
else
  ok=$((ok+1))
  echo "  ok nenhuma linha com as duas colunas vazias"
fi

echo "== Checagem (c): todo arquivo citado na coluna Trava existe em disco =="
arquivos_citados="$(printf '%s\n' "$travas_texto" | grep -oE '(hooks|scripts)/[A-Za-z0-9_.-]+\.(cjs|sh)' | sort -u)"
n_arquivos="$(printf '%s\n' "$arquivos_citados" | grep -c '.')"
arquivos_ausentes=""
for arq in $arquivos_citados; do
  [ -f "$SRC/$arq" ] || arquivos_ausentes="$arquivos_ausentes $arq"
done
if [ -n "$arquivos_ausentes" ]; then
  falhou=$((falhou+1))
  echo "  FALHA arquivo(s) citado(s) que nao existem em disco:$arquivos_ausentes"
else
  ok=$((ok+1))
  echo "  ok $n_arquivos arquivos citados existem em disco"
fi

echo
echo "Resultado: $ok ok, $falhou falha(s)"

if [ -n "$SO_CHECAGEM" ]; then
  # Chamada recursiva do auto-teste abaixo: so a checagem, sem novo auto-teste.
  if [ "$falhou" -eq 0 ]; then exit 0; else exit 1; fi
fi

echo
echo "== Auto-teste em caixa de areia =="
RAIZ_POSIX="$(mktemp -d)"
RAIZ="$(cygpath -m "$RAIZ_POSIX" 2>/dev/null || printf '%s' "$RAIZ_POSIX")"
trap 'rm -rf "$RAIZ_POSIX"' EXIT
echo "(caixa de areia: $RAIZ)"

# Caso 1: cópia sem a linha da regra 17 -> exit 1 citando "17".
copia17="$RAIZ/sem-regra-17.md"
grep -vE '^\| *17 *\|' "$TRAVAS_MD" > "$copia17"
saida17="$(RFM_MAPA_REGRAS_SO_CHECAGEM=1 TRAVAS_MD="$copia17" bash "$SELF" 2>&1)"
exit17=$?
if [ "$exit17" -eq 1 ] && printf '%s' "$saida17" | grep -q '17'; then
  ok=$((ok+1))
  echo "  ok auto-teste: cópia sem a regra 17 -> exit 1 citando 17"
else
  falhou=$((falhou+1))
  echo "  FALHA auto-teste: cópia sem a regra 17 deveria sair 1 citando 17 (saiu $exit17)"
  printf '%s\n' "$saida17" | sed 's/^/         /' | head -8
fi

# Caso 2: cópia citando hooks/gate-inexistente.cjs -> exit 1 citando o arquivo.
copiaFake="$RAIZ/arquivo-inexistente.md"
sed 's#hooks/foco-session-start\.cjs#hooks/gate-inexistente.cjs#' "$TRAVAS_MD" > "$copiaFake"
saidaFake="$(RFM_MAPA_REGRAS_SO_CHECAGEM=1 TRAVAS_MD="$copiaFake" bash "$SELF" 2>&1)"
exitFake=$?
if [ "$exitFake" -eq 1 ] && printf '%s' "$saidaFake" | grep -q 'gate-inexistente.cjs'; then
  ok=$((ok+1))
  echo "  ok auto-teste: cópia citando hooks/gate-inexistente.cjs -> exit 1 citando o arquivo"
else
  falhou=$((falhou+1))
  echo "  FALHA auto-teste: cópia citando arquivo inexistente deveria sair 1 citando-o (saiu $exitFake)"
  printf '%s\n' "$saidaFake" | sed 's/^/         /' | head -8
fi

echo
echo "Resultado final: $ok ok, $falhou falha(s)"
if [ "$falhou" -eq 0 ]; then
  exit 0
else
  exit 1
fi
