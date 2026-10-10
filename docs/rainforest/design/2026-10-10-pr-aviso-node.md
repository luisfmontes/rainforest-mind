# Design: aviso de PR sem repetição e node absoluto na abertura

## Objetivo

Fluxo `2026-10-10-pr-aviso-node`. Fecha a #482 (o painel de PR acordou a sessão três vezes
para o mesmo conflito do PR #481) e a #480 (achados da revisão do fluxo
`2026-10-10-mods-faixa-compact`: a abertura do mod chama `node` pelo nome, e o localizador
não guarda o fracasso).

## Fatos medidos

- `hooks/pr-puro.mjs` `virada(velho, novo)` compara só com a leitura anterior; `motivoDe`
  traduz `mergeStateStatus: UNKNOWN` para "sem dado de merge". O GitHub devolve `UNKNOWN`
  enquanto recalcula, então conflito → sem dado → conflito conta como virada nova.
- `hooks/pr.tsx` grava `novo` em `prResumo` antes de calcular a virada; `eventos(velho, novo)`
  também registra "conflito → sem dado de merge" e a volta.
- `hooks/abertura-mod-puro.mjs:77` roda `['node', script, ...]`; `hooks/register.ts` monta o
  `Io` com `rodar` e `raiz`. `hooks/testa-mod-abertura.cjs` importa `register.ts` direto no
  Node (sem engine) e afirma `argv[0] === 'node'`; por isso o `register.ts` não pode importar
  módulo que dependa de `claude-code`.
- `caminhoDoNode` mora em `hooks/mod.tsx` (átomo `nodeCaminho`) e, sem `node` achado, refaz os
  dois localizadores (teto de 10 s cada) a cada uso.

## Decisões fechadas

- **D1 — Leitura sem dado de merge herda o motivo anterior**: `herdarMotivo(velho, novo)` em
`hooks/pr-puro.mjs`: quando `novo.motivo` é o rótulo de `UNKNOWN` e há `velho`, devolve `novo`
com o `motivo` de `velho`; o `mergavel` de `novo` não muda (fica `false`, o lado seguro). O
`pr.tsx` aplica antes de gravar, de calcular eventos e a virada. Com isso conflito → sem dado
→ conflito acorda uma vez só e o pane deixa de listar o vaivém.

- **D2 — A abertura acha o node ela mesma, com as mesmas funções puras**: `hooks/abertura-mod-puro.mjs`
roda `localizadores('node', SystemRoot)` + `escolherExecutavel` (de `hooks/pr-puro.mjs`, puro) uma vez por
abertura, dentro da montagem memoizada, com cwd na pasta do plugin; o `register.ts` passa
`systemRoot: () => $.env.get('SystemRoot')` no `Io`. Sem `node` achado nenhum gerador roda e a abertura sai
`null`, a falha aberta que já existe. (Revisto na execução: o desenho anterior, passar o `caminhoDoNode` do
`mod.tsx` como dependência, o engine recusa — "$ itself is passed as an argument".)

- **D3 — Fracasso do localizador fica guardado por 5 minutos**: átomo `nodeFalhouEm` (ms do
`$.clock.now()`); dentro de `NODE_FALHA_TTL_MS = 300_000` o `caminhoDoNode` devolve `null` sem
rodar processo. Passado o prazo, tenta de novo (o `node` pode ter sido instalado).

- **D4 — Versão e docs**: PATCH (1.58.1, ou o próximo livre na hora do merge). CHANGELOG diz o
que muda para quem usa; CONTRIBUTING, na seção do `node` absoluto, cita a abertura e o prazo.

## Avaliado e descartado

- **Herdar também o `mergavel`**: descartado; leitura sem dado não pode virar "mande mergear".
- **Mover `caminhoDoNode` para um módulo compartilhado importado pelo `register.ts`**:
  descartado; o módulo dependeria de `claude-code` e a bateria da abertura roda sem engine.
- **Passar o `caminhoDoNode` do `mod.tsx` ao `register.ts` como dependência**: descartado na execução;
  o engine não carrega o módulo ("$ itself is passed as an argument").
- **Cache negativo também na abertura**: desnecessário; a busca roda uma vez por abertura.
- **Cache negativo em variável de módulo**: descartado; o átomo segue o mesmo ciclo de vida do
  `nodeCaminho` e não vaza entre engines de teste.

## Fora de escopo

- Vaivém de checks durante re-run (`checks-falha`): medir antes; não apareceu no #481.
- #466 e #470 (painel de PR e "Deixado para depois").

## Varredura

docs/rainforest/varredura/2026-10-10-pr-aviso-node.txt — só a #480 e a #482 abertas sobre o tema; nenhuma outra Issue ou PR trata o vaivém de `UNKNOWN` ou o `node` da abertura.

## Em aberto

- Nada.
