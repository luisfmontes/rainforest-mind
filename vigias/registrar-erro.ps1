# ESTE ARQUIVO E ASCII PURO, DE PROPOSITO - a mesma regra do erros.ps1.
# O PowerShell 5.1 le .ps1 sem BOM como CP-1252, e um travessao em UTF-8 fecha
# string no meio e mata o parse dezenas de linhas adiante. Hifen, nunca
# travessao; nenhum acento em string nem em comentario.
#
# ===========================================================================
# A porta de entrada do AGENTE para o vigias/ERROS.md (Issue #146).
# ===========================================================================
#
# O `erros.ps1` e a unica porta de ESCRITA, e ela ja resolve LF, UTF-8 sem BOM,
# mojibake de codepage OEM e saneamento de caminho de maquina. Mas ela e uma
# BIBLIOTECA: os chamadores dela dot-sourceiam e chamam `Write-ErroDeVigia`.
#
# O `vigias/_comum.md` mandava o agente LLM escrever o arquivo por conta
# propria, em prosa, com o caminho literal. Esse chamador nao passa por porta
# nenhuma - e e o menos previsivel de todos, porque e um modelo de linguagem
# redigindo texto livre com o `vigia.config.json` e caminhos da maquina no
# contexto.
#
# POR QUE ARQUIVO NOVO, E NAO UM `param()` NO `erros.ps1`. Dot-source de script
# com `param()` declara essas variaveis no ESCOPO DE QUEM CHAMA. O
# `run-vigia.ps1` tem o proprio `-Vigia`, e um `param($Vigia)` no `erros.ps1`
# dot-sourced sobrescreveria o dele com string vazia na linha 16, antes de
# qualquer coisa. A porta de entrada tinha de ser um arquivo separado.
#
# O `-Plugin` NAO e parametro de proposito: sai de `$PSScriptRoot`, porque este
# arquivo mora em `<plugin>/vigias/`. Caminho que o chamador nao informa e
# caminho que ele nao pode errar - e, no caso do agente, e o caminho de maquina
# que sai do prompt e para de existir no repositorio.
#
# Uso, do prompt de um vigia:
#   powershell -File <plugin>\vigias\registrar-erro.ps1 -Vigia sentinela-foco -Motivo "bridge fora do ar"

param(
    [Parameter(Mandatory=$true)][string]$Vigia,
    [Parameter(Mandatory=$true)][string]$Motivo,
    [string]$Log
)

$ErrorActionPreference = 'Stop'

$libErros = Join-Path $PSScriptRoot 'erros.ps1'
if (-not (Test-Path $libErros)) {
    # Sem a porta de escrita nao ha onde registrar - o stderr e o que sobra, e
    # e o que o log da tarefa agendada captura.
    [Console]::Error.WriteLine("erro: nao achei o erros.ps1 ao lado de $PSScriptRoot")
    exit 1
}
. $libErros

$plugin = Split-Path -Parent $PSScriptRoot

# NAO propaga excecao. Registrar uma falha nao pode ser o que derruba a ronda -
# o mesmo raciocinio do try/catch dentro do Write-LinhaEmLf, um andar acima.
try {
    if ($Log) {
        Write-ErroDeVigia -Vigia $Vigia -Motivo $Motivo -Plugin $plugin -Log $Log
    } else {
        Write-ErroDeVigia -Vigia $Vigia -Motivo $Motivo -Plugin $plugin
    }
} catch {
    [Console]::Error.WriteLine("erro ao registrar: $($_.Exception.Message)")
    exit 1
}

exit 0
