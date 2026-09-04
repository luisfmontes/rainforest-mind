# Régua absorve `bar.md` de mecanismos e preflight de renderização

## Objetivo

A skill `regua` já fixa uma régua externa nomeada e roda builder contra crítico
cego. Falta a ela o que faz o crítico **discriminar**: a destilação do que, na
régua, é bom — e a checagem de que os dois lados podem ser postos lado a lado
antes da rodada 1. As duas peças vêm da skill de terceiro `design-loop`, que
resolve a mesma classe de problema e é onde ela é melhor que a nossa.

## Contexto: por que agora

Um colega (JJ) afirmou que o rainforest-mind "consome muito token" e que
precisou mesclá-lo com o `design-loop`. Medido em 2026-09-04:

```
$ node scripts/orcamento.cjs
Hook (additionalContext): 7671 B
Skills (descriptions):    3603 B
Commands (descriptions):  1111 B
Agentes (descriptions):   2040 B
Total: 14425 B    (teto 15.000, exit 0)
```

~4,6k tokens estimados, ~6% de uma abertura de ~68k, contra 40,2k tokens de MCP
medidos com `/context all` em 2026-08-09. A premissa de custo não se sustenta na
injeção — e o `design-loop`, com 3 críticos × 3-4 peças × rodadas sem teto, é
**mais** caro que a `regua`, não menos (ele mesmo diz que o freio real é "você
olhando e parando a run"). Então mesclar não resolve o custo. O que sobrou de
aproveitável são as duas peças acima, e é só isso que este trabalho absorve.

## Decisões fechadas

- **D1 — O `bar.md` é visto só pelo crítico; o builder continua vendo a régua e a
  lacuna única** — porquê: builder que vê a lista de mecanismos otimiza para a
  checklist e vence a comparação sem ficar melhor. O loop passaria a medir a si
  mesmo.

- **D2 — O `bar.md` é arquivo em disco, em `docs/rainforest/reguas/<slug>.md`,
  commitado na rodada 1** — porquê: o crítico é `Agent` novo *toda rodada* e
  precisa receber o mesmo texto em todas. Texto que só existe na conversa não
  sobrevive ao contexto fresco, e reescrevê-lo por rodada muda a régua no meio do
  loop — exatamente o que a skill existe para impedir.

- **D3 — O preflight anuncia sempre e nomeia qual crítico vai cego; só bloqueia
  quando NENHUM dos dois lados renderiza** — porquê: nomear o bloqueio é a regra
  14 aplicada ao loop. Barrar por render parcial mataria o uso mais comum da
  skill (README, mensagem de erro, nome), onde "renderizar" é ler o arquivo.

- **D4 — A calibragem ganha uma rede na Fase 0: régua da qual não se consegue
  extrair 5–7 mecanismos verificáveis reprova antes da rodada 1. A calibragem da
  rodada 1 permanece** — porquê: é o ganho principal da absorção. O abort por
  régua ruim passa a custar 0 rodadas em vez de 1, e as duas redes pegam coisas
  diferentes (uma, régua da qual não se extrai critério; outra, régua da qual se
  extrai critério que não discrimina).

- **D5 — O `bar.md` não altera o veredito binário nem a lacuna única** — porquê:
  o crítico continua devolvendo "A ou B" e uma lacuna localizada. O `bar.md` é
  insumo para ele **enxergar**, não uma rubrica a pontuar; rubrica pontuada é o
  modo de falha que a skill inteira evita ("nota infla a cada rodada").

- **D6 — A atribuição no rodapé da skill passa a nomear as duas fontes** — porquê:
  hoje credita só o `robonuggets/gauntlet-loop`. Reimplementar a partir da
  descrição sem creditar de onde veio o `bar.md` repetiria o que o rodapé já diz
  ser errado.

## Avaliado e descartado

- **Os três críticos ortogonais do `design-loop` (brief / sistema / craft).**
  Triplicam o custo por rodada num trabalho cuja motivação declarada foi custo, e
  o `design-system.md` que o crítico de sistema julgaria não existe neste repo.
- **Mesclar as duas skills num arquivo só.** O `design-loop` não tem nenhum dos
  três freios da Fase 1 (teto como abort, commit por rodada, calibragem) — a
  fusão os diluiria em troca de um padrão que já temos.

## Fora de escopo

- Qualquer mudança no orçamento de token do plugin: a medição acima diz que o
  custo não está aqui. Se o número do JJ contradisser, é outro trabalho, com o
  dado dele na mesa.
- Motor de loop autônomo: continua sendo o `/loop` nativo.

## Em aberto

(vazio)
