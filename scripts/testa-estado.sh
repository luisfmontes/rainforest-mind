#!/bin/bash
# Bateria do scripts/estado.cjs — a maquina de estados do fluxo.
# Uso: bash scripts/testa-estado.sh
#
# O que esta bateria precisa provar, nesta ordem de importancia:
#   1. que `exigir` RECUSA com exit 2 quando o pre-requisito nao fechou. E a unica
#      coisa que separa este fluxo de prosa: no superpowers a transicao e texto que
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
# O `exigir` acima ARMA a catraca de mutacao, entao o fechamento feliz daqui em
# diante declara `mutacao`. Antes da catraca esta linha nao tinha --json; ela
# mudou porque o contrato mudou, e um caminho feliz que nao declara mutacao
# deixou de ser caminho feliz. Agora tambem exige `comando` e `saida` para
# executar e verificar.
esperado "marcar executar ok com evidencia"  0 $E marcar --slug t1 --estagio executar  --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"caso-teste-1"}]}'
esperado "marcar revisar ok"                 0 $E marcar --slug t1 --estagio revisar   --status ok
esperado "marcar verificar ok com evidencia" 0 $E marcar --slug t1 --estagio verificar --status ok --json '{"comando":"bash","saida":"done","comando":"bash test.sh","saida":"3 cases passed"}'
esperado "marcar fechar ok"                  0 $E marcar --slug t1 --estagio fechar    --status ok
igual "completo no fim" "completo" "$($E proximo --slug t1)"

echo
echo "== 3. parcial nao conta como fechado =="
$E iniciar --slug t2 >/dev/null
$E marcar --slug t2 --estagio design --status aprovado >/dev/null
$E marcar --slug t2 --estagio plano  --status ok >/dev/null
$E exigir --slug t2 --estagio executar >/dev/null
$E marcar --slug t2 --estagio executar --status parcial --json '{"tarefas_ok":3,"tarefas":5}' >/dev/null
igual "retomada aponta o estagio parcial" "executar" "$($E proximo --slug t2)"
esperado "revisar recusado com executar parcial" 2 $E exigir --slug t2 --estagio revisar
# reprovado rebaixa o upstream — revisar reprovado reabre executar para parcial
$E marcar --slug t2 --estagio executar --status ok --json '{"comando":"t2cmd","saida":"t2out","comando":"run","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E marcar --slug t2 --estagio revisar --status ok >/dev/null
$E exigir --slug t2 --estagio verificar >/dev/null
$E marcar --slug t2 --estagio verificar --status reprovado >/dev/null
esperado "revisar recusado com verificar reprovado" 2 $E exigir --slug t2 --estagio revisar
igual "retomada aponta o reaberto (executar)" "executar" "$($E proximo --slug t2)"

echo
echo "== 4. entrada invalida e recusada =="
esperado "estagio inexistente no marcar"  1 $E marcar --slug t2 --estagio inventado --status ok
esperado "estagio inexistente no exigir"  1 $E exigir --slug t2 --estagio inventado
esperado "status invalido para execucao"  1 $E marcar --slug t2 --estagio verificar --status aprovado
esperado "status invalido para design"    1 $E marcar --slug t2 --estagio design --status parcial
esperado "json malformado"                1 $E marcar --slug t2 --estagio revisar --status ok --json "{nao json"
esperado "slug inexistente"               1 $E ler --slug nao-existe
esperado "iniciar duas vezes"             1 $E iniciar --slug t2
esperado "slug com path traversal ../../x" 1 $E iniciar --slug '../../x'
esperado "slug com barra /: x/y"          1 $E iniciar --slug 'x/y'
esperado "slug com backslash: x\\y"       1 $E iniciar --slug 'x\y'
esperado "slug vazio"                     1 $E iniciar --slug ''

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
$E_REPO exigir --slug backstop-1 --estagio executar >/dev/null
$E_REPO marcar --slug backstop-1 --estagio executar --status ok --json '{"comando":"node test.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
# Executar rodaria no test-repo, vamos simular que criou algo capturando snapshot
esperado "backstop: exigir revisar captura snapshot" 0 $E_REPO exigir --slug backstop-1 --estagio revisar
esperado "backstop: marcar ok passa quando nada mudou" 0 $E_REPO marcar --slug backstop-1 --estagio revisar --status ok --json '{"achados":0,"base":"HEAD","head":"HEAD"}'

# Caso 2: exigir revisar => commit novo => marcar ok FALHA
echo "  preparando caso 2..."
$E_REPO iniciar --slug backstop-2 >/dev/null
$E_REPO marcar --slug backstop-2 --estagio design --status aprovado >/dev/null
$E_REPO marcar --slug backstop-2 --estagio plano --status ok >/dev/null
$E_REPO exigir --slug backstop-2 --estagio executar >/dev/null
$E_REPO marcar --slug backstop-2 --estagio executar --status ok --json '{"comando":"bash test.sh","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
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
$E_REPO exigir --slug backstop-3 --estagio executar >/dev/null
$E_REPO marcar --slug backstop-3 --estagio executar --status ok --json '{"comando":"node t.cjs","saida":"pass","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
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
$E_REPO exigir --slug backstop-4 --estagio executar >/dev/null
$E_REPO marcar --slug backstop-4 --estagio executar --status ok --json '{"comando":"bash cmd.sh","saida":"result","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
esperado "backstop-4: exigir revisar com arvore suja" 0 $E_REPO exigir --slug backstop-4 --estagio revisar
# Nao fazer mudanca nenhuma, sujeira pre-existente nao reprova
esperado "backstop-4: marcar ok passa com sujeira preexistente" 0 $E_REPO marcar --slug backstop-4 --estagio revisar --status ok --json '{"achados":0,"base":"HEAD","head":"HEAD"}'

# Caso 5: arquivo de estado VERSIONADO (como neste repo) => caminho feliz PASSA.
# Os casos 1 a 4 nunca commitavam o estado, entao o arquivo ja estava sujo
# (untracked) antes do instantaneo e caia dentro dele. No repo real ele e
# rastreado e limpo: o proprio `exigir` o suja ao gravar o instantaneo, e a
# primeira versao da trava recusava o caminho feliz SEMPRE. Fixture que nao
# reproduz o repo real deixa a trava verde e quebrada.
echo "  preparando caso 5..."
(cd "$SBP/test-repo" && rm -f lixo-preexistente.txt)
$E_REPO iniciar --slug backstop-5 >/dev/null
$E_REPO marcar --slug backstop-5 --estagio design --status aprovado >/dev/null
$E_REPO marcar --slug backstop-5 --estagio plano --status ok >/dev/null
$E_REPO exigir --slug backstop-5 --estagio executar >/dev/null
$E_REPO marcar --slug backstop-5 --estagio executar --status ok --json '{"comando":"node x.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
(cd "$SBP/test-repo" && git add -A && git commit -qm "estado versionado" >/dev/null 2>&1)
esperado "backstop-5: arvore limpa e estado versionado" 0 $E_REPO exigir --slug backstop-5 --estagio revisar
esperado "backstop-5: marcar ok passa (o exigir sujou o proprio estado)" 0 $E_REPO marcar --slug backstop-5 --estagio revisar --status ok --json '{"achados":0,"base":"HEAD","head":"HEAD"}'

# Caso 6: sujeira que MUDA DE POSICAO na saida do porcelain nao vira mutacao.
# Porcelain de rastreado-modificado vem com espaco na frente (` M caminho`).
# A primeira versao dava `.trim()` no bloco inteiro antes do split, o que comia
# esse espaco SO da primeira linha e cortava um caractere a mais do caminho.
# Efeito: o mesmo arquivo produzia chave diferente conforme a posicao — some um
# arquivo sujo de cima da lista e o de baixo "vira" caminho novo, sem ninguem
# ter tocado nele.
#
# O arranjo aqui e load-bearing, e custou uma versao errada deste teste. O
# `git status --porcelain` NAO ordena por caminho: lista as mudancas de arquivo
# RASTREADO primeiro e as untracked depois, qualquer que seja o nome. A primeira
# versao punha um untracked chamado `0-lixo.txt` na frente contando com ordem
# alfabetica; ele caia no fim da saida, o rastreado era a linha 1 nas DUAS
# medicoes, o defeito se cancelava e o teste passava sem provar nada.
#
# Para o rastreado mudar de posicao entre as duas medicoes precisa haver DOIS
# rastreados sujos, e o primeiro voltar ao conteudo commitado no meio.
echo "  preparando caso 6..."
(cd "$SBP/test-repo" \
  && echo "conteudo-alpha" > alpha.txt \
  && echo "conteudo-bravo" > bravo.txt \
  && git add -A && git commit -qm "dois rastreados" >/dev/null 2>&1)
(cd "$SBP/test-repo" && echo "sujo" >> alpha.txt && echo "sujo" >> bravo.txt)
$E_REPO iniciar --slug backstop-6 >/dev/null
$E_REPO marcar --slug backstop-6 --estagio design --status aprovado >/dev/null
$E_REPO marcar --slug backstop-6 --estagio plano --status ok >/dev/null
$E_REPO exigir --slug backstop-6 --estagio executar >/dev/null
$E_REPO marcar --slug backstop-6 --estagio executar --status ok --json '{"comando":"bash run.sh","saida":"done","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
esperado "backstop-6: exigir com dois rastreados sujos" 0 $E_REPO exigir --slug backstop-6 --estagio revisar
# O primeiro volta ao conteudo commitado (sem git destrutivo — so reescreve).
# Ninguem sujou nada novo: bravo.txt so subiu da linha 2 para a linha 1.
(cd "$SBP/test-repo" && echo "conteudo-alpha" > alpha.txt)
esperado "backstop-6: sujeira que so mudou de posicao nao e mutacao" 0 $E_REPO marcar --slug backstop-6 --estagio revisar --status ok --json '{"achados":0,"base":"HEAD","head":"HEAD"}'

echo
echo "== 11. catraca de mutacao no fechamento de executar (D6, D9, D10) =="
# Em 2026-08-21 um agente entregou 49/49 verde com a trava recusando o caminho
# feliz SEMPRE: ele colou saida de mutacao no relato, e o relato era a unica
# coisa que alguem conferia. Agora o campo e cobrado pelo `marcar`, que e
# externo ao agente e sai 2.
#
# Caixa propria: a secao 10 deixou RFM_ESTADO_ROOT apontando para o test-repo, e
# nada aqui precisa de git.
export RFM_ESTADO_ROOT="$SBP/catraca"
mkdir -p "$RFM_ESTADO_ROOT"

prep_catraca() { # slug — chega ate executar COM a catraca armada pelo exigir
  $E iniciar --slug "$1" >/dev/null
  $E marcar --slug "$1" --estagio design --status aprovado >/dev/null
  $E marcar --slug "$1" --estagio plano  --status ok >/dev/null
  $E exigir --slug "$1" --estagio executar >/dev/null
}

prep_sem_catraca() { # slug — fluxo ja aberto antes da catraca existir
  $E iniciar --slug "$1" >/dev/null
  $E marcar --slug "$1" --estagio design --status aprovado >/dev/null
  $E marcar --slug "$1" --estagio plano  --status ok >/dev/null
}

prep_catraca cat-1
esperado "sem o campo mutacao, recusa" 2 \
  $E marcar --slug cat-1 --estagio executar --status ok --json '{"comando":"cmd1","saida":"out1","tarefas_ok":2,"tarefas":2}'
# Recusa que nao diz o nome do campo manda o agente adivinhar, e adivinhacao
# volta como `--forcar`.
msg=$($E marcar --slug cat-1 --estagio executar --status ok --json '{"comando":"cmd1","saida":"out1","tarefas_ok":2,"tarefas":2}' 2>&1)
igual "a recusa nomeia o campo 'mutacao'" "sim" \
  "$(case "$msg" in *mutacao*) echo sim;; *) echo nao;; esac)"

prep_catraca cat-2
esperado "com um item vermelho, fecha" 0 \
  $E marcar --slug cat-2 --estagio executar --status ok --json '{"comando":"c2","saida":"o2","comando":"c2","saida":"o2","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}'
# ...e fecha porque NAO HA plano em disco nesta caixa. O cruzamento lista x plano
# so acontece quando ha plano para cruzar; sem ele a trava avisa e libera, como o
# resto deste arquivo faz quando nao consegue medir. Trava que reprova por nao
# conseguir medir e trava que se desliga no primeiro `--forcar`.
prep_catraca cat-2b
semplano=$($E marcar --slug cat-2b --estagio executar --status ok --json '{"comando":"run","saida":"ok","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' 2>&1)
igual "sem plano em disco, avisa em vez de recusar" "sim" \
  "$(case "$semplano" in *"plano nao encontrado"*) echo sim;; *) echo nao;; esac)"

# `n/a` com motivo e resposta aceita (D9): tarefa de doc nao tem comportamento a
# inverter, e exigir o impossivel cria o habito do --forcar.
prep_catraca cat-3
esperado "n/a COM motivo fecha" 0 \
  $E marcar --slug cat-3 --estagio executar --status ok --json '{"comando":"test","saida":"done","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":4,"resultado":"n/a","motivo":"tarefa so reescreve doc"}]}'

# ...mas `n/a` seco seria a palavra mais curta ate o exit 0.
prep_catraca cat-4
esperado "n/a SEM motivo recusa" 2 \
  $E marcar --slug cat-4 --estagio executar --status ok --json '{"comando":"c4","saida":"o4","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":4,"resultado":"n/a"}]}'

# Bateria que fica verde com o conserto invertido e o defeito que a catraca
# mede; declarar isso como sucesso e o caminho de fuga obvio.
prep_catraca cat-5
esperado "resultado 'verde' nao e resposta aceita" 2 \
  $E marcar --slug cat-5 --estagio executar --status ok --json '{"comando":"e","saida":"f","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"verde"}]}'

# Só o fechamento `ok` cobra: quem entregou meio fluxo ou reprovou precisa
# poder registrar isso sem prova de mutacao que ainda nao existe.
prep_catraca cat-6
esperado "parcial nao exige o campo"    0 $E marcar --slug cat-6 --estagio executar --status parcial   --json '{"tarefas_ok":3,"tarefas":5}'
esperado "reprovado nao exige o campo"  0 $E marcar --slug cat-6 --estagio executar --status reprovado

# A: Slug criado agora, sem exigir, recusa (exit 2) — nao avisa
prep_sem_catraca cat-7
esperado "executar novo sem exigir recusa" 2 \
  $E marcar --slug cat-7 --estagio executar --status ok --json '{"comando":"c7","saida":"o7","tarefas_ok":2,"tarefas":2}'
recusa=$($E marcar --slug cat-7 --estagio executar --status ok --json '{"comando":"c7","saida":"o7","tarefas_ok":2,"tarefas":2}' 2>&1)
igual "a recusa nomeia 'exigir'" "sim" \
  "$(case "$recusa" in *exigir*) echo sim;; *) echo nao;; esac)"

# D10: Estado antigo (antes de 2026-08-21), sem exigir, avisa + passa
# Para simular, cria estado manualmente com data antiga
# Nota: DIR_ESTADO = path.join(RAIZ, 'docs', 'rainforest', 'estado'), entao RFM_ESTADO_ROOT=$SBP/catraca
# procura em $SBP/catraca/docs/rainforest/estado/
mkdir -p "$SBP/catraca/docs/rainforest/estado"
cat > "$SBP/catraca/docs/rainforest/estado/cat-old.json" <<'EOF'
{
  "slug": "cat-old",
  "titulo": "cat-old",
  "criado_em": "2026-08-20",
  "arqueologia": { "status": "pendente" },
  "design": { "status": "aprovado", "em": "2026-08-20" },
  "plano": { "status": "ok", "em": "2026-08-20" },
  "executar": { "status": "pendente" },
  "revisar": { "status": "pendente" },
  "verificar": { "status": "pendente" },
  "fechar": { "status": "pendente" }
}
EOF
esperado "estado antigo sem catraca avisa e passa" 0 \
  $E marcar --slug cat-old --estagio executar --status ok --json '{"comando":"co","saida":"oo","tarefas_ok":2,"tarefas":2}'
aviso=$($E marcar --slug cat-old --estagio executar --status ok --json '{"comando":"co","saida":"oo","tarefas_ok":2,"tarefas":2}' 2>&1)
igual "o aviso menciona abertura anterior" "sim" \
  "$(case "$aviso" in *antes*) echo sim;; *) echo nao;; esac)"

# Validacao de fixture (propriedade adicionada apos a trava de mutacao)
# fixture e obrigatorio para resultado 'vermelho', nao exigido para 'n/a'.

# D11: vermelho SEM fixture recusa
prep_catraca cat-fixture-1
esperado "vermelho SEM fixture recusa" 2 \
  $E marcar --slug cat-fixture-1 --estagio executar --status ok --json '{"comando":"cf1","saida":"of1","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho"}]}'
msg_fixture=$($E marcar --slug cat-fixture-1 --estagio executar --status ok --json '{"comando":"cf1","saida":"of1","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho"}]}' 2>&1)
igual "a recusa nomeia o campo 'fixture'" "sim" \
  "$(case "$msg_fixture" in *fixture*) echo sim;; *) echo nao;; esac)"

# D11: vermelho COM fixture vazio recusa
prep_catraca cat-fixture-2
esperado "vermelho COM fixture vazio recusa" 2 \
  $E marcar --slug cat-fixture-2 --estagio executar --status ok --json '{"comando":"cf2","saida":"of2","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":""}]}'

# D11: vermelho COM fixture so espacos recusa
prep_catraca cat-fixture-3
esperado "vermelho COM fixture so espacos recusa" 2 \
  $E marcar --slug cat-fixture-3 --estagio executar --status ok --json '{"comando":"cf3","saida":"of3","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"   "}]}'

# D11: vermelho COM fixture preenchida fecha
prep_catraca cat-fixture-4
esperado "vermelho COM fixture preenchida fecha" 0 \
  $E marcar --slug cat-fixture-4 --estagio executar --status ok --json '{"comando":"g","saida":"h","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"nome-do-teste"}]}'

# D11: n/a SEM fixture fecha (fixture nao e exigida para n/a)
prep_catraca cat-fixture-5
esperado "n/a SEM fixture fecha" 0 \
  $E marcar --slug cat-fixture-5 --estagio executar --status ok --json '{"comando":"i","saida":"j","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":4,"resultado":"n/a","motivo":"tarefa so reescreve doc"}]}'

# D10: estado antigo com vermelho SEM fixture, avisa e passa (nao trava retroativo)
cat > "$SBP/catraca/docs/rainforest/estado/cat-old-fixture.json" <<'EOF'
{
  "slug": "cat-old-fixture",
  "titulo": "cat-old-fixture",
  "criado_em": "2026-08-20",
  "arqueologia": { "status": "pendente" },
  "design": { "status": "aprovado", "em": "2026-08-20" },
  "plano": { "status": "ok", "em": "2026-08-20" },
  "executar": { "status": "pendente" },
  "revisar": { "status": "pendente" },
  "verificar": { "status": "pendente" },
  "fechar": { "status": "pendente" }
}
EOF
# D10: catraca ARMADA ANTES da exigencia de fixture — divida herdada, avisa e passa.
# O caso acima cobre o fluxo SEM catraca nenhuma; este cobre o que armou ontem e
# tem plano escrito sem o campo. Travar esse quebraria fluxo em andamento.
prep_catraca cat-armada-antes
node -e 'const f=process.argv[1];const j=JSON.parse(require("fs").readFileSync(f,"utf8"));j.executar.catraca_mutacao="2026-08-22";require("fs").writeFileSync(f,JSON.stringify(j,null,2));' "$SBP/catraca/docs/rainforest/estado/cat-armada-antes.json"
esperado "catraca armada antes da exigencia: vermelho sem fixture avisa e passa" 0 \
  $E marcar --slug cat-armada-antes --estagio executar --status ok --json '{"comando":"x","saida":"y","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho"}]}'
aviso_herdada=$($E marcar --slug cat-armada-antes --estagio executar --status ok --json '{"comando":"x","saida":"y","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho"}]}' 2>&1)
igual "o aviso diz que e divida herdada" "sim" \
  "$(case "$aviso_herdada" in *herdada*) echo sim;; *) echo nao;; esac)"
esperado "estado antigo com vermelho sem fixture avisa e passa" 0 \
  $E marcar --slug cat-old-fixture --estagio executar --status ok --json '{"comando":"a","saida":"b","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho"}]}'
aviso_old=$($E marcar --slug cat-old-fixture --estagio executar --status ok --json '{"comando":"a","saida":"b","tarefas_ok":2,"tarefas":2,"mutacao":[{"tarefa":1,"resultado":"vermelho"}]}' 2>&1)
igual "retroatividade: aviso menciona abertura anterior" "sim" \
  "$(case "$aviso_old" in *antes*) echo sim;; *) echo nao;; esac)"

echo
echo "== 12. MUTACAO — sem a recusa da catraca, o caso 11 para de pegar =="
cp scripts/estado.cjs scripts/estado-catraca-mutante.cjs
sed -i "s|function verificarCatracaMutacao(slug, bloco, estado, extra) {|function verificarCatracaMutacao(slug, bloco, estado, extra) { return null; // MUTADO|" scripts/estado-catraca-mutante.cjs
prep_catraca cat-mut
saida=$(node scripts/estado-catraca-mutante.cjs marcar --slug cat-mut --estagio executar --status ok --json '{"comando":"cm","saida":"cmo","tarefas_ok":2,"tarefas":2}' 2>&1); mut=$?
if [ "$mut" = "0" ]; then
  ok=$((ok+1)); echo "  ok   sem verificarCatracaMutacao o fechamento vazio passa (ela e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao nao teve efeito — nao e a catraca que recusa (exit $mut)"
fi

echo
echo "== 13. 'pendentes' nao sobrevive ao fechamento terminal-positivo =="
# Defeito real: `marcar` fundia o bloco anterior do estagio com o `--json` novo
# em vez de substituir (`estado[estagio] = { ...estado[estagio], ...extra,
# status, em: hoje() }`). Um `pendentes` gravado num `parcial` atravessava o
# `ok` seguinte, e o registro final dizia "completo" (status ok) e "com
# pendencia" (pendentes presente) ao mesmo tempo — um revisor independente nao
# conseguiu decidir se o trabalho estava feito por causa disso.
# Sem RFM_ESTADO_ROOT: cai no cwd ($SBP), igual as secoes 1-9. Caminho RELATIVO
# de proposito nas verificacoes abaixo — bash e o `node -e` que le de volta
# compartilham o mesmo cwd, e um caminho absoluto vindo de `mktemp -d` (estilo
# MSYS, "/tmp/...") embutido dentro de um argumento de `node -e` atravessa a
# fronteira para um binario nativo do Windows e pode nao ser traduzido: foi
# assim que a primeira versao deste teste falhou por 'ENOENT', apontando para
# um caminho que a propria escrita nunca usou.
unset RFM_ESTADO_ROOT
ARQ_T_PEND="docs/rainforest/estado/t-pend.json"

$E iniciar --slug t-pend >/dev/null
$E marcar --slug t-pend --estagio design --status aprovado \
  --json '{"arquivo":"docs/rainforest/design/t-pend.md"}' >/dev/null
$E marcar --slug t-pend --estagio plano  --status ok \
  --json '{"arquivo":"docs/rainforest/planos/t-pend.md"}' >/dev/null
$E exigir  --slug t-pend --estagio executar >/dev/null
$E marcar --slug t-pend --estagio executar --status parcial \
  --json '{"tarefas_ok":5,"tarefas":6,"pendentes":["tarefa-6: falta rodar"]}' >/dev/null
$E marcar --slug t-pend --estagio executar --status ok \
  --json '{"comando":"tp","saida":"tp-out","tarefas_ok":6,"tarefas":6,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null

igual "pendentes NAO sobrevive ao fechamento ok" "sumiu" "$(node -e "
const e = JSON.parse(require('fs').readFileSync('$ARQ_T_PEND', 'utf8'));
console.log('pendentes' in e.executar ? 'sobreviveu' : 'sumiu');
")"
igual "status fechou ok mesmo assim" "ok" \
  "$(node -e "console.log(JSON.parse(require('fs').readFileSync('$ARQ_T_PEND', 'utf8')).executar.status)")"
igual "tarefas_ok do --json de fechamento venceu" "6" \
  "$(node -e "console.log(JSON.parse(require('fs').readFileSync('$ARQ_T_PEND', 'utf8')).executar.tarefas_ok)")"
igual "catraca_mutacao (armada pelo exigir) sobrevive ao fechamento" "sim" \
  "$(node -e "console.log(JSON.parse(require('fs').readFileSync('$ARQ_T_PEND', 'utf8')).executar.catraca_mutacao ? 'sim' : 'nao')")"
igual "arquivo do plano sobrevive" "docs/rainforest/planos/t-pend.md" \
  "$(node -e "console.log(JSON.parse(require('fs').readFileSync('$ARQ_T_PEND', 'utf8')).plano.arquivo)")"

# pendentes REPASSADO explicitamente no --json do fechamento e decisao de quem
# chama, nao vazamento do merge: continua presente porque foi pedido, nao
# porque sobrou do bloco anterior.
$E iniciar --slug t-pend2 >/dev/null
$E marcar --slug t-pend2 --estagio design --status aprovado >/dev/null
$E marcar --slug t-pend2 --estagio plano  --status ok >/dev/null
$E exigir  --slug t-pend2 --estagio executar >/dev/null
$E marcar --slug t-pend2 --estagio executar --status parcial \
  --json '{"tarefas_ok":1,"tarefas":2,"pendentes":["tarefa-2: falta"]}' >/dev/null
$E marcar --slug t-pend2 --estagio executar --status ok \
  --json '{"comando":"tp2","saida":"tp2-out","tarefas_ok":2,"tarefas":2,"pendentes":["nota: revisado depois"],"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"},{"tarefa":2,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
igual "pendentes explicito no --json do ok sobrevive (intencao, nao vazamento)" \
  "nota: revisado depois" \
  "$(node -e "console.log(JSON.parse(require('fs').readFileSync('docs/rainforest/estado/t-pend2.json', 'utf8')).executar.pendentes[0])")"

# snapshot do revisar (armado pelo exigir) tambem sobrevive ao fechamento ok.
# Repositorio PROPRIO, nao o "test-repo" da secao 10: aquele leva um "git reset
# --hard HEAD~1" no preparo do caso 3, que apaga do disco qualquer arquivo
# gravado so na "novo commit" (caso do backstop-1.json e backstop-2.json) —
# reusa-lo aqui daria FALHA por um motivo que nao e o desta secao.
mkdir -p "$SBP/snapshot-fix"
(cd "$SBP/snapshot-fix" && git init -q && git config user.email t@t && git config user.name T && echo x > a.txt && git add . && git commit -qm inicial)
export RFM_ESTADO_ROOT="$SBP/snapshot-fix"
$E iniciar --slug t-snap >/dev/null
$E marcar --slug t-snap --estagio design --status aprovado >/dev/null
$E marcar --slug t-snap --estagio plano  --status ok >/dev/null
$E exigir  --slug t-snap --estagio executar >/dev/null
$E marcar --slug t-snap --estagio executar --status ok \
  --json '{"comando":"snap","saida":"snap-ok","tarefas_ok":1,"tarefas":1,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E exigir  --slug t-snap --estagio revisar >/dev/null
$E marcar --slug t-snap --estagio revisar --status ok \
  --json '{"achados":0,"base":"HEAD","head":"HEAD"}' >/dev/null
igual "snapshot (armado pelo exigir revisar) sobrevive ao fechamento" "sim" \
  "$(node -e "const e=JSON.parse(require('fs').readFileSync('snapshot-fix/docs/rainforest/estado/t-snap.json','utf8')); console.log(e.revisar.snapshot ? 'sim' : 'nao')")"
unset RFM_ESTADO_ROOT

echo
echo "== 14. MUTACAO — sem apagar 'pendentes' no fechamento, o caso 13 para de pegar =="
cp scripts/estado.cjs scripts/estado-pendentes-mutante.cjs
sed -i "s/if (!(campo in extra)) delete base\[campo\];/\/\/ MUTADO: nao apaga mais nada/" scripts/estado-pendentes-mutante.cjs
# Ainda sem RFM_ESTADO_ROOT (default cwd) — mesmo motivo da secao 13. Slug
# proprio evita colisao com t-pend/t-pend2.
EM="node scripts/estado-pendentes-mutante.cjs"
$EM iniciar --slug t-pend-mut >/dev/null
$EM marcar --slug t-pend-mut --estagio design --status aprovado >/dev/null
$EM marcar --slug t-pend-mut --estagio plano  --status ok >/dev/null
$EM exigir  --slug t-pend-mut --estagio executar >/dev/null
$EM marcar --slug t-pend-mut --estagio executar --status parcial \
  --json '{"tarefas_ok":5,"tarefas":6,"pendentes":["tarefa-6: falta rodar"]}' >/dev/null
$EM marcar --slug t-pend-mut --estagio executar --status ok \
  --json '{"comando":"c","saida":"d","tarefas_ok":6,"tarefas":6,"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
mutres=$(node -e "
const e = JSON.parse(require('fs').readFileSync('docs/rainforest/estado/t-pend-mut.json', 'utf8'));
console.log('pendentes' in e.executar ? 'sobreviveu' : 'sumiu');
")
if [ "$mutres" = "sobreviveu" ]; then
  ok=$((ok+1)); echo "  ok   sem o delete, pendentes volta a vazar (o conserto e load-bearing)"
else
  falhou=$((falhou+1)); echo "  FALHA mutacao nao teve efeito — pendentes sumiu mesmo com o delete desligado (veio '$mutres')"
fi
rm -f scripts/estado-pendentes-mutante.cjs

echo
echo "== 15. evidencia (comando e saida) em executar e verificar =="
# Estágios executar e verificar exigem comando e saida preenchidos (não vazio,
# não só espaço) para fechar com ok. revisar e fechar não exigem esses campos.

# Caso (a): ok de executar sem evidencia e recusado
$E iniciar --slug t-ev >/dev/null
$E marcar --slug t-ev --estagio design --status aprovado >/dev/null
$E marcar --slug t-ev --estagio plano  --status ok >/dev/null
$E exigir  --slug t-ev --estagio executar >/dev/null
esperado "ok de executar sem evidencia e recusado" 2 \
  $E marcar --slug t-ev --estagio executar --status ok --json '{"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}'
msg_ev=$($E marcar --slug t-ev --estagio executar --status ok --json '{"mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' 2>&1)
igual "a recusa nomeia 'comando' e 'saida'" "sim" \
  "$(case "$msg_ev" in *comando*saida*) echo sim;; *) echo nao;; esac)"

# Caso (b): ok de verificar sem saida colada e recusado
$E iniciar --slug t-ev2 >/dev/null
$E marcar --slug t-ev2 --estagio design --status aprovado >/dev/null
$E marcar --slug t-ev2 --estagio plano  --status ok >/dev/null
$E exigir  --slug t-ev2 --estagio executar >/dev/null
$E marcar --slug t-ev2 --estagio executar --status ok --json '{"comando":"node x","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E marcar --slug t-ev2 --estagio revisar --status ok >/dev/null
esperado "ok de verificar sem saida colada e recusado" 2 \
  $E marcar --slug t-ev2 --estagio verificar --status ok --json '{"comando":"bash t.sh"}'

# Caso (c): ok com comando e saida nao vazios fecha
$E iniciar --slug t-ev3 >/dev/null
$E marcar --slug t-ev3 --estagio design --status aprovado >/dev/null
$E marcar --slug t-ev3 --estagio plano  --status ok >/dev/null
$E exigir  --slug t-ev3 --estagio executar >/dev/null
esperado "ok com comando e saida nao vazios fecha" 0 \
  $E marcar --slug t-ev3 --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"resultado","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}'

# Caso (d): revisar e fechar fecham sem os campos
$E marcar --slug t-ev3 --estagio revisar --status ok >/dev/null
esperado "revisar fecha sem comando e saida" 0 \
  $E marcar --slug t-ev3 --estagio revisar --status ok --json '{}'
# A verificacao ja foi marcada parcialmente, volta atras
$E marcar --slug t-ev3 --estagio verificar --status ok --json '{"comando":"bash t.sh","saida":"ok"}' >/dev/null
$E marcar --slug t-ev3 --estagio fechar --status ok >/dev/null
igual "fechar fecha sem evidencia" "ok" \
  "$([ $? = 0 ] && echo ok || echo erro)"

# Caso (e): campo com string vazia ou so espaco e recusado
$E iniciar --slug t-ev4 >/dev/null
$E marcar --slug t-ev4 --estagio design --status aprovado >/dev/null
$E marcar --slug t-ev4 --estagio plano  --status ok >/dev/null
$E exigir  --slug t-ev4 --estagio executar >/dev/null
esperado "comando vazio e recusado" 2 \
  $E marcar --slug t-ev4 --estagio executar --status ok --json '{"comando":"","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}'
esperado "saida so espacos e recusada" 2 \
  $E marcar --slug t-ev4 --estagio executar --status ok --json '{"comando":"cmd","saida":"   ","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}'

echo
echo "== 16. reprovado rebaixa o upstream imediato para parcial com rastro =="
# Caso (a): com executar fechado ok, marcar verificar reprovado deixa executar com status parcial e reaberto_por
$E iniciar --slug t-repr >/dev/null
$E marcar --slug t-repr --estagio design --status aprovado >/dev/null
$E marcar --slug t-repr --estagio plano  --status ok >/dev/null
$E exigir  --slug t-repr --estagio executar >/dev/null
# executar ok com evidencia e mutacao
$E marcar --slug t-repr --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E marcar --slug t-repr --estagio revisar --status ok >/dev/null
$E exigir  --slug t-repr --estagio verificar >/dev/null
# reprovado em verificar reabre executar
$E marcar --slug t-repr --estagio verificar --status reprovado >/dev/null
igual "executar em status parcial apos reprovacao em verificar" "parcial" \
  "$(node -e "console.log(JSON.parse(require('fs').readFileSync('docs/rainforest/estado/t-repr.json', 'utf8')).executar.status)")"
igual "executar tem reaberto_por.estagio === verificar" "verificar" \
  "$(node -e "console.log(JSON.parse(require('fs').readFileSync('docs/rainforest/estado/t-repr.json', 'utf8')).executar.reaberto_por.estagio)")"
igual "reaberto_por.data e ISO (2026-XX-XX)" "sim" \
  "$(node -e "const d = JSON.parse(require('fs').readFileSync('docs/rainforest/estado/t-repr.json', 'utf8')).executar.reaberto_por.data; console.log(/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(d) ? 'sim' : 'nao')")"

# Caso (b): exigir verificar seguinte recusa exit 2 nomeando executar
esperado "exigir verificar apos reprovacao recusa exit 2" 2 \
  $E exigir --slug t-repr --estagio verificar
msg_reopened=$($E exigir --slug t-repr --estagio verificar 2>&1)
igual "recusa nomeia o upstream reaberto (executar)" "sim" \
  "$(case "$msg_reopened" in *executar*) echo sim;; *) echo nao;; esac)"

# Caso (c): reprovar revisar reabre executar pelo mesmo mecanismo
$E iniciar --slug t-repr2 >/dev/null
$E marcar --slug t-repr2 --estagio design --status aprovado >/dev/null
$E marcar --slug t-repr2 --estagio plano  --status ok >/dev/null
$E exigir  --slug t-repr2 --estagio executar >/dev/null
$E marcar --slug t-repr2 --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E exigir  --slug t-repr2 --estagio revisar >/dev/null
# reprovado em revisar reabre executar
$E marcar --slug t-repr2 --estagio revisar --status reprovado >/dev/null
igual "revisar reprovado deixa executar em status parcial" "parcial" \
  "$(node -e "console.log(JSON.parse(require('fs').readFileSync('docs/rainforest/estado/t-repr2.json', 'utf8')).executar.status)")"
igual "reaberto_por.estagio === revisar" "revisar" \
  "$(node -e "console.log(JSON.parse(require('fs').readFileSync('docs/rainforest/estado/t-repr2.json', 'utf8')).executar.reaberto_por.estagio)")"

# Caso (d): fluxo fechado sem reprovacao nao ganha campo novo
$E iniciar --slug t-repr3 >/dev/null
$E marcar --slug t-repr3 --estagio design --status aprovado >/dev/null
$E marcar --slug t-repr3 --estagio plano  --status ok >/dev/null
$E exigir  --slug t-repr3 --estagio executar >/dev/null
$E marcar --slug t-repr3 --estagio executar --status ok --json '{"comando":"cmd","saida":"output","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E marcar --slug t-repr3 --estagio revisar --status ok >/dev/null
$E exigir  --slug t-repr3 --estagio verificar >/dev/null
$E marcar --slug t-repr3 --estagio verificar --status ok --json '{"comando":"bash test.sh","saida":"ok"}' >/dev/null
$E marcar --slug t-repr3 --estagio fechar --status ok >/dev/null
igual "fluxo completo sem reprovacao nao tem reaberto_por" "nao" \
  "$(node -e "const e = JSON.parse(require('fs').readFileSync('docs/rainforest/estado/t-repr3.json', 'utf8')); console.log(e.executar.reaberto_por ? 'sim' : 'nao')")"

# Caso (f): exigir do estagio reaberto passa (caminho de volta)
$E iniciar --slug t-repr4 >/dev/null
$E marcar --slug t-repr4 --estagio design --status aprovado >/dev/null
$E marcar --slug t-repr4 --estagio plano  --status ok >/dev/null
$E exigir --slug t-repr4 --estagio executar >/dev/null
$E marcar --slug t-repr4 --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E marcar --slug t-repr4 --estagio revisar --status ok >/dev/null
$E exigir --slug t-repr4 --estagio verificar >/dev/null
$E marcar --slug t-repr4 --estagio verificar --status reprovado >/dev/null
esperado "exigir do estagio reaberto passa" 0 $E exigir --slug t-repr4 --estagio executar

# Caso (g): ciclo completo reprovar-reabrir-refechar destrava o fluxo
$E marcar --slug t-repr4 --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
igual "reaberto_por foi limpo apos fechamento ok" "nao" \
  "$(node -e "const e = JSON.parse(require('fs').readFileSync('docs/rainforest/estado/t-repr4.json', 'utf8')); console.log(e.executar.reaberto_por ? 'sim' : 'nao')")"
# Agora o fluxo foi destravado: verificar (que reprovou) é exigivel novamente
esperado "verificar agora exigivel novamente (ciclo destravou)" 0 $E exigir --slug t-repr4 --estagio verificar

# Caso (e): estado antigo sem reaberto_por passa por exigir/proximo/marcar sem erro
mkdir -p "$SBP/estado-antigo/docs/rainforest/estado"
cat > "$SBP/estado-antigo/docs/rainforest/estado/t-old.json" <<'EOF'
{
  "slug": "t-old",
  "titulo": "t-old",
  "criado_em": "2026-08-20",
  "arqueologia": { "status": "pendente" },
  "design": { "status": "aprovado" },
  "plano": { "status": "ok" },
  "executar": { "status": "ok", "comando": "node x", "saida": "ok", "mutacao": [{"tarefa": 1, "resultado": "vermelho", "fixture": "teste"}] },
  "revisar": { "status": "ok" },
  "verificar": { "status": "pendente" },
  "fechar": { "status": "pendente" }
}
EOF
export RFM_ESTADO_ROOT="$SBP/estado-antigo"
E_OLD="node scripts/estado.cjs"
esperado "proximo em estado antigo passa" 0 $E_OLD proximo --slug t-old
igual "proximo aponta verificar" "verificar" "$($E_OLD proximo --slug t-old)"
esperado "exigir em estado antigo passa" 0 $E_OLD exigir --slug t-old --estagio verificar
esperado "marcar em estado antigo passa" 0 $E_OLD marcar --slug t-old --estagio verificar --status ok --json '{"comando":"bash","saida":"ok"}'
unset RFM_ESTADO_ROOT

echo
echo "== 17. contador tentativas: teto de 3 com destrave =="
# TAREFA 3: Quatro casos — fronteira 2/3, OK zera, liberar, estado antigo
# Sandbox com git init como nas tarefas anteriores

mkdir -p "$SBP/tarefa3"
(cd "$SBP/tarefa3" && git init -q && git config user.email t@t && git config user.name T && echo x > a.txt && git add . && git commit -qm inicial)
export RFM_ESTADO_ROOT="$SBP/tarefa3"
E_T3="node scripts/estado.cjs"

prep_t3() { # slug — chega até executar com catraca armada
  $E_T3 iniciar --slug "$1" >/dev/null
  $E_T3 marcar --slug "$1" --estagio design --status aprovado >/dev/null
  $E_T3 marcar --slug "$1" --estagio plano  --status ok >/dev/null
  $E_T3 exigir --slug "$1" --estagio executar >/dev/null
}

# Caso (a): fronteira exata 2/3 — 2a passa (exit 0), 3a recusa (exit 2)
prep_t3 t3-frontier
# Ciclo 1: reprova em verificar
$E_T3 marcar --slug t3-frontier --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E_T3 marcar --slug t3-frontier --estagio revisar --status ok >/dev/null
$E_T3 exigir --slug t3-frontier --estagio verificar >/dev/null
$E_T3 marcar --slug t3-frontier --estagio verificar --status reprovado >/dev/null
esperado "ciclo 1: exigir executar passa" 0 $E_T3 exigir --slug t3-frontier --estagio executar

# Ciclo 2: reprova de novo
$E_T3 marcar --slug t3-frontier --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E_T3 marcar --slug t3-frontier --estagio revisar --status ok >/dev/null
$E_T3 exigir --slug t3-frontier --estagio verificar >/dev/null
$E_T3 marcar --slug t3-frontier --estagio verificar --status reprovado >/dev/null
esperado "ciclo 2: exigir executar passa" 0 $E_T3 exigir --slug t3-frontier --estagio executar


# Ciclo 3: terceira reprovacao — RECUSA exit 2
$E_T3 marcar --slug t3-frontier --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E_T3 marcar --slug t3-frontier --estagio revisar --status ok >/dev/null
$E_T3 exigir --slug t3-frontier --estagio verificar >/dev/null
$E_T3 marcar --slug t3-frontier --estagio verificar --status reprovado >/dev/null
esperado "ciclo 3: exigir executar recusa exit 2" 2 $E_T3 exigir --slug t3-frontier --estagio executar

# Caso (c): liberar grava liberado_em e destrava
esperado "liberar passa" 0 $E_T3 liberar --slug t3-frontier --estagio verificar
esperado "apos liberar, exigir passa" 0 $E_T3 exigir --slug t3-frontier --estagio executar

# Caso (b): OK zera o contador — o REPROVADOR (verificar) fecha ok e o novo
# ciclo comeca de 1. A versao anterior deste caso nunca fechava o verificar
# e passava por causa do liberado_em residual (achado da revisao 2026-08-31,
# corrigido junto com a limpeza do liberado_em na reprovacao seguinte).
$E_T3 marcar --slug t3-frontier --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E_T3 marcar --slug t3-frontier --estagio revisar --status ok >/dev/null
$E_T3 exigir --slug t3-frontier --estagio verificar >/dev/null
$E_T3 marcar --slug t3-frontier --estagio verificar --status ok --json '{"comando":"x","saida":"y"}' >/dev/null
# verificar fechou ok: tentativas zerou. Reprova 1a vez do ciclo novo:
$E_T3 marcar --slug t3-frontier --estagio verificar --status reprovado >/dev/null
esperado "apos OK do reprovador, contador zerou: exigir passa" 0 $E_T3 exigir --slug t3-frontier --estagio executar

# Ciclo 2 novo: segunda de novo
$E_T3 marcar --slug t3-frontier --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E_T3 marcar --slug t3-frontier --estagio revisar --status ok >/dev/null
$E_T3 exigir --slug t3-frontier --estagio verificar >/dev/null
$E_T3 marcar --slug t3-frontier --estagio verificar --status reprovado >/dev/null
esperado "segundo de novo: exigir passa" 0 $E_T3 exigir --slug t3-frontier --estagio executar

# Caso (d): estado antigo sem tentativas conta do zero
mkdir -p "$SBP/tarefa3/docs/rainforest/estado"
cat > "$SBP/tarefa3/docs/rainforest/estado/t3-old.json" <<'JSONEOF'
{"slug":"t3-old","criado_em":"2026-08-20","design":{"status":"aprovado"},"plano":{"status":"ok"},"executar":{"status":"ok"},"revisar":{"status":"ok"},"verificar":{"status":"pendente"}}
JSONEOF
$E_T3 exigir --slug t3-old --estagio verificar >/dev/null
$E_T3 marcar --slug t3-old --estagio verificar --status reprovado >/dev/null
esperado "estado antigo: 1a reprovacao passa" 0 $E_T3 exigir --slug t3-old --estagio executar

unset RFM_ESTADO_ROOT

echo
echo "== 18. proximo imprime criterio, comando, saida e faltou do reprovado =="
# Tarefa 4: com um reprovado como ultimo veredito, proximo imprime o bloco do
# reprovado (criterio, comando, saida, faltou) junto do proximo passo.
# Sem reprovacao pendente, a saida nao muda nem um byte.

mkdir -p "$SBP/tarefa4"
(cd "$SBP/tarefa4" && git init -q && git config user.email t@t && git config user.name T && echo x > a.txt && git add . && git commit -qm inicial)
export RFM_ESTADO_ROOT="$SBP/tarefa4"
E_T4="node scripts/estado.cjs"

prep_t4() { # slug — chega até executar com catraca armada
  $E_T4 iniciar --slug "$1" >/dev/null
  $E_T4 marcar --slug "$1" --estagio design --status aprovado >/dev/null
  $E_T4 marcar --slug "$1" --estagio plano  --status ok >/dev/null
  $E_T4 exigir --slug "$1" --estagio executar >/dev/null
}

# Caso (a): com reprovacao pendente, proximo imprime criterio, comando, saida e faltou
echo "  preparando caso (a)..."
prep_t4 t4-reprovado
$E_T4 marcar --slug t4-reprovado --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E_T4 marcar --slug t4-reprovado --estagio revisar --status ok >/dev/null
$E_T4 exigir --slug t4-reprovado --estagio verificar >/dev/null
# Reprovar em verificar com criterio, comando, saida, faltou no --json
$E_T4 marcar --slug t4-reprovado --estagio verificar --status reprovado --json '{"criterio":"R1","comando":"bash test.sh","saida":"failed","faltou":"output mismatch"}' >/dev/null

# Agora proximo deve imprimir o bloco do reprovado
saida_com_reprovado=$($E_T4 proximo --slug t4-reprovado 2>&1)
# Verificar se a saida contem criterio, comando, saida, faltou E o proximo passo (executar)
tem_criterio=$(case "$saida_com_reprovado" in *"criterio: R1"*) echo sim;; *) echo nao;; esac)
tem_comando=$(case "$saida_com_reprovado" in *"comando: bash test.sh"*) echo sim;; *) echo nao;; esac)
tem_saida=$(case "$saida_com_reprovado" in *"saida: failed"*) echo sim;; *) echo nao;; esac)
tem_faltou=$(case "$saida_com_reprovado" in *"faltou: output mismatch"*) echo sim;; *) echo nao;; esac)
tem_proximo=$(case "$saida_com_reprovado" in *"executar"*) echo sim;; *) echo nao;; esac)

igual "com reprovado: imprime criterio" "sim" "$tem_criterio"
igual "com reprovado: imprime comando" "sim" "$tem_comando"
igual "com reprovado: imprime saida" "sim" "$tem_saida"
igual "com reprovado: imprime faltou" "sim" "$tem_faltou"
igual "com reprovado: imprime proximo passo (executar)" "sim" "$tem_proximo"

# Caso (b): sem reprovacao pendente, a saida e BYTE-IDENTICA
echo "  preparando caso (b)..."
prep_t4 t4-limpo
# Fluxo limpo sem reprovacao — capture a saida do proximo
saida_sem_reprovado=$($E_T4 proximo --slug t4-limpo 2>&1)
# prep_t4 ja passa por design aprovado e plano ok, entao proximo e executar
expected_sem_reprovado="executar"
igual "sem reprovado: saida e byte-identica ao esperado" "$expected_sem_reprovado" "$saida_sem_reprovado"

# Caso (c): depois de re-fechar com ok, volta a saida limpa
echo "  preparando caso (c)..."
prep_t4 t4-refechado
$E_T4 marcar --slug t4-refechado --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E_T4 marcar --slug t4-refechado --estagio revisar --status ok >/dev/null
$E_T4 exigir --slug t4-refechado --estagio verificar >/dev/null
# Reprovar em verificar
$E_T4 marcar --slug t4-refechado --estagio verificar --status reprovado --json '{"criterio":"R2","comando":"check.sh","saida":"nok","faltou":"assertion"}' >/dev/null
# Capturar a saida com reprovado
saida_antes_refecha=$($E_T4 proximo --slug t4-refechado 2>&1)
tem_r2_antes=$(case "$saida_antes_refecha" in *"criterio: R2"*) echo sim;; *) echo nao;; esac)
igual "antes de refecha: imprime R2" "sim" "$tem_r2_antes"

# Re-executar e re-fechar (limpar o reaberto_por)
$E_T4 marcar --slug t4-refechado --estagio executar --status ok --json '{"comando":"node script.cjs","saida":"ok","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"teste"}]}' >/dev/null
$E_T4 marcar --slug t4-refechado --estagio revisar --status ok >/dev/null
$E_T4 exigir --slug t4-refechado --estagio verificar >/dev/null
$E_T4 marcar --slug t4-refechado --estagio verificar --status ok --json '{"comando":"bash verify.sh","saida":"pass"}' >/dev/null

# Agora proximo deve voltar a saida limpa
saida_depois_refecha=$($E_T4 proximo --slug t4-refechado 2>&1)
expected_depois_refecha="fechar"
igual "depois de refecha: volta a saida limpa" "$expected_depois_refecha" "$saida_depois_refecha"

unset RFM_ESTADO_ROOT

echo
echo "== 19. reprovacao pendente nao vaza para fora da execucao (revisao 2026-08-31) =="
# CRITICO da revisao: exigir de limpar/arqueologia/design/plano nao pode ser
# bloqueado por reaberto_por alheio. E os dois avisos: liberar destrava UMA
# rodada (reprovacao seguinte re-arma o teto) e auto-reprovacao de executar
# nao imprime mensagem de rebaixamento sem efeito.

mkdir -p "$SBP/revisao1"
(cd "$SBP/revisao1" && git init -q && git config user.email t@t && git config user.name T && echo x > a.txt && git add . && git commit -qm inicial)
export RFM_ESTADO_ROOT="$SBP/revisao1"
E_R1="node scripts/estado.cjs"

# Prepara um fluxo com reprovacao pendente (executar reaberto)
$E_R1 iniciar --slug rev-vaza >/dev/null
$E_R1 marcar --slug rev-vaza --estagio design --status aprovado >/dev/null
$E_R1 marcar --slug rev-vaza --estagio plano  --status ok >/dev/null
$E_R1 exigir --slug rev-vaza --estagio executar >/dev/null
$E_R1 marcar --slug rev-vaza --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"t"}]}' >/dev/null
$E_R1 exigir --slug rev-vaza --estagio revisar >/dev/null
$E_R1 marcar --slug rev-vaza --estagio revisar --status ok >/dev/null
$E_R1 exigir --slug rev-vaza --estagio verificar >/dev/null
$E_R1 marcar --slug rev-vaza --estagio verificar --status reprovado >/dev/null

esperado "com reaberto pendente, exigir limpar passa"      0 $E_R1 exigir --slug rev-vaza --estagio limpar
esperado "com reaberto pendente, exigir arqueologia passa" 0 $E_R1 exigir --slug rev-vaza --estagio arqueologia
esperado "com reaberto pendente, exigir design passa"      0 $E_R1 exigir --slug rev-vaza --estagio design
esperado "com reaberto pendente, exigir plano passa"       0 $E_R1 exigir --slug rev-vaza --estagio plano
esperado "com reaberto pendente, exigir revisar recusa"    2 $E_R1 exigir --slug rev-vaza --estagio revisar

# Aviso 2 da revisao: liberar destrava UMA rodada — a reprovacao seguinte re-arma o teto
ciclo_rev() { # fecha executar+revisar e reprova verificar
  $E_R1 exigir --slug rev-teto --estagio executar >/dev/null 2>&1
  $E_R1 marcar --slug rev-teto --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"t"}]}' >/dev/null
  $E_R1 exigir --slug rev-teto --estagio revisar >/dev/null
  $E_R1 marcar --slug rev-teto --estagio revisar --status ok >/dev/null
  $E_R1 exigir --slug rev-teto --estagio verificar >/dev/null
  $E_R1 marcar --slug rev-teto --estagio verificar --status reprovado >/dev/null
}
$E_R1 iniciar --slug rev-teto >/dev/null
$E_R1 marcar --slug rev-teto --estagio design --status aprovado >/dev/null
$E_R1 marcar --slug rev-teto --estagio plano  --status ok >/dev/null
ciclo_rev; ciclo_rev; ciclo_rev   # 3 reprovacoes: teto atingido
esperado "teto atingido: exigir executar recusa" 2 $E_R1 exigir --slug rev-teto --estagio executar
$E_R1 liberar --slug rev-teto --estagio verificar >/dev/null
esperado "apos liberar: exigir executar passa" 0 $E_R1 exigir --slug rev-teto --estagio executar
ciclo_rev                          # 4a reprovacao consome o liberar
esperado "reprovacao apos liberar re-arma o teto" 2 $E_R1 exigir --slug rev-teto --estagio executar

# Aviso 4 da revisao: auto-reprovacao de executar nao anuncia rebaixamento sem efeito
$E_R1 iniciar --slug rev-auto >/dev/null
$E_R1 marcar --slug rev-auto --estagio design --status aprovado >/dev/null
$E_R1 marcar --slug rev-auto --estagio plano  --status ok >/dev/null
saida_auto=$($E_R1 marcar --slug rev-auto --estagio executar --status reprovado 2>&1)
case "$saida_auto" in
  *"upstream"*) igual "auto-reprovacao nao imprime rebaixamento falso" "sem-upstream" "$saida_auto" ;;
  *)            igual "auto-reprovacao nao imprime rebaixamento falso" "ok" "ok" ;;
esac

unset RFM_ESTADO_ROOT

echo
echo "== 20. verbo 'concluido' — reusa 'proximo', nao mente sobre ter terminado =="

mkdir -p "$SBP/concluido1"
(cd "$SBP/concluido1" && git init -q && git config user.email t@t && git config user.name T && echo x > a.txt && git add . && git commit -qm inicial)
export RFM_ESTADO_ROOT="$SBP/concluido1"
E_C="node scripts/estado.cjs"

# fluxo A: fecha os sete estagios, completo
$E_C iniciar --slug conc-a >/dev/null
$E_C marcar --slug conc-a --estagio design --status aprovado >/dev/null
$E_C marcar --slug conc-a --estagio plano  --status ok >/dev/null
$E_C exigir --slug conc-a --estagio executar >/dev/null
$E_C marcar --slug conc-a --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"t"}]}' >/dev/null
$E_C exigir --slug conc-a --estagio revisar >/dev/null
$E_C marcar --slug conc-a --estagio revisar --status ok >/dev/null
$E_C exigir --slug conc-a --estagio verificar >/dev/null
$E_C marcar --slug conc-a --estagio verificar --status ok --json '{"comando":"x","saida":"y"}' >/dev/null
$E_C marcar --slug conc-a --estagio fechar --status ok >/dev/null

esperado "concluido --slug com fluxo fechado sai 0" 0 $E_C concluido --slug conc-a

# fluxo B: fechado ate verificar, 'fechar' pendente
$E_C iniciar --slug conc-b >/dev/null
$E_C marcar --slug conc-b --estagio design --status aprovado >/dev/null
$E_C marcar --slug conc-b --estagio plano  --status ok >/dev/null
$E_C exigir --slug conc-b --estagio executar >/dev/null
$E_C marcar --slug conc-b --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"t"}]}' >/dev/null
$E_C exigir --slug conc-b --estagio revisar >/dev/null
$E_C marcar --slug conc-b --estagio revisar --status ok >/dev/null
$E_C exigir --slug conc-b --estagio verificar >/dev/null
$E_C marcar --slug conc-b --estagio verificar --status ok --json '{"comando":"x","saida":"y"}' >/dev/null

esperado "concluido --slug com 'fechar' pendente sai 2" 2 $E_C concluido --slug conc-b
saida_pendente=$($E_C concluido --slug conc-b 2>&1)
case "$saida_pendente" in
  *fechar*) ok=$((ok+1)); echo "  ok   concluido nomeia o estagio pendente (fechar)" ;;
  *) falhou=$((falhou+1)); echo "  FALHA concluido nao nomeou 'fechar' na saida: $saida_pendente" ;;
esac

esperado "concluido --slug inexistente sai 1" 1 $E_C concluido --slug slug-fantasma

echo
echo "== 21. 'concluido' sem --slug varre docs/rainforest/estado/ inteiro =="

# Diretorio com um unico fluxo aberto (design+plano fechados, executar pendente)
mkdir -p "$SBP/concluido2"
(cd "$SBP/concluido2" && git init -q && git config user.email t@t && git config user.name T && echo x > a.txt && git add . && git commit -qm inicial)
export RFM_ESTADO_ROOT="$SBP/concluido2"
E_C2="node scripts/estado.cjs"
$E_C2 iniciar --slug conc-aberto >/dev/null
$E_C2 marcar --slug conc-aberto --estagio design --status aprovado >/dev/null
$E_C2 marcar --slug conc-aberto --estagio plano  --status ok >/dev/null

esperado "varredura sem slug com um aberto sai 2" 2 $E_C2 concluido
saida_varredura=$($E_C2 concluido 2>&1)
case "$saida_varredura" in
  *conc-aberto*) ok=$((ok+1)); echo "  ok   varredura lista o slug aberto" ;;
  *) falhou=$((falhou+1)); echo "  FALHA varredura nao listou conc-aberto: $saida_varredura" ;;
esac

# Fecha o fluxo inteiro: a mesma varredura passa a sair 0
$E_C2 exigir --slug conc-aberto --estagio executar >/dev/null
$E_C2 marcar --slug conc-aberto --estagio executar --status ok --json '{"comando":"x","saida":"y","mutacao":[{"tarefa":1,"resultado":"vermelho","fixture":"t"}]}' >/dev/null
$E_C2 exigir --slug conc-aberto --estagio revisar >/dev/null
$E_C2 marcar --slug conc-aberto --estagio revisar --status ok >/dev/null
$E_C2 exigir --slug conc-aberto --estagio verificar >/dev/null
$E_C2 marcar --slug conc-aberto --estagio verificar --status ok --json '{"comando":"x","saida":"y"}' >/dev/null
$E_C2 marcar --slug conc-aberto --estagio fechar --status ok >/dev/null

esperado "varredura sem slug com todos concluidos sai 0" 0 $E_C2 concluido

# Diretorio de estado inexistente (nunca rodou 'iniciar'): varredura sai 0
mkdir -p "$SBP/concluido3"
export RFM_ESTADO_ROOT="$SBP/concluido3"
esperado "varredura sem nenhum arquivo de estado (dir ausente) sai 0" 0 node scripts/estado.cjs concluido

# Diretorio de estado existe mas esta vazio: varredura tambem sai 0
mkdir -p "$SBP/concluido3/docs/rainforest/estado"
esperado "varredura sem nenhum arquivo de estado (dir vazio) sai 0" 0 node scripts/estado.cjs concluido

unset RFM_ESTADO_ROOT

echo
echo "== 17. robustez do concluido: arquivo malformado nao derruba o processo =="
# Defeito: varredura sem slug fazia JSON.parse sem try/catch em cada arquivo.
# Um arquivo malformado derrubava com SyntaxError e stack trace, exit 1 colidindo
# com erro de uso documentado. A fix: catch o erro, reportar em stderr nomeando o
# arquivo, e sair 1 — indicando "nao consegui responder porque um arquivo nao dava".

# Setup: caixa com um arquivo malformado
mkdir -p "$SBP/robustez/docs/rainforest/estado"
export RFM_ESTADO_ROOT="$SBP/robustez"
echo '{ not valid json' > "$SBP/robustez/docs/rainforest/estado/malformed.json"

# Teste 1: arquivo malformado sozinho → exit 1, mensagem limpa em stderr
saida_mal=$($E concluido 2>&1); saida_code=$?
if [ "$saida_code" = "1" ]; then
  ok=$((ok+1)); echo "  ok   arquivo malformado sai exit 1"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo malformado saiu exit $saida_code, esperava 1"
fi
# Verificar que nao ha SyntaxError ou stack trace na saida
case "$saida_mal" in
  *SyntaxError*) falhou=$((falhou+1)); echo "  FALHA SyntaxError vazou na saida" ;;
  *JSON.parse*) falhou=$((falhou+1)); echo "  FALHA stack trace vazou na saida" ;;
  *) ok=$((ok+1)); echo "  ok   sem SyntaxError ou stack trace na saida" ;;
esac
# Verificar que a mensagem de erro nomeia o arquivo
case "$saida_mal" in
  *malformed.json*) ok=$((ok+1)); echo "  ok   mensagem de erro nomeia o arquivo" ;;
  *) falhou=$((falhou+1)); echo "  FALHA mensagem nao nomeou o arquivo" ;;
esac

# Teste 2: arquivo .json que eh diretorio (EISDIR) → exit 1
mkdir -p "$SBP/robustez/docs/rainforest/estado/directory.json"
saida_dir=$($E concluido 2>&1); saida_dir_code=$?
if [ "$saida_dir_code" = "1" ]; then
  ok=$((ok+1)); echo "  ok   arquivo que eh diretorio sai exit 1"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo-diretorio saiu exit $saida_dir_code, esperava 1"
fi
# Verificar que nao ha stack trace bruto na saida (nao procura por "EISDIR" pois e parte da msg limpa)
case "$saida_dir" in
  *"at readFileSync"*) falhou=$((falhou+1)); echo "  FALHA stack trace vazou na saida" ;;
  *"at "*.cjs:*) falhou=$((falhou+1)); echo "  FALHA stack trace vazou na saida" ;;
  *) ok=$((ok+1)); echo "  ok   sem stack trace na saida" ;;
esac
# Verificar que a mensagem de erro nomeia o arquivo
case "$saida_dir" in
  *directory.json*) ok=$((ok+1)); echo "  ok   mensagem de erro nomeia o arquivo de diretorio" ;;
  *) falhou=$((falhou+1)); echo "  FALHA mensagem nao nomeou o arquivo de diretorio" ;;
esac

# Teste 3: malformado + fluxo aberto → exit 1 E fluxo listado
# Cria um estado valido aberto
cat > "$SBP/robustez/docs/rainforest/estado/open.json" <<'ESTEOF'
{
  "slug": "open",
  "titulo": "Open flow",
  "criado_em": "2026-09-04",
  "arqueologia": { "status": "pendente" },
  "design": { "status": "pendente" },
  "plano": { "status": "pendente" },
  "executar": { "status": "pendente" },
  "revisar": { "status": "pendente" },
  "verificar": { "status": "pendente" },
  "fechar": { "status": "pendente" }
}
ESTEOF
saida_aberto=$($E concluido 2>&1); saida_aberto_code=$?
if [ "$saida_aberto_code" = "1" ]; then
  ok=$((ok+1)); echo "  ok   malformado + aberto sai exit 1"
else
  falhou=$((falhou+1)); echo "  FALHA malformado + aberto saiu exit $saida_aberto_code, esperava 1"
fi
case "$saida_aberto" in
  *open*) ok=$((ok+1)); echo "  ok   fluxo aberto ainda aparece na saida" ;;
  *) falhou=$((falhou+1)); echo "  FALHA fluxo aberto nao foi listado" ;;
esac

# Teste 4a: so arquivos sanos, nenhum aberto → exit 0
rm -f "$SBP/robustez/docs/rainforest/estado/malformed.json" "$SBP/robustez/docs/rainforest/estado/open.json"
rm -rf "$SBP/robustez/docs/rainforest/estado/directory.json"
cat > "$SBP/robustez/docs/rainforest/estado/completed.json" <<'ESTEOF'
{
  "slug": "completed",
  "titulo": "Completed",
  "criado_em": "2026-09-04",
  "arqueologia": { "status": "pendente" },
  "design": { "status": "aprovado" },
  "plano": { "status": "ok" },
  "executar": { "status": "ok" },
  "revisar": { "status": "ok" },
  "verificar": { "status": "ok" },
  "fechar": { "status": "ok" }
}
ESTEOF
esperado "so sanos sem aberto sai 0" 0 $E concluido

# Teste 4b: so arquivos sanos, um aberto → exit 2
cat > "$SBP/robustez/docs/rainforest/estado/open2.json" <<'ESTEOF'
{
  "slug": "open2",
  "titulo": "Open flow 2",
  "criado_em": "2026-09-04",
  "arqueologia": { "status": "pendente" },
  "design": { "status": "aprovado" },
  "plano": { "status": "pendente" },
  "executar": { "status": "pendente" },
  "revisar": { "status": "pendente" },
  "verificar": { "status": "pendente" },
  "fechar": { "status": "pendente" }
}
ESTEOF
esperado "so sanos com aberto sai 2" 2 $E concluido

# Teste 5a: conteudo null → exit 1, sem stack trace
rm -f "$SBP/robustez/docs/rainforest/estado/completed.json" "$SBP/robustez/docs/rainforest/estado/open2.json"
printf 'null' > "$SBP/robustez/docs/rainforest/estado/null-content.json"
saida_null=$($E concluido 2>&1); saida_null_code=$?
if [ "$saida_null_code" = "1" ]; then
  ok=$((ok+1)); echo "  ok   conteudo null sai exit 1"
else
  falhou=$((falhou+1)); echo "  FALHA conteudo null saiu exit $saida_null_code, esperava 1"
fi
case "$saida_null" in
  *TypeError*) falhou=$((falhou+1)); echo "  FALHA TypeError vazou na saida" ;;
  *reading*) falhou=$((falhou+1)); echo "  FALHA stack trace vazou na saida" ;;
  *) ok=$((ok+1)); echo "  ok   sem TypeError ou stack trace para null" ;;
esac
case "$saida_null" in
  *null-content.json*) ok=$((ok+1)); echo "  ok   mensagem de erro nomeia arquivo null" ;;
  *) falhou=$((falhou+1)); echo "  FALHA mensagem nao nomeou arquivo null" ;;
esac

# Teste 5b: conteudo array → exit 1, sem stack trace
printf '[]' > "$SBP/robustez/docs/rainforest/estado/array-content.json"
saida_arr=$($E concluido 2>&1); saida_arr_code=$?
if [ "$saida_arr_code" = "1" ]; then
  ok=$((ok+1)); echo "  ok   conteudo array sai exit 1"
else
  falhou=$((falhou+1)); echo "  FALHA conteudo array saiu exit $saida_arr_code, esperava 1"
fi
case "$saida_arr" in
  *TypeError*) falhou=$((falhou+1)); echo "  FALHA TypeError vazou na saida" ;;
  *reading*) falhou=$((falhou+1)); echo "  FALHA stack trace vazou na saida" ;;
  *) ok=$((ok+1)); echo "  ok   sem TypeError ou stack trace para array" ;;
esac
case "$saida_arr" in
  *array-content.json*) ok=$((ok+1)); echo "  ok   mensagem de erro nomeia arquivo array" ;;
  *) falhou=$((falhou+1)); echo "  FALHA mensagem nao nomeou arquivo array" ;;
esac

# Teste 5c: conteudo string → exit 1, sem stack trace
printf '"texto"' > "$SBP/robustez/docs/rainforest/estado/string-content.json"
saida_str=$($E concluido 2>&1); saida_str_code=$?
if [ "$saida_str_code" = "1" ]; then
  ok=$((ok+1)); echo "  ok   conteudo string sai exit 1"
else
  falhou=$((falhou+1)); echo "  FALHA conteudo string saiu exit $saida_str_code, esperava 1"
fi
case "$saida_str" in
  *TypeError*) falhou=$((falhou+1)); echo "  FALHA TypeError vazou na saida" ;;
  *reading*) falhou=$((falhou+1)); echo "  FALHA stack trace vazou na saida" ;;
  *) ok=$((ok+1)); echo "  ok   sem TypeError ou stack trace para string" ;;
esac
case "$saida_str" in
  *string-content.json*) ok=$((ok+1)); echo "  ok   mensagem de erro nomeia arquivo string" ;;
  *) falhou=$((falhou+1)); echo "  FALHA mensagem nao nomeou arquivo string" ;;
esac

# Teste 5d: conteudo numero → exit 1, sem stack trace
printf '42' > "$SBP/robustez/docs/rainforest/estado/number-content.json"
saida_num=$($E concluido 2>&1); saida_num_code=$?
if [ "$saida_num_code" = "1" ]; then
  ok=$((ok+1)); echo "  ok   conteudo numero sai exit 1"
else
  falhou=$((falhou+1)); echo "  FALHA conteudo numero saiu exit $saida_num_code, esperava 1"
fi
case "$saida_num" in
  *TypeError*) falhou=$((falhou+1)); echo "  FALHA TypeError vazou na saida" ;;
  *reading*) falhou=$((falhou+1)); echo "  FALHA stack trace vazou na saida" ;;
  *) ok=$((ok+1)); echo "  ok   sem TypeError ou stack trace para numero" ;;
esac
case "$saida_num" in
  *number-content.json*) ok=$((ok+1)); echo "  ok   mensagem de erro nomeia arquivo numero" ;;
  *) falhou=$((falhou+1)); echo "  FALHA mensagem nao nomeou arquivo numero" ;;
esac

# Teste 6: arquivo ruim ANTES (alfabeticamente) + fluxo aberto DEPOIS → exit 1 E fluxo listado
rm -f "$SBP/robustez/docs/rainforest/estado/null-content.json" "$SBP/robustez/docs/rainforest/estado/array-content.json" "$SBP/robustez/docs/rainforest/estado/string-content.json" "$SBP/robustez/docs/rainforest/estado/number-content.json"
printf 'null' > "$SBP/robustez/docs/rainforest/estado/2026-01-01-bad.json"
cat > "$SBP/robustez/docs/rainforest/estado/2026-09-04-open-later.json" <<'ESTEOF'
{
  "slug": "open-later",
  "titulo": "Open after bad",
  "criado_em": "2026-09-04",
  "arqueologia": { "status": "pendente" },
  "design": { "status": "pendente" },
  "plano": { "status": "pendente" },
  "executar": { "status": "pendente" },
  "revisar": { "status": "pendente" },
  "verificar": { "status": "pendente" },
  "fechar": { "status": "pendente" }
}
ESTEOF
saida_bad_then=$($E concluido 2>&1); saida_bad_then_code=$?
if [ "$saida_bad_then_code" = "1" ]; then
  ok=$((ok+1)); echo "  ok   arquivo ruim + aberto depois sai exit 1"
else
  falhou=$((falhou+1)); echo "  FALHA arquivo ruim + aberto depois saiu exit $saida_bad_then_code, esperava 1"
fi
case "$saida_bad_then" in
  *open-later*) ok=$((ok+1)); echo "  ok   fluxo aberto DEPOIS ainda aparece na saida" ;;
  *) falhou=$((falhou+1)); echo "  FALHA fluxo aberto DEPOIS nao foi listado" ;;
esac

# A mensagem tem de nomear o tipo que ESTA no arquivo. `typeof null` e 'object',
# e a primeira versao chamava null de "array" por causa disso. Checar so o exit
# code nao pega isso — e a licao do teste tautologico do EISDIR.
rm -f "$SBP/robustez/docs/rainforest/estado"/*.json
rm -rf "$SBP/robustez/docs/rainforest/estado"/*.json
printf 'null' > "$SBP/robustez/docs/rainforest/estado/tipo-null.json"
saida_tipo=$($E concluido 2>&1)
case "$saida_tipo" in
  *"nao e um objeto"*|*"deve ser um objeto, nao null"*|*"deve ser um objeto, não null"*)
    ok=$((ok+1)); echo "  ok   null e reportado como null, nao como array" ;;
  *array*)
    falhou=$((falhou+1)); echo "  FALHA null foi reportado como 'array': $saida_tipo" ;;
  *)
    falhou=$((falhou+1)); echo "  FALHA mensagem de tipo inesperada: $saida_tipo" ;;
esac

rm -f "$SBP/robustez/docs/rainforest/estado"/*.json
printf '[]' > "$SBP/robustez/docs/rainforest/estado/tipo-array.json"
saida_tipo2=$($E concluido 2>&1)
case "$saida_tipo2" in
  *array*) ok=$((ok+1)); echo "  ok   array continua sendo reportado como array" ;;
  *) falhou=$((falhou+1)); echo "  FALHA array nao foi reportado como array: $saida_tipo2" ;;
esac

unset RFM_ESTADO_ROOT

echo "== resultado: $ok ok, $falhou falhas =="
[ "$falhou" = 0 ]
