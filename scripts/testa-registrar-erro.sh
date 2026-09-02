#!/bin/bash
# Bateria da UNICA porta de escrita do vigias/ERROS.md (vigias/erros.ps1).
#
# Ela EXECUTA o artefato real — `vigias/backup-estado.ps1` numa caixa de areia —
# e olha os BYTES do arquivo que saiu. Nao le o codigo e nao confia no relato:
# os tres defeitos que ela cobre passaram meses em producao com o codigo a
# vista, e um deles (o mojibake) chegou a derrotar uma assercao desta propria
# entrega, que procurava 'nao achei o FOCO.md' e nunca casava porque a linha
# gravada dizia 'n<mojibake>o achei'.
#
# TRES PROPRIEDADES, uma por defeito, cada uma com criterio proprio. Um
# "a funcao foi reescrita" nao fecha nenhuma delas:
#
#   A. LF (V3)     — `Out-File -Append` no PowerShell 5.1 termina em CRLF e poe
#                    BOM ao criar arquivo. O ERROS.md e commitado em LF, entao
#                    todo append produzia fim de linha MIXED e o
#                    conferir-encoding.cjs recusava o repositorio inteiro. Como
#                    o backup falhava toda ronda, a bateria vermelha era
#                    permanente.
#
#   B. OEM (V4)    — o texto de erro vem do stderr do node em UTF-8, e o
#                    PowerShell o decodifica com [Console]::OutputEncoding, que
#                    na tarefa agendada e o codepage OEM. "nao" virava mojibake
#                    ANTES de ser gravado. Consertar so a escrita nao adianta.
#
#   C. Caminho (Issue #124) — o ERROS.md e RASTREADO num repositorio PUBLICO e
#                    recebe mensagem com caminho de maquina interpolado. Ja foi
#                    empurrado sozinho para a main duas vezes (bb77232,
#                    17ba994). O saneamento fica na porta de escrita, e nao na
#                    disciplina de quem redige a mensagem, para valer tambem
#                    para o chamador que ainda nao existe.
#
#   D. Trava       — nenhuma escrita nova pode escapar da porta unica.
#
# NOTA SOBRE AS FIXTURES DE CAMINHO (secao C2): elas usam uma pasta generica
# (`C:\pasta\Fulano\...`) e nao a forma de diretorio pessoal do Windows, embora
# seja essa a forma real que o defeito produz em campo. O motivo e concreto: o
# proprio gate de publicacao deste repositorio
# (hooks/gate-publicacao-destino.cjs) recusa gravar arquivo versionado que
# contenha aquela forma — e recusou este arquivo, com razao, nas duas primeiras
# tentativas, inclusive quando ela aparecia so num comentario explicando por que
# nao usa-la. O saneador casa QUALQUER caminho com letra de unidade, entao a
# fixture mede exatamente a mesma coisa sem plantar a forma que a trava existe
# para barrar.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

ok=0; falhou=0
igual()   { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1: '$2' != '$3'"; fi; }
verdade() { if [ "$2" = "sim" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1"; fi; }
falso()   { if [ "$2" = "nao" ]; then ok=$((ok+1)); echo "  ok    $1"; else falhou=$((falhou+1)); echo "  FALHA $1"; fi; }

command -v powershell >/dev/null 2>&1 || { echo "FALHA powershell nao esta no PATH — esta bateria nao significaria nada"; exit 1; }
command -v node       >/dev/null 2>&1 || { echo "FALHA node nao esta no PATH"; exit 1; }

win() { cygpath -w "$1"; }

# O nome de usuario falso da caixa. Escolhido para nao existir em lugar nenhum:
# se ele aparecer no ERROS.md, veio do caminho interpolado e o saneamento falhou.
# COM ESPACO, de proposito. A primeira versao usava `usuario-que-nao-deve-vazar`,
# sem espaco nenhum, e por isso 26 de 26 asseracoes ficaram verdes em cima de um
# vazamento real: o regex do saneamento parava no primeiro espaco, e no Windows o
# nome de usuario com espaco e o caso mais comum que existe. A revisao independente
# reproduziu rodando o backup-estado.ps1 de verdade, e a linha gravada trazia o
# nome inteiro. A fixture agora contem a unica coisa que a original nao tinha.
USUARIO_FALSO="Usuario Falso Que Nao Deve Vazar"

montar() {
  rm -rf "$SB/plugin" "$SB/home" "$SB/$USUARIO_FALSO"
  mkdir -p "$SB/plugin/scripts" "$SB/plugin/vigias" "$SB/plugin/hooks/lib" "$SB/home"
  cp "$SRC/scripts/foco.cjs"                 "$SB/plugin/scripts/foco.cjs"
  cp "$SRC/hooks/lib/raiz.cjs"               "$SB/plugin/hooks/lib/raiz.cjs"
  cp "$SRC/hooks/lib/contexto-sessao.cjs"    "$SB/plugin/hooks/lib/contexto-sessao.cjs"
  cp "$SRC/vigias/backup-estado.ps1"         "$SB/plugin/vigias/backup-estado.ps1"
  cp "$SRC/vigias/erros.ps1"                 "$SB/plugin/vigias/erros.ps1"
  # O ERROS.md da caixa nasce em LF, como o commitado. E o unico jeito de a
  # mistura CRLF+LF aparecer: arquivo novo gravado inteiro por Out-File sairia
  # CRLF de ponta a ponta e nao seria "mixed".
  printf -- '- linha que ja estava aqui, em LF\n' > "$SB/plugin/vigias/ERROS.md"
}

# Roda o backup com uma raiz que NAO existe, para provocar o erro de proposito.
# O caminho inexistente carrega o nome de usuario falso: e ele que o node
# interpola na mensagem, e e ele que o saneamento tem de apagar.
provocar_erro() {
  RFM_ROOT="$(win "$SB/$USUARIO_FALSO/dados/nao-existe")" \
  powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$(win "$SB/plugin/vigias/backup-estado.ps1")" \
    -Vigia sentinela-foco -Plugin "$(win "$SB/plugin")" > /dev/null 2>&1
  echo $?
}

ERROS="$SB/plugin/vigias/ERROS.md"

# Roda o MESMO backup, mas forcando o console a um codepage OEM antes - que e a
# condicao real da tarefa agendada, e a unica em que o defeito V4 nasce.
#
# Existe porque a mutacao M2 (tirar o Set-EncodingDeSaida) deixou a bateria
# VERDE na primeira rodada: numa sessao interativa o console ja e UTF-8, entao
# a interceptacao nao muda nada e o teste certificava uma propriedade que nao
# media. Bateria que fica verde com o conserto removido nao prova o conserto.
#
# Usa -Command em vez de -File porque o codepage precisa estar trocado ANTES de
# o script rodar, no MESMO processo - o `& script.ps1` herda o console do pai.
provocar_erro_em_oem() {
  RFM_ROOT="$(win "$SB/$USUARIO_FALSO/dados/nao-existe")"   powershell -NoProfile -ExecutionPolicy Bypass -Command     "[Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850);      & '$(win "$SB/plugin/vigias/backup-estado.ps1")'        -Vigia sentinela-foco -Plugin '$(win "$SB/plugin")'" > /dev/null 2>&1
  echo $?
}

echo "== A. LF: a linha gravada termina em LF, e o arquivo nao ganha BOM =="
montar
codigo=$(provocar_erro)
igual "o backup falhou, como a caixa pediu" "$codigo" "1"
linhas=$(wc -l < "$ERROS" | tr -d ' ')
igual "o ERROS.md tem duas linhas" "$linhas" "2"
# CRLF: conta bytes de retorno de carro. Zero e o unico numero aceitavel.
crs=$(tr -dc '\r' < "$ERROS" | wc -c | tr -d ' ')
igual "nenhum retorno de carro no arquivo" "$crs" "0"
# BOM: os tres primeiros bytes nao podem ser a marca de ordem de byte do UTF-8.
primeiro=$(head -c 3 "$ERROS" | od -An -tx1 | tr -d ' \n')
esperado_bom=$(printf '\xef\xbb\xbf' | od -An -tx1 | tr -d ' \n')
if [ "$primeiro" = "$esperado_bom" ]; then
  falhou=$((falhou+1)); echo "  FALHA o arquivo ganhou BOM"
else
  ok=$((ok+1)); echo "  ok    nenhum BOM no inicio do arquivo"
fi
# O ultimo byte tem de ser LF: linha sem terminador faz a proxima colar nela.
ultimo=$(tail -c 1 "$ERROS" | od -An -c | tr -d ' \n')
igual "o arquivo termina em LF" "$ultimo" '\n'

echo
echo "== B. OEM: o acento sobrevive ao caminho node -> PowerShell -> arquivo =="
# A mensagem do foco.cjs e "nao achei o FOCO.md em ..." COM til no primeiro 'a'.
# Se o codepage OEM entrar no meio, ela chega como 'n' + caractere de desenho de
# caixa + 'u-agudo' e este grep nao casa.
if grep -q 'não achei o FOCO.md' "$ERROS"; then
  ok=$((ok+1)); echo "  ok    o acento chegou intacto ao ERROS.md"
else
  falhou=$((falhou+1)); echo "  FALHA o acento nao sobreviveu — mojibake de codepage"
  echo "        linha gravada:"; sed -n '2p' "$ERROS" | sed 's/^/        /'
fi
# A assinatura do mojibake OEM, montada por BYTES para nao depender do que este
# arquivo .sh contem: U+251C (desenho de caixa) seguido de u-agudo.
assinatura=$(printf '\xe2\x94\x9c\xc3\xba')
if grep -qF "$assinatura" "$ERROS"; then
  falhou=$((falhou+1)); echo "  FALHA a assinatura de mojibake OEM esta no arquivo"
else
  ok=$((ok+1)); echo "  ok    nenhuma assinatura de mojibake OEM no arquivo"
fi

echo
echo "== B2. OEM forcado: a condicao real da tarefa agendada =="
# O caso que a secao B NAO cobre. Aqui o codepage do console e CP850 antes de o
# script rodar, exatamente como numa Scheduled Task. Sem o Set-EncodingDeSaida,
# os bytes UTF-8 do node sao lidos nessa tabela e o acento vira mojibake
# permanente - foi assim que o ERROS.md commitado ficou com 'n<caixa><u>o'.
montar
codigo=$(provocar_erro_em_oem)
igual "o backup falhou tambem sob codepage OEM" "$codigo" "1"
echo "  -- linha gravada sob CP850:"
sed -n '2p' "$ERROS" | sed 's/^/     /'
if grep -q 'não achei o FOCO.md' "$ERROS"; then
  ok=$((ok+1)); echo "  ok    o acento sobreviveu ao codepage OEM"
else
  falhou=$((falhou+1)); echo "  FALHA o acento nao sobreviveu ao codepage OEM"
fi
if grep -qF "$assinatura" "$ERROS"; then
  falhou=$((falhou+1)); echo "  FALHA a assinatura de mojibake OEM apareceu sob CP850"
else
  ok=$((ok+1)); echo "  ok    nenhuma assinatura de mojibake OEM sob CP850"
fi
crs=$(tr -dc '' < "$ERROS" | wc -c | tr -d ' ')
igual "e continua sem retorno de carro sob CP850" "$crs" "0"

echo
echo "== C. Caminho de maquina: Issue #124 =="
echo "  -- linha gravada (a que iria para o repo publico):"
sed -n '2p' "$ERROS" | sed 's/^/     /'
grep -q "$USUARIO_FALSO" "$ERROS" && r=sim || r=nao
falso "o nome de usuario NAO esta no ERROS.md" "$r"
grep -qE '[A-Za-z]:\\' "$ERROS" && r=sim || r=nao
falso "nenhum caminho com letra de unidade no ERROS.md" "$r"
grep -q '<caminho>' "$ERROS" && r=sim || r=nao
verdade "o marcador <caminho> esta no lugar do caminho" "$r"
# O saneamento nao pode virar apagador: o nome do arquivo e o que torna a
# mensagem util para quem for diagnosticar.
grep -q 'FOCO.md' "$ERROS" && r=sim || r=nao
verdade "a mensagem continua dizendo QUAL arquivo faltou" "$r"

echo
echo "== C2. o saneamento isolado, nos formatos que os chamadores produzem =="
# Os tres sitios reais que interpolam caminho: $configPath (duas vezes) e
# $bridgeLauncher. Exercitados direto na funcao, sem depender de provocar cada
# erro de producao — que exigiria bridge de pe e claude respondendo.
sanear() {
  powershell -NoProfile -ExecutionPolicy Bypass -Command \
    ". '$(win "$SB/plugin/vigias/erros.ps1")'; Get-MotivoSaneado '$1'" 2>/dev/null | tr -d '\r'
}
igual "caminho com letra de unidade vira marcador + folha" \
  "$(sanear 'sem destino: defina destinoWhatsapp em C:\pasta\Fulano\proj\vigia.config.json')" \
  'sem destino: defina destinoWhatsapp em <caminho>\vigia.config.json'
igual "caminho UNC tambem" \
  "$(sanear 'launcher em \\servidor\compart\bridge.ps1 nao existe')" \
  'launcher em <caminho>\bridge.ps1 nao existe'
igual "caminho terminado em barra (uma pasta) nao vaza a folha" \
  "$(sanear 'raiz C:\pasta\Fulano\dados\ invalida')" \
  'raiz <caminho> invalida'
igual "mensagem sem caminho nenhum passa intacta" \
  "$(sanear 'bridge nao subiu apos 60s (porta 3005 fechada)')" \
  'bridge nao subiu apos 60s (porta 3005 fechada)'
igual "dois caminhos na mesma mensagem, os dois saneados" \
  "$(sanear 'de C:\a\um.txt para D:\b\dois.txt')" \
  'de <caminho>\um.txt para <caminho>\dois.txt'

# --- ESPACO NO CAMINHO. O buraco que deixou a bateria verde em cima de um
#     vazamento, achado pela revisao independente em 2026-09-02. Nenhuma fixture
#     acima tinha espaco em segmento nenhum, e o regex antigo parava no primeiro.
#     No Windows o nome de usuario com espaco e o caso MAIS comum que existe.
#     (As fixtures usam pasta generica em vez da forma de diretorio pessoal pelo
#     motivo ja explicado no cabecalho: o gate de publicacao recusa a outra, e com
#     razao. O saneador casa qualquer caminho com letra de unidade.)
igual "nome de pasta COM espaco nao sobrevive" \
  "$(sanear 'erro em C:\pasta\Fulano De Tal\arquivo config.json')" \
  'erro em <caminho>\arquivo config.json'
igual "pasta com espaco no meio do caminho" \
  "$(sanear 'launcher em C:\Program Files\Bridge\start.ps1 nao existe')" \
  'launcher em <caminho>\start.ps1 nao existe'
igual "varios segmentos com espaco em sequencia" \
  "$(sanear 'config em C:\Meus Projetos\Fulano De Tal\vigia.config.json')" \
  'config em <caminho>\vigia.config.json'
# E a prova de que aceitar espaco nao fez o casador engolir a frase inteira: com
# `:` fora do segmento intermediario, "um.txt para D:" nao pode virar um segmento.
igual "aceitar espaco nao funde dois caminhos num marcador so" \
  "$(sanear 'copiando de C:\um lugar\a.txt para D:\outro lugar\b.txt agora')" \
  'copiando de <caminho>\a.txt para <caminho>\b.txt agora'
igual "prosa depois do caminho continua prosa" \
  "$(sanear 'raiz C:\pasta com espaco\dados\x.md e o resto da frase')" \
  'raiz <caminho>\x.md e o resto da frase'

echo
echo "== D. a trava: nenhuma escrita escapa da porta unica =="
# Olha LINHA DE EXECUCAO, nao o arquivo inteiro: os cabecalhos dos tres arquivos
# citam `Out-File` de proposito, para explicar por que ele saiu, e apagar essa
# explicacao para a trava passar seria apagar a razao. Mesmo desenho da trava de
# `git push` em testa-backup-estado.sh.
# `sem_comentario` tira as DUAS formas de comentario do PowerShell: a linha
# iniciada por `#` e o bloco `<# ... #>`. A primeira versao desta trava so tirava
# a linha, e por isso acusou o proprio erros.ps1: o bloco de ajuda dele cita
# `Out-File -Append` ao explicar o que substituiu. Trava que nao distingue
# comentario de execucao obriga a apagar a explicacao para ficar verde, que e o
# oposto do que ela existe para proteger.
sem_comentario() {
  awk '
    /<#/ { bloco=1 }
    bloco { if (/#>/) bloco=0; next }
    /^[ 	]*#/ { next }
    { print }
  ' "$1"
}
for alvo in run-vigia.ps1 backup-estado.ps1 erros.ps1; do
  exec_do_arquivo="$(sem_comentario "$SRC/vigias/$alvo")"
  if printf '%s' "$exec_do_arquivo" | grep -qE 'Out-File -Append'; then
    falhou=$((falhou+1)); echo "  FALHA $alvo tem 'Out-File -Append' em linha de execucao"
  else
    ok=$((ok+1)); echo "  ok    $alvo nao tem 'Out-File -Append' em linha de execucao"
  fi
done
# E o contrario: a mesma string em COMENTARIO nao pode acender a trava.
if printf '%s' "$(grep -E '^\s*#' "$SRC/vigias/erros.ps1")" | grep -q 'Out-File'; then
  ok=$((ok+1)); echo "  ok    o comentario cita 'Out-File' e a trava nao acende por isso"
else
  falhou=$((falhou+1)); echo "  FALHA o comentario deveria citar 'Out-File' — sem isso a trava nao esta provada nos dois sentidos"
fi
# Os .ps1 do backup sao ASCII puro por decisao herdada (o cabecalho do
# backup-estado.ps1 explica: travessao em UTF-8 lido como CP-1252 abre string e
# quebra o parser dezenas de linhas adiante). erros.ps1 nasceu depois e herda a
# regra. run-vigia.ps1 fica de fora: ele ja tem acento em comentario desde
# antes, e normaliza-lo agora e mudanca fora do escopo desta entrega.
for alvo in backup-estado.ps1 erros.ps1; do
  # `|| true`, e nao `|| echo 0`: quando nao ha casamento o `grep -c` JA imprime
  # 0 e ainda sai 1, entao o `echo` somava um segundo 0 e a comparacao virava
  # comparacao de dois zeros contra um. Bug do teste, nao do arquivo medido.
  n=$(LC_ALL=C grep -c '[^ -~	]' "$SRC/vigias/$alvo" 2>/dev/null || true)
  igual "$alvo e ASCII puro" "$n" "0"
done

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
