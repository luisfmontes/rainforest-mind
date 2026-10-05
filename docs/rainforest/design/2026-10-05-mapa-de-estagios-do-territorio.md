# Contrato do mapa de estágios do território

## Objetivo

Definir como um plugin de território declara, por estágio do fluxo, os agentes de outro plugin
que devem ser despachados, as skills e as tools de MCP que devem ser consultadas e os comandos
com exit code que devem ser rodados — e como as skills do rainforest leem essa declaração. Aqui
mora só o contrato genérico; o mapa de cada linguagem mora no plugin do território (D7 do design
de 2026-08-28).

## Contexto medido

- **Benchmark D6, rodada 2.** Sem mapa, o braço "rainforest + plugin de domínio" empatou com o
  plugin de domínio sozinho (N=2, júri cego de 3), chegou ao fim nas duas rodadas e saiu mais
  barato. Mas a combinação aconteceu por iniciativa do modelo: ele consultou o MCP do domínio
  algumas vezes e **não despachou nenhum agente** do outro plugin.
- **Teste de despacho, 2026-10-05.** O agente implementador do plugin de domínio funciona como
  subagente comum, devolvendo `DONE` sem Agent Teams. Mas ele não enxerga as tools de MCP, porque
  o `tools:` explícito do frontmatter as corta (issue aberta no repositório daquele plugin).
- **A portaria registra e não barra agente de outro plugin** (#264, fechada). O despacho cruzado
  já é permitido; o que falta é alguém mandar despachar.

## Decisões fechadas

- **D1 — A declaração é um manifesto `territorio.json` na raiz do plugin de território, e é ele que manda.** Comandos e despachos ficam no JSON; o conhecimento fica nas skills do território, que o JSON só aponta, sem copiar conteúdo — porquê: comando com exit code e "despache o agente X" precisam ser verificáveis por script, e duplicar conhecimento envelhece (Q4 do design de agosto).
- **D2 — Cada skill de estágio lê o mapa por `node scripts/territorio.cjs estagio <nome>`.** O script resolve o território do repositório e imprime o bloco daquele estágio — porquê: a injeção por hook de abertura é cortada pelo teto de entrega (~2,2 KB de 32 KB chegavam), e deixar o modelo procurar sozinho foi o que o benchmark mostrou não acontecer.
- **D3 — Descoberta em duas camadas: a regra de detecção do manifesto casa com o repositório, e um apontamento do próprio repositório (`.rainforest/territorio`) vence quando existe** — porquê: a detecção cumpre o D2 de agosto (`semear`/`setup` reconhecem o repo), e o apontamento resolve repositório misto sem adivinhar.
- **D4 — Por estágio, o mapa diz se o agente do território substitui o papel do rainforest ou soma a ele** — porquê: executar é naturalmente substituição (um só escreve o código), e revisar é naturalmente soma (revisor do rainforest em paralelo com os revisores do domínio).
- **D5 — Cada item do mapa é `obrigatorio` ou `opcional`, com `opcional` como padrão.** Opcional ausente (plugin desabilitado, agente inexistente, MCP fora do ar) volta para o papel padrão do rainforest e se anuncia em uma linha (regra 14); obrigatório ausente faz o estágio parar — porquê: comando de verificação tem que ser obrigatório, senão o `verificar` passa sem provar nada; agente e MCP não, porque o fluxo funcionou sem eles no benchmark.
- **D6 — Comandos usam variáveis (`{arquivo}` e as que o território declarar), resolvidas por um config local do usuário. Variável sem valor faz o `territorio.cjs` sair com exit ≠ 0 nomeando a variável** — porquê: o plugin é compartilhado e não pode carregar caminho de máquina; falhar dizendo o que falta é melhor que rodar comando quebrado.
- **D7 — O config local mora em `~/.rainforest/territorios/<nome>.json`, por máquina e fora de qualquer repositório** — porquê: é onde o rainforest já guarda os dados de cada usuário, o caminho de máquina não chega a commit por engano, e variável de ambiente esbarraria na regra 15.
- **D8 — Quem consulta o MCP é declarado por agente; o padrão é o orquestrador consultar as tools do estágio e entregar o resultado no briefing** — porquê: hoje o subagente do domínio não enxerga o MCP; quando o outro plugin corrigir, um campo no mapa troca isso sem mudar o contrato.
- **D9 — O estado do trabalho registra o que o território rodou em cada estágio (agentes, tools de MCP, comandos), e o `marcar` recusa com exit 2 quando falta evidência de um item obrigatório** — porquê: opcional é registro (regra 10, declaração não é portão); obrigatório sem saída é o "✅ sem comando" da regra 12.
- **D10 — O contrato sai como `versao_contrato: 0`, experimental, validado pelo território real que existe hoje e por um território sintético nos testes. Vira v1 quando o segundo território (D4 de agosto) o implementar** — porquê: o contrato nasce por extração (D1 de agosto), e o território sintético impede que a forma do primeiro território vire a forma do contrato (D5 de agosto).
- **D11 — O aceite é uma 3ª rodada do benchmark, num chamado novo: combinado com mapa contra combinado sem mapa. Critério: os agentes declarados aparecem despachados no transcript, a qualidade no júri cego não cai, e o custo não sobe mais de 30%** — porquê: suíte verde não prova que o mapa muda o comportamento, e o benchmark já pegou uma promessa uma vez.
- **D12 — Esta entrega liga quatro estágios: brainstorm (consultas), executar, revisar e verificar. Arqueologia e plano entram numa entrega curta depois, pelo mesmo mecanismo** — porquê: são os quatro em que o benchmark e o teste mostraram a lacuna.
- **D13 — Esta entrega é o contrato, o `territorio.cjs`, as quatro skills ligadas e o território sintético. O mapa do território real é escrito no repositório dele, depois que a frente em curso lá fechar, e o aceite (D11) roda quando os dois existirem** — porquê: um mapa escrito antes do contrato publicado teria de ser refeito, e o conteúdo do território não pode morar neste repositório público.

## Avaliado e descartado

- **Agent Teams como forma de orquestrar:** o teste de 2026-10-05 mostrou que o agente do domínio funciona como subagente comum; Agent Teams mantém os colegas vivos e não dá estado, portões nem registro. Fica disponível só para um agente que precise conversar no meio da tarefa, e isso não apareceu.
- **Injetar o mapa pelo hook de abertura:** medido em 2026-08-10, o teto de entrega cortava o payload (50 de 50 sessões receberam ~2,2 KB de 32 KB).
- **Deixar o modelo descobrir os agentes do outro plugin sozinho:** no benchmark, com os dois plugins habilitados, foram zero despachos em duas rodadas.

## Fora de escopo

- O mapa do território real e as variáveis dele (moram no repositório do território, D7 de agosto).
- Corrigir o acesso ao MCP no agente do outro plugin (issue aberta lá; aqui só o campo de D8).
- Ligar arqueologia e plano (D12, entrega seguinte).
- O segundo território (promove o contrato a v1, D10).

## Varredura

docs/rainforest/varredura/2026-10-05-mapa-de-estagios-do-territorio.txt — nenhuma Issue, PR, branch ou commit implementa mapa de estágios ou `territorio.json`. Achou a #264 (fechada): a portaria deixou de barrar agente de outro plugin e passou a só registrar, então o despacho cruzado que este contrato manda fazer já é permitido. Achou também os PRs #217 e #304, que são o design de agosto e o adendo do D2, base deste.

## Em aberto

- Nada.
