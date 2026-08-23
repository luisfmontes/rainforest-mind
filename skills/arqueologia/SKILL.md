---
name: arqueologia
description: Use antes do `brainstorm` quando a área que a demanda toca é código que ninguém daqui escreveu e ainda não tem mapa. Mapeia a FATIA — nunca a base inteira — e grava em docs/rainforest/mapas/ com escala de confiança. Não gera código.
---

# Arqueologia

Estágio **zero** do fluxo, e **opcional**. O `brainstorm` supõe que já se sabe do
que se está falando. Em código legado essa suposição é falsa, e aí ele fecha
decisão sobre terreno que ninguém viu.

Em projeto novo não há o que mapear — e é por isso que o `estado.cjs` não cobra
esta etapa em lugar nenhum: ela não aparece na retomada e não barra estágio
nenhum. O gatilho é *"a área da demanda não tem mapa"*, nunca *"sempre"*.

Adaptada da skill `arqueologia` de um plugin interno de cliente, escrita pelo mesmo
autor — lá ela é o estágio 1 do fluxo deles, e os quatro mecanismos abaixo
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

## Três passadas sobre o arquivo

**Superfície**: o que o arquivo é — entradas, `#include`, inventário de funções e
suas assinaturas. Lê o topo, escaneia linhas-chave, produz tabela de referência.
Afirmação: `CONFIRMADO` com `arquivo:linha` apontando para `#include` e declaração
de função. Toma minutos.

**Mecanismo**: o que cada bloco de funções faz — entrada, processamento,
saída, erro. Lê corpo da função, traça fluxo de chamadas internas. Afirmação:
`CONFIRMADO` (uma função que chama outra) com `arquivo:linha` de cada chamada.
Regra prática: se o arquivo tem `N` funções, são `N` afirmações, uma por função
descrita. Toma mais tempo que superfície.

**Regra implícita**: que regra de negócio o código encarna, que ninguém escreveu.
Exemplo: "o sistema recusa operação fora do período fiscal" — procure o
`GetSX8Recesso()` ou equivalente no código que confere datas. Afirmação:
`INFERIDO` porque quem escreveu não deixou o porquê, e `LACUNA` porque a regra
não vem claramente de um lugar só. Grava em `## Regras implícitas` dentro do
mapa, sujeita a reconferência. As três passadas rodam em sequência, não em
paralelo — e não rodam todas em um arquivo pequeno: reduza a fatia se ficar
claro que a passada de regra implícita vai render menos que `LACUNA`.

## Triagem antes de ler

Arquivo grande sem índice é trabalho perdido. Antes de abrir: `node scripts/triagem.cjs <arquivo>`
devolve números reais — linhas, funções, densidade e taxa de repetição — e
uma **classe**. Ela para aí: a classe é o que o script conclui, a estratégia de
leitura é o que **você** decide a partir dela.

As três classes, com o corte exato:

| classe | corte | o que a janela costuma fazer |
|---|---|---|
| `dado-como-codigo` | repetição ≥ 60% **ou** densidade ≥ 300 linhas/função | amostragem estrutural: `CONFIRMADO` vale para a amostra, nunca para a totalidade |
| `logica` | repetição < 40% | bloco de funções inteiras: `CONFIRMADO` por função lida |
| `indefinido` | repetição entre 40% e 60% | volta para o usuário — reduza a fatia ou escolha o lado à mão |

Os cortes não são arbitrados. Medidos sobre os 628 fontes de um repositório
Protheus real em 2026-08-22: a repetição tem mediana de 9%, p90 de 36% e p99 de
82%, e as duas famílias se separam sozinhas — os `UPD*` ficam acima de 92%
(`updiag.prw`: 27.992 linhas, 18 funções, 96,7%) e a lógica fica perto de 32%
(`IAG67M12.prw`: 13.692 linhas, 219 funções, 32,3%). Sobram 14 arquivos entre
40% e 60% que não caem limpo em nenhum lado — e é por eles que `indefinido`
existe. Forçar um deles para `dado-como-codigo` faria alguém ler por amostragem
um arquivo que é lógica, e o erro só apareceria no fim do mapa.

"Repetição" aqui é a proporção de linhas não vazias cuja forma normalizada
(literais de string trocados por marcador, espaços colapsados) aparece cinco
vezes ou mais no arquivo.

## Fatia dentro de um arquivo

Arquivo grande se corta por **função ancora**. A âncora escreve-se `.prw#<funcao>` — ou `.tlpp#<funcao>` conforme a extensão:

```
IAG67M12.prw#A67ValidSaldo
```

A faixa de linhas pode ser anotada como referência conferível (ex.: "linhas 1021-1089
na versão de 2026-08-22"), mas **nunca como identidade da fatia**. Razão: a faixa
apodrece no primeiro `#include` que entra no topo. Nome de função sobrevive, e está
sujeito ao mecanismo de conferência: se a função foi renomeada (antiga `A67ValidSaldo`,
nova `ValidarSaldoAgricola`), a segunda passagem da tabela de conferência marca
"a referência mudou, o comportamento não" — nenhum achado, apenas nota.

## Teto de bloco e fragmento em pasta

Um **bloco** (unidade de gravação) não passa de **40.000 caracteres**. A função
ancora só define onde cortar; o tamanho real vai variar por arquivo.

Medido em verdade: `IAG67M12.prw` com 219 funções rende **14 blocos** de
~40KB cada. No mesmo teto, `danfeii.prw` com 321 funções rende **4 blocos**
— a função varia 4x de tamanho entre arquivos, então contar função não funciona.
Em bytes, os dois ficam despacháveis e comparáveis.

Quando a fatia não cabe numa sessão (mapa > 15KB, muito mais de três passadas),
o agente grava cada bloco assim:

```
docs/rainforest/mapas/<fatia>/<bloco>.md
```

A pasta é permanente. O `COBERTURA.md` passa a indexar pasta além de arquivo:

| Fatia | Arquivo | Blocos | Profundidade | Data | Nota |
|---|---|---|---|---|---|
| `iadm-2505-nfe` | `nfesefaz.prw` | 14 | mecanismo + regra | 2026-08-22 | 36 duplicatas marcadas por hash |
| `iadm-2505-nfe` | `danfeii.prw` | 4 | mecanismo | 2026-08-22 | irmaos de `nfesefaz` (hash idêntico) |

Fragmento sem pasta volta ao documento único. Fragmento em pasta, no consolidado
ou na reconferência, se refere por pasta — não por arquivo individual.

## Regras implícitas

Passada que extrai regra de negócio grava em `## Regras implícitas` dentro do
próprio mapa — **não em arquivo `adrs/` separado**. Razão: regra de legado é
quase sempre `INFERIDO` porque quem escreveu não deixou o porquê. Arquivo chamado
`adrs/` dá aparência de **decisão registrada** a uma **inferência** — o avesso
do que a escala de confiança existe para evitar. Dentro do mapa, herda a escala
e fica sujeita a reconferência junto com a afirmação que a originou.

Exemplo de entrada:

```
## Regras implícitas

**Período fiscal fechado barra operação** — lê `GetSX8Recesso()` no topo, confere
se a data está na faixa bloqueada. `INFERIDO`, porque a regra vem do padrão de
entrada da função, não de comentário no código (CONFIRMADO: `nfesefaz.prw#MontaNFe`,
linhas 156-159).
```

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
