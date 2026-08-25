#!/bin/bash
# Bateria do agents/auditor-de-api.md — o agente que audita API existente contra
# a OWASP API Security Top 10 2023.
#
# Por que uma bateria para um arquivo de prompt: o valor deste agente está em ele
# ser ESPECÍFICO. A regua tem dez categorias nomeadas, e o modo de falha
# registrado neste plugin (Issue #61) é o agente trocar o criterio caro por um
# barato e devolver com o numero do original. Um agente que perde uma categoria
# no meio de uma edicao continua parecendo certo — e volta a ser "revise a
# seguranca", que e' exatamente o pedido generico que o desenho recusa.
#
# O que ela precisa provar, em ordem:
#
#   1. as dez categorias estao presentes e numeradas de API1 a API10, sem buraco
#   2. o modelo declarado e' sonnet (funcao de julgamento, nao mecanica)
#   3. a proibicao de consertar esta escrita
#   4. a proibicao de mandar requisicao esta escrita
#   5. segredo se reporta por nome, nunca por valor
#   6. o relatorio exige as dez secoes, e a superficie invisivel esta nomeada
#   7. a regua e' citada por URL e nao ha texto da OWASP copiado
#   8. a description cabe no orcamento (o corpo e' de graca, a description nao)

set -u

AGENTE="agents/auditor-de-api.md"

ok=0; falhou=0
tem()     { if echo "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

if [ ! -f "$AGENTE" ]; then
  echo "FALHA: $AGENTE nao existe — rode a partir da raiz do repositorio"
  exit 2
fi

CORPO="$(cat "$AGENTE")"

# ------------------------------------------------- 1. as dez categorias
# Este e' o caso nomeado como `fixture` na tarefa 1 do plano: com uma categoria
# renomeada ou removida, e' AQUI que a bateria fica vermelha, nomeando qual.
#
# A contagem se restringe ao bloco "## As dez varreduras" de proposito: o
# template do relatorio, mais abaixo no arquivo, tambem tem cabecalhos `### APIn`
# como exemplo. Contar o arquivo inteiro deixaria a bateria verde com uma
# varredura removida, desde que o exemplo dela sobrevivesse no template — que e'
# exatamente o falso-verde que esta bateria existe para nao ter.
echo; echo "1. as dez categorias estao presentes e numeradas de API1 a API10"
VARREDURAS="$(echo "$CORPO" | sed -n '/^## As dez varreduras$/,/^## Fora das dez/p')"

if [ -z "$VARREDURAS" ]; then
  falhou=$((falhou+1)); echo "  FALHA nao achei o bloco '## As dez varreduras' — a estrutura do agente mudou"
fi

# O titulo canonico de cada categoria vai cravado aqui de proposito. Conferir so'
# o NUMERO deixaria a bateria verde com a categoria renomeada para qualquer
# coisa — e a regua e' externa: se o titulo daqui divergir do da OWASP, o agente
# parou de auditar contra ela e ninguem ficou sabendo.
# Fonte: https://owasp.org/API-Security/editions/2023/en/0x11-t10/
titulo_de() {
  case "$1" in
    1)  echo "Broken Object Level Authorization" ;;
    2)  echo "Broken Authentication" ;;
    3)  echo "Broken Object Property Level Authorization" ;;
    4)  echo "Unrestricted Resource Consumption" ;;
    5)  echo "Broken Function Level Authorization" ;;
    6)  echo "Unrestricted Access to Sensitive Business Flows" ;;
    7)  echo "Server Side Request Forgery" ;;
    8)  echo "Security Misconfiguration" ;;
    9)  echo "Improper Inventory Management" ;;
    10) echo "Unsafe Consumption of APIs" ;;
  esac
}

for n in 1 2 3 4 5 6 7 8 9 10; do
  TITULO="$(titulo_de "$n")"
  if echo "$VARREDURAS" | grep -qF "### API${n} — ${TITULO}"; then
    ok=$((ok+1)); echo "  ok   API${n} — ${TITULO}"
  else
    falhou=$((falhou+1)); echo "  FALHA API${n} nao tem a varredura da OWASP 2023 ('### API${n} — ${TITULO}') — a regua ficou incompleta ou divergiu da fonte"
  fi
done

QTD="$(echo "$VARREDURAS" | grep -cE '^### API[0-9]+ — ')"
igual "sao exatamente 10 varreduras" "$QTD" "10"

# ------------------------------------------------- 2. modelo
echo; echo "2. o modelo declarado e' sonnet"
MODELO="$(sed -n 's/^model: *//p' "$AGENTE" | head -n 1)"
igual "frontmatter declara model: sonnet" "$MODELO" "sonnet"

# ------------------------------------------------- 3. proibicao de consertar
echo; echo "3. a proibicao de consertar esta escrita"
tem "o agente e' proibido de editar o codigo auditado" "$CORPO" "Nunca edite o código auditado"
tem "achar e consertar sao duas passadas" "$CORPO" "parou de procurar"

# ------------------------------------------------- 4. proibicao de trafego
echo; echo "4. a proibicao de mandar requisicao esta escrita"
tem "zero trafego contra endpoint" "$CORPO" "Zero tráfego contra"
tem "o motivo (ambiente de cliente) esta nomeado" "$CORPO" "autorização escrita"

# ------------------------------------------------- 5. segredo por nome
echo; echo "5. segredo se reporta por nome, nunca por valor"
# O texto e' prosa em markdown e a quebra de linha dele e' cosmetica: casar com a
# quebra exata deixaria a bateria vermelha depois de um simples reflow de
# paragrafo, com a garantia intacta. Compara-se o corpo COM AS QUEBRAS
# ACHATADAS, entao a asserção segue as palavras e nao a largura da coluna.
#
# E ha um motivo mais duro: `grep -F` com quebra de linha DENTRO do padrao trata
# as duas linhas como ALTERNATIVAS, nao como sequencia. A versao anterior desta
# asserção passava se qualquer uma das metades casasse -- era um OR acidental
# vestido de frase. Achatar o corpo transforma a frase inteira num padrao de uma
# linha so', e aí a asserção passa a exigir o que diz exigir.
CORPO_PLANO="$(echo "$CORPO" | tr '\n' ' ' | tr -s ' ')"
tem "proibicao de transcrever valor de segredo" "$CORPO_PLANO" "**Nunca transcreva o valor**"
tem "o historico do git entra na varredura" "$CORPO" "--diff-filter=A"

# ------------------------------------------------- 6. formato do relatorio
echo; echo "6. o relatorio exige as dez secoes e nomeia a superficie invisivel"
tem "as dez secoes sao obrigatorias" "$CORPO" "As dez seções são obrigatórias"
tem "relatorio com nove e' entrega incompleta" "$CORPO" "com nove é entrega incompleta"
tem "Server Actions estao nomeadas como superficie HTTP" "$CORPO" "Server Actions"
tem "a secao de premissas aceitas sem conferir existe" "$CORPO" "Premissas que aceitei sem conferir"

# ------------------------------------------------- 7. a regua e' citada, nao copiada
echo; echo "7. a regua e' citada por URL e o texto da OWASP nao foi copiado"
tem "a URL da edicao 2023 esta no corpo" "$CORPO" "owasp.org/API-Security/editions/2023"
tem "a trava de licenca esta declarada" "$CORPO" "CC BY-SA 4.0"
# O texto da OWASP e' CC BY-SA (ShareAlike) e este repo e' MIT: copiar contamina.
# A marca de copia seria o boilerplate de licenca da propria OWASP dentro daqui.
nao_tem "nao ha boilerplate de licenca da OWASP colado" "$CORPO" "Creative Commons Attribution-ShareAlike"

# ------------------------------------------------- 8. a description cabe no orcamento
echo; echo "8. a description cabe no orcamento"
DESC="$(sed -n 's/^description: *//p' "$AGENTE" | head -n 1)"
TAM="$(printf '%s' "$DESC" | wc -c | tr -d ' ')"
if [ "$TAM" -gt 0 ] && [ "$TAM" -le 300 ]; then
  ok=$((ok+1)); echo "  ok   description tem $TAM B (teto de 300 B por agente)"
else
  falhou=$((falhou+1)); echo "  FALHA description tem $TAM B — fora do teto de 300 B por agente"
fi

# O orcamento agregado e' a trava de verdade; aqui so' se confirma que ela passa
# com este agente instalado.
if node scripts/orcamento.cjs > /dev/null 2>&1; then
  ok=$((ok+1)); echo "  ok   node scripts/orcamento.cjs sai 0 com o agente instalado"
else
  falhou=$((falhou+1)); echo "  FALHA node scripts/orcamento.cjs nao sai 0 com o agente instalado"
fi

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
