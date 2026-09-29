# Zerar as Issues abertas, rodada 12 — variável que o gate não resolve (#350)

## Objetivo
Fechar a #350 fazendo os dois gates dizerem a causa real do bloqueio quando o
alvo do comando vem de variável ou substituição: hoje o gate-worktree culpa
"move o HEAD deste checkout" e o gate-fechar-issue culpa "caminho relativo",
e em nenhum dos dois o usuário lê que o problema é o `$`. Nenhuma expansão de
variável entra.

## Decisões fechadas
- **D1 — Nenhum parser expande variável: `git -C "$H"`, `cd "$TMP"` e `--body-file "$SP/x"` continuam incertos, como na base** — porquê: a rodada 9 tentou a resolução estática de `$VAR` no gate-fechar-issue e quatro revisões acharam bypass (crase colada, array, `read`/`printf -v`/`declare`/`+=`, comentário ou heredoc como atribuição falsa; `docs/rainforest/design/zerar-issues-9.md:11`). Aqui um bypass faria a trava co-locada liberar um `switch` no checkout compartilhado. O contorno com caminho literal já passa nos dois gates hoje: `git -C <literal>` de outro repo é comparado pelo toplevel e liberado.
- **D2 — Trava de sessão co-locada: alvo incerto continua barrando; quando o alvo que casou é incerto, a mensagem diz que o comando usa variável, substituição ou `cd` que o gate não resolve, e manda usar o caminho literal; o docblock de `gateDeSessaoColocada` registra que "falha para liberar" vale para falta de infraestrutura (sem `session_id`, sem `sessoes.json`, fora de repo), não para alvo que o parser não resolve** — porquê: o falso negativo é o incidente que a trava existe para impedir. Critério: `git -C "$H" switch -c x` com sessão co-locada sai 2 com "caminho literal" no stderr; `git -C <clone-literal-de-outro-repo> switch -c x` sai 0; `git -C <principal-literal> switch -c x` sai 2 com a mensagem atual (sem a frase de variável).
- **D3 — gate-fechar-issue (P2): `--body-file` com `$`, crase ou `$(` no caminho bloqueia com "variável não resolvível no --body-file: use o caminho literal", separado do caso de caminho relativo com `cd` dinâmico, que mantém a mensagem atual** — porquê: a #344 corrigiu o MSYS, mas a variável cai no ramo de relativo e a mensagem aponta a causa errada. Critério: `SP=C:/x; gh pr create --body-file "$SP/pr.md" …` sai 2 com "variável não resolvível"; `cd $D && gh pr create --body-file pr.md` sai 2 com a mensagem de relativo; o caminho literal absoluto continua 0.
- **D4 — Entrega: um PR, bump de minor sobre `origin/main`, casos novos nas baterias `hooks/testa-gate-worktree.sh` e `hooks/testa-gate-fechar-issue.sh` com mutação (tirar o ramo novo deixa vermelho); a #350 fecha pelo `fechar-issue.cjs` depois do merge, com o registro de D1** — porquê: formato das rodadas anteriores.

## Avaliado e descartado
- Expandir atribuições literais do próprio comando e variáveis de ambiente do hook (Q1 (a)+(b) da rodada): é a resolução estática que a rodada 9 reverteu depois de quatro bypass; aqui o furo liberaria um `switch` no checkout compartilhado.
- Expandir só variável de ambiente cujo nome não é atribuído no comando (Q1 (b')): mesma família de furo (heredoc, `declare`, `read`), com superfície menor, mas não nula.
- Liberar alvo incerto na trava co-locada, como o docblock sugeria: reabre o incidente original (mover o HEAD da outra sessão).

## Fora de escopo
- Resolver `$(...)`: exigiria executar o comando.
- O ramo do gate-worktree para o checkout principal sem sessão co-locada: já nomeia "cd com variavel" na mensagem (`hooks/gate-worktree.cjs:350`).

## Em aberto
(nenhum)
