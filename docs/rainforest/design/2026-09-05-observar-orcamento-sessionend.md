# Design: o orçamento do `observar.cjs` cabe no teto real do evento

Fecha a Issue #198.

## Objetivo

Fazer o `scripts/observar.cjs` caber no orçamento que o CLI de fato impõe ao evento
`SessionEnd`, para que ele pare de abortar os hooks irmãos — e deixar esse contrato
**medido por bateria**, não só escrito em comentário.

## O problema

O `timeout` que um hook declara é um **pedido**, não o teto. No shutdown o CLI roda
todos os hooks de `SessionEnd` em paralelo (`Promise.all`) compartilhando um único
`AbortSignal.timeout(i)`, com `i = max(1500, min(maior timeout declarado, 60000))` —
teto duro de 60 s para o evento inteiro, e um failsafe que mata o processo em `i+5s`.
Medido no `claude.exe` 2.1.220 lendo as strings do binário (funções `iz`/`yvr`/`rco`,
constantes `Ees=1500` e `f0E=60000`).

O `observar.cjs` declarava `timeout: 120` e usava `ORCAMENTO_MS = 90000`. Quando ele
consome o orçamento, o sinal aborta e **qualquer hook irmão em voo** devolve
`ABORT_ERR`, que o CLI imprime como `SessionEnd hook [...] failed: Hook cancelled`.

Dano medido: 19 sessões vazadas no `state.json` do `apontamento-horas` entre 06/08 e
26/08 — 19 `SessionEnd` que não terminaram. A vítima visível (`sessionend-hook.ps1`,
0,56 s medido) não era a causa.

## O que a rodada mediu, e que não estava na Issue

1. `observar.cjs` está declarado **duas vezes** no `hooks/hooks.json`, em eventos
   diferentes: `SessionStart` e `SessionEnd`, ambas com `timeout: 120`. As duas não
   se somam (o orçamento é por evento), mas **consertar uma deixa a outra em pé**.
2. **Nenhuma bateria media o valor.** Prova por mutação: trocar `ORCAMENTO_MS` de
   volta para 90000 deixava `testa-observar.sh` inteira verde (38 ok, 0 falha),
   porque todo caso injeta `TESTADOR_ORCAMENTO_MS` e o padrão nunca é exercido.
   Número que nenhum teste lê é número que qualquer edição futura desfaz em
   silêncio — foi assim que ele chegou a 90000.

## Decisões fechadas

- **D1 — `ORCAMENTO_MS` cai de 90000 para 25000.** Porque: precisa caber dentro dos
  60 s compartilhados **com folga para os hooks irmãos**, não encostar no teto. A
  marca d'água avança por fatia, então nada se perde — digere em mais sessões, que é
  preferível a ser morto no meio e levar os irmãos junto.
- **D2 — as duas declarações do `hooks.json` caem de 120 para 30.** Porque: são duas
  e a Issue falava de uma; corrigir só a de `SessionEnd` deixaria `SessionStart`
  declarando 120 s. O valor 30 mantém `ORCAMENTO_MS` (25 s) estritamente menor que o
  timeout declarado, que é a folga da D1.
- **D3 — a bateria passa a ler o NÚMERO declarado, não só o comportamento.** Porque:
  o contrato aqui **é** o número, e a mutação provou que nenhum caso de comportamento
  o enxerga. Três casos novos: orçamento < teto duro; toda declaração do `hooks.json`
  ≤ teto; orçamento < menor timeout declarado.

## Avaliado e descartado

- **Elevar o `timeout` declarado em vez de baixar o orçamento.** Descartado porque
  não funciona: o teto de 60 s é uma constante do CLI (`f0E`), e declarar mais que
  isso não move o `min()`. Foi essa a premissa errada que produziu o 120 original.
- **Deixar o `observar.cjs` sozinho no evento, tirando os irmãos.** Descartado:
  `heartbeat.cjs end` e `memoria-marca.cjs` são justamente os baratos (10 s e 5 s
  declarados) e os que perdem dado quando abortam. Quem tem de caber é o caro.
- **Tornar o orçamento adaptativo (medir a latência e ajustar em tempo de execução).**
  Descartado pelo freio de Pareto: o valor fixo com folga resolve o dano medido, e
  medição em tempo de shutdown é exatamente onde não sobra tempo para medir.

## Fora de escopo

**A versão do plugin NÃO sobe neste PR.** A ideia original pedia bump no mesmo
commit, mas há cinco PRs abertos de outras sessões e um worktree `fluxo/bump-1-6-0`
dedicado a isso. Bump em PR de feature é exatamente a colisão que a #193 documenta
(duas sessões bumparam `0.70.0` e o número deixou de distinguir duas entregas).
Quem bumpa é quem mescla. Isto não está nas decisões fechadas de propósito: é uma
decisão de NÃO fazer, não tem tarefa, e o `cobertura` recusa decisão sem tarefa —
está certo em recusar.

## Em aberto

O `SessionStart` também tem `observar.cjs` dividindo evento com
`foco-session-start.cjs` e `memoria-session-start.cjs`, que não declaram `timeout`
nem `async`. **Se** o startup tiver o mesmo orçamento compartilhado do shutdown, a
mesma inanição atingiria a injeção de abertura — o que se pareceria com o problema
conhecido de injeção truncada. A evidência do binário foi medida no caminho de
shutdown; o de startup **não foi lido**. Fica como hipótese registrada na #198, não
medida aqui. A D2 reduz o risco de qualquer forma, mas não responde a pergunta.
