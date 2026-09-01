#!/bin/bash
# Bateria do scripts/orcamento.cjs — o script que MEDE em bytes o custo do
# rainforest-mind (hook + descriptions de skills/commands/agentes) e acusa
# quando estoura os tetos.
#
# O que ela precisa provar, em ordem de gravidade:
#
#   1. regressao da fonte zerada. A primeira versao do extrator de description
#      usava um regex sem tolerar \r, e num checkout Windows (CRLF) o bloco de
#      frontmatter nao casava: a funcao devolvia string vazia e a fonte inteira
#      era medida como 0 B, em silencio. O efeito medido em 2026-08-13 foi
#      "Agentes: 0 B" e total de 11.472 B, contra 1.618 B e 13.604 B depois da
#      correcao. Um instrumento que subestima assim nunca dispara o gate que
#      ele existe para disparar. Fixture com CRLF de proposito.
#   2. caminho verde: roda contra raiz NEUTRA (sem FOCO.md), sai 0, uma linha
#      por fonte mais o total. É esta medição que o CI usa e que a máquina
#      do dono deve também passar.
#   3. caminho vermelho: --teto baixo estoura e sai != 0. Sem esta perna o
#      "gate" so afirma o caminho feliz e nao prova nada.
#   4. D8 — references/ fica fora do gate agregado. medirSkills (:104-121) mede
#      so o SKILL.md de cada pasta; references/ nao e contexto residente, so
#      entra quando alguem le um arquivo especifico. Fixture com e sem
#      references/ pesado (~10 KB) tem de medir o MESMO total — se algum dia o
#      medidor passar a varrer a pasta inteira, esta asserção acusa antes do
#      gate reprovar a propria quebra de skills-finas-com-references no dia
#      seguinte a entrega.
#
# A ultima secao e MUTACAO: sabota uma COPIA do orcamento.cjs para ignorar o
# teto — o original em scripts/orcamento.cjs nunca e tocado.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
SBP2="$(mktemp -d)"
RAIZ_GORDA="$(mktemp -d)"
node -e "require('fs').writeFileSync(process.argv[1]+'/FOCO.md','# Foco\n\n'+'x'.repeat(2500))" "$RAIZ_GORDA"
RAIZ_VAZIA="$(mktemp -d)"
MUT="$SRC/scripts/.orcamento-mutante-teste.cjs"
trap 'rm -rf "$SBP" "$SBP2" "$RAIZ_VAZIA" "$RAIZ_GORDA" "$MUT"' EXIT
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
tem()     { if echo "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

# ------------------------------------------------- 1. caminho verde (raiz neutra)
echo; echo "1. caminho verde — raiz neutra, sem FOCO.md"
SAIDA="$(RFM_ROOT="$RAIZ_VAZIA" node "$SRC/scripts/orcamento.cjs" 2>&1)"; CODIGO=$?
igual "sai 0" "$CODIGO" "0"
tem "linha do hook" "$SAIDA" "Hook (additionalContext):"
tem "linha das skills" "$SAIDA" "Skills (descriptions):"
tem "linha dos commands" "$SAIDA" "Commands (descriptions):"
tem "linha dos agentes" "$SAIDA" "Agentes (descriptions):"
tem "linha do total" "$SAIDA" "Total:"
nao_tem "nenhuma fonte medida como 0 B (repo em raiz neutra)" "$SAIDA" ": 0 B"

# ------------------------------------------------- 1a. medição da mesa (informacional)
echo; echo "1a. medição da mesa — raiz real, informa e nao conta"
SAIDA_MESA="$(node "$SRC/scripts/orcamento.cjs" 2>&1)"; CODIGO_MESA=$?
TOTAL_MESA="$(echo "$SAIDA_MESA" | sed -n 's/^Total: \([0-9]\+\) B$/\1/p')"
echo "  info total na mesa: $TOTAL_MESA B (exit $CODIGO_MESA)"

# ------------------------------------------------- 1b. invariância — raiz neutra estável mesmo com RAIZ_GORDA plantada
echo; echo "1b. invariancia — medição neutra nao muda mesmo com raiz pesada plantada"
# Primeira medição de raiz vazia (baseline)
SAIDA_VAZIA_1="$(RFM_ROOT="$RAIZ_VAZIA" node "$SRC/scripts/orcamento.cjs" 2>&1)"; CODIGO_VAZIA_1=$?
TOTAL_VAZIA_1="$(echo "$SAIDA_VAZIA_1" | sed -n 's/^Total: \([0-9]\+\) B$/\1/p')"
# Medição com RAIZ_GORDA para comprovar que ela é detectada e muda o resultado
SAIDA_GORDA="$(RFM_ROOT="$RAIZ_GORDA" node "$SRC/scripts/orcamento.cjs" 2>&1)"; CODIGO_GORDA=$?
TOTAL_GORDA="$(echo "$SAIDA_GORDA" | sed -n 's/^Total: \([0-9]\+\) B$/\1/p')"
# Segunda medição de raiz vazia (confirma que continua igual mesmo com RAIZ_GORDA no disco)
SAIDA_VAZIA_2="$(RFM_ROOT="$RAIZ_VAZIA" node "$SRC/scripts/orcamento.cjs" 2>&1)"; CODIGO_VAZIA_2=$?
TOTAL_VAZIA_2="$(echo "$SAIDA_VAZIA_2" | sed -n 's/^Total: \([0-9]\+\) B$/\1/p')"
igual "primeira medição neutra sai 0" "$CODIGO_VAZIA_1" "0"
# O sinal de "raiz gorda" deixou de poder ser o EXIT CODE, em 2026-08-25, e a razao
# nao e afrouxamento: o hook e limitado POR CONSTRUCAO a ORCAMENTO_BYTES (8.000),
# porque `tetoFoco = ORCAMENTO - fixo`. O maximo que o agregado pode atingir e
# 8.000 + as descricoes (~6.752) = ~14.752 B, abaixo do teto de 15.000 — nenhum
# FOCO.md, por maior que seja, faz o agregado estourar. Manter a assercao de exit
# aqui seria manter um teste que so pode ficar vermelho, e o caminho vermelho de
# verdade ja e coberto pela secao 2 (`--teto 1000`).
#
# O que continua discriminando: a raiz gorda empurra o HOOK ate encostar no teto
# dele. Raiz vazia nao encosta. Se a medicao parar de reagir ao tamanho do FOCO.md
# — que e o defeito que esta secao existe para pegar —, os dois ficam iguais.
HOOK_GORDA="$(echo "$SAIDA_GORDA" | sed -n 's/^Hook (additionalContext): \([0-9]\+\) B$/\1/p')"
HOOK_VAZIA="$(echo "$SAIDA_VAZIA_1" | sed -n 's/^Hook (additionalContext): \([0-9]\+\) B$/\1/p')"
if [ "$HOOK_GORDA" -gt "$HOOK_VAZIA" ]; then ok=$((ok+1)); echo "  ok   raiz gorda e detectada (hook $HOOK_GORDA B > vazia $HOOK_VAZIA B)"; else falhou=$((falhou+1)); echo "  FALHA raiz gorda nao mexeu no hook: gorda=$HOOK_GORDA vazia=$HOOK_VAZIA"; fi
if [ "$TOTAL_GORDA" -gt "$TOTAL_VAZIA_1" ]; then ok=$((ok+1)); echo "  ok   raiz gorda tem total maior"; else falhou=$((falhou+1)); echo "  FALHA raiz gorda tem total maior"; fi
igual "segunda medição neutra ainda sai 0 (mesmo com RAIZ_GORDA plantada)" "$CODIGO_VAZIA_2" "0"
igual "total neutro nao muda (neutralizacao provada, independente de raiz alternativa)" "$TOTAL_VAZIA_2" "$TOTAL_VAZIA_1"

# ------------------------------------------------- 1c. valores congelados (D6)
echo; echo "1c. valores congelados (D6) — constantes no teto nao mudam"
NUCLEOS_CHECK="$(grep -c 'NUCLEOS_MAX_BYTES: 5600' "$SRC/hooks/lib/contexto-sessao.cjs" 2>/dev/null || echo 0)"
ORCAMENTO_CHECK="$(grep -c 'ORCAMENTO_BYTES: 8000' "$SRC/hooks/lib/contexto-sessao.cjs" 2>/dev/null || echo 0)"
FOCO_MAX_CHECK="$(grep -c 'FOCO_MAX_BYTES: 2600' "$SRC/hooks/lib/contexto-sessao.cjs" 2>/dev/null || echo 0)"
FOCO_MIN_CHECK="$(grep -c 'FOCO_MIN_BYTES: 700' "$SRC/hooks/lib/contexto-sessao.cjs" 2>/dev/null || echo 0)"
TETO_AGREGADO_CHECK="$(grep -c '|| 15000' "$SRC/scripts/orcamento.cjs" 2>/dev/null || echo 0)"

if [ "$NUCLEOS_CHECK" -ge 1 ] && [ "$ORCAMENTO_CHECK" -ge 1 ] && [ "$FOCO_MAX_CHECK" -ge 1 ] && [ "$FOCO_MIN_CHECK" -ge 1 ] && [ "$TETO_AGREGADO_CHECK" -ge 1 ]; then
  ok=$((ok+1)); echo "  ok   D6: constantes congeladas (agregado revisado em 2026-08-25, Issue #74)"
else
  falhou=$((falhou+1)); echo "  FALHA D6: constantes mudaram. tetoFoco real e 1.841 B contra 2.600 nominais (nucleos comeram); NUCLEOS=$NUCLEOS_CHECK, ORCAMENTO=$ORCAMENTO_CHECK, FOCO_MAX=$FOCO_MAX_CHECK, FOCO_MIN=$FOCO_MIN_CHECK, TETO_AGR=$TETO_AGREGADO_CHECK"
fi

# ------------------------------------------------- 1d. banda de aviso — avisos nao disparam exit 1
echo; echo "1d. banda de aviso — avisos nao disparam exit 1"
# Com raiz neutra, total esta ok (exit 0). Agora testa o comportamento de aviso
# configurando um teto que faça a medição cair na banda de aviso (5% por padrão).
# O que se prova aqui e o COMPORTAMENTO do aviso (aparece, e nao vira exit 1) —
# nao o tamanho absoluto do agregado, que ja e coberto pela secao 2 (--teto 1000)
# e pela catraca de nucleo em hooks/testa-contexto-sessao.sh.
#
# Ate 2026-09-01 o teto vinha chumbado em 13.500 B, calculado sobre uma medicao
# neutra de ~13.126 B. O repo cresceu: em 01/09 a medicao neutra ja era 13.613 B,
# e o teto chumbado virou ESTOURO em vez de aviso — a bateria ficou vermelha sem
# que nada do que ela testa tivesse quebrado. O teto agora e DERIVADO da medicao,
# entao ele acompanha o repo: teto = total + 1 B deixa folga 1 B, sempre abaixo
# do limiar de 5%, logo sempre na banda de aviso.
TOTAL_NEUTRO="$(RFM_ROOT="$RAIZ_VAZIA" node "$SRC/scripts/orcamento.cjs" 2>&1 | sed -n 's/^Total: \([0-9]\+\) B$/\1/p')"
TETO_AVISO=$((TOTAL_NEUTRO + 1))
echo "  info total neutro $TOTAL_NEUTRO B, teto derivado $TETO_AVISO B (folga 1 B, dentro da banda de aviso)"
SAIDA_AVISO="$(RFM_ROOT="$RAIZ_VAZIA" node "$SRC/scripts/orcamento.cjs" --teto "$TETO_AVISO" 2>&1)"; CODIGO_AVISO=$?
tem "aviso de folga em agregado aparece na mensagem" "$SAIDA_AVISO" "Aviso de folga em agregado"
igual "mas exit é 0, aviso nao vira erro" "$CODIGO_AVISO" "0"

# ------------------------------------------------- 2. caminho vermelho
echo; echo "2. caminho vermelho — --teto 1000"
SAIDA2="$(node "$SRC/scripts/orcamento.cjs" --teto 1000 2>&1)"; CODIGO2=$?
igual "sai 1" "$CODIGO2" "1"
tem "acusa o estouro do teto agregado" "$SAIDA2" "Estouro de agregado"
tem "estouro cita o teto pedido (1000 B)" "$SAIDA2" "> 1000 B"

# ------------------------------------------------- 3. regressao: fonte zerada em CRLF
echo; echo "3. regressao — frontmatter CRLF nao pode medir 0 B"
mkdir -p "$SBP/hooks/lib" "$SBP/skills/exemplo" "$SBP/commands" "$SBP/agents" "$SBP/scripts"
cp "$SRC/scripts/orcamento.cjs" "$SBP/scripts/orcamento.cjs"
cp "$SRC/hooks/lib/folga.cjs" "$SBP/hooks/lib/folga.cjs"

# lib fake: so precisa conter o ORCAMENTO_BYTES que o script real le por regex
# (nunca digitado — lido de la, igual o script de producao faz do original).
printf 'module.exports = { TETOS: { ORCAMENTO_BYTES: 8000 } };\n' > "$SBP/hooks/lib/contexto-sessao.cjs"

# hook fake: additionalContext de tamanho conhecido (500 B, so 'x').
node -e '
  const fs = require("fs");
  fs.writeFileSync(process.argv[1], "#!/usr/bin/env node\nconsole.log(JSON.stringify({hookSpecificOutput:{additionalContext:\"x\".repeat(500)}}));\n");
' "$SBP/hooks/foco-session-start.cjs"

DESC_SKILL="Skill de exemplo para a fixture do orcamento"
DESC_CMD="Command de exemplo para a fixture do orcamento"
DESC_AGENTE="Agente de exemplo em CRLF para a fixture do orcamento"

printf -- '---\nname: exemplo\ndescription: %s\n---\ncorpo\n' "$DESC_SKILL" > "$SBP/skills/exemplo/SKILL.md"
printf -- '---\ndescription: %s\n---\ncorpo\n' "$DESC_CMD" > "$SBP/commands/exemplo.md"
# agente em CRLF de proposito — e o caso que quebrou em 2026-08-13.
printf -- '---\r\ndescription: %s\r\n---\r\ncorpo\r\n' "$DESC_AGENTE" > "$SBP/agents/exemplo.md"

SAIDA3="$(node "$SBP/scripts/orcamento.cjs" 2>&1)"; CODIGO3=$?
igual "fixture fica dentro dos tetos, sai 0" "$CODIGO3" "0"
nao_tem "nenhuma fonte medida como 0 B (fixture)" "$SAIDA3" ": 0 B"
tem "hook fake mediu os 500 B esperados" "$SAIDA3" "Hook (additionalContext): 500 B"

BYTES_SKILL="$(printf '%s' "$DESC_SKILL" | wc -c)"
BYTES_CMD="$(printf '%s' "$DESC_CMD" | wc -c)"
BYTES_AGENTE="$(printf '%s' "$DESC_AGENTE" | wc -c)"
tem "skill mediu exatamente os bytes da description" "$SAIDA3" "Skills (descriptions): $BYTES_SKILL B"
tem "command mediu exatamente os bytes da description" "$SAIDA3" "Commands (descriptions): $BYTES_CMD B"
tem "agente CRLF teve a description extraida (bytes exatos, sem \r sobrando)" "$SAIDA3" "Agentes (descriptions): $BYTES_AGENTE B"

# ------------------------------------------------- 4. D8 — references/ fora do gate agregado
echo; echo "4. D8 — references/ nao pode mudar o total agregado"
mkdir -p "$SBP2/hooks/lib" "$SBP2/skills/exemplo" "$SBP2/commands" "$SBP2/agents" "$SBP2/scripts"
cp "$SRC/scripts/orcamento.cjs" "$SBP2/scripts/orcamento.cjs"
cp "$SRC/hooks/lib/folga.cjs" "$SBP2/hooks/lib/folga.cjs"

printf 'module.exports = { TETOS: { ORCAMENTO_BYTES: 8000 } };\n' > "$SBP2/hooks/lib/contexto-sessao.cjs"
node -e '
  const fs = require("fs");
  fs.writeFileSync(process.argv[1], "#!/usr/bin/env node\nconsole.log(JSON.stringify({hookSpecificOutput:{additionalContext:\"x\".repeat(500)}}));\n");
' "$SBP2/hooks/foco-session-start.cjs"
printf -- '---\nname: exemplo\ndescription: Skill de exemplo para a fixture do D8\n---\ncorpo\n' > "$SBP2/skills/exemplo/SKILL.md"

# cenario A: pasta de skill SEM references/
SAIDA4A="$(node "$SBP2/scripts/orcamento.cjs" 2>&1)"; CODIGO4A=$?
TOTAL_4A="$(echo "$SAIDA4A" | sed -n 's/^Total: \([0-9]\+\) B$/\1/p')"

# cenario B: a MESMA pasta, agora com references/ pesado (~10 KB — grande o
# suficiente para que somar os arquivos mudasse o total de forma inequivoca).
mkdir -p "$SBP2/skills/exemplo/references"
node -e '
  const fs = require("fs");
  const path = require("path");
  const dir = process.argv[1];
  for (const n of [1, 2]) {
    fs.writeFileSync(path.join(dir, "regra-" + n + ".md"), "x".repeat(5120));
  }
' "$SBP2/skills/exemplo/references"

SAIDA4B="$(node "$SBP2/scripts/orcamento.cjs" 2>&1)"; CODIGO4B=$?
TOTAL_4B="$(echo "$SAIDA4B" | sed -n 's/^Total: \([0-9]\+\) B$/\1/p')"

igual "cenario A (sem references/) sai 0" "$CODIGO4A" "0"
igual "cenario B (com references/ de ~10 KB) sai 0" "$CODIGO4B" "0"
igual "total agregado nao muda quando references/ aparece (D8)" "$TOTAL_4B" "$TOTAL_4A"

# ------------------------------------------------- 5. mutacao (a bateria tem de acusar)
echo; echo "5. mutacao — copia do orcamento sabotada para ignorar o teto"
sed 's/process\.exit(tetoExcedido ? 1 : 0);/process.exit(0);/' "$SRC/scripts/orcamento.cjs" > "$MUT"
if ! grep -qF 'process.exit(tetoExcedido ? 1 : 0);' "$MUT"; then
  ok=$((ok+1)); echo "  ok   sabotagem aplicada na copia (scripts/orcamento.cjs original intocado)"
else
  falhou=$((falhou+1)); echo "  FALHA sed nao encontrou a linha a sabotar — mutante nao mutou nada"
fi
SAIDA5="$(node "$MUT" --teto 1000 2>&1)"; CODIGO5=$?
if [ "$CODIGO5" = "0" ]; then
  ok=$((ok+1)); echo "  ok   mutante ignora o estouro real e sai 0 (a asserção da secao 2, contra o original, pegaria isso)"
else
  falhou=$((falhou+1)); echo "  FALHA mutante ainda saiu != 0 — sabotagem nao teve efeito, mutante indetectavel"
fi

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
