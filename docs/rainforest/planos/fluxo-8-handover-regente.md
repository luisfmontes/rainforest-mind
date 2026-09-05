# Plano: Fluxo 8 — `handover.cjs` (entrega completa; `regente.cjs` não construído)

Design: `docs/rainforest/design/fluxo-8-handover-regente-canonico.md` (D1–D7) — narrativa completa em `docs/rainforest/design/fluxo-8-design-handover-regente.md`.

Planejado em 2026-09-05, seis dias depois do design consolidado de 2026-08-30, que nunca chegou ao estágio `plano`. O levantamento que precede as tarefas foi feito contra `ff11a9f` (ponta de `origin/main` no dia).

## Achados que mudam o plano (leia antes das tarefas)

1. **`hooks/lib/estagio-ativo.cjs`, `scripts/portoes.cjs` e `scripts/recibo.cjs` já existem e são reusados sem alteração — CONFIRMADO.** Nenhuma tarefa deste plano reimplementa resolução de branch ou contrato de exit code de portão. Os dois scripts documentam o contrato `0`/`1`/`2` no próprio cabeçalho (`scripts/portoes.cjs:24-30`, `scripts/recibo.cjs:20-25`).

2. **`scripts/poda.cjs` tagueia `estagio: null` em toda branch `fluxo/<slug>` — CONFIRMADO, reproduzido ao vivo na branch deste próprio fluxo:**

   ```
   $ node hooks/lib/poda-estagio.cjs --cwd "$(pwd)"
   null
   $ node -e "console.log(JSON.stringify(require('./hooks/lib/estagio-ativo.cjs').resolver({cwd: process.cwd()})))"
   {"slug":"fluxo-8-handover-regente","estagio":"design"}
   ```

   A causa é uma cópia divergente: `hooks/lib/poda-estagio.cjs:107` só remove o prefixo de data do slug, enquanto o canônico `hooks/lib/estagio-ativo.cjs:69` remove também o prefixo `fluxo/` da branch e `:116` o número do fluxo. A bateria de `poda-estagio` só exercita branch sem prefixo, então o defeito fica verde. Dependência externa do fluxo 5 — nenhuma tarefa deste plano toca esse arquivo; o efeito é que a calibração da Q2 (limiar de contexto por estágio) fica bloqueada até o conserto.

3. **`git worktree` por fluxo já é convenção universal e a detecção de agente em voo já existe — CONFIRMADO.** Regra 11 do plugin cobre isolamento, base conferida e limpeza; `scripts/limpar-worktrees.cjs` classifica e remove; `scripts/estado.cjs:146` trata `em_voo` como campo efêmero de primeira classe, com `hooks/gate-agente-em-voo.cjs` impedindo o turno terminar em silêncio com agente em voo. Essas eram duas das três razões que justificavam o `regente.cjs`; as duas já estão resolvidas por convenção. A terceira depende de Q1, que é decisão do dono — por isso este plano não constrói o regente (ver Tarefa 6).

4. **`hooks/lib/cli-externo.cjs` (`rodarCli`) tem vazamento de processo confirmado e sem correção — CONFIRMADO.** No Windows roda `spawnSync('cmd.exe', ['/d','/s','/c', <cmd>], { timeout, windowsVerbatimArguments: true })`; o `timeout` alcança o `cmd.exe`, não os netos. Issue #187 (aberta, outro dono) documenta sete processos vivos 95,8 h depois de uma execução real, um com 531,6 s de CPU. É exatamente o primitivo que um spawn headless reusaria — mais um motivo para o corte da Tarefa 6. Nenhuma tarefa deste plano toca esse arquivo.

5. **A detecção de travamento que existe não serve para sessão headless — CONFIRMADO.** `hooks/gate-agente-em-voo.cjs` roda no Stop hook de uma sessão viva; um processo `claude -p` externo não tem turno nem Stop hook. É precedente de que o problema já foi resolvido uma vez, não peça reusável.

## O que não pode quebrar

- **`handover.cjs` nunca decide o que ler nem o que entregar** — toda fonte de dado é mecânica e nomeada em D3; a única parte de julgamento (seção do modelo) é texto que a sessão escreve, nunca gerado por spawn.
- **Nenhuma tarefa reimplementa `estagio-ativo.cjs`** — toda resolução de branch→estágio importa o módulo existente. Reimplementar é o defeito do achado 2, repetido.
- **`.rainforest/` nunca é ignorado por inteiro** — só path-a-path, preservando o `.rainforest/agentes.json` versionado, que é o manifesto da portaria.
- **Nenhuma tarefa conserta `hooks/lib/poda-estagio.cjs` nem `hooks/lib/cli-externo.cjs`** — pertencem a outras frentes (fluxo 5; Issue #187).
- **Nenhuma tarefa constrói `regente.cjs`, nem em versão mínima** — D1 e "Avaliado e descartado" no design; construir agora decidiria a Q1 por omissão.
- **Node puro `.cjs`, zero dependência, Windows-first.**

## Tarefas

### 1. `handover.cjs` — montagem mecânica do handover por slug [tipo: implementar]
atende: D2, D3
arquivos: `scripts/handover.cjs`, `scripts/testa-handover-montar.sh`
depende de: nenhuma
paralela: sim

Escopo: `node scripts/handover.cjs montar <slug>` lê, nesta ordem, `estagio-ativo.cjs` (estágio atual), `docs/rainforest/estado/<slug>.json` (decisões e evidências dos estágios fechados), `node scripts/portoes.cjs status <arquivo>` quando o bloco do estágio citar um arquivo de portões, `node scripts/recibo.cjs mostrar <slug>` quando existir recibo gravado, e `git status --porcelain` / `git diff --stat` no worktree do slug — e grava `.rainforest/handover/<slug>/atual.md`, substituindo o conteúdo anterior (documento vivo, nunca log). Exporta `montar(slug)` por `module.exports`, para reuso pela Tarefa 3. Sem seção do modelo ainda (Tarefa 3): a primeira gravação inclui um cabeçalho de seção vazio.

mutacao:
  arquivo: `scripts/handover.cjs`
  de: a escrita usa `.tmp` + `fs.renameSync`, substituindo o arquivo inteiro
  para: `fs.appendFileSync`, que faria o arquivo virar log
  bateria: `bash scripts/testa-handover-montar.sh`
  fixture: caso "duas montagens seguidas produzem arquivo do mesmo tamanho" — a bateria monta duas vezes sem mudança de estado e compara bytes; com a mutação, o arquivo dobra

pronto quando: com o estado real desta branch (`docs/rainforest/estado/fluxo-8-handover-regente.json`), `node scripts/handover.cjs montar fluxo-8-handover-regente` produz `.rainforest/handover/fluxo-8-handover-regente/atual.md` com o estágio que o `estagio-ativo.cjs` devolve ao vivo — provado por `node scripts/handover.cjs montar fluxo-8-handover-regente && grep -q "estagio: $(node -e "process.stdout.write(require('./hooks/lib/estagio-ativo.cjs').resolver({cwd:process.cwd()}).estagio)")" .rainforest/handover/fluxo-8-handover-regente/atual.md` devolvendo exit 0, e por rodar o comando duas vezes seguidas com `wc -c` do arquivo devolvendo o mesmo número nas duas.

### 2. `handover.cjs status <slug>` — frescor por coerência de estágio [tipo: implementar]
atende: D5
arquivos: `scripts/handover.cjs`, `scripts/testa-handover-status.sh`
depende de: 1
paralela: nao

Escopo: `node scripts/handover.cjs status <slug>` lê o `atual.md` gravado, extrai o estágio registrado nele e compara com o que `estagio-ativo.cjs` devolve ao vivo. Bate → exit 0, imprime o estágio. Handover ausente, ou estágio registrado divergente do real → exit 1, imprimindo qual dos dois casos é e os dois estágios. O TTL em horas (Q3) fica fora: este comando mede coerência, não idade.

mutacao:
  arquivo: `scripts/handover.cjs`
  de: `status` compara estágio registrado com estágio real e sai 1 na divergência
  para: `status` sempre sai 0, ignorando a divergência
  bateria: `bash scripts/testa-handover-status.sh`
  fixture: caso "handover montado em design, estado avança para plano sem remontar" — a bateria fecha o estágio seguinte sem chamar `montar` de novo e confere que `status` acusa a divergência

pronto quando: com o handover montado num estágio e o estado real avançado para o seguinte por `estado.cjs marcar`, sem remontar, `node scripts/handover.cjs status <slug-fixture>` sai 1 e nomeia os dois estágios na saída — provado pelo comando devolvendo exit 1 e pela saída contendo o estágio registrado e o estágio real, ambos por nome.

### 3. Gatilho único: `estado.cjs marcar` chama a montagem em todo gate aprovado [tipo: implementar]
atende: D4
arquivos: `scripts/estado.cjs`, `scripts/handover.cjs`, `scripts/testa-handover-secao-modelo.sh`
depende de: 1
paralela: nao

Escopo: `scripts/estado.cjs`, no ponto em que grava `status: "ok"` de qualquer estágio, passa a chamar `require('./handover.cjs').montar(slug)` — chamada de função, não spawn, ponto único. Depois de remontar, se a seção do modelo do `atual.md` estiver ausente ou mais velha que o snapshot mecânico recém-gravado, o `marcar` imprime em stderr um aviso **não-bloqueante** pedindo a seção; o exit code do `marcar` continua o de hoje e nunca falha por causa disso.

mutacao:
  arquivo: `scripts/estado.cjs`
  de: o `marcar` bem-sucedido chama `montar(slug)` do handover
  para: o `marcar` bem-sucedido não toca o handover
  bateria: `bash scripts/testa-handover-secao-modelo.sh`
  fixture: caso "marcar plano ok remonta o handover sozinho" — a bateria roda `estado.cjs marcar --estagio plano --status ok` num fixture e confere que o `atual.md` foi atualizado sem chamada explícita a `handover.cjs`

pronto quando: com um fluxo fixture cujo `plano` acaba de ser marcado `ok`, o `atual.md` daquele slug passa a registrar o estágio seguinte sem nenhuma chamada adicional a `handover.cjs` — provado por rodar `node scripts/estado.cjs marcar --slug <slug-fixture> --estagio plano --status ok --json '{...}'` e, em seguida, `grep -q 'estagio: executar' .rainforest/handover/<slug-fixture>/atual.md` devolvendo exit 0.

### 4. Fronteira com o git: `.gitignore` ganha `.rainforest/handover/`, e o README documenta o comando real [tipo: configurar]
atende: D6
arquivos: `.gitignore`, `README.md`, `scripts/testa-gitignore-handover.sh`
depende de: 1
paralela: nao

Escopo: acrescenta `.rainforest/handover/` ao `.gitignore`, na mesma seção comentada que já explica `.rainforest/portaria/despachos.jsonl` e `.rainforest/colheita/`, com o comentário dizendo por que é rastro de execução e não estado versionado. O `README.md` ganha a linha de `scripts/handover.cjs` na tabela de scripts, **com o comando de uso exato**, no formato das linhas de `recibo.cjs` e `portoes.cjs`.

mutacao:
  arquivo: `.gitignore`
  de: a linha `.rainforest/handover/` presente
  para: linha removida
  bateria: `bash scripts/testa-gitignore-handover.sh`
  fixture: caso único — `git check-ignore -q .rainforest/handover/qualquer/atual.md` sai 0 com a linha e não-zero sem ela

pronto quando: com um arquivo real criado em `.rainforest/handover/fluxo-8-handover-regente/atual.md` pela Tarefa 1, o git não o enxerga como novidade — provado por `git status --porcelain -- .rainforest/handover/` devolvendo saída vazia e por `git check-ignore -q .rainforest/handover/fluxo-8-handover-regente/atual.md` devolvendo exit 0; **e** o comando de uso que a linha do `README.md` associa a `handover.cjs`, extraído da própria linha e executado literalmente como ela o escreve contra o slug `fluxo-8-handover-regente`, produz o arquivo que a linha promete — provado por rodar o comando copiado da tabela e conferir que `.rainforest/handover/fluxo-8-handover-regente/atual.md` passa a existir com `mtime` posterior à execução. Falha se o comando documentado, rodado como está escrito, não produzir esse efeito — o critério mede o que o README promete, não a presença do nome do script nele.

### 5. Hook de `SessionStart` interativo: lista handovers coerentes [tipo: implementar]
atende: D7
arquivos: `hooks/handover-session-start.cjs`, `hooks/hooks.json`, `hooks/testa-handover-session-start.sh`
depende de: 1, 2
paralela: nao

Escopo: novo hook de `SessionStart`, registrado em `hooks/hooks.json` ao lado dos irmãos já existentes. Varre `.rainforest/handover/*/atual.md`, chama `handover.cjs status <slug>` para cada um e imprime, na lista de tarefas assumíveis, só os que retornam exit 0; os divergentes saem em bloco separado, como aviso, nunca como assumíveis.

mutacao:
  arquivo: `hooks/handover-session-start.cjs`
  de: lista como assumível só o slug cujo `handover.cjs status` sai 0
  para: lista todos os slugs com `atual.md`, independente do status
  bateria: `bash hooks/testa-handover-session-start.sh`
  fixture: caso "handover divergente não aparece na lista de assumíveis" — dois fixtures, um coerente e um com estágio divergente forçado

pronto quando: alimentado pelo payload que o harness realmente envia num `SessionStart` (JSON no stdin, sem argumento extra), com dois handovers fixture — um coerente e um divergente —, o hook imprime o coerente na lista de assumíveis e não imprime o divergente nela — provado por `echo '{"source":"startup"}' | node hooks/handover-session-start.cjs` devolvendo saída em que o slug coerente aparece na seção de assumíveis e o divergente aparece apenas na seção de aviso.

### 6. Registro do corte de escopo: por que `regente.cjs` não foi construído [tipo: docs]
atende: D1
arquivos: `docs/rainforest/design/fluxo-8-handover-regente-canonico.md`, `docs/rainforest/design/fluxo-8-design-handover-regente.md`
depende de: 1, 5
paralela: nao

Escopo: o design canônico e um rodapé de status no design narrativo registram (a) o que a entrega cobre — handover completo; (b) por que `regente.cjs` não foi construído: as duas razões estruturais já resolvidas por convenção (worktree pela regra 11, agente em voo por `em_voo`), e a que sobrou dependente da Q1, que é do dono; (c) as duas dependências externas que bloqueariam qualquer tentativa futura — `hooks/lib/poda-estagio.cjs` (fluxo 5) e `hooks/lib/cli-externo.cjs` / Issue #187 (outro dono). Não introduz comportamento novo: documenta o das Tarefas 1 a 5 e o não-comportamento do que foi cortado.

mutacao: n/a
  motivo: tarefa de documentação de decisão de escopo. D1 diz o que **não** se constrói e por quê — não há comportamento a inverter, e inverter texto não produz bateria vermelha. A falsificação dela é a coerência do texto com o estado real do repositório, medida no `pronto quando` abaixo.

pronto quando: cada razão que o documento dá para o corte continua verdadeira contra o repositório real, e o documento passa no checador — provado por `node scripts/conferir-fluxo.cjs design --slug fluxo-8-handover-regente --design docs/rainforest/design/fluxo-8-handover-regente-canonico.md` devolvendo exit 0; por `node hooks/lib/poda-estagio.cjs --cwd "$PWD"` devolver `null` na branch `fluxo/<slug>` enquanto `node -e "console.log(require('./hooks/lib/estagio-ativo.cjs').resolver({cwd:process.cwd()}).estagio)"` devolve o estágio real, que é a divergência citada como dependência externa; e por `gh issue view 187 --json state -q .state` devolver `OPEN`, que é a outra dependência citada. Se qualquer uma das duas deixar de ser verdadeira, o texto está desatualizado e a tarefa reprova — o critério mede a correspondência entre o que o documento afirma e o que o repositório faz, não a presença das palavras no arquivo.

## Paralelismo

Só a tarefa 1 abre — é a única com `depende de: nenhuma`. A 2 e a 3 dependem dela e ambas tocam `scripts/handover.cjs`, então rodam em sequência entre si, nunca em paralelo. A 4 também depende da 1: o critério dela mede o `.gitignore` e o comando do README contra o arquivo que a 1 produz, e sem esse arquivo não há o que medir — foi o motivo de ela deixar de ser paralela. A 5 depende de 1 e 2. A 6 fecha, depois de 1 e 5, com a peça entregue à vista.

## O que este plano deliberadamente não faz

- **Não constrói `regente.cjs`, em nenhuma versão** — D1 e "Avaliado e descartado". As duas razões que o justificavam já são convenção do repositório; a que sobrou é a Q1, do dono. Construir agora decidiria a Q1 por omissão, porque a forma do comando implica a política de retry.
- **Não conserta `hooks/lib/poda-estagio.cjs`** — dependência externa (fluxo 5). Bloqueia a Q2 e está registrada como tal.
- **Não conserta `hooks/lib/cli-externo.cjs` / Issue #187** — dependência externa, outro dono.
- **Não implementa o destilamento de encerramento para memória** (Q5) — `memoria.cjs consolidar` já existe, mas sobre outro substrato (observações de transcrito, não evidência de gate).
- **Não fixa o TTL do handover** (Q3) — o `status` mede coerência de estágio, que basta para a entrega; a injeção automática que precisaria do TTL não faz parte dela.
