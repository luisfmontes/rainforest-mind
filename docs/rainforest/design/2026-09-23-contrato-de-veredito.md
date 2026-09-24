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
- **D7 — A 4ª rodada se libera com `docs/rainforest/portoes/<slug>-impasse.md` + `liberar --estagio revisar --rodada-extra "<o que o usuário disse>"`, gravado no estado** — porquê (emenda do plano, 2026-09-23: quem recusa a 4ª rodada é o `exigir executar` via `TETO_TENTATIVAS`, que já existe e se destrava por `liberar`; flag em `exigir revisar` não destravaria nada): a trava não prova que o usuário falou, mas impede passar da 3ª sem rastro auditável; frase-senha por sessão foi abolida na portaria (regra 10).
- **D8 — `achados: N` continua informado por quem marca** — porquê: contar achados em prosa é frágil, e o que a ideia irmã pedia (reprovado não depender do relato) fica coberto por D9.
- **D9 — `marcar revisar reprovado` também exige veredito `reprovado` gravado; o teto de D4 conta vereditos gravados, não marcações** — porquê: sem simetria, quem despacha ainda reabre o `executar` sem revisor nenhum ter dito nada.
- **D10 — `verificar` reprovado devolve também o `revisar` a `pendente`** — porquê: hoje a reprovação reabre só o `executar` e o `revisar` fica `ok`, então a mudança nova segue para o `verificar` sem revisão, e `marcar executar parcial` é recusado ("executar nao pode voltar a parcial com revisar em ok") — visto no fluxo `2026-09-23-memoria-sinal-de-utilidade` em 2026-09-23. Decidido pelo usuário em 2026-09-23 entrar neste fluxo, por ser o mesmo arquivo e a mesma trava.
- **D11 — Com `contrato-veredito` desligado, as travas de `marcar revisar` tratam o fluxo como sem contrato (só aviso)** — porquê: a revisão de 2026-09-23 achou que o `exigir revisar` arma a janela mesmo com o toggle desligado e o hook deixa de gravar — o `revisar` fica infechável, com recusa que manda rodar um revisor que não resolve.
- **D12 — O subcomando `veredito` exige `--transcrito <caminho>` e confere no arquivo: dentro de `.../subagents/`, primeiro prompt com o `Slug:` do fluxo, última linha do revisor igual ao veredito** — porquê: sem isso, a sessão que despacha grava `ok` à mão e o contrato volta a ser o relato dela (achado 2 da revisão); forjar passa a exigir fabricar um transcrito, auditável. Decidido pelo usuário em 2026-09-23.
- **D13 — `Slug:` errado no briefing é risco residual aceito e documentado** — porquê: D12 já exige o slug no transcrito real; amarrar ao diff revisado (`Head:` no briefing) é outro contrato. Decidido pelo usuário em 2026-09-23.
- **D14 — O transcrito que confirma o veredito tem de estar na pasta real de projetos do Claude (`<home>/.claude*/projects/<projeto>/<sessao>/subagents/agent-<agent_id>.jsonl`, com o `.meta.json` irmão de `agentType` revisor), e o caminho fica gravado no veredito; o contrato barra o atalho por hábito, não quem forja de propósito com acesso ao disco** — porquê: a segunda revisão (2026-09-23) forjou um `ok` com duas linhas numa pasta `subagents` qualquer em `$TEMP`; toda checagem por arquivo é forjável por quem escreve no disco, então o que se controla é o custo e o rastro — forjar passa a exigir escrever entre os transcritos reais, e o caminho gravado deixa a forja visível. Decidido pelo usuário em 2026-09-24.
  Emenda de 2026-09-24 (3ª revisão, impasse `portoes/2026-09-23-contrato-de-veredito-impasse.md`): a pasta de conta é **a config dir em uso** (`CLAUDE_CONFIG_DIR`, ou `~/.claude` sem ela), não qualquer `~/.claude*` — uma árvore inventada `~/.claude-x/` passava. Decidido pelo usuário em 2026-09-24.

## Avaliado e descartado
- Veredito por tool-call mutuamente exclusiva (open-code-review `agent.go:1558-1608`): exige ferramenta própria do subagente; a linha fechada + hook dá a mesma garantia sem MCP novo.
- Veredito na primeira linha (como os briefings desta sessão pediram): inverte a ordem análise → veredito.
- Linha `ACHADOS: N` obrigatória (D8).

## Fora de escopo
- `segunda-opiniao.cjs` (já tem contrato próprio, `concordo|discordo`).
- Contrato de veredito para `tester` ou outros agentes.
- Partição determinística do change-set e timeout por sub-revisor (peças 4-5 do open-code-review) — ideia `revisor-que-despacha-sub-revisores-nomeados`.

## Em aberto
