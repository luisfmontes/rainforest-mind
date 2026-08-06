param([Parameter(Mandatory=$true)][string]$Vigia)
# Roda um vigia headless em haiku. Registrado no Agendador de Tarefas do Windows.
$root = "C:\Projetos\rainforest-mind"
Set-Location $root
$promptFile = Join-Path $root "vigias\$Vigia.md"
if (-not (Test-Path $promptFile)) { exit 1 }
$prompt = Get-Content -Raw $promptFile
$log = Join-Path $root "vigias\log-$Vigia.txt"
"=== $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" | Out-File -Append -Encoding utf8 $log
# caminho completo: o Agendador de Tarefas não tem o PATH do usuário garantido
$claude = "C:\Users\Luis\AppData\Local\Microsoft\WinGet\Packages\Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe\claude.exe"
& $claude -p $prompt --model haiku --dangerously-skip-permissions 2>&1 |
  Out-File -Append -Encoding utf8 $log
