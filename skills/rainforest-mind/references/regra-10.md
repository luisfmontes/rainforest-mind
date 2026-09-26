# Regra 10 — Agentes baratos com método

Regra permanente, sem precisar ativar
nada: toda task mecânica (implementar, editar, configurar, pesquisar e
agir) é despachada no agente **`rainforest-mind:executor`** (subagent_type
do Agent tool) — haiku com o método de trabalho embutido no system prompt
(`agents/executor.md`, destilado do fable-method, MIT; os itens do método
moram lá, e mudam lá). Review/QA em sonnet via **`rainforest-mind:revisor`**
(`agents/revisor.md` — julga o código e reporta, não conserta). Testes de
uma entrega → **`rainforest-mind:tester`** (`agents/tester.md`, sonnet —
escreve os testes que faltam e commita os testes, não conserta o código).
Os quatro acrescentados em 2026-08-11, quando a ferramenta passou a ser de
outros devs também: **`planejador`** (`agents/planejador.md`, sonnet —
devolve plano e para antes da primeira linha de código), **`depurador`**
(`agents/depurador.md`, sonnet — executa a skill `depurar` e para se não
conseguir montar o loop vermelho-capaz, em vez de propor conserto às
cegas), **`resolvedor-de-build`** (`agents/resolvedor-de-build.md`, haiku —
só erro de build/tipo, diff mínimo, com os três gatilhos de parada) e
**`documentador`** (`agents/documentador.md`, haiku — escreve doc só do que
confirmou em `arquivo:linha`).
A divisão é **por função, nunca por domínio**: agente de domínio mora no
plugin do domínio (os seis de um plugin interno de cliente, por exemplo), porque
função atravessa projeto e domínio não. **A janela principal pensa** —
entende, decide, integra — e os agentes executam; opus só sob pedido
explícito. O `planejador` devolve plano, não arquitetura: julgamento fino
de arquitetura continua na janela principal (ou no agente nativo Plan). **Atenção (verificado 2026-08-06):** a definição do
agente só é aplicada em subagente **sem `name`** — agente nomeado vira
teammate com system prompt genérico e ignora o executor.md; nesse caso
(ou com outro tipo de agente), colar o bloco de método no prompt
manualmente. **Não nomear agente** salvo necessidade real de diálogo
contínuo: sem nome, o agente devolve o resultado inline e encerra sozinho;
nomeado, fica pendurado como teammate ocioso até alguém encerrar — e isso
incomoda o usuário na hora de fechar a conversa. Se nomear, enviar
shutdown_request ao terminar de usá-lo.

**E o custo de nomear não é o incômodo: é a entrega que não chega**
(2026-08-12, Issue #1). Três subagentes nomeados apuraram três repos, os
três cumpriram o critério — e os três sinalizaram `idle_notification` com
`idleReason: "available"` **sem entregar nada**. O relatório existia,
completo, dentro de cada um; só veio depois de uma cobrança explícita por
`SendMessage`, uma por agente, três turnos. Nomear troca subagente anônimo
(cujo texto final **é** o valor de retorno) por teammate persistente, que
só se comunica chamando `SendMessage` — e nada avisa que o resultado ficou
parado lá dentro. É a assinatura de sempre: **a peça existe, o caminho até
ela não, e a falha não faz barulho.**

Duas consequências práticas. Nomeando, o **briefing** tem que mandar
devolver — é o bloco 4 da forma do briefing, na skill `modo-dev`, e o
texto de lá cobre isso desde 2026-08-12. E se o agente calar mesmo assim,
**cobrar em vez de re-despachar**: o trabalho já está feito, re-despachar
paga a apuração duas vezes. Foi exatamente por serem nomeados que os três
puderam ser cobrados.

> Este parágrafo é elaboração, e elaboração **não é injetada**. Em
> 2026-08-12 o mecanismo já estava escrito acima ("sem nome, o agente
> devolve o resultado inline e encerra sozinho") e ainda assim a sessão
> pisou no defeito, porque despachou sem carregar `Skill(rainforest-mind)`
> antes de aplicar a regra 10. Por isso o núcleo carrega, em uma linha, o
> que a elaboração sozinha não protege — "nunca é nomeado": o que não cabe
> no núcleo não chega a lugar nenhum.

**E nomear custa o worktree junto** (verificado 2026-08-08): agente que
**edita arquivo nunca é nomeado** — nome só pra agente de conversa, que não
toca arquivo. A ilusão de isolamento é pior que a ausência dele.

> 2026-08-08: despacho com `isolation: "worktree"` e nome rodou **sem
> worktree nenhum** — o meta do nomeado não traz `worktreePath`, o do irmão
> sem nome, no mesmo dia e mesmo despacho, traz — e ele acabou commitando no
> checkout principal do usuário. O worktree que aparecia no `git worktree list`
> era de **outro** agente, e o diagnóstico apontou pro lugar errado por horas.

**Quando despachar — 3.000 tokens.** Se a task somada ao trabalho intermediário
dela (arquivos lidos inteiros, saídas de comando, tentativas descartadas)
acrescentaria ~3.000 tokens ou mais ao contexto da janela principal, despachar.
O que se compra é o contexto queimado longe daqui, não velocidade — e **abaixo
do limiar despachar sai mais caro que fazer**: subir um agente custa o system
prompt e o briefing dele inteiros, ordem de grandeza acima de uma edição
pequena. Não despachar pra tirar diff da tela do usuário; pra isso o limiar já
decide. A forma do briefing e o encadeamento de vários despachos moram na skill
`modo-dev`.

## A portaria — admissão por manifesto (fluxo 9)

Subagente só roda se estiver declarado no manifesto com o estágio ativo na sua lista. A decisão é tomada por código — hook `PreToolUse` (`hooks/portaria.cjs`) —, nunca por pergunta ao humano em runtime; exceção é editar o manifesto, e isso passa pelo `revisar`.

**Isto vale em toda sessão** com o plugin habilitado, não só no repositório dele (mudou em 2026-09-13). O manifesto é o `.rainforest/agentes.padrao.json` embarcado no plugin, ou o `.rainforest/agentes.json` do repo, que o **substitui por inteiro** quando existe.

O mecanismo inteiro — schema do manifesto, as sete decisões do fail-closed, o log de despacho, o modo `--lint`, o aceite do bloqueio e as duas portas da dívida do `escreve: false` — mora em `references/regra-10-portaria.md`; o escopo, a precedência entre os dois manifestos e o destino do log, em `references/regra-10-portaria-escopo.md`.

Os vigias headless carregam a versão resumida no `vigias/_comum.md`.

## Agente despachado é folha

Nenhum subagente despacha outro agente. Duas camadas, não uma. Os 9 agentes do
plugin (`agents/*.md`) trazem `disallowedTools: Agent` no frontmatter — a
ferramenta nem existe para eles, nem tentativa nem turno gasto. E a portaria
(`hooks/portaria.cjs`) nega qualquer chamada de `Agent` cujo payload traga
`agent_id`: essa chave (com `agent_type`) só aparece no `PreToolUse` quando a
chamada sai de **dentro** de um subagente — a janela principal nunca traz as
duas —, então esta camada cobre o que o frontmatter não alcança: os agentes
nativos do harness (`general-purpose`, `Explore`) e agente de qualquer outro
plugin instalado. A negação tem toggle, desligável por projeto:
`"agente-folha": false` no `.rainforest/config.json` do repo, mesma forma do
`contrato-veredito`.

**Folha com trabalho grande demais faz sozinha.** Não pede para particionar
e não devolve só uma proposta de divisão — se não cobrir tudo, devolve o
resultado parcial com a **lista explícita** do que não conferiu. Quem vê o
todo e decide particionar é sempre quem despachou, nunca a folha.

**Fechamento de rodada.** Antes de declarar pronta uma rodada com agentes em
paralelo, a janela roda `ListAgents` e para o que **ela mesma** abriu e
sobrou — pelo nome ou id que ela despachou, nunca o que não é dela. Folha
reduz o risco de agente pendurado, não zera: rodada de topo (a própria
janela despachando vários agentes) também deixa sobra, e ninguém além da
janela confere isso.

> **2026-09-04:** um revisor despachou quatro sub-revisores nomeados,
> acumulou ~243k tokens de contexto e esperou 8 minutos antes de fechar
> sozinho — o custo do aninhamento sem ganho de qualidade medido: o veredito
> sozinho já saía certo.

> **2026-09-23:** um avaliador `general-purpose` — nativo do harness, fora do
> alcance do frontmatter dos 9 agentes do plugin — manteve dois teammates
> pendurados no roster por ~2h. Quem percebeu foi o usuário, não a janela que
> os abriu.

## Racionalizações

| Pensamento | Realidade |
|---|---|
| "despachar custa mais que fazer" para task grande | 2026-08-12: o método não foi injetado, sessão pisou no defeito sem carregar a skill |
| "nome só pra conversa, sem isolamento" | 2026-08-08: agente nomeado rodou no checkout principal do usuário |
| "re-despachar custa menos" | 2026-08-12: núcleo rescrito para caber no context e chegou mudo |
