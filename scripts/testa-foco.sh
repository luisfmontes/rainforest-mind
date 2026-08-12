#!/bin/bash
# Bateria do scripts/foco.cjs — o script que TIRA texto do arquivo pessoal do usuario.
#
# O que ela precisa provar, em ordem de gravidade:
#
#   1. nada se perde. Entrada que sai do FOCO.md esta no AVANCOS.md, byte a byte —
#      esta e a unica propriedade que, se quebrar, quebra em silencio e so aparece
#      semanas depois, quando alguem for procurar o avanco de um dia especifico;
#   2. sem --aplicar nao escreve. O default do script e falar, nao mexer;
#   3. o corte e por BYTE e mantem os RECENTES. Teto em contagem foi o erro de
#      2026-08-10 na injecao, e a entrada de avanco varia 10x de tamanho;
#   4. pelo menos uma entrada fica sempre, mesmo que sozinha estoure o teto — sem
#      ela o FOCO.md perde a data do ultimo avanco, que e o que a regra 3 mede;
#   5. rodar duas vezes e seguro: nao duplica no historico e nao infla o ponteiro;
#   6. o que vem DEPOIS do bloco (Nao especificado, Fora de escopo, Frentes...)
#      sobrevive intacto — o recorte e por marcador, e marcador erra;
#   7. o hook continua lendo o arquivo rotacionado: `resumirFoco` tem de achar a
#      data do ultimo avanco no FOCO.md com ponteiro no topo do bloco. Se o
#      ponteiro cegar o hook, a rotacao conserta o arquivo e quebra a abertura.
#
# A ultima secao e MUTACAO: quebra o corte de proposito e exige que a bateria acuse.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
# `--` obrigatorio: todo alvo aqui comeca com "- " (entrada de avanco e item de lista),
# e sem ele o grep le o proprio texto procurado como opcao dele.
tem()     { if echo "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

roda() { node "$SRC/scripts/foco.cjs" rotacionar --raiz "$SBP/dados" "$@" 2>&1; }

# ---------------------------------------------------------------- o cenario
# Cinco avancos de tamanho MUITO diferente, que e o caso real medido no FOCO.md do
# usuario: os dois ultimos custam ~1,5 KB cada e os tres primeiros ~600 B cada, entao
# um teto de 3.200 B corta depois do quarto — e cortaria em outro lugar se o teto
# fosse em contagem de entradas.
montar() {
  rm -rf "$SBP/dados"; mkdir -p "$SBP/dados"
  node -e '
    const fs = require("fs");
    const g = (n) => "x".repeat(n);
    const foco = [
      "# Foco", "", "## Ativo", "",
      "**Trabalho de teste** `[trabalho]` — declarado 2026-08-01.",
      "Criterio de pronto: a bateria passar.", "",
      "Avancos:".replace("Avancos", "Avanços"),
      "- 2026-08-01: primeiro avanco, curto. " + g(550),
      "- 2026-08-02: segundo avanco, curto. " + g(550),
      "- 2026-08-03: terceiro avanco, curto. " + g(550),
      "- 2026-08-04: quarto avanco, GRANDE. " + g(1450),
      "- 2026-08-05 (tarde): quinto avanco, GRANDE. " + g(1450),
      "",
      "## Nao especificado ainda", "", "- nevoa preservada", "",
      "## Fora de escopo", "", "- descarte preservado", "",
      "## Frentes", "", "- frente preservada", ""
    ].join("\n");
    fs.writeFileSync(process.argv[1] + "/FOCO.md", foco, "utf8");
    fs.writeFileSync(process.argv[1] + "/ORIGINAL.md", foco, "utf8"); // testemunha da conservacao
  ' "$SBP/dados"
}

# ------------------------------------------------------- 1. sem --aplicar nao escreve
echo; echo "1. ensaio (sem --aplicar)"
montar
ANTES="$(node -e 'console.log(require("fs").statSync(process.argv[1]+"/FOCO.md").size)' "$SBP/dados")"
SAIDA="$(roda --teto 3200)"
DEPOIS="$(node -e 'console.log(require("fs").statSync(process.argv[1]+"/FOCO.md").size)' "$SBP/dados")"
tem "diz o que sairia" "$SAIDA" "sairiam 3 entrada(s)"
tem "avisa que precisa de --aplicar" "$SAIDA" "--aplicar"
igual "FOCO.md intocado" "$DEPOIS" "$ANTES"
if [ -e "$SBP/dados/AVANCOS.md" ]; then falhou=$((falhou+1)); echo "  FALHA nao criou AVANCOS.md no ensaio"; else ok=$((ok+1)); echo "  ok   nao criou AVANCOS.md no ensaio"; fi

# ------------------------------------------------------- 2. corte por byte, recentes ficam
echo; echo "2. corte por byte"
SAIDA="$(roda --teto 3200 --aplicar)"
FOCO="$(cat "$SBP/dados/FOCO.md")"
HIST="$(cat "$SBP/dados/AVANCOS.md")"
tem "os dois grandes (recentes) ficam" "$FOCO" "- 2026-08-05 (tarde): quinto avanco"
tem "o quarto tambem fica" "$FOCO" "- 2026-08-04: quarto avanco"
nao_tem "o primeiro sai do FOCO" "$FOCO" "- 2026-08-01: primeiro avanco"
nao_tem "o terceiro sai do FOCO" "$FOCO" "- 2026-08-03: terceiro avanco"
tem "o primeiro esta no historico" "$HIST" "- 2026-08-01: primeiro avanco"
tem "o terceiro esta no historico" "$HIST" "- 2026-08-03: terceiro avanco"
tem "ponteiro conta as tres que sairam" "$FOCO" "3 avan"
tem "ponteiro aponta o arquivo" "$FOCO" "AVANCOS.md"
tem "ponteiro traz a faixa de datas" "$FOCO" "de 2026-08-01 a 2026-08-03"

# ------------------------------------------------------- 3. nada se perde (byte a byte)
echo; echo "3. conservacao"
PERDIDAS="$(node -e '
  const fs = require("fs");
  const raiz = process.argv[1];
  const orig = fs.readFileSync(raiz + "/ORIGINAL.md", "utf8");
  const foco = fs.readFileSync(raiz + "/FOCO.md", "utf8");
  const hist = fs.readFileSync(raiz + "/AVANCOS.md", "utf8");
  const entradas = orig.split(/\n(?=- \d{4}-\d{2}-\d{2})/).filter((e) => /^- \d{4}/.test(e)).map((e) => e.trim());
  const perdidas = entradas.filter((e) => !foco.includes(e) && !hist.includes(e));
  console.log(perdidas.length ? perdidas.map((p) => p.slice(0, 40)).join(" | ") : "nenhuma");
' "$SBP/dados")"
igual "toda entrada original esta em um dos dois arquivos" "$PERDIDAS" "nenhuma"

# ------------------------------------------------------- 4. secoes seguintes intactas
echo; echo "4. o resto do arquivo"
tem "Nao especificado sobrevive" "$FOCO" "- nevoa preservada"
tem "Fora de escopo sobrevive" "$FOCO" "- descarte preservado"
tem "Frentes sobrevive" "$FOCO" "- frente preservada"

# ------------------------------------------------------- 5. idempotencia
echo; echo "5. rodar de novo"
SAIDA2="$(roda --teto 3200 --aplicar)"
FOCO2="$(cat "$SBP/dados/FOCO.md")"
HIST2="$(cat "$SBP/dados/AVANCOS.md")"
tem "segunda rodada nao acha o que mover" "$SAIDA2" "nada a mover"
igual "historico nao duplicou" "$(grep -c '2026-08-01: primeiro avanco' <<< "$HIST2")" "1"
igual "ponteiro nao inflou" "$(grep -c '3 avan' <<< "$FOCO2")" "1"

# ------------------------------------------------------- 6. minimo de uma entrada
echo; echo "6. piso de uma entrada"
montar
SAIDA="$(roda --teto 10 --aplicar)"
FOCO3="$(cat "$SBP/dados/FOCO.md")"
tem "o ultimo avanco fica mesmo estourando o teto" "$FOCO3" "- 2026-08-05 (tarde): quinto avanco"
igual "sobrou exatamente uma entrada datada" "$(grep -c '^- 2026-08-0' <<< "$FOCO3")" "1"

# ------------------------------------------------------- 7. FOCO.md sem bloco
echo; echo "7. foco sem avancos"
rm -rf "$SBP/dados"; mkdir -p "$SBP/dados"
printf '# Foco\n\n## Ativo\n\n**Recem declarado** — sem avanco nenhum ainda.\n' > "$SBP/dados/FOCO.md"
SAIDA="$(roda --aplicar)"; CODIGO=$?
tem "diz que nao ha o que rotacionar" "$SAIDA" "nada a rotacionar"
igual "sai 0" "$CODIGO" "0"

# ------------------------------------------------------- 8. o hook continua enxergando
echo; echo "8. integracao com a injecao"
montar
roda --teto 3200 --aplicar > /dev/null
INJECAO="$(node -e '
  const fs = require("fs");
  const { resumirFoco } = require(process.argv[1] + "/hooks/lib/contexto-sessao.cjs");
  console.log(resumirFoco(fs.readFileSync(process.argv[2] + "/FOCO.md", "utf8")));
' "$SRC" "$SBP/dados")"
tem "a data icada pelo hook e a mais recente" "$INJECAO" "2026-08-05"
tem "o criterio de pronto continua chegando" "$INJECAO" "Criterio de pronto"
tem "o ponteiro do historico chega junto" "$INJECAO" "AVANCOS.md"

# ------------------------------------------------------- 9. MUTACAO
echo; echo "9. mutacao (a bateria tem de acusar)"
montar
MUT="$SBP/foco-mutante.cjs"
sed 's/mantidas.length >= MIN_ENTRADAS && usado + custo > teto/false/' "$SRC/scripts/foco.cjs" > "$MUT"
node "$MUT" rotacionar --raiz "$SBP/dados" --teto 3200 --aplicar > /dev/null 2>&1
FOCOM="$(cat "$SBP/dados/FOCO.md")"
if grep -qF -- "- 2026-08-01: primeiro avanco" <<< "$FOCOM"; then
  ok=$((ok+1)); echo "  ok   corte desligado mantem tudo no FOCO (mutante detectavel pelo item 2)"
else
  falhou=$((falhou+1)); echo "  FALHA mutante passou despercebido: o corte nao depende do teto"
fi

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
