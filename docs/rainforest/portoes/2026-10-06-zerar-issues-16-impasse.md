# Impasse — zerar-issues-16, teto de 3 reprovações em `revisar`

**Data:** 2026-10-06

## Rodadas

| Rodada | Bloqueantes | Onde |
|---|---|---|
| 1 | 8 | gate-subagente-sem-instalar (4), limpar-worktrees, conferir-entrega, saude, testa-backup-gravar |
| 2 | 4 | gate-subagente-sem-instalar (flag com valor, `&`/`.` do PowerShell, pwsh com flags), conferir-cobertura-fixtures (restauração sem sha256) |
| 3 | 2 | gate-subagente-sem-instalar (redirecionamento colado a alvo citado), conferir-cobertura-fixtures (lock retomado como pid morto) |

Todos consertados, cada um com caso que fica vermelho sem o conserto, e as
catracas das tarefas tocadas re-rodadas vermelhas (`93e3ce59`, `2e882c3a`,
`c439514d`).

## Diagnóstico

Nem o critério (plano) nem a decisão (design) estão errados: os achados são
casos de borda da implementação, e o número de bloqueantes cai a cada rodada
(8 → 4 → 2), cada vez mais estreitos.

Ressalva registrada pelo usuário na rodada 3: o desligamento de gate deveria
ser só por variável de ambiente (`RAINFOREST_GATE_OFF`) ou config, sem o
arquivo `.rainforest-gate-off` em repo de cliente. A parte do D7 que barra a
criação do arquivo segue inofensiva nesta branch; a remoção do arquivo dos
gates vai em fluxo próprio depois do PR, para não reabrir esta revisão sobre
um diff de 61 arquivos.

## Decisão do usuário

Liberar a 4ª rodada de revisão (resposta "recomendado" às Q1/Q2 de
2026-10-06): remoção do arquivo em fluxo próprio depois do PR; varredura
completa antes da rodada 4.

## Rodada 4: reprovada por 1 bloqueante

Hooks aprovou. Scripts reprovou: snapshot de outra árvore saía 1 no
`conferir-entrega`, e o D24 e o `pronto quando:` da tarefa 12 pedem 2.
Consertado em `e1e68fda` (os dois gêmeos, bateria vermelha contra o anterior,
catraca da tarefa 12 vermelha).

## Decisão do usuário (rodada 5)

Liberar a 5ª rodada ("recomendado", 2026-10-06): um revisor só de scripts,
porque hooks aprovou na 4ª e nada em `hooks/` mudou depois dela.
