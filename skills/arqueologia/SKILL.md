---
name: arqueologia
description: Use antes do `brainstorm` quando a área que a demanda toca é código que ninguém daqui escreveu e ainda não tem mapa. Mapeia a FATIA — nunca a base inteira — e grava em docs/rainforest/mapas/ com escala de confiança. Não gera código.
---

# Arqueologia

Estágio **zero** da esteira, e **opcional**. O `brainstorm` supõe que já se sabe do
que se está falando. Em código legado essa suposição é falsa, e aí ele fecha
decisão sobre terreno que ninguém viu.

Em projeto novo não há o que mapear — e é por isso que o `estado.cjs` não cobra
esta etapa em lugar nenhum: ela não aparece na retomada e não barra estágio
nenhum. O gatilho é *"a área da demanda não tem mapa"*, nunca *"sempre"*.

Adaptada da skill `arqueologia` de um plugin interno de cliente, escrita pelo mesmo
autor — lá ela é o estágio 1 da esteira deles, e os quatro mecanismos abaixo
vêm de lá.

## O escopo é a fatia, e isso é trava

**Mapeie a fatia que a demanda toca, nunca a base inteira.** Se o mapa que você
está prestes a escrever não cabe numa sessão, o escopo está errado — volte e
reduza antes de ler mais um arquivo.

E esta skill **não gera código e não modifica fonte nenhum**. Ela escreve em
`docs/rainforest/mapas/` e mais nada.

## Toda afirmação sai rotulada

`CONFIRMADO` — leu no fonte, e cita `arquivo:linha`.
`INFERIDO` — convenção, padrão, nome sugestivo. Dito como tal.
`LACUNA` — não sabe e não descobriu. **É resposta boa**, e vale mais que um
`INFERIDO` disfarçado de fato.

É o mesmo vocabulário dos sete agentes, de propósito: mapa e entrega de agente
correm o mesmo risco de virar afirmação confiante sem lastro.

## Fatia já mapeada não é extração — é CONFERÊNCIA

Este é o mecanismo que mais importa, e o único que não existe em nenhum outro
lugar deste repo.

Antes de acrescentar qualquer coisa, olhe `docs/rainforest/mapas/COBERTURA.md`.
Se a fatia já tem linha lá, esta rodada é conferência. Para cada afirmação
marcada `CONFIRMADO`, volte ao `arquivo:linha` de origem e responda uma de três:

| No fonte de hoje | O que fazer |
|---|---|
| continua igual | nada — não regrave a linha |
| a referência mudou, o comportamento não | registre em `## Divergências desta rodada`, com a referência antiga e a nova |
| o comportamento mudou, ou o trecho sumiu | **achado**: divergência com antes, depois e data; a afirmação antiga vai para `## Arquivadas` **com o motivo** |

O porquê: **mapa que ninguém confere envelhece em silêncio**, e o `brainstorm`
trata cada `CONFIRMADO` como restrição do design. Afirmação `CONFIRMADO`
desatualizada é pior que `LACUNA` — porque ninguém desconfia dela.

## O mapa cresce por demanda

`docs/rainforest/mapas/<fatia>.md`, append-only, com `COBERTURA.md` de índice —
o que já foi mapeado, quando, e em que profundidade. Versionado, junto do design
e do plano: mapa é **veredito**, e é por ele que outra pessoa entende o terreno
sem refazer a leitura.

## A leitura é despachada

Ler muitos arquivos e devolver um mapa compacto é o perfil exato da regra 10:
a janela principal não precisa do conteúdo, precisa do mapa. Despache, e escolha
o agente pela função — **não invente agente novo antes de provar que os sete não
cobrem**. O `Explore` nativo acha; ele não mapeia, e a diferença é o artefato.

## Fechar

```
node scripts/estado.cjs marcar --slug <slug> --estagio arqueologia --status ok --json '{"fatia":"...","mapa":"docs/rainforest/mapas/<fatia>.md"}'
```

Olhou e concluiu que não há legado a mapear:

```
node scripts/estado.cjs marcar --slug <slug> --estagio arqueologia --status dispensada --json '{"motivo":"..."}'
```

**Registre `dispensada` em vez de pular.** Silêncio não distingue "não precisa" de
"ninguém olhou", e a próxima sessão não tem como saber qual dos dois foi.

**Condição de parada**: o mapa não cabe numa sessão → o escopo está errado, e a
saída é reduzir a fatia, não ler mais rápido nem resumir mais.
