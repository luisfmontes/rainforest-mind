# Validar a ponte Codex ao vivo com o plugin 1.8.0 instalado

Data: 2026-09-08. Origem: ideia plantada no fechamento do PR #222.

## Objetivo

Ver a ponte Codex funcionar pelo caminho que o usuário vai usar, sem atalho,
e fechar o caso "Codex sem cota" de forma legível. A tarefa 8 do fluxo
`agentes-em-codex` provou o mecanismo por dois atalhos honestos: o preâmbulo
`<!-- ponte-codex -->` foi colado no briefing (o plugin instalado era 1.7.0,
sem preâmbulo) e a linha `"runtime":"codex"` veio da portaria da branch rodada
à mão (a portaria viva era a do checkout principal). Com o 1.8.0 instalado,
os dois atalhos saem.

## Decisões fechadas

- **D1 — O que se prova.** Três coisas, cada uma com saída literal: (a) o
  agente `executor` do cache 1.8.0 lê o **próprio** preâmbulo e age como
  ponte, sem instrução extra no briefing; (b) a portaria viva grava
  `"runtime":"codex"` na linha `allow` do `despachos.jsonl`; (c) o commit do
  que o Codex deixou é feito pela ponte, no worktree do agente.
- **D2 — Briefing mínimo.** Só `Runtime: codex`; a linha `Despacho:` **não**
  entra: o script tem de ser achado por `$CLAUDE_PLUGIN_ROOT` ou pela raiz do
  repositório (o worktree do agente nasce da `origin/main`, que já tem o
  script). Se a ponte não achar o script, isso é achado, não ajuste.
- **D3 — Tarefa do Codex é trivial e descartável.** Criar um arquivo em
  `docs/rainforest/relatorios/` com conteúdo fixo. O worktree do agente é
  removido no `fechar`; o que fica é a evidência colada no relatório da T8.
- **D4 — Falha vira achado no repo.** Se (a), (b) ou (c) falhar, o defeito é
  do que já está na `main`: corrige-se nesta branch, com bateria, e o
  relatório registra. Sem Issue para erro deste trabalho; Issue só para
  defeito alheio à ponte (regra do usuário, 2026-09-08).
- **D5 — Codex sem cota falha fechado e legível.** Pedido do usuário em
  2026-09-08, com o limite de 5 h estourado naquele instante. Medido na hora:
  `codex exec` sai **1**, não cria o `-o`, e escreve no stderr
  `ERROR: You've hit your usage limit ... try again at 5:41 PM`;
  `despachar-codex.cjs` propaga exit 1 com stdout vazio e o stderr do Codex
  colado depois da linha `comando:`. Fechado já está (exit ≠ 0 é bloqueio
  para a ponte e para o gate). Legível ainda não: a causa fica na 12ª linha
  do stderr, atrás do banner do Codex, e o gate diria só "falha fechada —
  exit 1". O script passa a reconhecer a mensagem de cota e sair com
  **exit 75** (`EX_TEMPFAIL`: passageiro, tente depois) e uma primeira linha
  de stderr `codex sem cota: <mensagem original>`; o gate repete essa linha
  no `reason`. Bateria com dublê em modo `semcota`. O `--json` do Codex traz o
  mesmo texto num evento `error`, e o `/transferir` ganha a mesma leitura.

## Avaliado e descartado

- **Reaproveitar o fluxo `agentes-em-codex`**: já fechado e mergeado; reabrir
  estágio de fluxo concluído para colar evidência nova embaralha o recibo.
- **Testar sem fluxo aberto**: a portaria nega despacho sem estágio ativo, e
  é exatamente a portaria viva que se quer ver gravando `runtime`.
- **Tratar "sem cota" como exit 1 comum**: fechado, mas ilegível; o usuário
  não distingue cota de Codex quebrado sem ler o stderr inteiro.

## Fora de escopo

- `/transferir` e `gate-review-codex` ao vivo.
- Revisor em Codex (já provado na T8, fatiado).

## Em aberto

- (vazio)
