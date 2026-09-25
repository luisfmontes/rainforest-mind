# Subagente preso por comando em segundo plano

## Objetivo
O usuário viu o sexto revisor "travado" em 2026-09-25. O agente já tinha terminado, mas deixou vivo um comando que ele mesmo disparou e que o harness empurrou para segundo plano ao estourar os 2 minutos do Bash. Enquanto esse comando vive, o agente não sai da lista. Medido nas duas contas nos 14 dias até 2026-09-25: 34 de 113 execuções de revisor tiveram comando empurrado para segundo plano. Os casos se dividem em dois tipos:
- `find` a partir da raiz do disco (`find / -iname accounts.json`, `find / -iname ideias.jsonl`, `find / -maxdepth 6 ...`), que não termina em tempo útil no Windows e prende o agente por horas. O de 2026-09-25 ainda ia dar `cat` no `accounts.json` real, com os JIDs.
- Bateria longa (`testa-estado.sh`, `conferir-mutacao.cjs`, `testa-saude.sh`) que passa dos 2 minutos e termina sozinha depois: atrasa o fim do agente, mas não o prende.

## Decisões fechadas
- **D1 — Um hook `PreToolUse` de `Bash` nega, dentro de subagente (`agent_id` presente no payload), todo `find` cujo ponto de partida seja a raiz do disco: `/`, `/c`, `C:/`, `C:\` e as variantes, com ou sem `-maxdepth`** — porquê: é o tipo que prende por horas; dois dos casos medidos tinham `-maxdepth 6` e `-maxdepth 2` e ficaram presos do mesmo jeito, então o limite de profundidade não serve de saída. A mensagem manda procurar no caminho conhecido (a pasta de dados, `~/.whatsapp-mcp/`, o repositório). Decidido pelo usuário em 2026-09-25 (opção a); o "com ou sem `-maxdepth`" veio da medição, depois da proposta.
- **D2 — Só subagente. A janela principal segue livre** — porquê: a janela vê e para o que abriu, e o incidente é o do agente que termina e deixa o comando vivo. Mesma fronteira do `agent_id` que a folha (`2026-09-24-revisor-folha`) usa.
- **D3 — Toggle `busca-na-raiz`, ligado por padrão e desligável por projeto** — porquê: mesma forma do `agente-folha` e do `contrato-veredito`, para um projeto com necessidade legítima desligar sem release nova.
- **D4 — O perfil de trabalho dos agentes (`referencias/perfil-de-trabalho.md`, aplicado aos `agents/*.md` pelo `perfil.cjs`) ganha uma linha: comando que pode passar de 2 minutos roda com `timeout` explícito na chamada do Bash (até 600000), nunca indo para segundo plano, e o agente não entrega a resposta final com comando seu ainda rodando** — porquê: cobre o segundo tipo, que o hook não tem como distinguir antes de rodar. Decidido pelo usuário em 2026-09-25 (opção a).

## Avaliado e descartado
- Só a linha no perfil, sem hook: o `find /` já contrariava o bom senso e aconteceu em cerca de 8 execuções.
- Aceitar `find /` com `-maxdepth` baixo: medido, não resolve (D1).
- Barrar bateria longa no hook: não dá para saber antes de rodar quanto ela vai durar; o `timeout` explícito (D4) resolve sem proibir.

## Fora de escopo
- `grep -r` e buscas longas em pastas grandes que não são a raiz: não apareceram prendendo agente na medição.
- O payload do `PreToolUse` de `Bash` dentro de subagente: a presença de `agent_id` já foi confirmada ao vivo para `Agent` (`docs/rainforest/pesquisas/2026-09-24-revisor-folha-payload.md`), e a doc de hooks dá os mesmos campos comuns para toda ferramenta. A fixture deriva dessa captura trocando só `tool_name` e `tool_input`.

## Em aberto
