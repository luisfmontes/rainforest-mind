# ESTE ARQUIVO E ASCII PURO, DE PROPOSITO - a mesma regra do backup-estado.ps1.
# O PowerShell 5.1 le .ps1 sem BOM como CP-1252: um travessao em UTF-8
# (E2 80 94) chega como tres caracteres, e o ultimo e a aspa tipografica U+201D,
# que o tokenizer aceita como delimitador de string. A string FECHA no meio e o
# parse morre dezenas de linhas adiante, apontando o lugar errado.
# Escreva hifen, nunca travessao. Nenhum acento em string nem em comentario.
#
# ===========================================================================
# A UNICA porta de escrita do vigias/ERROS.md.
# ===========================================================================
#
# Existe porque a escrita estava espalhada em SEIS lugares - quatro no
# run-vigia.ps1 (toggle ilegivel, -Cwd inexistente, Stop-ComErro, bridge que
# nao subiu) e dois no backup-estado.ps1 - todos com a mesma linha copiada:
#
#     "- $(Get-Date ...) [$Vigia]: $Motivo" | Out-File -Append -Encoding utf8 ...
#
# Seis copias da mesma decisao, e por isso TRES defeitos diferentes moravam em
# todas as seis ao mesmo tempo. Os tres estao consertados aqui, uma vez so:
#
# --- 1. CRLF (V3 desta entrega) -------------------------------------------
# `Out-File` no PowerShell 5.1 termina linha com CRLF, sempre. O ERROS.md e
# commitado em LF. Append em CRLF sobre arquivo LF produz fim de linha MIXED, e
# `node scripts/conferir-encoding.cjs` recusa com exit 2. Como o backup falhava
# toda ronda (V2), CADA ronda de vigia acendia uma bateria vermelha no
# repositorio inteiro. Aqui a escrita e [IO.File]::AppendAllText com "`n"
# explicito e UTF-8 SEM BOM - `Out-File -Encoding utf8` no 5.1 poe BOM ao criar
# arquivo novo, e BOM tambem e recusado pela catraca.
#
# --- 2. MOJIBAKE DE CODEPAGE OEM (V4) -------------------------------------
# O texto de erro vem do stderr do `node`, em UTF-8. O PowerShell decodifica a
# saida de processo nativo usando [Console]::OutputEncoding, que numa tarefa
# agendada e o codepage OEM (CP850 nesta maquina). Os bytes C3 A3 da letra a-til viram
# dois caracteres de outra tabela, e o resultado e regravado em UTF-8 valido -
# mojibake permanente, ja commitado no ERROS.md desde 27/08.
# Quem conserta a LEITURA e o Set-EncodingDeSaida abaixo, chamado ANTES de
# invocar o node. Este arquivo tambem carrega a prova pela negativa: o
# conferir-encoding.cjs so conhecia a assinatura CP1252 e passava batido nessa.
#
# --- 3. CAMINHO DE MAQUINA EM REPO PUBLICO (Issue #124) -------------------
# O ERROS.md e RASTREADO neste repositorio, que e publico, e tres chamadores
# interpolam caminho de usuario na mensagem ($configPath, $bridgeLauncher).
# Ja foi empurrado sozinho para a main duas vezes (bb77232, 17ba994). Sanear na
# porta de escrita, e nao na disciplina de quem redige a mensagem, e o que faz
# a defesa valer para o chamador que ainda nao existe.

# UTF-8 sem BOM. Instanciado uma vez: `New-Object Text.UTF8Encoding($false)` e
# o unico jeito de pedir "UTF-8 e NAO ponha BOM" no 5.1 - [Text.Encoding]::UTF8
# carrega BOM.
$script:Utf8SemBom = New-Object System.Text.UTF8Encoding($false)

<#
.SYNOPSIS
Faz o PowerShell decodificar a saida de processo nativo como UTF-8.

.DESCRIPTION
Chamar ANTES de qualquer `& node ...` cuja saida possa ir para o ERROS.md ou
para o log. Sem isto, a saida do node atravessa o codepage OEM do console e o
acento vira mojibake permanente (defeito V4).

Devolve a codificacao anterior, para quem quiser restaurar. Falha em silencio
por desenho: em host sem console (tarefa agendada em certas configuracoes) a
atribuicao lanca, e derrubar a ronda inteira por causa da acentuacao de uma
mensagem de erro seria trocar um defeito cosmetico por um defeito de operacao.
#>
function Set-EncodingDeSaida {
    $anterior = $null
    try {
        $anterior = [Console]::OutputEncoding
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    } catch {
        # sem console: segue como esta
    }
    return $anterior
}

<#
.SYNOPSIS
Troca caminho absoluto de maquina por marcador, preservando o nome do arquivo.

.DESCRIPTION
Issue #124. O ERROS.md e versionado em repositorio publico e recebe mensagem
montada em tempo de execucao, com interpolacao de variavel - inclusive
$configPath e $bridgeLauncher, que sao caminhos da maquina do usuario e trazem
o nome de usuario dentro.

O marcador preserva o ULTIMO segmento do caminho. Trocar o caminho inteiro por
`<caminho>` tornaria a mensagem inutil para diagnostico ("nao achei o que?"),
e a informacao que resolve o problema e o NOME do arquivo, nao onde ele mora.
`.../vigia.config.json` diz tudo que o leitor precisa e nao diz quem e o dono
da maquina.

Cobre caminho com letra de unidade (C:\...) e UNC (\\servidor\...). Nao cobre
caminho relativo, que nao identifica maquina nem usuario.

A REGRA DE QUAIS CARACTERES ENTRAM NUM SEGMENTO, e as DUAS rodadas de vazamento
que foram precisas para chegar nela. Vale ler antes de mexer aqui.

Rodada 1, o regex original: `[^\s"'')]*`. Ele PARA no primeiro espaco, e no
Windows nome de pasta com espaco e o caso mais comum que existe. A revisao
independente reproduziu rodando o backup-estado.ps1 de verdade:

  ... nao achei o FOCO.md em <caminho>\Usuario Fernando Que Nao Deve Vazar\dados\nao-existe

A letra de unidade saia e o nome sobrevivia inteiro, num arquivo RASTREADO em
repositorio PUBLICO. A bateria nao pegou porque o usuario falso dela nao tinha
espaco: 26 de 26 verdes sem provar a propriedade que a Issue #124 pede.

Rodada 2, o conserto que ainda vazava: passou a aceitar espaco, mas continuou
excluindo `(`, `)` e `'`. A revisao achou de novo, e os exemplos matam a
questao - a pasta de programas de 32 bits, que existe em TODO Windows de 64
bits e leva `(x86)` entre parenteses no nome, e sobrenome com apostrofo, que e
comum. Os dois vazavam quase inteiros.

A LICAO, e a regra que sai dela: eu estava confundindo dois conjuntos
diferentes de caracteres. Os que DELIMITAM um caminho dentro de uma frase
(aspa, apostrofo, parentese, virgula) nao sao os mesmos que podem estar DENTRO
de um nome de pasta. Tratar os primeiros como se fossem impossiveis nos
segundos e o que produziu as duas rodadas de vazamento.

Entao a regra deixou de ser lista ad-hoc e passou a ser a do sistema de
arquivos: o segmento intermediario exclui exatamente os caracteres que o
Windows PROIBE num componente de caminho - `< > : " | ? *` - mais os
separadores e a quebra de linha. Todo o resto e legal num nome de pasta e
portanto entra: espaco, parentese, apostrofo, hifen, ponto, virgula,
e-comercial, colchete.

A FOLHA e mais estrita, e de proposito: alem dos proibidos, ela exclui os que
delimitam o caminho na frase, porque e ali que a mensagem volta a ser prosa.
Perder o `(1)` de `arquivo (1).txt` custa detalhe de exibicao; nao perder
custaria a frase inteira dentro do marcador.

O `:` FICA DE FORA do intermediario, e isso nao e detalhe: sem essa exclusao o
casador atravessa `um.txt para D:\` como se fosse um segmento com espaco e
engole DOIS caminhos distintos num marcador so.

Rodada 3, a varredura adversarial: as duas primeiras rodadas foram achadas por
outra pessoa, entao esta foi feita de proposito contra formas que ninguem tinha
tentado. Tres vazamentos a mais, e o primeiro e o pior de todos:

  - `file:///C:/pasta/...` - o `e:` de `file:` casava como letra de unidade. O
    casador comia `e:///`, punha marcador ALI, e o caminho de verdade logo
    depois ficava intocado. Produzia uma linha que PARECIA saneada. Vale para
    qualquer esquema (`http:`, `abc:`).
  - `\\?\UNC\servidor\...` e `\\?\C:\...` - o prefixo estendido travava o
    casador no `?`, e o resto sobrevivia.
  - `..\..\Users\Fulano\x.json` - caminho relativo identifica pessoa do mesmo
    jeito, e o comentario acima dizia o contrario.

LIMITE CONHECIDO E ACEITO, nao buraco esquecido: a FOLHA e preservada de
proposito, entao um nome de ARQUIVO que contenha nome de pessoa passa
(`C:\x\relatorio-do-Fulano.pdf` -> `<caminho>\relatorio-do-Fulano.pdf`). E o
mesmo compromisso explicado acima: sem a folha a mensagem nao diz o que faltou.
Na pratica os chamadores interpolam nomes fixos - `vigia.config.json`,
`bridge.ps1` - entao o risco e teorico. Se um dia um chamador interpolar caminho
com nome de pessoa no ARQUIVO, e a folha que precisa mudar, e a decisao volta
para a mesa.
#>
function Get-MotivoSaneado([string]$Motivo) {
    if (-not $Motivo) { return $Motivo }

    # JID DE WHATSAPP, antes do caminho. Achado em 2026-09-02 lendo o ERROS.md
    # commitado: ele carrega, em DUAS linhas, o JID real do grupo que recebe as
    # rondas - num repositorio PUBLICO. As linhas nasceram de um erro de envio
    # ("conta nao participa do grupo JID ..."), ou seja, exatamente pelo caminho
    # que a Issue #124 descreve: mensagem montada em runtime com dado da maquina
    # dentro. O `scripts/conferir-publicacao.cjs` ja tem regra dizendo que JID
    # vira marcador; o que faltava era alguem aplica-la na ESCRITA.
    #
    # Cobre as duas formas: conversa direta (`<telefone>@s.whatsapp.net`, que
    # carrega o numero com DDI e DDD) e grupo (`<id>@g.us`). A faixa de digitos
    # vai ate 20 de proposito: JID de grupo tem 18, e a regra do
    # conferir-publicacao.cjs para em 15 - por isso ela nunca pegou este caso.
    # Ver a Issue aberta sobre alargar aquela regra tambem.
    $Motivo = [regex]::Replace($Motivo, '\b\d{10,20}@(?:s\.whatsapp\.net|g\.us)\b', '<jid>')

    $avaliador = {
        param($m)
        $inteiro = $m.Value
        # Ultimo segmento depois de \ ou /. Os segmentos que sao ESTRUTURA de
        # caminho, e nao nome (`..`, `?`, `.`, `UNC`), nao servem de folha:
        # devolve-los seria trocar um caminho por outro pedaco de caminho.
        # Caminho terminado em separador (uma PASTA) tambem nao tem folha util.
        $folha = ($inteiro -split '[\\/]' |
                  Where-Object { $_ -ne '' -and $_ -ne '..' } |
                  Select-Object -Last 1)
        if ($inteiro -match '[\\/]$' -or -not $folha -or
            $folha -match '^[A-Za-z]:$' -or $folha -match '^[?.]$' -or $folha -eq 'UNC') {
            return '<caminho>'
        }
        return "<caminho>\$folha"
    }

    # ABRIDOR, quatro formas. A ORDEM IMPORTA: a mais especifica vem primeiro,
    # senao o `\\` simples engole o prefixo estendido e para no `?`, deixando o
    # resto do caminho intocado. As quatro sairam de uma varredura adversarial,
    # e as tres ultimas eram vazamento de verdade:
    #
    #   1. prefixo estendido   \\?\C:\...   \\?\UNC\servidor\...   \\.\pipe\...
    #   2. UNC simples         \\servidor\...
    #   3. letra de unidade    C:\...   C:/...
    #   4. relativo com ..     ..\..\Users\Fulano\...  <- identifica pessoa igual
    #
    # O `(?<![A-Za-z0-9])` da forma 3 NAO e zelo. Sem ele, o `e:` de `file:`
    # casa como letra de unidade: o casador come `e:///`, devolve marcador ali, e
    # o caminho REAL que vem logo depois fica INTOCADO. Vale para qualquer
    # esquema de URL - `http:`, `abc:` - e era o pior dos vazamentos, porque
    # produzia uma linha com marcador que PARECIA saneada.
    $prefixo  = '\\\\[?.]\\(?:UNC\\)?(?:[A-Za-z]:[\\/])?'
    $unc      = '\\\\'
    $unidade  = '(?<![A-Za-z0-9])[A-Za-z]:[\\/]'
    $relativo = '(?:\.\.[\\/])+'
    $abridor  = "(?:$prefixo|$unc|$unidade|$relativo)"

    $intermediario = '[^\\/:"<>|?*\r\n]*[\\/]'
    $folhaRe       = "[^\\/:`"<>|?*\r\n\s'(),;]*"

    return [regex]::Replace($Motivo, "$abridor(?:$intermediario)*$folhaRe", $avaliador)
}

<#
.SYNOPSIS
Grava UMA linha de erro de vigia no ERROS.md do plugin, e opcionalmente no log.

.DESCRIPTION
Porta unica. Todo erro de vigia passa por aqui - a bateria
scripts/testa-registrar-erro.sh fica vermelha se alguem acrescentar um
`Out-File` para o ERROS.md em qualquer lugar.

O ERROS.md fica no PLUGIN, nunca no $root (Issue #112, 2026-08-26): e o que a
execucao agendada produz e e de onde o vigias/dados-batedor-repos.js le. Ele e
registro de falha do PLUGIN, nao dado do usuario.
#>
function Write-ErroDeVigia {
    param(
        [Parameter(Mandatory=$true)][string]$Vigia,
        [Parameter(Mandatory=$true)][string]$Motivo,
        [Parameter(Mandatory=$true)][string]$Plugin,
        [string]$Log
    )
    $linha = "- $(Get-Date -Format 'yyyy-MM-dd HH:mm') [$Vigia]: $(Get-MotivoSaneado $Motivo)"
    $gravou = Write-LinhaEmLf -Caminho (Join-Path $Plugin "vigias\ERROS.md") -Linha $linha
    if ($Log) { [void](Write-LinhaEmLf -Caminho $Log -Linha $linha) }
    # Se nem o ERROS.md aceitou a linha, o erro precisa aparecer em ALGUM lugar.
    # A propria linha vai para o stderr: e o unico canal que sobra quando a porta
    # de registro e que falhou, e e o que o log da tarefa agendada captura.
    if (-not $gravou) { [Console]::Error.WriteLine($linha) }
}

<#
.SYNOPSIS
Acrescenta uma linha a um arquivo, terminada em LF, em UTF-8 sem BOM.

.DESCRIPTION
O substituto de `Out-File -Append -Encoding utf8`, que no PowerShell 5.1
termina em CRLF e poe BOM ao criar arquivo. Exposta separada porque o
run-vigia.ps1 tambem escreve linhas de LOG que nao sao erro, e o log em CRLF
tem o mesmo problema no dia em que alguem versionar o log.
#>
function Write-LinhaEmLf {
    param(
        [Parameter(Mandatory=$true)][string]$Caminho,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Linha
    )
    # O try/catch NAO e zelo defensivo generico, e o conserto de um defeito
    # apontado na revisao (2026-09-02) que e a doenca desta entrega inteira,
    # dentro da propria porta que existe para curar.
    #
    # Sem ele, uma falha REAL de escrita - disco cheio, ACL negada, arquivo
    # travado por antivirus, caminho longo demais - sobe como excecao do .NET e
    # derruba a ronda SEM registrar nada sobre o motivo. Tarefa que parece
    # saudavel e nao faz o que devia: exatamente o V1 desta entrega, um andar
    # acima. E a bateria de vigia agendado (T4) nao pegaria, porque ela olha
    # `NextRunTime`, nao `LastTaskResult`.
    #
    # O canal de ultimo recurso e o stderr, e nao ha ironia nisso: quando a
    # porta de registro e que falhou, escrever no lugar onde ela registraria
    # seria tentar duas vezes o que ja nao funcionou. O stderr chega ao log da
    # tarefa agendada, que e o unico canal que sobra.
    #
    # Devolve $true/$false em vez de lancar, para que o chamador possa decidir.
    # Nao lanca NUNCA: derrubar a ronda porque uma LINHA DE LOG nao coube em
    # disco seria trocar um defeito cosmetico por um defeito de operacao - o
    # mesmo raciocinio do Set-EncodingDeSaida.
    try {
        $dir = Split-Path -Parent $Caminho
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [System.IO.File]::AppendAllText($Caminho, $Linha + "`n", $script:Utf8SemBom)
        return $true
    } catch {
        # A MENSAGEM DA EXCECAO TAMBEM PASSA PELO SANEAMENTO, e nao e zelo: o
        # .NET monta o texto dele com o caminho COMPLETO dentro
        # ("Nao foi possivel localizar uma parte do caminho 'C:\...'"), entao
        # sanear so o `$Caminho` que eu passei deixava o vazamento entrar pela
        # porta dos fundos. Achado ao consertar uma assercao desta bateria que
        # passava por acidente - o teste quebrado escondia o defeito.
        #
        # O destino aqui e o stderr, que vai para o log da tarefa agendada, e
        # `vigias/log-*.txt` esta no .gitignore - ou seja, isto NAO chega ao
        # repositorio. Sanear mesmo assim, porque a funcao promete sanear, e
        # promessa que vale so no caminho feliz e a doenca que esta entrega
        # inteira existe para curar.
        $motivo = Get-MotivoSaneado $_.Exception.Message
        [Console]::Error.WriteLine("erro: nao consegui escrever em $(Get-MotivoSaneado $Caminho): $motivo")
        return $false
    }
}
