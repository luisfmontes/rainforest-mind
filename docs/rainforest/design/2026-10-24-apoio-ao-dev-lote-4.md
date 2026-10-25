# Apoio ao dev, lote 4: busca com trecho e proximidade, resumo invalidado em cascata, posição servida

## Objetivo
Quarto lote da rodada apoio-ao-dev (backlog de `relatorios/2026-10-24-releitura-do-livro.md`, grupos G1 e G2), tema
memória. Entram as peças com ponto de encaixe conferido no código atual (mapeamento de 2026-10-25), cada uma com
critério que falha na base.

Brainstorm conduzido sob a delegação do Luís ("faça o brainstorm de tudo com a opção recomendada", "pode seguir
todos os fluxos"). Cada `D<n>` é a resposta recomendada e fica **aberta a veto no PR**.

## Decisões fechadas
- **D1 — Para quem e quando: o Luís no fluxo diário, em qualquer repo, a partir do merge.** — porquê: mesmo público dos lotes 1 a 3.
- **D2 — Tudo convive.** Banco já gravado continua válido: colunas novas entram por migração (`adicionarColunaSeFaltar`, padrão de `scripts/memoria.cjs:435-452`) e linha antiga sem o valor novo segue servida como hoje. — porquê: o corpus do Luís não pode exigir rebuild.
- **D3 — `buscar --texto` devolve trecho e reordena por proximidade.** (a) O SELECT do ramo com texto ganha `snippet(observacoes_fts, ...)` com os termos entre `[` e `]` e reticências; a saída humana mostra o trecho no lugar dos 100 primeiros caracteres (`memoria.cjs:1127`), e o `--json` ganha o campo `trecho` sem perder `conteudo`. (b) A consulta busca `max(limite, 50)` candidatos por bm25 e reordena em JS: `final = s × (1 + prox)`, com `s = −bm25` e `prox = 1 / (1 + janela / termos)`, onde `janela` é o menor intervalo de tokens do conteúdo que contém todos os termos distintos da consulta (`prox = 0` quando algum termo falta ou a consulta tem um termo só); empate segue pelo mais recente, e o corte em `limite` vem depois do rerank. — porquê: hoje é bm25 puro (`memoria.cjs:961`) e a saída corta os 100 primeiros caracteres, que quase nunca contêm o termo; duas palavras juntas valem mais que espalhadas. Enxerto de context-mode `store.ts:263-348` (rerank por proximidade sobre top-N) e da peça plantada `memoria-snippet-por-highlight`.
- **D4 — Resumo derivado de observação superada sai da abertura.** `resumos` ganha a coluna `invalidado_em`. Quando o `reconciliar` marca `substituida_por` numa observação que tem `consolidada_em`, o resumo do mesmo projeto com `criada_em = consolidada_em` (o vínculo já existe: `consolidarAtomico` grava o mesmo instante nos dois, `memoria.cjs:1589-1608`) ganha `invalidado_em = agora` **quando a fração de observações dele já superadas chega a 1/4** (`LIMIAR_INVALIDA_RESUMO = 0.25`). A abertura (`buscarResumosRecentes`, `hooks/memoria-session-start.cjs:383-389`) deixa de servir resumo com `invalidado_em`. — porquê: hoje o reconciliar pode superar observação já consolidada (`memoria.cjs:2144-2146` não filtra `consolidada_em`) e o resumo continua servido com o fato velho. O limiar vem da medição no banco real em 2026-10-25: 310 resumos, todos com vínculo, mediana de 30 observações cada; 38 deles têm alguma observação superada, quase todos 1 de 30. Invalidar por uma só derrubaria 12% dos resumos por 3% de conteúdo; com 1/4, hoje cai 1 (1 de 4). Enxerto de agentmemory `cascade.ts` e cognee `invalidate_sessions.py` (invalidação por proveniência).
- **D5 — O uso registra a posição em que a memória foi servida.** `uso_memoria` ganha `posicao` (1 = primeira linha do bloco, na ordem em que `extrairLinhasServidas` lê o bloco, `scripts/lib/utilidade.cjs:61-63`), propagada até `gravarUso` (`utilidade.cjs:602`); linha antiga fica com `posicao` nula. O `utilidade --relatorio` ganha a nota média por faixa de posição (1–3, 4–7, 8+), sem mudar a seleção. — porquê: o relatório D9 decide se liga o ranking por utilidade (`memoria.cjs:25`), e sem a posição ele não separa "foi útil" de "estava no topo"; hoje a ordem se perde em `pontuarSessao` (`utilidade.cjs:643`). Enxerto da peça plantada `memoria-recall-log-com-rank-servido`.
- **D6 — Um fluxo, um PR, versão 1.78.0.** — porquê: mesmo motivo dos lotes anteriores.

## Avaliado e descartado
- **Captura no `PreCompact`**: redundante. O `observar.cjs` está na SessionStart sem matcher (`hooks/hooks.json:34-42`), então já roda depois de cada compactação, e lê o transcrito a partir do offset, que a compactação não trunca.
- **Filtro de relato de agente na captura**: já entregue no lote 1 (D3, `removerBlocosInjetados` em `scripts/observar.cjs`).
- **Utilidade dentro do score do `buscar`**: o próprio desenho diz que o sinal mede sem mudar a seleção até a régua D9 decidir (`utilidade.cjs:6-8`); D5 é o que falta para a régua ler certo.
- **Ranking da abertura com reforço (claude-mem ACT-R)**: nada conta reforço hoje (o merge do reconciliar só rejuvenesce a linha, `memoria.cjs:2045-2093`); depende de medir com D5 antes.

## Fora de escopo
- Limpeza retroativa do corpus com relato de agente (ideia `limpar-corpus-de-memoria-com-relato-de-agente`): o texto gravado já é resumo do haiku, sem marcador mecânico; pede amostra e critério próprios.
- Minerador falha→correção do transcrito (rtk `find_corrections`): peça grande, sem bateria vizinha; fica para lote próprio.
- Stopwords PT-BR no `buscar`: mudaria o casamento do FTS, não só a ordem.

## Varredura
docs/rainforest/varredura/2026-10-24-apoio-ao-dev-lote-4.txt — termos buscar, bm25, snippet, resumos, consolidada_em, uso_memoria, posicao, reconciliar. Nenhuma Issue aberta nem branch remota no tema. As fechadas tratam outro ponto: nome duplicado de projeto (#435), régua D7 do assunto (#436), SQLITE_BUSY no ALTER das migrações (#460, que vale para as colunas novas de D4 e D5: usar `adicionarColunaSeFaltar`, que já trata o BUSY). Os PRs da família (#305 reconciliação e consolidação, #326 sinal de utilidade, #535 bm25 no buscar) são a base sobre a qual D3 a D5 se apoiam; nenhum entrega trecho, proximidade, invalidação de resumo ou posição servida. Nada a reimplementar.

## Em aberto
