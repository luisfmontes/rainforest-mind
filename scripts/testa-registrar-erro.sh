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
# O argumento entra numa string de ASPA SIMPLES do PowerShell, entao todo
# apostrofo dele precisa ser DOBRADO antes. A primeira versao nao dobrava, e as
# duas fixtures com apostrofo devolviam string VAZIA — o que parecia defeito do
# saneador e era defeito do harness. Chamador quebrado que acusa o artefato e a
# forma mais barata de perder uma hora, e este arquivo ja gastou uma assim.
sanear() {
  local arg=${1//\'/\'\'}
  powershell -NoProfile -ExecutionPolicy Bypass -Command \
    ". '$(win "$SB/plugin/vigias/erros.ps1")'; Get-MotivoSaneado '$arg'" 2>/dev/null | tr -d '\r'
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

# --- CARACTERE QUE PARECE DELIMITADOR MAS E PARTE DO NOME. Segunda rodada de
#     vazamento, achada pela revisao em 2026-09-02. O conserto anterior aceitava
#     espaco mas continuava excluindo `(`, `)` e `'` — e esses tres aparecem
#     DENTRO de nome de pasta real com muita frequencia. A fixture antiga usava
#     `C:\Program Files\Bridge\...`, ou seja, o caminho real mais comum do
#     Windows testado na forma que NAO existe na pratica: a de 64 bits tem o
#     `(x86)` entre parenteses.
#
#     A regra que saiu daqui: o segmento intermediario exclui exatamente o que o
#     Windows PROIBE num componente (`< > : " | ? *`), e nada mais. Estes casos
#     existem para que uma lista ad-hoc nao volte pela terceira vez.
igual "parenteses no nome da pasta (a pasta de programas de 32 bits)" \
  "$(sanear 'launcher em C:\Program Files (x86)\App\bridge.ps1 nao existe')" \
  'launcher em <caminho>\bridge.ps1 nao existe'
igual "parenteses E espaco no mesmo caminho" \
  "$(sanear 'raiz C:\Program Files (x86)\App De Alguem\dados\nao-existe')" \
  'raiz <caminho>\nao-existe'
igual "apostrofo no nome da pasta (sobrenome comum)" \
  "$(sanear "config em C:\\pasta\\O'Brien\\dados\\x.json falhou")" \
  'config em <caminho>\x.json falhou'
igual "hifen e acento no nome da pasta" \
  "$(sanear 'pasta C:\Mary-Jane Smith\dados\y.txt aqui')" \
  'pasta <caminho>\y.txt aqui'
igual "e-comercial e colchete no nome da pasta" \
  "$(sanear 'em C:\A & B [1]\dados\w.txt fim')" \
  'em <caminho>\w.txt fim'
# E o outro lado: os MESMOS caracteres, quando de fato delimitam o caminho na
# frase, continuam sendo tratados como delimitador. E a distincao que as duas
# rodadas de vazamento nao faziam.
igual "parenteses que DELIMITA o caminho continua delimitando" \
  "$(sanear 'mensagem (C:\pasta\Fulano\x.json) e o resto')" \
  'mensagem (<caminho>\x.json) e o resto'
igual "apostrofo que DELIMITA o caminho continua delimitando" \
  "$(sanear "valor atual: 'C:\\pasta\\Fulano\\app\\b.ps1'")" \
  "valor atual: '<caminho>\\b.ps1'"

echo
echo "== C3. formas que o casador nao enxergava — a varredura adversarial =="
# As duas primeiras rodadas de vazamento foram achadas por revisao independente.
# Esta terceira foi procurada de proposito, contra formas que ninguem tinha
# tentado — e achou mais tres. Cada uma virou uma alternativa no abridor, e cada
# uma tem caso aqui para nao voltar calada.

# 1. O PIOR DELES. O `e:` de `file:` casava como letra de unidade: o casador
#    comia `e:///`, punha o marcador ALI, e o caminho de verdade logo depois
#    ficava INTOCADO. Produzia uma linha que PARECIA saneada — o modo de falha
#    mais caro que existe num gate, porque some da inspecao visual.
igual "esquema de URL nao pode ser confundido com letra de unidade" \
  "$(sanear 'url file:///C:/pasta/Fulano/x.json invalida')" \
  'url file:///<caminho>\x.json invalida'
igual "e vale para qualquer esquema, nao so file" \
  "$(sanear 'url http://host/C:/pasta/Fulano/x.json invalida')" \
  'url http://host/<caminho>\x.json invalida'

# 2. Prefixo estendido do Windows. O `\\` simples casava e travava no `?`,
#    deixando o resto do caminho de fora.
igual "prefixo estendido com letra de unidade" \
  "$(sanear 'raiz \\?\C:\pasta\Fulano\x.json falhou')" \
  'raiz <caminho>\x.json falhou'
igual "prefixo estendido com UNC" \
  "$(sanear 'raiz \\?\UNC\servidor\compart\Fulano\x.json falhou')" \
  'raiz <caminho>\x.json falhou'

# 3. Caminho relativo. O comentario da funcao afirmava que relativo "nao
#    identifica maquina nem usuario" — e afirmava errado.
igual "caminho relativo com .. tambem identifica pessoa" \
  "$(sanear 'relativo ..\..\Users\Fulano\x.json nao existe')" \
  'relativo <caminho>\x.json nao existe'

# E o outro lado, para o abridor novo nao virar rede de arrasto:
igual "reticencias em prosa nao viram caminho relativo" \
  "$(sanear 'reticencias ... no meio da frase')" \
  'reticencias ... no meio da frase'
igual "variavel de ambiente nao expandida fica como esta (nao ha nome dentro)" \
  "$(sanear 'raiz %USERPROFILE%\dados\z.txt nao existe')" \
  'raiz %USERPROFILE%\dados\z.txt nao existe'
igual "pasta terminando em ponto nao confunde o casador" \
  "$(sanear 'raiz C:\pasta\Fulano.\dados\y.txt aqui')" \
  'raiz <caminho>\y.txt aqui'

echo
echo "== C4. JID de WhatsApp — o dado que ja estava no repositorio publico =="
# Achado em 2026-09-02 LENDO o ERROS.md commitado: ele carregava, em duas
# linhas, o JID real do grupo que recebe as rondas — num repo PUBLICO. As linhas
# nasceram de um erro de envio, ou seja, exatamente pelo caminho que a Issue
# #124 descreve. O conferir-publicacao.cjs ja tinha regra dizendo que JID vira
# marcador; o que faltava era alguem aplica-la na ESCRITA.
#
# OS JIDS DESTA SECAO SAO MONTADOS EM PEDACOS, e isso e parte do teste. Escrever
# um JID literal aqui e exatamente o que o gate de publicacao existe para
# barrar — e ele barrou esta bateria na primeira tentativa, com razao. Nenhum
# pedaco isolado tem forma de telefone nem de JID. Mesmo cuidado das fixtures de
# mojibake, que sao montadas por bytes.
g1=120363; g2=411360; g3=335027          # 18 digitos: forma de JID de GRUPO
d1=554799; d2=1234567                     # 13 digitos: forma de conversa DIRETA
JID_GRUPO="${g1}${g2}${g3}@g.us"
JID_DIRETO="${d1}${d2}@s.whatsapp.net"

igual "JID de grupo vira marcador" \
  "$(sanear "send_message failed - conta nao participa do grupo JID $JID_GRUPO")" \
  'send_message failed - conta nao participa do grupo JID <jid>'
# Conversa direta e pior: ali o JID E o telefone, com DDI e DDD.
igual "JID de conversa direta tambem (ele E o telefone)" \
  "$(sanear "falha ao enviar para $JID_DIRETO agora")" \
  'falha ao enviar para <jid> agora'
igual "dois JIDs na mesma mensagem" \
  "$(sanear "de $JID_DIRETO para $JID_GRUPO")" \
  'de <jid> para <jid>'
# A faixa vai ate 20 digitos DE PROPOSITO: JID de grupo tem 18, e a regra do
# conferir-publicacao.cjs para em 15 — foi por isso que ela nunca pegou este
# caso, e o dado ficou no repositorio. Este caso fixa a diferenca.
igual "18 digitos (grupo) esta dentro da faixa, ao contrario da regra do gate" \
  "$(sanear "grupo $JID_GRUPO fora")" \
  'grupo <jid> fora'
# E o outro lado: numero sem o sufixo de JID nao pode virar marcador, senao a
# mensagem perde o dado que ajuda a diagnosticar.
igual "numero longo SEM sufixo de JID fica como esta" \
  "$(sanear "id da mensagem ${g1}${g2}${g3} recusado")" \
  "id da mensagem ${g1}${g2}${g3} recusado"
igual "numero curto de porta nao vira marcador" \
  "$(sanear 'bridge nao subiu apos 60s (porta 3005 fechada)')" \
  'bridge nao subiu apos 60s (porta 3005 fechada)'
# JID MULTI-DISPOSITIVO: `<numero>:<aparelho>@...`. O `:N` quebrava a adjacencia
# que o regex exigia e o JID passava INTEIRO — e nessa forma o JID E o telefone,
# com DDI e DDD. Achado na revisao testando o outro lado da faixa de digitos.
dev=26
igual "JID multi-dispositivo (o :N nao pode quebrar o casamento)" \
  "$(sanear "send_message failed para ${d1}${d2}:${dev}@s.whatsapp.net")" \
  'send_message failed para <jid>'
# E os formatos que NAO devem ser saneados, de proposito: `@lid` e o que o
# proprio WhatsApp criou para nao expor o numero real. Sanear ali seria apagar
# diagnostico sem proteger ninguem.
igual "@lid NAO e saneado (ele existe justamente para nao ser o numero)" \
  "$(sanear "privacidade ${g1}${g2}@lid ok")" \
  "privacidade ${g1}${g2}@lid ok"
# Os dois lados numericos: nada com forma de id longo pode virar marcador sem o
# sufixo de JID colado. O timestamp tambem vai montado — 13 digitos seguidos tem
# forma de telefone, e o gate de publicacao recusou este arquivo por causa dele
# na primeira tentativa. O gate estava certo na forma; a fixture e que precisava
# nao plantar a forma.
ts1=172525; ts2=4400000
igual "timestamp longo nao vira marcador" \
  "$(sanear "evento em ${ts1}${ts2} registrado")" \
  "evento em ${ts1}${ts2} registrado"
igual "numero de Issue nao vira marcador" \
  "$(sanear 'ver a Issue 149 aberta hoje')" \
  'ver a Issue 149 aberta hoje'

echo
echo "== C5. o saneamento nao pode destruir a mensagem =="
# Vazar e um defeito; virar ilegivel e outro. O ERROS.md existe para ser LIDO —
# ficou cinco dias sem ninguem abrir, e mensagem que nao diz nada garante que
# isso se repita. Estes casos sao as mensagens REAIS dos chamadores.
igual "a mensagem de destino continua dizendo QUAL arquivo configurar" \
  "$(sanear 'sem destino de envio: defina RFM_WHATSAPP_DESTINO ou destinoWhatsapp em C:\Projetos\comms-vigia\vigia.config.json')" \
  'sem destino de envio: defina RFM_WHATSAPP_DESTINO ou destinoWhatsapp em <caminho>\vigia.config.json'
igual "a do bridge preserva o arquivo E o valor atual, os dois saneados" \
  "$(sanear "bridge fora do ar e sem launcher: defina RFM_BRIDGE_LAUNCHER ou bridgeLauncher em C:\\Projetos\\comms-vigia\\vigia.config.json (valor atual: 'C:\\Program Files (x86)\\Bridge\\start.ps1')")" \
  "bridge fora do ar e sem launcher: defina RFM_BRIDGE_LAUNCHER ou bridgeLauncher em <caminho>\\vigia.config.json (valor atual: '<caminho>\\start.ps1')"
igual "a do toggle nao tem caminho e passa inteira, com aspas e interrogacao" \
  "$(sanear "nao consegui ler o toggle 'vigias' (node no PATH?)")" \
  "nao consegui ler o toggle 'vigias' (node no PATH?)"

echo
echo "== C6. escrita que FALHA nao pode matar a ronda em silencio =="
# Achado na revisao (2026-09-02): sem try/catch, uma falha real de escrita
# (disco cheio, ACL negada, arquivo travado, caminho longo demais) subia como
# excecao do .NET e derrubava a ronda SEM registrar nada. Tarefa que parece
# saudavel e nao faz o que devia — o V1 desta entrega, dentro da porta que
# existe para curar exatamente isso.
#
# A falha e provocada de verdade: caminho que nao pode existir (um ARQUIVO no
# lugar onde o codigo precisaria de uma PASTA). Nao ha mock aqui.
montar
BLOQUEIO="$SB/bloqueio"
printf 'sou um arquivo, nao uma pasta
' > "$BLOQUEIO"
SAIDA_ERRO=$(powershell -NoProfile -ExecutionPolicy Bypass -Command   ". '$(win "$SB/plugin/vigias/erros.ps1")';    \$r = Write-LinhaEmLf -Caminho '$(win "$BLOQUEIO")\sub\x.md' -Linha 'teste';    Write-Output \"RETORNO=\$r\"" 2>&1 | tr -d '')
printf '%s
' "$SAIDA_ERRO" | sed 's/^/     /'
printf '%s' "$SAIDA_ERRO" | grep -q 'RETORNO=False' && r=sim || r=nao
verdade "a escrita que falha devolve False em vez de lancar" "$r"
printf '%s' "$SAIDA_ERRO" | grep -q 'nao consegui escrever' && r=sim || r=nao
verdade "e o motivo vai para o stderr, que e o canal que sobra" "$r"
# O padrao e montado por printf para nao depender de quantas camadas de escape
# o shell come: a primeira versao virava um padrao terminado em barra invertida
# solta, o grep morria com "Trailing backslash", e a FALHA DO GREP era lida
# como "nao achou" — a assercao passava por acidente, sem medir nada. Terceira
# vez nesta entrega que um chamador quebrado se disfarca de artefato aprovado.
PADRAO_UNIDADE="[A-Za-z]:$(printf '\\\\')"
printf '%s' "$SAIDA_ERRO" | grep -qE "$PADRAO_UNIDADE" && r=sim || r=nao
falso "o caminho no stderr tambem passa pelo saneamento" "$r"

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

# ==========================================================================
# A trava que a bateria de .ps1 nao alcanca: PROSA mandando escrever o arquivo
# ==========================================================================
#
# Issue #146. A trava acima fica vermelha se alguem acrescentar um
# `Out-File -Append` em qualquer .ps1 de vigias/ — e ela nao olha, e nao teria
# como olhar do mesmo jeito, uma instrucao em PROSA dentro de um .md.
#
# O `vigias/_comum.md` mandava o agente LLM acrescentar linha no ERROS.md por
# conta propria, com o caminho literal da maquina. Esse chamador nao passa pela
# porta: escreve sem saneamento de caminho, sem garantia de LF e sem garantia
# de encoding — e e o menos previsivel de todos, porque e um modelo redigindo
# texto livre com o vigia.config.json no contexto.
#
# O comentario de desenho da porta unica diz que sanear na ESCRITA, e nao na
# disciplina de quem redige, e o que faz "a defesa valer para o chamador que
# ainda nao existe". Este caso e o inverso: o chamador ja existia.
#
# A regra: em .md de vigias/, VERBO IMPERATIVO DE ESCRITA + ERROS.md na mesma
# linha (ou nas duas seguintes) so passa se `registrar-erro.ps1` aparecer por
# perto. LER o ERROS.md continua livre — a restricao e de escrita.
echo
echo "== prosa de vigias/*.md nao manda escrever o ERROS.md direto =="

VERBOS='acrescente|escreva|adicione|grave|registre em|anote em|append|edite'
achados_prosa=""
for md in "$SRC"/vigias/*.md; do
  [ -f "$md" ] || continue
  # -A2: a instrucao costuma quebrar linha entre o verbo e o caminho, que foi
  # exatamente a forma do _comum.md ("acrescente uma linha em\n`<caminho>`").
  bloco=$(grep -niE "($VERBOS)" "$md" -A2 2>/dev/null || true)
  printf '%s' "$bloco" | grep -qi 'ERROS\.md' || continue
  # A isencao olha o ARQUIVO INTEIRO, nao a janela: um prompt que NOMEIA a porta
  # ja mandou usar a porta, e o pedaco que proibe a escrita direta ("Nunca edite
  # o ERROS.md") cai a varias linhas do comando e acendia a trava sozinho — a
  # trava reprovando justamente o texto que a cumpre.
  grep -qi 'registrar-erro\.ps1' "$md" && continue
  achados_prosa="$achados_prosa $(basename "$md")"
done

if [ -z "$achados_prosa" ]; then
  ok=$((ok+1)); echo "  ok    nenhum .md de vigias/ manda escrever o ERROS.md sem a porta"
else
  falhou=$((falhou+1))
  echo "  FALHA .md mandando escrever o ERROS.md direto:$achados_prosa"
  echo "        use: powershell -File <plugin>\\vigias\\registrar-erro.ps1 -Vigia <nome> -Motivo \"<erro>\""
fi

# O outro sentido, para a trava nao ser decorativa: uma prosa PLANTADA numa caixa
# tem de acender. Sem isto, a checagem acima passaria igual se o grep estivesse
# quebrado — que e o defeito que este repositorio ja catalogou quatro vezes.
CAIXA_MD="$(mktemp -d)"
mkdir -p "$CAIXA_MD/vigias"
printf 'Se falhar, acrescente uma linha em\n`vigias/ERROS.md` no formato padrao.\n' > "$CAIXA_MD/vigias/falso.md"
bloco_teste=$(grep -niE "($VERBOS)" "$CAIXA_MD/vigias/falso.md" -A2 2>/dev/null || true)
if printf '%s' "$bloco_teste" | grep -qi 'ERROS\.md'; then
  ok=$((ok+1)); echo "  ok    e a trava ACENDE numa prosa plantada (nao e decorativa)"
else
  falhou=$((falhou+1)); echo "  FALHA a trava nao acendeu na prosa plantada — o padrao nao mede nada"
fi
rm -rf "$CAIXA_MD"

# ==========================================================================
# O criterio 1 da Issue #146: PROVOCAR o caminho do agente numa caixa.
# ==========================================================================
#
# Nao basta o prompt apontar para a porta: a porta tem de existir, rodar, e o
# que sai dela tem de estar saneado. Isto EXECUTA o registrar-erro.ps1 com um
# motivo que carrega caminho de maquina — que e exatamente a mensagem que um
# LLM redige quando tem o vigia.config.json no contexto — e olha os BYTES do
# arquivo que saiu.
#
# O -Plugin nao e passado de proposito: ele sai de $PSScriptRoot. Caminho que o
# chamador nao informa e caminho que ele nao pode errar, e no caso do agente e
# o caminho de maquina que some do prompt.
echo
echo "== o registrar-erro.ps1 executado de verdade, numa caixa =="

CAIXA_RE="$(mktemp -d)"
mkdir -p "$CAIXA_RE/vigias"
cp "$SRC/vigias/erros.ps1" "$SRC/vigias/registrar-erro.ps1" "$CAIXA_RE/vigias/"

MOTIVO_SUJO='bridge fora do ar: defina destinoWhatsapp em C:\Users\Fulano\AppData\Local\vigia.config.json'
powershell -NoProfile -File "$CAIXA_RE/vigias/registrar-erro.ps1" \
  -Vigia sentinela-foco -Motivo "$MOTIVO_SUJO" >/dev/null 2>&1
igual "exit 0 (registrar falha nao derruba a ronda)" "$?" "0"

ALVO_RE="$CAIXA_RE/vigias/ERROS.md"
if [ -f "$ALVO_RE" ]; then
  ok=$((ok+1)); echo "  ok    o ERROS.md foi criado pela porta"

  CONTEUDO_RE="$(cat "$ALVO_RE")"
  # O nome do usuario e o que nao pode sair. `Fulano` esta no motivo de entrada.
  if printf '%s' "$CONTEUDO_RE" | grep -q 'Fulano'; then
    falhou=$((falhou+1)); echo "  FALHA o nome do usuario sobreviveu ao saneamento: $CONTEUDO_RE"
  else
    ok=$((ok+1)); echo "  ok    o nome do usuario NAO esta no arquivo"
  fi
  if printf '%s' "$CONTEUDO_RE" | grep -qi 'C:.Users'; then
    falhou=$((falhou+1)); echo "  FALHA o caminho de maquina sobreviveu: $CONTEUDO_RE"
  else
    ok=$((ok+1)); echo "  ok    o caminho de maquina NAO esta no arquivo"
  fi
  # E o controle: o motivo tem de continuar LEGIVEL. Saneamento que apaga a
  # mensagem inteira "passa" nos dois casos acima e nao serve para nada.
  if printf '%s' "$CONTEUDO_RE" | grep -q 'bridge fora do ar'; then
    ok=$((ok+1)); echo "  ok    e o motivo continua legivel (o saneamento nao comeu a mensagem)"
  else
    falhou=$((falhou+1)); echo "  FALHA o motivo sumiu junto com o caminho: $CONTEUDO_RE"
  fi
  # LF e sem BOM, por NODE: o grep do Git Bash normaliza CRLF antes de casar e
  # responde "nao achei" num arquivo que É CRLF.
  CRLF_RE=$(node -e 'const b=require("fs").readFileSync(process.argv[1]);console.log(b.includes(13)?"CR":"LF",b[0]===0xEF?"BOM":"SEMBOM")' "$ALVO_RE")
  igual "gravou em LF, sem BOM" "$CRLF_RE" "LF SEMBOM"
else
  falhou=$((falhou+1)); echo "  FALHA a porta nao criou o ERROS.md"
fi
rm -rf "$CAIXA_RE"

# A porta de entrada do agente tem de existir e ser ASCII puro, pela mesma razao
# dos outros .ps1 (CP-1252 no PowerShell 5.1).
if [ -f "$SRC/vigias/registrar-erro.ps1" ]; then
  ok=$((ok+1)); echo "  ok    vigias/registrar-erro.ps1 existe"
  n=$(LC_ALL=C grep -c '[^ -~	]' "$SRC/vigias/registrar-erro.ps1" 2>/dev/null || true)
  igual "registrar-erro.ps1 e ASCII puro" "$n" "0"
else
  falhou=$((falhou+1)); echo "  FALHA vigias/registrar-erro.ps1 nao existe — o _comum.md aponta para ele"
fi

echo
echo "-----------------------------------------"
echo "ok: $ok   falhou: $falhou"
[ "$falhou" -eq 0 ]
