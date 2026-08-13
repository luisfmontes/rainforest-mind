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
    --espera <caminho-que-a-tarefa-prometia> [--espera <outro>]
```

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

## Fechamento

Enquanto faltar tarefa:

```
node scripts/estado.cjs marcar --slug <slug> --estagio executar --status parcial --json '{"tarefas_ok":N,"tarefas":M}'
```

Todas fechadas, e só então:

```
node scripts/estado.cjs marcar --slug <slug> --estagio executar --status ok --json '{"tarefas_ok":M,"tarefas":M}'
```

`parcial` é o estado honesto e **não libera `revisar`** — `exigir` do
próximo estágio recusa com exit 2 enquanto `executar` não estiver `ok`.
É assim que "5 de 7" para de virar "pronto" sem ninguém decidir isso.

**Condição de parada**: tarefa cujo critério de sucesso não dá pra
verificar — comando que não existe, saída ambígua, agente que não
completou — não é marcada `ok` por otimismo. Vira pendência nomeada no
`--json` (ex.: `"pendentes":["tarefa-3: worktree nao respondeu"]`) e o
estágio fecha `parcial`, não `ok`.
