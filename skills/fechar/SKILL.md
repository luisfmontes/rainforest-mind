---
name: fechar
description: Use no estágio 'fechar' do fluxo rainforest-mind — depois de 'verificar' fechado, é o fim do fluxo: commit, remoção dos worktrees e abertura do PR, que é o destino padrão de toda branch.
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
fluxo" sozinho). `git add -A` é **proibido**: o hook
`gate-staging-total.cjs` barra com exit 2 fora de worktree linkado —
adicione por caminho.

**Árvore suja de algo que não é deste trabalho é condição de parada**:
pare e mostre o `git status` ao usuário em vez de commitar por cima. Nunca
assuma que um arquivo modificado é seu porque está lá.

## 2. Limpar o repositório local

Arquivo temporário, log e artefato de teste que o **próprio fluxo**
gerou e que não é entrega (harness descartável da fase de execução, log de
comando rodado à mão, etc.) — apague. **Confira de quem é antes de
apagar**: outra sessão trabalha no mesmo working tree (`git worktree list`
mostra quem mais está ativo), e o que não foi este fluxo que criou fica
de pé.

## 3. Remover os worktrees deste trabalho

```
git worktree remove <caminho>
git worktree prune
```

Invoque a skill `limpar` para isso — ela já separa o que tem trabalho
pendente do que está limpo, e decide o que remove sem perguntar.

## 4. Abrir PR

**O destino da branch é sempre PR.** Abra o PR e informe o número — sem menu,
sem pergunta. O menu de três opções que ficava aqui foi removido em 2026-08-24:
a escolha já estava feita em toda rodada, e perguntar o que já está respondido
só custava um turno.

Isso não tira a palavra do usuário: se **ele** disser outra coisa (mergear
direto, manter a branch), vale o que ele disse, e é isso que vai em `acao` no
fechamento do estágio.

**Corpo do PR — palavras-chave de fechamento.** O GitHub reconhece, em
**inglês e case-insensitive**, estas palavras antes de cada número de issue:
`close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`,
`resolved`. A **palavra precisa repetir antes de cada número**, senão fecha só
a primeira: `Closes #81, closes #79` funciona; `Closes #81 e #79` fecha só
a #81. Incidente 2026-08-24 (PR #85): usou `Fecha #81 e #79` em português —
nenhuma palavra-chave foi reconhecida e as duas issues continuaram abertas.

**A branch remota sai sozinha no merge.** O repositório tem
`delete_branch_on_merge` ligado desde 2026-08-26, então o `gh pr merge` apaga a
`origin/<branch>` sem `--delete-branch`. Isso **não** alcança a branch local nem
o worktree — os dois continuam sendo trabalho do passo 2 e do passo 3, e é
justamente a metade que sobrevive e ninguém vê. Fork deste repositório não herda
a configuração: quem clonar liga com
`gh api -X PATCH repos/<dono>/<repo> -f delete_branch_on_merge=true`.

## 5. Conferir se a versão ficou para trás

Depois do PR aberto, no repositório do **plugin**:

```
node scripts/conferir-versao.cjs
```

`exit 0` segue; **`exit 2` para e sobe uma linha** para o usuário, com o número
de commits acumulados e a recomendação de subir a versão — e **qual casa**: PATCH
se o lote só consertou, MINOR se entrou coisa nova ou mudou contrato (a tabela
está no `CONTRIBUTING.md`). Não suba a versão por
conta própria — release é decisão dele, e o commit de bump é entrega própria.

O motivo é que o plugin que **executa** não é o clone: é o cache
`~/.claude/plugins/cache/<marketplace>/<plugin>/<versão>/`, indexado pela
versão. Sem bump não existe versão nova para o `claude plugin update` buscar, e
o trabalho fica na `main` sem chegar em máquina nenhuma — inclusive na do
usuário.

> 2026-08-26: o `plugin.json` estava em 0.77.0 desde o dia anterior e a `main`
> tinha 18 commits além disso — quatro PRs de regra, três defeitos de produção,
> uma trava de borda nova. Nada rodando. O `/saude` já dizia "o que EXECUTA está
> atrás: 18 commit(s) atrás"; ninguém olhava no momento em que dava para agir.
> A regra do bump não estava escrita em lugar nenhum — nem aqui, nem no
> `CONTRIBUTING.md`, nem nas 17 regras. Era hábito, e hábito não dispara.

Fora do repositório do plugin, o comando sai `0` dizendo que não deu para medir.
Falha **aberta** de propósito: isto não é guarda-corpo de segurança.

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

`acao` é o que **de fato aconteceu** no passo 4: `pr` no caminho normal, e
`merge` ou `manteve` só quando o usuário pediu outra coisa. Nunca a que
pareceria mais razoável em retrospecto — o registro serve para saber o que foi
feito, não para justificar.

O `marcar ... fechar ok` grava o estado no JSON, sujando o `git status`. Se
houver pendência, o commit se repete: os passos 1 a 3 fizeram sua parte, e o
estágio só termina com a árvore limpa.

## Conferir de fora se o fluxo fechou: `concluido`

```
node scripts/estado.cjs concluido --slug <slug>
```

Sai `0` se o fluxo fechou até o `fechar`, `2` imprimindo o estágio pendente
se não, `1` se o slug não existe. Sem `--slug`, varre todos os fluxos em
`docs/rainforest/estado/`: `0` se todos concluídos (ou nenhum arquivo), `2`
listando slug e estágio de cada um aberto.

Para que serve, e para quem: quem dispara o fluxo por script — `claude -p`,
CI, uma rodada de bench — não distingue, pelo exit code do **processo**, um
fluxo que fechou de um que morreu no meio do `revisar`: os dois devolvem
`0`. Este verbo responde essa pergunta, sob demanda.

**Não está pendurado no `SessionEnd`.** Pendurar ali transforma um verbo que
responde quando perguntado num vigia que fala sozinho toda sessão, inclusive
nas que legitimamente não têm fluxo aberto. Se o aviso automático fizer
falta depois do verbo em uso, vira fluxo próprio com o barulho medido em vez
de chutado.

**Fica de fora, Issue #180**: o estágio que despacha agente em background
aposta que o turno dura mais que o agente — aposta perdida em toda sessão
não interativa. O `concluido` diz que o fluxo ficou pela metade; ele **não**
impede que fique.

## Condição de parada

Árvore suja com algo alheio ao trabalho: pare e mostre, nunca commite por
cima. E o passo 4 não fecha sem o PR existir: `acao: "pr"` sem número de PR é
estágio marcado por cima de trabalho que não aconteceu.
