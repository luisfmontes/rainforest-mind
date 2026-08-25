#!/bin/bash
# Bateria de testes da skill `fechar` — valida o passo 4 (destino PR) e instruções
# sobre palavras-chave de fechamento de issues no GitHub.
#
# O que ela precisa provar, em ordem:
#
#   1. Todas as palavras-chave nomeadas no SKILL.md são reconhecidas pelo GitHub
#   2. Classificador de corpo de PR: identifica quais issues seriam fechadas
#   3. O passo 4 não oferece mais "Merge local" como opção do usuário
#   4. Valores de `acao` mencionados são aceitos (fechar não rejeita nenhum)

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ok=0; falhou=0

tem()     { if echo "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

# Função para extrair todas as palavras-chave do SKILL.md (entre crases, na seção de palavras-chave)
# Extrai do parágrafo que começa com "O GitHub reconhece"
extrair_palavras_chave_skill() {
  sed -n '/O GitHub reconhece/,/\./p' "$SRC/skills/fechar/SKILL.md" 2>/dev/null | \
    grep -o '`[A-Za-z]*`' | sed 's/`//g' | sort -u
}

# Função para classificar um corpo de PR e retornar os números de issues fechadas
# Argumentos: texto do corpo PR
# Retorna: números das issues separados por espaço (em ordem encontrada)
classificar_pr_body() {
  local body="$1"
  # Padrão case-insensitive: palavra-chave + espaço + hash + número
  # Usa grep com PCRE para case-insensitive e extrai os números
  echo "$body" | grep -io '\(close\|closes\|closed\|fix\|fixes\|fixed\|resolve\|resolves\|resolved\)[[:space:]]\+#[0-9]\+' \
    | grep -io '#[0-9]\+' \
    | tr -d '#' \
    | tr '\n' ' ' \
    | sed 's/[[:space:]]*$//'
}

# ------------------------------------------------- 1. Palavras-chave do SKILL.md estão corretas
echo; echo "1. Palavras-chave do SKILL.md estão no conjunto canônico do GitHub"
PALAVRAS_SKILL="$(extrair_palavras_chave_skill)"
CONJUNTO_CANONICO="close closed closes fix fixed fixes resolve resolved resolves"

for palavra in $PALAVRAS_SKILL; do
  if echo " $CONJUNTO_CANONICO " | grep -qF " $palavra "; then
    ok=$((ok+1))
    echo "  ok   '$palavra' está no conjunto canônico"
  else
    falhou=$((falhou+1))
    echo "  FALHA '$palavra' NÃO está no conjunto canônico"
  fi
done

# ------------------------------------------------- 2. Classificador de corpo de PR
echo; echo "2. Classificador de corpo de PR — casos conhecidos"

# Caso 2a: Fecha #81 e #79 (português, não funciona)
CORPO_2A="Fecha #81 e #79"
RESULT_2A="$(classificar_pr_body "$CORPO_2A")"
igual "Fecha #81 e #79 → nenhuma issue (português não reconhecido)" "$RESULT_2A" ""

# Caso 2b: Closes #81, closes #79 (funciona)
CORPO_2B="Closes #81, closes #79"
RESULT_2B="$(classificar_pr_body "$CORPO_2B")"
igual "Closes #81, closes #79 → 81 79" "$RESULT_2B" "81 79"

# Caso 2c: Closes #81 e #79 (fecha só #81, não repete a palavra)
CORPO_2C="Closes #81 e #79"
RESULT_2C="$(classificar_pr_body "$CORPO_2C")"
igual "Closes #81 e #79 → só 81 (não repete palavra)" "$RESULT_2C" "81"

# Caso 2d: fixes #12 (minúsculas)
CORPO_2D="fixes #12"
RESULT_2D="$(classificar_pr_body "$CORPO_2D")"
igual "fixes #12 → 12 (minúsculas funcionam)" "$RESULT_2D" "12"

# Caso 2e: Resolve #5, closes #8 (múltiplas palavras-chave diferentes)
CORPO_2E="Resolve #5, closes #8"
RESULT_2E="$(classificar_pr_body "$CORPO_2E")"
igual "Resolve #5, closes #8 → 5 8 (palavras diferentes)" "$RESULT_2E" "5 8"

# ------------------------------------------------- 2f. os EXEMPLOS DO SKILL.md
# Os casos 2a-2e acima são strings escritas nesta bateria: eles provam que o
# classificador funciona, mas NENHUMA edição no SKILL.md os deixa vermelhos —
# a bateria estaria desacoplada justamente do arquivo que diz revisar.
# Esta seção fecha isso: os três exemplos saem do SKILL.md e são classificados.
# Trocar um exemplo do texto por um errado deixa AQUI vermelho.
echo; echo "2f. os exemplos escritos no SKILL.md classificam como o texto promete"

# A extração é ESCOPADA ao parágrafo das palavras-chave, com a mesma disciplina
# da seção 1. Varrer o arquivo inteiro atrás de crase-com-#numero pegaria
# qualquer frase legítima que citasse uma issue em outro ponto do texto — e a
# bateria acusaria regressão por motivo desconexo do que ela protege. Vermelho
# por motivo errado ensina quem mantém a ignorar o vermelho.
mapfile -t EXEMPLOS < <(
  sed -n '/O GitHub reconhece/,/^$/p' "$SRC/skills/fechar/SKILL.md" \
    | grep -o '`[^`]*#[0-9][^`]*`' | sed 's/^`//; s/`$//'
)

igual "o SKILL.md traz exatamente 3 exemplos de corpo de PR" "${#EXEMPLOS[@]}" "3"

if [ "${#EXEMPLOS[@]}" -eq 3 ]; then
  # 1º: o que funciona (repete a palavra) -> fecha as duas
  R1="$(classificar_pr_body "${EXEMPLOS[0]}")"
  QTD1="$(echo "$R1" | wc -w | tr -d ' ')"
  igual "exemplo 1 do texto ('${EXEMPLOS[0]}') fecha 2 issues" "$QTD1" "2"

  # 2º: a armadilha (não repete a palavra) -> fecha só a primeira
  R2="$(classificar_pr_body "${EXEMPLOS[1]}")"
  QTD2="$(echo "$R2" | wc -w | tr -d ' ')"
  igual "exemplo 2 do texto ('${EXEMPLOS[1]}') fecha só 1 issue" "$QTD2" "1"

  # 3º: o incidente de 2026-08-24, em português -> não fecha nada
  R3="$(classificar_pr_body "${EXEMPLOS[2]}")"
  igual "exemplo 3 do texto ('${EXEMPLOS[2]}') não fecha issue nenhuma" "$R3" ""
fi

# ------------------------------------------------- 3. Passo 4 não oferece "Merge local" como opção
echo; echo "3. Passo 4 não oferece 'Merge local' como opção"
CONTEUDO_SKILL="$(cat "$SRC/skills/fechar/SKILL.md")"
nao_tem "não há '1. Merge local'" "$CONTEUDO_SKILL" "1. Merge local"
nao_tem "não há '2. Abrir PR'" "$CONTEUDO_SKILL" "2. Abrir PR"
nao_tem "não há '3. Manter a branch'" "$CONTEUDO_SKILL" "3. Manter a branch"
tem "há referência a 'Abrir PR'" "$CONTEUDO_SKILL" "Abrir PR"
tem "há referência a 'destino da branch é sempre PR'" "$CONTEUDO_SKILL" "destino da branch é sempre PR"

# ------------------------------------------------- 4. Valores de acao coerentes
echo; echo "4. Os valores de acao da prosa batem com os do comando, no mesmo arquivo"
# A versão anterior desta seção somava `ok` num laço sobre uma lista cravada
# AQUI DENTRO, sem ler nada e sem condição nenhuma: nenhuma edição no SKILL.md
# ou no estado.cjs a deixava vermelha. Ela inflava o placar em 3 e não media
# coisa alguma. O que dá para medir de verdade é COERÊNCIA INTERNA: a prosa do
# fechamento nomeia valores de `acao`, e o comando logo acima traz a lista
# `merge|pr|manteve`. Se um lado mudar e o outro não, quem seguir a skill grava
# um valor que o exemplo não prevê — e é isso que fica vermelho aqui.
#
# O estado.cjs NÃO valida o valor de acao (confirmado lendo o script: o --json
# entra como objeto livre). Por isso a trava não pode ser "o estado.cjs recusa" —
# essa trava não existe, e escrever que existe seria mandar confiar em nada.

# Valores citados na LISTA do comando: --json '{"acao":"merge|pr|manteve"}'
DO_COMANDO="$(grep -o '"acao":"[^"]*"' "$SRC/skills/fechar/SKILL.md" | head -n 1 | sed 's/.*:"//; s/"$//' | tr '|' ' ')"
# Valores citados na PROSA logo abaixo do comando (palavras entre crases).
DA_PROSA="$(sed -n '/^`acao` é o que/,/^$/p' "$SRC/skills/fechar/SKILL.md" | grep -o '`[a-z]\+`' | sed 's/`//g' | grep -vw acao | sort -u | tr '\n' ' ')"

if [ -z "$DO_COMANDO" ]; then
  falhou=$((falhou+1)); echo "  FALHA nao achei a lista de acao no comando do SKILL.md"
fi
if [ -z "$DA_PROSA" ]; then
  falhou=$((falhou+1)); echo "  FALHA nao achei valor de acao citado na prosa do SKILL.md"
fi

for valor in $DA_PROSA; do
  if echo " $DO_COMANDO " | grep -qF " $valor "; then
    ok=$((ok+1)); echo "  ok   acao='$valor' citado na prosa esta na lista do comando"
  else
    falhou=$((falhou+1)); echo "  FALHA acao='$valor' esta na prosa mas NAO na lista do comando ($DO_COMANDO)"
  fi
done

for valor in $DO_COMANDO; do
  if echo " $DA_PROSA " | grep -qF " $valor "; then
    ok=$((ok+1)); echo "  ok   acao='$valor' da lista do comando esta explicado na prosa"
  else
    falhou=$((falhou+1)); echo "  FALHA acao='$valor' esta na lista do comando mas NAO na prosa"
  fi
done

# O caminho normal virou PR: se 'pr' sumir dos dois lados, a skill perdeu o
# proprio passo 4.
if echo " $DO_COMANDO " | grep -qF " pr "; then
  ok=$((ok+1)); echo "  ok   'pr' continua entre os valores de acao"
else
  falhou=$((falhou+1)); echo "  FALHA 'pr' sumiu dos valores de acao — o passo 4 abre PR"
fi

# ------------------------------------------------- 5. Incidente documentado
echo; echo "5. Incidente 2026-08-24 documentado no SKILL.md"
tem "referência a PR #85" "$CONTEUDO_SKILL" "PR #85"
tem "referência a issues #81 e #79" "$CONTEUDO_SKILL" "#81 e #79"
tem "referência a data 2026-08-24" "$CONTEUDO_SKILL" "2026-08-24"
tem "explicação do problema (português)" "$CONTEUDO_SKILL" "português"

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
