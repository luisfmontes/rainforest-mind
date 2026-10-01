# Rodada 13 — laço sem gh (#362), veredito no worktree do revisor (#363), menores do semear-travas (#364)

## Objetivo
Fechar as três Issues abertas pela revisão do fluxo `2026-09-30-semear-travas`: um falso positivo do gate-fechar-issue, o veredito do revisor gravado no worktree errado e cinco achados menores das travas novas.

## Decisões fechadas
- **D1 — #362 não é defeito: `bash $b` sem aspas continua barrado (exit 2), e a mensagem passa a dizer o porquê — sem aspas a variável se divide em palavras e pode injetar `-c`; `bash "$b"` continua passando** — porquê: medido em 01/10, `CMD='-c echo${IFS}INJETADO:${IFS}gh${IFS}issue${IFS}close${IFS}12'; bash $CMD` imprimiu `INJETADO: gh issue close 12`; a revisão do lote 4 já tinha fechado esse furo (`hooks/lib/tokens-comando.cjs:849`). Liberar seria o bypass; o contorno são duas aspas. Critério: `for b in a.sh; do bash $b; done` sai 2 com "injetar" no stderr; `for b in a.sh; do bash "$b"; done` sai 0; a Issue fecha com esse registro.
- **D2 — #363: `raizComEstadoDoSlug` junta como candidatos o repoRoot e os worktrees que têm `docs/rainforest/estado/<slug>.json`, descarta os worktrees de agente do harness (`.claude/worktrees/agent-*`, o mesmo teste de `ehWorktreeDeAgente` em `hooks/lib/contexto-sessao.cjs`), e entre os que sobram prefere o que tem a janela de revisar armada (`revisar.vereditos` é array); sobrando mais de um, continua ambíguo e não grava** — porquê: o JSON de estado é commitado, então a cópia do revisor pode estar armada também e o critério "armado" sozinho empata; excluir só o `payload.cwd` quebra o revisor não isolado, cujo cwd é o próprio worktree do fluxo. O caminho `agent-*` é a convenção do harness (branches `worktree-agent-<hash>` no histórico). Critério: bateria do hook com revisor em `.claude/worktrees/agent-x` com cópia armada do estado grava no worktree do fluxo e deixa a cópia do revisor intacta; revisor não isolado continua gravando no worktree do fluxo.
- **D3 — #364 itens 1 e 2: o gate-turno-prometido remove aspas e crases pareadas só quando o par fecha (aspas soltas na mesma linha não engolem a promessa), e passa a remover citação multi-linha entre aspas e bloco `>`** — porquê: o falso negativo do item 1 deixa promessa passar; o falso positivo do item 2 custa um turno, e o cabeçalho promete "citações". Critério: casos novos em `hooks/testa-gate-turno-prometido.cjs`, vermelhos antes.
- **D4 — #364 itens 3 e 4: `--exige` fora do worktree (preparar-worktree) e `--slug` com separador ou `..` (varrer) saem com exit 2 e mensagem que nomeia o valor** — porquê: normalizar em silêncio esconde o erro de quem chamou; recusar é o padrão das travas da família. Critério: casos em `scripts/testa-preparar-worktree.sh` e `scripts/testa-varrer.sh`.
- **D5 — #364 item 5: `docs/travas-mecanicas.md` cita `python` e `python3` na forma simples do `conferir-prova`** — porquê: o código aceita as duas.
- **D6 — Entrega: um PR, bump de minor sobre a `origin/main` do momento, cada item com caso de bateria vermelho antes do conserto (mutação), Issues fechadas pelo `fechar-issue.cjs` depois do merge** — porquê: formato das rodadas anteriores.

## Avaliado e descartado
- #362 tratando `bash <arquivo>` com variável sem aspas como execução de arquivo (primeira versão da D1, aprovada e revertida em 01/10): `bash $CMD` injeta `-c` pela divisão de palavras — medido, imprimiu `INJETADO: gh issue close 12`.
- #362 resolvendo a lista literal do `for`: é a resolução estática que a rodada 9 reverteu depois de quatro bypasses (reatribuição no corpo, `read`, `declare`).
- #362 liberando segmento sem `gh` no texto: abre `bash -c "$x"` com `gh` dentro da variável.
- #363 casando pela branch `fluxo/<slug>`: o slug do estado e o nome da branch divergem (medido nesta rodada).
- #363 só pela janela armada, ou só excluindo o `payload.cwd`: o estado é commitado (a cópia do revisor pode estar armada) e o revisor não isolado tem o cwd no próprio fluxo.
- #364 itens 3 e 4 normalizando o caminho: esconde o erro de quem chamou.

## Fora de escopo
- Mudar a regra 11 (revisor em worktree isolado): o conserto é no hook, não no isolamento.

## Varredura
docs/rainforest/varredura/2026-10-01-zerar-issues-13.txt — achou o histórico #337, #309 (aspas em `bash $t`) e #329 (estado só no worktree), todas fechadas; nenhuma branch, PR aberto ou ideia duplicando esta rodada.

## Em aberto
(nenhum)
