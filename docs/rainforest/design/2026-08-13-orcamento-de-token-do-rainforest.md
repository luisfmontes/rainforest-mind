# Orçamento de token do rainforest — medir a abertura antes de comprimir nada

## Objetivo

Dar ao plugin uma régua de custo: repartir a abertura de uma sessão por fonte,
com número medido, e acusar quando as fontes que o rainforest controla passarem
do orçamento declarado. A régua vem antes de qualquer decisão de compressão —
hoje não existe medição que justifique comprimir coisa alguma.

## Decisões fechadas

- **D1 — O alvo da medição é a abertura inteira, não só o que o plugin emite** — porquê: medido em 2026-08-13, o hook do rainforest emite 7.885 B numa abertura de 67.914 tokens, e o maior emissor único é o `skill_listing` com 33.352 B, vindo majoritariamente de outros plugins. Medir só o rainforest responde a pergunta errada e se dá um boletim bom.

- **D2 — A entrega é instrumento permanente, estendendo `scripts/medir-injecao.py`** — porquê: levantamento avulso apodrece em uma semana. E o script já lê transcript e já tem o modo `--entrega`; a lacuna dele é não somar as fontes fixas, não a de ler transcript. Script novo ao lado seria duplicação.

- **D3 — A atribuição sai só do transcript, com uma linha "não atribuído" para o resto** — porquê: os registros `attachment` já trazem cada fonte com tamanho próprio (`skill_listing`, `deferred_tools_delta`, `agent_listing_delta`, `hook_*`), o que é exato e custa zero. O tamanho do resíduo já é informação por si.

- **D4 — A fatia do rainforest dentro das listagens se isola pelo prefixo do plugin** — porquê: conferido no transcript de 2026-08-13 — os nomes chegam prefixados (`rainforest-mind:brainstorm`), e as 18 skills do plugin somam 3.473 B dos 29.943 B de conteúdo da listagem (11,6%). Sem isso, D3 e D6 colidiriam: não daria para acusar só o que é próprio.

- **D5 — Byte é a medida primária; token estimado vai ao lado, com o fator visível na saída** — porquê: byte é exato e reproduzível. O token estimado existe porque sem conversão a linha de "não atribuído" não pode ser calculada — o total da abertura vem em token, as fontes vêm em byte.

- **D6 — Ao estourar, declara e acusa com exit ≠ 0, mas só nas fontes que o rainforest controla** — porquê: acusar estouro do `skill_listing` agregado é apontar para algo que não é do plugin e que o usuário não pode acionar. Alarme não acionável ensina a ignorar o alarme.

- **D7 — O orçamento é o `ORCAMENTO_BYTES: 8000` do hook, preservado, mais um agregado de 14.000 B para o plugin inteiro** — porquê: hoje o plugin ocupa ~12.976 B (hook 7.885 + skills 3.473 + agentes ~1.618), então 14.000 dá ~8% de folga. Só o agregado permitiria mover peso de bolso em bolso sem alarme; só os tetos separados não responderia "quanto o plugin custa".

- **D8 — São dois artefatos, não um: um gate determinístico e um diagnóstico** — porquê: `testa-orcamento.sh` mede as fontes direto do repo, é determinístico e entra no laço do `CONTRIBUTING.md:11` com exit ≠ 0; `medir-injecao.py --repartir` lê transcript real, que muda a cada sessão, e serve de diagnóstico. Gate que depende de transcript falha sozinho e vira ruído.

- **D9 — O contrato de compressão do headroom fica plantado, não entra nesta entrega** — porquê: a dor que o motivava (payload de abertura cortado — 32 KB emitidos, ~2,2 KB entregues, medido em 2026-08-10) aparece resolvida na medição de 2026-08-13, com 7.885 B e zero truncamento. Construir compressor sem dor medida é acrescentar mecanismo que nada exercitou — a pergunta 1 do próprio livro-de-repos apontada para dentro. Plantado como `contrato-de-compressao-do-headroom-reimplementado`, com gancho amarrado ao primeiro estouro que este instrumento acusar.

## Avaliado e descartado

- **Acoplar o `headroomlabs-ai/headroom`** — reprovou na pergunta 4 do livro-de-repos em 2026-08-09 e continua reprovando em 2026-08-13: issue #1466 ("not working on Windows") segue aberta, atualizada no mesmo dia com checklist de investigação e zero comentários; há 85 PRs de Windows abertos contra 488 mesclados, 6 deles abertos nas últimas 48h. Além disso a arquitetura não encaixa: o headroom comprime como **proxy** entre agente e API, e o rainforest é plugin de skills e hooks — não intercepta chamada nenhuma.

- **Medir só o que o plugin emite** — a medição mostrou o rainforest em ~12.976 B de uma abertura de 67.914 tokens, cerca de 6%. Otimizaria a metade menor.

- **Medição diferencial (abrir sessões com fontes desligadas para atribuir por diferença)** — o próprio `medir-injecao.py` registra piso de ruído de ±10,7k tokens entre sessões consecutivas com a injeção constante (medido em 2026-08-10), maior que quase tudo que se quer medir. E gasta sessões do usuário.

- **Um script novo ao lado do `medir-injecao.py`** — duplicaria a leitura de transcript, que já está pronta e testada.

- **Um artefato único cobrindo repo e transcript** — o transcript varia a cada sessão; um gate que afirma sobre ele nasce instável e treina o usuário a ignorar falha vermelha.

## Fora de escopo

- **Emagrecer o payload do hook ou subir o teto** — o hook está em 7.885 de 8.000 B (98,6% do próprio orçamento), e isso é achado real, mas decidir o que fazer com o número é a entrega seguinte. Misturar as duas é o caminho para reescrever a régua até o payload caber nela.
- **Reimplementar as peças de compressão do headroom** — plantado, ver D9.
- **Atribuir system prompt do Claude Code, CLAUDE.md e memórias** — o transcript não guarda esses campos; cairiam na linha de "não atribuído".
- **Token real via `count_tokens`** — exige chave de API que não existe (o Console exigia compra em 2026-08-09).
- **Reduzir as 93 skills listadas na abertura** — apareceu na medição, mas é configuração do ambiente do usuário, não do plugin.

## Em aberto

- O fator byte→token usado na coluna estimada foi medido e fixado: **`BYTES_POR_TOKEN = 3.11`**. Proveniência: medido em 2026-08-13 com `tiktoken` (tokenizador cl100k_base de Claude) sobre o payload real gerado por `hooks/foco-session-start.cjs` deste repositório — 7.666 bytes (UTF-8) → 2.465 tokens. Fica declarado como constante única e visível na saída. O que ele **não** garante: mudanças futuras no payload do hook, adição de skills ou agentes, ou revisions do tokenizador de Claude exigem remedir; este valor é snapshot de 2026-08-13 e não é estável por indefinido.
