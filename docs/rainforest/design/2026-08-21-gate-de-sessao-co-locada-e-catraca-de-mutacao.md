# Gate de sessão co-locada e catraca de mutação: as duas famílias mais reincidentes viram exit code

**Data:** 2026-08-21
**Origem:** `/semear` de 2026-08-21 sobre 60 observações, 47 ideias abertas e 3 relatórios. Propostas P1 e P2, as duas famílias com mais reincidência do acervo.

## Objetivo

Trocar prosa por exit code nas duas famílias que mais voltaram, e que voltaram **hoje**:

- **Família 1 — sessão paralela sem noção de dono (11 registros).** Issues #25 e #38. Hoje, `git checkout -b` no diretório compartilhado arrancou a outra sessão da branch dela; ela commitou 3 vezes na minha branch sem saber. O texto da regra 11 foi seguido corretamente — e a saída que ele prescreve (`branch nova, tirada da base`) é o ato que causa o dano.
- **Família 2 — bateria que não sabe falhar (8 registros).** Issue #21, relatório de 2026-08-19, `obs-2026-08-17-dez-baterias-que-nao-sabiam-falhar` (10 de 18 entregas). Hoje, um agente cumpriu todos os critérios falsificáveis do briefing, colou saída de mutação, entregou 49/49 verde — e a trava recusava o caminho feliz **sempre**.

O que separa as duas do resto do acervo é a Issue #4: ela também reincidiu hoje (worktree nasceu 2 commits atrás) e **custou zero**, porque tinha mecanismo. A conferência de base parou o agente antes de ele editar. As outras duas só tinham texto.

## Decisões fechadas

- **D1 — O gate dispara por `cwd` idêntico, não por repositório.** Outra sessão viva cujo `cwd` registrado é exatamente o mesmo. Foi o caso real das duas vezes (#25 e #38). Medir por `git-common-dir` pegaria também worktree do mesmo repo — e barraria quem trabalha na própria worktree, que é justamente o comportamento que o método quer premiar. Trava que atrapalha vira trava desligada.

- **D2 — Só os verbos que movem o HEAD do checkout: `checkout` e `switch`** (inclusive `-b`/`-c`). `commit`, `merge`, `rebase`, `reset` passam. Cobrir todo o `GIT_QUE_MEXE` barraria as duas sessões simetricamente, inclusive a dona legítima da branch.

- **D3 — "Viva" é janela de tempo de ~4h, trabalhando ou parada.** Não há alternativa: das 5 entradas de `sessoes.json`, **zero** tem `pid`, então o filtro `!s.pid || estaVivo(s.pid)` do `sessoesVivas` nunca dispara e a vivacidade já é, de fato, só tempo. Janela longa porque **dono de branch dura mais que atenção**: hoje o usuário pausou a outra janela e ela continuou dona: uma janela de 15 min teria liberado o `checkout` exatamente no momento errado.

- **D4 — A fonte é `sessoes.json` da raiz de DADOS, resolvida por `resolverRaiz`, nunca o do repositório.** O `sessoes.json` versionado na raiz do repo tem 1 entrada, de 2026-08-12, e não recebe escrita. O vivo é `~/.rainforest/sessoes.json`. É o mesmo tropeço já registrado em `hooks/heartbeat.cjs:13-17` ("o `sessoes.json` que ele lia simplesmente não recebia mais escrita"), e repeti-lo seria a terceira vez.

- **D5 — O gate se exclui pelo `session_id` do evento.** O hook recebe `session_id` (provado: `hooks/heartbeat.cjs:50` é quem escreve as chaves de `sessoes.json` com ele), e as duas entradas de hoje têm `cwd` idêntico — logo `cwd` sozinho não distingue. Sem `session_id` no evento, o gate **libera**, pelo mesmo princípio de fail-open que ele já aplica quando o git não responde.

- **D6 — A catraca de mutação é cobrada como campo obrigatório no `marcar --estagio executar --status ok`.** Mesma forma da trava de `base`/`head` do `revisar`, que já existe e funciona. Sem o campo, exit 2.

- **D7 — O alvo da mutação é declarado pela tarefa do plano**, não inferido. Campo `mutacao:` com arquivo, padrão a inverter e comando da bateria. Quem sabe o que inverter é quem escreveu o conserto. Mutação automática estilo mutmut não existe pronta para o mix shell+node deste repo e seria outro projeto.

- **D8 — O agente roda a catraca para iterar; a integração RE-roda, e só ela vale.** É o P1 do relatório de 2026-08-08, já colado no cabeçalho do `conferir-entrega.cjs`: *"enquanto o veredito de uma checagem for redigido pelo mesmo agente que ela deveria travar, ela não trava nada"*. Hoje provou de novo: o agente rodou mutação, relatou mutação, entregou quebrado.

- **D9 — Toda tarefa declara `mutacao`, e `n/a` com motivo é resposta aceita.** Tarefa de doc não tem comportamento a inverter; exigir o impossível cria o hábito do `--forcar` e mata a trava. Restringir a exigência a "tarefa que toca `testa-*`" esconde a tarefa que **devia** ter bateria e não tem, que é metade do problema.

- **D10 — Ausência de declaração em trabalho já em curso avisa, não trava.** Mesmo desenho do backstop de mutação entregue hoje: travar retroativo quebra esteira aberta.

- **D11 — `conferir-mutacao.cjs` recusa quando a mutação não casa com o fonte.** Precedente literal em `scripts/testa-conferir-relatorio.sh:126` (`MUTACAO NAO APLICADA` → exit 1) e elogiado no relatório de 2026-08-19: guarda que protege quem a escreveu. Sem ela, padrão que não casa vira "bateria vermelha" por motivo errado.

## Avaliado e descartado

- **Gate por `git-common-dir` (mesmo repositório).** Pegaria worktree, mas barraria o trabalho em worktree — o comportamento correto. Descartado em D1.
- **Gate sobre todo o `GIT_QUE_MEXE`.** Cobriria o `commit` da #25, mas barra a dona da branch junto. Descartado em D2.
- **Vivacidade por `prompt_ts > stop_ts` ("trabalhando").** Sessão morta no meio de um turno fica "trabalhando" para sempre; sessão pausada deixa de ser dona. Erra nas duas direções. Descartado em D3.
- **Catraca só como script citado no briefing.** É exatamente o arranjo que falhou hoje. Descartado em D6.
- **`verificar` mutando sozinho toda bateria nova do diff.** O mais forte, mas exige inferir o alvo — o problema difícil. Descartado em D7; volta se D7 provar ser burocracia.
- **Mutação automática (mutmut e similares).** Não há ferramenta para shell+node aqui. Projeto próprio, não tarefa.
- **`mutacao` obrigatório sem escape.** Cria o hábito do `--forcar`. Descartado em D9.

## Fora de escopo

- **P3 (teste que cola a saída crua medida) e P4 (abertura anuncia ultracode/workflows)** — plantadas com gancho em 2026-08-21, não entram nesta esteira.
- **Defeito do `semear.cjs` em worktree** — plantado em 2026-08-21 (`semear-deriva-projeto-do-cwd-e-quebra-em-worktree`).
- **Falso positivo da checagem 4 do `conferir-entrega.cjs`** (compara contra "limpo" em vez de contra instantâneo) — é a P4 do relatório de hoje, arrasta o gêmeo Python e a bateria dos dois. Fica para Issue própria.
- **Reescrever a regra 11 trocando "branch nova" por "worktree nova"** — é a P2 da Issue #38. Depende de D1/D2 existirem primeiro; texto sem o gate atrás é o que já falhou.
- **Registrar `pid` no `sessoes.json`.** Tornaria a vivacidade real em vez de temporal, e é a correção de fundo do D3 — mas muda o contrato de quem escreve o arquivo e vale sozinho.

## Em aberto

- **Nada bloqueia o `plano`.** A fronteira esvaziou em duas rodadas.
- **A base desta esteira** é decisão do `plano`, não do design: a branch `regua-e-backstop-de-mutacao` está publicada e sem PR, e este trabalho pode sair dela ou de uma base limpa. O `plano` decide quando souber a granularidade das tarefas.
