# Regra 11 — o checkout principal fica na branch padrão

Separado de `regra-11.md` em 2026-09-08 pelo mesmo motivo que partiu as regras
10 e 12: a elaboração já encostava no teto de bytes de um `reference`, e o que
entra aqui paga por subtração ou por arquivo novo. A regra em si — isolamento
de subagente, hash de base, conferência na integração — continua em `regra-11.md`.

## A regra

**O checkout principal fica na branch padrão; todo trabalho nasce em worktree.**
Vale para a sessão do usuário, não só para subagente. A pasta do repositório
(o checkout que `git worktree list` lista primeiro) não sai da `main`: branch
nova nasce com

```
git worktree add .claude/worktrees/<slug> -b fluxo/<slug> origin/main
```

ou com `EnterWorktree`, que faz o mesmo e move a sessão para lá — e o trabalho
inteiro (design, plano, código, commit) acontece dentro do worktree. Pedido
literal do Luís em 2026-09-08: "de preferência criar wt e não trabalhar na
pasta do repositório, deixando ele na main".

## Por que é regra, e não gosto (Issue #195)

Os **vigias agendados** resolvem a raiz pelo checkout principal
(`Split-Path -Parent $PSScriptRoot`) e rodam contra o que estiver lá: com ele
numa branch de trabalho, o sentinela roda contra código não mergeado. E
sessões paralelas se **co-locam** nesse diretório, então um `checkout -b` ali
move o HEAD de todo mundo — o gate de sessão co-locada recusa isso quando há
outra sessão viva, mas não quando a sessão está sozinha e a outra chega depois.

> 2026-09-02: dois fluxos trabalhados por horas com o principal em
> `fluxo/portoes` e `fluxo/recibo`, e o Luís corrigiu. De carona, um `ERROS.md`
> escrito pelo vigia na árvore errada carregava um identificador que a outra
> frente acabara de expurgar do repo público — commitar teria desfeito o
> conserto deles.

## A trava (2026-09-08)

`node scripts/estado.cjs iniciar` **recusa com exit 2** quando roda no checkout
principal (não é worktree linkado: `git rev-parse --git-dir` e `--git-common-dir`
resolvem para o mesmo lugar) com a branch atual diferente da padrão. A branch
padrão vem de `refs/remotes/origin/HEAD`; sem ela, `main`, senão `master`. A
mensagem traz a receita:

```
RECUSADO: o checkout principal está em 'fluxo/x', não em 'main'.
  git worktree add .claude/worktrees/x fluxo/x
  git checkout main
```

`exigir` no mesmo estado **só avisa**, em uma linha no stderr — trabalho em voo
não é derrubado por erro do estágio zero; `iniciar` é onde corrigir custa zero
linha. Fora de repositório git, nada muda: a caixa de areia de
`scripts/testa-estado.sh` não é repositório e continua verde sem edição.

O caso legítimo existe — clone dedicado a uma frente só — e se **declara**, em
vez de virar exceção de runtime: a chave `principal-livre: true` em
`.rainforest/config.json` do projeto desliga a recusa, pela mesma cadeia de
`hooks/lib/config.cjs` que os gates usam — lida por `resolverConfig().valores`,
**nunca** por `ligado()`: a chave tem sentido invertido (ligada, desliga a trava)
e `ligado()` devolve `true` em erro e em chave desconhecida, o que derrubaria a
trava em silêncio num descompasso de versão (mesmo cuidado de `branch-forcar`). Sem
config, a trava está ativa. Bateria: `scripts/testa-estado-principal.sh`.

## Avaliado e descartado

- **Hook `PreToolUse` sobre `git checkout -b`** — recusaria também o
  `git checkout main` de volta, que é exatamente o conserto.
- **Recusar também no `exigir`** — pega quem começou errado e continuou, mas
  derruba trabalho em voo por erro que já passou.
- **Só avisar** — era a decisão 2 em aberto da #195: aviso vira rotina, e o
  incidente de 2026-09-02 aconteceu com o fato visível no `git status`.
