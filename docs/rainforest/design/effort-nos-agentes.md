# Design — effort fixado no frontmatter dos agentes

Data: 2026-10-10. Enxerto B da comparação do `executar` com o orquestrador do
plugin `wildz-data` (Rafael Siqueira), decidido pelo Luís em 2026-10-09/10.

## Objetivo

O `Agent` não tem parâmetro `effort`: o subagente herda o effort da sessão que
despacha. Revisor e tester, que existem para julgar, rodam no effort que a
janela principal tiver naquele dia. O plugin do Rafael fixa `effort` no
frontmatter do agente (`plan-generator`: sonnet/high; `plan-evaluator-rubric`:
haiku/xhigh). O CLI instalado guarda o `effort` da definição junto do agente
escolhido no despacho (`effort:w.effort, … selectedAgent:w` no binário), e é
isso que este design usa.

## Decisões fechadas

- **D1 — Os agentes de julgamento levam `effort: high`.** `revisor`, `tester`,
  `depurador`, `auditor-de-seguranca`, `planejador`, `arqueologo`.
- **D2 — Os agentes mecânicos levam `effort: medium`.** `executor`,
  `documentador`, `resolvedor-de-build`.
- **D3 — Bateria por glob.** `scripts/testa-agentes-effort.sh` lê `agents/*.md`
  por glob e reprova agente sem `effort:`, com valor fora de
  `low|medium|high|xhigh|max`, ou com valor diferente do mapa D1/D2. Agente
  novo sem a linha reprova sozinho, como na `testa-agentes-folha.sh`.
- **D4 — Effort é teto por papel, não ordem fixa.** `CLAUDE_CODE_EFFORT_LEVEL`
  do operador continua tendo precedência (é o comportamento do harness, não
  algo que o plugin controle); o CHANGELOG diz isso.

## Avaliado e descartado

- `xhigh` para o revisor, como o avaliador do Rafael: descartado nesta rodada —
  o revisor é sonnet com método longo, e o custo dobraria sem medida que o
  justifique. Revê-se quando o laço D existir e houver número.
- Gravar effort no briefing: impossível, o `Agent` não aceita o parâmetro.

## Fora de escopo

O caminho Codex (`despachar-codex.cjs`), que mapeia effort por `model:` em
`config.cjs`; veredito em JSON (C); laço de iteração (D).

## Em aberto

Nada.

## Varredura

`docs/rainforest/varredura/effort-nos-agentes.txt` — termos `effort`,
`model: sonnet`, `model: haiku`. Os leitores do frontmatter achados são
`scripts/testa-agentes-folha.sh` (exige `disallowedTools`, proíbe `tools:`,
não restringe outras chaves) e `scripts/despachar-codex.cjs` (extrai só
`model:`); nenhum quebra com uma linha `effort:` a mais.
