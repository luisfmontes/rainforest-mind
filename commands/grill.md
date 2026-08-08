---
description: Entrevista adversarial — mapeia o plano em árvore de decisão e interroga até não sobrar suposição
argument-hint: [o plano ou decisão a interrogar — vazio usa o que está na mesa]
---

Entreviste o Luís até chegarem a entendimento compartilhado sobre
`$ARGUMENTS` — ou, se vazio, sobre o plano/decisão que já está na mesa nesta
conversa.

Mapeie o assunto como **árvore de decisão**: toda decisão ramifica nas
decisões que dependem dela.

## Rodadas e fronteira

A **fronteira** é o conjunto de decisões cujos pré-requisitos já estão
resolvidos — as perguntas que dá para fazer *agora* sem chutar uma resposta
que você ainda não ouviu. Pergunta cuja resposta depende de outra ainda
aberta pertence a uma rodada **posterior**, não a esta.

Faça a fronteira inteira numa rodada só, numerada, cada pergunta com a sua
resposta recomendada:

```
❓ **Q1 — <título curto>**: <a pergunta, com as alternativas quando houver>
➡️ **Recomendo:** <sua resposta, com o porquê em uma linha>
```

E então **pare e espere**. Ele responde "1 ok, 2 não, usa X" em vez de compor
tudo do zero — a recomendação é o que torna a rodada barata de responder.

Cada rodada de respostas remodela a árvore: decisão fechada empurra a
fronteira para fora e destrava o que dependia dela. Recalcule a fronteira e
faça a rodada seguinte.

## Fato é seu, decisão é dele

Descobrir **fato** é seu trabalho, nunca dele (regra 16). Pergunta da
fronteira que precisa de um fato do ambiente — o que tem no arquivo, a
estrutura da tabela, o que o fonte faz hoje, que versão está instalada, o que
o log diz — vira busca sua, despachada pela regra 10, não pergunta para ele.

E não trave nisso: busca rodando é pré-requisito não resolvido, então só as
perguntas **a jusante dela** esperam — o resto da fronteira vai agora, na
mesma rodada.

O que sobe para ele é **decisão**: o que ele quer, qual caminho, o que entra
no escopo, qual trade-off aceitar. Essas esperam a resposta dele.

## Fim da sessão

Acaba quando a fronteira esvazia: todo ramo visitado, **nada suposto em
silêncio**. Aí resuma o entendimento em poucas linhas e **pare** — não
execute. Só vira trabalho depois de ele confirmar que chegaram ao mesmo
lugar; a regra 5 registra a decisão com o porquê.

Você nunca responde as próprias perguntas. Um grill que responde pelo Luís
deixou de ser grill e virou monólogo com pontos de interrogação.

---

Mecânica de `grilling` e `grill-me` (mattpocock/skills, MIT): árvore de
decisão, fronteira por rodadas, e a partição fato/decisão.
