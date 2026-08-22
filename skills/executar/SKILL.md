---
name: executar
description: Executa um plano da esteira despachando agentes — a fatia paralela quando o plano marca tarefas independentes, serial quando não marca. Use depois que `plano` fechou `ok`, nunca para decidir arquitetura ou escrever o plano.
---

# Executar

Lê `docs/rainforest/planos/<slug>.md` e faz o que ele manda acontecer. **Esta
skill despacha, não implementa** — se você se pegar editando arquivo do
projeto na mão, pare: a task era pra um agente.

## Abertura

```
node scripts/estado.cjs exigir --slug <slug> --estagio executar
```

Exit ≠ 0 (recusa por `design` ou `plano` em aberto) encerra aqui — não se
improvisa plano na cabeça pra contornar. Passou: leia o plano inteiro antes
de despachar a primeira task.

## O paralelismo é o ponto

O plano marca quais tarefas são independentes entre si; essas vão **em
paralelo**, o resto serial. Antes de despachar, leia as regras **10, 11 e
12** de `skills/rainforest-mind/SKILL.md` (carregue `Skill(rainforest-mind)`
se precisar do detalhe) e os sete agentes em `agents/` — `executor`,
`revisor`, `tester`, `planejador`, `depurador`, `resolvedor-de-build`,
`documentador`. A escolha do agente é por **função**, nunca por domínio.

**Despacho paralelo é uma resposta com várias chamadas de `Agent`.** Uma
chamada de `Agent` por resposta, esperando a volta antes da próxima, é
serial — mesmo que as tasks fossem independentes no plano. Tarefa com
ordem entre si (a segunda lê o resultado da primeira) vai serial de
propósito; tarefa sem ordem que sai uma chamada por resposta é
paralelismo desperdiçado, não cautela.

## Todo agente que edita roda isolado

`isolation: "worktree"` em toda chamada de `Agent` que vai tocar arquivo —
é isto que permite o paralelo: sem isolamento, dois agentes na mesma árvore
conflitam entre si, e foi por isso que o superpowers proibiu paralelo de
implementadores. Aqui não precisa proibir porque a trava existe.

O briefing de cada agente leva, sempre:
- **O hash da base** (regra 11) e a instrução de conferir na primeira ação
  (`git log -1`), abortando se divergir — só hash velho conhecido autoriza
  `git merge --ff-only`.
- **O hash velho conhecido, já nomeado, desde o primeiro despacho.** O HEAD
  do `main` (ou o commit imediatamente anterior ao início do trabalho) é
  candidato natural: é ali que o worktree nasce quando nasce errado. A Issue #4
  mediu **2 de 8 despachos confirmados por abort explícito, possivelmente 5 de
  8**, sempre no mesmo hash — a regra 11 chama isso de "intermitente" e a
  medição diz que é frequente. Deixar a autorização para a segunda tentativa
  custou 3 despachos completos numa única tarefa, mais um worktree órfão para
  remover à mão.
- **Os caminhos que a tarefa promete criar**, para o `--espera` da integração
  abaixo — sem eles, arquivo que o agente cria e nunca chega ao commit passa
  por todas as outras checagens.
- **Git destrutivo proibido** e commit só na branch de trabalho, nunca `main`.
- **Critério de sucesso falsificável**, copiado literal da tarefa do plano:
  comando exato e saída exata que provam pronto — nunca adjetivo
  ("robusto", "de verdade", "não decorativo").

Agente que edita **nunca é nomeado** (regra 10): nome sem worktree é a
ilusão de isolamento, e nomear sem necessidade de diálogo contínuo deixa
teammate ocioso pendurado.

## Integração confere na fonte

Entrega de agente não se aceita pelo relato (regra 12). Ao receber:

```
node scripts/conferir-entrega.cjs --worktree <wt> --base <hash> --head-antes <hash-antes-do-despacho> \
    [--paralelo] --espera <caminho-que-a-tarefa-prometia> [--espera <outro>]
```

Passe `--paralelo` em despachos paralelos; a flag afrouxa a checagem 4 para
só reprovar sujeira que cruza com os arquivos do commit, deixando o resto como
aviso.

`--espera` confere na **árvore do commit**, não no disco: `ls -la` e `cat` do
agente provam que o arquivo existe, nunca que ele foi commitado, e
`git status --porcelain` (checagem 3) por desenho não lista arquivo ignorado.
Foi assim que um `.gitignore` com `*` se autoexcluiu e sumiu da entrega com as
cinco checagens verdes (Issue #4).

Exit ≠ 0 é achado, não detalhe — trate como base errada até provar o
contrário. **Nenhum identificador do relato entra num comando**: hash,
caminho, número — re-derive de `git` antes de usar. Passou a checagem
mecânica, rode o critério de sucesso do briefing e olhe a saída real; suíte
verde relatada não é evidência.

## A catraca de mutação: quem roda não é quem julga

O agente roda a catraca **para iterar** — é assim que ele descobre, ainda
dentro do worktree, que a bateria dele não sabe falhar. Mas **o relato dele
não fecha a tarefa**. A integração **re-roda** `conferir-mutacao.cjs` na volta,
e **o exit code dela é o veredito**. Bateria relatada vermelha e não re-rodada
é bateria não medida.

Isto é o P1 do relatório de método de 2026-08-08, já colado no cabeçalho de
`conferir-entrega.cjs`:

> "Enquanto o veredito de uma checagem for redigido pelo mesmo agente que ela
> deveria travar, ela não trava nada."

Em **2026-08-21** isso se repetiu, e é por causa desse dia que esta seção
existe: o agente rodou mutação, relatou mutação, colou saída de mutação, e
entregou quebrado — 49 de 49 verde, com a trava que ele dizia ter invertido
recusando o caminho feliz **sempre**. A bateria não sabia falhar; o relato
não tinha como revelar isso, porque quem o escreveu foi quem seria barrado.

Para cada tarefa que o plano marcou com `mutacao:`, a integração roda:

```
node scripts/conferir-mutacao.cjs --raiz <worktree> --arquivo <fonte> \
    --de '<trecho literal a inverter>' --para '<o que entra no lugar>' \
    --bateria '<comando da bateria>' [--timeout <ms>]
```

`--arquivo`, `--de`, `--para` e `--bateria` são **obrigatórios**; `--raiz`
(diretório de trabalho da bateria, padrão o cwd) e `--timeout` (teto em ms,
padrão 300000) são opcionais. Rodar sem argumento nenhum imprime o uso e sai 1.

Os quatro valores saem do bloco `mutacao:` **da tarefa do plano**, nunca do
relato do agente — é a mesma regra de re-derivar identificador, e aqui ela
pesa mais: o relato é justamente a peça que a catraca desconfia.

| exit | significa | o que fazer |
|---|---|---|
| `0` | mutação casou e bateria **VERMELHA** | única aprovação: a bateria sabe falhar |
| `2` | mutação casou e bateria **VERDE** | reprovado — a bateria não mede o conserto |
| `3` | `MUTACAO NAO APLICADA` — o `--de` não existe no fonte | a declaração está errada; nada foi medido |
| `1` | erro de uso, ou bateria sem veredito (estouro de tempo / sinal) | não é aprovação nem reprovação |

`2` e `3` são códigos **diferentes de propósito**: "a bateria é fraca" e "a
declaração de mutação está errada" pedem conserto em lugares distintos, e o
`3` nunca pode ser lido como reprovação da bateria — em 2026-08-19 um `sed`
com alvo errado deixou a bateria vermelha por outro motivo e o resultado quase
virou prova. Veredito certo pelo motivo errado é pior que veredito errado,
porque ninguém volta a olhar.

No Git Bash, argumento que **começa** com `//` chega ao script com uma barra
só (`'// coment'` vira `'/ coment'`) e não casa, dando `3` sem culpa do fonte.
Ponha um caractere antes das barras, ou exporte `MSYS_NO_PATHCONV=1`.

## Fechamento

Enquanto faltar tarefa:

```
node scripts/estado.cjs marcar --slug <slug> --estagio executar --status parcial --json '{"tarefas_ok":N,"tarefas":M}'
```

Todas fechadas, e só então:

```
node scripts/estado.cjs marcar --slug <slug> --estagio executar --status ok --json '{"tarefas_ok":M,"tarefas":M,"mutacao":[{"tarefa":1,"resultado":"vermelho"},{"tarefa":4,"resultado":"n/a","motivo":"tarefa so reescreve doc"}]}'
```

O campo `mutacao` é **obrigatório no `ok`** (e só nele: `parcial` e
`reprovado` não o cobram) — um item por tarefa do plano. `resultado` aceita
`vermelho` ou `n/a`, e `n/a` exige `motivo` não vazio. **`verde` não é
resposta aceita**: bateria que continua verde com o conserto invertido é
exatamente o defeito que a catraca mede. O que se declara aqui é o resultado
que a **integração** obteve ao re-rodar `conferir-mutacao.cjs` — o campo
existe para que haja alvo declarado a re-rodar e para que "esqueci" pare de
sair 0, não para transformar o relato do agente em veredito.

**Validação da cobertura**: o campo `mutacao` deve cobrir **todas as tarefas**
do plano (`docs/rainforest/planos/<slug>.md`) — nenhuma ausente, nenhuma
duplicada, nenhuma inexistente. Se o plano não existir, a validação avisa e
passa (fail-open); se os dados divergirem, a marcação recusa com exit 2.
Tarefas do plano são os itens numerados no formato `### <n>. ` do markdown
(ex.: `### 1. Implementar feature`, `### 2. Testes`).

`parcial` é o estado honesto e **não libera `revisar`** — `exigir` do
próximo estágio recusa com exit 2 enquanto `executar` não estiver `ok`.
É assim que "5 de 7" para de virar "pronto" sem ninguém decidir isso.

**Condição de parada**: tarefa cujo critério de sucesso não dá pra
verificar — comando que não existe, saída ambígua, agente que não
completou — não é marcada `ok` por otimismo. Vira pendência nomeada no
`--json` (ex.: `"pendentes":["tarefa-3: worktree nao respondeu"]`) e o
estágio fecha `parcial`, não `ok`.
