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
> antes de aplicar a regra 10. Por isso o núcleo passou a dizer, em uma
> linha, que nomeado só entrega por `SendMessage`: o que não cabe no
> núcleo não chega a lugar nenhum.

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

Desde 2026-08-31, subagente só roda se estiver declarado em `.rainforest/agentes.json` com o estágio ativo na sua lista. A decisão é tomada por código (hook `PreToolUse` que intercepta a tool `Task`), nunca por pergunta ao humano em runtime.

> **Regra 10 (reescrita):** Subagente só roda se estiver declarado em `.rainforest/agentes.json` e o estágio ativo constar na sua lista. A portaria decide por código; o humano nunca é perguntado em sessão. Exceção não existe em runtime — exceção é editar o manifesto, e edição de manifesto é mudança versionada que passa pelo `revisar`.

**O manifesto** (`.rainforest/agentes.json`) declara por agente:
- `estagios`: em quais estágios do grafo (ex.: `["revisar"]`, `["design", "plano"]`) pode ser despachado.
- `escreve`: por ora, sempre `false` — subagente não escreve, só relata.

Exemplo:
```json
{
  "versao": 1,
  "agentes": {
    "revisor":    { "estagios": ["revisar"], "escreve": false },
    "planejador": { "estagios": ["design", "plano"], "escreve": false }
  }
}
```

**Fail-closed, sempre com motivo.** A portaria nega quando: manifesto ausente ou inválido (JSON malformado ou `versao` desconhecida), agente não declarado, sem estágio ativo (nenhum fluxo aberto que case com a branch), estágio ativo fora da lista `estagios` do agente, ou `escreve: false` mas o arquivo `.claude/agents/<nome>.md` declara tools fora da allowlist read-only (`Read`, `Grep`, `Glob`). Toda negação sai com motivo não vazio — negação muda é bug.

**Log de despacho** (`.rainforest/portaria/despachos.jsonl`): append-only, uma linha JSON por decisão, aprovada ou negada. Cada linha é autocontida — legível isolada, sem precisar do resto do log para fazer sentido:
```json
{"ts":"2026-08-31T14:02:11Z","agente":"revisor","estagio":"revisar","decisao":"allow","sessao":"<id>"}
{"ts":"2026-08-31T14:05:47Z","agente":"executor","estagio":"revisar","decisao":"deny","motivo":"agente 'executor' não consta no manifesto","sessao":"<id>"}
```

O log é evidência de primeira classe: responde "quem rodou, quando, em qual estágio" com `cat`, e o recibo do fluxo 7 pode referenciá-lo. **Adicionado ao `.gitignore`** — `.rainforest/agentes.json` e `.rainforest/portaria/amostra.json` ficam versionados (documentação); o log de execução não.

**Exceção é editar o manifesto.** Quem quer disparar agente não declarado edita `.rainforest/agentes.json`, passando a mudança pelo `revisar` — é o único jeito de aprovar novas declarações. Em runtime, sem edição no manifesto, não há pergunta ao humano.

**Estado atual (Opção A: 2026-08-31).** Enquanto `escreve: false` for a única opção no schema e agentes escritores (`executor`, `documentador`, `resolvedor-de-build`, `tester`) não tiverem worktree próprio (extensão futura não implementada), esses quatro agentes não cabem no manifesto real — ficar de fora do manifesto significa serem bloqueados assim que o hook for registrado em `.claude/settings.json`. A Tarefa 9 do plano (fluxo 9) registra bloqueio explícito — o hook entra em produção (`main`) apenas com aceite por escrito do usuário de que sabe e aceitou que `executor`/`documentador`/`resolvedor-de-build`/`tester` param de rodar nesse instante, até a reavaliação futura de `escreve: true` com isolamento de worktree.

Os vigias headless carregam a versão resumida no `vigias/_comum.md`.
