# Jornada: prompt de máquina não conta como presença humana (#485)

## Objetivo
`scripts/jornada.cjs` passa a contar como presença só o que o usuário digitou. Hoje 73% das entradas que o filtro aceita são de máquina (1.503 de 2.047 em 3 dias de transcripts), e a madrugada vira jornada: o relógio da regra 8 avisou "jornada efetiva 9h12" com o usuário dormindo.

## Decisões fechadas
- **D1 — Critério de "humano" por lista de permissão em `mensagensHumanas()`.** Conta `origin.kind === "human"`. Quando `origin` está ausente (CLI antigo), cai na lista de exclusão: `entrypoint === "cli"`, `isSidechain` falso e prompt que não começa com `<task-notification>`. Os filtros atuais (`toolUseResult`, `isMeta`, `isCompactSummary`) continuam antes — porquê: o transcript já marca a origem (`origin.kind` = `human`, `task-notification`, `plugin`; `entrypoint` = `cli`, `sdk-cli`, `sdk-py`), então não se adivinha por texto. A lista de permissão falha para o lado seguro (subconta); lista de exclusão pura repetiria o defeito quando surgir um `origin.kind` novo.
- **D2 — `[Request interrupted by user]` conta como presença.** É o usuário apertando Esc, sem `origin` — porquê: ação humana real; cai no ramo de exclusão de D1 e passa (`entrypoint: cli`).
- **D3 — `node scripts/jornada.cjs` imprime "sinais de máquina descartados: N".** Porquê: se o filtro quebrar numa versão nova do CLI, o número zerado aparece em vez de a jornada mudar em silêncio.
- **D4 — O conserto fica só em `jornada.cjs`.** O relógio do mod já consome `mensagensHumanas()` e herda a correção — porquê: não há segunda fonte do filtro a sincronizar.
- **D5 — Critério falsificável para a entrega:** rodar `node scripts/jornada.cjs --dia 2026-10-10 --json` e o script da `origin/main` sobre os mesmos transcripts reais: `mensagens` antigo = `mensagens` novo + `maquina_descartadas`, `maquina_descartadas` > 0 e `efetiva_min` novo < antigo. (Emenda de 2026-10-13: a versão aprovada exigia a madrugada de 10/10 fora da jornada, premissa tirada da issue; os transcripts mostram que o usuário digitou de 00:00 a 01:12 naquela noite, então a madrugada em si não era toda de máquina.) e a bateria nova cobre uma fixture por origem (`human`, `task-notification`, `plugin`, `sdk-cli`, `sdk-py`, sem `origin` + `cli`, interrupção) com a mutação que reverte o filtro e a deixa vermelha.

## Avaliado e descartado
- **Filtrar por texto do prompt** (`<task-notification>`, "responda apenas"): descartado, o transcript tem `origin.kind` e `entrypoint`, que não dependem do que o prompt diz.
- **Lista de exclusão pura** (descartar `sdk-*`, `task-notification`, `plugin`): descartado, falha para o lado do defeito atual — qualquer `origin.kind` novo volta a inflar a jornada.

## Fora de escopo
- Mudar o corte de 55 min ou o limiar da regra 8: a #485 é sobre o que conta como sinal, não sobre quanto.
- Reescrever dias passados: `jornada.cjs` mede sob demanda, nada gravado a corrigir.
- Mudar o relógio do mod: herda o conserto (D4).

## Varredura
docs/rainforest/varredura/2026-10-13-jornada-presenca-humana.txt — só a própria #485 casa; nenhum PR ou branch prévio tocou o filtro (#389 e #390 trouxeram o relógio, que consome o filtro sem alterá-lo). Mudou nada no design.

## Em aberto
- Briefing de subagente em worktree e prompt de loop/wakeup: nos transcripts medidos não apareceu nenhuma entrada `isSidechain` verdadeira, e a origem do wakeup não foi isolada. D1 os cobre por exclusão (`origin.kind` ≠ `human`), mas a fixture de D5 deve usar um prompt de wakeup real se o executor achar um.
