# Gate: barrar matar processo por nome (#517)

## Objetivo
Um gate PreToolUse em Bash e PowerShell que barra matar processo por nome — a forma
que, em 2026-10-13, deixou um revisor rodar `taskkill /IM python.exe`, matar 3
processos alheios e derrubar o MCP do WhatsApp. Matar por PID continua livre.

## Decisões fechadas
- **D1 — Vale para subagente e janela principal** — porquê: a regra 15 diz "agente e janela"; o incidente foi de subagente, mas a janela pode repetir o mesmo erro.
- **D2 — Modelo de ameaça: agente descuidado, não adversário** — porquê: o vetor real é o atalho cômodo (`/IM python.exe`), não fuga deliberada. Barra as formas diretas: `taskkill /IM` e `taskkill /FI "IMAGENAME eq …"`; `pkill`; `killall`; `Stop-Process -Name` e os aliases `spps`/`kill -Name`; `Get-Process <nome> | Stop-Process` (e `gps`/`ps` como alias de `Get-Process`); `kill`/`xargs kill` alimentado por `pgrep` ou `pidof` (`kill $(pgrep x)`, `pgrep x | xargs kill`). Desce em `bash -c`, `eval`, `pwsh -Command`, wrappers (`sudo`, `env`, `FOO=1`) pelo mesmo parser do `gate-subagente-sem-instalar`. Fica fora, documentado: `wmic process … delete`, `Invoke-CimMethod … Terminate`, matar de dentro de script (`python -c "os.kill(...)"`, `node -e`) e PID calculado por outro caminho qualquer.
- **D3 — Por PID passa** — porquê: é a forma que a regra 15 prescreve. Passam `taskkill /PID n` (com ou sem `/T /F`), `kill n`, `kill -9 n`, `Stop-Process -Id n`, `Get-Process -Id n | Stop-Process`, e consulta sem matar (`Get-Process node`, `pgrep x`, `tasklist /FI ...`).
- **D4 — Desligamento: toggle `matar-por-nome` (padrão ligado); a janela principal também respeita `RAINFOREST_GATE_OFF`, o subagente nunca** — porquê: quando o usuário pede "mata todos os node", a janela precisa de saída; subagente não decide isso sozinho.
- **D5 — A mensagem de bloqueio ensina a saída por PID** — porquê: o agente bloqueado precisa de caminho honesto: listar (`tasklist /FI "IMAGENAME eq x"`, `Get-Process x`, `pgrep -a x`), conferir que o processo é desta sessão, matar pelo PID. Para a janela, cita também o `RAINFOREST_GATE_OFF`.
- **D6 — Bateria de dois lados com mutação** — porquê: critério de pronto da #517. Sai 2 para cada forma por nome de D2 (inclusive dentro de `bash -c` e `pwsh -Command`), 0 para as formas de D3, 0 com toggle desligado, 0 na janela com `RAINFOREST_GATE_OFF`, 2 no subagente com `RAINFOREST_GATE_OFF`. A mutação que desliga o casamento deixa a bateria vermelha.

## Avaliado e descartado
- Regex sobre o texto cru do comando: o `gate-subagente-sem-instalar` começou assim e deixou passar `bash -c "…"`, `sudo …` e `FOO=1 …` (revisão da zerar-issues-16); por isso o gate novo usa `segmentosParaGate` + `posicaoDeComando`.

## Fora de escopo
- Matar por porta (`fuser -k`, `npx kill-port`, `Get-NetTCPConnection … OwningProcess`): plantado como ideia `gate-matar-por-porta`, com gancho. A forma Windows passa PID via `OwningProcess`, difícil de separar de PID legítimo.
- As formas indiretas listadas em D2 (wmic, CIM, script).

## Varredura
docs/rainforest/varredura/2026-10-14-gate-matar-por-nome.txt — só a própria #517 sobre o tema; nenhum gate, branch ou PR anterior. Os usos de `taskkill`/`Stop-Process` no repo (`hooks/lib/cli-externo.cjs`, baterias) são código interno, não comando da ferramenta Bash, então o gate não os toca. Mudou: confirmou que é gate novo, não extensão.

## Em aberto
