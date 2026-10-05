# Plano: Zerar issues: #377, #378, #379, #382, #385

Design: docs/rainforest/design/2026-10-05-zerar-issues-15.md

Base: `530d62b7` (origin/main). O critério de tempo da tarefa 9 só se mede no CI do PR do fluxo, que roda só em PR: o PR abre em rascunho ao fim do `executar`.

## O que não pode quebrar
- Toda bateria existente segue verde e sem perder caso (contagem de `ok` não cai em bateria alterada).
- `estado.cjs marcar` sem `arquivo`/`doc` no `--json` segue como hoje (falha aberta para projeto sem plano em disco).
- `conferir-mutacao.cjs` mantém os códigos de saída documentados (0, 1, 2, 3, 4, 5, 69) e a cópia descartável (#266): o fonte do usuário nunca é mutado.
- Plano sem `raiz:` em `mutacao:` roda exatamente como hoje (`--raiz` = raiz do repo).
- O mod continua passando `--cwd`/`CLAUDE_PROJECT_DIR` aos scripts; `claude plugin validate .claude-plugin/plugin.json` sai 0.
- O CI conta as mesmas 168+ baterias: a união dos shards é a lista do `varrer-baterias.sh` sem `--shard`.

## Tarefas

### 1. marcar recusa plano ou design declarado e ausente [tipo: implementar]
atende: D1
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — o comportamento novo só se mede pelos casos novos da bateria, que a base não tem
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `if (declarado && !fs.existsSync(path.resolve(RAIZ, declarado)))`
  para: `if (false)`
  bateria: `bash scripts/testa-estado.sh`
  fixture: `testa-estado.sh, casos "marcar plano ok com arquivo declarado ausente recusa" e "marcar design aprovado com doc declarado ausente recusa"`
pronto quando: num slug de caixa (`RFM_ESTADO_ROOT` temporário, o mesmo modelo dos casos existentes), `marcar --estagio plano --status ok --json '{"arquivo":"docs/rainforest/planos/<slug>.md",...}'` com o arquivo ausente sai 2 com stderr contendo `RECUSADO: plano declarado em 'arquivo' não existe` e o estado segue sem `plano: ok`; o mesmo para `--estagio design --status aprovado --json '{"doc":...}'` (mensagem com `design declarado em 'doc' não existe`); com o arquivo presente, os dois seguem fechando; sem o campo, comportamento atual. A condição tem a forma literal `if (declarado && !fs.existsSync(path.resolve(RAIZ, declarado)))`, com `declarado` = `extra.arquivo` no `plano` e `extra.doc` no `design` — provado por `bash scripts/testa-estado.sh` imprimindo os dois casos novos como ok e `0 falha(s)`

### 2. catraca copia a raiz com junction sem pedir privilégio [tipo: implementar]
atende: D2
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base sai 1 com EPERM no caso novo, que ela não tem
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (fs.lstatSync(p).isSymbolicLink()) { links.push(p); return false; }`
  para: `if (false) { links.push(p); return false; }`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: `testa-conferir-mutacao.sh, caso "raiz com node_modules como junction mede e sai 0"`
pronto quando: com uma raiz de caixa cujo `node_modules` é junction (`fs.symlinkSync(alvo, '<raiz>/node_modules', 'junction')`, que no Windows não exige privilégio) para uma pasta com um módulo que a bateria importa, `conferir-mutacao.cjs` com uma mutação que a bateria pega sai 0 (`ok: bateria VERMELHA`) em vez de 1 com `EPERM`; o `filter` do `cpSync` tem a linha literal do `de:` acima, e cada link guardado é recriado na pasta temporária com `fs.symlinkSync(fs.realpathSync(p), destino, 'junction')` para diretório e cópia do conteúdo para arquivo — provado por `bash scripts/testa-conferir-mutacao.sh` imprimindo o caso novo como ok e `0 falha(s)`

### 3. cópia da raiz que falha sai 69 [tipo: implementar]
atende: D3
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: 2
paralela: nao
prova-na-base: verde — a base sai 1 com stack trace no caso novo, que ela não tem
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `const EXIT_COPIA_FALHOU = 69;`
  para: `const EXIT_COPIA_FALHOU = 1;`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: `testa-conferir-mutacao.sh, caso "junction quebrada na raiz sai 69 nao-verificavel"`
pronto quando: com uma raiz de caixa cujo `node_modules` é junction para uma pasta já apagada, `conferir-mutacao.cjs` sai 69, com stderr começando por `nao-verificavel: copia da raiz falhou —` e sem stack trace (`at ` não aparece no stderr); o `catch` da cópia sai por `process.exit(EXIT_COPIA_FALHOU)` com `const EXIT_COPIA_FALHOU = 69;` — provado por `bash scripts/testa-conferir-mutacao.sh` imprimindo o caso novo como ok e `0 falha(s)`

### 4. caso vermelho sai inteiro mesmo com saída truncada [tipo: implementar]
atende: D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: 3
paralela: nao
prova-na-base: verde — a base trunca e não tem o caso novo
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `const MARCAS_FALHA = ['FALHA', '✖', '(fail)', 'not ok'];`
  para: `const MARCAS_FALHA = [];`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: `testa-conferir-mutacao.sh, caso "falha no meio de saida longa aparece em casos vermelhos"`
pronto quando: com uma bateria de caixa que imprime 300 linhas de `ok`, uma linha `FALHA caso-escondido-no-meio` no meio e mais 300 linhas, e sai 1 com a mutação aplicada, o stdout do `conferir-mutacao.cjs` traz uma seção `--- casos vermelhos ---` com a linha `FALHA caso-escondido-no-meio` inteira, mesmo com o trecho geral truncado; as marcas vêm da constante literal do `de:` acima — provado por `bash scripts/testa-conferir-mutacao.sh` imprimindo o caso novo como ok e `0 falha(s)`

### 5. mutacao aceita raiz por tarefa [tipo: implementar]
atende: D5
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo.sh`, `skills/plano/SKILL.md`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base não tem o campo `raiz:` nem o caso novo
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `'--raiz', raizTarefa,`
  para: `'--raiz', RAIZ,`
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: `testa-conferir-fluxo.sh, caso "mutacoes com raiz: de app roda a bateria dentro do app"`
pronto quando: num repo de caixa com `app/src/x.js` e `app/test/x.test.js` (bateria `node --test test/x.test.js`, só existe relativa a `app/`) e um plano cujo bloco `mutacao:` traz `raiz: app` e `arquivo: src/x.js`, `conferir-fluxo.cjs mutacoes` imprime `tarefa 1: vermelho` e sai 0 (na base sai `pulada`); `cobertura` com `raiz: nao-existe` recusa citando a pasta; sem `raiz:`, o caso existente segue igual. O argumento é montado com `const raizTarefa = campos.raiz ? path.resolve(RAIZ, campos.raiz.replace(/^`|`$/g, '').trim()) : RAIZ;` e passado como `'--raiz', raizTarefa,`; o template de `mutacao:` em `skills/plano/SKILL.md` mostra o campo `raiz:` opcional com uma frase sobre monorepo — provado por `bash scripts/testa-conferir-fluxo.sh` imprimindo o caso novo como ok e `0 falha(s)`

### 6. razao mostra o erro quando não há rótulo [tipo: implementar]
atende: D6
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo.sh`
depende de: 5
paralela: nao
prova-na-base: verde — a base devolve motivo vazio e não tem o caso novo
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `const MARCAS_ERRO = ['Error', 'erro', 'EPERM'];`
  para: `const MARCAS_ERRO = [];`
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: `testa-conferir-fluxo.sh, caso "pulada por erro sem rotulo traz a linha do erro"`
pronto quando: com uma tarefa cujo `conferir-mutacao.cjs` sai com stderr sem rótulo conhecido e uma linha `Error: ENOENT: arquivo-de-teste` (por exemplo `arquivo:` apontando para pasta, ou outro modo reproduzível que o executor escolher e nomear), a linha de `conferir-fluxo.cjs mutacoes` termina em ` — Error: ENOENT: arquivo-de-teste` em vez de motivo vazio; `razao()`, sem rótulo, devolve a primeira linha do stderr que contém um item da constante literal do `de:` acima — provado por `bash scripts/testa-conferir-fluxo.sh` imprimindo o caso novo como ok e `0 falha(s)`

### 7. mod roda node com cwd na raiz do plugin [tipo: implementar]
atende: D7
arquivos: `hooks/mod.tsx`, `hooks/abertura-mod-puro.mjs`, `hooks/mod-relogio.test.tsx`, `hooks/mod-faixa.test.tsx`, `hooks/testa-mod-abertura.cjs`
depende de: nenhuma
paralela: sim
prova-na-base: verde — o comportamento só se observa no `claude plugin test` com o caso novo, que a base não tem
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `const r = await io.rodar(argv, { cwd: io.raiz, env, timeoutMs })`
  para: `const r = await io.rodar(argv, { env, timeoutMs })`
  bateria: `claude plugin test .`
  fixture: `mod-relogio.test.tsx, test "o process.run do relogio roda com cwd na raiz do plugin"`
pronto quando: com o `process.run` no formato real do engine, as três chamadas `node` de `hooks/mod.tsx` (faixa-dados em `buscar`, relogio-sessoes e jornada em `rodarJson`, que passa a receber a raiz em `io`) e a de `hooks/abertura-mod-puro.mjs` chegam com `cwd` igual à raiz do plugin (`$.plugin.root`), continuando a mandar `--cwd <pasta da sessão>` e `CLAUDE_PROJECT_DIR`; o `test` novo do relógio (terminal e desktop) confere o `cwd` das duas leituras do relógio, `mod-faixa.test.tsx` confere o da faixa, e `testa-mod-abertura.cjs` confere o da abertura — provado por `claude plugin test .` com `0 fail` e o `(pass)` do test novo, `node hooks/testa-mod-abertura.cjs` com `0 falha(s)`, e `claude plugin validate .claude-plugin/plugin.json` saindo 0

### 8. .cjs chamam o node pelo caminho do processo [tipo: implementar]
atende: D8
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/gate-verificador-staged.cjs`, `scripts/conselho.cjs`, `scripts/poda.cjs`, `scripts/testa-node-por-nome.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-node-por-nome.sh`
mutacao:
  arquivo: `hooks/gate-verificador-staged.cjs`
  de: `spawnSync(process.execPath, [verificador.caminho`
  para: `spawnSync("node", [verificador.caminho`
  bateria: `bash scripts/testa-node-por-nome.sh`
  fixture: `testa-node-por-nome.sh, caso "nenhum spawn/exec de node por nome fora de bateria"`
pronto quando: com os `.cjs` reais de `hooks/` e `scripts/` (fora `testa-*`), nenhuma chamada `spawn`/`spawnSync`/`execFile`/`execFileSync`/`exec`/`execSync` tem `'node'` ou `"node"` como comando — os cinco pontos (`gate-publicacao-destino.cjs` `execFileSync`, `gate-verificador-staged.cjs`, `conselho.cjs` nos dois, `poda.cjs`) passam a `process.execPath`; a bateria nova `scripts/testa-node-por-nome.sh` (cabeçalho `# @categoria: bateria`) varre os arquivos, lista cada ocorrência com `arquivo:linha` quando falha, e prova que acende plantando uma ocorrência numa cópia temporária — provado por `bash scripts/testa-node-por-nome.sh` saindo 0 com `0 falha(s)` e `node scripts/conferir-categoria.cjs` saindo 0

### 9. CI em dois shards repartidos por tempo [tipo: implementar]
atende: D9
arquivos: `scripts/repartir-baterias.cjs`, `scripts/tempos-baterias.json`, `scripts/varrer-baterias.sh`, `scripts/testa-varrer-baterias.sh`, `.github/workflows/baterias.yml`
depende de: nenhuma
paralela: sim
prova-na-base: verde — `--shard` não existe na base; o caso novo é o que mede
mutacao:
  arquivo: `scripts/repartir-baterias.cjs`
  de: `const alvo = cargas.indexOf(Math.min(...cargas));`
  para: `const alvo = 0;`
  bateria: `bash scripts/testa-varrer-baterias.sh`
  fixture: `testa-varrer-baterias.sh, caso "shards 1/2 e 2/2 cobrem a lista inteira, sem repetir, com cargas equilibradas"`
pronto quando: com a lista real de baterias do repositório e `scripts/tempos-baterias.json` gerado do log do último run verde do PR #390 (segundos por bateria), `bash scripts/varrer-baterias.sh --shard 1/2 --listar` e `--shard 2/2 --listar` imprimem listas disjuntas cuja união é igual à lista sem `--shard`, com diferença de carga somada ≤ o maior peso individual; `scripts/repartir-baterias.cjs` ordena por peso decrescente (empate por nome) e põe cada bateria no shard de menor carga com a linha literal do `de:` acima; bateria sem peso recebe a mediana; o `baterias.yml` roda a matriz `shard: [1, 2]` com `bash scripts/varrer-baterias.sh --shard ${{ matrix.shard }}/2`, nome `baterias (node 24, shard N/2)`, mesmo `timeout-minutes: 35`, e o comentário do topo que falava em 20 baterias/3 min passa a dizer o que se mede hoje; no CI do PR do fluxo, cada job de shard termina em ≤ 25 min (`gh run view` do PR) e a soma das baterias dos dois placares é igual ao total — provado por `bash scripts/testa-varrer-baterias.sh` com o caso novo ok e `0 falha(s)`, e pelo `gh run view` do PR

### 10. Notas da versão 1.39.2 e Issue do git/gh por nome [tipo: docs]
atende: D1, D2, D3, D4, D5, D6, D7, D8, D9
arquivos: `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`
depende de: 1, 2, 3, 4, 5, 6, 7, 8, 9
paralela: nao
mutacao: n/a
  motivo: nota de versão, bump e Issue não têm comportamento a inverter; a falsificação é a coerência com as decisões
pronto quando: versão `1.39.2` nos dois manifestos e no badge do README; `CHANGELOG.md` com `## 1.39.2 — 2026-10-05` descrevendo, do ponto de vista de quem usa, o efeito de cada uma das cinco issues (plano/design fantasma recusado; catraca mede com junction e diz por que não mediu; campo `raiz:` para monorepo; node não resolvido pela pasta do repo; CI em dois shards), sem prometer nada sobre `git`/`gh`; e uma Issue nova aberta no repo descrevendo o vetor de `git`/`gh` chamados por nome, com a medição do `node.exe` falso desta rodada — provado por `bash scripts/testa-versao.sh` saindo 0, leitura da seção contra o design e `gh issue view` da Issue nova

### 11. abertura roda node na raiz do plugin sem perder o projeto da memória [tipo: implementar]
atende: D7
arquivos: `scripts/memoria.cjs`, `hooks/memoria-session-start.cjs`, `hooks/abertura-mod-puro.mjs`, `hooks/testa-mod-abertura.cjs`, `hooks/testa-memoria-session-start.sh`
depende de: 7
paralela: nao
prova-na-base: verde — o caso novo da bateria é o que mede, e a base não o tem
mutacao:
  arquivo: `hooks/memoria-session-start.cjs`
  de: `resolverCaminhos(process.env.CLAUDE_PROJECT_DIR || process.cwd())`
  para: `resolverCaminhos()`
  bateria: `bash hooks/testa-memoria-session-start.sh`
  fixture: `testa-memoria-session-start.sh, caso "com cwd fora do projeto e CLAUDE_PROJECT_DIR no projeto, a memoria filtra pelo projeto"`
pronto quando: emenda da tarefa 7, que voltou parcial com evidência: `scripts/memoria.cjs:118` (`resolverCaminhos`) tira o projeto de `process.cwd()` e ignora `CLAUDE_PROJECT_DIR`, então mudar o `cwd` da abertura para a raiz do plugin trocaria o filtro de memória pelo do próprio plugin. `resolverCaminhos(cwd = process.cwd())` passa a usar o `cwd` recebido (no `encontrarGit` e no `resolverRaiz({ cwd, plugin })`), sem mudar os outros chamadores; `hooks/memoria-session-start.cjs` chama com a linha literal do `de:` acima; e `hooks/abertura-mod-puro.mjs` passa `cwd: io.raiz` mantendo `env: { CLAUDE_PROJECT_DIR: cwd }`. Com `memoria-session-start.cjs` rodado com a pasta atual = outra pasta e `CLAUDE_PROJECT_DIR` = um projeto de caixa, o projeto da saída é o da caixa; `testa-mod-abertura.cjs` espera o `cwd` na raiz do plugin — provado por `bash hooks/testa-memoria-session-start.sh` com o caso novo ok e `0 falha(s)`, `node hooks/testa-mod-abertura.cjs` com `0 falha(s)` e `claude plugin test .` com `0 fail`

### 12. gate de bateria deixa passar varrer-baterias --listar [tipo: implementar]
atende: D9
arquivos: `hooks/gate-bateria-sem-timeout.cjs`, `hooks/testa-gate-bateria-sem-timeout.cjs`
depende de: 9
paralela: nao
prova-na-base: verde — `--listar` não existe na base
mutacao:
  arquivo: `hooks/gate-bateria-sem-timeout.cjs`
  de: `if (analise.ehVarredor && analise.args.includes("--listar")) continue;`
  para: `if (false) continue;`
  bateria: `node hooks/testa-gate-bateria-sem-timeout.cjs`
  fixture: `testa-gate-bateria-sem-timeout.cjs, caso "varrer-baterias.sh --shard 1/2 --listar nao e varredura completa → 0"`
pronto quando: emenda achada na tarefa 9 — o subagente que rodou `bash scripts/varrer-baterias.sh --shard 1/2 --listar` (só imprime a lista) foi barrado três vezes como "varredura completa ~29 min". Com o payload de subagente que a bateria monta, `--shard 1/2 --listar` com timeout de 60 s sai 0, e `--shard 1/2` sem `--listar` segue barrado (2) — provado por `node hooks/testa-gate-bateria-sem-timeout.cjs` com `ok: 61   falhou: 0`
