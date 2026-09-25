---
name: fechar
description: "Use no estágio 'fechar' do fluxo rainforest-mind — depois de 'verificar' fechado, é o fim do fluxo: commit, remoção dos worktrees e abertura do PR, que é o destino padrão de toda branch."
---

# Fechar

Abre sempre com:

```
node scripts/estado.cjs exigir --slug <slug> --estagio fechar
```

Exit 2 significa que `verificar` ainda não fechou com `ok` — pare, não
force `marcar` por cima.

Seis passos, nesta ordem.

## 1. Commitar o pendente

Confira `git status` na branch de trabalho. Comite o que restou, com
mensagem que diz **o que** mudou e **por quê** (não "fechamento da
fluxo" sozinho). `git add -A` é **proibido**: o hook
`gate-staging-total.cjs` barra com exit 2 fora de worktree linkado —
adicione por caminho.

**Árvore suja de algo que não é deste trabalho é condição de parada**:
pare e mostre o `git status` ao usuário em vez de commitar por cima. Nunca
assuma que um arquivo modificado é seu porque está lá.

## 2. Fechar as Issues do plano

Sem `--confirmo`: o fechamento de Issue é o resultado natural do fluxo, não
um ato que exige frase digitada (a frase continua obrigatória só para apagar
branch e worktree sujo, em `limpar-branches`/`limpar-worktrees`). Para cada
Issue que o plano deste fluxo resolveu, feche por uma das duas formas — nunca
um "ou" vago, escolha pinada pela existência do portão:

**(a) Existe `docs/rainforest/portoes/<slug>.md` para este fluxo:**

```
node scripts/portoes.cjs rodar docs/rainforest/portoes/<slug>.md
node scripts/fechar-issue.cjs <n> --comando "node scripts/portoes.cjs rodar docs/rainforest/portoes/<slug>.md" --saida-arquivo docs/rainforest/portoes/<slug>.md
```

`rodar` grava o campo `EVIDENCIA:` de volta no próprio arquivo do portão —
depois de rodar, o arquivo já é comando+saída, não só a definição do portão.

**(b) Sem portão para este fluxo** (não existe
`docs/rainforest/portoes/<slug>.md`): rode o comando do critério de
pronto da Issue redirecionando a saída para um arquivo **dentro do
repositório** (ex.: `docs/rainforest/estado/<slug>-fechar-<n>.txt`, apagado
depois de usado — mesma disciplina de "limpar o repositório local" do passo
seguinte) e passe esse arquivo em `--saida-arquivo`:

```
<comando do critério de pronto> > docs/rainforest/estado/<slug>-fechar-<n>.txt 2>&1
node scripts/fechar-issue.cjs <n> --comando "<comando do critério de pronto>" --saida-arquivo docs/rainforest/estado/<slug>-fechar-<n>.txt
rm docs/rainforest/estado/<slug>-fechar-<n>.txt
```

**Nunca um caminho fora do repositório**: `--saida-arquivo` recusa
(`estaNoRepositorio` em `fechar-issue.cjs`) e `--saida` recusa qualquer valor
que já seja o caminho de um arquivo existente, colado ou não — "o diretório
temporário da sessão" não é atalho válido: colar um caminho onde se espera
saída sempre é erro.

## 3. Limpar o repositório local

Arquivo temporário, log e artefato de teste que o **próprio fluxo**
gerou e que não é entrega (harness descartável da fase de execução, log de
comando rodado à mão, etc.) — apague. **Confira de quem é antes de
apagar**: outra sessão trabalha no mesmo working tree (`git worktree list`
mostra quem mais está ativo), e o que não foi este fluxo que criou fica
de pé.

## 4. Remover os worktrees deste trabalho

```
git worktree remove <caminho>
git worktree prune
```

Invoque a skill `limpar` para isso — ela já separa o que tem trabalho
pendente do que está limpo, e decide o que remove sem perguntar.

## 5. Abrir PR

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
a #81 — e uma palavra-chave em português (`Fecha #81 e #79`) não é
reconhecida, deixando as issues abertas.

**A branch remota sai sozinha no merge.** O repositório tem
`delete_branch_on_merge` ligado desde 2026-08-26, então o `gh pr merge` apaga a
`origin/<branch>` sem `--delete-branch`. Isso **não** alcança a branch local nem
o worktree — os dois continuam sendo trabalho do passo 3 e do passo 4, e é
justamente a metade que sobrevive e ninguém vê. Fork deste repositório não herda
a configuração: quem clonar liga com
`gh api -X PATCH repos/<dono>/<repo> -f delete_branch_on_merge=true`.

## 6. Conferir se a versão ficou para trás

Depois do PR aberto, no repositório do **plugin**:

```
node scripts/conferir-versao.cjs
```

`exit 0` segue; **`exit 2` para e sobe uma linha** para o usuário, com o número
de commits acumulados e a recomendação de subir a versão — e **qual casa**: PATCH
se o lote só consertou, MINOR se entrou coisa nova ou mudou contrato (a tabela
está no `CONTRIBUTING.md`). Não suba a versão por
conta própria — release é decisão dele, e o commit de bump é entrega própria.

**Antes de recomendar o bump, pergunte: outra pessoa faz o release lendo só o README?**
Se o README não descreve o que mudou de um jeito que alguém que não viu o
trabalho consiga instalar e usar, a doc entra antes do bump — porquê: no
plugin de dados analisado em 2026-09-12, 89% dos commits eram de uma pessoa
só, e o release inteiro morava em 187 KB de prosa que só ela sabia navegar.

O motivo é que o plugin que **executa** não é o clone: é o cache
`~/.claude/plugins/cache/<marketplace>/<plugin>/<versão>/`, indexado pela
versão. Sem bump não existe versão nova para o `claude plugin update` buscar, e
o trabalho fica na `main` sem chegar em máquina nenhuma — inclusive na do
usuário.

> O risco é silencioso: nada no repositório aplica o bump automaticamente, e
> hábito não dispara sozinho quando ninguém está olhando no momento em que dá
> para agir.

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

`acao` é o que **de fato aconteceu** no passo 5: `pr` no caminho normal, e
`merge` ou `manteve` só quando o usuário pediu outra coisa. Nunca a que
pareceria mais razoável em retrospecto — o registro serve para saber o que foi
feito, não para justificar.

O `marcar ... fechar ok` grava o estado no JSON, sujando o `git status`. Se
houver pendência, o commit se repete: os passos 1 a 4 fizeram sua parte, e o
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

Essa recusa é sobre **aviso falado** — um vigia que interrompe toda sessão
para dizer algo que ninguém perguntou. `hooks/titulo-sessao-end.cjs` também
roda no `SessionEnd`, mas escreve o estado do fluxo no título de uma sessão
já encerrada: não fala com ninguém, então não reabre esta decisão (ver
`docs/rainforest/design/2026-09-15-titulo-de-sessao-encerrada.md`, "Fora de
escopo").

**Fica de fora, Issue #180**: o estágio que despacha agente em background
aposta que o turno dura mais que o agente — aposta perdida em toda sessão
não interativa. O `concluido` diz que o fluxo ficou pela metade; ele **não**
impede que fique.

## Condição de parada

Árvore suja com algo alheio ao trabalho: pare e mostre, nunca commite por
cima. E o passo 5 não fecha sem o PR existir: `acao: "pr"` sem número de PR é
estágio marcado por cima de trabalho que não aconteceu.
