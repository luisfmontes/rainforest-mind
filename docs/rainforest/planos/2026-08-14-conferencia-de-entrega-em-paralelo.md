# Plano: Conferencia de entrega e teste de saude sobrevivem a despacho paralelo

Design: docs/rainforest/design/2026-08-14-conferencia-de-entrega-em-paralelo.md

## O que não pode quebrar

Medido no repositorio antes de escrever este plano, em 2026-08-14 — os tres
sao a linha de base contra a qual "verde" significa alguma coisa:

- `bash scripts/testa-conferir-entrega.sh` sai **0** hoje (16 casos). Nenhum
  caso existente pode ser reescrito para acomodar a mudanca: eles sao a prova
  de que o comportamento sem `--paralelo` nao mudou.
- `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh`
  sai **0** hoje (Python 3.13.5 no PATH). A paridade dos gemeos e o motivo de a
  variavel `CONFERIR` existir.
- `bash scripts/testa-saude.sh` sai **0** hoje. Ele passa por acidente: o
  historico atual e linear o bastante. Verde depois da mudanca nao prova nada
  sozinho — so prova junto com o cenario de merge da tarefa 2.
- **Sem `--paralelo`, `conferir-entrega` se comporta exatamente como hoje.** A
  flag e a unica porta do comportamento novo.
- Os codigos de saida continuam sendo 0 aprovado, 1 reprovado, 2 erro de uso.
- Aviso nao derruba exit 0; falha derruba para 1.

## Tarefas

### 1. Ancestralidade, cruzamento e avisos no conferir-entrega.cjs [tipo: implementar]
atende: D1, D2, D3, D4
arquivos: `scripts/conferir-entrega.cjs`
depende de: nenhuma
paralela: sim
pronto quando: `bash scripts/testa-conferir-entrega.sh; echo EXIT=$?` devolve `EXIT=0` com os 16 casos existentes intactos (nenhuma linha de caso reescrita — o diff nao toca `scripts/testa-conferir-entrega.sh`), E `node scripts/conferir-entrega.cjs --worktree . --paralelo 2>&1 | head -1` NAO contem `opcao desconhecida`.

### 2. Situacao A do testa-saude.sh roda contra fonte sintetica [tipo: teste]
atende: D5
arquivos: `scripts/testa-saude.sh`
depende de: nenhuma
paralela: sim
pronto quando: `bash scripts/testa-saude.sh; echo EXIT=$?` devolve `EXIT=0` **rodando de uma base cujo historico contem merge commits nos ultimos tres passos** — a partir de 2026-08-15 a propria branch de trabalho serve, porque a integracao das tarefas 1 e 3 colocou dois merges ali. A situacao A tem de aparecer como `ok`.

**Emenda de 2026-08-15, segunda rodada — a tarefa era incumprivel como escrita.**
A segunda tentativa entregou diff VAZIO relatando sucesso. Investigando, a causa
nao era o agente: enquanto o fixture clonar o repositorio real, o cenario
"exatamente 3 commits atras" depende da sorte do historico, e naquele momento
ele **nao existia** — as contagens dos dez ancestrais do HEAD eram
`0, 1, 2, 4, 4, 5, 7, 8, 8, 9`, sem o 3. D5 foi reescrita: a situacao A passa a
montar uma **fonte sintetica** (repo proprio, clone com 1 commit, mais 3 commits
na fonte depois do clone), ficando 3 atras por construcao. Registro tambem que
**entrega vazia passa pelas seis checagens do `conferir-entrega`** — so o
criterio de diff do plano a pegou.

**Historico da emenda — o criterio anterior era jogavel.** Ele pedia
`grep -c 'HEAD~3' scripts/testa-saude.sh` devolvendo `0` mais a suite verde. A
primeira tentativa satisfez os dois **sem consertar nada**: trocou
`reset --hard HEAD~3` por
`rev-list --first-parent -n 4 HEAD | tail -1`, que e o mesmo commit por outro
caminho, e a suite passou porque o worktree do agente nascia numa base ainda
linear. Medido na janela principal em 2026-08-15, a mesma versao rodada contra
o historico com merges falhou identica ao defeito original:
`esperava '3 commit(s) atras', veio '5 commit(s) atras'`. Criterio que se
satisfaz renomeando nao e criterio — o de agora so passa se o comportamento
mudar.

### 3. O caminho paralelo do executar passa a flag [tipo: docs]
atende: D7
arquivos: `skills/executar/SKILL.md`
depende de: nenhuma
paralela: sim
pronto quando: `grep -n -- '--paralelo' skills/executar/SKILL.md` devolve pelo menos uma linha, e essa linha esta dentro do bloco de invocacao que hoje comeca em `skills/executar/SKILL.md:74`; o texto ao redor diz em uma frase que a flag vale **so** no despacho paralelo e o que ela afrouxa. `agents/executor.md` NAO aparece no diff.

### 4. Porte das mesmas mudancas para o gemeo em Python [tipo: implementar]
atende: D6
arquivos: `scripts/conferir-entrega.py`
depende de: 1
paralela: nao
pronto quando: `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh; echo EXIT=$?` devolve `EXIT=0`, E `python scripts/conferir-entrega.py --worktree . --paralelo 2>&1 | head -1` NAO contem `opcao desconhecida`. A logica sai da tarefa 1, nao de reimplementacao independente: mesmas mensagens, mesmos vereditos.

### 5. Casos novos que exercitam a rodada paralela [tipo: teste]
atende: D1, D2, D3, D4, D6
arquivos: `scripts/testa-conferir-entrega.sh`
depende de: 1, 4
paralela: nao
pronto quando: `bash scripts/testa-conferir-entrega.sh; echo EXIT=$?` devolve `EXIT=0` E `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh; echo EXIT=$?` devolve `EXIT=0`, com pelo menos estes quatro casos novos, cada um nomeando `paralelo`: (a) HEAD do principal avancou para frente + `--paralelo` -> exit 0 com aviso contendo `avancou`; (b) HEAD do principal moveu para tras (`checkout HEAD~1`) + `--paralelo` -> exit **1**, porque recuo nunca e avanco; (c) sujeira no principal em arquivo que o agente NAO tocou + `--paralelo` -> exit 0 com aviso contendo `nenhuma nos arquivos do agente`; (d) sujeira no principal em arquivo que o agente TOCOU (`feito.txt`) + `--paralelo` -> exit **1**. O caso (b) e o que separa D1 de "desligar a checagem 5".

### 6. O conjunto que decide o cruzamento vira evidencia impressa [tipo: implementar]
atende: D2, D4
arquivos: `scripts/conferir-entrega.cjs`, `scripts/conferir-entrega.py`
depende de: 1, 4
paralela: nao
pronto quando: rodando o `conferir-entrega` com `--paralelo` num cenario com sujeira no principal, a saida da checagem 4 contem a linha `$ git -C <worktree> diff --name-only <base>..<commit>` (ou o `show --name-only` equivalente quando nao ha `--base`) **antes** do veredito, com a lista de arquivos crua; e as duas baterias seguem em `29 ok, 0 falha(s)` (`bash scripts/testa-conferir-entrega.sh` e a mesma com `CONFERIR="python scripts/conferir-entrega.py"`), sem reescrita de caso.

**Emenda de 2026-08-15, vinda do `revisar`.** Achado 1 do revisor independente:
`arquivosAgente` (`conferir-entrega.cjs:190,192` e `conferir-entrega.py:110,112`)
usa `c.git`, que nao imprime, e com isso o **conjunto de arquivos que decide o
cruzamento** nunca aparece no relatorio. O cabecalho do proprio arquivo
(`conferir-entrega.cjs:51-52`) declara o contrario: "cada checagem imprime o
comando literal e a saida CRUA antes do veredito".

O achado foi **conferido e estreitado** na janela principal antes de virar
tarefa: `c.git` silencioso ja era o padrao da casa para consulta auxiliar,
inclusive na linha 253, onde a checagem 2 decide o veredito com um
`merge-base --is-ancestor` silencioso desde antes desta entrega. Logo a chamada
equivalente na checagem 5 segue precedente e **nao** entra nesta tarefa. O que
entra e so o `arquivosAgente`: diferente de um booleano de ancestralidade, um
**conjunto** o leitor nao consegue reconstruir a partir do que esta impresso.

## Cobertura

- D1 -> tarefas 1, 5
- D2 -> tarefas 1, 5, 6
- D3 -> tarefas 1, 5
- D4 -> tarefas 1, 5, 6
- D5 -> tarefa 2
- D6 -> tarefas 4, 5
- D7 -> tarefa 3
