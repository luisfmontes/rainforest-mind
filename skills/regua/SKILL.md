---
name: regua
description: Use quando a tarefa não tem teste e o critério de aceite viraria "está bom" — visual, texto, ergonomia, nome, documentação. Fixa uma régua externa nomeada e roda builder contra crítico cego até vencer a comparação. Não use quando já existe teste: aí o teste é a régua.
---

# Régua

O `verificar` roda o critério que o `plano` escreveu. Isso funciona enquanto o
critério é falsificável: "os 8 casos de `testa-statusline.sh` passam" tem
resposta, e a resposta não depende de quem olha.

Existe uma classe de tarefa em que esse critério não existe. "Deixar a
statusline legível", "escrever o README", "melhorar a mensagem de erro",
"escolher o nome". Aí o critério que sobra é **"está bom"** — e "está bom" é
auto-referente: quem produziu sempre acha que sim, e o revisor que herdou a
narrativa concorda. É o mesmo modo de falha da regra 12, num lugar onde a regra
12 não alcança, porque não há saída real para executar e olhar.

Esta skill troca "está bom" por **"melhor que aquilo ali"** — um artefato
externo, concreto, que existe fora desta conversa e não foi escrito por ninguém
envolvido nela.

## Antes de qualquer coisa: quase sempre a resposta é não

Se a tarefa **tem teste**, o teste é a régua e esta skill é overhead puro. Não
use quando:

- existe um critério falsificável possível e você só não escreveu ainda —
  escreva o critério, é mais barato que um loop;
- a tarefa é mecânica (renomear, mover, corrigir parse) — vá para `plano`;
- a diferença entre "bom" e "ótimo" não muda nada para quem recebe — isso é a
  regra 9, e ela vence esta skill;
- você quer **opções** e não um vencedor — isso é `divergir`.

Use quando errar o acabamento custa a impressão de quem recebe, e você percebe
que não consegue escrever a frase "isto está pronto quando ___".

## Fase 0 — a régua, e o direito de recusar a tarefa

A régua é escolhida **antes** da primeira linha de trabalho, e precisa passar
nos três testes:

| Teste | A pergunta | Reprova quando |
|---|---|---|
| **Nomeada** | que artefato, exatamente? | "as boas práticas", "um README profissional", "algo tipo o do Stripe" |
| **Obtível** | você consegue pôr os dois lado a lado agora? | está atrás de login, é uma lembrança, é um print de qualidade ruim |
| **Comparável** | os dois respondem à mesma pergunta? | comparar um CLI com um site, um README de biblioteca com o de um produto |

Régua que não passa nos três **não vira loop**. A skill para aqui e devolve a
escolha da régua para o usuário — porque régua vaga faz o crítico alucinar a
comparação e aprovar a primeira rodada, que é a falha mais comum deste padrão.

E uma régua **boa demais** é o outro lado da mesma moeda: se o alvo é
inalcançável com o esforço disponível, o loop nunca sai e queima orçamento
parecendo progresso. O teto da fase 1 existe por causa disso.

## Fase 1 — os três freios, declarados antes de largar

O padrão original não tem nenhum destes, e é por isso que ele só funciona com
alguém olhando. Os três se declaram **antes** da rodada 1:

**Teto de rodadas.** Um número. Ele **não é a condição de saída** — é o abort.
Saída é vencer a comparação; abort é acabar o orçamento e você olhar o que tem.
Confundir os dois é o que produz "5 rodadas, pronto!" com o trabalho pior que na
rodada 2.

**Commit por rodada.** Cada rodada fecha com um commit próprio, mensagem
`regua: rodada N — <o que mudou>`. A última rodada **não é necessariamente a
melhor**: sem commit por rodada, voltar para a rodada 3 é impossível e o loop
vira um caminho só de ida.

**Calibragem na rodada 1.** Se o crítico da primeira rodada não conseguir
apontar **uma lacuna específica e fechável**, o problema é a régua, não o
trabalho. Aborte e escolha outra. Crítico que diz "o B está mais polido" na
rodada 1 já provou que não vai discriminar na rodada 7.

## Fase 2 — o loop

Cada rodada tem duas metades, e elas **nunca** rodam no mesmo contexto.

**Builder.** Recebe a tarefa e, a partir da rodada 2, **a lacuna única** que o
crítico apontou — uma, não uma lista. Lista faz o builder espalhar esforço e
não fechar nenhuma. Ele não vê os vereditos anteriores.

**Crítico.** `Agent` novo **toda rodada**, nunca `fork`, nunca o mesmo da rodada
anterior. Recebe os dois artefatos **sem rótulo** e sem saber qual é qual, sem
saber que rodada é, e sem saber que um deles é "nosso". Devolve:

1. **Qual venceu** — binário, A ou B. Nunca nota, nunca "empate", nunca "os dois
   têm méritos". Nota infla a cada rodada; binário não.
2. **A lacuna única** — se o vencedor não foi o nosso, a **uma** coisa concreta
   que decidiu. Com localização, igual a achado de `revisar`: "a terceira linha
   força o leitor a contar colunas" é lacuna, "parece menos polido" não é.

O crítico ser novo a cada rodada é o mecanismo, não zelo. Crítico que
acompanhou o loop julga **progresso** ("muito melhor que a rodada 3") em vez de
julgar contra a régua, e aprova cedo demais por simpatia acumulada.

## Condição de parada

Três saídas, e só três:

- **Venceu** — o crítico cego escolheu o nosso. Fim, sem mais uma rodada. Mais
  uma rodada depois de vencer é a regra 9 sendo violada com método.
- **Teto** — acabaram as rodadas. Você olha os commits, escolhe o melhor, e a
  entrega sai com a distância para a régua **nomeada em uma linha**, não
  escondida.
- **Régua errada** — a calibragem da rodada 1 falhou. Nada foi entregue, e isso
  é resultado, não fracasso: descobrir em uma rodada que a régua não discrimina
  é o barato desta skill.

Esta skill **não é estágio da esteira** e não aparece no `estado.cjs` — é
invocável sozinha, como `divergir`, `semear` e `arqueologia`. Ela também pode
alimentar o `plano`: a régua vira o critério de aceite da tarefa que não tinha
nenhum, e aí o `verificar` volta a ter o que rodar.

## Rodando sozinho, sem babá

O loop longo autônomo é feito com o `/loop` **nativo do Claude Code** — esta
skill não implementa motor nenhum, e não precisa. O que ela adiciona ao `/loop`
é justamente o que falta nele: uma condição de saída que não é "o usuário
mandou parar".

`/loop` sem régua e sem teto é queima de token com aparência de progresso. Com
os dois, é a única configuração em que largar e sair de perto se sustenta.

## O que falsificaria esta skill

Guarde a régua e o número da rodada em que o loop saiu. Se, em três usos,
**todos** saírem na rodada 1 ou 2, a régua está sendo escolhida fraca de
propósito e a skill virou cerimônia — o remédio é apertar a régua, não rodar
mais. Se, em três usos, **nenhum** vencer dentro do teto, ou o teto está curto
demais ou o padrão não paga o custo nesta classe de trabalho, e ele sai daqui.

Os dois testes são baratos e valem mais que qualquer argumento de desenho,
inclusive os desta página.

Padrão adaptado do `robonuggets/gauntlet-loop`, que enuncia bem a tese central —
trocar rubrica auto-avaliada por comparação cega contra uma referência externa
nomeada — e cataloga com honestidade as formas de quebrá-la. Reimplementado a
partir da descrição, sem copiar arquivo, porque regra deste plugin não depende
de plugin de terceiro. Os três freios da fase 1 (teto de rodadas como abort e
não como saída, commit por rodada, calibragem na rodada 1), o crítico novo a
cada rodada e o teste de falsificação acima são daqui: o original não tem
nenhum, e é por isso que ele só funciona com alguém olhando.
