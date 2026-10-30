---
name: fechar
description: "Use no estágio 'fechar' do fluxo rainforest-mind — depois de 'verificar' fechado, é o fim do fluxo: commit, remoção dos worktrees e abertura do PR, que é o destino padrão de toda branch."
---

# Fechar

Abre sempre com:

```
node scripts/estado.cjs exigir --slug <slug> --estagio fechar
```

Exit 2 significa que `verificar` ainda não fechou com `ok`, ou que algum
estágio ainda tem pendência sem destino — pare, não force `marcar` por cima
nem edite o arquivo de estado. No segundo caso o remédio é gravar o `destinos`
da pendência com `node scripts/estado.cjs destinar --slug <slug> --estagio <e> --json '{"destinos":[...]}'`
(resolvida com `evidencia`, plantada com `ref`, descartada com `motivo`), como a
mensagem do próprio `exigir` mostra. O `destinar` grava destinos (acrescenta, ou substitui o de uma
pendência que já tinha) e tira de `pendentes` as destinadas: não muda `status` nem
refaz os gates de evidência do estágio.

O destino padrão é `resolvida`: o achado que cabe neste PR (mesma classe do
conserto, ou pequeno) se corrige aqui antes do merge. `plantada` com ref de Issue
fica para o que não cabe: outra área, decisão aberta do usuário, trabalho grande
ou repo de outro dono (regra 6).

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

**Publicar é um script, não prosa.** O push e o merge passam por
`scripts/publicar-branch.cjs`. Ele confere o que a sessão costumava declarar pelo
texto do CLI. Os dois comandos `gh` que escrevem continuam com você, pelo Bash,
para o `gate-fechar-issue` conferir a evidência das Issues que o PR fecha.

1. `node scripts/publicar-branch.cjs publicar` faz `fetch`, `merge-tree` contra a
   base, push e confere `HEAD == @{u}`. Última linha `PR aberto: <n>`: o PR já
   existe, use esse número. `PR aberto: nenhum`: rode
   `gh pr create --title "<título>" --body-file <arquivo>` com o corpo abaixo. `PR aberto: n/a`: o remoto não é GitHub, o passo termina no push.
2. `node scripts/publicar-branch.cjs esperar-ci --pr <n>`, sempre em background
   (Monitor ou `run_in_background`), porque as baterias levam minutos. Diga ao
   usuário de quem é a bola enquanto espera.
3. Com `esperar-ci` saindo 0, rode `gh pr merge <n> --squash`, nunca `--auto`. Sem
   check obrigatório na branch, o `--auto` mergeia na hora, sem esperar o CI, e o
   gate o barra. Depois rode
   `node scripts/publicar-branch.cjs confirmar-merge --pr <n>`. Só o exit 0 dele
   (state `MERGED`) prova o merge. A linha de sucesso do `gh` não prova.

**Código mudou depois do `verificar ok`** (CI vermelho): `exigir --estagio fechar`
e `marcar fechar ok` recusam (exit 2) mudança da branch depois do HEAD gravado (a da
`main` não conta) e edição rastreada não commitada. Rode o `exigir` de novo antes de
republicar. Com `--raiz`, só avisa. A volta é `node scripts/estado.cjs reabrir --slug <slug> --estagio executar
--motivo "<o que mudou>"`: revisar e verificar de novo (#567).

Com a chave `executar-autonomo` ligada, há três diferenças: o conflito que fica só em versão ou CHANGELOG
se resolve sem parar, a saída de `estado.cjs decididos` entra no corpo do PR, e o fim avisa por
push. Ver `skills/executar/references/modo-autonomo.md`.

| exit | quem sai | o que fazer |
|---|---|---|
| `0` | qualquer um | segue para o próximo item |
| `1` | qualquer um | uso errado; corrija o comando |
| `3` | `publicar` | conflito com a base, nada foi empurrado: traga a base (merge ou rebase, ato seu) e rode de novo |
| `4` | `publicar` | push recusado ou `HEAD != @{u}`: não abra PR; leia o stderr |
| `5` | `esperar-ci` | CI vermelho ou sem check: `reabrir` (acima), conserte na branch, não mergeie |
| `6` | `confirmar-merge` | o state não virou `MERGED` (ou o PR fechou): não declare merge; mostre o `gh pr view` |
| `7` | `esperar-ci` | CI verde, mas a chave `fechar-mergear` está desligada: pare no PR aberto e informe o número |
| `8` | `esperar-ci` | repositório sem CI de PR (nenhum workflow do checkout alcança o PR, e o PR sem check): a evidência é o `verificar`; com `fechar-mergear` ligada mergeie, senão pare no PR aberto |
| `69` | qualquer um | ambiente (rede, `gh` ausente ou sem auth, remoto não GitHub): anuncie em uma linha (regra 14) |

A chave `fechar-mergear` vem desligada por padrão: em repositório de cliente, o
merge é do humano. Neste repositório ela está ligada em `.rainforest/config.json`.

**Corpo do PR — quatro seções, nesta ordem.** O PR é o gargalo da revisão humana;
o corpo existe para torná-la barata. Sem preâmbulo, prosa curta:

```markdown
## Resumo
<o menor visual que deixa a mudança clara>

## Evidência
- **Antes:** <saída, teste vermelho, print>
  **Depois:** <a mesma coisa, agora certa>

## Perigo de merge
**Porta:** <mão dupla | mão única> — <uma linha, se precisar>
**Raio de impacto:** <uma palavra> — <o que pode quebrar, se precisar>

## Deixado para depois
<a saída do `deixado`, colada como está>
```

- **Resumo**: escolha a menor vista que serve — pseudocódigo para lógica, árvore
  de chamadas para fluxo, árvore de arquivos para refatoração ampla, `diff` da
  *forma* (não do código) quando a estrutura já existe, Mermaid para interação.
  Uma, às vezes duas; nunca todas.
- **Evidência**: execução real, antes e depois — o mesmo comando, as duas
  saídas. O `EVIDENCIA:` que o `verificar` gravou nos portões é a fonte
  natural; "li o código e deve funcionar" não é evidência (regra 12).
- **Perigo de merge**: **mão dupla** é o que se desfaz com um revert; **mão
  única** é o que age no mundo e não volta (dado apagado, publicação, migração,
  mensagem enviada). Mão dupla com raio pequeno pede revisão leve — dizer isso
  é o que poupa o tempo de quem revisa.
- **Deixado para depois**: cole a saída de `node scripts/estado.cjs deixado --slug <slug>` como está, inclusive a linha `nada ficou para depois`. É a resposta, no PR, ao que o fluxo adiou: cada pendência com o seu destino (resolvida, plantada ou descartada).

Template enxertado da skill `pr` (mattpocock/skills v1.3, MIT), que adapta o
`show-me` de Dex Horthy (HumanLayer).

**Corpo do PR — palavras-chave de fechamento.** O GitHub reconhece, em
**inglês e case-insensitive**, estas palavras antes de cada número de issue:
`close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`,
`resolved`. A **palavra precisa repetir antes de cada número**, senão fecha só
a primeira: `Closes #81, closes #79` funciona; `Closes #81 e #79` fecha só
a #81 — e uma palavra-chave em português (`Fecha #81 e #79`) não é
reconhecida, deixando as issues abertas.

**PR empilhada: troque a base da de cima antes de mergear a de baixo.** Mergear a
PR de baixo apaga a branch dela, e a PR que a tinha como base fecha no ato e não
reabre (`gh pr reopen` e `gh pr edit --base` recusam depois). Antes do merge:
`gh pr edit <de-cima> --base main`; só então `gh pr merge <de-baixo> --squash
--delete-branch`. Com `delete_branch_on_merge` ligado (parágrafo abaixo) o risco é
o mesmo, mesmo sem a flag.

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
Tag e release do GitHub saem sozinhas do `.github/workflows/release.yml` quando
o bump chega à `main`: não há passo de release no `fechar`.

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

Abra com o **balanço de quem conduziu**: as observações que a própria sessão
aprendeu (método, ferramenta, defeito), cada uma já registrada (regra 13). Só
depois pergunte, em uma linha: **"alguma observação desta sessão?"** — é o gancho
para o que não foi registrado no meio do trabalho. Pergunta sem balanço próprio
conta como encerramento incompleto: devolve a ele o levantamento que a sessão
tinha obrigação de fazer.

## Fechamento do estágio

```
node scripts/estado.cjs marcar --slug <slug> --estagio fechar --status ok \
  --json '{"acao":"merge|pr|manteve"}'
```

`acao` é o que **de fato aconteceu** no passo 5. `merge` só vale com o
`confirmar-merge` saindo 0. `pr` vale quando o PR ficou aberto (chave
`fechar-mergear` desligada, ou CI ainda sem veredito). `manteve` vale quando o
usuário pediu para não abrir o PR. Nunca a que
pareceria mais razoável em retrospecto — o registro serve para saber o que foi
feito, não para justificar.

O `marcar ... fechar ok` grava o estado no JSON, sujando o `git status`. Se
houver pendência, o commit se repete: os passos 1 a 4 fizeram sua parte, e o
estágio só termina com a árvore limpa.

## Conferir de fora se o fluxo fechou: `concluido`

Para quem confere depois, fora do fluxo, se um trabalho terminou: `references/concluido.md`.

## Condição de parada

Árvore suja com algo alheio ao trabalho: pare e mostre, nunca commite por
cima. E o passo 5 não fecha sem o PR existir: `acao: "pr"` sem número de PR é
estágio marcado por cima de trabalho que não aconteceu.
