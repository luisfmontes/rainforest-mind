---
description: Primeiro estágio da esteira — entrevista adversarial em árvore de decisão, até não sobrar suposição, e grava o design
argument-hint: [o assunto a decidir — vazio usa o que está na mesa]
---

Conduza o estágio **brainstorm** da esteira sobre `$ARGUMENTS` — ou, se vazio,
sobre o plano/decisão que já está na mesa nesta conversa.

Carregue `Skill(brainstorm)` e siga o método de lá: registrar o trabalho no
estado antes da primeira rodada, mapear o assunto como árvore de decisão,
perguntar só a fronteira, uma rodada numerada de cada vez com a resposta
recomendada em cada pergunta — e **parar e esperar**.

Você nunca responde as próprias perguntas. Entrevista que responde pelo Luís
deixou de ser entrevista e virou monólogo com pontos de interrogação.

Descobrir **fato** é seu trabalho, nunca dele (regra 16): pergunta que o
ambiente responde vira busca sua, despachada pela regra 10. O que sobe para ele
é **decisão**.

Acaba quando a fronteira esvazia, com o design escrito em
`docs/rainforest/design/<slug>.md` e o estágio marcado — e aí **para**. Só vira
trabalho depois de ele confirmar que chegaram ao mesmo lugar.

---

Renomeado de `/grill` em 2026-08-11, quando virou o primeiro de sete estágios:
o par `brainstorm` → `plano` diz o que uma palavra sozinha não dizia — que vem
pergunta e que sai plano. É também como o `superpowers` e o plugin interno de cliente
de cliente chamam este mesmo estágio.

Mecânica de `grilling` e `grill-me` (mattpocock/skills, MIT): árvore de
decisão, fronteira por rodadas, e a partição fato/decisão.
