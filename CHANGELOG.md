# Notas de atualização

O que mudou em cada versão publicada, do ponto de vista de quem **usa** o plugin —
não o log de commits. A versão instalada aparece em `/plugin` → Installed Plugins,
e atualizar é `/plugin` → Browse Plugins → Update Marketplace, depois Update no
`rainforest-mind`.

Este arquivo começa na **1.19.0**. As versões anteriores não têm notas escritas: o
que existe delas é o commit de release (`git log --grep="^Versao "`), e reescrever
29 releases de memória produziria nota bonita e errada. Versão nova daqui em diante
entra aqui no mesmo commit que sobe o `version` do `plugin.json`.

## 1.19.1 — 2026-09-17

**Rota com emoji de status por etapa** (Issue #299).

A regra 4 já mandava fechar cada etapa com "Fechamos [n]/[total]", mas não dizia em
que **formato** acompanhar o todo. Em tarefa longa o checkpoint contava o avanço e
não mostrava o mapa, e a pessoa perdia de vista quantas etapas faltavam e onde
estava. Agora a elaboração da regra 4 traz a rota — uma linha por etapa com marcador
de status — e a `modo-dev` aponta para ela.

Muda o que você vê na resposta; não muda comando, gate nem dado.

## 1.19.0 — 2026-09-17

Cinco issues fechadas, todas de trava que prometia mais do que cumpria.

- **Regra 6 agora diz em que repo "conserta na hora" vale** (#291). A regra mandava
  consertar defeito na hora e não dizia **onde**: o conserto saía no repositório do
  vizinho. Passou a ser explícita — defeito que atrapalha no repo **da sessão**
  conserta na hora; repo alheio é Issue + `Q`, nunca commit.
- **`gate-agente-em-voo` para de repetir o aviso a cada turno** (#298). O gate
  prometia avisar **uma** vez e, em sessão interativa, repetia no turno seguinte.
  A memória era de slot único e duas sessões alternando se sobrescreviam; virou mapa
  por sessão, com assinatura dos agentes em voo.
- **`gate-verificador-staged` volta a respeitar o marcador `dados-de-exemplo`** (#293).
  O marcador era ignorado e o toggle anunciado no cabeçalho do arquivo não existia —
  duas promessas sem implementação.
- **Mutantes de `testa-foco.sh` passam a morrer pelo comportamento certo** (#292).
  Os mutantes dos itens 9 e 13 morriam por `MODULE_NOT_FOUND`, não pela mutação:
  a bateria parecia provar e não provava nada.
- **Achados da revisão do ciclo anterior** (#294): catraca que rodava em cópia, `.pyc`
  no caminho de teste e conversão de caminho do MSYS.

## Antes da 1.19.0

Sem notas escritas. Para ver o que cada release carregou:

```
git log --grep="^Versao " --format="%ad %s" --date=short
```
