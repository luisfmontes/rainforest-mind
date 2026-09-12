# Statusline mostra o tempo até o reset; checkout principal fica na main

## Objetivo
Duas coisas pedidas pelo Luís em 2026-09-08, na mesma frase de abertura da
sessão: a barra de status dizer **quanto falta para a janela de tokens
reiniciar**, e a regra 11 passar a dizer que **se trabalha em worktree, deixando
a pasta do repositório na `main`** — com trava, que é o que a Issue #195 pedia.

## Decisões fechadas
- **D1 — Cada janela de limite (`5h`, `7d`) mostra, ao lado do percentual, o tempo até o reset no formato compacto `↻2h10` (menos de um dia) ou `↻3d4h` (um dia ou mais), lido de `rate_limits.<janela>.resets_at` (epoch em segundos)** — porquê: o dado já chega no stdin da barra (doc oficial do harness), então é uma conta, não uma consulta; `resets_at` ausente, não numérico ou já passado não mostra nada e não derruba os outros segmentos — a barra nunca trava.
- **D2 — A regra 11 (núcleo em `SKILL.md`, elaboração em `regra-11.md`, tabela do README) ganha a preferência explícita: o checkout principal do repositório fica na branch padrão, e trabalho de qualquer sessão — não só de subagente — nasce em worktree (`git worktree add` ou `EnterWorktree`)** — porquê: os vigias agendados resolvem a raiz pelo checkout principal e rodam contra o que estiver lá (Issue #195); sessões paralelas se co-locam nele; e o pedido do Luís foi literalmente "de preferência criar wt e não trabalhar na pasta do repositório".
- **D3 — `estado.cjs iniciar` recusa com exit 2 quando roda no checkout principal (não é worktree linkado) com a branch atual diferente da padrão, e a mensagem traz a receita (`git worktree add .claude/worktrees/<slug> <branch>` e `git checkout <padrão>`); a chave `principal-livre: true` em `.rainforest/config.json` desliga a recusa; fora de repositório git nada muda; `exigir` só avisa em uma linha no stderr, sem recusar** — porquê: `iniciar` é o momento mais barato de corrigir, antes de qualquer linha escrita; recusar garante e avisar vira rotina (as duas decisões em aberto da #195); a chave usa a mesma cadeia dos gates (`hooks/lib/config.cjs`), porque o caso legítimo existe — clone dedicado a uma frente só; e derrubar `exigir` no meio de um trabalho em voo puniria quem já está no estágio 4 por um erro do estágio 0.
- **D4 — Versão 1.9.0** — porquê: `iniciar` passa a recusar um estado que antes aceitava, em qualquer repositório que use o fluxo — mudança de comportamento para outros devs é minor, não patch.

## Avaliado e descartado
- **Trava em hook `PreToolUse` sobre `git checkout -b`** — o gate-worktree já intercepta `checkout`/`switch`, mas só quando há outra sessão viva no diretório; estender para "sempre que houver worktree linkado" recusaria o `git checkout main` de volta, que é exatamente o conserto. A recusa no `iniciar` não tem esse falso positivo.
- **Recusar também no `exigir`** — pega quem começou errado e continuou, mas derruba trabalho em voo por erro que já passou; o aviso de uma linha mantém o fato visível sem o custo.
- **Mostrar o horário absoluto do reset (`14h35`)** — o pedido foi "quantas horas faltam"; horário absoluto obriga a conta de cabeça que a barra existe para poupar.

## Fora de escopo
- As demais 19 Issues abertas — estão no fluxo `zerar-issues`, em paralelo.
- Mudar o segmento de percentual (`5h 23%`), suas faixas de cor ou sua ordem.
- Trava na portaria ou no `saude.cjs` para o mesmo fato.

## Em aberto
- Nada. D3 foi decisão desta sessão sobre as duas perguntas em aberto da #195; a aprovação do design deriva do pedido do Luís de 2026-09-08 e da autorização explícita de trabalhar com subagentes nesta sessão.
