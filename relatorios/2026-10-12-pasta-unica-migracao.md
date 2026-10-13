# Migração real para a pasta única (tarefa 5 do fluxo pasta-unica)

Conferida em 2026-10-13 às 08:42, depois do merge do PR #504 e com o plugin
1.63.0 instalado. O `unificar --aplicar` já tinha rodado (pasta aposentada às
08:27); este relatório cola o estado medido depois, contra o "pronto quando" da
tarefa 5. Caminhos da máquina trocados por `~`, e-mail por `<email>`.

## Clone instalado

```
$ git -C ~/.claude/plugins/marketplaces/rainforest-mind log --oneline -1
687a0b2 Versao 1.63.0: uma pasta so de config e conta.cjs unificar (#504)
```

## Pasta pessoal aposentada

```
$ node scripts/conta.cjs unificar
não há pasta pessoal para unificar: nada a fazer
exit=2
$ ls -d ~/.claude-personal*
~/.claude-personal.aposentada
```

`~/.claude-personal` não existe; `~/.claude-personal.aposentada` existe (datada
de 13/10 08:27).

## Sessão sem `CLAUDE_CONFIG_DIR`

```
$ printenv CLAUDE_CONFIG_DIR
(vazio, exit 1)
```

A sessão aberta com `claude` carrega o índice de memória de
`~/.claude/projects/C--Projetos-rainforest-mind/memory/MEMORY.md` (53 linhas),
com as memórias que antes moravam na pasta pessoal.

## Uma pasta só, conta team

```
$ node scripts/conta.cjs
pasta trabalho: conta em uso trabalho (<email>) · em casa · 5 h 2% · semana 57%
contas:
  trabalho: 5 h 2% · semana 57%
  pessoal: 5 h 3% · semana 27%
reservas: trabalho presente · pessoal presente
estacionados: trabalho ausente · pessoal ausente
troca automática: ligada
exit=0
```

## Vigia reagendado do clone instalado

```
$ schtasks /query /tn \ClaudeVigias\troca-de-conta /v /fo list
Hora da próxima execução:  13/10/2026 08:42:00
Horário da última execução: 13/10/2026 08:42:01
Status:                    Pronto
Tarefa a ser executada:    "C:\WINDOWS\System32\conhost.exe" --headless "C:\Program Files\nodejs\node.exe" "~\.claude\plugins\marketplaces\rainforest-mind\scripts\conta.cjs" vigiar
Repetir: a cada:           0 hora(s), 1 minuto(s)
```

## MCPs

```
$ claude mcp list
protheus: https://…/sse (SSE) - ✘ Failed to connect — HTTP 404
github: docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server - ✘ Failed to connect — CONNECTION_CLOSED
```

Os dois aparecem na pasta única, que é o que a tarefa pede (a configuração
migrou). Nenhum dos dois conecta, por causa alheia à migração: o `protheus`
aponta para um túnel ngrok que responde 404, e o `github` depende do Docker.
