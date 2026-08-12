---
description: Estágio zero, opcional — mapeia a fatia de código legado que a demanda vai tocar, antes do brainstorm decidir sobre ela
argument-hint: [a fatia: módulo, rotina, tabela ou processo que a demanda toca]
---

Carregue `Skill(arqueologia)` e mapeie `$ARGUMENTS`.

Antes de ler o primeiro arquivo, duas coisas:

1. **Confirme a fatia com o usuário.** Escopo é o que a demanda toca, nunca a base
   inteira — mapa que não cabe numa sessão significa escopo errado, e a saída é
   reduzir, não resumir mais.
2. **Olhe `docs/rainforest/mapas/COBERTURA.md`.** Fatia com linha lá não é
   extração nova: é **conferência**, e o método muda inteiro.

Toda afirmação sai rotulada — `CONFIRMADO` com `arquivo:linha`, `INFERIDO` dito
como tal, `LACUNA` quando não descobriu. `LACUNA` é resposta boa; `INFERIDO`
disfarçado de fato é o defeito que o mapa existe para não ter.

A leitura é despachada (regra 10): a janela precisa do mapa, não do conteúdo.

No fim, marque o estágio — `ok` com o caminho do mapa, ou `dispensada` com o
motivo se não houver legado a mapear. **Registrar `dispensada` importa**: silêncio
não distingue "não precisa" de "ninguém olhou".

Esta skill não gera código e não modifica fonte nenhum.
