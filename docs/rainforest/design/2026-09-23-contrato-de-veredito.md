# Contrato de veredito de uma linha no revisar

## Objetivo
O veredito do `revisar` deixa de passar pelo relato de quem despacha: o revisor
termina com uma linha fechada, um hook a grava direto da saída dele, e o
`estado.cjs` só aceita `ok` ou `reprovado` que batam com o que foi gravado.
Depois de três reprovações seguidas, a quarta rodada é decisão do usuário, com
o impasse escrito.

## Decisões fechadas
- **D1 — A exigência mora em hook `SubagentStop` + trava no `estado.cjs`** — porquê: o `SubagentStop` traz `agent_type` e `last_assistant_message` e dispara também para agente em background (doc `hooks.md` e `sub-agents.md`, conferido em 2026-09-23); só texto no `agents/revisor.md` é contrato sem catraca, e parâmetro no `estado.cjs` continua sendo o relato de quem despacha — o buraco da ideia `reprovado-sem-diff-deixa-achado-auto-relatado`.
- **D2 — Última linha exata `VEREDITO: ok` ou `VEREDITO: reprovado`** — porquê: análise antes do veredito é ordem que sustenta o resultado (open-code-review `agent.go:1567-1574`); mesma extração do `segunda-opiniao.cjs` (última linha com conteúdo, após trim, vocabulário fechado), que se reaproveita em vez de reinventar.
- **D3 — Sem a linha, ou fora do vocabulário, a revisão não existe** — porquê: tratar como reprovado inventaria um veredito que ninguém deu; `marcar revisar` recusa e pede revisão nova.
- **D4 — Teto de 3 reprovações por fluxo; a 4ª rodada exige impasse escrito e decisão do usuário** — porquê: "a flagged disagreement beats a false approved" (claudex-loop `codex-review/SKILL.md:117`); o fluxo `2026-09-23-memoria-sinal-de-utilidade` levou 4 rodadas, cada reprovação com defeito real — o teto não manda parar, torna a 4ª decisão dele.
- **D5 — O slug vem da linha `Slug: <slug>` do briefing do revisor** — porquê: o evento não traz slug; mesma forma das linhas `Runtime:` e `Sensor:`; o hook a lê da primeira mensagem do transcrito do subagente (`agent_transcript_path`). Revisor sem `Slug:` (revisão avulsa) não grava nem trava.
- **D6 — Revisores em paralelo: `ok` exige todos os vereditos gravados desde o último `exigir revisar` iguais a `ok`** — porquê: "vale o último" deixaria um reprovado ser coberto por um ok que chegou depois.
- **D7 — A 4ª rodada se libera com `docs/rainforest/portoes/<slug>-impasse.md` + `exigir revisar --rodada-extra "<o que o usuário disse>"`, gravado no log** — porquê: a trava não prova que o usuário falou, mas impede passar da 3ª sem rastro auditável; frase-senha por sessão foi abolida na portaria (regra 10).
- **D8 — `achados: N` continua informado por quem marca** — porquê: contar achados em prosa é frágil, e o que a ideia irmã pedia (reprovado não depender do relato) fica coberto por D9.
- **D9 — `marcar revisar reprovado` também exige veredito `reprovado` gravado; o teto de D4 conta vereditos gravados, não marcações** — porquê: sem simetria, quem despacha ainda reabre o `executar` sem revisor nenhum ter dito nada.

## Avaliado e descartado
- Veredito por tool-call mutuamente exclusiva (open-code-review `agent.go:1558-1608`): exige ferramenta própria do subagente; a linha fechada + hook dá a mesma garantia sem MCP novo.
- Veredito na primeira linha (como os briefings desta sessão pediram): inverte a ordem análise → veredito.
- Linha `ACHADOS: N` obrigatória (D8).

## Fora de escopo
- `segunda-opiniao.cjs` (já tem contrato próprio, `concordo|discordo`).
- Contrato de veredito para `tester` ou outros agentes.
- Partição determinística do change-set e timeout por sub-revisor (peças 4-5 do open-code-review) — ideia `revisor-que-despacha-sub-revisores-nomeados`.

## Em aberto
