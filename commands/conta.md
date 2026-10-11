---
description: Mostra a conta em uso de cada pasta do Claude Code e troca a pasta de conta na mão
argument-hint: [pessoal | trabalho | preparar pessoal|trabalho]
---

Rode o CLI da troca de conta com os argumentos recebidos:

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/conta.cjs" $ARGUMENTS
```

**Sem argumento** (é o mesmo que `status`): mostra, por pasta, a conta em uso e se ela está em casa; os
percentuais de 5 h e da semana das duas contas; quais reservas de login existem; e se a troca automática está
ligada.

**`pessoal` ou `trabalho`**: troca a pasta `trabalho` (`~/.claude`) para a conta pedida, na hora. O CLI só aceita
o verbo, então o atalho vira `trocar <conta>` no lugar de `$ARGUMENTS`:

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/conta.cjs" trocar pessoal
```

Para mexer na outra pasta, use `trocar <conta> --pasta pessoal`. Troca manual não volta sozinha: a pasta fica
na conta escolhida até a próxima troca manual.

**`preparar pessoal` ou `preparar trabalho`**: abre um login no navegador para a conta pedida e grava a reserva
dela, depois de conferir no servidor que o login é mesmo da conta. Faz-se uma vez por conta. A troca automática
só liga quando as duas reservas existem.

A troca automática e a volta são descritas na seção "Troca automática de conta" do README.
