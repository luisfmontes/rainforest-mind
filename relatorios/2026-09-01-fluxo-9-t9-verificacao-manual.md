# Fluxo 9, Tarefa 9 — verificação manual única da portaria

**Data:** 2026-09-01 · **Claude Code:** 2.1.240 · **Windows**
**Branch:** `fluxo/portaria` · **Estágio ativo no momento do teste:** `revisar`

Este é o único episódio de evidência que nenhuma bateria offline reproduz: o
comportamento do **harness real** quando o hook `PreToolUse` nega um despacho.

## Por que ela rodou no `revisar`, e não dentro do `executar`

A Tarefa 9 é tarefa do estágio `executar` no plano, e **não pode fechar lá**. O
critério exige um **allow** para `rainforest-mind:revisor`, e o manifesto real
admite três agentes, nenhum deles com `executar` na lista:

```
revisor              ["revisar"]
auditor-de-seguranca ["revisar"]
planejador           ["design","plano"]
```

Enquanto `executar` é o estágio ativo, a portaria nega **todo** despacho — que é
a consequência aceita da Opção A, não um defeito do hook. O defeito é de
ordenação do plano, e foi achado na execução. O `executar` foi fechado com a
Tarefa 9 marcada `n/a` no ledger de mutação, com esse motivo escrito, e a
evidência foi colhida no minuto seguinte, já no `revisar`.

Antes do fechamento, as duas **negações** já tinham sido provadas no worktree
real, com o manifesto real, ainda em `executar`:

```
$ printf '%s' '{"session_id":"prova-t9-offline",…,"tool_input":{"subagent_type":"rainforest-mind:revisor",…}}' \
  | CLAUDE_PROJECT_DIR="$PWD" node hooks/portaria.cjs
estágio 'executar' não permitido para 'revisor' (permitidos: revisar)
EXIT=2

$ … "subagent_type":"rainforest-mind:executor" …
agente 'executor' não consta no manifesto
EXIT=2
```

## O teste

Sessão **nova** do Claude Code (`claude -p`, headless) com o diretório do
projeto na raiz do worktree — portanto com o `.claude/settings.json` versionado
(matcher `Task|Agent` → `hooks/portaria.cjs`) e o `.rainforest/agentes.json`
no lugar. Dois despachos, nesta ordem, e nada mais:

1. `rainforest-mind:revisor` — **declarado**, estágio ativo `revisar` na lista.
2. `rainforest-mind:executor` — **não declarado** (Opção A).

O log foi apagado antes (`rm -f .rainforest/portaria/despachos.jsonl`) para que
as duas linhas abaixo sejam desta sessão e de mais nada.

## Resultado — relatado pela sessão

```
**Sonda A (revisor):** RODOU — retornou `PING`.
**Sonda B (executor):** BLOQUEADO — mensagem exata: `agente 'executor' não consta no manifesto`.
```

## Resultado — evidência primária (`.rainforest/portaria/despachos.jsonl`)

O relato da sessão é relato. Isto é o que o hook escreveu:

```json
{"ts":"2026-09-01T13:05:40.613Z","agente":"revisor","estagio":"revisar","decisao":"allow","sessao":"b5faace0-3ac7-478c-b950-8566f917d9e1"}
{"ts":"2026-09-01T13:05:40.720Z","agente":"executor","estagio":"?","decisao":"deny","sessao":"b5faace0-3ac7-478c-b950-8566f917d9e1","motivo":"agente 'executor' não consta no manifesto"}
```

Mesmo `sessao` nas duas linhas — é a mesma sessão real, não duas invocações
avulsas do script.

## O que isso fecha (D8)

| Afirmação | Estado |
|---|---|
| Agente declarado, estágio certo → roda **sem nenhum prompt de autorização ao humano** | ✅ o `revisor` rodou e devolveu `PING`; nenhuma pergunta apareceu |
| Agente não declarado → **negado**, com o motivo chegando à sessão | ✅ `agente 'executor' não consta no manifesto`, palavra por palavra |
| A negação **não derruba** a sessão | ✅ a sessão seguiu, relatou os dois casos e saiu com `EXIT=0` |
| Cada decisão vira uma linha autocontida no log (D4) | ✅ as duas linhas acima, `allow` e `deny` |
| O log não entra no git (D4 + Tarefa 4) | ✅ `git status --porcelain` vazio depois do teste |

## O que este teste NÃO prova

- Não prova que `escreve: false` impede escrita. Não impede: nenhum dos nove
  `agents/*.md` declara `tools:`, então a checagem de allowlist não tem o que
  ler. Dívida nomeada em `skills/rainforest-mind/references/regra-10.md`.
- Não prova o comportamento com o hook registrado na **máquina** — ele está
  registrado só no `.claude/settings.json` **do projeto**, de propósito (D6).
- O `estagio` sai como `"?"` na linha de deny por agente não declarado: a
  portaria nega antes de resolver o estágio. É o desenho (não gastar leitura
  depois de já ter motivo), mas custa contexto em quem for ler o log depois.
