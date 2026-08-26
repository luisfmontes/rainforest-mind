# ESTE ARQUIVO E ASCII PURO, DE PROPOSITO. O PowerShell 5.1 le .ps1 sem BOM
# como CP-1252: um travessao em UTF-8 (E2 80 94) chega como `a` `EUR` `"` - e
# essa ultima aspa ABRE uma string. Tres travessoes nos comentarios deste
# arquivo deixaram o parser com string nao terminada na linha 74, apontando
# um erro a 60 linhas da causa. Escreva hifen, nao travessao.
#
# Backup do estado do usuario, chamado pelo `sentinela-foco` no fim da ronda.
#
# POR QUE ESTE ARQUIVO EXISTE SEPARADO do run-vigia.ps1 (2026-08-26, Issue #118):
# para chegar no fim do run-vigia.ps1 e preciso node no PATH, o toggle `vigias`
# ligado, destino de WhatsApp configurado, a bridge de pe na porta 3005 e o
# claude.exe respondendo. Uma bateria que executasse o caminho inteiro **enviaria
# uma mensagem de WhatsApp de verdade** - e uma bateria que nao executa nada
# certifica um arquivo que nunca leu. Foi exatamente o que aconteceu na primeira
# tentativa desta tarefa: a bateria fabricava uma copia do bloco e rodava a copia,
# entao com `git push origin main` reintroduzido no arquivo real ela saia
# `9 ok, 0 falha(s)`.
#
# Separado, este pedaco roda numa caixa de areia sem bridge, sem claude e sem
# node do toggle - e passa a ser provavel por execucao.
#
# O QUE SAIU DAQUI, e por que nao volta: ate 2026-08-26 este bloco fazia
#   git -C $root add FOCO.md ideias.jsonl vigias/ERROS.md 2>$null
#   git -C $root commit -m "Backup diario do estado (sentinela)"
#   git -C $root push origin main
# Esse `add` nao podia funcionar em raiz nenhuma: a pasta de dados nao e
# repositorio git, e FOCO.md/ideias.jsonl nao sao versionados no plugin. O
# `2>$null` engolia a falha. Sobrava `vigias/ERROS.md`, que E rastreado no
# plugin, entao a tarefa agendada commitava e empurrava sozinha para a `main` de
# um repositorio PUBLICO. Aconteceu em bb77232 (10/08) e 17ba994 (07/08).
# Backup nao empurra. Se um dia existir copia fora da maquina, ela tem destino
# proprio e nao passa por aqui.

param(
    [Parameter(Mandatory=$true)][string]$Vigia,
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Plugin,
    [string]$Log,
    [switch]$Teste
)

# Quantas copias o rodizio guarda. Numero explicito de proposito: o
# `.ideias-backups` chegou a 293 arquivos por herdar um padrao implicito, que e
# um rodizio que nao roda. 30 cobre um mes de rondas diarias.
$TETO_COPIAS = 30

function Registrar-Erro([string]$Motivo) {
    # Mesmo formato dos outros erros do run-vigia.ps1. O ERROS.md fica no PLUGIN:
    # e o que a execucao agendada produz hoje e e de onde o
    # vigias/dados-batedor-repos.js le. A raiz definitiva e a Issue #112.
    $linha = "- $(Get-Date -Format 'yyyy-MM-dd HH:mm') [$Vigia]: $Motivo"
    $destino = Join-Path $Plugin "vigias\ERROS.md"
    $linha | Out-File -Append -Encoding utf8 $destino
    if ($Log) { $linha | Out-File -Append -Encoding utf8 $Log }
}

# O -Teste bloqueava so o envio, e o backup rodava igual. Em 2026-08-10 um teste
# manual levou o FOCO.md que o usuario tinha modificado e ainda nao commitado
# para a main. Modo de teste que escreve no repositorio do usuario nao e teste.
if ($Teste) {
    if ($Log) { "modo teste: backup do estado NAO executado" | Out-File -Append -Encoding utf8 $Log }
    exit 0
}

$foco = Join-Path $Plugin "scripts\foco.cjs"
if (-not (Test-Path $foco)) {
    Registrar-Erro "nao achei o scripts/foco.cjs em $Plugin - backup do FOCO.md nao rodou"
    exit 1
}

# Sem `2>$null`: era ele que escondia a falha. Falha de backup fala.
$saida = & node $foco backup --raiz $Root --teto $TETO_COPIAS 2>&1
$codigo = $LASTEXITCODE

if ($codigo -ne 0) {
    Registrar-Erro "backup do FOCO.md falhou (exit $codigo): $($saida -join ' ')"
    exit 1
}

if ($Log) { "backup do estado: $($saida -join ' ')" | Out-File -Append -Encoding utf8 $Log }
exit 0
