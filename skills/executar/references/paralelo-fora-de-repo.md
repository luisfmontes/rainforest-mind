# Tarefa paralela fora de repo: `fluxo/<slug>-t<n>`

Quando a sessão não está dentro do repositório (#565), `isolation: "worktree"` não
despacha. Os worktrees se criam à mão e se declaram na linha `Worktree:` do briefing.

A portaria lê a branch do worktree declarado, e o git não deixa a mesma branch em dois
worktrees. Por isso cada tarefa paralela ganha a sua branch, criada da ponta de
`fluxo/<slug>`:

```
git worktree add <dir> -b fluxo/<slug>-t<n> fluxo/<slug>
```

A forma `-t<n>`, só com dígitos, casa com o fluxo `<slug>` (#613, #610). Outro sufixo
(`-tarefa1`, `-tx`) não casa. A branch `fluxo/<slug>/t<n>`, com barra, não existe
enquanto `fluxo/<slug>` existir, por conflito de refs no git.

Dentro do repositório nada muda: a portaria lê a branch de quem despacha, que é
`fluxo/<slug>`, e os worktrees de `isolation: "worktree"` podem ter qualquer nome.
