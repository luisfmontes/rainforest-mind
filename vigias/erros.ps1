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
#>
function Get-MotivoSaneado([string]$Motivo) {
    if (-not $Motivo) { return $Motivo }

    $avaliador = {
        param($m)
        $inteiro = $m.Value
        # Ultimo segmento depois de \ ou /. Caminho terminado em separador
        # (uma PASTA) nao tem folha util: vira so o marcador.
        $folha = ($inteiro -split '[\\/]' | Where-Object { $_ -ne '' } | Select-Object -Last 1)
        if ($inteiro -match '[\\/]$' -or -not $folha -or $folha -match '^[A-Za-z]:$') {
            return '<caminho>'
        }
        return "<caminho>\$folha"
    }

    # Letra de unidade OU UNC, seguido de qualquer coisa que nao seja espaco,
    # aspa ou fecha-parenteses (os delimitadores que as mensagens de fato usam).
    $re = '(?:[A-Za-z]:[\\/]|\\\\)[^\s"'')]*'
    return [regex]::Replace($Motivo, $re, $avaliador)
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
    Write-LinhaEmLf -Caminho (Join-Path $Plugin "vigias\ERROS.md") -Linha $linha
    if ($Log) { Write-LinhaEmLf -Caminho $Log -Linha $linha }
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
    $dir = Split-Path -Parent $Caminho
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::AppendAllText($Caminho, $Linha + "`n", $script:Utf8SemBom)
}
