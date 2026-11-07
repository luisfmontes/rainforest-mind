# Leitor cego do plano

Detalhe do passo de leitura cega do `## Fechar` do `skills/plano/SKILL.md`. Lá ficam a regra
de quando rodar e o que fazer com os achados; aqui ficam o briefing e o porquê.

## Por que existe

As checagens do `marcar plano ok` são mecânicas: cobertura das `D<n>`, `busca:`, `prova:`,
bloco `mutacao:`. Nenhuma delas pergunta se o executor sabe **o que codar, onde e como**. Quem
escreveu o plano não consegue ler a própria lacuna, porque tem o design e a conversa na cabeça e
preenche sozinho o que falta no texto. O executor é um haiku que recebe só o texto da tarefa e
os arquivos listados. Decisão que o plano deixou em aberto, ele toma sozinho, e toma errado.

O leitor cego nasce sem a conversa e lê o plano na posição do executor.

## Quando

Antes do `marcar plano ok`, sempre que o plano tiver ao menos uma tarefa de tipo `implementar`,
`configurar` ou `teste`, ou sem tipo. Plano só de `docs` e `pesquisar` dispensa: não há
implementador para confundir.

## Despacho

- `subagent_type: "general-purpose"`, com `model: "sonnet"`, em background.
- Sem `isolation`: o leitor não escreve. O briefing proíbe editar e o manifesto declara o
  `general-purpose` como agente que não escreve.
- Sem a linha `Slug:`. O hook de veredito só grava para o tipo `revisor`, mas a linha não tem
  função aqui e não deve existir.
- Commite o plano antes do despacho e não edite o worktree enquanto o leitor roda. Ele lê a
  árvore, e um arquivo que muda no meio da leitura vira achado falso. Na primeira rodada, um
  bump de versão feito em paralelo virou "README sem a versão".
- O briefing leva **só** o que está abaixo. Resumo da conversa, intenção da sessão ou "o que
  eu quis dizer" desfazem a cegueira, e aí o leitor confirma o que você já pensa.

## Briefing

Preencha os três `<...>` e mande o resto como está. A primeira linha, `Contexto: cego`, faz o hook
`memoria-assunto-agente.cjs` não anexar memória de outras sessões nem glossário ao briefing; sem
ela, resumos alheios entram no fim do prompt e o leitor deixa de ser cego. Ela fica sozinha na
linha, exatamente assim.

```
Contexto: cego

Você vai ler um plano de implementação como se fosse implementá-lo, sem nenhum contexto além
dos arquivos abaixo. Não edite nenhum arquivo, não rode comando que escreva e não proponha
código.

Design aprovado: <caminho absoluto do design>
Plano: <caminho absoluto do plano>
Repositório: <caminho absoluto da raiz do worktree do fluxo>

Quem vai implementar cada tarefa é um agente haiku. Ele recebe só o texto daquela tarefa do
plano e pode abrir os arquivos que ela lista em `arquivos:`. Ele não vê a conversa que produziu
o plano e não pode perguntar nada.

Para cada tarefa, pergunte-se: "só com este texto, eu sei exatamente o que codar, em que
arquivo e de que jeito?". Procure:
1. Decisão deixada para quem implementa: assinatura de função, formato de saída, estratégia de
   erro, nome de campo, ordem de operações, o que fazer no caso de borda. O plano tem que dizer;
   se não diz, o executor inventa.
2. Passo vago: "ajustar o hook", "tratar o caso", "atualizar a doc", em vez de "acrescentar X em
   Y no arquivo Z".
3. Tarefa que contradiz o design ou uma decisão `D<n>` que nenhuma tarefa realiza de fato,
   mesmo citada no `atende:`.
4. Critério de pronto que o executor não consegue rodar como está escrito: comando que não
   existe, caminho que não existe no repositório, saída esperada ambígua. Abra o repositório
   para conferir; não suponha.

Para cada achado, dê:
- Grau: bloqueante (o executor vai errar ou parar), maior (vai acertar só por sorte) ou menor
  (atrito sem risco de erro).
- Tarefa: o número da tarefa, ou "plano" se for transversal.
- Achado: o que falta ou está ambíguo, citando o trecho do plano.
- Orientação: o que o plano precisa dizer para o executor não ter de decidir.

Sem achado em algum grau, diga isso. Termine com a linha: leitura completa
```

## Depois da volta

- **Bloqueante e maior:** corrija no plano antes do `marcar ok`. Se um deles não for corrigido,
  o plano ganha uma linha dizendo por quê. Não sobe pergunta ao usuário: editar o plano é
  trabalho do estágio.
- **Menor:** fica a critério da sessão.
- **Achado que muda uma `D<n>` do design** não se resolve no plano. É achado `[design]`: o fluxo
  para e a decisão sobe ao usuário, como a regra 16 manda; fechada a decisão, o design muda e o
  plano é refeito.
- Confira as citações do leitor na fonte antes de agir (regra 12): ele também pode inventar uma
  lacuna que não existe.

Origem: persona `implementation_readiness` do `google/elephant-goldfish-model` (Apache-2.0),
reescrita para o fluxo daqui; o crédito está no design `2026-11-07-leitores-cegos`.
