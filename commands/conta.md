---
description: Mostra a conta em uso de cada pasta do Claude Code e troca a pasta de conta na mão
argument-hint: [pessoal | trabalho [--pasta trabalho|pessoal] | preparar pessoal|trabalho | agendar [--imprimir] | desagendar | unificar [--aplicar] [--profile <arquivo>]]
---

Rode o CLI da troca de conta com os argumentos recebidos:

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/conta.cjs" $ARGUMENTS
```

**Sem argumento** (é o mesmo que `status`): mostra, por pasta, a conta em uso e se ela está em casa; os
percentuais de 5 h e da semana das duas contas; quais reservas de login existem; se a troca automática está
ligada; e os limites em uso.

**`/conta pessoal` ou `/conta trabalho`**: troca a pasta **desta sessão** (a do `CLAUDE_CONFIG_DIR`;
sem ele, `~/.claude`) para a conta pedida, na hora. Para mexer na outra pasta, use `--pasta trabalho` ou
`--pasta pessoal`. `trocar <conta>` continua valendo como sinônimo
(`node "${CLAUDE_PLUGIN_ROOT}/scripts/conta.cjs" trocar pessoal`). Troca manual não volta sozinha: a pasta fica
na conta escolhida até a próxima troca manual.

**`agendar` / `desagendar`**: cria ou remove a tarefa agendada do vigia (a cada 1 minuto). `agendar` só roda depois
que as duas reservas existem; `agendar --imprimir` mostra o comando sem agendar nada.

**`preparar pessoal` ou `preparar trabalho`**: abre um login no navegador para a conta pedida e grava a reserva
dela, depois de conferir no servidor que o login é mesmo da conta. Faz-se uma vez por conta. A troca automática
só liga quando as duas reservas existem (com uma pasta só, basta a reserva da pessoal).

**`unificar`**: junta a pasta pessoal na de trabalho (pasta única). Sem `--aplicar` só relata o que faria. Com
`--aplicar`, migra e renomeia a pessoal para `.claude-personal.aposentada`. `--profile <arquivo>` troca as funções
`claude-pessoal` e `claude-trabalho` do perfil do PowerShell por um `claude` só, com backup `<arquivo>.bak-pasta-unica`.
Recusa se houver `claude` aberto, inclusive dentro de uma sessão: rode-o num terminal sem Claude aberto. O passo a passo está na seção
"Juntar as duas pastas numa só" do README.

A troca automática e a volta são descritas na seção "Troca automática de conta" do README.
