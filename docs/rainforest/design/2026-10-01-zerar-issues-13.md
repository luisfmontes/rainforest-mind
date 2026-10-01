# Rodada 13 — laço sem gh (#362), veredito no worktree do revisor (#363), menores do semear-travas (#364)

## Objetivo
Fechar as três Issues abertas pela revisão do fluxo `2026-09-30-semear-travas`: um falso positivo do gate-fechar-issue, o veredito do revisor gravado no worktree errado e cinco achados menores das travas novas.

## Decisões fechadas
- **D1 — #362: `bash|sh <arquivo>` (com ou sem aspas, com ou sem variável) é execução de arquivo, não wrapper de string; só `-c`, `eval`, `-Command` e `-EncodedCommand` com variável continuam ilegíveis** — porquê: `bash script.sh` literal já passa, porque o gate nunca leu conteúdo de arquivo; `bash $b` não esconde nada a mais. Liberar qualquer segmento sem `gh` abriria `bash -c "$x"`. Critério: `for b in a.sh; do bash $b; done` sai 0; `bash -c "$x"` continua saindo 2 (`hooks/testa-gate-fechar-issue.sh`).
- **D2 — #363: `raizComEstadoDoSlug` escolhe, entre o repoRoot e os worktrees que têm `docs/rainforest/estado/<slug>.json`, o que tem a janela de revisar armada (`vereditos: []` pelo `exigir --estagio revisar`), excluindo o toplevel de `payload.cwd` quando ele é um worktree linkado e outro candidato existe** — porquê: é o critério da Issue; excluir só o worktree do revisor ainda dá "ambíguo" com 2+ cópias, e casar pela branch depende de nome (slug `2026-10-01-zerar-issues-13` x branch `fluxo/zerar-issues-13`). Critério: bateria do hook com revisor em worktree linkado com cópia do estado grava no worktree do fluxo ativo e deixa a cópia do revisor intacta.
- **D3 — #364 itens 1 e 2: o gate-turno-prometido remove aspas e crases pareadas só quando o par fecha (aspas soltas na mesma linha não engolem a promessa), e passa a remover citação multi-linha entre aspas e bloco `>`** — porquê: o falso negativo do item 1 deixa promessa passar; o falso positivo do item 2 custa um turno, e o cabeçalho promete "citações". Critério: casos novos em `hooks/testa-gate-turno-prometido.cjs`, vermelhos antes.
- **D4 — #364 itens 3 e 4: `--exige` fora do worktree (preparar-worktree) e `--slug` com separador ou `..` (varrer) saem com exit 2 e mensagem que nomeia o valor** — porquê: normalizar em silêncio esconde o erro de quem chamou; recusar é o padrão das travas da família. Critério: casos em `scripts/testa-preparar-worktree.sh` e `scripts/testa-varrer.sh`.
- **D5 — #364 item 5: `docs/travas-mecanicas.md` cita `python` e `python3` na forma simples do `conferir-prova`** — porquê: o código aceita as duas.
- **D6 — Entrega: um PR, bump de minor sobre a `origin/main` do momento, cada item com caso de bateria vermelho antes do conserto (mutação), Issues fechadas pelo `fechar-issue.cjs` depois do merge** — porquê: formato das rodadas anteriores.

## Avaliado e descartado
- #362 liberando segmento sem `gh` no texto: abre `bash -c "$x"` com `gh` dentro da variável, que a própria Issue exige barrar.
- #363 casando pela branch `fluxo/<slug>`: o slug do estado e o nome da branch divergem (medido nesta rodada).
- #364 itens 3 e 4 normalizando o caminho: esconde o erro de quem chamou.

## Fora de escopo
- Ler o conteúdo de arquivo executado por `bash <arquivo>` atrás de `gh`: o gate nunca fez isso, nem para caminho literal.
- Mudar a regra 11 (revisor em worktree isolado): o conserto é no hook, não no isolamento.

## Varredura
docs/rainforest/varredura/2026-10-01-zerar-issues-13.txt — achou o histórico #337, #309 (aspas em `bash $t`) e #329 (estado só no worktree), todas fechadas; nenhuma branch, PR aberto ou ideia duplicando esta rodada.

## Em aberto
(nenhum)
