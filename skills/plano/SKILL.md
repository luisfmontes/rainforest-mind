---
name: plano
description: Use depois que o design de um trabalho está aprovado na esteira do rainforest-mind, para transformar decisões fechadas em tarefas executáveis — nunca antes da primeira linha de código.
---

# Plano

Segundo estágio da esteira (design → plano → executar → revisar → verificar
→ fechar). Lê o design aprovado e escreve tarefas **tipadas**, cada uma com
sua dependência declarada — é essa marcação que o estágio `executar` usa
para despachar em paralelo; sem ela o paralelismo vira adivinhação.

## Abrir

```
node scripts/estado.cjs exigir --slug <slug> --estagio plano
```

Sai com exit 2 se `design` não estiver `aprovado` — não insista, volte para
o `brainstorm`. Leia o design inteiro em
`docs/rainforest/design/<slug>.md` antes de escrever a primeira tarefa.

## Template — `docs/rainforest/planos/<slug>.md`

Caminho relativo à **raiz do projeto em que se trabalha**, como o design.

```markdown
# Plano: <título>

Design: docs/rainforest/design/<slug>.md

## O que não pode quebrar
- <invariante 1>
- <invariante 2>

## Tarefas

### 1. <nome da tarefa> [tipo: implementar|configurar|pesquisar|teste|docs]
depende de: nenhuma
paralela: sim
pronto quando: `<comando exato>` devolve `<saída ou exit esperado>`

### 2. <nome da tarefa> [tipo: ...]
depende de: 1
paralela: nao
pronto quando: `<comando exato>` devolve `<saída ou exit esperado>`
```

Cada tarefa leva: **tipo**, `depende de:` (números das tarefas antecessoras
ou "nenhuma"), `paralela: sim|nao` (só "sim" quando `depende de: nenhuma`) e
critério de pronto **falsificável** — comando e saída esperada, nunca
"funcionar bem" ou "funcionar corretamente".

**Proibido placeholder.** Tarefa com "TBD", "a definir" ou critério de
pronto vago não entra no plano — falta decisão, e decisão que falta volta
para o `brainstorm`; não se resolve inventando aqui.

## Fechar

```
node scripts/estado.cjs marcar --slug <slug> --estagio plano --status ok --json '{"arquivo":"docs/rainforest/planos/<slug>.md","tarefas":N,"paralelas":[1,3]}'
```

**Condição de parada: o plano termina antes da primeira linha de código.**
Se a tentação for "só implementar essa parte pra confirmar", isso é uma
tarefa marcada no plano e o `executar` que faz depois — não aqui.

---

Segundo estágio da esteira rainforest-mind. `exigir`/`marcar` vêm de
`scripts/estado.cjs` — leia-o antes de citar uma flag que ele não tem.
