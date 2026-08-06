---
description: Avalia se a ideia está no escopo e a planta se estiver fora
argument-hint: [ideia em uma frase — vazio para listar plantadas]
---

A fonte da verdade das ideias é `C:\Projetos\rainforest-mind\ideias.jsonl` —
um objeto JSON por linha, com os campos: `id` (kebab-case), `titulo`,
`descricao`, `contexto` (de onde surgiu e por quê), `projeto` (repo/pasta,
ou "solta"), `ao_colher` (primeiro passo, ou null), `status`
("plantada"/"colhida"), `plantada_em`, e para colhidas `colhida_em` +
`resultado`.

Se `$ARGUMENTS` estiver vazio: leia o jsonl e liste as **plantadas** em
markdown legível (título, há quantos dias plantada, projeto, contexto em uma
linha), mais novas primeiro; feche com uma linha resumindo as colhidas.

Se `$ARGUMENTS` tiver texto: avalie se a ideia está dentro do foco declarado
(FOCO.md do repo rainforest-mind).

- **Se estiver no escopo:** confirmar e perguntar: "Isso está no foco — entra
  na tarefa atual ou planto para depois?"
- **Se estiver fora:** plantar — acrescentar UMA linha ao `ideias.jsonl` com
  todos os campos (status "plantada", data de hoje). Se o `projeto` não
  estiver óbvio pelo contexto da conversa, perguntar em uma linha antes de
  gravar. Confirmar: "plantada, de volta a [tarefa]".

Para **colher**: não apagar a linha — reescrevê-la com status "colhida",
`colhida_em` e `resultado`. Colhida ≠ apagada: o histórico fica.
