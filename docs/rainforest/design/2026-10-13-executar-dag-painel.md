# executar: DAG com camadas, retomada por sentinela e painel do fluxo

## Objetivo
O `executar` deixa de depender de `paralela:` marcado à mão: as camadas saem do `depende de:` do plano, com recusa de ciclo, de dependência inexistente e de arquivo compartilhado na mesma camada. Cada tarefa ganha estado próprio, com a integração provada por um trailer git, e uma sessão nova retoma um `executar` pela metade sabendo o que re-marcar e o que redespachar. Um painel HTML local mostra o fluxo para quem não está olhando.

Enxertos F e G do wildz-data 1.0.126 (Rafael Siqueira): `scripts/plan_state.mjs` (`layers`, `resume`, `_latestCommittedAcceptedIteration`), `skills/execute/SKILL.md` e `scripts/render_artifacts.mjs`. As decisões D1 a D8 são as recomendações da rodada 1, aceitas pelo Luís em 2026-10-13 ("segue como recomendado").

## Decisões fechadas
- **D1 — Quem usa: a sessão que orquestra o `executar`, ao despachar (que camada vai agora) e ao retomar numa sessão nova depois de queda, compactação ou troca de conta (o que já entrou, o que redespachar); o painel serve ao Luís quando um `executar` longo roda sem ele olhando** — porquê: hoje a retomada se faz lendo o `git log` à mão.
- **D2 — As camadas são calculadas do `depende de:` (Kahn); `paralela:` deixa de ser exigido, e plano antigo que ainda o traz passa com aviso, sem recusa — inclusive o conflito de arquivo do D3 entre tarefas da mesma camada em que alguma declara `paralela: nao`, que vira aviso (`paralela: sim` com arquivo em comum continua recusa, como já era) (emenda do executar, 2026-10-13: planos de 2026-08 serializavam por `paralela: nao`, sem `depende de:`)** — porquê: dois lugares dizendo a mesma coisa divergem, e o `paralela:` manual já precisou de regra própria (D14 da cobertura) para concordar com o `depende de:`.
- **D3 — A cobertura recusa: ciclo, `depende de:` citando tarefa inexistente, e duas tarefas da mesma camada com `arquivos:` em comum; a mensagem nomeia as tarefas** — porquê: o conflito de arquivo só era pego entre tarefas marcadas `paralela: sim`; medido por camada, pega o que a marcação esqueceu.
- **D4 — Estado por tarefa em três valores: `pendente` (nunca despachada), `em_voo` (agente despachado, registrado em `em_voo`) e `integrada` (existe na branch do fluxo um commit com o trailer `Rainforest-Tarefa: <slug>#<n>`); o trailer é a sentinela, e o JSON de estado nunca é a fonte da verdade da integração** — porquê: verdade em disco que a sessão não declara sem ter feito, o equivalente do `iter-N.committed` do wildz-data.
- **D5 — `estado.cjs retomar --slug <slug>` lê git e estado e devolve: tarefa com trailer e não contada no estado → re-marcar; tarefa em `em_voo` sem trailer → redespachar do zero; e a próxima camada com o que falta. A ordem da integração fica fixa: conferência (`conferir-entrega` e mutação) → commit com trailer → `marcar`** — porquê: é o `resume` do wildz-data (`re-mark`/`redispatch`/`next_task`), com commit no lugar de arquivo.
- **D6 — Painel HTML local em `<dados>/fluxos/<slug>/painel.html`, regenerado pelo `estado.cjs` a cada `marcar` de `executar`, `revisar` e `verificar`, com um cartão por tarefa (estado, camada, iteração do laço, veredito); a notificação no teto, no `flaky` e no fim fica com a sessão (`PushNotification`), escrita na skill** — porquê: hook não notifica, e publicar Artifact a cada mudança de status custaria uma publicação por evento.
- **D7 — Um fluxo só: DAG e retomada primeiro, painel na última tarefa; se o painel crescer, sai para fluxo próprio** — porquê: o painel lê o estado por tarefa do D4.
- **D8 — Modelo de ameaça da recusa de camadas: protege contra plano com ciclo ou dependência inexistente e contra duas tarefas da mesma camada declarando o mesmo arquivo; fica fora a tarefa que toca arquivo que não declarou (o `creep` do `revisar` pega) e a dependência real que não foi escrita no plano** — porquê: a recusa confere a declaração, não adivinha dependência implícita.

## Avaliado e descartado
- Sentinela em arquivo (`iter-N.committed`, como no wildz-data): aqui a integração já é um commit na branch do fluxo; um arquivo ao lado seria segunda fonte que pode divergir do git.
- Painel como Artifact publicado: uma publicação por mudança de status, com rede e aprovação no caminho do `marcar`.

## Fora de escopo
- Despachar sozinho a próxima camada: a sessão continua despachando; o `retomar` só diz o quê.
- Inferir dependência pelo conteúdo das tarefas (D8).
- Notificação disparada por hook.

## Varredura
docs/rainforest/varredura/2026-10-13-executar-dag-painel.txt — termos `depends_on`, `touches`, `retomada`, `sentinela`, `painel`, `camadas`. Nenhuma Issue ou PR sobre camadas ou retomada do `executar`; os casamentos são do sentinela de backup (#118, #150), do painel do `/saude` (#20, #34) e da retomada de agente por `SendMessage` (#181), sem relação. As ideias `executar-dag-touches-e-retomada` e `painel-do-fluxo-html` são a origem; o veredito gravado por hook (contrato de 2026-09-23) cumpre o gancho de F.

## Em aberto
