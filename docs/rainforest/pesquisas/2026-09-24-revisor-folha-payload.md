# Pesquisa: payload do `PreToolUse` para `Agent`/`Task` — folha vs. janela

Tarefa 1 de `docs/rainforest/planos/2026-09-24-revisor-folha.md`. Claude Code
**2.1.281** nesta máquina.

## Método

Cinco sessões headless (`claude -p`), rodadas com `cwd` fora de qualquer
repositório git (`$TEMP\...\scratchpad\portaria-folha`, que `git
rev-parse --show-toplevel` confirma **não** ser um repositório — evita que um
agente real do plugin (`rainforest-mind:executor`) tente operar sobre esta
árvore por engano). Todas usaram:

- `--settings ./settings-captura.json` — hook `PreToolUse` próprio, matcher
  `"Task|Agent"` (mesmo padrão já usado em `hooks/hooks.json:91`), que só lê o
  stdin e anexa a linha em `captura.jsonl` (sempre `exit 0`, nunca decide).
- `--output-format json --permission-mode bypassPermissions`.
- `--agents <arquivo>` para agentes de teste definidos inline, e/ou
  `--plugin-dir <pasta>` para agentes de teste definidos em `.md` de verdade
  (formato que a tarefa 4 do plano vai usar).

Arquivos de configuração e o script do hook ficaram em
`$TEMP\claude\C--Projetos-rainforest-mind\553122e5-fb70-4bad-8c90-94892ab86341\scratchpad\portaria-folha\`
— fora do worktree, apagados ao final (ver seção "Limpeza").

### Sessão A — fato (a), aninhamento via `--agents`
```
claude -p "Use a ferramenta Agent para despachar subagent_type \"despachante\" com o prompt exato: \"Despache agora, usando a ferramenta Agent, o subagent_type trivial com o prompt: responda apenas a palavra ok. Aguarde o resultado e depois responda apenas: feito.\". Aguarde a conclusao completa (incluindo o despacho aninhado que o despachante deve fazer) e so entao responda uma frase curta confirmando." \
  --settings ./settings-captura.json \
  --agents ./agents-aninhamento.json \
  --output-format json \
  --permission-mode bypassPermissions
```
`agents-aninhamento.json` define `despachante` (sem restrição) e `trivial`
(só responde "ok"). Saída (`result`): `"O despachante terminou e respondeu
\"feito\"..."`. `subagent_stats`:
```
{"spawned":2,"spawned_by_subagents":1,"max_depth":2,"by_type":{"despachante":1,"trivial":1}}
```
`captura.jsonl` recebeu 2 linhas — a chamada da janela (despachando
`despachante`) e a chamada de dentro do `despachante` (despachando
`trivial`).

### Sessão B — fato (b), `disallowedTools` via `--agents`
```
claude -p "Use a ferramenta Agent para despachar subagent_type \"restrito\" com o prompt: \"Liste suas ferramentas conforme instruido.\". Aguarde a resposta completa e repita literalmente, sem resumir, o que o agente restrito respondeu (as duas linhas)." \
  --settings ./settings-captura.json \
  --agents ./agents-disallowed.json \
  --output-format json \
  --permission-mode bypassPermissions
```
`agents-disallowed.json` define `restrito` com `"disallowedTools": ["Agent"]`
e o prompt: "liste em uma linha, separado por vírgula, os nomes EXATOS das
ferramentas definidas para você nesta chamada [...] diga SIM/NAO se Agent
(ou Task) está entre elas".

### Sessão C — checar `agent_id`/`agent_type` quando o alvo é agente de plugin
Mesmo padrão da sessão A, mas o `despachante2` despacha
`subagent_type: "rainforest-mind:executor"` (agente real do plugin, carregado
via `--plugin-dir` apontando para este worktree). **Efeito colateral
relevante**: isso carrega os `hooks.json` reais do plugin, então o
`portaria.cjs` de verdade rodou e negou o despacho aninhado (`isolation`
`undefined`) — a chamada nunca chegou a existir como agente, então essa sessão
não respondeu à pergunta do prefixo (ver "Efeito colateral" abaixo).

### Sessão D — fato extra: prefixo `plugin:agente` em `agent_type`
Para responder à pergunta do prefixo sem tocar o plugin real, criei um
plugin **temporário, sem `hooks.json`**, só com `.claude-plugin/plugin.json`
(`name: "temp-plugin"`) e dois agentes `.md`:
- `agents/despachante3.md` — despacha `trivial` (o mesmo custom agent da
  sessão A, reaproveitado via `--agents`).
- `agents/restrito2.md` — frontmatter com `disallowedTools: Agent`.

```
claude -p "Use a ferramenta Agent para despachar subagent_type \"temp-plugin:despachante3\" com o prompt: \"Faca o despacho aninhado conforme sua instrucao e responda feito.\". Aguarde a conclusao e responda uma frase curta confirmando." \
  --settings ./settings-captura.json \
  --agents ./agents-aninhamento.json \
  --plugin-dir ./temp-plugin \
  --output-format json \
  --permission-mode bypassPermissions
```
`subagent_stats`: `{"spawned":2,"spawned_by_subagents":1,"max_depth":2,"by_type":{"temp-plugin:despachante3":1,"trivial":1}}`
— desta vez o aninhamento aconteceu de verdade (não foi negado).

### Sessão E — fato (b) via frontmatter `.md` (não só `--agents` JSON)
```
claude -p "Use a ferramenta Agent para despachar subagent_type \"temp-plugin:restrito2\" com o prompt: \"Liste suas ferramentas conforme instruido.\". Aguarde a resposta completa e repita literalmente, sem resumir, o que o agente respondeu (as duas linhas)." \
  --settings ./settings-captura.json \
  --plugin-dir ./temp-plugin \
  --output-format json \
  --permission-mode bypassPermissions
```

## Conclusão (a) — `agent_id`/`agent_type` só dentro de subagente

**CONFIRMADO.** Linha 1 de `captura.jsonl` da sessão A (chamada da JANELA
principal despachando `despachante`) **não tem** `agent_id` nem `agent_type`
entre as chaves do payload:
```
keys: cwd, effort, hook_event_name, permission_mode, prompt_id, session_id, tool_input, tool_name, tool_use_id, transcript_path
```
Linha 2 (chamada de DENTRO do `despachante`, despachando `trivial`) **tem**
as duas chaves:
```
keys: agent_id, agent_type, cwd, effort, hook_event_name, permission_mode, prompt_id, session_id, tool_input, tool_name, tool_use_id, transcript_path
agent_id: a016f5a93de4208ad | agent_type: despachante
```
Esses dois JSONs foram salvos, sem edição de conteúdo (só reformatados com
`JSON.stringify(obj, null, 2)` — mesmo conteúdo, mesma ordem de chaves,
indentado) em:
- `hooks/fixtures/portaria-folha/payload-de-subagente.json` (linha 2, `agent_id`
  e `agent_type` presentes)
- `hooks/fixtures/portaria-folha/payload-da-janela.json` (linha 1, sem as
  duas chaves)

Confirmação extra pelo lado do harness (não só pelo hook): `subagent_stats`
da sessão A —
`{"spawned":2,"spawned_by_subagents":1,"max_depth":2,"by_type":{"despachante":1,"trivial":1}}`
— `spawned_by_subagents: 1` é o harness dizendo, de forma independente do
meu hook, que um dos dois despachos veio de dentro de outro agente.

Em todas as 7 linhas de `captura.jsonl` (sessões A a E) `tool_name` foi
sempre `"Agent"` (nunca `"Task"`), apesar de o matcher do hook cobrir os
dois nomes e de fixtures existentes no repo usarem `tool_name: "Task"`
(`hooks/testa-portaria-log-fora-do-repo.cjs:61`,
`hooks/testa-portaria-manifesto.cjs:68,89`) — nesta versão (2.1.281) o nome
efetivo da ferramenta é `Agent`.

### Bônus confirmado na sessão D — prefixo `plugin:agente`
O `agent_type` de um agente **definido em plugin** (`.md` real, não
`--agents` JSON) que despacha outro agente vem **prefixado** com o nome do
plugin e dois-pontos, exatamente como o design supôs
(`rainforest-mind:revisor`):
```
agent_id: a849811f77dad714e | agent_type: temp-plugin:despachante3 | subagent_type pedido: trivial
```
(plugin de teste `temp-plugin`, agente `despachante3` → `agent_type:
"temp-plugin:despachante3"`).

Isso não usa o plugin `rainforest-mind` real como agente-que-chama (só
verifiquei o plugin real como agente-**chamado**, na sessão C, onde a
portaria de verdade negou o despacho antes de qualquer `agent_type` de
`rainforest-mind:*` existir como chamador). Então: **CONFIRMADO** que
`agent_type` de agente de plugin vem prefixado `plugin:agente` (testado com
`temp-plugin:despachante3`); **LACUNA** — não testei especificamente com um
agente do plugin `rainforest-mind` como chamador (só como alvo, na sessão C,
onde a chamada nunca chegou a ser um agente por causa da negação de
`isolation`).

## Conclusão (b) — `disallowedTools: Agent` tira a ferramenta

**CONFIRMADO**, nos dois formatos (agente inline via `--agents` JSON — sessão
B — e agente de plugin via frontmatter `.md` real — sessão E, que é o
formato que a tarefa 4 do plano vai usar).

Resposta do agente `restrito` (sessão B, campo `result` da saída JSON —
rótulo: relato do próprio agente, não estado do harness):
```
Bash, Edit, Glob, Grep, ListAgents, PowerShell, Read, ReportFindings, Skill, ToolSearch, Write, mcp__claude_ai_Claude_Docs__batch, mcp__claude_ai_Claude_Docs__guide, mcp__claude_ai_Claude_Docs__update, advisor
NAO
```
Resposta do agente `temp-plugin:restrito2` (sessão E, mesmo formato de
prompt, agora via frontmatter `.md` real com `disallowedTools: Agent`) —
**idêntica**:
```
Bash, Edit, Glob, Grep, ListAgents, PowerShell, Read, ReportFindings, Skill, ToolSearch, Write, mcp__claude_ai_Claude_Docs__batch, mcp__claude_ai_Claude_Docs__guide, mcp__claude_ai_Claude_Docs__update, advisor
NAO
```
`Agent`/`Task` não aparece em nenhuma das duas listas. `permission_denials`
de ambas as sessões: `[]` (o agente nem tentou — a ferramenta simplesmente
não estava no seu pool, então não gerou negação de permissão, só ausência).
`subagent_stats` das duas sessões mostra `spawned: 1` (só o despacho da
janela para o agente restrito; nenhum despacho aninhado saiu dele).

Controle: o agente `despachante` da sessão A (mesmo mecanismo `--agents`,
sem `disallowedTools`) **conseguiu** chamar `Agent` de dentro de si — então a
ausência em `restrito`/`restrito2` é o bloqueio, não uma limitação geral do
mecanismo de despacho headless.

## Efeito colateral encontrado (importante) — escreveu em `~/.rainforest` real

As cinco sessões headless (A a E) **escreveram no `~/.rainforest` real do
usuário** (`~/.rainforest/portaria/despachos.jsonl`,
`~/.rainforest/rainforest.db`, `~/.rainforest/sessoes.json`), mesmo as que
não usaram `--plugin-dir` (A, B) e mesmo a que usou só o `temp-plugin`
sem `hooks.json` (D, E). Motivo: `--settings <arquivo>` **soma** ao
`settings.json` de sistema/usuário/projeto — não os substitui — e o plugin
`rainforest-mind` já está instalado e habilitado globalmente nesta máquina
(por isso o `PreToolUse` real da portaria dispara em toda sessão `claude`,
independente de flags de isolamento que eu passei). Não usei
`--safe-mode`/`--setting-sources` para isolar, e o briefing não pedia — mas
o resultado é escrita real fora do worktree, o que a seção "Restrições" do
briefing proíbe explicitamente eu fazer.

Evidência (`hooks/portaria.cjs` grava em `~/.rainforest/portaria/despachos.jsonl`
uma linha por decisão; as últimas 4 linhas do arquivo real, coladas cruas):
```
{"ts":"2026-09-24T19:23:12.276Z","repo":"C:\\Users\\Luis\\AppData\\Local\\Temp\\claude\\C--Projetos-rainforest-mind\\553122e5-fb70-4bad-8c90-94892ab86341\\scratchpad\\portaria-folha","agente":"despachante2","estagio":"fora-de-fluxo","decisao":"allow","sessao":"004239a7-51d9-46d0-ad41-8d552b6913b9","escreve_conferido":false,"runtime":"claude","declarado":false,"fora_de_fluxo":true}
{"ts":"2026-09-24T19:23:15.653Z","repo":"C:\\Users\\Luis\\AppData\\Local\\Temp\\claude\\C--Projetos-rainforest-mind\\553122e5-fb70-4bad-8c90-94892ab86341\\scratchpad\\portaria-folha","agente":"executor","estagio":"fora-de-fluxo","decisao":"deny","sessao":"004239a7-51d9-46d0-ad41-8d552b6913b9","motivo":"agente 'executor' declara 'escreve: true' e so roda com isolation: \"worktree\" (veio undefined) — agente que edita nunca roda na arvore do usuario (regra 11)"}
{"ts":"2026-09-24T19:29:13.303Z","repo":"C:\\Users\\Luis\\AppData\\Local\\Temp\\claude\\C--Projetos-rainforest-mind\\553122e5-fb70-4bad-8c90-94892ab86341\\scratchpad\\portaria-folha","agente":"despachante3","estagio":"fora-de-fluxo","decisao":"allow","sessao":"83eab276-c97c-49a8-9578-8cad55e9c88d","escreve_conferido":false,"runtime":"claude","declarado":false,"fora_de_fluxo":true}
{"ts":"2026-09-24T19:30:11.877Z","repo":"C:\\Users\\Luis\\AppData\\Local\\Temp\\claude\\C--Projetos-rainforest-mind\\553122e5-fb70-4bad-8c90-94892ab86341\\scratchpad\\portaria-folha","agente":"restrito2","estagio":"fora-de-fluxo","decisao":"allow","sessao":"7746d320-ef82-4497-a8e8-0771d3f1c9e1","escreve_conferido":false,"runtime":"claude","declarado":false,"fora_de_fluxo":true}
```
`repo` em cada linha aponta para a pasta temporária da pesquisa (nunca este
worktree) — não há linha com `repo` deste worktree. **Não apaguei nem editei**
`despachos.jsonl`, `rainforest.db` ou `sessoes.json` reais: são estado
compartilhado com sessões concorrentes reais do usuário (a própria janela
que despachou esta tarefa também grava ali), e apagar sem saber o que mais
mudou nesse intervalo arrisca derrubar trabalho alheio (mesma lógica da
seção "Limpar o ambiente" da memória do usuário — "conferir de quem é antes
de apagar"). Reporto e paro aqui; não tentei limpar.

Também escreveram (aceito pelo briefing — "a sessão headless grava o próprio
transcrito na config dir, como qualquer sessão"): 5 transcritos de sessão em
`~/.claude-personal/projects/C--Users-Luis-AppData-Local-Temp-claude-C--Projetos-rainforest-mind-553122e5-fb70-4bad-8c90-94892ab86341-scratchpad-portaria-folha/`
(sessões A a E, incluindo as subpastas `subagents/` de cada uma) e entradas
em `~/.claude-personal/.../memory/`.

## Limpeza feita

Apagados (todos fora do worktree, dentro do scratchpad da sessão):
`settings-captura.json`, `captura.cjs`, `captura.jsonl`, `agents-*.json`,
`temp-plugin/`, `sessao{A..E}-stdout.json`, `sessao{A..E}-stderr.log`.
Não apaguei os transcritos reais em `~/.claude-personal/.../projects/...`
nem os arquivos de `~/.rainforest` (ver seção anterior).

## Premissas do briefing aceitas sem conferir

- Que `claude --agents` e `--plugin-dir` funcionam como a ajuda descreve em
  produção real (não só na doc) — conferido empiricamente aqui, então deixou
  de ser premissa.
- Que o Claude Code 2.1.281 desta máquina é a versão relevante para a doc
  oficial citada no design (`hooks.md`, `sub-agents.md`) — não abri essas
  páginas da doc oficial nesta pesquisa; só confirmei o comportamento ao
  vivo, que é o que a tarefa pede. **LACUNA**: não comparei texto da doc
  oficial contra o observado, só validei o observado.
