# Amostras reais do payload do `PreToolUse` de despacho de subagente

Colhidas em **2026-09-01**, Claude Code **2.1.240**, Windows. São a resposta da
**Premissa 2** do fluxo 9 e o que a **D7** manda: o parser do `portaria.cjs` se
fixa **nestes campos**, nunca em schema imaginado (o incidente de 2026-08-19 —
hook lendo `evento.project`, campo que o harness nunca envia — é o motivo).

Como foram colhidas: sessão **nova** do Claude Code (`claude -p`, headless) com
`.claude/settings.json` deste repositório no checkout, despachando um subagente
de verdade. O hook estava em modo captura (primeira captura vence).

## `amostra.json` — despacho simples

Colhida no worktree `fluxo/portaria`, agente `general-purpose`, sem isolamento.

## `amostra-com-isolation.json` — despacho com `isolation` e `name`

Colhida num repositório git de sandbox com o mesmo hook registrado, para
descobrir os campos que o despacho simples não mostra. Agente
`rainforest-mind:executor`, `isolation: "worktree"`, `name: "sonda-um"`.

## O que as duas provam (e o que muda no desenho)

| Fato medido | Consequência |
|---|---|
| `tool_name` é **`"Agent"`**, não `"Task"` | o matcher tem de ser `Task\|Agent`; o design falava só em `Task` |
| o nome do agente está em **`tool_input.subagent_type`** | é o campo que a decisão 1 lê |
| `subagent_type` vem **com prefixo de plugin** (`rainforest-mind:executor`) | a chave do manifesto é o nome nu — o parser precisa tirar o prefixo `<plugin>:` |
| `isolation` e `name` aparecem em `tool_input` quando usados | a checagem futura de `escreve: true` com worktree obrigatório tem onde olhar |
| `session_id` está na raiz do payload | é o `sessao` da linha do `despachos.jsonl` (D4) |
| `cwd` está na raiz do payload | o hook não depende só de `CLAUDE_PROJECT_DIR` |

Amostra é **documentação datada**, não estado vivo: não regenere, não
sobrescreva. Se o harness mudar o schema, colha uma amostra **nova, com data
nova, em arquivo novo**, e deixe estas onde estão.
