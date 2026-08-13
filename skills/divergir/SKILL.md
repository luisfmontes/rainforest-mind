---
name: divergir
description: Use ANTES do `brainstorm`, quando o espaço de decisão é largo e a primeira ideia já está ancorando a conversa — "qual desses caminhos", nomear, desenhar superfície de API, bug difuso. Dispara N frames isolados em paralelo, depois um crítico separado. Devolve material para decidir; não decide e não gera código.
---

# Divergir

O `brainstorm` **converge**: entrevista adversarial até não sobrar suposição.
Ele supõe que já existe um caminho na mesa. Quando o espaço é largo e ninguém
listou as opções, ele estreita cedo — em cima da primeira ideia, que ganhou não
por ser boa e sim por ter chegado primeiro.

Esta skill é o passo anterior, e existe por um motivo que é **arquitetural, não
de prompt**: pedir "me dê 5 alternativas" numa janela só produz 5 variações
ancoradas na primeira, porque todas nascem no mesmo contexto. Frames isolados
não se veem, então não se ancoram.

## Antes de qualquer coisa: isto é caro

São **N+1 despachos** para uma pergunta que ainda não é trabalho. Não use quando:

- já existe um caminho óbvio e o que falta é executá-lo — vá para `plano`;
- o pedido é de execução, não de escolha;
- a decisão é reversível e barata (nome de variável interna, ordem de campo):
  divergir custa mais que errar e trocar;
- você já tem 2 caminhos claros e quer escolher entre eles — isso é `brainstorm`,
  que é mais barato e interativo.

Use quando errar a escolha custa reescrever, e quando você percebe que está
defendendo a primeira ideia em vez de comparando.

## Fase 1 — divergir, sem ninguém se ver

`Agent` em paralelo, **um por frame**, todos com o MESMO enunciado do problema
e **contexto zero entre si**. Nenhum recebe a saída de outro; nenhum é nomeado.
Use `rainforest-mind:planejador` (sonnet, devolve abordagem e nunca código, e
já rotula `CONFIRMADO`/`INFERIDO`/`LACUNA`).

O isolamento **é** o mecanismo. Se os frames rodarem em sequência na mesma
janela, ou se um vir o resultado do outro, a skill não faz nada que um prompt
comum já não faça — e aí não vale o custo.

Seis frames, escolhidos para serem ortogonais e não sinônimos:

| Frame | A pergunta que ele faz |
|---|---|
| `restricao-dura` | e se o recurso mais caro (tempo, memória, atenção do usuário, dinheiro, tokens) fosse **10× menor**? |
| `inversao` | e se a responsabilidade morasse do **outro lado da fronteira** — no chamador, no dado, no usuário, no sistema operacional? |
| `incentivo` | quem ganha e quem perde com cada caminho, e que comportamento o desenho **premia sem querer**? |
| `ja-existe` | que peça pronta (deste repo, do host, do SO, do protocolo) resolve isso **sem código novo**? "Não construa" é resposta legítima |
| `modo-de-falha` | comece pelo desastre e volte: que desenho torna aquele desastre **impossível** em vez de improvável? |
| `premissa` | o problema como foi **enunciado** está certo? Ataque o pedido, não a solução |

O `premissa` não vem do original e é o mais importante em repositório com
história: é a regra 16 aplicada à ideação — enunciado errado produz seis boas
respostas para a pergunta errada, e nenhum dos outros cinco frames tem
permissão para notar isso.

Cada frame devolve **ideias com o porquê**, nunca uma só. Frame que devolve uma
ideia não divergiu, opinou.

## Fase 2 — focar, por um crítico que também nasce zerado

Um `Agent` novo, **nunca `fork`** de nenhum dos frames e nunca da janela que
despachou: quem herda a narrativa de quem gerou valida a narrativa. Ele recebe
todas as ideias **sem saber de que frame veio cada uma** e devolve:

1. **Agrupamento** — ideias que são a mesma coisa com nome diferente colapsam.
2. **Refutação do sedutor-mas-quebrado** — a ideia que soa ótima e falha na
   primeira semana, com **uma linha** dizendo onde quebra. Refutação exige
   cenário concreto de falha (entrada, estado, sequência), igual a achado de
   `revisar`: "eu faria diferente" não refuta nada.
3. **Shortlist** com o critério explícito de corte.
4. **A escolha não-óbvia** — o caminho que sobreviveu e que ninguém teria
   proposto de primeira, com o porquê. Se a escolha não-óbvia for igual à
   primeira ideia da conversa, **diga isso**: é o resultado mais valioso da
   rodada, porque significa que a ancoragem não custou nada desta vez.

## Condição de parada

Esta skill **não decide e não escreve código**. Ela entrega o material, e a
decisão é do usuário (regra 16) — apresentada como decisão numerada, com
recomendada. Fechada a escolha, o `brainstorm` converge em cima dela e grava o
design; a esteira segue dali.

Ela também **não é estágio da esteira** e não aparece no `estado.cjs`: é
invocável sozinha, a qualquer momento, como `semear` e `arqueologia`. Amarrar
um oitavo estágio numa esteira de sete, para um mecanismo que ainda não provou
mudar decisão nenhuma, é caro na hora errada.

## O que falsificaria esta skill

Rode-a numa decisão real e guarde a escolha. Se, em três rodadas, a escolha
final for sempre a mesma que você teria feito sem divergir, **a skill não paga
o custo e sai** — o problema é que a ancoragem não estava custando nada, e o
remédio não tinha doença. Esse teste é barato e vale mais que qualquer
argumento de desenho, inclusive os desta página.

Contrato adaptado do `UditAkhourii/adhd`, que enuncia bem a tese ("tree-of-thought
widens search but walks a single shared context, so anchoring persists across
branches — an architectural problem, not a prompting one"). Reimplementado a
partir da descrição, sem copiar código, porque regra deste plugin não depende de
plugin de terceiro — quem instalar o original pode usá-lo como conferência,
nunca como requisito. O frame `premissa`, a exigência de cenário concreto na
refutação e o teste de falsificação acima são daqui.
