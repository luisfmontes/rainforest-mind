# Harness: contexto do UserPromptSubmit e updatedInput do Agent

Medido em 2026-10-08, Claude Code 2.1.293, `claude -p --model haiku`, 4 rodadas
(limite era 6). Fluxo `2026-10-08-memoria-por-assunto`, tarefa 1.

Sandbox (cwd das rodadas), abaixo `<SB>`:
`<home>/AppData/Local/Temp/claude/C--Projetos-rainforest-mind/722539d9-b368-4e3f-9f32-6a3fd43848ae/scratchpad/harness-probe/`.
`RFM_ROOT=<SB>/../harness-probe-root` em todas as rodadas.
`CLAUDE_CONFIG_DIR` da conta é `~/.claude-personal`, então os transcritos
ficaram em `~/.claude-personal/projects/<slug-do-cwd>/`.

## Hooks de teste (dentro do sandbox)

`hook-prompt.js` (UserPromptSubmit), saída fixa:

```json
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"contexto de teste MARCA-ASSUNTO-7f3 fim"}}
```

`hook-agent.js` (PreToolUse, matcher `Agent`): lê o stdin, devolve
`hookSpecificOutput.updatedInput` = `tool_input` inteiro com `prompt` +
`"\nMARCA-AGENTE-9c1"`; só acrescenta `"permissionDecision":"allow"` quando
`PROBE_ALLOW=1`. Declarados em `s-a.json` e `s-b.json`, passados por `--settings`.

## Rodada 1 — (a) UserPromptSubmit

Comando:

```
cd <SB> && RFM_ROOT=<SB>/../harness-probe-root claude -p --model haiku --settings s-a.json --output-format json "Responda apenas: ok"
```

Saída: JSON de resultado normal (`"stop_reason":"end_turn"`, `session_id a852aee3-571e-43fa-a39e-626fd2f76e0d`).
Transcrito `a852aee3-....jsonl`: a marca aparece em exatamente UMA linha (índice 18 de 38,
0-based). Forma literal (fixture `prompt-submit.jsonl`; `cwd` abreviado aqui, cru na fixture):

```
{"parentUuid":"09b92113-0177-459f-9279-fe6b02865c07","isSidechain":false,"attachment":{"type":"hook_additional_context","content":["contexto de teste MARCA-ASSUNTO-7f3 fim"],"hookName":"UserPromptSubmit","toolUseID":"hook-a9c01229-8c73-43b0-8fd4-d95b6fca91ef","hookEvent":"UserPromptSubmit"},"type":"attachment","uuid":"6983a233-5a36-4518-81e6-12fb53300986","timestamp":"2026-10-08T11:29:48.550Z","rendered":[{"content":"<system-reminder>\nUserPromptSubmit hook additional context: contexto de teste MARCA-ASSUNTO-7f3 fim\n</system-reminder>"}],"renderedRole":"system","userType":"external","entrypoint":"sdk-cli","cwd":"...","sessionId":"a852aee3-571e-43fa-a39e-626fd2f76e0d","version":"2.1.293","gitBranch":"HEAD"}
```

Resposta de (a):

- `type` = `"attachment"`; `attachment.type` = `"hook_additional_context"`.
- Texto em `attachment.content[0]` (array de strings, uma por contexto) e também
  em `rendered[0].content`, já embrulhado como
  `<system-reminder>\nUserPromptSubmit hook additional context: <texto>\n</system-reminder>`.
- `attachment.hookEvent` = `"UserPromptSubmit"`, `attachment.hookName` = `"UserPromptSubmit"`.
- Não é a linha `type:"user"` do prompt (índice 8): o contexto vem em linha PRÓPRIA,
  posterior (índice 18), depois de attachments `environment`, `model`, `skill_listing` etc.
  O stdout cru do hook (`hook_success`) NÃO guardou a marca nesta rodada (nenhuma outra linha a contém).

## Rodada 2 — tentativa de (b1), INVÁLIDA (hooks de usuário interferiram)

Comando:

```
cd <SB> && RFM_ROOT=<SB>/../harness-probe-root claude -p --model haiku --settings s-b.json --output-format json "Use a ferramenta Agent (subagent_type general-purpose) com este briefing exato, em tres linhas: 'Instrucao: responda apenas repetindo literalmente a ULTIMA linha deste briefing.' / 'linha do meio' / 'FIM-DO-BRIEFING'. Depois imprima literalmente a resposta do subagente."
```

Saída: `result: Qual atividade ou chamado Jira você vai trabalhar nesta conversa? Se não quiser registrar horas agora, diga "pula". ...` com `subagent_stats.spawned = 0`.
Um hook de usuário (apontamento de horas) interceptou o prompt; o Agent nunca rodou. Descartada.
Correção nas rodadas seguintes: `--setting-sources project` (não carrega settings de usuário
nem os hooks dos plugins habilitados lá; `--settings s-b.json` continua valendo).

## Rodada 3 — (b1): updatedInput SEM permissionDecision

Comando (mesmo prompt da rodada 2):

```
cd <SB> && RFM_ROOT=<SB>/../harness-probe-root claude -p --model haiku --setting-sources project --settings s-b.json --output-format json "<mesmo prompt>"
```

Sem `--allowedTools`, sem bypass: modo de permissão padrão do `-p`. `permission_denials: []`.

Resposta do pai impressa:

```
A resposta do subagente foi:

MARCA-AGENTE-9c1

Ela não bate com a última linha do briefing, que era `FIM-DO-BRIEFING`. ...
```

O subagente respondeu `MARCA-AGENTE-9c1`: a marca é a nova ÚLTIMA linha do briefing, ou seja, ele recebeu o prompt alterado.
Onde fica gravado (session `7c737140-545e-4575-af30-b83ceacf480f`):

- Pai, linha `assistant` com `tool_use` do Agent: `input.prompt` e `wireToolInputs[...].prompt` ficam com o prompt ORIGINAL (sem a marca). O transcrito do pai NÃO mostra o prompt alterado nesse campo.
- Pai, linha seguinte, `attachment` com `attachment.type="hook_success"`, `hookName="PreToolUse:Agent"`: `attachment.stdout` guarda o JSON cru do hook, com `updatedInput.prompt` contendo a marca.
- Pai, linha `user` com `tool_result`: `toolUseResult.prompt` = prompt ALTERADO (com `\nMARCA-AGENTE-9c1`), `toolUseResult.status="async_launched"`, `permissionDecision` = `{"decision":"accept","source":"config"}`.
- Filho (`<sessao>/subagents/agent-a37464c2ec09cda59.jsonl`), PRIMEIRA linha (`type:"user"`, `isSidechain:true`): `message.content` é string e termina em `\nMARCA-AGENTE-9c1`.
- `subagents/<agente>.meta.json`: `{"agentType":"general-purpose",...,"requestShape":"background"}`. Neste sabor o Agent foi lançado em segundo plano (o modelo não passou `run_in_background`; o harness tratou como `background` em modo não interativo).

Fixtures: `agente-pai.jsonl` = as três linhas do pai (tool_use, hook_success, tool_result),
`agente-filho.jsonl` = a primeira linha do filho.

## Rodada 4 — (b2): updatedInput COM permissionDecision "allow"

Comando:

```
cd <SB> && PROBE_ALLOW=1 RFM_ROOT=<SB>/../harness-probe-root claude -p --model haiku --setting-sources project --settings s-b.json --output-format json "<mesmo prompt>"
```

Sem `--allowedTools`. `permission_denials: []`. Resposta do pai impressa:

```
O subagente respondeu com a linha abaixo, literalmente:

MARCA-AGENTE-9c1

A resposta não é `FIM-DO-BRIEFING`, ...
```

Session `e1e80331-3509-4b3a-a2eb-078415100fcc`. Mesmo mapa de gravação: `tool_use.input` original sem marca;
`hook_success.stdout` com `updatedInput` + `"permissionDecision":"allow"`; `toolUseResult.prompt` com a marca,
`permissionDecision` = `{"decision":"accept","source":"hook","reasonType":"hook"}`; primeira linha do filho com a marca.
Aqui o Agent rodou em primeiro plano (`run_in_background:false` no tool_use).

## Resultado

- b1 (sem permissionDecision): entregou a marca ao subagente. Source da decisão de permissão: `config`.
- b2 (com allow): entregou a marca ao subagente. Source: `hook`.
- Os dois sabores diferem em execução (b1 background, b2 foreground), mas é o modelo que escolhe isso; nenhuma das duas rodadas depende de `permissionDecision` para entregar a marca.
- Cada sabor foi rodado UMA vez (haiku). Não houve rodada de repetição.

D5: updatedInput VALE
D5-permissao: sem permissionDecision VALE

## Premissas aceitas sem conferir

- Que o modo de permissão padrão do `-p` é o que o briefing chama de "padrão"; não rodei a variante interativa.
- Que `--setting-sources project` não muda o tratamento de `updatedInput` (só tira hooks de usuário/plugins). Não rodei b1 com os hooks de usuário carregados porque a rodada 2 foi bloqueada por eles.
- Que haiku se comporta como o modelo de produção quanto ao Agent; o hook age antes do modelo do filho, então a marca chegar não depende do modelo.
- As fixtures preservam `cwd` com o caminho do sandbox (contém o nome de usuário do Windows), aceito pelo briefing; copiadas sem edição.
