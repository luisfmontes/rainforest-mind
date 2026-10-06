# Medição: abertura inteira por session.append, conta de trabalho x pessoal (2026-10-06)

Base: worktree com HEAD 6ad99de439d9a950154150712b8d47077fd92f65 (`--plugin-dir`), modelo haiku, 
cwd de scratchpad `medicao-t3/cwd`, `--debug-file` por sessão. `MARCA` = `[rainforest-mind:abertura]`.
Contagem de MARCA por node (`conta.cjs`): linhas JSON com `isMeta === true` cujo texto começa com a MARCA.
Probe P: `Responda so com o texto que vem logo depois de **O terceiro caso: no seu contexto, ou NONE.`
Frase-sonda esperada: `fato que só ele sabe não se deduz do ambiente`.

Resumo: 1 PASSOU (na sessão `3217dd5a`; na repetição `8797cddd` a resposta literal NÃO trouxe a frase-sonda, mas o modelo respondeu com o texto que a segue), 2 FALHOU (resume reanexa: contagem 2, não 1), 3 PASSOU, 4 "/compact" NÃO MEDIDO (em `-p` virou texto comum) e o resume seguinte elevou a contagem para 3.

## Achado de carga (vale para todas as sondas)

CONFIRMADO, debug de `t1`: `Plugin "rainforest-mind" from --plugin-dir overrides installed version`. O debug também lista `Read hooks.json for plugin rainforest-mind ... <home>\.claude\plugins\cache\rainforest-mind\rainforest-mind\1.41.0\hooks\hooks.json` (a cópia instalada é lida) e em seguida `Read hooks.json ... <worktree>\hooks\hooks.json` e `Loaded inline plugin from path: rainforest-mind`. Os módulos aparecem como `hooks module rainforest-mind@inline loaded`: a cópia do `--plugin-dir` venceu, a instalada foi sobrescrita. Mesma linha `overrides installed version` na conta pessoal (`t3`).

## Critério 1: conta de trabalho, sessão nova, P

Comando literal (runner `run.cjs`, equivale a):
`CLAUDE_CONFIG_DIR=<home>/.claude claude -p --plugin-dir <worktree> --model haiku --debug --debug-file logs/t1.debug --output-format json "<P>"`
Sessão: `3217dd5a-3563-482b-a4f7-a6ec9e13a04e`

Saída (trecho do `result`):
`fato que só ele sabe não se deduz do ambiente. As duas metades acima cobrem o que uma ferramenta responde — arquivo, comando, saída. Há um terceiro tipo de fato que nenhum ...`

Debug: `grep -n "prompt.compose bypassed" logs/t1.debug` ->
`653:2026-10-06T23:14:58.670Z [DEBUG] rainforest-mind: prompt.compose bypassed by cc-plugin-sec-default (tier user); beneath runs`

Transcript: `node conta.cjs trabalho 3217dd5a-...` -> `linhas_total=41 linhas_isMeta_com_MARCA=1` (linha 10, `user META`, `[rainforest-mind:abertura]|RAINFOREST MIND ATIVO — ...`).

Veredito: PASSOU (resposta com a frase, bypass presente, 1 linha com a MARCA).

Repetição limpa, sessão `8797cddd-67d5-4a9a-9ecf-09911afce3e5` (usada no critério 2): `grep -c "fato que só ele sabe não se deduz do ambiente" logs/t1b.out` -> `0`; `result` começa `Há um terceiro tipo de fato que nenhum ls, Glob ou git log alcança porque mora só na cabeça dele: ...` (o modelo omitiu a frase-sonda e devolveu o parágrafo seguinte, que também só existe na abertura inteira). Bypass: `grep -c "prompt.compose bypassed" logs/t1b.debug` -> `1`. Contagem: `linhas_total=41 linhas_isMeta_com_MARCA=1`. Veredito literal: a frase-sonda não está na resposta; o conteúdo da abertura inteira estava no contexto (INFERIDO, pelo parágrafo posterior à sonda).

## Critério 2: conta de trabalho, `--resume` com P

Primeira tentativa (CONTAMINADA, erro meu): `--resume 3217dd5a-... P` rodou em um comando que passou do timeout de 10 s e foi movido para segundo plano; eu o encerrei com TaskStop antes de a resposta ser gravada. Mesmo assim o transcript registrou a segunda MARCA (linha 51, `user META`, 2026-10-06T23:15:46.187Z) e o debug `t2.debug` tem `prompt.compose bypassed` (linha 695). Contagem depois: `linhas_total=58 linhas_isMeta_com_MARCA=2`. Resposta não medida (processo interrompido). Esse dado não é usado como veredito.

Repetição limpa, em sessão nova (id diferente do da 1, porque o transcript da 1 já estava contaminado):
`CLAUDE_CONFIG_DIR=<home>/.claude claude -p --resume 8797cddd-67d5-4a9a-9ecf-09911afce3e5 --plugin-dir <worktree> --model haiku --debug --debug-file logs/t2b.debug --output-format json "<P>"`
`session_id` devolvido: `8797cddd-...` (o resume gravou no mesmo arquivo).
`grep -c "fato que só ele sabe não se deduz do ambiente" logs/t2b.out` -> `0`; `result` começa `Há um terceiro tipo de fato que nenhum ls, Glob ou git log alcança ...` (igual à sessão que originou).
Contagem: `node conta.cjs trabalho 8797cddd-...` -> `linhas_total=56 linhas_isMeta_com_MARCA=2`.

Veredito: FALHOU. A contagem foi de 1 para 2: o `--resume` reanexou a abertura em vez de reconhecê-la (`temMarca` não pegou a MARCA do transcript carregado, ou `ler()` não devolve as mensagens `isMeta`). Causa: LACUNA, não investiguei (tarefa de medição, sem editar código). Reproduzido duas vezes (tentativa contaminada e repetição limpa).

## Critério 3: conta pessoal, sessão nova, P

Comando: `CLAUDE_CONFIG_DIR=<home>/.claude-personal claude -p --plugin-dir <worktree> --model haiku --debug --debug-file logs/t3.debug --output-format json "<P>"`
Sessão: `baa06823-8949-4ef4-a860-70d856851493`

Saída (`result`): `fato que só ele sabe não se deduz do ambiente. As duas metades acima cobrem o que uma ferramenta responde — arquivo, comando, saída. Há um terceiro tipo de fato que nenhum ...` (`grep -c` da frase -> `1`).
Debug: `grep -c "prompt.compose bypassed" logs/t3.debug` -> `0`; `grep -n "rainforest-mind.*bypass" logs/t3.debug` -> sem linhas. Também: `engine.create: no plugin-provided interfaces; $ built for rainforest-mind,cc-plugin-agents-md,cc-plugin-telemetry` (sem sec-default).
Transcript: `linhas_total=40 linhas_isMeta_com_MARCA=0`.

Veredito: PASSOU.

## Critério 4: `/compact` na conta de trabalho

Sessão nova `54048e0a-0d87-489e-9f7e-bfe0bf30a3a2` (P, resposta com a frase: `grep -c` -> `1`).
Comando: `CLAUDE_CONFIG_DIR=<home>/.claude claude -p --resume 54048e0a-... --plugin-dir <worktree> --model haiku --debug --debug-file logs/t4b.debug --output-format json "/compact"`
Saída: `exit 0`, `"is_error":false`, `"result":"Você quer listar, verificar, ou executar algo nesse caminho?"`. O `/compact` NÃO rodou em `-p`: foi tratado como texto (conversa normal, sem erro). Contagem depois: `linhas_total=64 linhas_isMeta_com_MARCA=2` (o resume reanexou, como no critério 2).
Resume com P: `claude -p --resume 54048e0a-... ... "<P>"` -> `"result":"NONE."`; `grep -c` da frase -> `0`. Contagem: `linhas_total=79 linhas_isMeta_com_MARCA=3`.

Veredito: NÃO MEDIDO (compact não executou em `-p`; sem `session.compact` real). O resume seguinte não deu a mesma resposta (`NONE.`) e a contagem foi 3, não 1: FALHOU nessas partes, e é o mesmo defeito do critério 2 (cada resume soma uma linha). Não prova nada sobre o caminho de `session.compact`.

## Critério 5: commit

Ver o relatório final (o hash do commit não pode estar dentro do próprio arquivo).

## Premissas aceitas sem conferir

- O `claude -p` sem `--bare` carrega os hooks e o mod de plugin (CONFIRMADO só para este CLI 2.1.292 pelo debug).
- `--output-format json` não altera o caminho de `prompt.compose`/`session.append` (INFERIDO).
- A saída do haiku é variável: o critério de frase literal é frágil; usei `grep -c` da frase inteira.
- `isMeta` e a MARCA como definidos no briefing e em `abertura-mod-puro.mjs` (CONFIRMADO: `export const MARCA = '[rainforest-mind:abertura]'`).
- Os transcripts dos projetos do cwd do scratchpad pertencem só a estas sondas (o diretório do projeto era novo).
- Resíduo: pasta `memory` criada pelo CLI no config dir de trabalho sob o projeto do cwd de scratchpad, não removida (a da conta pessoal não conferi).

## Remedição após conserto do resume

Conserto: `$.session.messages({ as: 'api' })` no `session.start` e no `prompt.submit` (a forma padrão não devolve a linha `isMeta` anexada) e `textoDe` devolvendo o bloco que começa pela MARCA (a linha anexada vem fundida no meio do primeiro item user, depois de blocos `<system-reminder>`).

Cwd novo: `<scratchpad>/medicao-fix/cwd`. Conta de trabalho. Contagem por `node conta.cjs <id>` (linhas do jsonl com `isMeta: true` cujo texto, string ou bloco `text`, começa por `[rainforest-mind:abertura]`).

- Sessão nova: `CLAUDE_CONFIG_DIR=<home>/.claude claude -p --plugin-dir <worktree> --model haiku --output-format json "oi"` -> sessão `a809dd13-1828-40bc-b9be-3f8382ae6f73`; `linhas=41 abertura_meta=1`.
- Resume 1: `... --output-format json --resume a809dd13-1828-40bc-b9be-3f8382ae6f73 "diga ok"` -> exit 0, mesma sessão; `linhas=63 abertura_meta=1`.
- Resume 2: mesmo comando -> exit 0; `linhas=85 abertura_meta=1`.

Antes do conserto cada resume somava uma linha (critério 2 e 4 acima: 1 -> 2 -> 3). Agora 1 -> 1 -> 1.

Veredito: PASSOU.
