# Fase 1 — por que o orçamento é abort, não saída

O teto de rodadas **não é a condição de saída** — é o abort. Saída é vencer a
comparação; abort é acabar o orçamento e você olhar o que tem. Confundir os dois
é o que produz "5 rodadas, pronto!" com o trabalho pior que na rodada 2.

O número mora no `## Freios` do manifesto desde a Fase 0, e o conferidor exige a
seção. Declarar o teto de novo na Fase 1 devolveria à conversa o que selá-lo em
disco tirou de lá.

# Por que commit por rodada

A última rodada **não é necessariamente a melhor**. Sem commit por rodada,
voltar para a rodada 3 é impossível e o loop vira um caminho só de ida — e é o
commit de cada rodada que dá ao keep/discard um SHA para guardar em vez de um
diretório que a rodada seguinte sobrescreve.
