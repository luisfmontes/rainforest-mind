# Design: aviso de contexto alto na fronteira de estágio, pelo uso real do transcript

## Objetivo
Sessão longa enche o contexto sem sinal nenhum: uma morreu em 96%, e o hábito de passar o bastão em torno de 70% depende de alguém olhar a barra. O `estado.cjs exigir` passa a avisar, em uma linha, quando a última mensagem da sessão já usa mais tokens que o limiar. É o momento em que parar custa menos, porque o estágio anterior acabou de fechar.

## Decisões fechadas
- **D1 — A medida é a soma de `input_tokens`, `cache_creation_input_tokens` e `cache_read_input_tokens` da última mensagem `assistant` do transcript** — porquê: os três campos repartem o prompt, então a soma é o contexto daquele turno. Em 2026-11-09 o transcript real desta sessão trouxe `2 + 6995 + 146043`: sem o `cache_read` a medida daria 7 mil. Mensagem com soma zero (`<synthetic>`) e `isSidechain` não contam, porque não são o contexto da janela. Quando `usage.iterations` existe (resposta que consultou o advisor), o topo soma todas as chamadas ao modelo e dobra a medida (215 registros em 54 sessões, emenda de 2026-11-10 após a revisão 1): vale a soma da última iteração `type: message`. Depois de `/compact`, a última mensagem já vem baixa e o aviso some sozinho.
- **D2 — O transcript se acha por `CLAUDE_CODE_SESSION_ID`, em `<CLAUDE_CONFIG_DIR ou ~/.claude>/projects/*/<id>.jsonl`, e só a cauda de 1 MB é lida** — porquê: a pasta do projeto vem do cwd em que a sessão nasceu, que o `exigir` em worktree não conhece; varrer as 782 pastas com `existsSync` é barato. O id só passa se casar `^[\w-]+$`, para não virar caminho. O registro mais recente fica no fim, e transcript passa de dezenas de MB.
- **D3 — O limiar é a chave `contexto-alto-tokens`, inteiro maior ou igual a zero, padrão 310000, e 0 desliga** — porquê: decisão do Luís em 2026-11-09 (Q1 A, tokens e configurável) e em 2026-11-10 (padrão 310 mil). O padrão de 700 mil presumia janela de 1 M e nunca dispararia: em 54 sessões o autocompact entrou entre 211 mil e 447 mil (`compactMetadata.preTokens`), e nenhuma passou de 442 mil. 310 mil é 70% desse teto real, o ponto que a memória `handover-quando-contexto-alto` usa; 32 das 54 sessões chegaram lá. A chave entra em `CHAVES` com tipo novo `tokens`.
- **D4 — O aviso sai só no `exigir`, em stderr, antes das recusas, sem mudar exit nem stdout** — porquê: decisão do Luís em 2026-11-09 (Q2 A). Fronteira de estágio é o ponto de decidir, e não precisa de hook novo. Antes das recusas porque estágio recusado também é hora de saber. Sem deduplicação: são poucas fronteiras por sessão.
- **D5 — O aviso falha para o silêncio, com o `require` da lib dentro do `try`** — porquê: é aviso, não trava, e não protege contra ninguém; o que fica fora é sessão sem fluxo e sessão que ignora o aviso. Transcript ausente, JSON quebrado, config ilegível ou lib que não está lá não podem derrubar `exigir`. O `require` no `try` também deixa de fora as caixas de bateria que copiam o `estado.cjs` e listam as libs à mão: o #674 perdeu uma rodada de CI por um `require` novo nelas.
- **D6 — O texto diz o uso, o limiar e o que fazer antes do estágio pedido** — porquê: quem lê precisa decidir ali. A forma é `aviso: contexto em 320 mil tokens (limiar 310 mil). Antes de abrir 'plano', registre o estado e considere /compact ou uma sessão nova.`

## Avaliado e descartado
- Detectar a janela pelo marcador `[1m]` no modelo: o transcript desta sessão traz `claude-opus-5-5` sem marcador, e a tabela de famílias que o ECC mantém (`scripts/lib/transcript-context.js`) envelhece a cada modelo novo.
- Reaproveitar o `criarExtractorUsage` de `scripts/poda.cjs:64`: ele lê stream SSE do proxy, não JSONL de transcript.

## Fora de escopo
- Sessão fora de fluxo: decisão Q2 A; o hook em toda ferramenta ficou de fora.
- Parar a sessão ou compactar sozinho: o aviso informa, quem decide é a sessão.
- Porcentagem da janela: exigiria declarar o tamanho dela, e a Q1 fechou em tokens.

## Varredura
docs/rainforest/varredura/2026-11-09-aviso-contexto-alto.txt — nenhuma Issue, PR ou branch sobre o aviso. Os casamentos de `handover` são o `handover.cjs` antigo e o de `autocompact`, a #608 do `/saude`; nenhum lê uso de contexto. O `ao_colher` da ideia pedia ler o ECC e conferir o formato real: lido o `transcript-context.js` (confirma a soma dos três campos) e conferido o transcript desta versão (D1).

## Em aberto
Nada.
