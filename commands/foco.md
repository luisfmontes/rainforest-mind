---
description: Estado da conversa e do foco ativo, ou declara/troca/conclui foco
argument-hint: [novo foco | trocar <frente> | concluir | vazio para estado]
---

O arquivo de foco é `C:\Projetos\rainforest-mind\FOCO.md`, com as seções
`## Ativo` (um único foco, com critério de pronto e avanços datados),
`## Compromissos com prazo`, `## Frentes` e `## Concluídos`.

Se `$ARGUMENTS` estiver vazio, despeje o estado — neste formato:

1. **Foco ativo:** o que é, critério de pronto, último avanço datado
2. **Compromissos com prazo:** cada um com quantos dias faltam (avisar se
   vencido ou a ≤2 dias)
3. **Estamos em:** o que está sendo feito agora e em que etapa (n/total)
4. **Loops abertos:** perguntas sem resposta, pendências combinadas e não
   executadas, decisões em aberto — uma por linha
5. **Decisões tomadas:** "X, porque Y" — só as desta conversa
6. **Ideias plantadas nesta conversa:** se houver

Se `$ARGUMENTS` for `concluir`: confirme que o critério de pronto foi
atendido (pergunte a evidência se não estiver óbvio), mova o foco ativo para
`## Concluídos` com a data e pergunte qual é o próximo (ofereça os
compromissos com prazo e as frentes como candidatos).

Se `$ARGUMENTS` for `trocar <frente-ou-compromisso>`: preserve o foco atual
(com seus avanços) de volta na lista de origem, promova o alvo a `## Ativo`
e confirme em uma frase. Troca é sem culpa — nada se perde.

Qualquer outro texto: grave-o como novo foco ativo com a data de hoje. Um
foco precisa de **critério de pronto verificável** — se o texto não deixar
claro como saberemos que acabou, pergunte "como saberemos que acabou?" antes
de gravar. Se já havia foco ativo diferente, pergunte se ele volta para
frente/compromisso ou se foi concluído.
