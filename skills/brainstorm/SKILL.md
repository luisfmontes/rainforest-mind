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

**Exceção: delegação explícita prévia.** Se ele disse, antes das perguntas, que
pode seguir como recomendado, a rodada vira design escrito: as respostas
recomendadas entram como decisões, com uma linha por decisão relatando o que
ficou fechado. Só sobe pergunta o que a delegação não cobre (escopo novo, risco
de publicação). Perguntar o que a delegação já fechou devolve a ele o trabalho
que acabou de delegar.

**Exceção: ele pediu para conversar.** Se ele responde a uma decisão com
"precisamos conversar", "quero rever" ou "é cedo para decidir", não é falta de
alternativa na mesa: ele discorda ou desconfia de algo na sua análise. Responda em
prosa curta com **uma** pergunta aberta e pare. Menu numerado serve à fronteira
madura, em que ele sabe o que quer e falta escolher; devolvido nessa hora, fecha a
conversa que ele queria abrir.

### Perguntas obrigatórias da primeira rodada

Três perguntas entram na primeira rodada sempre que o documento ainda não as
responde — a premissa de alvo recalibra todos os riscos, e perguntar custa menos
que reescrever a seção depois:

- **Para QUEM e em que MOMENTO a entrega serve?** Risco, pendência e pergunta a
  terceiro só se escrevem depois de saber, por exemplo, se a carga é inicial em
  base vazia.
- **A rotina nova convive com a existente ou a substitui?** Painel desenhado ao
  lado da tela que devia substituir é o caso típico.
- **Cada valor de um domínio (códigos, status, tipos) sai com o cenário real que
  o produz e a rotina que o grava.** Rótulo sozinho não é proposta, é
  vocabulário seu.

**Quando o design cria selo, trava, gate ou validador**, uma quarta pergunta é
obrigatória: *contra quem isto protege, e o que fica fora?* A resposta vira
decisão `D<n>` do design (o modelo de ameaça), e o briefing do revisor a cita
desde a rodada 1. Sem modelo escrito, cada revisão acha um vetor novo e a
auditoria não converge; com ele, o que ficou fora é critério de parada, não
buraco.

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

## Varredura
docs/rainforest/varredura/<slug>.txt — <o que ela achou, e o que isso mudou>

## Em aberto
- <o que não fechou — geralmente vazio no fim>
```

### Varredura: o que o repositório já sabia

Antes de gravar o design, rode `node scripts/varrer.cjs --slug <slug> <termo>...`
com os termos do tema. Ele consulta Issues e PRs em qualquer estado, branches
remotas, `git log --all --grep` e o `ideias.jsonl`, e grava
`docs/rainforest/varredura/<slug>.txt` com cada comando e a saída. A seção
`## Varredura` cita esse arquivo; `marcar --estagio design` recusa (exit 2) sem
ele, ou com ele vazio. Existe porque um design já reimplementou uma Issue
inteira depois de varrer só a `main` (`varri-so-a-main-e-duplique-feature`).

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

`node scripts/estado.cjs marcar --estagio design --status aprovado` recusa design que não siga o formato acima: seções obrigatórias, decisões marcadas como `**D<n> — ...**` com `n` sequencial de 1, sem buraco e sem repetido. Sem o formato, o comando sai com exit 2.

## Conselho: debate estruturado de decisões (opt-in)

Quando `.rainforest/conselho/` existe no projeto, o design pode convocar o
conselho **antes de marcar aprovado** — um debate estruturado de cada
decisão (`D1`, `D2`, etc.) com três ou mais personas (Codex e Gemini são opcionais):

```
node scripts/conselho.cjs abrir --questao <caminho-da-decisao.md>
node scripts/conselho.cjs pareceres [--membro <nome>]   # (cada persona escreve um parecer; --membro reexecuta só esse)
node scripts/conselho.cjs revisar [--membro <nome>]     # (anônimos avaliam os pareceres alheios; --membro reexecuta só esse)
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
