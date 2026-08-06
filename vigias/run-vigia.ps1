param([Parameter(Mandatory=$true)][string]$Vigia)
# Roda um vigia headless em haiku. Registrado no Agendador de Tarefas do Windows.
$root = "C:\Projetos\rainforest-mind"
Set-Location $root
$promptFile = Join-Path $root "vigias\$Vigia.md"
if (-not (Test-Path $promptFile)) { exit 1 }
$prompt = Get-Content -Raw $promptFile
$log = Join-Path $root "vigias\log-$Vigia.txt"
"=== $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" | Out-File -Append -Encoding utf8 $log

# Pré-checagem: o WSL hiberna e derruba o bridge do WhatsApp (porta 8765).
# Acordar o WSL religa o bridge; esperar até 90s pela porta.
if (-not (Test-NetConnection localhost -Port 8765 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    "bridge fora do ar - acordando WSL" | Out-File -Append -Encoding utf8 $log
    wsl -d Ubuntu -e true | Out-Null
    $up = $false
    foreach ($i in 1..18) {
        Start-Sleep -Seconds 5
        if (Test-NetConnection localhost -Port 8765 -InformationLevel Quiet -WarningAction SilentlyContinue) { $up = $true; break }
    }
    if (-not $up) {
        "- $(Get-Date -Format 'yyyy-MM-dd HH:mm') [$Vigia]: bridge nao subiu apos acordar o WSL (porta 8765 fechada)" |
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
