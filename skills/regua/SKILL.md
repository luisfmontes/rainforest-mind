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

Se a tarefa **tem teste**, o teste é a régua e esta skill é overhead puro. Os
quatro casos em que ela não se usa — critério falsificável que você só não
escreveu, tarefa mecânica, diferença que não muda nada para quem recebe
(regra 9), e querer opções em vez de um vencedor (`divergir`) — estão em
`references/quando-nao-usar.md`.

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

### Os mecanismos: selam a régua por construção

Régua nomeada ainda não é régua **útil**. "O README do Stripe" passa nos três
testes acima e mesmo assim não diz nada ao crítico, que responde com o que sobra
quando falta critério: "o B está mais polido".

Antes da rodada 1, leia a régua de verdade e escreva **5 a 7 mecanismos** em
um manifesto único: `docs/rainforest/reguas/<slug>.md`. Este arquivo carrega
as três coisas — qual é a régua, os mecanismos, e uma seção `## Freios` com o
teto de rodadas. Mecanismo é o que alguém **confere olhando** — não adjetivo.
Veja o formato exigido em `references/formato-manifesto.md`.

Quatro pares de exemplo, adjetivo contra mecanismo, estão em
`references/mecanismos-exemplos.md`.

O arquivo é **commitado na rodada 1** e não muda depois. Isso não é
organização: o crítico é `Agent` novo a **toda** rodada, e o que não estiver em
disco não chega nele. É por isso que o teto de rodadas deixou de viver na
conversa e virou item do arquivo — e régua reescrita no meio do loop é régua
trocada no meio do loop, a mesma fraude que trocar o teto.

**Não consegue escrever cinco?** A régua reprovou, e reprovou **de graça**. Essa
é a rede barata: ela custa zero rodada, enquanto a calibragem da Fase 1 custa
uma. As duas ficam, porque pegam coisas diferentes — aqui, régua da qual não se
extrai critério nenhum; lá, régua da qual se extrai critério que não discrimina.

### Crítico cego lerá do commit, pela checagem

O crítico recebe o manifesto pela saída de `node scripts/conferir-regua.cjs
mostrar --slug <slug>`, e é o **único** caminho que imprime o arquivo. Assim
não existe a abertura "pegou o conteúdo sem conferir": a checagem da âncora e
do formato (cinco a sete mecanismos, seção "Freios" presente) roda antes da
impressão, e só imprime se passou. Arquivo lido direto, ou por `git show` por
conta do orquestrador, falseia o mecanismo — o ganho de ter a régua sob controle
do git é **um ponto onde burlar**, em vez de um por rodada e por crítico.

O topo continua procedural — a sessão que orquestra precisa chamar o comando
certo — porque quem orquestra é um LLM. Não é promessa de impossibilidade de
burla; é limite honesto de onde termina a garantia.

### Preflight: quem consegue ver o quê

Uma checagem, não uma pergunta. Roda antes da rodada 1 e reporta em um bloco:

- **A régua abre?** Baixe a página, tire o print, leia o arquivo — agora. Se está
  atrás de login ou sumiu, isso é o teste "Obtível" falhando tarde.
- **O nosso lado renderiza?** Print para site, filmstrip para animação, PDF para
  documento, saída do comando para CLI. Para texto — README, mensagem de erro,
  nome — renderizar é abrir o arquivo, e isso sempre dá.
- **As ferramentas que o trabalho exige respondem?** Geração de imagem, de voz,
  navegador — o que a tarefa precisar.

Então **diga o que falta e qual crítico vai cego por causa disso** — em uma
linha, como manda a regra 14. Seguir calado com um crítico que não enxerga o
artefato produz veredito com a mesma cara de um veredito bom, e ninguém volta a
olhar.

**O primeiro item não é aviso, é parada.** Régua que não abre é o teste
"Obtível" reprovando — só que tarde, na hora de usar em vez da hora de escolher.
Vale o que já valia lá: **não vira loop**, e a escolha da régua volta para o
usuário. Nada do resto do preflight salva um lado que não existe.

Os outros dois itens **anunciam, não barram**. O nosso lado renderizando pela
metade, ou uma ferramenta faltando, segue o loop com o crítico prejudicado
nomeado — barrar por isso mataria o uso mais comum da skill. A única parada que
nasce aqui é o nosso lado não renderizar de jeito nenhum: aí não há o que pôr do
outro lado da comparação, e insistir é queimar rodada.

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

Cada rodada tem três peças: **builder**, **crítico da régua** e **crítico interno**
— nunca no mesmo contexto, e a partir da rodada 2.

**Builder.** Recebe a tarefa e **a lacuna única** que o crítico da régua
apontou — uma, não uma lista. Lista faz o builder espalhar esforço e não fechar
nenhuma. Ele não vê os vereditos anteriores, e **não vê o arquivo de
mecanismos** — vê a régua, o artefato inteiro. Builder com a lista na mão
otimiza para a lista: entrega os sete itens, vence a
comparação e não fica melhor. Aí o loop mede a si mesmo, que é a forma mais cara
de não medir nada.

A partir da rodada 2, o builder parte do **artefato do melhor guardado**
materializado pelo orquestrador através de `git show`, não do último commit. O
melhor guardado é um SHA registrado no log de rodadas versionado,
`docs/rainforest/reguas/<slug>-rodadas.tsv`, com as colunas `rodada`, `commit`,
`venceu_regua`, `venceu_interno`, `status` (em `keep|discard|abortado`) e `lacuna`,
e atualizado pela comparação interna a cada rodada.

**O limite do `git show`: artefato que só existe renderizado.** `git show` devolve
o que está versionado, e isso basta enquanto o artefato é texto — README, mensagem
de erro, código, nome. Quando o que se julga é um render — print de tela,
filmstrip de animação, PDF de documento —, o arquivo renderizado **precisa estar
commitado junto** com a rodada. Sem isso a **comparação interna fica cega**:
seguiria comparando o fonte enquanto o crítico da régua julga a imagem, e os
dois mediriam coisas diferentes sem ninguém perceber. O preflight da Fase 0
pergunta se o nosso lado renderiza; aqui o render precisa **sobreviver à
rodada**, não só existir durante ela.

**Crítico da régua.** `Agent` novo **toda rodada**, nunca `fork`, nunca o mesmo
da rodada anterior. Recebe o nosso artefato e a régua **sem rótulo** e sem saber
qual é qual, sem saber que rodada é — mais o arquivo de mecanismos da Fase 0,
que é o que ele tem para enxergar com. Caminho: `node scripts/conferir-regua.cjs
mostrar --slug <slug>`. Devolve:

1. **Qual venceu** — binário, nosso ou régua. Nunca nota, nunca "empate", nunca
   "os dois têm méritos". Nota infla a cada rodada; binário não.
2. **A lacuna única** — se o vencedor não foi o nosso, a **uma** coisa concreta
   que decidiu. Com localização, igual a achado de `revisar`: "a terceira linha
   força o leitor a contar colunas" é lacuna, "parece menos polido" não é. Essa
   lacuna é a **única** que alimenta o builder da rodada seguinte — nunca vem da
   comparação interna. Senão o loop passa a se perseguir, medindo a si mesmo.

**Crítico interno.** `Agent` novo **toda rodada**, separado e cego como o crítico
da régua. Recebe nosso-novo e nosso-melhor **sem rótulo** e sem saber qual é
mais recente — mais o mesmo arquivo de mecanismos, pelo mesmo comando
`conferir-regua.cjs mostrar`. Devolve **só** o binário: guardar (keep) ou
descartar (discard). Sem lacuna, sem nota, sem progresso.

Despachos separados porque um crítico só, vendo nosso-novo, nosso-melhor e a
régua juntos, identifica pelo parentesco quais dois são nossos — o anonimato cai
ali. Os dois recebem o mesmo manifesto porque crítico sem critério devolve "o B
está mais polido", a falha já nomeada na calibragem da Fase 1.

**Os mecanismos não são uma rubrica.** O crítico não pontua sete itens e soma:
ele continua devolvendo A ou B (régua) ou keep/discard (interno), e **uma** lacuna
(régua só). A lista existe para ele saber onde olhar, não para virar nota — nota
infla a cada rodada, e é por isso que o veredito continua binário.

O crítico ser novo a cada rodada é o mecanismo, não zelo. Quem acompanhou o
loop julga **progresso** ("muito melhor que a rodada 3") em vez de julgar contra
a régua, e aprova cedo por simpatia acumulada — no crítico interno isso vira
"está bom demais pra jogar fora?", o mesmo viés por outra porta.

## Condição de parada

Quatro saídas, não três:

- **Venceu** — o crítico da régua escolheu o nosso. Fim, sem mais uma rodada.
  Mais uma rodada depois de vencer é a regra 9 sendo violada com método.
- **Teto** — acabaram as rodadas declaradas na Fase 1. Você entrega o **melhor
  guardado** do log, materializado via `git show`, com a distância para a régua
  **nomeada em uma linha**. Os commits das rodadas descartadas **permanecem no
  histórico**: o que não avança é o ponteiro. A regra 11 proíbe git destrutivo em
  agente, e poder voltar à rodada 3 depende do commit dela estar lá.
- **Estagnação** — três rodadas seguidas com `discard` do crítico interno. Há
  rodadas sobrando, mas o ponteiro não se moveu em três tentativas, e com dois
  críticos por rodada isso é o investimento deixando de pagar. Distinto do teto:
  teto é "acabaram os recursos", estagnação é "recursos sobraram, tentativas
  pararam".
- **Régua errada** — a calibragem da rodada 1 falhou. Nada foi entregue, e isso
  é resultado, não fracasso: descobrir em uma rodada que a régua não discrimina
  é o barato desta skill.

Esta skill **não é estágio do fluxo** e não aparece no `estado.cjs` — é
invocável sozinha, como `divergir`, `semear` e `arqueologia`. Ela também pode
alimentar o `plano`: a régua vira o critério de aceite da tarefa que não tinha
nenhum, e aí o `verificar` volta a ter o que rodar.

## O que falsificaria esta skill

Três testes baratos e controláveis:

1. Se, em três usos, **todos** saírem na rodada 1 ou 2, a régua está sendo
   escolhida fraca de propósito e a skill virou cerimônia — o remédio é
   apertar a régua, não rodar mais.
2. Se, em três usos, **nenhum** vencer dentro do teto, ou o teto está curto
   demais ou o padrão não paga o custo nesta classe de trabalho — ele sai daqui.
3. Se, em três usos, **toda rodada** der `keep`, o crítico interno não
   discrimina — não há comparação, só chapa. O remédio não é apertá-lo: é
   **cortá-lo inteiramente**. Dois críticos por rodada para nunca reprovar nada
   é cerimônia cara.

Os três testes são baratos e valem mais que qualquer argumento de desenho,
inclusive os desta página.

Três fontes, e todas valem nomear. Padrão adaptado do
`robonuggets/gauntlet-loop`, que enuncia bem a tese central —
trocar rubrica auto-avaliada por comparação cega contra uma referência externa
nomeada — e cataloga com honestidade as formas de quebrá-la. Reimplementado a
partir da descrição, sem copiar arquivo, porque regra deste plugin não depende
de plugin de terceiro. Os três freios da fase 1 (teto de rodadas como abort e
não como saída, commit por rodada, calibragem na rodada 1), o crítico novo a
cada rodada e o teste de falsificação acima são daqui: o original não tem
nenhum, e é por isso que ele só funciona com alguém olhando.

A Fase 0 deve o arquivo de mecanismos e o preflight à skill `design-loop`, que
resolve a mesma classe de problema e acerta nesses dois pontos: destilar a régua
em coisas conferíveis por olho antes de começar, e dizer em voz alta qual crítico
vai cego quando falta o render. O resto dela ficou de fora por medição, não por
gosto — três críticos por rodada, sem teto e sem commit intermediário, custa mais
que este loop inteiro, e o custo era justamente a queixa que trouxe as duas
skills para a mesma mesa (2026-09-04).

A imutabilidade da régua por construção (Fase 0, arquivo em disco com âncora de
git) e o keep/discard automático por comparação interna entre rodadas (Fase 2)
são enxertos do `karpathy/autoresearch`. Dele veio a ideia de decidir
sozinho, a cada iteração, se guarda o trabalho ou descarta. A selagem veio pela
ausência: lá o juiz (`evaluate_bpb`) é protegido só por uma linha de markdown, e
o agente avaliado pode editá-lo — o commit de adição como selo é a resposta
daqui a esse buraco, não uma peça copiada de lá. Dele ficou de fora:
o custo fixo de 5 minutos por tentativa (lá faz `val_bpb` comparável entre
arquiteturas diferentes; aqui a comparabilidade vem do crítico cego vendo os
dois artefatos lado a lado). Reimplementado a partir da descrição, sem copiar
arquivo — o original não está neste repositório, e o padrão não reusa código de
terceiro nesta classe de controle.

## Onde mora o resto

- `references/quando-nao-usar.md` — os quatro casos de overhead puro.
- `references/mecanismos-exemplos.md` — adjetivo contra mecanismo.
- `references/loop-autonomo.md` — largar rodando no `/loop` nativo.
- `references/fronteira-de-honestidade.md` — de onde número pode sair aqui.
