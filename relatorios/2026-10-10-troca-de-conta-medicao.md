# Troca de conta: medição real (tarefa 9)

Fluxo `2026-10-10-troca-de-conta`, medido entre 2026-10-10 23:00 e 2026-10-11 07:30, com as duas contas reais da
máquina: a da organização (team) em `~/.claude` e a pessoal (max) em `~/.claude-personal`. E-mails, ids e tokens
estão mascarados (`<conta-org>`, `<conta-pessoal>`).

## Reservas (D9)

```
$ node scripts/conta.cjs preparar pessoal
Login successful.
reserva de pessoal gravada · falta a reserva de trabalho
$ node scripts/conta.cjs preparar trabalho
Login successful.
reserva de trabalho gravada · troca automática ligada (as duas reservas existem)
```

Os dois logins saíram pela aba que o `claude auth login` abre (callback local); o caminho de colar código não é
usável quando o processo roda sem terminal, e não foi preciso.

## (a) A pasta trocada passa a usar o login que entrou

A medição foi feita na direção que responde à dúvida da organização: pasta `~/.claude` (casa: org) para a conta
pessoal, e volta.

```
$ node scripts/conta.cjs trocar pessoal --pasta trabalho
pasta trabalho: trabalho -> pessoal (manual)
$ CLAUDE_CONFIG_DIR=~/.claude claude auth status
  "email": "<conta-pessoal>",
  "subscriptionType": "max"
$ CLAUDE_CONFIG_DIR=~/.claude claude -p "responda só: ok" --output-format json
result= ok is_error= false
```

Sessão já aberta também troca, sem reiniciar: às 23:22:39, com a pasta trocada, uma sessão de trabalho que já estava
aberta (não as duas `claude -p` acima) fez a atualização horária da política e gravou a política da conta pessoal
(item c). Ela leu o token novo do `.credentials.json` sem reinício.

## (b) Ninguém perdeu a autenticação

```
$ node scripts/conta.cjs trocar trabalho --pasta trabalho
pasta trabalho: pessoal -> trabalho (manual)
$ CLAUDE_CONFIG_DIR=~/.claude claude auth status
  "email": "<conta-org>",
  "subscriptionType": "team"
```

Transcritos de `~/.claude/projects` modificados desde 23:15 (sessões `-p` e as três janelas do projeto Protheus,
ativas até 07:22 do dia seguinte), procurados por `run /login|OAuth token has expired|authentication_error|invalid_grant`:
0 ocorrências em todos. A sessão desta medição, em `~/.claude-personal`, seguiu respondendo do começo ao fim.

## (c) A política da organização NÃO acompanha a pasta

Desvio do plano: em vez de `claude -p --debug`, a prova é o `policy-limits.json`, que o CLI regrava a cada hora
com a política da conta que está no login (o `cc-plugin-sec-default` sai dessa política).

```
antes (22:22:39, login org):        3 restrições em "restrictions"
com a pasta trocada (23:22:39, login pessoal): 1 restrição, a da conta pessoal
```

As restrições da organização caem enquanto a pasta está no login pessoal, e voltam na próxima atualização depois
da volta (de hora em hora, ou numa sessão nova). Levado ao Luís: ele manteve a D1 (a pasta de trabalho pode ir para
a conta pessoal) e fica de conferir que o uso para treino está desligado na conta pessoal.

## (d) Vigia real

```
$ node scripts/conta.cjs agendar
ÊXITO: a tarefa agendada "\ClaudeVigias\troca-de-conta" foi criada corretamente.
vigia agendado: a cada 1 minuto
$ schtasks /Query /TN \ClaudeVigias\troca-de-conta /V /FO LIST
Status:                      Pronto
Hora da próxima execução:    11/10/2026 07:28:00
Horário da última execução:  11/10/2026 07:27:01
Último resultado:            0
```

As aspas do `/TR` passaram no `schtasks` real (a dúvida que a bateria não fechava). A rodada observada não trocou:
nenhuma conta perto dos 97%.

## Estado no fim

```
$ node scripts/conta.cjs status
pasta trabalho: conta em uso trabalho (<conta-org>) · em casa · 5 h 0% · semana 53%
pasta pessoal: conta em uso pessoal (<conta-pessoal>) · em casa · 5 h 2% · semana 14%
reservas: trabalho presente · pessoal presente
troca automática: ligada
```

## Achados que viraram conserto neste fluxo

- `/conta pessoal|trabalho` sem `--pasta` agia sempre na pasta de trabalho; de uma sessão da pasta pessoal,
  `/conta trabalho` respondia "já está". Agora vale a pasta da sessão (`CLAUDE_CONFIG_DIR`), caso (j) de
  `testa-conta.sh`, vermelho com a reversão.
- O vigia roda `conta.cjs` pelo caminho absoluto de onde foi agendado; agendado de um worktree, morre quando ele é
  removido. O `agendar` agora avisa, e o fechamento do fluxo reagenda do clone instalado do plugin.

## (e) Renovação real dos logins guardados (D13, 2026-10-11)

Com o vigia desagendado desde a revisão 1, as duas reservas estavam vencidas desde as 07:17 (horário local), o caso
que a D13 resolve. Uma rodada real do vigia, sem `RFM_TEST`:

```
$ node scripts/conta.cjs vigiar
sem ação
rodada concluída
reserva-pessoal.json  vence +8 h  refresh token girado (sha256 e3813cf874ce -> bb9322a6f78d)
reserva-team.json     vence +8 h  refresh token girado (sha256 045db4039c0f -> aaae07bb3b5c)
```

Nenhum evento `renovacao_falhou`. Depois, `/api/oauth/profile` com o access token novo de cada reserva respondeu a
conta registrada para ela (team e pessoal: confere). O formato da requisição (`POST` JSON em
`platform.claude.com/v1/oauth/token`, `client_id` público do CLI e `scope`) vale no servidor real.
