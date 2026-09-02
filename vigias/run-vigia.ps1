param([Parameter(Mandatory=$true)][string]$Vigia, [switch]$Teste, [string]$Cwd)
# Roda um vigia headless em haiku. Registrado no Agendador de Tarefas do Windows.
# A raiz sai da localizacao do proprio script, nao de um caminho fixo: este
# repositorio e publico e nenhum caminho desta maquina deve estar nele.
$root = if ($env:RFM_ROOT) { $env:RFM_ROOT } else { Split-Path -Parent $PSScriptRoot }
# O PLUGIN e sempre a pasta acima deste script, mesmo quando $root aponta para a
# pasta de DADOS (RFM_ROOT). Os dois nao sao a mesma coisa desde 2026-08-11.
$plugin = Split-Path -Parent $PSScriptRoot

# A escrita no ERROS.md mora no vigias/erros.ps1, e este dot-source vem ANTES
# de qualquer caminho que possa falhar - inclusive a leitura do toggle, que e
# o primeiro erro possivel da ronda. Ate 2026-09-01 as quatro escritas deste
# arquivo eram quatro copias da mesma linha de Out-File, com os mesmos tres
# defeitos em cada uma (CRLF, mojibake OEM, caminho de maquina em repo
# publico). O porque de cada um esta no cabecalho daquele arquivo.
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
# Uma vez so, e no topo: daqui para baixo TODA saida de processo nativo
# (node, claude) e decodificada como UTF-8. Sem isto ela atravessa o
# codepage OEM do console - que e o que a tarefa agendada usa - e o acento
# chega corrompido ao ERROS.md e ao log. O mojibake que esta commitado no
# ERROS.md desde 27/08 nasceu exatamente aqui.
Set-EncodingDeSaida | Out-Null

# TOGGLE `vigias` — as rondas nascem DESLIGADAS (chave em hooks/lib/config.cjs).
# Quem instala o plugin sem PowerShell agendado, sem claude.exe no caminho e sem
# destino de envio nao pode descobrir essas dependencias por erro em tarefa
# agendada. A pergunta vai para o Node de proposito: reimplementar a cadeia de tres
# niveis (projeto > usuario > padrao) aqui seria a segunda copia da regra, e copia
# mantida a mao diverge calada.
$estado = & node (Join-Path $plugin "scripts\setup.cjs") --ligado vigias 2>$null
if ($LASTEXITCODE -ne 0) {
    # Desligado NAO e erro: sai limpo, sem escrever em ERROS.md. Ja "nao consegui
    # perguntar" e erro, e vai para o log — silencio faria a ronda parar sem rastro.
    if ($estado -eq 'desligado') {
        # SEM travessao dentro de string: o arquivo e UTF-8 sem BOM, o Windows
        # PowerShell 5.1 le como cp1252, e os bytes de `—` terminam em 0x94, que
        # e a aspa tipografica U+201D. O tokenizer aceita aspa tipografica como
        # delimitador: a string FECHAVA no meio e o parse morria com "'}' de
        # fechamento ausente" 20 linhas depois. Nos 10 travessoes que este arquivo
        # ja tinha isso nunca apareceu porque todos estao em COMENTARIO.
        Write-Output "vigias desligado nesta configuracao - nada a fazer. Ligue com: node scripts/setup.cjs --ligar vigias"
        exit 0
    }
    Write-ErroDeVigia -Vigia $Vigia -Plugin $plugin -Motivo "nao consegui ler o toggle 'vigias' (node no PATH?)"
    exit 1
}

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
    Write-ErroDeVigia -Vigia $Vigia -Plugin $plugin -Motivo "-Cwd nao existe: $cwd"
    exit 1
}
Set-Location $cwd

# Configuracao da maquina: destino de envio, launcher do bridge, caminho do
# claude.exe. Mora FORA do repositorio, que e publico — JID de grupo e caminho
# de usuario sao dado pessoal e nao se versionam. Precedencia: variavel de
# ambiente, depois este arquivo. Modelo em vigias/vigia.config.exemplo.json.
$configPath = if ($env:RFM_VIGIA_CONFIG) { $env:RFM_VIGIA_CONFIG } else { Join-Path $cwd "vigia.config.json" }
$cfg = if (Test-Path $configPath) { Get-Content -Raw -Encoding UTF8 $configPath | ConvertFrom-Json } else { $null }
function Get-LocalConfig([string]$Var, [string]$Chave) {
    $v = [Environment]::GetEnvironmentVariable($Var)
    if ($v) { return $v }
    if ($script:cfg -and $script:cfg.$Chave) { return $script:cfg.$Chave }
    return $null
}
# ERRO DE VIGIA VAI PARA O $plugin, NUNCA PARA O $root (Issue #112, 2026-08-26).
# Ate hoje tres escritas usavam $root e uma usava $plugin. Sem RFM_ROOT as
# quatro acertavam o mesmo arquivo por COINCIDENCIA, porque $root cai no
# proprio plugin. Com RFM_ROOT definido elas se partiam: duas listas de erro,
# nenhuma completa, e ninguem avisado.
# O ERROS.md e rastreado neste repositorio e o vigias/dados-batedor-repos.js
# le dele pelo lerLinhasDoPlugin. Ele e registro de falha do PLUGIN, nao dado
# do usuario. Se voce escrever `Join-Path $root "vigias\ERROS.md"` de novo, a
# bateria scripts/testa-erros-md-raiz.sh fica vermelha — de proposito.
function Stop-ComErro([string]$Motivo) {
    Write-ErroDeVigia -Vigia $Vigia -Plugin $plugin -Motivo $Motivo
    exit 1
}

$destino = Get-LocalConfig 'RFM_WHATSAPP_DESTINO' 'destinoWhatsapp'
if (-not $destino) {
    Stop-ComErro "sem destino de envio: defina RFM_WHATSAPP_DESTINO ou destinoWhatsapp em $configPath"
}

$promptFile = Join-Path $root "vigias\$Vigia.md"
if (-not (Test-Path $promptFile)) { exit 1 }
# -Encoding UTF8 é obrigatório: sem ele o Get-Content lê o arquivo como ANSI e
# todo acento chega ao modelo como mojibake (Ã§, â€"). Verificado em 2026-08-08. rf-encoding-exemplo: bytes acima sao exemplo documentado do sintoma, nao mojibake real.
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
# O destino entra no prompt em vez de ficar escrito no _comum.md: e o unico dado
# do arquivo que identifica uma pessoa.
$prompt += "`n`n## Destino de envio`n`nEnvie para o JID ``$destino``. Nao invente destino, nao procure outro chat: e este."

$log = Join-Path $root "vigias\log-$Vigia.txt"
[void](Write-LinhaEmLf -Caminho $log -Linha "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===")
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
$bridgeLauncher = Get-LocalConfig 'RFM_BRIDGE_LAUNCHER' 'bridgeLauncher'
if (-not (Test-NetConnection $bridgeHost -Port $bridgePort -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    [void](Write-LinhaEmLf -Caminho $log -Linha "bridge fora do ar - subindo o launcher nativo")
    if ($bridgeLauncher -and (Test-Path $bridgeLauncher)) {
        Start-Process powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$bridgeLauncher -WindowStyle Hidden
    } else {
        Stop-ComErro "bridge fora do ar e sem launcher: defina RFM_BRIDGE_LAUNCHER ou bridgeLauncher em $configPath (valor atual: '$bridgeLauncher')"
    }
    $up = $false
    foreach ($i in 1..12) {
        Start-Sleep -Seconds 5
        if (Test-NetConnection $bridgeHost -Port $bridgePort -InformationLevel Quiet -WarningAction SilentlyContinue) { $up = $true; break }
    }
    if (-not $up) {
        Write-ErroDeVigia -Vigia $Vigia -Plugin $plugin -Motivo "bridge nao subiu apos 60s (porta $bridgePort fechada)"
        exit 1
    }
}
# O Agendador de Tarefas nao tem o PATH do usuario garantido, entao o caminho
# completo importa — mas ele se descobre, nao se escreve: o caminho do instalador
# muda de maquina e envelhece calado.
$claude = Get-LocalConfig 'RFM_CLAUDE_EXE' 'claudeExe'
if (-not $claude) { $claude = (Get-Command claude -ErrorAction SilentlyContinue).Source }
if (-not $claude) {
    Stop-ComErro "claude.exe nao encontrado: defina RFM_CLAUDE_EXE ou claudeExe em $configPath"
}
# Modelo por vigia. Haiku é o padrão e serve para quase todos. Em 2026-08-08 o
# jardineiro perdeu 3 de 5 rondas e a culpa pareceu do modelo — subir para sonnet
# não mudou nada, porque a causa era a entrega do prompt, não a capacidade. Só
# subir aqui com prova, depois de descartar truncamento e encoding.
#
# 2026-08-20, sentinela-foco: a prova apareceu. Com o gmail já reabilitado no
# comms-vigia, `claude -p --model haiku` achou mcp__gmail-leitura__list_inbox_threads
# pelo ToolSearch, não conseguiu chamar, e inventou duas causas no mesmo turno.
# O MESMO prompt (por STDIN, mesmo -Cwd, mesma sessão não-interativa) com
# --model sonnet voltou com 50 threads reais da inbox. Truncamento e encoding
# estão descartados porque os dois modelos receberam os mesmos bytes pelo mesmo
# caminho — o que muda é atravessar ToolSearch até a chamada da tool diferida.
# Vale só para quem depende de tool MCP diferida: o whatsapp não é diferido, e
# por isso os vigias que só mandam mensagem continuam em haiku.
$modelos = @{
    'sentinela-foco' = 'sonnet'
}
$modelo = if ($modelos.ContainsKey($Vigia)) { $modelos[$Vigia] } else { 'haiku' }
[void](Write-LinhaEmLf -Caminho $log -Linha "modelo: $modelo")
# Tamanho do prompt no log: a evidencia de entrega vem do harness, nao do
# modelo se auto-reportando. Em 2026-08-08 o jardineiro perdeu 3 de 5 rondas
# e a suspeita caiu no modelo; a causa era o prompt chegando com 1379 de 2717
# caracteres. Numero no log deixa isso visivel sem depender de ninguem.
[void](Write-LinhaEmLf -Caminho $log -Linha "prompt: $($prompt.Length) chars")
# Prompt vai por STDIN, não como argumento: passado em argv ele é cortado no
# meio (o jardineiro chegava com 1379 de 2717 caracteres, perdendo as rondas
# 3 a 5). Passo que some do prompt vira passo que some do relatório.
# Linha a linha pelo Write-LinhaEmLf, e nao por Out-File: o log tambem sofria
# CRLF, e no dia em que alguem versionar o log ele quebra a catraca de
# encoding do mesmo jeito que o ERROS.md quebrava.
$prompt | & $claude -p --model $modelo --dangerously-skip-permissions 2>&1 |
  ForEach-Object { [void](Write-LinhaEmLf -Caminho $log -Linha "$_") }

# O backup do estado fica de fora da execução de teste. O -Teste bloqueava só o
# envio, e este bloco rodava igual: em 2026-08-10 um teste manual levou o
# FOCO.md que o usuario tinha modificado e ainda não commitado para a main, no
# commit 720585f, com a mensagem "Backup diario do estado (sentinela)". Modo de
# teste que escreve no repositório do usuário não é teste — é a ronda de verdade
# com o envio desligado.
# O backup do estado saiu deste arquivo em 2026-08-26 (Issue #118) e virou o
# vigias/backup-estado.ps1. Dois motivos, e o segundo e o que importa:
#
# 1. O que estava aqui nao fazia backup. `git -C $root add FOCO.md ideias.jsonl`
#    nao podia funcionar em raiz nenhuma — a pasta de dados nao e repositorio
#    git, e esses dois arquivos nao sao versionados no plugin. O `2>$null`
#    engolia a falha, sobrava o vigias/ERROS.md (que E rastreado aqui), e a
#    tarefa agendada commitava e empurrava sozinha para a `main` de um
#    repositorio PUBLICO: bb77232 (10/08) e 17ba994 (07/08). As tres linhas
#    que sairam eram `git -C $root add ...`, `git -C $root commit -m ...` e
#    `git push origin main`. Elas estao escritas aqui de proposito: a trava
#    de scripts/testa-backup-estado.sh olha linha de EXECUCAO, e o caso que
#    prova isso e justamente este comentario continuar verde.
#
# 2. Enquanto o bloco morava aqui, ele so era alcancavel depois da bridge do
#    WhatsApp, do claude.exe e do toggle — ou seja, prova-lo por execucao
#    exigiria enviar uma mensagem de verdade. Separado, ele roda numa caixa de
#    areia e a bateria executa o artefato em vez de descreve-lo.
# SEM -Root, de proposito (2026-09-01). Passar $root aqui era o defeito: sem
# RFM_ROOT no ambiente, $root e a raiz do PLUGIN, e o foco.cjs precisa da raiz
# de DADOS. O backup-estado.ps1 deixa o foco.cjs resolver pela cadeia canonica;
# o porque completo esta no cabecalho de param() daquele arquivo.
$argsBackup = @('-Vigia', $Vigia, '-Plugin', $plugin, '-Log', $log)
if ($Teste) { $argsBackup += '-Teste' }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $plugin 'vigias\backup-estado.ps1') @argsBackup
