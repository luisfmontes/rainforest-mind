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

# ============================================================================
# Issue #118 — `backup`: cria .foco-backups/foco-<timestamp>.md com rodízio
# ============================================================================

# ------------------------------------------------------- 9. backup: cria arquivo idêntico
echo; echo "9. backup (cria arquivo idêntico ao original)"
montar
SAIDA="$(node "$SRC/scripts/foco.cjs" backup --raiz "$SBP/dados")"
tem "anuncia que criou o backup" "$SAIDA" "backup:"
BACKUP_FILE="$(ls "$SBP/dados/.foco-backups/foco-"*.md 2>/dev/null | head -1)"
if [ -n "$BACKUP_FILE" ]; then
  cmp "$SBP/dados/FOCO.md" "$BACKUP_FILE"
  if [ $? -eq 0 ]; then
    ok=$((ok+1)); echo "  ok   backup é byte a byte idêntico ao original (cmp)"
  else
    falhou=$((falhou+1)); echo "  FALHA backup não é idêntico ao original"
  fi
else
  falhou=$((falhou+1)); echo "  FALHA nenhum arquivo de backup foi criado"
fi

# ------------------------------------------------------- 10. rodízio converge para o teto numa execução
echo; echo "10. o rodizio do backup guarda no maximo o teto de copias"
montar
rm -rf "$SBP/dados/.foco-backups"; mkdir -p "$SBP/dados/.foco-backups"
# Monta 8 cópias dentro do diretório
for i in 1 2 3 4 5 6 7 8; do
  printf 'teste %d\n' $i > "$SBP/dados/.foco-backups/foco-2026-01-0${i}-000000-000.md"
  sleep 0.01  # Garante order por sort
done
COUNT_ANTES="$(ls "$SBP/dados/.foco-backups/foco-"*.md 2>/dev/null | wc -l)"
# Roda UMA vez com teto 3 — deve convergir para 3
TETO=3
node "$SRC/scripts/foco.cjs" backup --teto $TETO --raiz "$SBP/dados" > /dev/null 2>&1
COUNT_DEPOIS="$(ls "$SBP/dados/.foco-backups/foco-"*.md 2>/dev/null | wc -l)"
igual "diretorio tinha 8, teto e 3, apos uma execucao sobram exatamente 3" "$COUNT_DEPOIS" "3"

# ------------------------------------------------------- 11. backup: FOCO.md ausente
echo; echo "11. backup com FOCO.md ausente"
rm -rf "$SBP/dados"; mkdir -p "$SBP/dados"
SAIDA="$(node "$SRC/scripts/foco.cjs" backup --raiz "$SBP/dados" 2>&1)"; CODIGO=$?
tem "nomeia o arquivo que não achou" "$SAIDA" "FOCO.md"
igual "sai com código 1 (erro)" "$CODIGO" "1"
if [ ! -d "$SBP/dados/.foco-backups" ]; then
  ok=$((ok+1)); echo "  ok   não criou diretório .foco-backups"
else
  falhou=$((falhou+1)); echo "  FALHA criou diretório mesmo com erro"
fi

# ------------------------------------------------------- 12. .foco-backups está no .gitignore
echo; echo "12. git check-ignore .foco-backups"
(cd "$SRC" && git check-ignore ".foco-backups/test.md" > /dev/null 2>&1)
if [ $? -eq 0 ]; then
  ok=$((ok+1)); echo "  ok   .foco-backups é ignorado pelo git"
else
  falhou=$((falhou+1)); echo "  FALHA .foco-backups não está no .gitignore"
fi

# ------------------------------------------------------- 13. MUTACAO do backup (desligar o laço de poda)
echo; echo "13. mutacao backup (a bateria tem de acusar)"
montar
rm -rf "$SBP/dados/.foco-backups"; mkdir -p "$SBP/dados/.foco-backups"
# Monta 8 cópias
for i in 1 2 3 4 5 6 7 8; do
  printf 'teste %d\n' $i > "$SBP/dados/.foco-backups/foco-2026-01-0${i}-000000-000.md"
  sleep 0.01
done
MUT_BACKUP="$SBP/foco-mutante-backup.cjs"
# Mutação: trocar "while (arquivos.length > teto)" por "while (false)"
node -e "
  const fs = require('fs');
  const content = fs.readFileSync(process.argv[1], 'utf8');
  const mutated = content.replace(
    /while \(arquivos\.length > teto\)/,
    'while (false)'
  );
  if (content === mutated) {
    console.error('MUTACAO_NAO_ENCONTRADA');
    process.exit(1);
  }
  fs.writeFileSync(process.argv[2], mutated, 'utf8');
" "$SRC/scripts/foco.cjs" "$MUT_BACKUP"
node "$MUT_BACKUP" backup --teto 3 --raiz "$SBP/dados" > /dev/null 2>&1
COUNT_MUT="$(ls "$SBP/dados/.foco-backups/foco-"*.md 2>/dev/null | wc -l)"
if [ "$COUNT_MUT" -gt 3 ]; then
  ok=$((ok+1)); echo "  ok   desligar o laço de poda mantem tudo (mutante detectavel)"
else
  falhou=$((falhou+1)); echo "  FALHA mutante passou despercebido: a poda rodou mesmo com while(false)"
fi
rm -f "$MUT_BACKUP"

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

# ============================================================================
# Issue #74 — `separar`: FOCO.md monolitico -> FOCO.md (tatico) + ESTRATEGIA.md
# ============================================================================
#
# RODADA 2 (retrabalho): a bateria original roteava por LINHA, e a fixture
# tinha uma linha por sentenca -- por construcao, nao podia expor o defeito
# real (prosa com quebra dura em ~80 colunas, varias linhas por frase). Contra
# o FOCO.md de verdade do usuario, o roteamento por linha cortava frases no
# meio. A partir daqui o roteamento e por PARAGRAFO (bloco separado por linha
# em branco) -- um paragrafo vai INTEIRO para um lado ou outro, nunca partido.
#
# O que esta bateria precisa provar, na mesma ordem de gravidade da secao acima:
#   10. sem --aplicar nao escreve nada (mesma garantia de sempre);
#   11. os campos que o HOOK le por regex direto do FOCO.md (titulo/natureza,
#       Pastas:, Ociosidade maxima:, Critério de pronto, Marcos, Avancos,
#       Compromissos com prazo) ficam no arquivo TATICO; um paragrafo de prosa
#       SEPARADO (com linha em branco antes e depois) vai inteiro pro
#       ESTRATEGIA.md, junto com as secoes nao-residentes;
#   12. nada se perde — toda linha do original esta em UM dos dois arquivos;
#   13. `separar` e migracao de UMA VEZ: recusa sobrescrever ESTRATEGIA.md;
#   14. PROSA QUEBRADA EM VARIAS LINHAS (o caso que faltava): um paragrafo de
#       contexto com quebra dura de linha, como o arquivo real, sobrevive
#       INTEIRO e JUNTO no ESTRATEGIA.md -- nenhuma linha isolada, nenhuma
#       frase cortada no meio;
#   15. MUTACAO — desligar o roteamento por PARAGRAFO (faze-lo decidir por
#       LINHA de novo) tem que voltar a partir o paragrafo de prosa.

montar_split() {
  rm -rf "$SBP/dados"; mkdir -p "$SBP/dados"
  node -e '
    const fs = require("fs");
    const foco = [
      "# Foco", "",
      "## Ativo", "",
      "Prosa-meta sintetica sobre o formato do arquivo, sem campo tatico nenhum aqui.", "",
      "**Projeto Teste Separar** `[trabalho]` \u2014 declarado 2026-08-01.",
      "Pastas: C:/tmp/a",
      "        C:/tmp/b",
      "Ociosidade m\u00e1xima: 10 min.",
      "Prazo: entrega em 2026-09-01.",
      "Crit\u00e9rio de pronto: a bateria passar.", "",
      "Prosa de contexto de negocio, com uma justificativa historica que nao muda toda semana.", "",
      "Marcos (cronograma):",
      "- Marco 1 -- 2026-08-10.", "",
      "Avan\u00e7os:",
      "- 2026-08-01: primeiro avanco.", "",
      "## N\u00e3o especificado ainda", "", "- nevoa preservada", "",
      "## Fora de escopo", "", "- descarte preservado", "",
      "## Compromissos com prazo", "", "- compromisso preservado 2026-09-01", "",
      "## Frentes", "", "- frente preservada", "",
      "## Conclu\u00eddos", "", "- concluido preservado", "",
    ].join("\n");
    fs.writeFileSync(process.argv[1] + "/FOCO.md", foco, "utf8");
    fs.writeFileSync(process.argv[1] + "/ORIGINAL.md", foco, "utf8");
  ' "$SBP/dados"
}

echo; echo "10. separar: dry-run nao escreve nada"
montar_split
SAIDA="$(node "$SRC/scripts/foco.cjs" separar --raiz "$SBP/dados" 2>&1)"
tem "mostra o plano" "$SAIDA" "Plano:"
tem "avisa que precisa de --aplicar" "$SAIDA" "--aplicar"
if [ -e "$SBP/dados/ESTRATEGIA.md" ]; then
  falhou=$((falhou+1)); echo "  FALHA criou ESTRATEGIA.md no ensaio"
else
  ok=$((ok+1)); echo "  ok   nao criou ESTRATEGIA.md no ensaio"
fi

echo; echo "11. separar --aplicar: campos taticos ficam no FOCO.md, paragrafo de prosa vai inteiro pro ESTRATEGIA.md"
node "$SRC/scripts/foco.cjs" separar --raiz "$SBP/dados" --aplicar > /dev/null
FOCOS="$(cat "$SBP/dados/FOCO.md")"
EST="$(cat "$SBP/dados/ESTRATEGIA.md")"
tem "titulo/natureza/data ficam no tatico"        "$FOCOS" "Projeto Teste Separar"
tem "Pastas: fica no tatico"                      "$FOCOS" "Pastas: C:/tmp/a"
tem "continuacao de Pastas fica no tatico"        "$FOCOS" "C:/tmp/b"
tem "Ociosidade fica no tatico"                   "$FOCOS" "Ociosidade máxima: 10 min"
tem "Critério de pronto fica no tatico"           "$FOCOS" "Critério de pronto"
tem "Marcos ficam no tatico"                      "$FOCOS" "Marco 1"
tem "Avancos ficam no tatico"                     "$FOCOS" "primeiro avanco"
tem "Compromissos com prazo fica no tatico"       "$FOCOS" "compromisso preservado"
nao_tem "paragrafo de prosa sai do tatico"        "$FOCOS" "justificativa"
tem "paragrafo de prosa vai pro estrategico"      "$EST" "justificativa"
tem "Nao especificado vai pro estrategico"        "$EST" "nevoa preservada"
tem "Fora de escopo vai pro estrategico"          "$EST" "descarte preservado"
tem "Frentes vai pro estrategico"                 "$EST" "frente preservada"
tem "Concluidos vai pro estrategico"              "$EST" "concluido preservado"
nao_tem "estrategico nao carrega Compromissos"    "$EST" "compromisso preservado"

echo; echo "12. separar: nada se perde (toda linha do original esta em um dos dois arquivos)"
PERDIDAS="$(node -e '
  const fs = require("fs");
  const raiz = process.argv[1];
  const orig = fs.readFileSync(raiz + "/ORIGINAL.md", "utf8");
  const foco = fs.readFileSync(raiz + "/FOCO.md", "utf8");
  const est = fs.readFileSync(raiz + "/ESTRATEGIA.md", "utf8");
  const linhas = orig.split("\n").map((l) => l.trim()).filter(Boolean);
  const perdidas = linhas.filter((l) => !foco.includes(l) && !est.includes(l));
  console.log(perdidas.length ? perdidas.join(" | ") : "nenhuma");
' "$SBP/dados")"
igual "toda linha original esta em um dos dois arquivos" "$PERDIDAS" "nenhuma"

echo; echo "13. separar: recusa sobrescrever ESTRATEGIA.md existente"
SAIDA="$(node "$SRC/scripts/foco.cjs" separar --raiz "$SBP/dados" --aplicar 2>&1)"; CODIGO=$?
tem "recusa com mensagem clara" "$SAIDA" "já existe"
igual "sai com erro (nao silencioso)" "$CODIGO" "1"

echo; echo "14. prosa quebrada em varias linhas (o caso que faltava) nao e cortada no meio"
montar_quebrada() {
  rm -rf "$SBP/dados"; mkdir -p "$SBP/dados"
  node -e '
    const fs = require("fs");
    const foco = [
      "# Foco", "",
      "## Ativo", "",
      "**Projeto Prosa Quebrada** `[trabalho]` \u2014 declarado 2026-08-01.",
      "Pastas: C:/tmp/quebrado",
      "Crit\u00e9rio de pronto: a bateria passar.", "",
      "Esta e uma prosa de contexto de negocio propositalmente quebrada em varias",
      "linhas curtas, imitando o arquivo real do usuario, que envolve justificativa",
      "historica e nao deveria ser cortada no meio de nenhuma frase durante o",
      "processo de separacao entre o arquivo tatico e o estrategico.", "",
      "Marcos (cronograma):",
      "- Marco 1 -- 2026-08-10.", ""
    ].join("\n");
    fs.writeFileSync(process.argv[1] + "/FOCO.md", foco, "utf8");
  ' "$SBP/dados"
}
montar_quebrada
node "$SRC/scripts/foco.cjs" separar --raiz "$SBP/dados" --aplicar > /dev/null
FOCOQ="$(cat "$SBP/dados/FOCO.md")"
ESTQ="$(cat "$SBP/dados/ESTRATEGIA.md")"
tem "identidade (com Pastas e Criterio) fica inteira no tatico" "$FOCOQ" "Projeto Prosa Quebrada"
tem "Criterio de pronto continua no mesmo paragrafo tatico"     "$FOCOQ" "Critério de pronto"
nao_tem "nenhuma linha da prosa quebrada vaza pro tatico"       "$FOCOQ" "justificativa"
CONFERE="$(node -e '
  const fs = require("fs");
  const raiz = process.argv[1];
  const foco = fs.readFileSync(raiz + "/FOCO.md", "utf8");
  const est = fs.readFileSync(raiz + "/ESTRATEGIA.md", "utf8");
  // O paragrafo de prosa quebrada, EXATAMENTE como foi escrito (4 linhas
  // coladas por \n) -- se sobreviveu inteiro e junto, este bloco aparece
  // como substring continua em UM dos dois arquivos.
  const paragrafo = [
    "Esta e uma prosa de contexto de negocio propositalmente quebrada em varias",
    "linhas curtas, imitando o arquivo real do usuario, que envolve justificativa",
    "historica e nao deveria ser cortada no meio de nenhuma frase durante o",
    "processo de separacao entre o arquivo tatico e o estrategico.",
  ].join("\n");
  const noFoco = foco.includes(paragrafo);
  const noEst = est.includes(paragrafo);
  console.log(JSON.stringify({ noFoco, noEst }));
' "$SBP/dados")"
tem "o paragrafo de 4 linhas sobrevive INTEIRO e JUNTO (nao partido)" "$CONFERE" '"noEst":true'
tem "e nao ficou nenhum pedaco dele no tatico"                        "$CONFERE" '"noFoco":false'

echo; echo "15. MUTACAO — desligar o roteamento por PARAGRAFO tem que voltar a partir a prosa quebrada"
montar_quebrada
MUT="$SBP/foco-mut-paragrafo.cjs"
# sed com classes de regex dentro de regex (\n{2,}) e fragil de escapar
# corretamente em shell; a troca e feita em JS puro, por substring exata.
node -e '
  const fs = require("fs");
  const src = process.argv[1], dst = process.argv[2];
  const t = fs.readFileSync(src, "utf8");
  const alvo = ".split(/\\n{2,}/)";
  const novo = ".split(/\\n/)";
  if (!t.includes(alvo)) { console.error("ANCORA_NAO_ENCONTRADA"); process.exit(1); }
  fs.writeFileSync(dst, t.split(alvo).join(novo), "utf8");
' "$SRC/scripts/foco.cjs" "$MUT"
if [ ! -s "$MUT" ] || diff -q "$SRC/scripts/foco.cjs" "$MUT" > /dev/null; then
  falhou=$((falhou+1)); echo "  FALHA a mutacao nao encontrou o split por paragrafo -- teste invalido"
else
  node "$MUT" separar --raiz "$SBP/dados" --aplicar > /dev/null 2>&1
  FOCOM="$(cat "$SBP/dados/FOCO.md" 2>/dev/null)"
  # Com o roteamento voltando a ser por LINHA, a primeira linha da prosa
  # quebrada ("Esta e uma prosa...") nao comeca com `**` -- deixa de ser
  # reconhecida como continuacao do paragrafo de identidade e cai solta;
  # o sintoma observavel e a prosa aparecer FRAGMENTADA (a primeira linha
  # separada das demais) em vez de sobreviver inteira e junta no estrategico.
  ESTM="$(cat "$SBP/dados/ESTRATEGIA.md" 2>/dev/null)"
  CONFEREM="$(node -e '
    const fs = require("fs");
    const raiz = process.argv[1];
    const est = fs.existsSync(raiz + "/ESTRATEGIA.md") ? fs.readFileSync(raiz + "/ESTRATEGIA.md", "utf8") : "";
    const paragrafo = [
      "Esta e uma prosa de contexto de negocio propositalmente quebrada em varias",
      "linhas curtas, imitando o arquivo real do usuario, que envolve justificativa",
      "historica e nao deveria ser cortada no meio de nenhuma frase durante o",
      "processo de separacao entre o arquivo tatico e o estrategico.",
    ].join("\n");
    console.log(JSON.stringify({ paragrafoIntacto: est.includes(paragrafo) }));
  ' "$SBP/dados")"
  if echo "$CONFEREM" | grep -qF '"paragrafoIntacto":false'; then
    ok=$((ok+1)); echo "  ok   mutacao expos que o roteamento por paragrafo e o que mantem a prosa inteira"
  else
    falhou=$((falhou+1)); echo "  FALHA mutante passou despercebido: a prosa continuou intacta mesmo roteando por linha"
  fi
fi
rm -f "$MUT"

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
