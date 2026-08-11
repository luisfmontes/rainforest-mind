# Artefatos da esteira

A esteira tem sete estágios — **brainstorm → plano → executar → revisar →
verificar → fechar**, mais **limpar** — e cada um deixa rastro. Este diretório
guarda o rastro que é **decisão**. O que é **execução** fica fora do git.

A divisão não é organizacional, é de diff: decisão precisa de histórico e de
revisão por gente; rastro de execução, não. Misturar os dois faz o `git log`
encher de ruído até ninguém mais ler.

| O quê | Onde | No git? | Escrito por |
|---|---|---|---|
| Design aprovado | `docs/rainforest/design/<slug>.md` | **sim** | `brainstorm` |
| Plano de implementação | `docs/rainforest/planos/<slug>.md` | **sim** | `plano` |
| Estado da esteira | `.rainforest/estado/<slug>.json` | não | `scripts/estado.cjs` |
| Worktrees do trabalho | `.claude/worktrees/` | não | `executar`, limpos pelo `limpar` |

O **slug** é `AAAA-MM-DD-<tema-em-kebab>` e é o mesmo nas três linhas — é ele
que amarra design, plano e estado ao mesmo trabalho.

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
