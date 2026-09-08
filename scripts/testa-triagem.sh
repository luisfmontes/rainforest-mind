#!/bin/bash
# Bateria do scripts/triagem.cjs — a triagem determinística que separa fonte
# legado "dado-como-codigo" (tabela disfarçada de .prw) de "logica" de verdade,
# antes de qualquer passada de leitura gastar chamada de modelo nele (D3, D4, D9).
#
# O script real (`scripts/triagem.cjs`) NUNCA é copiado para uma caixa de areia
# aqui — é chamado no caminho de verdade do repositório. Isso é load-bearing: o
# critério de sucesso deste plano manda mutar o `scripts/triagem.cjs` REAL em
# disco (troca de corte 0.6→0.99, depois a faixa cinzenta) e conferir que esta
# bateria fica vermelha. Se ela chamasse uma cópia, mutar o arquivo real não
# mudaria nada e a prova de mutação seria vácuo.
#
# Fixtures são sintéticas — a bateria não depende de
# C:\Microsiga\erp-trabalho\inovacao existir. As formas replicam as
# medições reais do design (docs/rainforest/design/2026-08-22-agente-arqueologo.md):
# repetição alta -> dado-como-codigo; densidade alta com repetição baixa -> a
# MESMA classe pela 2ª perna do OU; poucas repetições e muitas funções -> logica;
# faixa 40%-60% -> indefinido; dois caminhos com conteúdo idêntico -> duplicataDe;
# e a armadilha que o design registra como já ter enganado uma medição anterior
# (grep contando "function" em comentário e no meio da linha).
#
# Se a pasta do inovacao existir de verdade, uma seção extra confere os fontes
# reais contra os valores do design — pulada com aviso quando não existir.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRIAGEM="$SRC/scripts/triagem.cjs"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "(fixtures em: $TMP)"

ok=0; falhou=0

# --- helpers ------------------------------------------------------------

# Lê um campo do JSON produzido pelo triagem.cjs. Usa um script node à parte
# (nunca `node -e` com o caminho embutido) para não repetir a armadilha de
# tradução de caminho MSYS que já custou uma versão errada de testa-perfil.sh.
cat > "$TMP/campo.cjs" <<'EOF'
const fs = require('fs');
const [, , arquivoJson, idx, campo] = process.argv;
const arr = JSON.parse(fs.readFileSync(arquivoJson, 'utf8'));
const item = arr[Number(idx)];
if (!item) { console.log('__INDICE_INEXISTENTE__'); process.exit(0); }
const v = item[campo];
console.log(v === undefined ? '__AUSENTE__' : v);
EOF
campo() { node "$TMP/campo.cjs" "$1" "$2" "$3"; }

igual() { # nome esperado obtido
  if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"
  else falhou=$((falhou+1)); echo "  FALHA $1: esperava '$2', veio '$3'"; fi
}
esperado() { # nome, exit esperado, comando...
  local nome="$1" esp="$2"; shift 2
  local saida; saida=$("$@" 2>&1); local got=$?
  if [ "$got" = "$esp" ]; then ok=$((ok+1)); echo "  ok   $nome (exit $got)"
  else falhou=$((falhou+1)); echo "  FALHA $nome: esperava exit $esp, veio $got"; echo "$saida" | sed 's/^/         /'; fi
}

# Roda a triagem sobre um ou mais arquivos e grava o JSON em $1 (arquivo de
# saída); os arquivos de entrada vêm depois. Devolve o exit code do processo.
triar() { # arquivo_saida arquivo_entrada...
  local out="$1"; shift
  node "$TRIAGEM" "$@" --json > "$out" 2> "${out}.err"
  echo $?
}

echo
echo "== 1. repetição alta -> dado-como-codigo (1ª perna do OU) =="
# Linha declarativa repetida centenas de vezes, como as tabelas de campo do
# zupd01.prw real. 3 formas distintas x 700 repetições = 2100 linhas
# repetidas; 50 funções únicas mantêm a densidade baixa (~43), isolando o
# efeito à perna de repetição, não à de densidade.
FIX_A="$TMP/a-dado-repeticao-alta.prw"
awk 'BEGIN{
  for (i=1;i<=700;i++) print "AllTrim(oItem:cCampo) := 1"
  for (i=1;i<=700;i++) print "AllTrim(oItem:cValor) := 2"
  for (i=1;i<=700;i++) print "AllTrim(oItem:cTipo)  := 3"
  for (i=1;i<=50;i++) print "function FuncGerada" i "()"
}' > "$FIX_A"
esperado "triagem roda sem erro (fixture A)" 0 triar "$TMP/a.json" "$FIX_A"
igual "classe = dado-como-codigo (repetição alta)" "dado-como-codigo" "$(campo "$TMP/a.json" 0 classe)"
igual "nfunc conta as 50 funções geradas" "50" "$(campo "$TMP/a.json" 0 nfunc)"
REP_A="$(campo "$TMP/a.json" 0 repRatio)"
DENS_A="$(campo "$TMP/a.json" 0 densidade)"
# A classe tem que vir da PERNA DA REPETIÇÃO aqui, não da densidade — senão
# esta fixture e a da tarefa 2 (densidade) provariam a mesma coisa duas vezes.
if awk -v r="$REP_A" 'BEGIN{exit !(r>=0.6)}'; then
  ok=$((ok+1)); echo "  ok   repRatio $REP_A fica >= 0.6 (a perna que devia disparar)"
else falhou=$((falhou+1)); echo "  FALHA repRatio $REP_A não chegou a 0.6"; fi
if awk -v d="$DENS_A" 'BEGIN{exit !(d<300)}'; then
  ok=$((ok+1)); echo "  ok   densidade $DENS_A fica < 300 (não é ela quem decide aqui)"
else falhou=$((falhou+1)); echo "  FALHA densidade $DENS_A já bastaria sozinha — fixture não isola a perna"; fi

echo
echo "== 2. densidade alta, repetição baixa -> dado-como-codigo (2ª perna do OU) =="
# 1 função e milhares de linhas variadas: cada linha muda um número FORA de
# aspas (a normalização só mexe em literal entre aspas), então repRatio cai
# perto de zero. densidade = linhas/nfunc estoura 300 com nfunc=1.
FIX_B="$TMP/b-dado-densidade.prw"
awk 'BEGIN{
  print "function UnicaFuncao()"
  for (i=1;i<=1200;i++) print "local xVar" i " := " i " // comentario " i
}' > "$FIX_B"
esperado "triagem roda sem erro (fixture B)" 0 triar "$TMP/b.json" "$FIX_B"
igual "classe = dado-como-codigo (densidade alta)" "dado-como-codigo" "$(campo "$TMP/b.json" 0 classe)"
igual "nfunc = 1 (uma função só)" "1" "$(campo "$TMP/b.json" 0 nfunc)"
REP_B="$(campo "$TMP/b.json" 0 repRatio)"
DENS_B="$(campo "$TMP/b.json" 0 densidade)"
if awk -v r="$REP_B" 'BEGIN{exit !(r<0.6)}'; then
  ok=$((ok+1)); echo "  ok   repRatio $REP_B fica < 0.6 (não é a perna da repetição aqui)"
else falhou=$((falhou+1)); echo "  FALHA repRatio $REP_B chegou a 0.6 — fixture não isola a 2ª perna"; fi
if awk -v d="$DENS_B" 'BEGIN{exit !(d>=300)}'; then
  ok=$((ok+1)); echo "  ok   densidade $DENS_B fica >= 300 (a perna que devia disparar)"
else falhou=$((falhou+1)); echo "  FALHA densidade $DENS_B não chegou a 300"; fi

echo
echo "== 3. repetição baixa, muitas funções -> logica =="
# Dezenas de funções curtas e distintas, no molde do ZXX01M99.prw real (219
# funções, 32,3% de repetição). 40 funções x 4 linhas cada, corpo variado por
# índice: nada se repete 5+ vezes.
FIX_C="$TMP/c-logica-muitas-funcoes.prw"
awk 'BEGIN{
  for (i=1;i<=40;i++) {
    print "function Funcao" i "()"
    print "local nRet" i " := " i
    print "nRet" i " += " i
    print "Return nRet" i
  }
}' > "$FIX_C"
esperado "triagem roda sem erro (fixture C)" 0 triar "$TMP/c.json" "$FIX_C"
igual "classe = logica" "logica" "$(campo "$TMP/c.json" 0 classe)"
igual "nfunc = 40" "40" "$(campo "$TMP/c.json" 0 nfunc)"

echo
echo "== 4. faixa 40%-60% de repetição -> indefinido =="
# Metade das linhas (500 de 1010, ~49,5%) repetida 5+ vezes; a outra metade
# única. 10 funções mantêm a densidade em ~101, bem abaixo de 300 — senão a
# 2ª perna do OU capturaria o caso antes de chegar na faixa cinzenta.
FIX_D="$TMP/d-indefinido-cinzenta.prw"
awk 'BEGIN{
  for (f=1;f<=20;f++) for (r=1;r<=25;r++) print "campo(" f ") := \"valorRepetido\""
  for (u=1;u<=500;u++) print "local xUnico" u " := " u
  for (g=1;g<=10;g++) print "function FuncCinza" g "()"
}' > "$FIX_D"
esperado "triagem roda sem erro (fixture D)" 0 triar "$TMP/d.json" "$FIX_D"
igual "classe = indefinido" "indefinido" "$(campo "$TMP/d.json" 0 classe)"
REP_D="$(campo "$TMP/d.json" 0 repRatio)"
if awk -v r="$REP_D" 'BEGIN{exit !(r>=0.4 && r<0.6)}'; then
  ok=$((ok+1)); echo "  ok   repRatio $REP_D está mesmo dentro de [0.4, 0.6)"
else falhou=$((falhou+1)); echo "  FALHA repRatio $REP_D saiu da faixa cinzenta — fixture não testa o que diz testar"; fi

echo
echo "== 5. dois caminhos, conteúdo idêntico -> duplicataDe no segundo =="
# Mesma fixture (a de muitas funções, seção 3) salva em dois nomes, no molde
# de zfiscal01.prw em receituario/BASE e receituario/CLIENTE_B no repositório
# real (mesmo hash, 13.650 linhas cada). A marca tem que sair do CONTEÚDO
# (hash), não do nome do arquivo.
mkdir -p "$TMP/dup/BASE" "$TMP/dup/CLIENTE_B"
cp "$FIX_C" "$TMP/dup/BASE/zfiscal01.prw"
cp "$FIX_C" "$TMP/dup/CLIENTE_B/zfiscal01.prw"

esperado "triagem roda sem erro (BASE antes de CLIENTE_B)" 0 \
  triar "$TMP/dup1.json" "$TMP/dup/BASE/zfiscal01.prw" "$TMP/dup/CLIENTE_B/zfiscal01.prw"
HASH_BASE="$(campo "$TMP/dup1.json" 0 hash)"
HASH_CLIENTE_B="$(campo "$TMP/dup1.json" 1 hash)"
igual "os dois hashes batem" "$HASH_BASE" "$HASH_CLIENTE_B"
CANONICO_1="$(campo "$TMP/dup1.json" 0 arquivo)"
DUPDE_1="$(campo "$TMP/dup1.json" 1 duplicataDe)"
igual "o 2º aponta duplicataDe pro 1º (ordem BASE, CLIENTE_B)" "$CANONICO_1" "$DUPDE_1"
SEM_DUP_1="$(campo "$TMP/dup1.json" 0 duplicataDe)"
igual "o canônico NÃO carrega duplicataDe" "__AUSENTE__" "$SEM_DUP_1"

# Adversarial: inverte a ordem dos argumentos na linha de comando. Pela leitura
# do código, quem systematically vira duplicata é o caminho alfabeticamente
# maior (CLIENTE_B > BASE), não "o segundo processado" — testar só a ordem
# alfabética natural deixaria passar um bug na metade `else` de
# hashMap/duplicataDe (o ramo que existe só quando o caminho novo é o
# alfabeticamente menor).
esperado "triagem roda sem erro (CLIENTE_B antes de BASE)" 0 \
  triar "$TMP/dup2.json" "$TMP/dup/CLIENTE_B/zfiscal01.prw" "$TMP/dup/BASE/zfiscal01.prw"
# --json ordena por arquivo (results.sort), então o índice 0 aqui também é o
# BASE (alfabeticamente menor), igual na rodada anterior.
CANONICO_2="$(campo "$TMP/dup2.json" 0 arquivo)"
DUPDE_2="$(campo "$TMP/dup2.json" 1 duplicataDe)"
igual "mesma marca, ordem de argv invertida" "$CANONICO_2" "$DUPDE_2"
igual "o canônico continua sendo o alfabeticamente menor (BASE)" "$CANONICO_1" "$CANONICO_2"

echo
echo "== 6. 'function' em comentário e no meio da linha NÃO conta em nfunc =="
# A armadilha que o design regista como já ter enganado uma medição anterior
# ('Avaliado e descartado' do design: grep contando comentário como função, e
# nao reconhecendo limite de linha). Só a regex ancorada de declaração conta.
FIX_F="$TMP/f-funcoes-armadilha.prw"
cat > "$FIX_F" <<'EOF'
function RealFunc1()
local x := 1
Return x

Static Function RealFunc2()
local y := 2
Return y

   User Function RealFunc3()
local z := 3
Return z

// user function ComentadoNaoConta()
x := "function StringNaoConta"
   x := "outra function no meio  Bar"
FunctionalityFlag := .T.
EOF
esperado "triagem roda sem erro (fixture F)" 0 triar "$TMP/f.json" "$FIX_F"
igual "nfunc = 3 (só as declarações reais)" "3" "$(campo "$TMP/f.json" 0 nfunc)"

echo
echo "== 7. bordas exatas do corte de repetição (adversarial: off-by-one) =="
# 0,60 exatos: a condição é '>= 0.6', então o limite PERTENCE a dado-como-codigo.
FIX_G1="$TMP/g1-boundary-06.prw"
awk 'BEGIN{
  for (f=1;f<=12;f++) for (r=1;r<=5;r++) print "campo(" f ") := 1"
  for (u=1;u<=35;u++) print "local xU" u " := " u
  for (g=1;g<=5;g++) print "function FuncB" g "()"
}' > "$FIX_G1"
esperado "triagem roda sem erro (fixture G1)" 0 triar "$TMP/g1.json" "$FIX_G1"
REP_G1="$(campo "$TMP/g1.json" 0 repRatio)"
igual "repRatio bate exatamente 0.6" "0.6" "$REP_G1"
igual "0.6 exato conta como dado-como-codigo" "dado-como-codigo" "$(campo "$TMP/g1.json" 0 classe)"

# 0,40 exatos: a condição de logica é '< 0.4' (estrita), então o limite NÃO
# pertence a logica — cai em indefinido. Se alguém trocar por '<=', este caso
# vira o primeiro a divergir, e é justamente o caso que ninguém pensa em olhar
# a olho quando está testando só o caminho "óbvio".
FIX_G2="$TMP/g2-boundary-04.prw"
awk 'BEGIN{
  for (f=1;f<=8;f++) for (r=1;r<=5;r++) print "campo(" f ") := 1"
  for (u=1;u<=55;u++) print "local xU" u " := " u
  for (g=1;g<=5;g++) print "function FuncC" g "()"
}' > "$FIX_G2"
esperado "triagem roda sem erro (fixture G2)" 0 triar "$TMP/g2.json" "$FIX_G2"
REP_G2="$(campo "$TMP/g2.json" 0 repRatio)"
igual "repRatio bate exatamente 0.4" "0.4" "$REP_G2"
igual "0.4 exato NÃO é logica — é indefinido" "indefinido" "$(campo "$TMP/g2.json" 0 classe)"

echo
echo "== 8. entrada inválida é recusada (exit != 0) =="
esperado "sem argumento nenhum" 1 node "$TRIAGEM"
esperado "arquivo inexistente" 1 node "$TRIAGEM" "$TMP/nao-existe-mesmo.prw"

echo
echo "== 8b. cadeia de duplicata com 4 arquivos — todos apontam para o canônico final =="
# Reproduz o defeito A: quando há uma cadeia de duplicatas, os intermediários devem
# apontar para o canônico final (menor alfabeticamente), não para o "anterior" que é
# também duplicata. Ordem processada: C, B, D, A com conteúdo idêntico.
# O canônico deve ser A (menor alfabeticamente), e C, B, D devem todos apontar para A.
FIX_CHAIN_C="$TMP/chain-c.prw"
FIX_CHAIN_B="$TMP/chain-b.prw"
FIX_CHAIN_D="$TMP/chain-d.prw"
FIX_CHAIN_A="$TMP/chain-a.prw"

# Conteúdo idêntico (cópia do fixture C de "muitas funções")
for f in "$FIX_CHAIN_C" "$FIX_CHAIN_B" "$FIX_CHAIN_D" "$FIX_CHAIN_A"; do
  awk 'BEGIN{
    for (i=1;i<=40;i++) {
      print "function Funcao" i "()"
      print "local nRet" i " := " i
      print "nRet" i " += " i
      print "Return nRet" i
    }
  }' > "$f"
done

esperado "triagem roda sem erro (cadeia C B D A)" 0 \
  triar "$TMP/chain.json" "$FIX_CHAIN_C" "$FIX_CHAIN_B" "$FIX_CHAIN_D" "$FIX_CHAIN_A"

# Encontrar índices (JSON vem ordenado alfabeticamente por arquivo)
achar_chain_idx() {
  node -e '
    const fs=require("fs");
    const arr=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const i=arr.findIndex(x=>x.arquivo.includes("chain-" + process.argv[2] + ".prw"));
    console.log(i);
  ' "$TMP/chain.json" "$1"
}
IX_A="$(achar_chain_idx a)"
IX_B="$(achar_chain_idx b)"
IX_C="$(achar_chain_idx c)"
IX_D="$(achar_chain_idx d)"

# Todos devem ter o mesmo hash
HASH_A="$(campo "$TMP/chain.json" "$IX_A" hash)"
HASH_B="$(campo "$TMP/chain.json" "$IX_B" hash)"
HASH_C="$(campo "$TMP/chain.json" "$IX_C" hash)"
HASH_D="$(campo "$TMP/chain.json" "$IX_D" hash)"
igual "chain-a e chain-b: mesmo hash" "$HASH_A" "$HASH_B"
igual "chain-b e chain-c: mesmo hash" "$HASH_B" "$HASH_C"
igual "chain-c e chain-d: mesmo hash" "$HASH_C" "$HASH_D"

# Chain-a (alfabeticamente menor) é o canônico — os outros devem apontar para ele
FILE_CHAIN_A="$(campo "$TMP/chain.json" "$IX_A" arquivo)"
DUPDE_CHAIN_A="$(campo "$TMP/chain.json" "$IX_A" duplicataDe)"
DUPDE_CHAIN_B="$(campo "$TMP/chain.json" "$IX_B" duplicataDe)"
DUPDE_CHAIN_C="$(campo "$TMP/chain.json" "$IX_C" duplicataDe)"
DUPDE_CHAIN_D="$(campo "$TMP/chain.json" "$IX_D" duplicataDe)"

igual "chain-a NÃO carrega duplicataDe (é o canônico)" "__AUSENTE__" "$DUPDE_CHAIN_A"
igual "chain-b aponta para chain-a (canônico final)" "$FILE_CHAIN_A" "$DUPDE_CHAIN_B"
igual "chain-c aponta para chain-a (canônico final)" "$FILE_CHAIN_A" "$DUPDE_CHAIN_C"
igual "chain-d aponta para chain-a (canônico final)" "$FILE_CHAIN_A" "$DUPDE_CHAIN_D"

echo
echo "== 8c. arquivo vazio — nfunc = 0, não é dado-como-codigo por densidade infinita =="
# Arquivo vazio teria densidade = Infinity, mas NÃO deve ser classificado como
# dado-como-codigo só por isso. Só a perna de repetição (alta) poderia decidir.
FIX_VAZIO="$TMP/vazio.prw"
touch "$FIX_VAZIO"
esperado "triagem roda sem erro (arquivo vazio)" 0 triar "$TMP/vazio.json" "$FIX_VAZIO"
igual "nfunc = 0 em arquivo vazio" "0" "$(campo "$TMP/vazio.json" 0 nfunc)"
igual "classe ≠ dado-como-codigo (repetição não é alta)" "indefinido" "$(campo "$TMP/vazio.json" 0 classe)"
DENS_VAZIO="$(campo "$TMP/vazio.json" 0 densidade)"
igual "densidade = null (nfunc === 0)" "null" "$DENS_VAZIO"

echo
echo "== 8d. arquivo binário repetitivo — nfunc = 0, não é dado-como-codigo mesmo com repetição =="
# Arquivo com padrão binário repetido 200 linhas (formato legítimo com header/padding alinhado).
# Mesmo com repRatio alto, não deve ser dado-como-codigo porque nfunc === 0.
# O guard deve sempre devolver 'indefinido' quando não há funções.
FIX_BIN_REP="$TMP/binario-repetitivo.prw"
# Criar padrão binário \x00\x01\x02\x03 em 200 linhas
{
  for i in $(seq 1 200); do
    printf '\x00\x01\x02\x03\n'
  done
} > "$FIX_BIN_REP"
esperado "triagem roda sem erro (arquivo binário repetitivo)" 0 triar "$TMP/binario-rep.json" "$FIX_BIN_REP"
igual "nfunc = 0 em arquivo binário repetitivo" "0" "$(campo "$TMP/binario-rep.json" 0 nfunc)"
igual "classe ≠ dado-como-codigo apesar de repetição" "indefinido" "$(campo "$TMP/binario-rep.json" 0 classe)"
DENS_BIN_REP="$(campo "$TMP/binario-rep.json" 0 densidade)"
igual "densidade = null (nfunc === 0)" "null" "$DENS_BIN_REP"

echo
echo "== 8e. arquivo binário aleatório — nfunc = 0, baixa repetição, ainda é indefinido =="
# Arquivo com bytes aleatórios também tem nfunc = 0 e densidade = Infinity.
# Mesma regra: não deve ser dado-como-codigo, pois o guard cobre nfunc === 0.
FIX_BIN_RAND="$TMP/binario-aleatorio.prw"
dd if=/dev/urandom of="$FIX_BIN_RAND" bs=1 count=100 2>/dev/null
esperado "triagem roda sem erro (arquivo binário aleatório)" 0 triar "$TMP/binario-rand.json" "$FIX_BIN_RAND"
igual "nfunc = 0 em arquivo binário aleatório" "0" "$(campo "$TMP/binario-rand.json" 0 nfunc)"
igual "classe ≠ dado-como-codigo (mesmo com baixa repetição)" "indefinido" "$(campo "$TMP/binario-rand.json" 0 classe)"
DENS_BIN_RAND="$(campo "$TMP/binario-rand.json" 0 densidade)"
igual "densidade = null (nfunc === 0)" "null" "$DENS_BIN_RAND"

echo
echo "== 9. PROVA CONTRA O FONTE REAL (pulada sem ~/.rainforest/fontes-reais.json) =="
# Só roda se a pasta existir de verdade nesta máquina — a bateria não pode
# depender disso (o worktree que revisa/verifica pode não ter o inovacao ao
# lado). Quando existe, confere contra os valores medidos no design
# (docs/rainforest/design/2026-08-22-agente-arqueologo.md), NUNCA escrevendo
# nele — só leitura, via `find`, porque os caminhos exatos do plano são
# abreviados com '...' e uma vez já divergiram do real (ZXX02V01.tlpp mora em
# templates/EST/..., não templates/MOD/... como o texto do plano sugere).
# Os fontes reais NAO moram neste repositorio, e o caminho deles tambem nao:
# sao codigo de trabalho, e este repo e publico. A bateria le a lista de um
# arquivo PRIVADO, fora da arvore -- ~/.rainforest/fontes-reais.json, com
# cinco chaves apontando para caminho absoluto:
#
#   repetitivo   -> espera classe `dado-como-codigo`
#   logica       -> espera classe `logica` e >= 100 funcoes
#   indefinido   -> espera classe `indefinido`
#   duplicata_a  -> espera mesmo hash de duplicata_b
#   duplicata_b  -> espera `duplicataDe` apontando para duplicata_a
#
# Sem o arquivo, a prova contra fonte real e PULADA e dita em voz alta --
# nunca silenciosamente verde. Foi assim que os caminhos de trabalho sairam
# do repositorio em 2026-09-08 sem a bateria perder a cobertura na maquina de
# quem tem os fontes.
FONTES_JSON=""
for cand in "$HOME/.rainforest/fontes-reais.json" "$USERPROFILE/.rainforest/fontes-reais.json"; do
  if [ -f "$cand" ]; then FONTES_JSON="$cand"; break; fi
done

if [ -z "$FONTES_JSON" ]; then
  echo "  (pulado: ~/.rainforest/fontes-reais.json nao existe nesta maquina)"
else
  campo_json() { # chave -> caminho, vazio se a chave falta ou o arquivo nao existe
    node -e '
      const fs=require("fs");
      const o=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
      const v=o[process.argv[2]];
      process.stdout.write(v && fs.existsSync(v) ? String(v) : "");
    ' "$FONTES_JSON" "$1"
  }
  F_REPET="$(campo_json repetitivo)"
  F_LOGICA="$(campo_json logica)"
  F_INDEF="$(campo_json indefinido)"
  F_DUP_A="$(campo_json duplicata_a)"
  F_DUP_B="$(campo_json duplicata_b)"

  if [ -z "$F_REPET" ] || [ -z "$F_LOGICA" ] || [ -z "$F_INDEF" ] || [ -z "$F_DUP_A" ] || [ -z "$F_DUP_B" ]; then
    echo "  (pulado: fontes-reais.json existe, mas alguma das cinco chaves falta ou aponta para arquivo inexistente)"
    echo "    repetitivo=$F_REPET"
    echo "    logica=$F_LOGICA"
    echo "    indefinido=$F_INDEF"
    echo "    duplicata_a=$F_DUP_A"
    echo "    duplicata_b=$F_DUP_B"
  else
    esperado "triagem roda sem erro nos fontes reais" 0 \
      triar "$TMP/real.json" "$F_REPET" "$F_LOGICA" "$F_INDEF" "$F_DUP_A" "$F_DUP_B"
    # --json ordena por caminho. A busca e por CAMINHO EXATO, nao por
    # substring do nome: duplicata_a e duplicata_b sao o mesmo nome de arquivo
    # em pastas diferentes, e substring nao distingue os dois.
    achar_indice() { # caminho_exato
      node -e '
        const fs=require("fs");
        const arr=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
        const norm=(s)=>String(s).split("\\").join("/");
        const alvo=norm(process.argv[2]);
        console.log(arr.findIndex(x=>norm(x.arquivo)===alvo));
      ' "$TMP/real.json" "$1"
    }
    IX_REPET="$(achar_indice "$F_REPET")"
    IX_LOGICA="$(achar_indice "$F_LOGICA")"
    IX_INDEF="$(achar_indice "$F_INDEF")"
    IX_DUP_A="$(achar_indice "$F_DUP_A")"
    IX_DUP_B="$(achar_indice "$F_DUP_B")"

    NFUNC_REPET="$(campo "$TMP/real.json" "$IX_REPET" nfunc)"
    if [ "$NFUNC_REPET" -ge 10 ]; then ok=$((ok+1)); echo "  ok   repetitivo: >= 10 funcoes (dado-como-codigo)"; else falhou=$((falhou+1)); echo "  FALHA repetitivo: >= 10 funcoes: esperava >= 10, veio '$NFUNC_REPET'"; fi
    igual "repetitivo: classe dado-como-codigo" "dado-como-codigo" "$(campo "$TMP/real.json" "$IX_REPET" classe)"
    NFUNC_LOGICA="$(campo "$TMP/real.json" "$IX_LOGICA" nfunc)"
    if [ "$NFUNC_LOGICA" -ge 100 ]; then ok=$((ok+1)); echo "  ok   logica: >= 100 funcoes"; else falhou=$((falhou+1)); echo "  FALHA logica: >= 100 funcoes: esperava >= 100, veio '$NFUNC_LOGICA'"; fi
    igual "logica: classe logica" "logica" "$(campo "$TMP/real.json" "$IX_LOGICA" classe)"
    igual "indefinido: classe indefinido" "indefinido" "$(campo "$TMP/real.json" "$IX_INDEF" classe)"
    HASH_DUP_A="$(campo "$TMP/real.json" "$IX_DUP_A" hash)"
    HASH_DUP_B="$(campo "$TMP/real.json" "$IX_DUP_B" hash)"
    igual "duplicata_a e duplicata_b: mesmo hash" "$HASH_DUP_A" "$HASH_DUP_B"
    igual "duplicata_b marcado como duplicataDe" "$(campo "$TMP/real.json" "$IX_DUP_A" arquivo)" \
      "$(campo "$TMP/real.json" "$IX_DUP_B" duplicataDe)"
  fi
fi

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" = 0 ]
