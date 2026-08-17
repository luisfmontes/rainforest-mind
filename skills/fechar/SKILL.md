---
name: fechar
description: Use no estágio 'fechar' da esteira rainforest-mind — depois de 'verificar' fechado, é o fim da esteira, com commit, remoção de worktrees, e a pergunta de destino ao usuário. Nunca decide o destino por conta própria.
---

# Fechar

Abre sempre com:

```
node scripts/estado.cjs exigir --slug <slug> --estagio fechar
```

Exit 2 significa que `verificar` ainda não fechou com `ok` — pare, não
force `marcar` por cima.

Quatro passos, nesta ordem.

## 1. Commitar o pendente

Confira `git status` na branch de trabalho. Comite o que restou, com
mensagem que diz **o que** mudou e **por quê** (não "fechamento da
esteira" sozinho). `git add -A` é **proibido**: o hook
`gate-staging-total.cjs` barra com exit 2 fora de worktree linkado —
adicione por caminho.

**Árvore suja de algo que não é deste trabalho é condição de parada**:
pare e mostre o `git status` ao usuário em vez de commitar por cima. Nunca
assuma que um arquivo modificado é seu porque está lá.

## 2. Limpar o repositório local

Arquivo temporário, log e artefato de teste que a **própria esteira**
gerou e que não é entrega (harness descartável da fase de execução, log de
comando rodado à mão, etc.) — apague. **Confira de quem é antes de
apagar**: outra sessão trabalha no mesmo working tree (`git worktree list`
mostra quem mais está ativo), e o que não foi esta esteira que criou fica
de pé.

## 3. Remover os worktrees deste trabalho

```
git worktree remove <caminho>
git worktree prune
```

Invoque a skill `limpar` para isso — ela já separa o que tem trabalho
pendente do que está limpo, e decide o que remove sem perguntar.

## 4. Perguntar o destino

Três opções numeradas, e **para**:

1. Merge local
2. Abrir PR
3. Manter a branch como está

**Não decida por ele.** Mesmo que uma opção pareça óbvia (branch pequena,
sem conflito), a escolha entre merge, PR e manter é dele — nomear as três
e esperar a resposta é o próprio ponto deste passo.

## Depois: writeback

Se este trabalho avançou o **foco ativo** (FOCO.md, seção Ativo), acrescente
uma linha datada na seção **Avanços**: `- AAAA-MM-DD: o que andou` (regra 5
do `rainforest-mind`). Não avançou foco nenhum → não escreve nada aí.

Escreveu avanço, rode em seguida:

```
node scripts/foco.cjs rotacionar --aplicar
```

É o que mantém o bloco "Avanços" dentro do teto: o que passa vai para o
`AVANCOS.md` ao lado, e o FOCO.md ganha a linha de histórico apontando para
lá. Sem isso o arquivo só cresce, e ele é lido inteiro em toda sessão que
precisa conferir prazo, marco ou avanço.

Pergunte, em uma linha: **"alguma observação desta sessão?"** (regra 13) —
é o gancho para o que não foi registrado no meio do trabalho.

## Fechamento do estágio

```
node scripts/estado.cjs marcar --slug <slug> --estagio fechar --status ok \
  --json '{"acao":"merge|pr|manteve"}'
```

`acao` é a resposta que o usuário deu no passo 4 — nunca a que pareceria mais
razoável.

O `marcar ... fechar ok` grava o estado no JSON, sujando o `git status`. Se
houver pendência, o commit se repete: os passos 1 a 3 fizeram sua parte, e o
estágio só termina com a árvore limpa.

## Condição de parada

Árvore suja com algo alheio ao trabalho: pare e mostre, nunca commite por
cima. E a pergunta do passo 4 não tem resposta padrão — sem ela, o estágio
não fecha.
