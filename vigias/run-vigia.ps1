param([Parameter(Mandatory=$true)][string]$Vigia)
# Roda um vigia headless em haiku. Registrado no Agendador de Tarefas do Windows.
$root = "C:\Projetos\rainforest-mind"
Set-Location $root
$promptFile = Join-Path $root "vigias\$Vigia.md"
if (-not (Test-Path $promptFile)) { exit 1 }
$prompt = Get-Content -Raw $promptFile
$log = Join-Path $root "vigias\log-$Vigia.txt"
"=== $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" | Out-File -Append -Encoding utf8 $log

# Pré-checagem do bridge do WhatsApp. Desde 2026-08-07 ele roda NATIVO no Windows
# na porta 3005: a instalação que vivia no WSL (porta 8765) foi removida, então
# acordar o WSL não religa mais nada. A porta 8080 não serve nesta máquina — está
# em faixa reservada do Windows (Hyper-V/WSL) e o bind falha em silêncio.
# Se a porta estiver fechada, sobe o mesmo launcher que a tarefa
# WhatsAppMCPBridge usa no logon.
$bridgePort = 3005
$bridgeLauncher = "C:\Projetos\whatsapp-mcp\start-bridge.ps1"
if (-not (Test-NetConnection localhost -Port $bridgePort -InformationLevel Quiet -WarningAction SilentlyContinue)) {
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
        if (Test-NetConnection localhost -Port $bridgePort -InformationLevel Quiet -WarningAction SilentlyContinue) { $up = $true; break }
    }
    if (-not $up) {
        "- $(Get-Date -Format 'yyyy-MM-dd HH:mm') [$Vigia]: bridge nao subiu apos 60s (porta $bridgePort fechada)" |
          Out-File -Append -Encoding utf8 (Join-Path $root "vigias\ERROS.md")
        exit 1
    }
}
# caminho completo: o Agendador de Tarefas não tem o PATH do usuário garantido
$claude = "C:\Users\Luis\AppData\Local\Microsoft\WinGet\Packages\Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe\claude.exe"
& $claude -p $prompt --model haiku --dangerously-skip-permissions 2>&1 |
  Out-File -Append -Encoding utf8 $log

if ($Vigia -eq 'sentinela-foco') {
    git -C $root add FOCO.md ideias.jsonl vigias/ERROS.md 2>$null
    $staged = git -C $root diff --cached --name-only
    if ($staged) {
        git -C $root commit -m "Backup diario do estado (sentinela)" | Out-File -Append -Encoding utf8 $log
        git -C $root push origin main 2>&1 | Out-File -Append -Encoding utf8 $log
    }
}
