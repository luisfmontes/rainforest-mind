# Plano: Mods do painel de PR e plugins em dia dentro do rainforest

Design: docs/rainforest/design/2026-10-09-mods-pr-e-plugins.md

Base: `279ec07f` (ponta de `origin/main` em 2026-10-09, versão 1.53.2).
Protótipos provados nesta data, ponto de partida do código (lidos, nunca importados):
`<home>/.claude-personal/dev-mods/<sessao>/painel-pr/hooks/register.tsx` e
`<home>/.claude-personal/dev-mods/<sessao>/plugins-em-dia/hooks/register.ts`.

## Emenda ao design

- **D9**: o padrão da lista é só `rainforest-mind@rainforest-mind`. O repositório é público e o gate de publicação barra o nome do marketplace de trabalho; o plugin de trabalho entra pela opção, configurada na máquina dele.

## O que não pode quebrar

- A abertura, a barra acima do prompt e o `/painel` seguem iguais: `node hooks/testa-mod-abertura.cjs`, `node hooks/testa-mod-painel.cjs`, `node hooks/testa-mod-faixa.cjs`, `node hooks/testa-mod-relogio.cjs`, `node hooks/testa-mod-mapa.cjs` e `node hooks/testa-mod-deixado.cjs` saem 0 sem alteração nesses arquivos de teste.
- O hook de `tool.call` do painel de PR **nunca** altera ou faz falhar o comando que observa: devolve o resultado de `next(e)` como veio, inclusive quando ele próprio lança (`.catch` que repassa).
- Sem PR acompanhado, o mod não roda `gh` nenhuma vez depois da checagem de abertura (sem polling ocioso).
- A sessão só é acordada (`$.prompt.submit`) por PR desta sessão (D6); PR acompanhado por `/pr` nunca acorda.
- `varrer-baterias` não depende do binário `claude` (CI): a lógica vive em `.mjs` puro testado em Node; `claude plugin test` é prova local, em arquivo sem prefixo `testa-`.
- Nenhum nome do marketplace ou plugin de trabalho, nem caminho com o usuário da máquina, entra em arquivo versionado.
- Os protótipos em `dev-mods/` ficam fora do repositório e são removidos antes da prova ao vivo (tarefa 6), para não haver dois `/pr` registrados.

## Tarefas

### 1. Lógica pura do painel de PR [tipo: implementar]
atende: D3, D4, D5, D6, D7, D10
arquivos: `hooks/pr-puro.mjs`, `hooks/testa-mod-pr.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-mod-pr.cjs`
mutacao:
  arquivo: `hooks/pr-puro.mjs`
  de: `return origem === 'sessao' || /^fluxo\//.test(branch || '');`
  para: `return true;`
  bateria: `node hooks/testa-mod-pr.cjs`
  fixture: `testa-mod-pr.cjs, caso "PR acompanhado por /pr em branch comum nao e da sessao"`
pronto quando: com a saída REAL de `gh pr view 455 --repo luisfmontes/rainforest-mind --json number,title,url,state,isDraft,headRefOid,headRefName,baseRefName,author,updatedAt,mergeable,mergeStateStatus,reviewDecision,latestReviews,statusCheckRollup,comments` e de `gh api graphql` com `reviewThreads(first:100){totalCount nodes{isResolved}}` do mesmo PR (coladas como fixtures, com uma variante em que só `statusCheckRollup` muda de `IN_PROGRESS` para `COMPLETED/SUCCESS` e outra com `mergeStateStatus: DIRTY`), `resumir(pr, threads)` devolve branch → base, autor, estado, checks, mergeabilidade com motivo e `threadsAbertas/threadsTotal`; `eventos(velho, novo, agora)` devolve cada mudança como `{ icone, texto: 'A → B' }` e **não** emite a linha "sem checks" quando ela vem logo depois de um push (D10); `virada(velho, novo)` devolve `checks-ok`, `checks-falha`, `mudanca-pedida`, `conflito` ou `merged`, e `null` para mudança não decisiva; `quieto(ultimaMudancaMs, agoraMs)` é verdadeiro só a partir de 180000 ms; `ehDaSessao({ origem, branch })` é verdadeiro para `origem: 'sessao'` e para branch `fluxo/*` e falso para `/pr` em branch comum; `nota(virada, resumo)` traz número, título e a ação da D5 (verde e `mergeStateStatus: CLEAN` → "mergeie"; verde e não `CLEAN` → não manda mergear; vermelha → "investigue e conserte na branch"; mudança pedida ou conflito → "resuma e traga ao usuário, sem alterar") — provado por `node hooks/testa-mod-pr.cjs` imprimindo `N ok, 0 falha(s), 0 skipped`.

Nota: ES module sem Node e sem `$`, no molde de `hooks/painel-puro.mjs`. `ehDaSessao` termina com exatamente `return origem === 'sessao' || /^fluxo\//.test(branch || '');`, uma vez só. Nenhum caso afirma sobre o texto do fonte. Superfície humana: a bateria falha se número, título, branch → base, motivo de bloqueio ou contagem de threads sumirem do resumo.

### 2. Lógica pura do plugins-em-dia [tipo: implementar]
atende: D8, D9, D10
arquivos: `hooks/plugins-em-dia-puro.mjs`, `hooks/testa-mod-plugins-em-dia.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-mod-plugins-em-dia.cjs`
mutacao:
  arquivo: `hooks/plugins-em-dia-puro.mjs`
  de: `.filter(id => (registro.plugins?.[id] || []).some(i => i.scope === 'user'))`
  para: `.filter(id => (registro.plugins?.[id] || []).length > 0)`
  bateria: `node hooks/testa-mod-plugins-em-dia.cjs`
  fixture: `testa-mod-plugins-em-dia.cjs, caso "plugin instalado so no escopo local fica fora"`
pronto quando: com a FORMA real do `installed_plugins.json` da conta pessoal (versão 2, ids `nome@marketplace` com lista de instalações `scope`/`version`), copiada como fixture com o plugin e o marketplace de trabalho trocados por `plugin-trabalho@mkt-trabalho` e o `installPath` trocado por `<home>`, e uma variante em que `plugin-trabalho@mkt-trabalho` só tem a entrada `scope: 'local'`: `alvos(registro, lista)` devolve só os ids com entrada `scope: 'user'`; `marketplaces(alvos)` devolve cada marketplace uma vez, na ordem dos alvos; `subiram(antes, depois)` lista `nome antes -> depois` só do que mudou; `podeRodar(ultimaMs, agoraMs, forcado)` é falso abaixo de 1800000 ms e verdadeiro com `forcado`; `acaoAposSubir(subiram, recarregaSeguro)` devolve `'nada'` sem subida, `'recarregar'` com `recarregaSeguro: true` e `'avisar'` com `false` (D8); `LISTA_PADRAO` é `['rainforest-mind@rainforest-mind']` (D9, emenda) — provado por `node hooks/testa-mod-plugins-em-dia.cjs` imprimindo `N ok, 0 falha(s), 0 skipped`.

Nota: mesma ordem do `Update-ClaudePlugins` do perfil do PowerShell (marketplace antes de plugin; filtro por instalação no escopo user, nunca por `enabledPlugins`).

### 3. Fiação no mod: pane `/pr`, gatilho automático, despertar, `/plugins-em-dia` e opção [tipo: implementar]
atende: D2, D4, D6, D7, D8, D9
arquivos: `hooks/pr.tsx`, `hooks/plugins-em-dia.ts`, `hooks/mod.tsx`, `types/index.d.ts`, `.claude-plugin/plugin.json`, `hooks/mod-pr.test.tsx`
depende de: 1, 2
paralela: nao
prova: `claude plugin validate .claude-plugin/plugin.json 2>&1 | grep -q "command.run{command=pr}"`
mutacao:
  arquivo: `hooks/pr.tsx`
  de: `if (pr.deveAcordar) await $.prompt.submit(`
  para: `if (true) await $.prompt.submit(`
  bateria: `claude plugin test .`
  fixture: `mod-pr.test.tsx, caso "PR acompanhado por /pr nao acorda a sessao"`
pronto quando: com o `hooks/hooks.json`, o `plugin.json` e os tipos reais, `claude plugin validate .claude-plugin/plugin.json` sai 0 e lista `command.run{command=pr}`, `command.run{command=plugins-em-dia}`, `tool.call{tool=Bash|PowerShell}` com `.catch`, `ui.render{component=Pane, requestId=rainforest-mind-pr}` e os estados novos em `declares state:`, ao lado de todos os hooks que já listava em `279ec07f`; e `claude plugin test .` sai 0 com os casos de `mod-pr.test.tsx` em `terminal` e `desktop` — servindo por `on('process.run')` as saídas REAIS da tarefa 1 —: `gh pr create` observado no Bash abre o pane e marca origem `sessao`; `gh pr view 455` observado também abre; comando que falha não abre; o resultado do `tool.call` volta idêntico ao de `next(e)` mesmo com `gh` saindo 1; a virada `checks-ok` com PR da sessão grava a nota por `$.session.append` e, com o relógio simulado 180 s adiante, chama `$.prompt.submit` uma vez; o mesmo com PR de `/pr` em branch comum grava a nota e **não** chama `$.prompt.submit`; `merged` para o polling (nenhum `gh` depois); `/plugins-em-dia` com `process.run` servindo o registro antes e depois devolve o texto com `rainforest-mind 1.53.2 -> 1.54.0`; com `recarregaSeguro` falso não chama `$.command.run({ command: 'reload-plugins' })`. E `node hooks/testa-mod-abertura.cjs`, `node hooks/testa-mod-painel.cjs` e os casos existentes de `claude plugin test .` seguem verdes — provado por esses comandos.

Nota:
- `hooks/mod.tsx` importa estaticamente `register as pr` de `./pr.tsx` e `register as pluginsEmDia` de `./plugins-em-dia.ts` e os chama no `register`, como já faz com a abertura. Sem `import()`.
- O engine recusa `$` passado a função própria: o `$` só aparece dentro das closures de `pr.tsx`/`plugins-em-dia.ts`; aos `.mjs` vão valores.
- Átomos em `rainforest-mind` com prefixo `pr`/`pluginsEmDia`; tipos em `types/index.d.ts` com prefixo `RainforestMind`.
- `.claude-plugin/plugin.json` ganha em `userConfig` a lista de plugins (D9, padrão `LISTA_PADRAO`) e `recarregarSozinho` (boolean, padrão `false` até a tarefa 4 medir).
- `pr.deveAcordar` = `ehDaSessao(...) && virada !== null && quieto(...)`, calculado no `.mjs`; a linha `if (pr.deveAcordar) await $.prompt.submit(` aparece uma vez só.

### 4. Medir o recarregamento na conta de trabalho [tipo: pesquisar]
atende: D8
arquivos: nenhum
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: medição em sessão interativa real da conta de trabalho; a falsificação é o controle (a pergunta-sonda respondida antes do reload) e o relato do que a sessão respondeu depois.
pronto quando: numa sessão da conta de trabalho com o rainforest-mind instalado, a pergunta-sonda sobre "O terceiro caso:" é respondida antes; depois de `/reload-plugins` e `/clear` a mesma sonda é feita de novo, e o texto das duas respostas fica colado na evidência; resposta `NONE` depois do reload = risco confirmado, e o padrão de `recarregarSozinho` fica `false`; resposta correta = padrão vira `true` na tarefa 3 (emenda de uma linha) — provado pelas respostas coladas.

Nota: é o `ao_colher` da ideia `append-conta-org-perde-flag-no-reload`. Precisa do usuário na conta de trabalho; não bloqueia as tarefas 1 a 3. Com o resultado, colher a ideia por `node scripts/ideias.cjs colher`.

### 5. Documentação, versão 1.54.0 e CHANGELOG [tipo: docs]
atende: D1, D10
arquivos: `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 3, 4
paralela: nao
mutacao: n/a
  motivo: tarefa de documentação e versão, sem comportamento a inverter; a falsificação é a coerência com o design e com o código entregue.
pronto quando: a versão 1.54.0 está em `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` e no badge do `README.md`; `## 1.54.0` no topo do `CHANGELOG.md` diz o que ele passa a ver (o pane de PR que abre sozinho, `/pr`, o despertar só em PR da sessão e o que o Claude faz em cada virada, `/plugins-em-dia`, a opção da lista e se recarrega sozinho conforme a tarefa 4); a seção do mod em `CONTRIBUTING.md` cita o intervalo de consulta, os 3 min de quietude e a regra de "PR desta sessão" — provado por um `node -e` que importa `hooks/pr-puro.mjs` e `hooks/plugins-em-dia-puro.mjs`, lê os números (`POLL_MS`, o limiar do `quieto`, `LISTA_PADRAO`) e sai 1 se o texto do `CHANGELOG.md`/`CONTRIBUTING.md` divergir deles, mais `node scripts/conferir-versao.cjs` e `bash scripts/testa-versao.sh` saindo 0.

### 6. Prova ao vivo [tipo: teste]
atende: D1, D2, D4, D5
arquivos: nenhum
depende de: 5
paralela: nao
prova-na-base: verde — prova em sessão interativa real com o plugin carregado por `--plugin-dir`; não há comando que reproduza a sessão na base.
mutacao: n/a
  motivo: medição em sessão interativa real; o controle é a sessão sem o plugin do worktree, em que nada abre.
pronto quando: com a pasta de protótipos em `dev-mods/` removida e uma sessão `claude --plugin-dir <worktree deste fluxo>`, um `gh pr create` real (o PR deste fluxo) abre o pane com branch → base, autor, checks e threads; a CI terminando gera a nota na conversa e, com a sessão parada, um turno novo em que o Claude age conforme a D5; `/plugins-em-dia` responde com as versões reais — provado pelos prints do pane e pelo trecho do transcript com a nota e o turno acordado, colados na evidência e no PR.

## Cobertura

D1: 5, 6 · D2: 3, 6 · D3: 1 · D4: 1, 3, 6 · D5: 1, 6 · D6: 1, 3 · D7: 1, 3 · D8: 2, 3, 4 · D9: 2, 3 · D10: 1, 2, 5

## Lacunas conhecidas

- Se `$.prompt.submit` interromper um turno em curso em vez de esperar a sessão ficar parada, a D7 cai; os tipos dizem que ele "starts a turn of its own once the session is idle", e a tarefa 6 confere ao vivo.
