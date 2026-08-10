param([Parameter(Mandatory=$true)][string]$Vigia, [switch]$Teste, [string]$Cwd)
# Roda um vigia headless em haiku. Registrado no Agendador de Tarefas do Windows.
$root = if ($env:RFM_ROOT) { $env:RFM_ROOT } else { "C:\Projetos\rainforest-mind" }

# O diretorio de trabalho do claude NAO e a raiz do repositorio por acidente de
# historia: `disabledMcpServers` do .claude.json e por projeto, e neste
# repositorio o whatsapp e o gmail ficam desligados de proposito — aqui se mexe
# no plugin, nao se envia mensagem. Rodando daqui, o vigia herdava esse
# desligamento e ficava sem send_message e sem triagem de inbox, sem nenhum erro
# que dissesse isso (2026-08-10: o init da sessao mostrava `status: disabled`
# enquanto `claude mcp list` dizia Connected). O -Cwd aponta para uma pasta que
# nao esta na lista de desligados. Sem -Cwd, o comportamento antigo.
$cwd = if ($Cwd) { $Cwd } else { $root }
if (-not (Test-Path $cwd)) {
    "- $(Get-Date -Format 'yyyy-MM-dd HH:mm') [$Vigia]: -Cwd nao existe: $cwd" |
      Out-File -Append -Encoding utf8 (Join-Path $root "vigias\ERROS.md")
    exit 1
}
Set-Location $cwd
$promptFile = Join-Path $root "vigias\$Vigia.md"
if (-not (Test-Path $promptFile)) { exit 1 }
# -Encoding UTF8 é obrigatório: sem ele o Get-Content lê o arquivo como ANSI e
# todo acento chega ao modelo como mojibake (Ã§, â€"). Verificado em 2026-08-08.
$prompt = Get-Content -Raw -Encoding UTF8 $promptFile
# Execução manual fora do agendamento. Marcar a mensagem como teste não
# funciona: o envio é uma tool do modelo, e ele ignorou a marca nas duas
# formas tentadas (prefixo no prompt e regra de formato no _comum). Não
# enviar é determinístico — e ainda tira o ruído do grupo.
if ($Teste) {
    $prompt = "EXECUCAO DE TESTE (manual, fora do agendamento): NAO chame send_message nem qualquer tool de envio. Em vez de enviar, escreva no final da sua resposta a mensagem completa que voce enviaria, entre uma linha ---INICIO--- e uma linha ---FIM---. Todo o resto do trabalho (ler as fontes, apurar, decidir) e identico ao normal.`n`n" + $prompt
}

# Dados apurados por script, quando o vigia tiver um. Existe porque instrução
# não conserta aritmética: o jardineiro deu 12, 10, 9 e 11 para o mesmo
# arquivo (10 era o certo) e chegou a somar observação com ideia. O número
# vem contado; ao modelo cabe redigir.
$dadosScript = Join-Path $root "vigias\dados-$Vigia.js"
if (Test-Path $dadosScript) {
    $apurado = (& node $dadosScript 2>&1 | Out-String).Trim()
    if ($apurado) {
        $prompt += "`n`n## Dados apurados agora, direto do arquivo`n`n$apurado`n`nUse ESTES numeros e ESTAS listas. Nao reconte, nao estime, nao complete de memoria: onde o bloco acima e a fonte, ele vence qualquer contagem sua."
    }
}
$log = Join-Path $root "vigias\log-$Vigia.txt"
"=== $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" | Out-File -Append -Encoding utf8 $log

# Pré-checagem do bridge do WhatsApp. Desde 2026-08-07 ele roda NATIVO no Windows
# na porta 3005: a instalação que vivia no WSL (porta 8765) foi removida, então
# acordar o WSL não religa mais nada. A porta 8080 não serve nesta máquina — está
# em faixa reservada do Windows (Hyper-V/WSL) e o bind falha em silêncio.
# Se a porta estiver fechada, sobe o mesmo launcher que a tarefa
# WhatsAppMCPBridge usa no logon.
# Host e porta saem do WHATSAPP_API_BASE_URL (a mesma variável que o MCP e o
# hook já leem), para que trocar de porta valha em um lugar só.
$bridgeUrl = if ($env:WHATSAPP_API_BASE_URL) { $env:WHATSAPP_API_BASE_URL } else { "http://localhost:3005" }
$bridgeHost = ([uri]$bridgeUrl).Host
$bridgePort = ([uri]$bridgeUrl).Port
$bridgeLauncher = if ($env:RFM_BRIDGE_LAUNCHER) { $env:RFM_BRIDGE_LAUNCHER } else { "C:\Projetos\whatsapp-mcp\start-bridge.ps1" }
if (-not (Test-NetConnection $bridgeHost -Port $bridgePort -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    "bridge fora do ar - subindo o launcher nativo" | Out-File -Append -Encoding utf8 $log
    if (Test-Path $bridgeLauncher) {
        Start-Process powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$bridgeLauncher -WindowStyle Hidden
    } else {
        "- $(Get-Date -Format 'yyyy-MM-dd HH:mm') [$Vigia]: launcher nao encontrado em $bridgeLauncher" |
          Out-File -Append -Encoding utf8 (Join-Path $root "vigias\ERROS.md")
        exit 1
    }
    $up = $false
    foreach ($i in 1..12) {
        Start-Sleep -Seconds 5
        if (Test-NetConnection $bridgeHost -Port $bridgePort -InformationLevel Quiet -WarningAction SilentlyContinue) { $up = $true; break }
    }
    if (-not $up) {
        "- $(Get-Date -Format 'yyyy-MM-dd HH:mm') [$Vigia]: bridge nao subiu apos 60s (porta $bridgePort fechada)" |
          Out-File -Append -Encoding utf8 (Join-Path $root "vigias\ERROS.md")
        exit 1
    }
}
# caminho completo: o Agendador de Tarefas não tem o PATH do usuário garantido
$claude = if ($env:RFM_CLAUDE_EXE) { $env:RFM_CLAUDE_EXE } else { "C:\Users\Luis\AppData\Local\Microsoft\WinGet\Packages\Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe\claude.exe" }
# Modelo por vigia. Haiku é o padrão e por ora serve para todos: o mapa fica
# vazio de propósito. Em 2026-08-08 o jardineiro perdeu 3 de 5 rondas e a culpa
# pareceu do modelo — subir para sonnet não mudou nada, porque a causa era a
# entrega do prompt, não a capacidade. Só subir aqui com prova, depois de
# descartar truncamento e encoding.
$modelos = @{}
$modelo = if ($modelos.ContainsKey($Vigia)) { $modelos[$Vigia] } else { 'haiku' }
"modelo: $modelo" | Out-File -Append -Encoding utf8 $log
# Tamanho do prompt no log: a evidencia de entrega vem do harness, nao do
# modelo se auto-reportando. Em 2026-08-08 o jardineiro perdeu 3 de 5 rondas
# e a suspeita caiu no modelo; a causa era o prompt chegando com 1379 de 2717
# caracteres. Numero no log deixa isso visivel sem depender de ninguem.
"prompt: $($prompt.Length) chars" | Out-File -Append -Encoding utf8 $log
# Prompt vai por STDIN, não como argumento: passado em argv ele é cortado no
# meio (o jardineiro chegava com 1379 de 2717 caracteres, perdendo as rondas
# 3 a 5). Passo que some do prompt vira passo que some do relatório.
$prompt | & $claude -p --model $modelo --dangerously-skip-permissions 2>&1 |
  Out-File -Append -Encoding utf8 $log

# O backup do estado fica de fora da execução de teste. O -Teste bloqueava só o
# envio, e este bloco rodava igual: em 2026-08-10 um teste manual levou o
# FOCO.md que o Luís tinha modificado e ainda não commitado para a main, no
# commit 720585f, com a mensagem "Backup diario do estado (sentinela)". Modo de
# teste que escreve no repositório do usuário não é teste — é a ronda de verdade
# com o envio desligado.
if ($Vigia -eq 'sentinela-foco' -and $Teste) {
    "modo teste: backup do estado (git add/commit/push) NAO executado" |
      Out-File -Append -Encoding utf8 $log
}
if ($Vigia -eq 'sentinela-foco' -and -not $Teste) {
    git -C $root add FOCO.md ideias.jsonl vigias/ERROS.md 2>$null
    $staged = git -C $root diff --cached --name-only
    if ($staged) {
        git -C $root commit -m "Backup diario do estado (sentinela)" | Out-File -Append -Encoding utf8 $log
        git -C $root push origin main 2>&1 | Out-File -Append -Encoding utf8 $log
    }
}
