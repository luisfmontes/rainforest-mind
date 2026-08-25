#!/bin/bash
# Bateria do agents/auditor-de-seguranca.md — o agente que audita codigo existente
# contra DUAS reguas externas: a OWASP Top 10 2025 (sempre) e a OWASP API
# Security Top 10 2023 (so quando ha superficie de API).
#
# Por que uma bateria para um arquivo de prompt: o valor deste agente esta em ele
# ser ESPECIFICO e em a regua estar INTEIRA. Duas coisas podem apodrecer em
# silencio, e as duas ja aconteceram neste repositorio:
#
#   1. Uma categoria some ou e renomeada numa edicao, e o agente continua
#      parecendo certo. Por isso os titulos canonicos vao CRAVADOS aqui: conferir
#      so o numero deixaria verde uma categoria renomeada para qualquer coisa.
#      Foi assim que a Top 10 CLASSICA quase entrou na edicao errada -- a vigente
#      e a 2025, nao a 2021, e o A10 mudou de nome entre as duas.
#   2. As cinco falhas do video que originaram este agente somem no meio de uma
#      edicao. Em 2026-08-24 TRES das cinco ficaram de fora da primeira entrega,
#      justamente porque nada travava contra elas. Agora trava.
#
# O que ela precisa provar, em ordem:
#
#   1. as dez da OWASP Top 10 2025, com o titulo da edicao VIGENTE
#   2. as dez da OWASP API Security Top 10 2023
#   3. as cinco falhas do video, nominalmente, no bloco indice
#   4. as quatro ferramentas do video, nomeadas
#   5. regua pulada exige motivo escrito
#   6. o metodo continua: sonnet, nao conserta, zero trafego, segredo por nome
#   7. as reguas sao citadas por URL e o texto da OWASP nao foi copiado
#   8. a description cabe no orcamento

set -u

AGENTE="agents/auditor-de-seguranca.md"

ok=0; falhou=0
tem()     { if echo "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

if [ ! -f "$AGENTE" ]; then
  echo "FALHA: $AGENTE nao existe — rode a partir da raiz do repositorio"
  exit 2
fi

CORPO="$(cat "$AGENTE")"
# O corpo achatado serve para asserção que nao pode depender da largura da coluna:
# `grep -F` com quebra de linha DENTRO do padrao trata as linhas como
# ALTERNATIVAS, nao como sequencia, e isso ja produziu um OR acidental aqui.
CORPO_PLANO="$(echo "$CORPO" | tr '\n' ' ' | tr -s ' ')"

# As contagens se restringem ao bloco de cada regua de proposito: o template do
# relatorio, mais abaixo no arquivo, tambem tem cabecalhos de categoria como
# exemplo. Contar o arquivo inteiro deixaria a bateria verde com uma varredura
# removida, desde que o exemplo dela sobrevivesse no template.
REGUA1="$(echo "$CORPO" | sed -n '/^## Régua 1 —/,/^## Régua 2 —/p')"
REGUA2="$(echo "$CORPO" | sed -n '/^## Régua 2 —/,/^## Fora das réguas/p')"

# ------------------------------------------------- 1. OWASP Top 10 2025
# Fonte: https://owasp.org/Top10/2025/ (conferida em 2026-08-25)
echo; echo "1. as dez da OWASP Top 10 2025, com o titulo da edicao vigente"
[ -z "$REGUA1" ] && { falhou=$((falhou+1)); echo "  FALHA nao achei o bloco '## Régua 1 —'"; }

titulo_2025() {
  case "$1" in
    01) echo "Broken Access Control" ;;
    02) echo "Security Misconfiguration" ;;
    03) echo "Software Supply Chain Failures" ;;
    04) echo "Cryptographic Failures" ;;
    05) echo "Injection" ;;
    06) echo "Insecure Design" ;;
    07) echo "Authentication Failures" ;;
    08) echo "Software or Data Integrity Failures" ;;
    09) echo "Security Logging and Alerting Failures" ;;
    10) echo "Mishandling of Exceptional Conditions" ;;
  esac
}

for n in 01 02 03 04 05 06 07 08 09 10; do
  T="$(titulo_2025 "$n")"
  if echo "$REGUA1" | grep -qF "### A${n} — ${T}"; then
    ok=$((ok+1)); echo "  ok   A${n} — ${T}"
  else
    falhou=$((falhou+1)); echo "  FALHA A${n} nao tem a varredura da OWASP Top 10 2025 ('### A${n} — ${T}') — regua incompleta ou divergiu da edicao vigente"
  fi
done
igual "sao exatamente 10 varreduras na Regua 1" "$(echo "$REGUA1" | grep -cE '^### A[0-9]+ — ')" "10"

# ------------------------------------------------- 2. OWASP API Security 2023
echo; echo "2. as dez da OWASP API Security Top 10 2023"
[ -z "$REGUA2" ] && { falhou=$((falhou+1)); echo "  FALHA nao achei o bloco '## Régua 2 —'"; }

titulo_api() {
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
  T="$(titulo_api "$n")"
  if echo "$REGUA2" | grep -qF "### API${n} — ${T}"; then
    ok=$((ok+1)); echo "  ok   API${n} — ${T}"
  else
    falhou=$((falhou+1)); echo "  FALHA API${n} nao tem a varredura da OWASP API 2023 ('### API${n} — ${T}')"
  fi
done
igual "sao exatamente 10 varreduras na Regua 2" "$(echo "$REGUA2" | grep -cE '^### API[0-9]+ — ')" "10"

# ------------------------------------------------- 3. as cinco do video
# Este e o caso que existe porque TRES das cinco ficaram de fora da entrega de
# 2026-08-24. Cada falha precisa estar nominalmente no indice, com destino.
echo; echo "3. as cinco falhas do video estao no indice, com destino"
INDICE="$(echo "$CORPO" | sed -n '/^## As cinco do vídeo/,/^## Régua 1 —/p')"
[ -z "$INDICE" ] && { falhou=$((falhou+1)); echo "  FALHA nao achei o bloco '## As cinco do vídeo'"; }

tem "falha 1 — trava de linha (RLS) desligada" "$INDICE" "RLS"
tem "falha 2 — front-end decidindo quem e admin" "$INDICE" "Front-end decidindo quem é admin"
tem "falha 3 — IDOR" "$INDICE" "IDOR"
tem "falha 4 — segredo no front e no historico" "$INDICE" "Segredo no front-end e no histórico do git"
tem "falha 5 — input sem tratamento" "$INDICE" "Input sem tratamento"
igual "o indice tem exatamente 5 linhas de falha" "$(echo "$INDICE" | grep -cE '^\| [1-5] \| ')" "5"

# As duas frases-criterio do video, que sao o julgamento e nao o enfeite.
tem "criterio: regra de negocio e no back" "$CORPO_PLANO" "Regra de negócio é no back; o front só renderiza"
tem "criterio: tudo que o usuario digita e mentira" "$CORPO_PLANO" "tudo que o usuário digita é mentira até que se prove o"

# E o padrao concreto de cada falha, na categoria onde ela mora.
tem "falha 1 tem padrao de fronteira de confianca" "$CORPO" "fronteira de confiança"
tem "falha 2 tem padrao de autorizacao no cliente" "$CORPO" "autorização decidida no cliente"
tem "falha 3 tem o padrao do identificador decorativo" "$CORPO" "identificador decorativo"
tem "falha 4 tem a metade do front (variavel vira JS legivel)" "$CORPO_PLANO" "vira JavaScript legível"
tem "falha 5 tem padrao de render nao escapado" "$CORPO" "dangerouslySetInnerHTML"

# ------------------------------------------------- 4. as ferramentas do video
echo; echo "4. as quatro ferramentas do video estao nomeadas"
for f in Gitleaks OpenGrep Bandit "OWASP ZAP"; do
  tem "ferramenta '$f' nomeada" "$CORPO" "$f"
done
tem "o ZAP e' marcado como execucao contra alvo vivo" "$CORPO" "só com autorização escrita do dono do alvo"
tem "nenhuma ferramenta e' instalada" "$CORPO_PLANO" "não instala nenhuma delas"

# ------------------------------------------------- 5. regua pulada exige motivo
echo; echo "5. regua pulada exige motivo escrito"
tem "a obrigacao de declarar a regua pulada e o motivo" "$CORPO_PLANO" "Régua pulada sem motivo escrito é entrega incompleta"
tem "o relatorio tem secao de reguas aplicadas" "$CORPO" "## Réguas aplicadas"
tem "o template preve PULADA com o motivo" "$CORPO" "**PULADA**"

# ------------------------------------------------- 6. o metodo continua
echo; echo "6. o metodo nao regrediu"
igual "frontmatter declara model: sonnet" "$(sed -n 's/^model: *//p' "$AGENTE" | head -n 1)" "sonnet"
tem "o agente e' proibido de editar o codigo auditado" "$CORPO" "Nunca edite o código auditado"
tem "achar e consertar sao duas passadas" "$CORPO" "parou de procurar"
tem "zero trafego contra endpoint" "$CORPO" "Zero tráfego contra"
tem "o motivo (ambiente de cliente) esta nomeado" "$CORPO" "autorização escrita"
tem "proibicao de transcrever valor de segredo" "$CORPO_PLANO" "**Nunca transcreva o valor**"
tem "o historico do git entra na varredura" "$CORPO" "--diff-filter=A"
tem "Server Actions estao nomeadas como superficie HTTP" "$CORPO" "Server Actions"
tem "a secao de premissas aceitas sem conferir existe" "$CORPO" "Premissas que aceitei sem conferir"

# ------------------------------------------------- 7. reguas citadas, nao copiadas
echo; echo "7. as reguas sao citadas por URL e o texto da OWASP nao foi copiado"
tem "URL da Top 10 2025" "$CORPO" "owasp.org/Top10/2025"
tem "URL da API Security 2023" "$CORPO" "owasp.org/API-Security/editions/2023"
tem "a trava de licenca esta declarada" "$CORPO" "CC BY-SA 4.0"
nao_tem "nao ha boilerplate de licenca da OWASP colado" "$CORPO" "Creative Commons Attribution-ShareAlike"

# ------------------------------------------------- 8. referencia cruzada intacta
# Este caso existe por um achado real da revisao de 2026-08-25: a emenda inseriu
# uma etapa nova no meio do metodo, TODAS as letras seguintes andaram uma casa, e
# tres referencias cruzadas continuaram apontando para a letra velha -- "compare o
# inventario da etapa (a)" passou a apontar para "Decida quais reguas se aplicam".
# O texto ficou coerente aos olhos e errado no conteudo, e nada travava.
echo; echo "8. toda referencia a etapa/item aponta para uma etapa que existe"

LETRAS_EXISTENTES="$(echo "$CORPO" | grep -oE '^### \([a-z]\)' | grep -oE '\([a-z]\)' | tr -d '()' | sort -u | tr '\n' ' ')"
TOTAL_REF="$(echo "$CORPO" | grep -cE '(etapa|item) \([a-z]\)')"

if [ "$TOTAL_REF" -eq 0 ]; then
  falhou=$((falhou+1)); echo "  FALHA nao achei referencia nenhuma a etapa/item — o padrao mudou e este caso parou de medir"
fi

# Parte 1: toda letra referida existe como etapa. Pega o caso grosseiro
# (referencia a uma letra que nao existe).
for L in $(echo "$CORPO" | grep -oE '(etapa|item) \([a-z]\)' | grep -oE '\([a-z]\)' | tr -d '()' | sort -u); do
  if echo " $LETRAS_EXISTENTES " | grep -qF " $L "; then
    ok=$((ok+1)); echo "  ok   referencia a ($L) aponta para etapa existente"
  else
    falhou=$((falhou+1)); echo "  FALHA referencia a ($L) nao existe como etapa"
  fi
done

# Parte 2: TODA ocorrencia de cada frase aponta para a letra CERTA.
#
# A primeira versao desta secao parava na parte 1 mais duas asserções `tem` de
# substring — e a revisao de 2026-08-25 mostrou que isso tinha o mesmo furo que a
# secao existe para pegar. Dois buracos, os dois reais:
#   (a) letra que EXISTE mas aponta para a etapa errada passava. Trocar
#       "etapa (b)" por "etapa (d)" mantinha tudo verde, porque (d) existe.
#   (b) `grep -F` procura a substring no corpo INTEIRO. "inventário da etapa (b)"
#       aparece DUAS vezes; quebrar uma continuava verde por causa da outra.
# Por isso aqui se conta ocorrencia por ocorrencia, e a letra esperada e' cravada
# por frase — nao por presenca.
# Comparação por STRING FIXA de ponta a ponta, sem regex: a frase carrega
# parenteses e asterisco, e escapar isso a mao foi onde a primeira tentativa
# quebrou. `total` conta toda ocorrencia da frase seguida de "(", `certas` conta
# as que trazem a letra esperada, e a diferenca sao as erradas.
confere_ref() {
  local rotulo="$1" frase="$2" esperada="$3" minimo="$4"
  local certas erradas total
  total="$(echo "$CORPO_PLANO" | grep -oF "$frase (" | wc -l | tr -d ' ')"
  certas="$(echo "$CORPO_PLANO" | grep -oF "$frase ($esperada)" | wc -l | tr -d ' ')"
  erradas=$((total - certas))
  if [ "$total" -lt "$minimo" ]; then
    falhou=$((falhou+1)); echo "  FALHA $rotulo: esperava ao menos $minimo ocorrencia(s) de '$frase (X)', achei $total — a frase mudou e este caso parou de medir"
  elif [ "$erradas" -gt 0 ]; then
    falhou=$((falhou+1)); echo "  FALHA $rotulo: $erradas de $total ocorrencia(s) de '$frase' NAO apontam para ($esperada)"
  else
    ok=$((ok+1)); echo "  ok   $rotulo: as $total ocorrencia(s) de '$frase' apontam para ($esperada)"
  fi
}

confere_ref "o inventario e' referido pela etapa que o monta" "inventário da etapa" "b" 2
confere_ref "o formato de achado e' referido pela etapa que o define" "formato da etapa" "e" 1
confere_ref "segredo-por-nome e' referido pelo item que o define" "nunca por valor (item" "h" 1
confere_ref "a regua pulada e' referida pela etapa que a decide" "motivo** (item" "a" 1

# ------------------------------------------------- 9. deduplicacao entre reguas
# A02 e API8 tem o MESMO nome ("Security Misconfiguration") e padroes quase
# identicos: sem instrucao de deduplicacao, o mesmo achado sai duas vezes com
# identificadores diferentes, inflando contagem e veredito.
echo; echo "9. achado que cai nas duas reguas se reporta uma vez"
tem "a colisao A02 x API8 esta nomeada" "$CORPO_PLANO" "Security Misconfiguration\` têm o mesmo nome"
tem "manda reportar no lugar mais especifico" "$CORPO_PLANO" "Reporte no lugar mais específico"
tem "manda deixar referencia cruzada na outra secao" "$CORPO_PLANO" "referência cruzada"
tem "manda contar uma vez" "$CORPO_PLANO" "**Conte uma vez.**"

# ------------------------------------------------- 10. alvo sem web e severidade
# As tres travas desta secao vieram da PRIMEIRA execucao real do agente num alvo
# sem API (o proprio rainforest-mind, 2026-08-25). Ele seguiu o metodo e reportou
# tres pontos em que o arquivo, sozinho, nao bastava -- e os tres sao do mesmo
# tipo: instrucao escrita so' em vocabulario de aplicacao web.
echo; echo "10. o metodo serve a alvo que nao e' web, e severidade tem criterio"
tem "manda TRADUZIR as cinco falhas para alvo sem navegador" "$CORPO_PLANO" "Alvo que não é web: traduza, não pule"
tem "'nao se aplica' sem traducao tentada e' recusado" "$CORPO_PLANO" "sem a tradução tentada é indistinguível"

# A tabela de traducao tem que cobrir AS CINCO. A primeira versao cobria 1, 2, 3
# e 5 -- a falha 4 (segredo) ficou de fora sem nenhuma nota dizendo que era
# proposital, e a propria regra do arquivo ("se a traducao nao fechar, diga que
# nao fechou") nunca chegava a ser aplicada a ela porque ela nao entrava no
# exercicio. Achado da segunda revisao de 2026-08-25.
TRADUCAO="$(echo "$CORPO" | sed -n '/^| a falha, na forma geral |/,/^$/p')"
igual "a tabela de traducao cobre as CINCO falhas" "$(echo "$TRADUCAO" | grep -cE '^\| \*\*[1-5]\.\*\* ')" "5"
for n in 1 2 3 4 5; do
  if echo "$TRADUCAO" | grep -qE "^\| \*\*${n}\.\*\* "; then
    ok=$((ok+1)); echo "  ok   falha $n tem linha na tabela de traducao"
  else
    falhou=$((falhou+1)); echo "  FALHA falha $n nao tem traducao para alvo sem navegador"
  fi
done
tem "a falha 4 tem as duas metades separadas na traducao" "$CORPO_PLANO" "duas metades e elas se traduzem diferente"
tem "A05 cobre argumento de CLI virando shell" "$CORPO_PLANO" "a fonte não é o request — é o argumento"
tem "A05 nomeia a defesa (lista de argumentos, sem shell)" "$CORPO" "execFileSync"
tem "A05 avisa que nome de branch aceita metacaractere" "$CORPO_PLANO" "nome de arquivo e identificador aceitam metacaractere"
tem "severidade tem criterio, nao sensacao" "$CORPO_PLANO" "A severidade tem critério, não é sensação"
tem "criterio de severidade e' ganho + pre-condicao" "$CORPO_PLANO" "o que o atacante ganha"
tem "a fronteira critica/alta esta decidida" "$CORPO_PLANO" "sem autenticação de terceiro, é \`alta\`, não \`crítica\`"

# ------------------------------------------------- 11. orcamento
echo; echo "11. a description cabe no orcamento"
DESC="$(sed -n 's/^description: *//p' "$AGENTE" | head -n 1)"
TAM="$(printf '%s' "$DESC" | wc -c | tr -d ' ')"
if [ "$TAM" -gt 0 ] && [ "$TAM" -le 300 ]; then
  ok=$((ok+1)); echo "  ok   description tem $TAM B (teto de 300 B por agente)"
else
  falhou=$((falhou+1)); echo "  FALHA description tem $TAM B — fora do teto de 300 B por agente"
fi

if node scripts/orcamento.cjs > /dev/null 2>&1; then
  ok=$((ok+1)); echo "  ok   node scripts/orcamento.cjs sai 0 com o agente instalado"
else
  falhou=$((falhou+1)); echo "  FALHA node scripts/orcamento.cjs nao sai 0 com o agente instalado"
fi

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
