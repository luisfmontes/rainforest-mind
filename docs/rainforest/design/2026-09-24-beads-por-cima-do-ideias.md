# Beads por cima do ideias.jsonl: dependência entre ideias

## Objetivo
O `ideias.jsonl` ganha o que o Beads tem de enxertável: dependência entre ideias
como campo, com bloqueio e "prontas" derivados pelo `ideias.cjs`. Não se troca o
armazenamento e não se adota o Beads como ferramenta — é a resposta "por cima,
em peças, não no lugar" da avaliação de 2026-09-23
(`relatorios/2026-09-23-batedor-doze-repos-indicados.md`).

## Decisões fechadas
- **D1 — Enxerta só a peça do grafo de dependência (bloqueio e prontas derivados, com detector de ciclo); ID por hash não entra** — porquê: 59 das 335 ideias abertas (medido em 2026-09-24) já citam outra ideia pelo id na prosa, e parte é bloqueio real ("quando a autoavaliação… rodar", "DESBLOQUEIO: …") — a relação existe e o script não a vê, então ideia bloqueada disputa vaga com as prontas. O ID por hash resolve um problema que já está resolvido (`ideias.cjs` recusa id repetido) e quebraria os links `[[id]]` que ideias e memória usam. Decidido pelo usuário em 2026-09-24.
- **D2 — Uma relação só: `depende_de` (lista de ids), que bloqueia; parentesco continua em `[[id]]` na prosa** — porquê: só o bloqueio muda comportamento (o que está pronto); campo de parentesco sem efeito vira dado que ninguém mantém. Decidido pelo usuário em 2026-09-24.
- **D3 — As 59 abertas que citam outra ideia passam por uma classificação única: a janela propõe a lista de `depende_de` e o usuário aprova em lote antes de gravar** — porquê: poucas para classificar à mão, muitas para ficar invisíveis; sem a passada o campo nasce vazio e as prontas mentem desde o primeiro dia. Inferência automática descartada: citar não é depender (a amostra mostrou irmãs, desbloqueios e vizinhas misturados). Decidido pelo usuário em 2026-09-24.
- **D4 — O bloqueio aparece no `listar` (marca as bloqueadas, filtro `--prontas`) e o `iniciar`/`colher` de ideia bloqueada avisa nomeando quem bloqueia, sem recusar** — porquê: dependência escrita em prosa às vezes é mole; recusar ensinaria o hábito do `--forcar`, que é como trava morre (`skills/plano/SKILL.md`). O aviso deixa a decisão com o usuário, com o nome na tela. Decidido pelo usuário em 2026-09-24.
- **D5 — Bloqueio solta quando a ideia bloqueadora é colhida ou descartada; unificada, o bloqueio segue para a sobrevivente (`unificada_em_id`); o `conferir` avisa dependência de ideia descartada** — porquê: bloqueio que nunca solta é pior que solto demais, e o aviso cobre a dependente que perdeu o sentido junto. Decidido pelo usuário em 2026-09-24.
- **D6 — `plantar`/`editar` recusam `depende_de` com id inexistente ou que feche ciclo; o `conferir` acusa o que já está gravado inconsistente** — porquê: com ciclo, nenhuma das ideias do ciclo fica pronta nunca; id inexistente é quase sempre erro de digitação. Mesmo papel do `cycledetector.go:9-60` do Beads. Decidido pelo usuário em 2026-09-24.

## Avaliado e descartado
- Beads no lugar do `ideias.jsonl` (`gastownhall/beads`): Dolt embutido é o único backend (a proposta de backend plugável é só design), e o plugin roda `bd prime` em SessionStart e PreCompact — reprova nas perguntas 2, 3 e 5 do livro de repos (relatório de 2026-09-23).
- ID por `sha256` + nonce em base36 (`internal/idgen/hash.go:53-84`): D1.
- CAS por `row_lock` e compactação do Beads: resolvem merge célula a célula do Dolt e exigem LLM por item; o lock de arquivo do `ideias.cjs` basta.
- Relação `irma` como campo: D2.
- Inferir `depende_de` do texto: D3.

## Fora de escopo
- Os git hooks do Beads (post-checkout, post-merge…): o `ideias.jsonl` mora em `~/.rainforest`, fora de repo.
- Mudar como a abertura de sessão mostra ideias (hoje só aponta o arquivo).

## Em aberto
