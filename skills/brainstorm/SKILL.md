---
name: brainstorm
description: Use quando um trabalho novo entra no fluxo do rainforest-mind e ainda não tem design aprovado — primeiro estágio, antes de qualquer plano ou código.
---

# Brainstorm

Primeiro estágio do fluxo (design → plano → executar → revisar → verificar
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
versão instalada, o que o log diz — não sobe para o usuário: vira busca sua,
despachada pela regra 10 quando o custo justificar. Busca rodando não trava a
rodada inteira: só as perguntas a jusante dela esperam, o resto vai na mesma
rodada.

## Fim: fronteira vazia

Acaba quando não sobra ramo — **nada suposto em silêncio**. Aí escreve o
design doc e grava o estado. **Não executa**: vira trabalho só depois de ele
confirmar que chegaram ao mesmo lugar.

### Design doc — `docs/rainforest/design/<slug>.md`

Caminho relativo à **raiz do projeto em que se trabalha**, nunca à do plugin: o
design descreve aquele código e mora ao lado dele.

```markdown
# <título>

## Objetivo
<uma ou duas frases>

## Decisões fechadas
- **D1 — <decisão>** — porquê: <motivo>
- **D2 — <decisão>** — porquê: <motivo>

## Avaliado e descartado
- <caminho tentado e a medição que o matou>

## Fora de escopo
- <o que ficou de fora e por quê>

## Em aberto
- <o que não fechou — geralmente vazio no fim>
```

### Avaliado e descartado vs. Fora de escopo

As duas seções existem e **são diferentes**:

- **Avaliado e descartado**: caminho que você tentou e mediu — ficou mais lento, mais complexo, menos seguro, ou viola restrição do projeto. Decisão **refutada por evidência**.
- **Fora de escopo**: o que você não vai fazer no projeto, porque o projeto não é sobre aquilo. Decisão **não tomada, porque não é responsabilidade desta entrega**.

A seção "Avaliado e descartado" é distinta porque reduz a chance de a mesma ideia ressurgir na próxima rodada: quando você escreve "tentei compilar in-memory e o tempo subiu 40%", quem ler sabe que não foi esquecimento e sabe por que ficar longe.

### Fechar o estágio

O `iniciar` já rodou lá na abertura. Aqui só se marca:

```
node scripts/estado.cjs marcar --slug <slug> --estagio design --status aprovado --json '{"doc":"docs/rainforest/design/<slug>.md"}'
```

Só depois que ele confirmou o entendimento. Marcar `aprovado` sem a palavra
dele é assinar a aprovação no lugar de quem aprova — e é o que destranca o
`plano`, o `executar` e todo o resto do fluxo.

### Trava de formato

A partir de 2026-08-13, `node scripts/estado.cjs marcar --estagio design --status aprovado` recusa design que não siga o formato acima: seções obrigatórias, decisões marcadas como `**D<n> — ...**` com `n` sequencial de 1, sem buraco e sem repetido. Sem o formato, o comando sai com exit 2.

## Conselho: debate estruturado de decisões (opt-in)

Quando `.rainforest/conselho/` existe no projeto, o design pode convocar o
conselho **antes de marcar aprovado** — um debate estruturado de cada
decisão (`D1`, `D2`, etc.) com três ou mais personas (Codex e Gemini são opcionais):

```
node scripts/conselho.cjs abrir --questao <caminho-da-decisao.md>
node scripts/conselho.cjs pareceres          # (cada persona escreve um parecer)
node scripts/conselho.cjs revisar            # (anônimos avaliam os pareceres alheios)
node scripts/conselho.cjs sintetizar [--unanime]
node scripts/conselho.cjs conferir --fase pareceres|revisao|sintese
```

**Portões** (imperativos; terceira reprovação consecutiva na mesma fase abandona):
- Parecer sem objeções `objecoes >= 1` → reprovado
- Ranking de revisão incompleto ou com empate → reprovado
- Síntese sem `divergencias_nao_resolvidas` (ou `--unanime` explícito) → reprovado

**Opt-in:** sem o diretório, nada muda. Membro ligado indisponível reprova
por falha fechada, nunca silencia — **desligar no `/setup`** se ele não está à
mão.

Membros Claude (`cetico`, `arquiteto`, `usuario-final`) ligados por padrão.
Codex e Gemini desligados; ligar com `node scripts/setup.cjs --ligar conselho-codex`
e `--ligar conselho-gemini` (requerem CLIs autenticados nesta máquina).

---

Estágio 1 do fluxo rainforest-mind. Método adaptado de `grilling`/`grill-me`
(mattpocock/skills, MIT). Chamado por `/brainstorm` — era `/grill` até
2026-08-11.
