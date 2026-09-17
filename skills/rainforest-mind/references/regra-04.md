# Regra 4 — Checkpoint no meio, não só no fim

A frase do núcleo ("Fechamos [n]/[total]: [o que]. Próxima: [qual].") diz a
etapa que fechou e a próxima. Sozinha, ela obriga a rolar a tela para saber o
resto — e no terminal rolar para trás não é caminho. Por isso o checkpoint
**carrega a rota**.

## A rota

Tarefa de 3+ etapas declara a rota no início, numerada — é a mesma lista do
`modo-dev` (`1. [passo] → verifica: [checagem]`), agora com estado. A cada
checkpoint, a frase do núcleo abre e a **rota inteira** vem embaixo,
re-renderizada: passado, presente e futuro de uma vez.

Cada etapa leva exatamente um de quatro estados:

- ✅ feito
- 🔄 rodando agora
- ⏳ não começou
- ❌ reprovada, ou travada por conta própria

Sem o ❌, etapa que falhou aparece como ✅ ou ⏳ — mentira de relance. Não
existe quinto estado: o que não cabe nos quatro vai na prosa da linha.

Linha ✅ se reduz ao rótulo — o que ela provou já foi dito no checkpoint dela.
As demais carregam o **fato concreto** em `código` (hash, comando, critério):
sem isso a rota vira lista de tarefa genérica.

## Numeração estável — o oposto da regra 1, de propósito

Etapa **não renumera**. A etapa 3 é a 3 do começo ao fim, mesmo depois que a 1
e a 2 fecharam. A regra 1 manda o contrário para respostas a pedidos (item
resolvido sai e os demais renumeram do 1), e as duas não colidem porque numeram
coisas diferentes: a regra 1 numera **pedidos** de um turno, esta numera
**etapas** de uma tarefa que atravessa turnos — e etapa só é reconhecível entre
turnos se o número não se mexer.

## Exemplo

```
Fechamos 3/5: revisão aprovada. Próxima: verificação.

1. ✅ Worktree conferido
2. ✅ Executor entregou
3. ✅ Revisão adversarial
4. 🔄 Verificação — critério é `advpls appre` exit 0 num `.prw` de 400+ campos
5. ⏳ PR fechando a `#104`
```

E se a verificação reprova — a rota continua inteira:

```
Fechamos 3/5, e a 4 reprovou: `advpls appre` saiu 1. Próxima: corrigir e repetir a 4.

1. ✅ Worktree conferido
2. ✅ Executor entregou
3. ✅ Revisão adversarial
4. ❌ Verificação — `advpls appre` saiu 1: `campo duplicado na linha 212`
5. ⏳ PR fechando a `#104` — espera a 4
```

❌ marca a etapa que **ela mesma** falhou ou travou. Etapa que só espera a
reprovada continua ⏳, com o motivo na prosa: marcar a 5 como ❌ esconderia
qual das duas precisa de conserto.
