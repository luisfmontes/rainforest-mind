# Impasse: 2026-10-13-executar-autonomo

O `revisar` reprovou três vezes seguidas, e o teto do laço foi atingido em 2026-10-14.

## Por que não é critério nem design errado

Os achados de cada volta foram fechados na volta seguinte, e o revisor confirmou isso rodando os cenários. Cada volta encontrou defeitos novos, sempre no `integrar-tarefa.cjs`, cada vez mais estreitos.

- **Volta 1:** 8 achados.
- **Volta 2:** 3 achados, todos introduzidos pelo conserto da retomada.
- **Volta 3:** 1 achado médio e 3 baixos.
  - **Médio:** a retomada confia só no trailer. Com `--base` velha, ou com o fluxo reescrito por rebase, o script dá `aceito` sem a correção do agente e apaga o worktree dele.
  - **Baixo:** a branch do agente sobra quando a retomada acontece sem worktree.
  - **Baixo:** a recusa deixa pasta vazia.
  - **Baixo:** dois comentários de cabeçalho ficaram desatualizados.

Nenhum achado é `[design]`. As decisões D1 a D7 continuam de pé.

## Conserto proposto para a 4ª rodada

- Na retomada com o worktree do agente presente, conferir com `git apply --check -R` que o diff `base..agenteHead` já está no HEAD. Se não estiver, recusar com o passo `retomada` e manter o worktree.
- Apagar a branch do agente também quando o worktree já tiver sumido.
- Na recusa, remover as pastas que ficarem vazias.
- Atualizar os dois comentários.
- Na bateria, acrescentar o cenário da `--base` velha num redespacho, com a recusa esperada.

## Decisão do usuário

2026-10-14, Luís: "recomendado" (opção A) — libera a 4ª rodada com o conserto proposto acima.
