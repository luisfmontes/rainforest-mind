# Artefatos da esteira

A esteira tem sete estágios — **brainstorm → plano → executar → revisar →
verificar → fechar**, mais **limpar** — e cada um deixa rastro. Este diretório
guarda o rastro que é **decisão**. O que é **execução** fica fora do git.

A divisão não é organizacional, é de diff: decisão precisa de histórico e de
revisão por gente; rastro de execução, não. Misturar os dois faz o `git log`
encher de ruído até ninguém mais ler.

**Todos os caminhos abaixo são relativos à raiz do projeto em que você está
trabalhando** — não a este repositório. Trabalhou num repo de ERP legado, os
documentos nascem lá, ao lado do código que eles descrevem.

| O quê | Onde | No git? | Escrito por |
|---|---|---|---|
| Design aprovado | `<projeto>/docs/rainforest/design/<slug>.md` | **sim** | `brainstorm` |
| Plano de implementação | `<projeto>/docs/rainforest/planos/<slug>.md` | **sim** | `plano` |
| Estado da esteira | `<projeto>/.rainforest/estado/<slug>.json` | não | `scripts/estado.cjs` |
| Worktrees do trabalho | `<projeto>/.claude/worktrees/` | não | `executar`, limpos pelo `limpar` |

O **slug** é `AAAA-MM-DD-<tema-em-kebab>` e é o mesmo nas três linhas — é ele
que amarra design, plano e estado ao mesmo trabalho.

### Por que no projeto e não aqui

Existem **dois** tipos de estado, e confundi-los foi um defeito real, pego em
2026-08-11 antes de a esteira rodar em campo:

| | Onde mora | Por quê |
|---|---|---|
| `FOCO.md`, `ideias.jsonl` | cadeia de dados (`RFM_ROOT` > projeto > global > plugin) | são **do Luís** e atravessam projeto: o foco de hoje vale em qualquer pasta |
| design, plano, estado | **sempre o projeto do trabalho** | são **do projeto**: descrevem aquele código e só fazem sentido ao lado dele |

Na primeira versão o estado usava a cadeia de dados, e por isso uma feature de
outro repositório teria o rastro gravado dentro do rainforest-mind — longe do
código, invisível para quem clonasse o projeto, e misturado com o estado de
outra feature de outro repo. O `estado.cjs` resolve por
`CLAUDE_PROJECT_DIR` (ou o diretório de trabalho), e tem teste provando que
`RFM_ROOT` apontando para fora **não** o desvia.

Ao criar o primeiro trabalho num projeto, o `iniciar` avisa numa linha se
`.rainforest/estado/` ainda não estiver no `.gitignore` daquele repositório —
avisa, não edita: mexer no versionado de um projeto alheio não é papel desta
ferramenta.

## Por que o estado fica fora do git

O `.rainforest/estado/<slug>.json` é máquina de estados, não documento: muda
várias vezes por sessão, e versioná-lo produziria um commit por marcação sem
informação nenhuma para quem lê o histórico depois. O que importa dele — que
decisão foi tomada e o que foi entregue — já está no design, no plano e nos
commits do próprio trabalho.

Ele existe para **retomada**: sessão nova (ou sessão que perdeu contexto na
compactação) roda `node scripts/estado.cjs proximo --slug <slug>` e sabe onde
parou, sem reler a conversa — que é justamente o que a compactação levou.

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
