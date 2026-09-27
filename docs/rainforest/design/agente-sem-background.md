# Subagente preso por bateria sem `timeout`: o perfil vira mecanismo

## Objetivo
Em 2026-09-27 o usuário viu, pela oitava vez, um agente parado na revisão. Medido nos
transcritos da sessão `fafafc3e` (fluxo zerar-issues-9): **10 de 14 subagentes** (4 revisores
e 6 executores) tiveram pelo menos um comando empurrado para segundo plano pelo harness. Em
quase todos o motivo é o mesmo: uma bateria (`testa-gate-*.sh`, `testa-estado.sh`,
`testa-saude.sh`, `testa-varrer-baterias.sh`, `varrer-baterias.sh`, `conferir-mutacao.cjs`)
rodada em primeiro plano **sem o parâmetro `timeout`** do Bash. Passados 2 minutos, o harness
joga o comando para segundo plano, o agente entrega o relato e continua na lista até a bateria
acabar. A varredura completa leva cerca de 29 minutos.

Desde 2026-09-25, `referencias/perfil-de-trabalho.md` (replicado nos `agents/*.md`) diz "Nada seu
fica rodando depois da resposta... `timeout` explícito". A regra está escrita e mesmo assim não é
seguida; a #192 já tinha medido a mesma coisa com a proibição de background. O design
`2026-09-25-busca-na-raiz` descartou "barrar bateria longa no hook" por não dar para saber a
duração antes de rodar. Este design não depende disso: não prevê a duração, **exige o parâmetro**.

## Decisões fechadas
- **D1 — Um hook `PreToolUse` de `Bash` nega, dentro de subagente (`agent_id` presente no payload), a execução de bateria sem `tool_input.timeout` maior que 120000** — porquê: é o gatilho medido. Com o `timeout` na chamada, o Bash espera até 10 minutos em primeiro plano em vez de empurrar para segundo plano. Conta como bateria a execução (por `bash`, `sh`, `node`, `./` ou caminho direto) de `testa-*.sh`, `testa-*.cjs`, `varrer-baterias.sh` ou `conferir-mutacao.cjs`, e `conferir-fluxo.cjs mutacoes`. **Ler** o arquivo (`cat`, `grep`, `sed`) não conta. A mensagem de bloqueio diz o valor a passar (`timeout: 600000`). Decidido pelo usuário em 2026-09-27 (opção a).
- **D2 — No mesmo hook, dentro de subagente, `varrer-baterias.sh` sem `--so` é negado mesmo com `timeout`** — porquê: a varredura completa (~29 min no CI) passa do teto de 10 minutos do Bash, então nem o `timeout` a segura em primeiro plano. A varredura completa passa a ser de quem integra; o agente roda `varrer-baterias.sh --so <bateria>` ou a bateria direto. Decidido pelo usuário em 2026-09-27 (opção a).
- **D3 — Só subagente; toggle `bateria-sem-timeout`, ligado por padrão e desligável por projeto** — porquê: mesma fronteira e mesma forma do `busca-na-raiz` e do `agente-folha`. A janela principal vê e para o que abriu.
- **D4 — O texto acompanha o mecanismo:** a linha "Nada seu fica rodando" de `referencias/perfil-de-trabalho.md` (e dos `agents/*.md` que a copiam) cita o gate; o "Não protege contra: bateria longa" de `hooks/gate-busca-raiz.cjs` aponta para ele; a seção "Critério que roda bateria carrega o placar" de `skills/executar/SKILL.md` diz que o laço inteiro é rodado pela integração, e o agente cola o placar das baterias que a tarefa toca — porquê: sem isso, a skill manda o agente fazer exatamente o que o gate nega.
- **D5 — Entrega: um PR, versão minor sobre `origin/main` (gate novo muda contrato), CHANGELOG e README (badge)** — porquê: formato das rodadas anteriores.

## Avaliado e descartado
- Só reforçar o texto do perfil: já está escrito desde 2026-09-25 e falhou em 10 de 14 agentes numa única sessão.
- Proibir `run_in_background` em subagente: é outro gatilho (#192) e não foi o medido aqui. Fica fora desta rodada.
- Prever a duração da bateria: impossível antes de rodar, e desnecessário, porque o parâmetro resolve.

## Fora de escopo
- Contorno deliberado: bateria chamada por variável (`for f in ...; do bash $f`), por script em arquivo ou por `bash -c` montado. O gate protege contra o esquecimento honesto, que é a forma medida. Ele lê separadores (`;`, `&&`, `||`, `|`, quebra de linha), envoltórios (`timeout N`, `time`, `env`, `nice`), `cd X &&` antes e redirecionamento/pipe depois. Corpo de heredoc é texto e não conta.
- Comando longo que não é bateria (o `python3 - <<EOF` do revisor 6, `npm test` num repo alheio). Não dá para reconhecer sem prever duração; o perfil de trabalho continua valendo para esses.

## Em aberto
Nada.
