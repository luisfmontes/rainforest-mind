#!/bin/bash
# Bateria do scripts/semear.cjs — o coletor que alimenta a skill `semear`.
#
# O que precisa provar, nesta ordem de importancia:
#   1. que ele ACHA as observacoes do projeto mesmo com o campo `projeto` escrito
#      de varios jeitos. E o caso real: 20 valores distintos para ~6 projetos, com
#      `rainforest-mind` escrito de quatro formas e caminho do Windows dentro de
#      algumas. Comparacao por igualdade perderia dois tercos do historico — e o
#      material perdido some em silencio, que e a pior forma de perder;
#   2. que ele NAO traz ideia de outro projeto. Propor com evidencia alheia e pior
#      que nao propor: a proposta parece fundamentada e nao esta;
#   3. que ideia ABERTA aparece separada, para a skill nao repropor o que ja foi
#      proposto e ninguem executou;
#   4. que sem pasta de dados ele AVISA, em vez de devolver vazio como se o
#      historico nao existisse.
#
# A ultima secao e MUTACAO: troca a comparacao por igualdade estrita e exige que o
# item 1 pare de pegar.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"
SBP="$(mktemp -d)"
SB="$(cygpath -m "$SBP" 2>/dev/null || printf '%s' "$SBP")"
trap 'rm -rf "$SBP"' EXIT
echo "(caixa de areia: $SB)"

ok=0; falhou=0
tem()     { if echo "$2" | grep -qF "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava achar '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }

# Dados de mentira, com o campo `projeto` escrito dos quatro jeitos que existem
# no arquivo real — e um registro de OUTRO projeto, que nao pode vazar.
mkdir -p "$SBP/dados" "$SBP/proj/relatorios"
cat > "$SBP/dados/ideias.jsonl" <<'EOF'
{"id":"obs-nome-limpo","titulo":"OBS-LIMPO","tipo":"observacao","status":"plantada","projeto":"meu-projeto","descricao":"d","contexto":"c","ao_colher":"a","gancho":"g","plantada_em":"2026-08-01"}
{"id":"obs-com-caminho","titulo":"OBS-CAMINHO","tipo":"observacao","status":"colhida","projeto":"meu-projeto (C:\\Projetos\\meu-projeto)","descricao":"d","contexto":"c","ao_colher":"a","gancho":"g","plantada_em":"2026-08-01"}
{"id":"ideia-aberta","titulo":"IDEIA-ABERTA","status":"plantada","projeto":"meu-projeto","descricao":"d","contexto":"c","ao_colher":"a","gancho":"g","plantada_em":"2026-08-01"}
{"id":"ideia-colhida","titulo":"IDEIA-FECHADA","status":"colhida","projeto":"meu-projeto","descricao":"d","contexto":"c","ao_colher":"a","gancho":"g","plantada_em":"2026-08-01"}
{"id":"de-outro-projeto","titulo":"NAO-PODE-VAZAR","tipo":"observacao","status":"plantada","projeto":"outro-projeto-qualquer","descricao":"d","contexto":"c","ao_colher":"a","gancho":"g","plantada_em":"2026-08-01"}
EOF
printf '# INCIDENTE DE TESTE\n\ncorpo\n' > "$SBP/proj/relatorios/2026-08-01-incidente.md"

roda() { ( cd "$SBP/proj" && RFM_ROOT="$SB/dados" CLAUDE_PROJECT_DIR="$SB/proj" \
  node "$SRC/scripts/semear.cjs" --projeto meu-projeto 2>&1 ); }
S="$(roda)"

echo
echo "== 1. acha o historico mesmo com o campo projeto escrito de varios jeitos =="
tem "acha a observacao com nome limpo"        "$S" "OBS-LIMPO"
tem "acha a observacao com caminho no campo"  "$S" "OBS-CAMINHO"
tem "conta as duas"                           "$S" "OBSERVACOES (2)"

echo
echo "== 2. nao traz evidencia de outro projeto =="
nao_tem "registro de outro projeto fica fora" "$S" "NAO-PODE-VAZAR"

echo
echo "== 3. ideia aberta vem separada, e a fechada nao entra =="
tem     "ideia aberta aparece"        "$S" "IDEIA-ABERTA"
nao_tem "ideia ja colhida nao aparece" "$S" "IDEIA-FECHADA"
# Observacao NAO pode aparecer duas vezes: ela ja tem bloco proprio, e repetir
# infla a lista de "nao reproponha" com coisa que nao e proposta.
tem     "abertas conta so a ideia, nao a observacao" "$S" "IDEIAS ABERTAS (1)"

echo
echo "== 4. relatorio do projeto entra =="
tem "relatorio do projeto aparece" "$S" "INCIDENTE DE TESTE"

echo
echo "== 5. sem pasta de dados, AVISA em vez de devolver vazio =="
# Dois vazios diferentes, e os avisos precisam ser diferentes tambem: raiz
# DECLARADA que nao existe e erro de configuracao dele; cadeia que nao resolve
# nada e usuario novo sem setup. Um aviso so para os dois mandaria metade das
# pessoas para o comando errado.
DECL="$( cd "$SBP/proj" && RFM_ROOT="$SB/nao-existe" CLAUDE_PROJECT_DIR="$SB/proj" \
  node "$SRC/scripts/semear.cjs" --projeto meu-projeto 2>&1 )"
tem "raiz declarada e inexistente: diz qual arquivo faltou" "$DECL" "nao consegui ler"
SEM="$( cd "$SBP/proj" && env -u RFM_ROOT HOME="$SBP/lar-vazio" USERPROFILE="$SB/lar-vazio" \
  CLAUDE_PROJECT_DIR="$SB/proj" node "$SRC/scripts/semear.cjs" --projeto meu-projeto 2>&1 )"
tem "sem raiz nenhuma: manda rodar o setup" "$SEM" "sem pasta de dados"
tem "e nomeia o comando exato"              "$SEM" "setup.cjs --criar"

echo
echo "== 6. MUTACAO — comparar por igualdade estrita perde o historico =="
cp "$SRC/scripts/semear.cjs" "$SBP/semear-mutante.cjs"
python - "$SBP/semear-mutante.cjs" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
antes = s
s = s.replace("  return a.includes(b) || b.includes(a.split('-c-')[0]);", "  return a === b; // MUTADO")
assert s != antes, "ancora do combina() sumiu"
p.write_text(s, encoding="utf-8", newline="\n")
PY
MUT="$( cd "$SBP/proj" && RFM_ROOT="$SB/dados" CLAUDE_PROJECT_DIR="$SB/proj" \
  node "$SBP/semear-mutante.cjs" --projeto meu-projeto 2>&1 )"
if echo "$MUT" | grep -qF "OBS-CAMINHO"; then
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — nao e o combina() que acha o historico"
else
  ok=$((ok+1)); echo "  ok   com igualdade estrita a observacao com caminho SOME (o combina e load-bearing)"
fi

echo
echo
echo "== 7. relatorio de OUTRO projeto nao vaza para este =="
# Defeito real, achado quando o Luis perguntou se o semear usa a arqueologia: o
# bloco de relatorios caia na pasta do PLUGIN quando o projeto nao tinha
# `relatorios/`. Um repo recem-instalado recebia os 14 incidentes do rainforest
# como se fossem a historia dele — e a regra que sustenta a skill e justamente
# "toda proposta cita o registro que a origina". Citar incidente alheio produz
# proposta que PARECE fundamentada sem estar, que e pior que nao propor.
SEM_REL="$( cd "$SBP" && CLAUDE_PROJECT_DIR="$SB" RFM_ROOT="$SB/dados"   node "$SRC/scripts/semear.cjs" --projeto meu-projeto 2>&1 )"
tem     "projeto sem relatorios: conta zero"        "$SEM_REL" "RELATORIOS (0)"
nao_tem "e nao traz os relatorios do plugin"        "$SEM_REL" "rainforest"

echo
echo "== 8. o mapa da arqueologia entra quando existe =="
# Semear le o HISTORICO; arqueologia le o TERRENO. Uma nao dispara a outra —
# arqueologia custa uma sessao e e escopada a uma demanda — mas mapa ja escrito
# e evidencia barata, e ignora-la seria desperdicar a unica fonte que existe em
# projeto sem historico nenhum.
mkdir -p "$SBP/proj/docs/rainforest/mapas"
printf '| fatia | profundidade | quando |
|---|---|---|
| faturamento | 2 | 2026-08-11 |
'   > "$SBP/proj/docs/rainforest/mapas/COBERTURA.md"
COM_MAPA="$(roda)"
tem "a fatia mapeada aparece no digest" "$COM_MAPA" "faturamento"
tem "sob o bloco de mapas"              "$COM_MAPA" "MAPAS DE LEGADO"

echo
echo "== 9. sem historico NENHUM, diz o que fazer em vez de devolver vazio =="
# E o caso de quem acabou de instalar, nao uma anomalia. Tres blocos vazios e
# honesto e inutil: o primeiro uso ensinaria que a skill nao serve.
NOVO="$( cd "$SBP" && CLAUDE_PROJECT_DIR="$SB/proj-virgem" RFM_ROOT="$SB/dados"   node "$SRC/scripts/semear.cjs" --projeto nunca-usado 2>&1 )"
tem "diz que nao ha historico"          "$NOVO" "SEM HISTORICO"
tem "aponta a arqueologia como a outra fonte" "$NOVO" "Skill(arqueologia)"
tem "e o recomendador oficial para stack"     "$NOVO" "claude-automation-recommender"

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
