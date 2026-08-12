---
name: modo-dev
description: Carregue antes de escrever código quando a decisão técnica for pesar — escada YAGNI, causa raiz antes de remendo, rastreabilidade de cada linha do diff até o pedido, expandir–contrair, e o que uma decisão merece de registro. Não é para tarefa mecânica: essa vai direto para o agente da função (regra 10).
---

# Modo Dev

Essência de disciplina de desenvolvimento, sob demanda — comprimida de
plugins e repos que não precisam carregar em toda sessão (ponytail,
superpowers, karpathy, mattpocock; procedência item a item no README).

## Antes de codar

1. **Entender antes de resolver.** Ler o código que a mudança toca, traçar o
   fluxo real de ponta a ponta. Preguiça na solução, nunca na leitura.
2. **Pensar antes de construir.** Pedido criativo/ambíguo → alinhar intenção
   e abordagem com o usuário antes do código (1 pergunta certa > 100 linhas
   erradas).
3. **Plano com verificação por passo.** Tarefa de 3+ etapas declara a rota
   antes de começar, no formato `1. [passo] → verifica: [checagem]`.
   Critério forte deixa o trabalho rodar sozinho até o fim; critério fraco
   ("faz funcionar") obriga a voltar perguntando no meio.

## A cadeia antes do código

Ordem: **`/brainstorm` → design → `plano` → implementar**. Nem
toda tarefa merece os cinco degraus — mesma lógica da escada: **parar no
primeiro degrau que segura**. Os gatilhos:

1. **Brainstorm** — há mais de um caminho plausível e nenhum óbvio, ou o
   pedido é ambíguo. Diverge, não decide: sai com as opções na mesa, não com
   a escolhida.
2. **Design** — a decisão bate as **três** condições de "Qual decisão merece
   registro escrito" (difícil de reverter, surpreendente sem contexto,
   trade-off real). Aí o design **é** esse registro. Ele nasce na **branch de
   trabalho**, nunca na `main` (regra 11 do rainforest-mind).
3. **`/brainstorm`** — interroga o desenho antes de ele virar rota; entra quando o
   design custou decisão de verdade.
4. **Planejamento** — tarefa de 3+ etapas: fatias no formato `1. [passo] →
   verifica: [checagem]`. É o mesmo material que vira critério de sucesso no
   briefing do executor.
5. **Implementar** — despacho com hash de base e critério de sucesso pronto
   (regras 10 a 12).

Pular degrau é legítimo e se diz em uma linha ("sem brainstorm: só um
caminho plausível"). O que não vale é pular calado.

## Despachar: a forma do briefing

O limiar de **quando** despachar é a regra 10 (~3.000 tokens). Aqui está o
**como**. Subagente só enxerga o que o briefing dá; cinco blocos, sempre,
nesta ordem:

1. **Contexto** — o que ele vai mexer e onde mora (caminho, branch, hash de
   base da regra 11).
2. **Objetivos** — numerados e concretos, um por linha.
3. **Restrições** — o que olhar e, explicitamente, o que ignorar.
4. **Formato de saída** — a forma exata que a janela principal quer de volta,
   **e como devolvê-la**. As duas coisas: subagente **anônimo** devolve
   sozinho (o texto final dele é o valor de retorno), mas subagente
   **nomeado** é teammate persistente e só entrega chamando `SendMessage` —
   terminar o trabalho não entrega nada. Nomeou, o briefing manda devolver,
   e diz também que **reportar bloqueio é entrega válida** (ferramenta sem
   credencial, repo que sumiu, rede fechada), com o comando e a saída de
   erro colados. Silêncio não é.
5. **Critério de sucesso** — qual comando rodar, qual saída conta como pronto,
   e qual mutação (revertendo o comportamento real) tem que quebrar qual teste.

O bloco 5 não é enfeite: é o que transforma "terminei" em evidência (regra 12),
e sai pronto do passo 4 da cadeia acima. Briefing vago produz trabalho vago, e
o custo de descobrir isso é uma rodada inteira.

## Despachar: encadear vários

Vários subagentes em sequência não é loop mecânico. A janela principal despacha
um, **lê a saída**, e só então decide o que o próximo é — próxima fatia, passe
de crítica, refação, verificação, ângulo diferente. Cada prompt é composto na
hora com base no que acabou de voltar; não existe template compartilhado nem
número fixo de rodadas.

O teste que separa: **se as chamadas seriam iguais, era pra ser paralelo.** O
que faz a próxima ser diferente da anterior é a leitura da anterior. Tasks
independentes e sem ordem entre si vão juntas, numa mensagem só.

## A escada (parar no primeiro degrau que segura)

1. Precisa existir? Necessidade especulativa = pular, dizer em 1 linha (YAGNI).
2. Já existe neste codebase? Reusar helper/padrão existente.
3. Stdlib resolve? Usar. Plataforma nativa resolve? Usar.
4. Dependência já instalada resolve? Usar. Nunca adicionar nova pro que cabe em poucas linhas.
5. Só então: o mínimo que funciona. Menor diff, sem abstração não pedida,
   sem scaffolding "pra depois".

**Ponto de variação só com dois casos reais.** Uma implementação é costura
hipotética; duas é costura real. Não crie o ponto onde o comportamento
"poderia" variar antes do segundo caso existir de fato.

**Teste da deleção.** Na dúvida se uma camada paga aluguel: imagine apagá-la.
A complexidade some junto? era passa-culpa. Reaparece espalhada em N
chamadores? estava fazendo trabalho de verdade.

**Onde a escada não desce.** Quatro coisas ficam inteiras enquanto todo o
resto encolhe: validação de entrada em fronteira de confiança, tratamento de
erro que evita perda de dados, segurança, e o que o usuário pediu
explicitamente.

**Bug = causa raiz, não sintoma.** Antes de editar, ver todos os callers; a
correção mora onde todos passam, não no caminho que o ticket citou. Bug
difícil (intermitente, sem repro óbvio, regressão de performance) tem
protocolo próprio — ver a skill `depurar`.

## Refactor de raio grande (expandir–contrair)

Mudança mecânica cujo raio de explosão atinge o codebase inteiro — renomear
um campo, trocar o tipo de um símbolo compartilhado — não cabe em fatia
vertical: uma edição só quebra mil chamadores de uma vez e nada fecha verde.
Sequência: **expandir** (a forma nova nasce ao lado da velha, nada quebra) →
**migrar** os chamadores em lotes dimensionados pelo raio (por pasta, por
módulo), cada lote fechando verde porque a forma velha ainda existe →
**contrair** (apagar a velha quando não sobrar chamador). Nunca as três
etapas no mesmo commit.

## Enquanto coda

- **Commit a cada entrega fechada, sempre.** Nunca deixar trabalho sem commit
  na sessão — já houve perda de trabalho por reset de agente (2026-08-06).
- Lógica não-trivial deixa **um** teste/check executável mínimo. Trivial não
  precisa (YAGNI vale pra teste também).
- Estado e resultados intermediários vão para **arquivo** (plano, notas,
  FOCO/IDEIAS), não para o chat — contexto é recurso finito.
- **Toda linha alterada rastreia até o pedido.** Se não dá pra traçar a seta
  de uma linha do diff até o que o usuário pediu, ela não entra. Melhoria de
  código vizinho, reformatação e refactor de carona são diff que ninguém
  pediu — e escondem a mudança real na hora de revisar.
- **Código morto alheio se menciona, não se apaga.** Remova só os órfãos que
  a sua própria mudança deixou sem uso (import, variável, função). O que já
  estava morto antes de você chegar vira uma linha no relatório.

## Antes de dizer "pronto"

- **Evidência antes de afirmação.** Rodar o comando de verificação (lint,
  teste, build) e olhar a saída antes de declarar concluído. Falhou = dizer
  que falhou, com a saída.

## Qual decisão merece registro escrito

As três ao mesmo tempo, senão não escreve: **difícil de reverter** (mudar de
ideia depois custa de verdade), **surpreendente sem o contexto** (quem ler
daqui a seis meses vai perguntar "por que assim?") e **resultado de trade-off
real** (havia alternativa viável e você escolheu por um motivo nomeável).
Faltando uma das três, a linha datada nos Avanços do FOCO.md já basta —
registro que documenta o óbvio vira sedimento e some no meio do que importa.
