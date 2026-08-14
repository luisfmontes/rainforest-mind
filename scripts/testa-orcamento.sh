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
#   2. caminho verde: roda contra o repo REAL (sem --teto), sai 0, uma linha
#      por fonte mais o total. E esta asserção que faz a suite do
#      CONTRIBUTING.md:11 acusar quando o plugin engordar alem de 14.000 B.
#   3. caminho vermelho: --teto baixo estoura e sai != 0. Sem esta perna o
#      "gate" so afirma o caminho feliz e nao prova nada.
#
# A ultima secao e MUTACAO: sabota uma COPIA do orcamento.cjs para ignorar o
# teto — o original em scripts/orcamento.cjs nunca e tocado.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
MUT="$SRC/scripts/.orcamento-mutante-teste.cjs"
trap 'rm -rf "$SBP" "$MUT"' EXIT
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
tem()     { if echo "$2" | grep -qF -- "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF -- "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3', veio '$2')"; fi; }

# ------------------------------------------------- 1. caminho verde (repo real)
echo; echo "1. caminho verde — repo real, sem --teto"
SAIDA="$(node "$SRC/scripts/orcamento.cjs" 2>&1)"; CODIGO=$?
igual "sai 0" "$CODIGO" "0"
tem "linha do hook" "$SAIDA" "Hook (additionalContext):"
tem "linha das skills" "$SAIDA" "Skills (descriptions):"
tem "linha dos commands" "$SAIDA" "Commands (descriptions):"
tem "linha dos agentes" "$SAIDA" "Agentes (descriptions):"
tem "linha do total" "$SAIDA" "Total:"
nao_tem "nenhuma fonte medida como 0 B (repo real)" "$SAIDA" ": 0 B"

# ------------------------------------------------- 2. caminho vermelho
echo; echo "2. caminho vermelho — --teto 1000"
SAIDA2="$(node "$SRC/scripts/orcamento.cjs" --teto 1000 2>&1)"; CODIGO2=$?
igual "sai 1" "$CODIGO2" "1"
tem "acusa o estouro do teto agregado" "$SAIDA2" "Estouro do teto agregado"
tem "estouro cita o teto pedido (1000 B)" "$SAIDA2" "> 1000 B"

# ------------------------------------------------- 3. regressao: fonte zerada em CRLF
echo; echo "3. regressao — frontmatter CRLF nao pode medir 0 B"
mkdir -p "$SBP/hooks/lib" "$SBP/skills/exemplo" "$SBP/commands" "$SBP/agents" "$SBP/scripts"
cp "$SRC/scripts/orcamento.cjs" "$SBP/scripts/orcamento.cjs"

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

# ------------------------------------------------- 4. mutacao (a bateria tem de acusar)
echo; echo "4. mutacao — copia do orcamento sabotada para ignorar o teto"
sed 's/process\.exit(tetoExcedido ? 1 : 0);/process.exit(0);/' "$SRC/scripts/orcamento.cjs" > "$MUT"
if ! grep -qF 'process.exit(tetoExcedido ? 1 : 0);' "$MUT"; then
  ok=$((ok+1)); echo "  ok   sabotagem aplicada na copia (scripts/orcamento.cjs original intocado)"
else
  falhou=$((falhou+1)); echo "  FALHA sed nao encontrou a linha a sabotar — mutante nao mutou nada"
fi
SAIDA4="$(node "$MUT" --teto 1000 2>&1)"; CODIGO4=$?
if [ "$CODIGO4" = "0" ]; then
  ok=$((ok+1)); echo "  ok   mutante ignora o estouro real e sai 0 (a asserção da secao 2, contra o original, pegaria isso)"
else
  falhou=$((falhou+1)); echo "  FALHA mutante ainda saiu != 0 — sabotagem nao teve efeito, mutante indetectavel"
fi

echo; echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ] || exit 1
