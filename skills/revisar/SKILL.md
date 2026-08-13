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

## Revisor não muta — encaminha a mutação

Validar por mutação (reverter o comportamento e ver o teste falhar) é
técnica boa e é **ofício do `tester`**, que roda com `isolation: "worktree"`
justamente para isso. O revisor não tem worktree por desenho — `revisar` é
leitura — e por isso **não edita fonte em lugar nenhum**, muito menos no
diretório principal do usuário.

Quando o achado só fecha com mutação, ele sai como achado **com a mutação
descrita** (que linha inverter, que teste deveria quebrar) e quem despacha
manda um `tester` isolado executá-la. Não é burocracia: em 2026-08-13 um
revisor mutou `gerar_updater_projeto.py` direto no diretório principal, o
`gate-worktree.cjs` bloqueou o `git checkout --` do próprio revert — corretamente,
pela letra da trava — e ele desfez reescrevendo o arquivo por fora do git,
o que funcionou e não deixou rastro auditável (Issue #4). A trava não estava
errada; o caminho é que não existia.

## Creep: medido contra o plano, não contra o gosto

**Creep é código sem tarefa correspondente no plano.** Arquivo que você tocou mas que não se encaixa em nenhum glob de `arquivos:` de tarefa nenhuma é achado e reprova a revisão.

Isto é **distinto** de "eu faria diferente":

- **Estilo** ("não é assim que eu escreveria", "deixaria mais limpo"): só entra se violar padrão documentado do repo. Senão, é gosto, não achado.
- **Creep** ("esse arquivo não era pra ser tocado", "essa mudança não estava no plano"): arquivo no diff que não casa com nenhum `arquivos:` da tarefa. Sempre reprova.

### Saída única: emendar o plano

Encontrou creep? A única forma de destravá-lo é emendar o plano: a tarefa que faltava entra no plano com critério falsificável. **Justificar em prosa não destrava** — "era uma limpeza necessária", "o compilador pediu" são narrativas, não ações que o plano registra.

A emenda deixa rastro conscientemente registrado de que o escopo cresceu — é isso que distingue creep legítimo (genuinamente necessário) de mudança de escopo silenciosa.

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

### Trava de cobertura de creep

A partir de 2026-08-13, `node scripts/estado.cjs marcar --estagio revisar --status ok` recusa se o `--json` não incluir `base` e `head` — são os dois pontos que definem o diff e permitem provar ausência de creep. Sem eles, fechar a revisão sem poder provar que o diff não toca arquivo fora do plano é o buraco que a trava fecha.

Fechar review como `reprovado` com achados de creep também exige `base` e `head` para que quem fizer a próxima rodada saiba qual era o escopo.
