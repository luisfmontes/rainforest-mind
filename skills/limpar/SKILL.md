---
name: limpar
description: Manutenção do rastro do fluxo rainforest-mind — worktree órfão, estado concluído e arquivo temporário. Invocável sozinha a qualquer momento, nunca bloqueia (exigir --estagio limpar sempre passa). Nunca remove worktree com alteração pendente sem a palavra do usuário.
---

# Limpar

Manutenção, não estágio de trabalho — por isso `exigir --estagio limpar`
sempre passa, e esta skill nunca é pré-requisito de nada. Ela existe porque
**worktree órfão nasce da sessão que não chegou ao `fechar`**: trabalho
interrompido, agente que travou, sessão fechada no meio.

## 1. Listar o que existe

Use o script que entende a diferença entre worktree de verdade e diretório
órfão:

```
node scripts/limpar-worktrees.cjs
```

O script lista todos os worktrees registrados e do disco, classifica cada um
como:

- **limpo**: worktree registrado, com `.git` próprio e sem alterações — pode ser removido
- **sujo**: tem `.git` próprio, mas há alterações — nunca remover sozinho
- **órfão**: diretório sem `.git` próprio (responde pelo pai)

**Por que `git -C <dir> status --porcelain` não é suficiente:** quando `<dir>`
não tem `.git` próprio, o git responde pelo repositório pai, mascarando que o
diretório é órfão (Issue #142). O script confere, por `realpath`, se o
`toplevel` lido DE DENTRO do diretório bate com o próprio diretório.

## 2. Remover só o que está limpo

Worktree classificado como **limpo** remove sem perguntar:

```
node scripts/limpar-worktrees.cjs --remover
```

Worktree **sujo** ou **órfão** nunca é removido — o script não toca neles.

**Worktree com alteração pendente (sujo)**: mostre ao usuário o que há
dentro e deixe a decisão — recuperar, descartar, ou deixar por enquanto.

## 3. A branch, que sobrevive ao worktree

Remover o worktree **não** remove a branch. Ela fica, e ninguém repara — medido
neste repo em 11/08: zero worktree órfão no disco e **sete branches**
`worktree-agent-*` penduradas.

```
node scripts/limpar-branches.cjs
```

Sem `--remover` ele só lista, em oito classes. As que importam:

- **`resolvida-local`** — já está na base, nunca foi empurrada. É o resíduo de
  worktree de agente. Sai com `-d`, sem risco: a base contém tudo.
- **`sumiu-divergente`** — o remoto foi apagado e a base **não** contém aqueles
  commits. É o caso do *squash merge*: o trabalho está lá em cima, mas o `-d`
  recusa porque para o git ele nunca chegou. Só o `-D` apaga — e é por isso que
  esse `-D` existe, não por desleixo.
- **`mergeada-por-squash`** — o PR foi mergeado por squash e o remoto **não** foi
  apagado, então nenhum sinal de git acende: `--merged` é falso porque o squash
  não deixa os commits na base, e o upstream não está `gone`. Quem decide é o
  estado do PR (`gh`). Também só sai com `-D`. Sem o `gh` respondendo, a branch
  fica `viva` e o script avisa em uma linha — falta de resposta nunca vira
  remoção. Nasceu da Issue #14, em que três branches mergeadas passavam por
  trabalho vivo.
- **`viva`** — não está na base e o remoto está de pé. **Nunca entra na remoção**,
  nem com `--forcar`.
- **`padrao`** — a branch padrão do repositório (`origin/HEAD`). **Nunca entra na
  remoção**, seja qual for a `--base`. Nasceu da Issue #23, e o ponto é que a
  classificação estava *certa* e levava ao lugar errado — ver logo abaixo.

E a base é escolhível: `--base <ref>` mede contra a ref que você passar, em vez
de `origin/HEAD`. É o que permite limpar resíduo de agente num fluxo cujo
trabalho ainda não chegou à `main` — sem isso, tudo que vive só na branch de
trabalho aparece como `viva`.

Esse `--base` tem um efeito que não é óbvio: a branch de trabalho **saiu** da
`main`, então a `main` está contida nela, então a `main` satisfaz "já está na
base". Em 2026-08-19 isso apagou a `main` local junto com as 11 branches de
agente, e o passo seguinte do `fechar` morreu com `fatal: ambiguous argument
'main..HEAD'`. Estar na `main` não protegia — no incidente a pessoa estava na
branch de trabalho. Por isso a classe `padrao` existe separada da `atual` e da
`base`, e por isso ela não olha o valor de `--base`.

O modo de remoção é configurável, e o padrão é o conservador:

```
node scripts/limpar-branches.cjs --remover              # -d
node scripts/limpar-branches.cjs --remover --forcar     # -D só nesta rodada
node scripts/setup.cjs --ligar branch-forcar            # -D como padrão
```

**Remover exige estar na base e com ela em dia** — o script recusa e explica.
Não é preciosismo: tudo é medido contra a base *local*, e base velha faz branch
já mergeada parecer viva. Aí a limpeza não limpa e parece que não havia o que
limpar.

O remoto é decisão à parte (`--remoto`), e vale perguntar antes: branch local se
recria com o SHA — que o script imprime ao apagar —, branch remota some para
todo mundo.

## 4. Resto do rastro

- **Estado concluído**: `node scripts/estado.cjs listar` mostra `(completo)`
  para trabalhos com os sete estágios fechados. Não é para apagar o JSON
  (fica em `docs/rainforest/estado/`, versionado, e serve de histórico) — é
  para conferir se o worktree correspondente já devia ter sumido no passo 2.
- **Arquivo temporário**: log de comando, harness descartável, artefato de
  teste que sobrou de uma sessão que não passou pelo `fechar`. Mesma regra
  do passo 2: confira de quem é antes de apagar.

## Condição de parada

Worktree com alteração não commitada **nunca é removido sem a palavra
dele** — perda de trabalho não tem desfazer. Na dúvida sobre se uma
alteração é do trabalho corrente ou de outra sessão paralela, mostrar e
perguntar custa uma linha; apagar errado não tem volta.
