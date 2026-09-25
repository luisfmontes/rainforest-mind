# Veredito do revisor fora da última linha exata

## Objetivo
O contrato de veredito (`2026-09-23-contrato-de-veredito`) grava `invalido`
sempre que a última linha do revisor não é exatamente `VEREDITO: ok|reprovado` —
e isso aconteceu em quase metade das revisões reais com a intenção clara. O hook
passa a devolver a vez ao revisor para ele escrever a linha, e a extração aceita
o negrito em volta dela.

## Decisões fechadas
- **D1 — Quando a última linha não é veredito válido, o hook do `SubagentStop` bloqueia a parada do revisor (`decision: "block"`) com o motivo "termine com a linha exata `VEREDITO: ok` ou `VEREDITO: reprovado`", e o próprio revisor escreve a linha** — porquê: medido em 2026-09-25 nas 17 revisões cujo briefing pedia a linha: 9 exatas no fim, 1 em negrito, 7 com o veredito na primeira linha ou no meio e texto depois, 0 sem veredito. O veredito continua sendo do revisor, na forma exata, e custa um turno só quando ele erra. O comportamento do bloqueio vem da doc do `SubagentStop`; a primeira tarefa do plano o confirma ao vivo. Decidido pelo usuário em 2026-09-25.
- **D2 — A extração aceita negrito, sublinhado ou crase em volta da linha (`**VEREDITO: ok**`), e só isso** — porquê: a marcação em volta não deixa ambiguidade e aceitar poupa o turno do bloqueio; procurar o veredito em qualquer posição não entra — na primeira linha ele inverte a ordem análise → veredito (D2 do contrato), e no meio pode ser citação. A marcação de um lado só (`**VEREDITO: ok`) também passa: a regra tira a marcação de cada ponta, sem exigir par, e o texto entre as pontas continua tendo de ser exato. Decidido pelo usuário em 2026-09-25.
- **D3 — No segundo erro (payload com `stop_hook_active: true`) o hook não bloqueia de novo: grava `invalido`, como hoje** — porquê: uma segunda chance basta; bloquear sem limite prende o subagente em laço, e o `invalido` segue auditável. Decidido pelo usuário em 2026-09-25.
- **D4 — A tolerância de D2 mora na função compartilhada `scripts/lib/extrair-veredito.cjs`, então vale também para o `concordo|discordo` do `segunda-opiniao.cjs`** — porquê: mesmo defeito, mesma função; duas regras de extração é como uma delas fica para trás. Decidido pelo usuário em 2026-09-25.
- **D5 — O bloqueio segue as fronteiras do contrato atual: só revisão com `Slug:` (a avulsa não grava nem bloqueia) e só com o toggle `contrato-veredito` ligado** — porquê: é o mesmo contrato ganhando uma segunda chance, não um contrato novo; toggle próprio seria uma chave a mais sem caso de uso. Padrão do contrato existente, registrado aqui para não ficar suposto.

## Avaliado e descartado
- Aceitar a linha do veredito em qualquer posição: D2.
- Só reforçar o texto do `agents/revisor.md`: o texto já pede a última linha, e o briefing de cada revisão repetia o pedido — 7 de 17 erraram mesmo assim.
- Bloquear sem limite: D3.

## Fora de escopo
- Mudar o vocabulário (`ok|reprovado`) ou o formato da linha.
- Contrato de veredito para outros agentes (`tester`).

## Em aberto
