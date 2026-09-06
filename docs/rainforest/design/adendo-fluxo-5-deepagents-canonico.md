# Adendo ao Fluxo 5 (`poda.cjs`) — design canônico

> Forma canônica (`conferir-fluxo.cjs design`) de
> `docs/rainforest/design/adendo-fluxo-5-deepagents.md` (narrativa) e companion de
> `docs/rainforest/design/fluxo-5-design-poda.md` (design original — fase 0 fechada, PR #136).
> Divergência entre este arquivo e a narrativa se resolve a favor deste. Mesmo
> precedente do fluxo 11 (`docs/rainforest/estado/fluxo-11-conselho.json`, bloco
> `plano.decisoes.formato-canonico`).
>
> **Status (2026-09-05): decisões registradas, construção BLOQUEADA.** Medido nesta
> máquina, não relatado:
>
> ```
> $ node scripts/relatorio-poda.cjs --json
> {"gate":"FECHADO","dias_distintos":0,"faltam":7}
> ```
>
> (exit 1). `docs/rainforest/design/fluxo-5-design-poda.md:53`: *"Gate de saída da
> fase 0: relatório de uma semana de uso real. Sem ele, fase 1 não abre."* E
> `:107-108`: *"fases 1 e 2 só com o relatório de evidência em mãos."* As duas
> frases condicionam **abrir** a fase 1 — planejar e construir —, não só ligá-la
> depois de pronta. As D1–D9 abaixo valem para quando o gate abrir; nenhuma vira
> tarefa de `plano` hoje.
>
> **Nota de método**: o adendo *adota* números calibrados por terceiro (deepagents).
> Isso não os torna decisão fechada do dono. Só vira `D` aqui o que o adendo decide
> de fato (formato, arquitetura, o que não copiar) ou o que um achado do
> levantamento provou com `arquivo:linha`. Número emprestado sem medição própria
> desta máquina fica em `## Em aberto`.

## Objetivo

Fixar, em forma que o checador aceita, o que o adendo de fato decidiu para a fase 1
do `poda.cjs` — formato do stub, histórico append-only, o que não copiar — e o que o
estado real do repositório já resolveu desde 2026-08-30, sem promover a decisão
fechada números de calibração que ninguém neste repositório mediu ainda, e sem
autorizar construção que a regra de evidência do próprio design original barra.

## Decisões fechadas

- **D1 — O histórico de sessão podado é append-only**: um arquivo por sessão (`sessao-<id>.md`), nunca reescrito, uma seção datada por evento de poda. Origem: adendo, seção 3, ancorado na regra R1 do design original (`fluxo-5-design-poda.md:40`, "nunca reescrever blocos que já foram enviados... compressão determinística e estável"). Não é número emprestado: é arquitetura de cache que o design original já exigia, e que o deepagents confirma de fora.

- **D2 — O stub de poda tem forma estrutural fixa**: cabeçalho `[podado]`, caminho do arquivo CCR, instrução explícita de leitura parcial (`offset`/`limit`) embutida no próprio texto do stub, e um marcador de linhas omitidas separando a prévia de início da de fim. Origem: adendo, seção 2, partes qualitativas. **Não** inclui o número de linhas de cada prévia — isso é calibração, e está em `## Em aberto`.

- **D3 — Todo caminho novo de fase 1 (arquivo CCR, `sessao-<id>.md`) resolve por `hooks/lib/poda-dados.cjs`, nunca por caminho literal.** Origem: achado do levantamento — o módulo já exporta `raizPoda`, `caminhoMetricas`, `caminhoContexto`, `caminhoPid` e `portaPadrao`, todos exercitados por `scripts/testa-poda-dados.sh`. Caminho literal repetiria o erro que a fase 0 já evitou.

- **D4 — A limpeza dos arquivos CCR do estágio ocorre no `fechar`, não no `colher`.** O estágio `colher` não existe: `fluxo-5-design-poda.md:67` ainda o cita, e `docs/rainforest/design/fluxo-7-design-recibo.md:104-108` já resolveu a mesma confusão para o recibo — "leia-se `fechar` onde o design escreveu `colher`". Correção textual apoiada em precedente, não invenção. **Esta decisão não depende do gate** e é aplicada nesta entrega.

- **D5 — A fase 1 fica mecanicamente inerte enquanto o gate de evidência da fase 0 estiver `FECHADO`.** O `poda.cjs` consultaria em runtime o mesmo cálculo de dias distintos que o `relatorio-poda.cjs` já expõe; com o gate fechado, o corpo da requisição seguiria byte-idêntico ao comportamento de hoje, mesmo com a chave de compressão (D6) ligada. É trava de desenho para quando a construção for autorizada — **não é, por si, autorização para construir**.

- **D6 — Kill switch dedicado da fase 1**: chave `poda-compactar` em `hooks/lib/config.cjs`, nascendo `padrao: false`, distinta da chave `poda` (fase 0, medição, `padrao: true` desde 2026-08-31 — `hooks/lib/config.cjs:128`, cuja descrição cobre só a escrita de métricas). Origem: R3 do design original.

- **D7 — A rubrica estruturada para portão manual (seção 4 do adendo) não é implementada.** A semente já foi avaliada e rejeitada por outro fluxo, fechado em 2026-09-04: `docs/rainforest/design/fluxo-12-regua.md`, D5 — "o `bar.md` não altera o veredito binário nem a lacuna única... rubrica pontuada é o modo de falha que a skill inteira evita". Esta decisão só registra o encerramento. **Não depende do gate** e é aplicada nesta entrega.

- **D8 — Nenhuma dependência do ecossistema LangChain, nenhum pacote externo e nenhuma chamada de LLM para sumarização entram na fase 1.** Origem: decisão literal do próprio adendo, seção "O que explicitamente não copiar".

- **D9 — A fase 1 exigiria bufferizar e reserializar o corpo da requisição antes de repassar ao upstream**, substituindo — só quando D5 e D6 permitirem — o caminho de streaming não-bufferizado que a fase 0 usa hoje (`scripts/poda.cjs:400-406`, `req.on('data')` → `proxyReq.write(chunk)`). A resposta (SSE) continuaria sem buffer e intocada, e a regra de ouro R1 não muda. É mudança arquitetural, não incremento — e esse custo é parte do que a evidência de 7 dias precisa justificar.

## Avaliado e descartado

- **Fixar 85% (gatilho de janela), 10% (retenção) e 5+5 (tamanho da prévia) como decisão fechada nesta entrega.** Descartado por ora. São números calibrados pelo deepagents num sistema diferente, e esta máquina não tem medição própria para confirmar, contestar, ou sequer dizer se o formato de dado que a fase 0 grava é compatível com o cálculo que eles pressupõem — o gate está em 0 de 7 dias e não existe `metricas.jsonl` real. Ficam em `## Em aberto`.

- **Construir a fase 1 agora, mecanicamente inerte até o gate abrir.** Descartado. Obedece à letra da regra R4 (nunca custa mais caro que a ausência), mas não ao "não abre" das duas frases do design original, que condicionam o investimento de engenharia, não só a ativação. O Risco 1 do design original justifica a leitura: compressão mal calibrada pode aumentar custo, e o R3 lembra que, se o cache hit já domina, ela pode nem precisar existir — nada disso é decidível sem dado real.

- **Rubrica pontuada como portão manual** — descartada por decisão herdada do fluxo 12 (D7).

- **`docs/rainforest/poda.json` como config numérica em árvore versionada** — já descartado na fase 0; o kill switch de fase 1 (D6) entra em `hooks/lib/config.cjs`, como os demais.

## Fora de escopo

- Fase 2 do design original (poda em fronteira de estágio) — este adendo não a toca.
- Resolver a Q2 do fluxo 8 (limiar de reinício de sessão) — o fluxo 8 tem a própria pergunta em aberto, e ela é de lá.
- Rodar a coleta de 7 dias de evidência — é uso do sistema por quem liga o proxy no dia a dia, não tarefa de código.
- Detecção automática do tamanho máximo de janela por modelo a partir do corpo da requisição.
- Generalizar a poda proativa para arrays JSON e diffs por tamanho — o design original só dá número para "log longo" (>200 linhas); os outros dois tipos não têm limiar decidido em lugar nenhum.

## Em aberto

- **Q1 — Adotar compactação reativa por ocupação de janela como mecanismo novo de fase 1**, além da poda proativa que o design original já decidiu? Recomendada: **esperar a evidência de 7 dias**. Razão: não existe design aprovado para esse mecanismo, e construí-lo sem saber como o contexto cresce na prática repete o Risco 1.

- **Q2 — Se Q1 for "sim": 85% da janela como gatilho?** Recomendada: **default provisório e configurável**, revisto assim que houver `metricas.jsonl` próprio. Razão: é prior razoável de um sistema comparável, mas hoje não há nada aqui para confirmá-lo ou contestá-lo.

- **Q3 — Retenção de 10% do histórico recente intacto?** Recomendada: igual à Q2 — default provisório, revisto com dado próprio.

- **Q4 — Prévia de 5+5 linhas no stub (D2)?** Recomendada: **adotar já**. Razão: é o único dos três números com risco baixo — o CCR sempre guarda o original inteiro, então errar aqui não compromete reversibilidade nem custo de token.

- **Q5 — (herdada do design original, `fluxo-5-design-poda.md:90`) `ANTHROPIC_BASE_URL` com conta por assinatura (OAuth) vs. API key: os headers autenticam nos dois modos?** Recomendada: **validar no ambiente real antes de reabrir a fase 1**. Razão: checagem barata, e não depende de dado acumulado.

- **Q6 — (herdada, `fluxo-5-design-poda.md:91`) contagem de tokens sem tokenizer.** Metade já tem resposta: o `contexto.json` grava `usage.input_tokens` real a cada resposta desde a fase 0, então não é preciso estimar o que já foi gasto. A outra metade segue aberta: **o tamanho máximo da janela por modelo não tem fonte automática neste repositório**, e sem ele "85% de quê" não tem denominador. Recomendada: quando a fase 1 reabrir, virar decisão explícita — valor por variável de ambiente, ou tabela por modelo mantida à mão —, nunca detecção automática inventada.

- **Q7 — (herdada, `fluxo-5-design-poda.md:92`) detecção do tipo de `tool_result`: pelo shape do conteúdo, ou correlacionando com o `tool_use` do turno anterior no mesmo corpo?** Recomendada: **correlacionar com o `tool_use`**. Razão: um array grande pode ser saída de `Bash`, `Grep` ou `Read`, com heurísticas de compressão diferentes, e o corpo da requisição já carrega essa informação no mesmo turno.

## Gancho de retorno

Um comando, um campo, um valor:

```
node scripts/relatorio-poda.cjs --json
```

Hoje devolve `{"gate":"FECHADO","dias_distintos":0,"faltam":7}` com exit 1. **Destrava
quando devolver `"gate":"ABERTO"`** — o que acontece com `dias_distintos >= 7` — e
sair com exit 0. É a única condição: nenhum outro arquivo do repositório declara uma
segunda pré-condição para abrir a fase 1. As sete perguntas acima não são
pré-condição do gate; são o que fica para decidir **depois** que ele abrir, com a
evidência na mão.

A partir daí, reabrir este adendo direto no `design` do fluxo 5 — a arqueologia já
foi feita em 2026-09-05 e não muda com o tempo; o que muda é só a saída do comando.
