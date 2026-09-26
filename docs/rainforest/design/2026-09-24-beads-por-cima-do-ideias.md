# Beads por cima do ideias.jsonl: não acopla

## Objetivo
Responder a ideia `beads-no-lugar-ou-por-cima-do-ideias-jsonl` com medição: o
que o Beads tem de enxertável (grafo de dependência entre itens, com bloqueio e
"prontas" derivados) resolveria um problema que o `ideias.jsonl` tem? A medição
diz que não — e o achado fica registrado para não voltar como suposição.

## Decisões fechadas
- **D1 — Não acopla: nem o Beads no lugar, nem o grafo de dependência por cima** — porquê: das 336 ideias abertas, 55 citam outra ideia pelo id (86 citações), e classificadas uma a uma só **1** é bloqueio de verdade (`papel-de-advisor-que-observa-a-janela-principal` espera `autoavaliacao-do-metodo-contra-o-rastro`); 45 são parentesco e 40 citam ideia já colhida ou descartada (`docs/rainforest/pesquisas/2026-09-24-dependencias-propostas.md`). Um mecanismo de bloqueio para uma ideia é código mantido por nada. A primeira versão deste design (D1–D6, enxertar o grafo) partiu da suposição de que "parte das 59 é bloqueio real"; a medição a derrubou antes da primeira linha de código entrar. Decidido pelo usuário em 2026-09-24, depois da medição.
- **D2 — O achado vira uma linha no `vigias/livro-de-repos.md` e a ideia é colhida com o resultado** — porquê: é a terceira saída que a própria ideia previa ("não acopla e o achado vira uma linha no livro"); colhida com o número, a ideia não volta a pedir avaliação sem dado novo. Decidido pelo usuário em 2026-09-24.

## Avaliado e descartado
- Beads no lugar do `ideias.jsonl` (`gastownhall/beads`): Dolt embutido é o único backend e o plugin roda `bd prime` em SessionStart e PreCompact — reprova nas perguntas 2, 3 e 5 do livro de repos (relatório de 2026-09-23).
- Grafo de dependência por cima (`depende_de` com bloqueio, `listar --prontas`, aviso no `iniciar`/`colher`, recusa de ciclo, `conferir`): desenhado e planejado nesta sessão, descartado pela medição de D1 — 1 bloqueio em 336 abertas.
- ID por `sha256` + nonce em base36 (`internal/idgen/hash.go:53-84`): o `ideias.cjs` já recusa id repetido, e hash quebraria os links `[[id]]`.
- CAS por `row_lock` e compactação do Beads: resolvem merge célula a célula do Dolt e exigem LLM por item; o lock de arquivo do `ideias.cjs` basta.

## Fora de escopo
- Os git hooks do Beads: o `ideias.jsonl` mora em `~/.rainforest`, fora de repo.
- Gravar o único `depende_de` encontrado: sem o campo no `ideias.cjs`, a relação continua na prosa do gancho da ideia, onde já está.

## Em aberto
