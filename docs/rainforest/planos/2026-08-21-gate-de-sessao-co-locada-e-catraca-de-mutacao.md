# Plano: Gate de sessão co-locada e catraca de mutação

Design: docs/rainforest/design/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.md

As tarefas abaixo já trazem o campo `mutacao:` que a tarefa 5 vai passar a exigir. É dogfooding deliberado: este plano é o primeiro fixture real da trava, e se o formato não servir para ele, não serve.

## O que não pode quebrar

- **A janela principal sem sessão co-locada não pode ser barrada em nada.** O gate hoje libera todo mundo sem `agent_id`; depois desta mudança ele continua liberando, exceto no caso novo. Falso positivo aqui trava o trabalho de quem está sozinho no repo.
- **O gate falha para o lado de LIBERAR.** `sessoes.json` ausente, ilegível, sem `session_id` no evento, ou raiz de dados não resolvida → passa. É o princípio que ele já aplica quando o git não responde.
- **`RAINFOREST_GATE_OFF`, `.rainforest-gate-off` e o toggle de `hooks/lib/config.cjs` continuam desligando tudo**, inclusive a condição nova. Nenhuma saída de emergência existente pode deixar de funcionar.
- **`marcar --status parcial` e `--status reprovado` não ganham exigência nenhuma.** Só o fechamento `ok` cobra.
- **Trabalho de esteira já aberto não pode travar retroativamente** (D10).
- **As baterias que já existem continuam verdes**: `testa-gate-worktree.sh`, `testa-contexto-sessao.sh`, `testa-estado.sh`, `testa-conferir-esteira.sh`.

## Tarefas

### 1. Helper `sessaoColocada` em `contexto-sessao.cjs` [tipo: implementar]
atende: D1, D3, D4
arquivos: `hooks/lib/contexto-sessao.cjs`, `hooks/testa-contexto-sessao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: a comparação de `cwd` normalizado que decide co-locação
  para: `false` constante (nunca acha co-locada)
  bateria: `bash hooks/testa-contexto-sessao.sh`
pronto quando: com o `sessoes.json` REAL da raiz de dados (`~/.rainforest/sessoes.json`, que hoje tem 2 entradas com `cwd` = `C:\Projetos\rainforest-mind` e 3 com outros caminhos, e **nenhuma** com `pid`), chamar o helper passando o `session_id` de uma dessas duas devolve **exatamente a outra**; passando um `session_id` inexistente devolve **as duas**; passando o `cwd` de `C:/Projetos/sabia` devolve **vazio**. A janela é de 4h medida sobre `max(prompt_ts, stop_ts)`, e entrada com `stop_ts > prompt_ts` (parada) **conta**. Provado por `node -e` que faz `require('./hooks/lib/contexto-sessao.cjs')` e imprime os três resultados, com a saída colada.

### 2. Ligar a condição no `gate-worktree.cjs` [tipo: implementar]
atende: D2, D5
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: o `process.exit(2)` do ramo de sessão co-locada
  para: `process.exit(0)`
  bateria: `bash hooks/testa-gate-worktree.sh`
pronto quando: alimentando o hook pelo **stdin, no formato real que o harness envia** — `{"session_id":"<uuid>","cwd":"C:\\Projetos\\rainforest-mind","tool_name":"Bash","tool_input":{"command":"git checkout -b x"}}`, **sem** campo `agent_id`, porque a janela principal não tem — o processo sai **2** e a mensagem cita `git worktree add`. Com o mesmo payload e `"command":"git commit -m x"`, sai **0**. Com `cwd` de diretório que tem só uma entrada em `sessoes.json`, sai **0**. Com `RAINFOREST_GATE_OFF=1`, sai **0** mesmo no caso que barraria. Com `agent_id` presente, o comportamento antigo é idêntico ao de antes. Provado rodando `node hooks/gate-worktree.cjs < payload.json; echo $?` para cada caso, com os exit codes colados.

### 3. `scripts/conferir-mutacao.cjs` [tipo: implementar]
atende: D11
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: a guarda que exige que o padrão tenha casado no fonte
  para: seguir mesmo sem casar
  bateria: `bash scripts/testa-conferir-mutacao.sh`
pronto quando: com os **commits reais desta branch** como entrada — `53fa44d` (backstop consertado) e `0272cdf` (a mesma trava antes do conserto) — o script se comporta assim: **(a)** contra a árvore de `53fa44d`, mutando `!sujos_antes.has(c) && !propria.has(c)` para `!sujos_antes.has(c)` em `scripts/estado.cjs` e rodando `bash scripts/testa-estado.sh`, a bateria fica **vermelha** e o script sai **0**; **(b)** contra a árvore de `0272cdf`, o mesmo padrão **não existe no fonte** e o script sai **≠ 0** com a mensagem `MUTACAO NAO APLICADA` — nunca "bateria vermelha", que seria o veredito certo pelo motivo errado; **(c)** mutando um comentário (mudança que não altera comportamento), a bateria fica **verde** e o script sai **≠ 0**. Em todos os casos o fonte é restaurado ao final, provado por `git status --porcelain` vazio. Saída crua dos três casos colada.

### 4. Campo `mutacao` obrigatório no fechamento de `executar` [tipo: implementar]
atende: D6, D9, D10
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: a recusa por ausência do campo `mutacao`
  para: `null` (não recusa nunca)
  bateria: `bash scripts/testa-estado.sh`
pronto quando: com um slug que passou por `exigir --estagio executar`, `node scripts/estado.cjs marcar --estagio executar --status ok --json '{"tarefas_ok":2,"tarefas":2}'` sai **2** e a mensagem nomeia `mutacao`; com `"mutacao":[{"tarefa":1,"resultado":"vermelho"}]` sai **0**; com `"mutacao":[{"tarefa":4,"resultado":"n/a","motivo":"tarefa so reescreve doc"}]` sai **0**; com `"mutacao":[{"tarefa":4,"resultado":"n/a"}]` (sem motivo) sai **2**; `--status parcial` e `--status reprovado` saem **0** sem o campo. Slug cujo `executar` foi aberto antes desta mudança **avisa e sai 0** (D10). Exit codes colados.

### 5. Formato `mutacao:` na tarefa do plano, com trava de cobertura [tipo: implementar]
atende: D7, D9
arquivos: `skills/plano/SKILL.md`, `scripts/conferir-esteira.cjs`, `scripts/testa-conferir-esteira.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-esteira.cjs`
  de: a checagem de presença do bloco `mutacao:` por tarefa
  para: `continue` (aceita tarefa sem o bloco)
  bateria: `bash scripts/testa-conferir-esteira.sh`
pronto quando: com **este próprio arquivo de plano** como entrada (`docs/rainforest/planos/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.md`, que já traz `mutacao:` nas 6 tarefas), `node scripts/conferir-esteira.cjs cobertura --slug 2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao` sai **0**; com uma cópia do mesmo arquivo com o bloco `mutacao:` removido de uma tarefa, sai **2** nomeando o número da tarefa; com `mutacao: n/a` mais `motivo:`, sai **0**; com `mutacao: n/a` sem `motivo:`, sai **2**. Saída colada.

### 6. `executar` documenta que o veredito da catraca é da integração [tipo: docs]
atende: D8
arquivos: `skills/executar/SKILL.md`
depende de: 3, 4
paralela: nao
mutacao:
  arquivo: `skills/executar/SKILL.md`
  de: n/a
  para: n/a
  motivo: doc não tem comportamento a inverter; a falsificação é o casamento com a interface real do script, verificado abaixo
pronto quando: a seção nova de `skills/executar/SKILL.md` cita `conferir-mutacao.cjs` com **as mesmas flags que o script realmente aceita** — provado rodando `node scripts/conferir-mutacao.cjs` sem argumentos, colando o texto de uso, e conferindo que toda flag citada na skill aparece nele; e diz explicitamente que o relato de mutação do agente **não fecha a tarefa**, sendo o exit code da integração o veredito. Nenhuma flag citada na doc pode faltar no script, e nenhuma flag obrigatória do script pode faltar na doc.
