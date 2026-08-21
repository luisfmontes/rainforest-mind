#!/bin/bash
# Bateria do scripts/estado.cjs — a maquina de estados da esteira.
# Uso: bash scripts/testa-estado.sh
#
# O que esta bateria precisa provar, nesta ordem de importancia:
#   1. que `exigir` RECUSA com exit 2 quando o pre-requisito nao fechou. E a unica
#      coisa que separa esta esteira de prosa: no superpowers a transicao e texto que
#      o modelo le e obedece, e <HARD-GATE> e tag XML sem parser;
#   2. que `marcar` recusa FECHAR um estagio pulando os anteriores — senao
#      `marcar verificar ok` pularia a revisao inteira em silencio;
#   3. que ela NAO barra o caminho feliz. Falso positivo aqui trava todo trabalho;
#   4. que `parcial` nao conta como fechado (o caso "5 de 7 tarefas");
#   5. que a retomada aponta o primeiro estagio aberto.
#
# A ultima secao e MUTACAO: afrouxa `estaFechado` para aceitar qualquer status e exige
# que os testes 1 e 2 parem de pegar. Bateria verde com a trava removida testa outra coisa.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)/caixa"
trap 'rm -rf "$(dirname "$SBP")"' EXIT

mkdir -p "$SBP/scripts" "$SBP/hooks/lib"
cp "$SRC/scripts/estado.cjs" "$SBP/scripts/"
cp "$SRC/hooks/lib/raiz.cjs" "$SBP/hooks/lib/"
# A caixa vira raiz de dados: sem marcador, resolverRaiz cairia no repo de verdade
# e a bateria escreveria estado no .rainforest do usuario.
touch "$SBP/FOCO.md"
cd "$SBP" || exit 1
echo "(caixa de areia: $SBP)"

ok=0; falhou=0
E="node scripts/estado.cjs"

esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}
igual() { # nome, esperado, obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi
}

echo
echo "== 1. a trava RECUSA fora de ordem (exit 2, nao 1) =="
$E iniciar --slug t1 >/dev/null
esperado "exigir executar sem design"        2 $E exigir --slug t1 --estagio executar
esperado "exigir revisar sem executar"       2 $E exigir --slug t1 --estagio revisar
esperado "exigir fechar sem verificar"       2 $E exigir --slug t1 --estagio fechar
esperado "fechar verificar pulando o resto"  2 $E marcar --slug t1 --estagio verificar --status ok
esperado "fechar plano sem design"           2 $E marcar --slug t1 --estagio plano --status ok
# design nao tem pre-requisito: nunca pode ser barrado
esperado "exigir design passa sempre"        0 $E exigir --slug t1 --estagio design
# limpar e manutencao, nao estagio: nao pode depender de nada
esperado "exigir limpar passa sempre"        0 $E exigir --slug t1 --estagio limpar

echo
echo "== 2. o caminho feliz NAO e barrado =="
esperado "marcar design aprovado"   0 $E marcar --slug t1 --estagio design    --status aprovado
esperado "marcar plano ok"          0 $E marcar --slug t1 --estagio plano     --status ok
esperado "exigir executar agora ok" 0 $E exigir --slug t1 --estagio executar
esperado "marcar executar ok"       0 $E marcar --slug t1 --estagio executar  --status ok
esperado "marcar revisar ok"        0 $E marcar --slug t1 --estagio revisar   --status ok
esperado "marcar verificar ok"      0 $E marcar --slug t1 --estagio verificar --status ok
esperado "marcar fechar ok"         0 $E marcar --slug t1 --estagio fechar    --status ok
igual "completo no fim" "completo" "$($E proximo --slug t1)"

echo
echo "== 3. parcial nao conta como fechado =="
$E iniciar --slug t2 >/dev/null
$E marcar --slug t2 --estagio design --status aprovado >/dev/null
$E marcar --slug t2 --estagio plano  --status ok >/dev/null
$E marcar --slug t2 --estagio executar --status parcial --json '{"tarefas_ok":3,"tarefas":5}' >/dev/null
igual "retomada aponta o estagio parcial" "executar" "$($E proximo --slug t2)"
esperado "revisar recusado com executar parcial" 2 $E exigir --slug t2 --estagio revisar
# reprovado tambem nao fecha — revisao que reprovou nao libera o proximo
$E marcar --slug t2 --estagio executar --status ok >/dev/null
$E marcar --slug t2 --estagio revisar --status reprovado >/dev/null
esperado "verificar recusado com revisar reprovado" 2 $E exigir --slug t2 --estagio verificar
igual "retomada aponta o reprovado" "revisar" "$($E proximo --slug t2)"

echo
echo "== 4. entrada invalida e recusada =="
esperado "estagio inexistente no marcar"  1 $E marcar --slug t2 --estagio inventado --status ok
esperado "estagio inexistente no exigir"  1 $E exigir --slug t2 --estagio inventado
esperado "status invalido para execucao"  1 $E marcar --slug t2 --estagio verificar --status aprovado
esperado "status invalido para design"    1 $E marcar --slug t2 --estagio design --status parcial
esperado "json malformado"                1 $E marcar --slug t2 --estagio revisar --status ok --json "{nao json"
esperado "slug inexistente"               1 $E ler --slug nao-existe
esperado "iniciar duas vezes"             1 $E iniciar --slug t2

echo
echo "== 5. o estado sobrevive e e retomavel =="
igual "arquivo no lugar certo" "sim" "$([ -f docs/rainforest/estado/t1.json ] && echo sim || echo nao)"
igual "listar mostra os dois" "2" "$($E listar | grep -c '^t')"
prox_t2_antes="$($E proximo --slug t2)"
igual "retomada estavel entre chamadas" "$prox_t2_antes" "$($E proximo --slug t2)"

echo
echo "== 6. o estado mora no PROJETO, nao na cadeia de dados do rainforest =="
# Defeito real, pego em 2026-08-11 antes de rodar em campo: o estado usava
# hooks/lib/raiz.cjs (a cadeia RFM_ROOT > projeto > global > plugin > legado), e
# com isso uma feature de outro repositorio teria o estado gravado dentro do
# rainforest-mind — longe do codigo e misturado com o de outra feature.
# Sao dois tipos de estado: FOCO/ideias sao do usuario e atravessam projeto; design,
# plano e estado sao do PROJETO e ficam onde o trabalho esta.
mkdir -p "$SBP/outro-projeto"
( cd "$SBP/outro-projeto" && RFM_ROOT="$SBP" node ../scripts/estado.cjs iniciar --slug t-local >/dev/null 2>&1 )
igual "estado cai no cwd, mesmo com RFM_ROOT apontando pra fora" "sim" \
  "$([ -f "$SBP/outro-projeto/docs/rainforest/estado/t-local.json" ] && echo sim || echo nao)"
igual "e NAO cai na raiz de dados" "sim" \
  "$([ -f "$SBP/docs/rainforest/estado/t-local.json" ] && echo nao || echo sim)"
# CLAUDE_PROJECT_DIR vence o cwd: e o que o harness informa como raiz do projeto.
mkdir -p "$SBP/dir-do-harness"
( cd "$SBP" && CLAUDE_PROJECT_DIR="$SBP/dir-do-harness" node scripts/estado.cjs iniciar --slug t-harness >/dev/null 2>&1 )
igual "CLAUDE_PROJECT_DIR vence o cwd" "sim" \
  "$([ -f "$SBP/dir-do-harness/docs/rainforest/estado/t-harness.json" ] && echo sim || echo nao)"

echo
echo "== 7. MUTACAO — afrouxar estaFechado tem que quebrar os itens 1 e 3 =="
cp scripts/estado.cjs scripts/estado-mutante.cjs
sed -i "s/return bloco.status === (FECHADO\[estagio\] || 'ok');/return true; \/\/ MUTADO/" scripts/estado-mutante.cjs
$E iniciar --slug t3 >/dev/null
saida=$(node scripts/estado-mutante.cjs exigir --slug t3 --estagio fechar 2>&1); mut=$?
if [ "$mut" = "0" ]; then
  ok=$((ok+1)); echo "  ok   sem estaFechado a trava para de recusar (ela e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao nao teve efeito — nao e estaFechado que decide (exit $mut)"
fi

echo
echo "== 8. ARQUEOLOGIA — estagio zero, opcional de verdade =="
# O estagio zero mapeia codigo que ninguem daqui escreveu, antes de o brainstorm
# fechar decisao sobre terreno que ninguem viu. Ele e OPCIONAL: em projeto novo
# nao ha o que mapear, e exigir mapa ali seria burocracia. "Opcional" aqui e
# mecanico, nao promessa no texto — e sao tres provas distintas.
$E iniciar --slug t-arq >/dev/null
igual "nunca aparece na retomada" "design" "$($E proximo --slug t-arq)"
$E marcar --slug t-arq --estagio design --status aprovado >/dev/null
esperado "nao barra o plano estando pendente"  0 $E exigir --slug t-arq --estagio plano
esperado "e ele proprio nunca e barrado"       0 $E exigir --slug t-arq --estagio arqueologia
# `dispensada` e `ok` sao caminhos diferentes para o mesmo lugar: os dois
# significam que alguem olhou e decidiu. O silencio nao distingue "nao precisa"
# de "ninguem olhou", e e essa diferenca que o registro compra.
esperado "aceita ok"                           0 $E marcar --slug t-arq --estagio arqueologia --status ok
esperado "aceita dispensada"                   0 $E marcar --slug t-arq --estagio arqueologia --status dispensada
esperado "recusa status de execucao"           1 $E marcar --slug t-arq --estagio arqueologia --status parcial
igual "mesmo fechada, nao muda a retomada" "plano" "$($E proximo --slug t-arq)"

echo
echo "== 9. MUTACAO — pondo a arqueologia na varredura, o opcional vira obrigatorio =="
cp scripts/estado.cjs scripts/estado-arq-mutante.cjs
sed -i "s/for (const e of \['design', 'plano', ...EXECUCAO\])/for (const e of ['arqueologia', 'design', 'plano', ...EXECUCAO])/" scripts/estado-arq-mutante.cjs
$E iniciar --slug t-arq2 >/dev/null
MUTA="$(node scripts/estado-arq-mutante.cjs proximo --slug t-arq2)"
if [ "$MUTA" = "arqueologia" ]; then
  ok=$((ok+1)); echo "  ok   na varredura, ela passa a ser cobrada (ficar fora e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao sem efeito — nao e a varredura que decide (veio '$MUTA')"
fi

echo
echo "== 10. backstop de mutacao no revisar (Issue #4) =="

# Prepara um repositorio minimo para testar, DENTRO da caixa
mkdir -p "$SBP/test-repo"
(
  cd "$SBP/test-repo"
  git init >/dev/null
  git config user.email "test@test" >/dev/null
  git config user.name "Test" >/dev/null
  echo "initial" > initial.txt
  git add . && git commit -m "initial" >/dev/null
)

# TODOS os testes rodam com RFM_ESTADO_ROOT apontando para test-repo
# Nota: precisamos exportar para que o sh -c veja a variavel
export RFM_ESTADO_ROOT="$SBP/test-repo"
E_REPO="node scripts/estado.cjs"

# Caso 1: exigir revisar => nada muda => marcar ok PASSA
echo "  preparando caso 1..."
$E_REPO iniciar --slug backstop-1 >/dev/null
$E_REPO marcar --slug backstop-1 --estagio design --status aprovado >/dev/null
$E_REPO marcar --slug backstop-1 --estagio plano --status ok >/dev/null
$E_REPO marcar --slug backstop-1 --estagio executar --status ok >/dev/null
# Executar rodaria no test-repo, vamos simular que criou algo capturando snapshot
esperado "backstop: exigir revisar captura snapshot" 0 $E_REPO exigir --slug backstop-1 --estagio revisar
esperado "backstop: marcar ok passa quando nada mudou" 0 $E_REPO marcar --slug backstop-1 --estagio revisar --status ok --json '{"achados":0,"base":"HEAD","head":"HEAD"}'

# Caso 2: exigir revisar => commit novo => marcar ok FALHA
echo "  preparando caso 2..."
$E_REPO iniciar --slug backstop-2 >/dev/null
$E_REPO marcar --slug backstop-2 --estagio design --status aprovado >/dev/null
$E_REPO marcar --slug backstop-2 --estagio plano --status ok >/dev/null
$E_REPO marcar --slug backstop-2 --estagio executar --status ok >/dev/null
esperado "backstop-2: exigir revisar" 0 $E_REPO exigir --slug backstop-2 --estagio revisar
# Fazer um commit novo (simula outro dev commitando)
(cd "$SBP/test-repo" && echo "mudanca" >> initial.txt && git add . && git commit -m "novo commit" >/dev/null)
esperado "backstop-2: marcar ok falha quando HEAD mudou" 2 $E_REPO marcar --slug backstop-2 --estagio revisar --status ok --json '{"achados":0,"base":"HEAD","head":"HEAD"}'

# Caso 3: exigir revisar => arquivo rastreado modificado => marcar ok FALHA
echo "  preparando caso 3..."
# Reverter o commit anterior para o caso 3
(cd "$SBP/test-repo" && git reset --hard HEAD~1 >/dev/null)
$E_REPO iniciar --slug backstop-3 >/dev/null
$E_REPO marcar --slug backstop-3 --estagio design --status aprovado >/dev/null
$E_REPO marcar --slug backstop-3 --estagio plano --status ok >/dev/null
$E_REPO marcar --slug backstop-3 --estagio executar --status ok >/dev/null
esperado "backstop-3: exigir revisar" 0 $E_REPO exigir --slug backstop-3 --estagio revisar
# Modificar um arquivo rastreado (simula revisor editando)
(cd "$SBP/test-repo" && echo "arquivo modificado" >> initial.txt)
esperado "backstop-3: marcar ok falha quando arquivo ficou sujo" 2 $E_REPO marcar --slug backstop-3 --estagio revisar --status ok --json '{"achados":0,"base":"HEAD","head":"HEAD"}'

# Caso 4: exigir revisar com arvore JA SUJA => nenhuma sujeira nova => marcar ok PASSA
echo "  preparando caso 4..."
# Desfazer a mudanca anterior
(cd "$SBP/test-repo" && git checkout -- initial.txt)
# Criar um arquivo extra sujo ANTES de exigir (simula lixo pre-existente do usuario)
(cd "$SBP/test-repo" && echo "lixo" > lixo-preexistente.txt)
$E_REPO iniciar --slug backstop-4 >/dev/null
$E_REPO marcar --slug backstop-4 --estagio design --status aprovado >/dev/null
$E_REPO marcar --slug backstop-4 --estagio plano --status ok >/dev/null
$E_REPO marcar --slug backstop-4 --estagio executar --status ok >/dev/null
esperado "backstop-4: exigir revisar com arvore suja" 0 $E_REPO exigir --slug backstop-4 --estagio revisar
# Nao fazer mudanca nenhuma, sujeira pre-existente nao reprova
esperado "backstop-4: marcar ok passa com sujeira preexistente" 0 $E_REPO marcar --slug backstop-4 --estagio revisar --status ok --json '{"achados":0,"base":"HEAD","head":"HEAD"}'

echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
