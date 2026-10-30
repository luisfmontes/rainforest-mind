# O que falsificaria a skill régua

Movido de `skills/regua/SKILL.md`, seção "O que falsificaria esta skill", em 2026-10-30, para abrir folga no teto de 16 KB da skill.

## O que falsificaria esta skill

Três testes baratos, que valem mais que qualquer argumento desta página:

1. Se, em três usos, **todos** saírem na rodada 1 ou 2, a régua está sendo
   escolhida fraca de propósito e a skill virou cerimônia — o remédio é
   apertar a régua, não rodar mais.
2. Se, em três usos, **nenhum** vencer dentro do teto, ou o teto está curto
   demais ou o padrão não paga o custo nesta classe de trabalho — ele sai daqui.
3. Se, em três usos, **toda rodada** der `keep`, o crítico interno não
   discrimina — não há comparação, só chapa. O remédio não é apertá-lo: é
   **cortá-lo inteiramente**. Dois críticos por rodada para nunca reprovar nada
   é cerimônia cara.

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

