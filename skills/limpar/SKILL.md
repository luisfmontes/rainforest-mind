---
name: limpar
description: Manutenção do rastro da esteira rainforest-mind — worktree órfão, estado concluído e arquivo temporário. Invocável sozinha a qualquer momento, nunca bloqueia (exigir --estagio limpar sempre passa). Nunca remove worktree com alteração pendente sem a palavra do Luís.
---

# Limpar

Manutenção, não estágio de trabalho — por isso `exigir --estagio limpar`
sempre passa, e esta skill nunca é pré-requisito de nada. Ela existe porque
**worktree órfão nasce da sessão que não chegou ao `fechar`**: trabalho
interrompido, agente que travou, sessão fechada no meio.

## 1. Listar o que existe

```
git worktree list
```

Para cada worktree que não é o repositório principal, entre nele e confira
o estado:

```
git -C <caminho> status --porcelain
```

Separe em dois grupos: **limpo** (porcelain vazio, nada para commitar) e
**com alteração pendente** (qualquer coisa na saída, staged ou não).

## 2. Remover só o que está limpo

Worktree limpo remove **sem perguntar**:

```
git worktree remove <caminho>
```

Worktree com alteração pendente **nunca é removido sozinho** — mostre ao
Luís **o que há dentro** (`git -C <caminho> status --porcelain` e, se
ajudar a decidir, `git -C <caminho> diff --stat`) e deixe a decisão com
ele: recuperar, descartar, ou deixar por enquanto.

Depois de remover, sempre:

```
git worktree prune
```

## 3. Resto do rastro

- **Estado concluído**: `node scripts/estado.cjs listar` mostra `(completo)`
  para trabalhos com os sete estágios fechados. Não é para apagar o JSON
  (fica em `.rainforest/estado/`, fora do git, e serve de histórico) — é
  para conferir se o worktree correspondente já devia ter sumido no passo 2.
- **Arquivo temporário**: log de comando, harness descartável, artefato de
  teste que sobrou de uma sessão que não passou pelo `fechar`. Mesma regra
  do passo 2: confira de quem é antes de apagar.

## Condição de parada

Worktree com alteração não commitada **nunca é removido sem a palavra
dele** — perda de trabalho não tem desfazer. Na dúvida sobre se uma
alteração é do trabalho corrente ou de outra sessão paralela, mostrar e
perguntar custa uma linha; apagar errado não tem volta.
