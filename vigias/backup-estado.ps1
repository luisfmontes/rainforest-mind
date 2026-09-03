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

# NAO EXISTE MAIS UM -Root AQUI, e a ausencia dele e o conserto (2026-09-01).
# Ate hoje este script recebia -Root e o repassava como `--raiz` para o foco.cjs.
# Quem chamava era o run-vigia.ps1, que calculava a raiz assim:
#   $root = if ($env:RFM_ROOT) { $env:RFM_ROOT } else { Split-Path -Parent $PSScriptRoot }
# `RFM_ROOT` nao esta definida nesta maquina (`printenv RFM_ROOT` sai 1), nem na
# sessao interativa nem na tarefa agendada, entao $root era SEMPRE a raiz do
# repositorio do PLUGIN. E o foco.cjs resolve raiz de DADOS, nao de repositorio:
# o FOCO.md mora em ~/.rainforest, nao no plugin. Resultado: toda ronda de todo
# vigia terminava com `nao achei o FOCO.md em <raiz do plugin>` no ERROS.md,
# desde 27/08 - o dia seguinte ao fechamento da Issue #118, que se chamava
# justamente "O backup diario do sentinela nunca fez backup". A #118 tirou o
# `git push` perigoso e criou este arquivo; o backup nunca chegou a funcionar.
#
# POR QUE NAO PASSAR A RAIZ CERTA, em vez de nao passar nada: o default do
# foco.cjs JA e a cadeia canonica de 4 niveis (hooks/lib/raiz.cjs - RFM_ROOT,
# <projeto>/.rainforest, ~/.rainforest, plugin auto-hospedado). Calcular a raiz
# aqui em PowerShell seria a SEGUNDA copia dessa cadeia, mantida a mao, e copia
# mantida a mao diverge calada - o mesmo argumento que o run-vigia.ps1 ja usa
# para perguntar o toggle ao Node em vez de reimplementar a precedencia.
#
# Efeito colateral bom: a bateria passa a dirigir a caixa por RFM_ROOT, entao
# ela exercita a resolucao DE VERDADE. Antes ela entregava a resposta pronta
# via -Root, e por isso ficava verde enquanto a producao estava quebrada.
param(
    [Parameter(Mandatory=$true)][string]$Vigia,
    [Parameter(Mandatory=$true)][string]$Plugin,
    [string]$Log,
    [switch]$Teste
)

# Quantas copias o rodizio guarda. Numero explicito de proposito: o
# `.ideias-backups` chegou a 293 arquivos por herdar um padrao implicito, que e
# um rodizio que nao roda. 30 cobre um mes de rondas diarias.
$TETO_COPIAS = 30

# A escrita mora no vigias/erros.ps1, dot-sourced aqui e no run-vigia.ps1.
# Ate 2026-09-01 esta funcao era a SEXTA copia da mesma linha de Out-File, e os
# tres defeitos dela (CRLF, mojibake OEM, caminho de maquina em repo publico)
# moravam nas seis ao mesmo tempo. O porque completo de cada um esta no
# cabecalho daquele arquivo.
$libErros = Join-Path $PSScriptRoot 'erros.ps1'
if (-not (Test-Path $libErros)) {
    # Sem a porta de escrita nao ha como REGISTRAR que ela falta: o unico canal
    # honesto que sobra e falar alto e sair diferente de zero, para o
    # LastTaskResult do agendador guardar o sinal. A guarda existe porque a
    # ausencia dela ja mordeu: quando esta porta nasceu, as caixas de areia das
    # baterias nao copiavam o arquivo, o dot-source morria e o script inteiro
    # calava - nenhum erro, nenhuma linha, exit 0 aparente. Morte silenciosa e a
    # classe de defeito que esta entrega inteira existe para fechar.
    [Console]::Error.WriteLine("erro: nao achei o erros.ps1 ao lado de $PSScriptRoot - a ronda nao roda sem a porta de escrita do ERROS.md")
    exit 1
}
. $libErros

function Registrar-Erro([string]$Motivo) {
    Write-ErroDeVigia -Vigia $Vigia -Motivo $Motivo -Plugin $Plugin -Log $Log
}

# ERROS.md e versionado - a ultima linha de um log externo pode carregar caminho
# absoluto com o nome de usuario real (ex.: um "C:\Users\<usuario>\..." qualquer)
# ou crescer sem limite (stack trace, JSON de erro). O caminho absoluto/UNC ja
# e coberto rio abaixo: Registrar-Erro -> Write-ErroDeVigia -> Get-MotivoSaneado
# (vigias/erros.ps1), que substitui `C:\...`, `\\servidor\...` e `..\...\...`
# por `<caminho>` (mantendo so a folha) - CONFERIDO por mutacao: apagar so o
# trecho de troca de caminho aqui nao muda o resultado, porque o saneamento de
# verdade ja acontece na porta unica de escrita. O que falta ali e um TETO de
# tamanho: uma linha de log gigante nao pode inflar o ERROS.md sem limite.
function Truncar-LinhaDeErro([string]$Linha) {
    if ($Linha.Length -gt 200) {
        $Linha = $Linha.Substring(0, 200)
    }
    return $Linha
}

# O -Teste bloqueava so o envio, e o backup rodava igual. Em 2026-08-10 um teste
# manual levou o FOCO.md que o usuario tinha modificado e ainda nao commitado
# para a main. Modo de teste que escreve no repositorio do usuario nao e teste.
if ($Teste) {
    if ($Log) { [void](Write-LinhaEmLf -Caminho $Log -Linha "modo teste: backup do estado NAO executado") }
    exit 0
}

$foco = Join-Path $Plugin "scripts\foco.cjs"
if (-not (Test-Path $foco)) {
    Registrar-Erro "nao achei o scripts/foco.cjs em $Plugin - backup do FOCO.md nao rodou"
    exit 1
}

# Sem `2>$null`: era ele que escondia a falha. Falha de backup fala.
#
# O Set-EncodingDeSaida ANTES do `& node` e o conserto do V4, e a ordem importa:
# o PowerShell decodifica a saida de processo nativo no ato da captura, usando
# [Console]::OutputEncoding. Numa tarefa agendada isso e o codepage OEM, entao
# "nao" saia do node como UTF-8 e chegava aqui ja corrompido - e o ERROS.md
# guarda esse mojibake desde 27/08. Consertar so a ESCRITA nao adiantaria: o
# texto ja teria sido lido errado.
Set-EncodingDeSaida | Out-Null
$saida = & node $foco backup --teto $TETO_COPIAS 2>&1
$codigo = $LASTEXITCODE

if ($codigo -ne 0) {
    Registrar-Erro "backup do FOCO.md falhou (exit $codigo): $($saida -join ' ')"
    exit 1
}

# Backup externo (scripts/backup.cjs gravar) - apos o backup local do FOCO.md
$backup_externo = Join-Path $Plugin "scripts\backup.cjs"
if (Test-Path $backup_externo) {
    Push-Location $Plugin
    $backup_log = & node scripts\backup.cjs gravar 2>&1
    $codigo_externo = $LASTEXITCODE
    Pop-Location

    if ($codigo_externo -ne 0) {
        $ultima_linha = if ($backup_log -is [array]) { $backup_log[-1] } else { $backup_log }
        $ultima_linha = Truncar-LinhaDeErro -Linha $ultima_linha
        Registrar-Erro "backup externo falhou (exit $codigo_externo): $ultima_linha"
    }
}

if ($Log) { [void](Write-LinhaEmLf -Caminho $Log -Linha "backup do estado: $($saida -join ' ')") }
exit 0
