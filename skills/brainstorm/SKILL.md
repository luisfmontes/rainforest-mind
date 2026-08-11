---
name: brainstorm
description: Use quando um trabalho novo entra na esteira do rainforest-mind e ainda não tem design aprovado — primeiro estágio, antes de qualquer plano ou código.
---

# Brainstorm

Primeiro estágio da esteira (design → plano → executar → revisar → verificar
→ fechar). É o `/grill` renomeado e promovido: mesmo método, mais o registro de estado
nas duas pontas. O método está inteiro aqui — não se dilui.

## Método

Mapeie o assunto como **árvore de decisão**. A **fronteira** é o conjunto de
decisões cujos pré-requisitos já fecharam — só essas entram na rodada.
Pergunta que depende de outra ainda aberta é de rodada posterior, não desta.

Faça a fronteira inteira numa rodada só, numerada, cada pergunta com a
resposta recomendada:

```
❓ **Q1 — <título curto>**: <a pergunta, com alternativas quando houver>
➡️ **Recomendo:** <sua resposta, com o porquê em uma linha>
```

E então **pare e espere**. Cada rodada de respostas remodela a árvore:
decisão fechada empurra a fronteira para fora — recalcule e faça a rodada
seguinte. Você nunca responde as próprias perguntas.

## Abrir: registre o trabalho antes da primeira rodada

Assim que o assunto tem nome, **antes** de perguntar qualquer coisa:

```
node scripts/estado.cjs iniciar --slug <AAAA-MM-DD-tema-em-kebab> --titulo "<título>"
```

Cedo, não no fim. Brainstorm longo é o caso normal, e trabalho que só aparece
no `listar` depois de fechado é trabalho invisível enquanto está aberto — que é
exatamente o que esta ferramenta existe para evitar. Slug que já existe
(retomada) recusa o `iniciar` com exit 1: siga, o estado já está lá.

Este é o único estágio que **não** abre com `exigir`: `design` não tem
pré-requisito, e `exigir` recusa slug inexistente — é este estágio quem cria o
estado.

## Fato é meu, decisão é dele (regra 16)

Pergunta da fronteira que o ambiente responde — o que tem no arquivo, a
versão instalada, o que o log diz — não sobe para o Luís: vira busca sua,
despachada pela regra 10 quando o custo justificar. Busca rodando não trava a
rodada inteira: só as perguntas a jusante dela esperam, o resto vai na mesma
rodada.

## Fim: fronteira vazia

Acaba quando não sobra ramo — **nada suposto em silêncio**. Aí escreve o
design doc e grava o estado. **Não executa**: vira trabalho só depois de ele
confirmar que chegaram ao mesmo lugar.

### Design doc — `docs/rainforest/design/<slug>.md`

```markdown
# <título>

## Objetivo
<uma ou duas frases>

## Decisões fechadas
- **<decisão>** — porquê: <motivo>
- **<decisão>** — porquê: <motivo>

## Fora de escopo
- <o que ficou de fora e por quê>

## Em aberto
- <o que não fechou — geralmente vazio no fim>
```

### Fechar o estágio

O `iniciar` já rodou lá na abertura. Aqui só se marca:

```
node scripts/estado.cjs marcar --slug <slug> --estagio design --status aprovado --json '{"doc":"docs/rainforest/design/<slug>.md"}'
```

Só depois que ele confirmou o entendimento. Marcar `aprovado` sem a palavra
dele é assinar a aprovação no lugar de quem aprova — e é o que destranca o
`plano`, o `executar` e todo o resto da esteira.

---

Estágio 1 da esteira rainforest-mind. Método adaptado de `grilling`/`grill-me`
(mattpocock/skills, MIT). Chamado por `/brainstorm` — era `/grill` até
2026-08-11.
