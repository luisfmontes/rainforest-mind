---
description: Avalia se a ideia está no escopo e a planta se estiver fora
argument-hint: [ideia em uma frase — vazio para listar plantadas]
---

A fonte da verdade das ideias é `C:\Projetos\rainforest-mind\ideias.jsonl` —
um objeto JSON por linha, com os campos: `id` (kebab-case), `titulo`,
`descricao`, `contexto` (de onde surgiu e por quê), `projeto` (repo/pasta,
ou "solta"), `ao_colher` (primeiro passo, ou null), `status`
("plantada"/"colhida"), `plantada_em`, e para colhidas `colhida_em` +
`resultado`. Campo opcional `tipo`: ausente ou `"ideia"` (padrão) para ideia
do Luís; `"observacao"` para as da regra 13 — geradas por correção dele
sobre método, com `ao_colher` = mudança de regra. `/ideia` sem argumento
lista só as ideias; observação é assunto do jardineiro de sexta.

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

**Escrita segura (sessões paralelas).** O Luís roda várias janelas e todas
escrevem neste arquivo. Antes de gravar: reler o arquivo vivo — não confiar
no que foi lido no começo do turno —, acrescentar **só append** de UMA linha,
e conferir depois que a contagem subiu exatamente 1 e que a linha nova é JSON
válido. Colher é a única reescrita permitida, e reescreve **uma** linha,
nunca o arquivo inteiro. Caminho do Windows vai com barra dupla (`C:\\Projetos\\x`):
em 2026-08-07 uma linha gravou `C:\Projetos\rainforest-mind` e o `\r` virou
carriage return dentro do valor — JSON válido, conteúdo corrompido.

Dois detalhes que já quebraram o append (2026-08-08, os dois pegos pela
conferência de contagem): **o arquivo pode não terminar em newline** — grave
o `\n` que falta antes da linha nova, senão ela gruda na última e some do
contador; e **não monte o JSON dentro de aspas do shell** — o escape das
barras se perde no caminho. Escreva a linha num arquivo, valide com
`JSON.parse`, e só então acrescente.
