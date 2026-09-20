# Plano — régua selada por construção e keep/discard por comparação interna

**Slug:** `2026-09-19-regua-selada-keep-discard` · **Design:** `docs/rainforest/design/2026-09-19-regua-selada-keep-discard.md`
**Base:** `origin/main` @ `4f714ef6` · **Branch:** `fluxo/regua-selada-keep-discard`

Cinco tarefas, dezoito decisões. **Fan-out em duas ondas**, separadas por arquivo
compartilhado:

- **Onda 1** (arquivos disjuntos entre si): T1 (`scripts/conferir-regua.cjs` e sua
  bateria), T3 (`skills/regua/SKILL.md`), T5 (`vigias/livro-de-repos.md`).
- **Onda 2**: T2 volta ao script depois da T1, T4 volta à skill depois da T3.

**Restrição que vale para todas:** o repo é público — nenhum caminho desta máquina
em código, teste ou fixture. Toda asserção de bateria tem os dois ramos (`if/else`).
Bloco `mutacao` com `de:`/`para:` **literais**. O critério das duas tarefas `docs`
mora em `docs/rainforest/criterios/fluxo-13-regua-fase0.md` e
`docs/rainforest/criterios/fluxo-13-regua-loop.md`, escritos neste estágio e
**não** por quem executa — critério redigido pelo mesmo agente que ele deveria
travar não trava nada. Os dois são julgados por `scripts/segunda-opiniao.cjs`, na
mesma forma que fechou o fluxo 12 (`docs/rainforest/estado/fluxo-12-regua.json`).
**Atenção para o `verificar`:** `segunda-opiniao.cjs` não é peça marcada `sensor`
por `conferir-categoria.cjs`, então o fechamento das tarefas 3 e 4 precisa
declarar `sensor_externo` no `--json`, senão `estado.cjs` recusa com exit 2.

**Prescrição de nomes para T1/T2.** O bloco `mutacao` depende de linha literal, e
a linha ainda não existe. O script expõe, obrigatoriamente: a constante
`const EXIT_RECUSA = 1;`, a função `ancoraDe(slug)` (só resolve a âncora) e a
função `exigirAncoraEFormato(slug)` (resolve a âncora, valida o formato, aborta
com `EXIT_RECUSA`). Nome diferente reprova a tarefa pelo bloco `mutacao`.

**Emenda de 2026-09-20 (creep do `revisar`).** Três arquivos entraram no diff
sem tarefa que os cobrisse, e o `conferir-fluxo.cjs creep` os pegou:

- `scripts/testa-conferir-categoria.sh` entra em `arquivos:` da T1. Não foi
  escolha: a bateria fixa a distribuição real de categorias do repo, e um sensor
  novo obriga a atualizá-la. Era consequência da T1 que o plano não previu.
- `docs/rainforest/criterios/fluxo-13-regua-fase0.md` entra na T3 e
  `...-loop.md` na T4. Os dois foram escritos **neste estágio**, de propósito —
  critério redigido por quem executa não trava nada —, mas são artefatos do diff
  e precisam de dono declarado.

## O que não pode quebrar
- Todas as baterias `scripts/testa-*.sh` e `hooks/testa-*.sh` continuam verdes (CI roda todas).
- `docs/rainforest/reguas/2026-09-14-conferidor-de-cli.md` não é tocado e nada o passa pelo conferidor novo: foi medição de uma vez só, já encerrada, e reabri-lo para ganhar seção "Freios" seria rejulgar peça antiga sob régua nova.
- O builder continua sem ver o manifesto de mecanismos (critério 1 de `docs/rainforest/criterios/fluxo-12-regua.md`).
- As seis afirmações de `docs/rainforest/criterios/fluxo-12-regua.md` continuam verdadeiras sobre o texto da skill depois das T3 e T4.
- `scripts/conferir-categoria.cjs` continua verde: o script novo declara `// @categoria: sensor`.

## Tarefas

### 1. `conferir-regua.cjs` confere âncora e formato do manifesto [tipo: implementar]
atende: D1, D4, D5, D6, D7
arquivos: `scripts/conferir-regua.cjs`, `scripts/testa-conferir-regua.sh`, `scripts/testa-conferir-categoria.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-regua.cjs`
  de: `const EXIT_RECUSA = 1;`
  para: `const EXIT_RECUSA = 0;`
  bateria: `bash scripts/testa-conferir-regua.sh`
  fixture: `testa-conferir-regua.sh, caso "manifesto editado na arvore de trabalho recusa"`
pronto quando: num repositório git real com `docs/rainforest/reguas/<slug>.md` commitado e depois editado na árvore de trabalho, `node scripts/conferir-regua.cjs conferir --slug <slug>` sai 1 nomeando o arquivo; com o manifesto intacto mas sem a seção `## Freios`, sai 1; com quatro `### M<n>`, sai 1; com manifesto intacto, `## Freios` presente e 5 a 7 `### M<n>` sequenciais, sai 0; com slug inexistente, sai 2 — provado por `bash scripts/testa-conferir-regua.sh` devolvendo `resultado: N ok, 0 falha(s)` e exit 0, com zero casos pulados.

### 2. Modo `mostrar`: a checagem e a leitura são o mesmo caminho [tipo: implementar]
atende: D2, D3
arquivos: `scripts/conferir-regua.cjs`, `scripts/testa-conferir-regua.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/conferir-regua.cjs`
  de: `const ancora = exigirAncoraEFormato(slug);`
  para: `const ancora = ancoraDe(slug);`
  bateria: `bash scripts/testa-conferir-regua.sh`
  fixture: `testa-conferir-regua.sh, caso "mostrar com manifesto editado nao imprime nada"`
pronto quando: num repositório git real, com o manifesto alterado na árvore de trabalho, `node scripts/conferir-regua.cjs mostrar --slug <slug>` escreve **zero byte** em stdout e sai 1; com o manifesto intacto, o stdout é byte a byte idêntico a `MSYS_NO_PATHCONV=1 git show "$(git log --diff-filter=A --format=%H -- docs/rainforest/reguas/<slug>.md | tail -1)":docs/rainforest/reguas/<slug>.md` — provado por `bash scripts/testa-conferir-regua.sh` devolvendo `resultado: N ok, 0 falha(s)` e exit 0.

### 3. Skill `regua`: Fase 0 passa a produzir manifesto selado [tipo: docs]
atende: D2, D18
arquivos: `skills/regua/SKILL.md`, `docs/rainforest/criterios/fluxo-13-regua-fase0.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: tarefa de texto prescritivo; não há linha de comportamento a inverter. A falsificação é o crítico cego do `pronto quando`, que julga coerência com o design e não presença de string.
pronto quando: com o diff real da branch contra `origin/main`, um modelo de outra família julgando as quatro afirmações da Fase 0 responde `concordo` na última linha — provado por `node scripts/segunda-opiniao.cjs --base origin/main --head HEAD --criterio docs/rainforest/criterios/fluxo-13-regua-fase0.md --modelo codex` devolvendo exit 0; e as seis afirmações do fluxo 12 continuam verdadeiras sobre o mesmo arquivo — provado por `node scripts/segunda-opiniao.cjs --base origin/main --head HEAD --criterio docs/rainforest/criterios/fluxo-12-regua.md --modelo codex` devolvendo `concordo` e exit 0.

### 4. Skill `regua`: Fase 2, keep/discard e as quatro paradas [tipo: docs]
atende: D8, D9, D10, D11, D12, D13, D14, D15, D16
arquivos: `skills/regua/SKILL.md`, `docs/rainforest/criterios/fluxo-13-regua-loop.md`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: mesma natureza da tarefa 3 — texto prescritivo, sem comportamento executável a inverter.
pronto quando: com o diff real da branch contra `origin/main`, um modelo de outra família julgando as sete afirmações do loop responde `concordo` na última linha — provado por `node scripts/segunda-opiniao.cjs --base origin/main --head HEAD --criterio docs/rainforest/criterios/fluxo-13-regua-loop.md --modelo codex` devolvendo exit 0.

### 5. `karpathy/autoresearch` entra no livro de repos [tipo: docs]
atende: D17
arquivos: `vigias/livro-de-repos.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: uma linha de tabela; o comportamento que a protege já existe e é a catraca `conferir-livro-de-repos.cjs`, cuja bateria não muda nesta entrega.
pronto quando: com a linha de `karpathy/autoresearch` datada de `2026-09-19` na tabela "Avaliados", `node scripts/conferir-livro-de-repos.cjs` sai 0 — e, trocando o veredito dessa linha para `Enxertar: vale a pena`, sai 2 com `VEREDITO FORA DO VOCABULÁRIO` citando a linha, provando que a linha nova está de fato dentro do alcance da catraca e não antes do corte.
