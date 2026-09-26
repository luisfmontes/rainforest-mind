# Agente despachado é folha: não despacha agente

## Objetivo
Nenhum subagente despacha outro agente: os 9 agentes do plugin perdem a
ferramenta `Agent`, a portaria nega `Agent` vindo de dentro de qualquer
subagente, e a janela confere o roster antes de declarar uma rodada pronta.
Fecha a classe dos incidentes de 2026-09-04 (revisor com quatro sub-revisores
pendurados, ~243k tokens) e 2026-09-23 (avaliador `general-purpose` com dois
teammates no roster por ~2h).

## Decisões fechadas
- **D1 — Revisor e auditor são folha: nunca despacham; review grande se particiona em quem despachou** — porquê: nos dois incidentes o sub-despacho só trouxe custo e órfão, e o veredito saiu certo sozinho; particionar é papel de quem vê o todo e pode parar agente. Decidido pelo usuário em 2026-09-24.
- **D2 — Folha vale para os 9 agentes do plugin, e todo briefing a agente nativo do harness (`general-purpose`, `Explore`) leva a linha "não despache agente"** — porquê: nenhum dos 9 despacha hoje (conferido por grep em `agents/*.md` em 2026-09-24), então travar todos não tira nada; o incidente de 2026-09-23 veio de um nativo, cujo frontmatter o plugin não edita. Decidido pelo usuário em 2026-09-24.
- **D3 — Regra 10 ganha o fechamento de rodada: antes de declarar pronta uma rodada com agentes em paralelo, a janela roda `ListAgents` e para o que ela mesma abriu e sobrou** — porquê: em 2026-09-23 a janela não conferiu e quem viu o agente travado foi o usuário; folha reduz o risco, não zera — rodada de topo também deixa sobra. Decidido pelo usuário em 2026-09-24.
- **D4 — Duas camadas: `disallowedTools: Agent` no frontmatter dos 9 agentes, e a portaria nega `Agent` quando o payload do `PreToolUse` traz `agent_id`** — porquê: o frontmatter tira a ferramenta do agente (nem tenta, nem gasta turno); a portaria cobre os nativos, fazendo da linha do briefing (D2) reforço e não barreira única. Fatos da doc oficial (`hooks.md`: `agent_id`/`agent_type` só presentes dentro de subagente; `sub-agents.md`: `disallowedTools` remove do pool herdado), a confirmar ao vivo na primeira tarefa do plano. Decidido pelo usuário em 2026-09-24.
- **D5 — Folha com trabalho grande demais faz sozinha e, se não cobrir tudo, devolve parcial com a lista explícita do que não conferiu** — porquê: parcial com lacuna nomeada é útil e deixa a quem despachou decidir particionar o resto; devolver só uma proposta de partição queima uma rodada inteira de agente por um plano. Decidido pelo usuário em 2026-09-24.
- **D6 — A negação da portaria tem toggle `agente-folha`, ligado por padrão e desligável por projeto** — porquê: a portaria roda em todo projeto das duas contas; projeto que precise de aninhamento legítimo (workflow, por exemplo) desliga sem release nova — mesma forma do `contrato-veredito`. Decidido pelo usuário em 2026-09-24.

## Avaliado e descartado
- Sub-revisores com partição determinística do change-set e timeout por subtarefa (open-code-review, `grouping.go:22` e `agent.go:674,734-808`): resolve a espera indefinida, mas mantém o custo e o órfão que os dois incidentes mostraram sem ganho de qualidade medido — o veredito sozinho saiu certo nas duas vezes.
- `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` no `settings.json` das duas contas: configuração do usuário mantida em sincronia à mão entre duas config dirs — a mesma deriva que tirou as regras da CLAUDE.md para o plugin em 2026-08-10; e o plugin não altera o ambiente do usuário (regra 15).
- Folha devolver só a proposta de partição (D5).

## Fora de escopo
- Guarda de profundidade por nome de coordenador (oh-my-openagent `isCoordinatorAgent`, `delegate-task/constants.ts:405-415`): aqui não há agente coordenador — quem coordena é a janela principal.
- O que o harness faz com filho vivo quando o pai termina: não documentado; D3 cobre pelo lado da janela.
- Agentes de outros plugins (ex.: `protheus`): o frontmatter é deles; a portaria (D4) os cobre quando o toggle está ligado.

## Em aberto
