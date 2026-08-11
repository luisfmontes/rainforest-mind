---
name: revisar
description: Revisão independente de uma entrega da esteira, contra o diff real — nunca pelo relato de quem implementou. Use depois que `executar` fechou `ok`, antes de `verificar`.
---

# Revisar

Abre com:

```
node scripts/estado.cjs exigir --slug <slug> --estagio revisar
```

Recusa (exit 2) se `executar` estiver `parcial` — não existe revisão de
entrega incompleta; é o próprio estado que barra, não julgamento seu.

## Contexto zerado, nunca `fork`

Revisor nasce sem a conversa que produziu a entrega — `Agent` novo, nunca
`fork` do agente que despachou. Quem herda a narrativa de quem escreveu
valida a narrativa, não o código: some a chance de o revisor notar algo
que quem implementou já decidiu que estava certo. Use
`rainforest-mind:revisor` (`agents/revisor.md` — leia antes de citar; é
sonnet com o método de review embutido).

## O relato de quem implementou não é fonte

O briefing do revisor traz caminho, diff e critério de sucesso original —
nunca o resumo de "o que foi feito". Justificativa de desenho do
implementador ("deixei assim por YAGNI", "não fiz X porque Y") é ele
dando nota a si mesmo e **nunca reduz a severidade de um achado**: se o
código faz a coisa errada, a explicação de por que faz não conserta.

## Escopo fixado por diff

```
git diff <base>...<head>
```

Três pontos, sempre — mostra só o que a branch trouxe desde que divergiu
da base. `git diff base..head` ou `HEAD~1` pegam o commit errado e cortam
task com vários commits, ou trazem mudança alheia que chegou em paralelo
na base. Sem diff (branch igual à base, ou `head` inexistente), **não há
revisão**: pare e reporte em vez de revisar de memória da conversa.

## Achado exige cenário

Achado só sobrevive com `arquivo:linha` e o cenário concreto de falha —
entrada ou estado que produz resultado errado. "Eu faria diferente" ou
"não é assim que eu escreveria" não é achado, é estilo, e só entra se
violar padrão documentado do repo.

## Veredito binário

```
node scripts/estado.cjs marcar --slug <slug> --estagio revisar --status ok --json '{"achados":0}'
```

ou

```
node scripts/estado.cjs marcar --slug <slug> --estagio revisar --status reprovado --json '{"achados":N}'
```

Não existe meio-termo: `reprovado` **não libera** `verificar` — `exigir`
do próximo estágio recusa enquanto `revisar` não fechar `ok` — e devolve o
trabalho para `executar`, com os achados numerados como a lista de
pendências da próxima rodada.

**Condição de parada**: sem diff, não há review. Reportar isso — branch
sem commit novo, `head` que não existe, worktree que não foi integrado —
vale mais que produzir um veredito sobre o que a memória da conversa
lembra ter sido feito.
