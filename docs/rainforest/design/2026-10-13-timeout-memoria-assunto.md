# memoria-assunto-prompt dentro do timeout (#509, #507)

## Objetivo
O 1º pedido de cada sessão deixa de estourar o timeout do hook `memoria-assunto-prompt.cjs`
sob carga, atacando a causa medida (semeadura pelo transcrito) e não só o teto.

Medição de partida (Windows 11, 2026-10-13, banco com 14.373 observações): hook inteiro
1502 ms no 1º pedido contra 309–556 ms nos seguintes; `node -e ""` sozinho 137 ms. Na
semeadura, `acharAlvo` levou 60–190 ms por linha servida, 1667 ms para 14 linhas — cada
chamada refaz 3 consultas `LIKE` (dia −1, 0, +1) sem índice e formata ~530 candidatas de até
três jeitos. Leitura e parse dos 2 MiB do transcrito: 8 ms.

## Decisões fechadas
- **D1 — Cache por laço em `acharAlvo`** — `acharAlvo(conexao, linha, apelidos, cache)` aceita um objeto de cache opcional criado por quem chama; com ele, as candidatas de cada dia (observações e resumos) são consultadas e formatadas uma vez só e viram um mapa linha formatada → alvo, reaproveitado nas linhas seguintes do mesmo laço. Os dois chamadores (`memoriaDoPedido` no hook e `pontuarSessao` em `scripts/lib/utilidade.cjs`) passam o cache. Sem cache, o comportamento e a saída são os de hoje. — porquê: as 14 buscas viram 1 (estimativa ~150 ms); cache que vive só no laço não envelhece se o banco for gravado depois, o que um cache global por conexão (WeakMap) arriscaria.
- **D2 — Timeout de 5 para 10 s** — `hooks/hooks.json`, entrada do `memoria-assunto-prompt.cjs` no `UserPromptSubmit`. — porquê: folga para a partida do node sob carga, que varia mais de 2× entre rodadas; mesma correção já aplicada a um hook de `UserPromptSubmit` de outro plugin da máquina.
- **D3 — Hook continua síncrono** — sem `async`. — porquê: com `async` o contexto não chega ao pedido que o disparou, e é o único em que ele serve.
- **D4 — #507 no mesmo PR** — o caso de `hooks/testa-memoria-assunto-prompt.cjs` que exige `d1 < 1500` passa a exigir `d1` abaixo do timeout do hook lido do `hooks.json`; o que prova a não-releitura continua sendo o `d2` e o arquivo da sessão. — porquê: mesma causa e mesmo arquivo; o teto de 1500 ms media a máquina, não o hook.
- **D5 — Critério de pronto por contagem, não por relógio** — bateria nova: semear 14 linhas servidas do mesmo dia faz no máximo 3 consultas `LIKE` em `observacoes` (hoje 42), contadas por um wrapper de `conexao.prepare`; e as mesmas linhas devolvem os mesmos alvos com e sem cache. Mais a medição real antes/depois no host, colada no PR. — porquê: falsificável e rodável no CI sem depender da velocidade do runner; o critério manual da issue (20 prompts, 5 janelas) só confirmaria o que a contagem prova.

## Avaliado e descartado
- `async: true` no hook — descartado por D3 (contexto chegaria tarde demais).
- Só subir o timeout — o 1º pedido segue em ~1,5 s em repouso e escala com o número de linhas servidas; a carga ainda o empurra para o teto.
- Cache global por conexão (WeakMap) — `pontuarSessao` grava no mesmo banco; cache que sobrevive ao laço pode servir candidata velha.

## Fora de escopo
- Índice em `observacoes(criada_em)` ou troca do `LIKE` por faixa — muda schema/migração; com o cache a consulta roda 3 vezes por sessão, o ganho restante não paga a migração.
- Custo de partida do node e dos `require` (~15–260 ms) — não é desta causa.

## Varredura
docs/rainforest/varredura/2026-10-13-timeout-memoria-assunto.txt — achou a #507 (bateria do mesmo hook vermelha no CI pela 1ª chamada lenta, mesma causa), que entrou por D4; a #436/PR #459 (régua D7) explica por que `acharAlvo` tenta três formatos de linha, que o cache precisa preservar; a #243 (outro hook estourando timeout 5) é a mesma classe, já fechada.

## Em aberto
