# Artefatos da esteira

A esteira tem sete estágios — **brainstorm → plano → executar → revisar →
verificar → fechar**, mais **limpar** — e cada um deixa rastro. Este diretório
guarda os três artefatos que **outra pessoa precisa receber** para pegar o
trabalho no meio. Fora do git fica só a tagarelice da execução.

A divisão não é decisão-vs-execução — é **veredito vs. tagarelice**: o veredito
de cada estágio (fechou? com que número?) é a fonte de verdade e viaja com o
repositório; brief, diff e worktree são rastro e morrem com a máquina.

**Todos os caminhos abaixo são relativos à raiz do projeto em que você está
trabalhando** — não a este repositório. Trabalhou num repo de ERP legado, os
documentos nascem lá, ao lado do código que eles descrevem.

| O quê | Onde | No git? | Escrito por |
|---|---|---|---|
| Design aprovado | `<projeto>/docs/rainforest/design/<slug>.md` | **sim** | `brainstorm` |
| Plano de implementação | `<projeto>/docs/rainforest/planos/<slug>.md` | **sim** | `plano` |
| Estado da esteira | `<projeto>/docs/rainforest/estado/<slug>.json` | **sim** | `scripts/estado.cjs` |
| Worktrees do trabalho | `<projeto>/.claude/worktrees/` | não | `executar`, limpos pelo `limpar` |

O **slug** é `AAAA-MM-DD-<tema-em-kebab>` e é o mesmo nas três linhas — é ele
que amarra design, plano e estado ao mesmo trabalho.

### Por que no projeto e não aqui

Existem **dois** tipos de estado, e confundi-los foi um defeito real, pego em
2026-08-11 antes de a esteira rodar em campo:

| | Onde mora | Por quê |
|---|---|---|
| `FOCO.md`, `ideias.jsonl` | cadeia de dados (`RFM_ROOT` > projeto > global > plugin) | são **do usuario** e atravessam projeto: o foco de hoje vale em qualquer pasta |
| design, plano, estado | **sempre o projeto do trabalho** | são **do projeto**: descrevem aquele código e só fazem sentido ao lado dele |

Na primeira versão o estado usava a cadeia de dados, e por isso uma feature de
outro repositório teria o rastro gravado dentro do rainforest-mind — longe do
código, invisível para quem clonasse o projeto, e misturado com o estado de
outra feature de outro repo. O `estado.cjs` resolve por
`CLAUDE_PROJECT_DIR` (ou o diretório de trabalho), e tem teste provando que
`RFM_ROOT` apontando para fora **não** o desvia.

## Por que o estado é versionado

A primeira versão escondia o estado num `.rainforest/estado/` fora do git, com o
argumento de que "rastro de execução não polui o diff". O argumento estava
errado, e caiu com uma pergunta: **o estado existe para o Claude saber como o
fluxo ficou e para outro dev pegar a atividade no meio.** Fora do git, quem
clona o repositório não recebe nada — e a retomada, que é a razão de o arquivo
existir, passa a funcionar só para quem já estava naquela máquina.

É o que o plugin interno de cliente faz: o `gates.json` mora em `docs/plans/`,
junto do design e do plano, e a skill manda ler dele em vez da conversa —
*"não confie em afirmação da conversa: o arquivo é a fonte de verdade"*.

O que **não** entra no git é a outra metade: worktrees, briefs de agente, diffs
de review, log. Isso é conversa de máquina e morre com a máquina — é o que o
`superpowers` mantém git-ignored no workspace dele, e a distinção certa é essa.

O custo é um arquivo JSON de ~40 linhas por trabalho, commitado junto com o
trabalho, não em commit próprio. Barato para o que compra: outra pessoa clona,
roda `proximo --slug <slug>` e sabe exatamente onde parou e por quê.

## Por que design e plano ficam no git

Porque são as duas coisas que alguém vai querer contestar depois: *por que
decidimos assim* e *o que combinamos fazer*. Decisão sem histórico vira decisão
refeita — e refazer decisão fechada é o desperdício que a esteira existe para
cortar.

O design registra **o porquê de cada decisão**, não só o resultado. O plano
registra **o critério de pronto de cada tarefa, falsificável** — comando e saída
esperada, nunca "funcionar bem".

## Retomar um trabalho

```
node scripts/estado.cjs listar                    # o que está em andamento
node scripts/estado.cjs proximo --slug <slug>     # o primeiro estágio aberto
node scripts/estado.cjs ler --slug <slug>         # o estado inteiro
```

O estágio seguinte **recusa** rodar se o anterior não fechou:
`exigir` sai com código 2 e diz o que falta. É comando externo de propósito —
checagem escrita dentro da skill é redigida pelo mesmo agente que ela deveria
barrar, e aí não barra nada.
