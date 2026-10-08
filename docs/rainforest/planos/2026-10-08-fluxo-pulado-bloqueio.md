# Plano: Fluxo pulado — bloquear com caminho leve declarado (#430)

Design: docs/rainforest/design/2026-10-08-fluxo-pulado-bloqueio.md

**Base:** `origin/main` @ `23c52948` · **Branch:** `fluxo/fluxo-pulado-bloqueio`

Quatro tarefas. A T1 cria o `leve` e o leitor compartilhado; T2 (Edit) e T3
(despacho) dependem dele e tocam arquivos disjuntos. A T4 fecha doc e versão
por último.

**Restrição que vale para todas:** o repo é público — nenhum caminho desta
máquina em código, teste ou fixture; e-mail de `git config` em bateria é
`test@<email>`. Toda asserção tem os dois ramos. O payload de teste é o que
o harness manda no stdin do `PreToolUse` — `session_id`, `cwd`,
`hook_event_name`, `tool_name`, `tool_input` (com `file_path` no Edit/Write,
`subagent_type`/`prompt` no Agent) — e nenhum campo a mais.

## O que não pode quebrar
- Repositório **sem** fluxo (nem `docs/rainforest/estado/` nem `docs/plans/*.gates.json`): Edit e despacho passam como hoje, exit 0, sem saída nova.
- Fluxo aberto na branch: Edit de código passa, exit 0.
- Chave `aviso-fluxo` desligada no config: nada bloqueia (Edit nem despacho).
- Edit em `.md` e em qualquer arquivo sob `docs/`: passa.
- Edit feito por subagente (`agent_id` no payload): o gate do Edit não o barra (quem o barra é o despacho, T3).
- Portaria: a negação da regra 11 (escreve sem `isolation: "worktree"`) e o registro em `despachos.jsonl` continuam como estão; agente **não declarado** no manifesto (outro plugin) não é barrado por fluxo.
- `estado.cjs`: subcomandos e flags aceitos hoje continuam aceitos; `listar`, `concluido` e o `resolver` não tratam um registro de `leve` como fluxo aberto nem quebram ao lê-lo.
- Todas as baterias `scripts/testa-*.sh` e `hooks/testa-*` continuam verdes.

## Tarefas

### 1. `estado.cjs leve --motivo` e o leitor `caminho-leve` [tipo: implementar]
atende: D6, D7
arquivos: `scripts/estado.cjs`, `hooks/lib/caminho-leve.cjs`, `scripts/testa-estado-leve.sh`, `scripts/testa-estado.sh`, `scripts/testa-estado-territorio.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-estado-leve.sh`
mutacao:
  arquivo: `hooks/lib/caminho-leve.cjs`
  de: `return registro && typeof registro.motivo === 'string' && registro.motivo.trim() !== '' ? registro : null;`
  para: `return registro ? registro : null;`
  bateria: `bash scripts/testa-estado-leve.sh`
  fixture: caso "registro de leve com motivo vazio gravado a mao nao libera a branch"
pronto quando: num repositório git real com `docs/rainforest/estado/` e branch `fluxo/x`, `node scripts/estado.cjs leve --motivo "hotfix mecanico"` sai 0 e grava no estado versionado da branch um registro `leve` com `motivo` e `data`, que `leveDaBranch` de `hooks/lib/caminho-leve.cjs` devolve para `fluxo/x` e não devolve para `fluxo/y`; no mesmo repo na branch padrão (`main`), sai 2 com stderr citando a regra 11 e nada gravado; `--motivo ""` e `--motivo` ausente saem 2; num repositório só com `docs/plans/a.gates.json` (trilho protheus), sai 0 e grava sob o `.git` (`git rev-parse --git-common-dir`), nada na árvore de trabalho (`git status --porcelain` vazio), inclusive na branch padrão; `node scripts/estado.cjs listar` não mostra o registro de `leve` como trabalho e o `resolver` de `hooks/lib/estagio-ativo.cjs` continua devolvendo `null` na branch só com `leve` — provado por `bash scripts/testa-estado-leve.sh` com um caso por afirmação acima, placar `falhou: 0` e `skipped: 0`. A linha da mutação é escrita literalmente como no `de:`, uma expressão só, e nenhum caso afirma sobre o texto do fonte.

### 2. `aviso-fluxo` bloqueia toda edição de código sem fluxo nem `leve` [tipo: implementar]
atende: D1, D2, D4, D8, D9
arquivos: `hooks/aviso-fluxo.cjs`, `hooks/testa-aviso-fluxo.cjs`, `hooks/testa-bloqueio-fluxo.cjs`
depende de: 1
paralela: nao
prova: `node hooks/testa-bloqueio-fluxo.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo.cjs`
  de: `  process.exit(2); // bloqueio-fluxo`
  para: `  process.exit(0); // bloqueio-fluxo`
  bateria: `node hooks/testa-bloqueio-fluxo.cjs`
  fixture: caso "rainforest sem fluxo: Edit de .cjs sai 2 na primeira e na segunda edicao"
pronto quando: com o payload real do harness (`{"session_id","cwd","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"<repo>/scripts/x.cjs","old_string","new_string"}}`) num repositório git real com `docs/rainforest/estado/` e nenhum fluxo aberto na branch, o hook sai **2** com stderr que nomeia `estado.cjs iniciar`/`/rainforest-mind:brainstorm` **e** `estado.cjs leve --motivo` com o caminho absoluto do `scripts/estado.cjs` do plugin — e sai 2 de novo na segunda edição da mesma sessão (D8). Trilho protheus (`docs/plans/a.gates.json` com mais de 24 h): sai 2 nomeando `/protheus:trabalhar` e o `leve`. Casos vizinhos que **passam** com exit 0: depois de `estado.cjs leve --motivo x` na branch; fluxo aberto na branch; `.gates.json` com menos de 24 h; Edit de `README.md` e de `docs/x.cjs`; payload com `agent_id`; chave `aviso-fluxo` desligada; repositório sem fluxo; payload vazio ou ilegível. Contornos que **continuam bloqueados**: `tool_name` `Write` e `MultiEdit` com o mesmo arquivo; `file_path` relativo ao `cwd`; `cwd` num subdiretório do repo. Pergunta de superfície humana: quem lê o stderr sabe as duas saídas e o comando exato de cada uma — o caso falha se qualquer dos dois comandos sumir da mensagem. Provado por `node hooks/testa-bloqueio-fluxo.cjs` (um caso por linha acima, `falhou: 0`, `skipped: 0`) e `node hooks/testa-aviso-fluxo.cjs` atualizado (os casos que esperavam `additionalContext` passam a esperar o bloqueio) com `falhou: 0`. Parada declarada (D2): escrita por Bash não é caso desta bateria.

### 3. Portaria recusa despacho de agente que escreve fora do estágio dele [tipo: implementar]
atende: D3, D4, D5
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`, `hooks/testa-portaria-nucleo.cjs`
depende de: 1
paralela: nao
prova: `node hooks/testa-portaria-fluxo-pulado.cjs`
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `const bloqueiaFluxoPulado = trilhoComFluxo && escreveDeclarado && !leve && !estagioPermitido;`
  para: `const bloqueiaFluxoPulado = false;`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: caso "repo rainforest sem fluxo: despacho de executor sai 2"
pronto quando: com o payload real do harness para `Agent` (`{"session_id","cwd","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"subagent_type":"rainforest-mind:executor","prompt":"...","isolation":"worktree"}}`) num repositório git real com `docs/rainforest/estado/`: sem fluxo aberto e sem `leve`, a portaria sai **2** com stderr que nomeia o agente, o estágio exigido (`executar`) e as duas saídas (abrir/avançar o fluxo, `estado.cjs leve --motivo`); com fluxo aberto em `plano`, `executor` sai 2; com fluxo em `executar`, `executor` passa; com fluxo em `design`, `arqueologo` passa; com `leve` na branch, `executor` passa sem fluxo; `revisor` e `planejador` (`escreve: false`) passam sem fluxo; agente não declarado no manifesto passa sem fluxo; chave `aviso-fluxo` desligada, tudo passa; repositório sem fluxo nenhum, tudo passa. Trilho protheus: `.gates.json` com menos de 24 h libera (sem estágio a comparar), sem ele `executor` sai 2. Contorno que **continua bloqueado**: `subagent_type` sem o prefixo do plugin (`executor`) resolve para o mesmo agente do manifesto. Todo despacho que passa continua gravando a linha em `despachos.jsonl` como hoje. Provado por `node hooks/testa-portaria-fluxo-pulado.cjs` (um caso por afirmação, `falhou: 0`, `skipped: 0`) e as baterias `hooks/testa-portaria-*.cjs` existentes verdes.

### 4. Doc, regra 10 e versão [tipo: docs]
atende: D1, D2, D3, D4, D5, D6, D7, D8, D9
arquivos: `README.md`, `CHANGELOG.md`, `skills/rainforest-mind/SKILL.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `hooks/lib/config.cjs`, `hooks/testa-abertura-mod-foco.sh`
depende de: 2, 3
paralela: nao
mutacao: n/a
  motivo: só texto e número de versão; a falsificação é a coerência com o design e o `testa-versao.sh`.
pronto quando: com o design aprovado ao lado, o README deixa de listar o `aviso-fluxo` entre os hooks que "avisam sem barrar" e o descreve na tabela de travas com as duas saídas (abrir fluxo, `leve`) e a chave `aviso-fluxo` (a descrição da chave em `hooks/lib/config.cjs` deixa de dizer "avisa"); a linha da regra 10 no README e o núcleo em `skills/rainforest-mind/SKILL.md` deixam de dizer que estágio é só log e nomeiam a exceção do D5 (`escreve: true` fora do estágio dele, sem `leve`, é barrado); o CHANGELOG ganha a versão **1.49.0** dizendo o que muda para quem usa (bloqueio nos dois trilhos, `leve` por branch, despacho barrado, chave para desligar) e o que fica de fora (Bash, D2); `plugin.json` dos dois manifestos e o badge do README em 1.49.0 — provado por `bash scripts/testa-versao.sh` com `falhou: 0`, `bash hooks/testa-abertura-mod-foco.sh` com `falhou: 0` (o núcleo injetado mudou) e leitura lado a lado de cada D1–D9 contra o texto novo, registrada no relato do `executar` com a linha do doc que realiza cada uma.

## Emenda 1 — achados do revisar (2026-10-08)

O `revisar` reprovou com 7 achados. As tarefas 5 a 7 fecham os achados 1, 2, 3, 5, 6 e 7 dentro das decisões já aprovadas. O achado 4 (o que conta como "aberto" no trilho protheus) espera decisão do usuário e entra como emenda própria.

### 5. `aviso-fluxo` decide pelo repositório do arquivo, não pelo `cwd` [tipo: implementar]
atende: D1, D2, D9
arquivos: `hooks/aviso-fluxo.cjs`, `hooks/testa-bloqueio-fluxo.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-bloqueio-fluxo.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo.cjs`
  de: `const gitTop = toplevel(diretorioExistente(path.resolve(ev.cwd, filePath)));`
  para: `const gitTop = toplevel(ev.cwd);`
  bateria: `node hooks/testa-bloqueio-fluxo.cjs`
  fixture: caso "arquivo de codigo fora de qualquer repositorio passa com cwd num repo sem fluxo"
pronto quando: com o payload real do harness, (a) `cwd` num repositório rainforest sem fluxo e `Write` de um `.js` num diretório temporário fora de qualquer repositório sai **0**; (b) `cwd` fora de qualquer repositório e `Edit` de `<repo>/hooks/x.cjs` (repo com trilho, sem fluxo, sem `leve`) sai **2**; (c) `cwd` no checkout principal (`main`) e `Edit` de um `.cjs` dentro de um worktree cuja branch tem fluxo aberto sai **0**, e o mesmo sem fluxo nem `leve` sai **2**; (d) `Write` de `<repo>/pasta-nova/sub/x.cjs` (diretório ainda inexistente) sem fluxo sai **2** — o repositório se acha subindo até o primeiro diretório que existe; (e) `FONTE.PRW` e `A.CJS` sem fluxo saem **2** (extensão comparada em minúsculas) e `.c`, `.h`, `.cpp`, `.bat`, `.cmd` entram na lista; (f) HEAD destacado sem fluxo sai 2 com mensagem que manda trocar para uma branch, sem oferecer `leve` (que recusaria). A linha da mutação é escrita literalmente como no `de:`. Provado por `node hooks/testa-bloqueio-fluxo.cjs` (`falhou: 0`, `skipped: 0`) e `node hooks/testa-aviso-fluxo.cjs` sem falha.

### 6. Portaria: estágios do manifesto e mensagem sem beco [tipo: implementar]
atende: D3, D5, D9
arquivos: `.rainforest/agentes.padrao.json`, `hooks/portaria.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-portaria-fluxo-pulado.cjs`
mutacao:
  arquivo: `.rainforest/agentes.padrao.json`
  de: `"estagios": ["executar", "revisar", "verificar"],`
  para: `"estagios": ["executar", "verificar"],`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: caso "tester despacha com fluxo em revisar (mutacao do revisar)"
pronto quando: com o payload real do harness para `Agent` e o manifesto padrão do plugin, `tester` despachado com fluxo aberto em `revisar` passa (exit 0) — a skill `revisar` manda o `tester` executar a mutação — e `documentador` com fluxo em `fechar` passa; `executor` em `revisar` e em `fechar` continua saindo **2**. Com HEAD destacado, a mensagem de bloqueio manda trocar para uma branch em vez de oferecer `leve`; com o `cwd` na branch padrão de repo rainforest, a mensagem diz para despachar de dentro do worktree do fluxo (o `leve` é recusado ali). O lint do manifesto que `hooks/testa-portaria-lint.cjs` exercita aceita o manifesto novo. Provado por `node hooks/testa-portaria-fluxo-pulado.cjs` (`falhou: 0`, `skipped: 0`) e as baterias `hooks/testa-portaria-*.cjs` todas com exit 0.

### 7. `regra-10-portaria.md` acompanha o código [tipo: docs]
atende: D3, D5
arquivos: `skills/rainforest-mind/references/regra-10-portaria.md`
depende de: 6
paralela: nao
mutacao: n/a
  motivo: só texto de referência; a falsificação é a coerência com `hooks/portaria.cjs` e o manifesto.
pronto quando: com `hooks/portaria.cjs` e `.rainforest/agentes.padrao.json` ao lado, a tabela de `regra-10-portaria.md` deixa de dizer que "estágio fora da lista do agente" sempre passa — passa para agente que lê; agente declarado com `escreve: true` fora dos `estagios` dele, sem `leve`, é barrado (#430) — e a frase "a portaria barra um caso só" passa a nomear os dois casos (escreve sem worktree; escreve fora do estágio sem `leve`). Provado por leitura lado a lado registrada no relato, com a linha do código que sustenta cada frase.

## Emenda 2 — achados da rodada 2 do revisar (2026-10-08)

Rodada 2 reprovou com A (caminho do comando na portaria), B1/B2 (becos na mensagem do Edit), C (tabela da regra-10-portaria) e D (NotebookEdit). D fica como dívida declarada: `.ipynb` não está na lista de extensões de código, então o NotebookEdit não é "edição de código" pela D2 — o design passa a dizê-lo. O achado 4 (aberto no protheus) segue à espera da decisão do usuário.

### 8. `estado.cjs leve --repo <raiz>` [tipo: implementar]
atende: D6, D7
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-leve.sh`
depende de: 1
paralela: nao
prova: `bash scripts/testa-estado-leve.sh`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const raizLeve = repoArg ? path.resolve(repoArg) : RAIZ;`
  para: `const raizLeve = RAIZ;`
  bateria: `bash scripts/testa-estado-leve.sh`
  fixture: caso "leve --repo grava no repositorio indicado, nao no do cwd"
pronto quando: com `cwd` num repositório A (branch padrão `main`) e `--repo <raiz de B>` apontando para um worktree B na branch `fluxo/v` com `docs/rainforest/estado/`, `node scripts/estado.cjs leve --motivo x --repo <B>` sai 0, grava o `leve` no estado de B para `fluxo/v` e nada em A (`git -C A status --porcelain` vazio); sem `--repo`, o comportamento de hoje (cwd) não muda; `--repo` para caminho que não é repositório git sai 2 com stderr dizendo isso; trilho protheus com `--repo` grava sob o `git-common-dir` de B. A linha da mutação é escrita literalmente como no `de:`. Provado por `bash scripts/testa-estado-leve.sh` (`falhou: 0`, `skipped: 0`) e `bash scripts/testa-estado.sh` sem falha.

### 9. Mensagem do gate do Edit sem beco [tipo: implementar]
atende: D9
arquivos: `hooks/aviso-fluxo.cjs`, `hooks/testa-bloqueio-fluxo.cjs`
depende de: 8
paralela: nao
prova: `node hooks/testa-bloqueio-fluxo.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo.cjs`
  de: `const ofereceLeve = !headDestacado && !(trilho === 'rainforest' && ehBranchPadrao);`
  para: `const ofereceLeve = !headDestacado;`
  bateria: `node hooks/testa-bloqueio-fluxo.cjs`
  fixture: caso "rainforest na branch padrao: mensagem manda abrir worktree e nao oferece leve"
pronto quando: com o payload real do harness, (a) repo rainforest na branch padrão sem fluxo: sai 2 e a mensagem manda trabalhar num worktree (`git worktree add`) e abrir o fluxo lá, sem oferecer `leve`; (b) em qualquer caso que ofereça `leve`, o comando impresso é `node <abs>/scripts/estado.cjs leve --motivo "<por quê>" --repo "<raiz do repositório do arquivo>"`, com barras `/`, e **rodado de verdade pela bateria a partir de outro `cwd`** libera a próxima edição (exit 0); (c) o caminho do `estado.cjs iniciar` impresso também é absoluto com `/`. A linha da mutação é escrita literalmente como no `de:`. Provado por `node hooks/testa-bloqueio-fluxo.cjs` (`falhou: 0`, `skipped: 0`) e `node hooks/testa-aviso-fluxo.cjs` sem falha.

### 10. Mensagem da portaria com comando que roda [tipo: implementar]
atende: D9
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`
depende de: 8
paralela: nao
prova: `node hooks/testa-portaria-fluxo-pulado.cjs`
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `const leveDaMensagem = `node ${caminhoEstado} leve --motivo "<por que>" --repo "${raizBarras}"`;`
  para: `const leveDaMensagem = `node ${caminhoEstado} leve --motivo "<por que>"`;`
  bateria: `node hooks/testa-portaria-fluxo-pulado.cjs`
  fixture: caso "o leve impresso pela portaria, rodado de outro cwd, libera o despacho"
pronto quando: com o payload real do harness para `Agent` bloqueado por fluxo, o stderr traz o `estado.cjs` por caminho absoluto com barras `/` (nenhuma contrabarra no comando) nas duas saídas — a de abrir o fluxo (`iniciar`) e a do `leve` com `--repo "<raiz>"` —, e a bateria **roda o comando `leve` impresso** a partir de um `cwd` diferente e o despacho seguinte passa (exit 0). A linha da mutação é escrita literalmente como no `de:`. Provado por `node hooks/testa-portaria-fluxo-pulado.cjs` (`falhou: 0`, `skipped: 0`) e todas as `hooks/testa-portaria-*.cjs` com exit 0.

### 11. Doc: tabela da portaria e NotebookEdit [tipo: docs]
atende: D2, D5
arquivos: `skills/rainforest-mind/references/regra-10-portaria.md`, `docs/rainforest/design/2026-10-08-fluxo-pulado-bloqueio.md`
depende de: 10
paralela: nao
mutacao: n/a
  motivo: só texto; a falsificação é a coerência com `hooks/portaria.cjs` e `hooks/aviso-fluxo.cjs`.
pronto quando: a linha nova da tabela de `regra-10-portaria.md` diz que o bloqueio vale **em repositório com trilho de fluxo e com a chave `aviso-fluxo` ligada**, coerente com `trilhoComFluxo` em `hooks/portaria.cjs`; a D2 do design diz que `.ipynb` não está na lista de extensões de código e por isso o NotebookEdit fica fora, coerente com `EXTENSOES_CODIGO` em `hooks/aviso-fluxo.cjs`. Provado por leitura lado a lado registrada no relato, com a linha do código que sustenta cada frase.

## Emenda 3 — achado 4: o que é "aberto" no protheus (2026-10-08)

O usuário decidiu a Q1 pela opção A (D10). As duas cópias da regra das 24 h (`hooks/aviso-fluxo.cjs` e `hooks/portaria.cjs`) passam a chamar uma função só.

### 12. Protheus: fluxo aberto pelo campo `branch` do `.gates.json` [tipo: implementar]
atende: D1, D10
arquivos: `hooks/lib/caminho-leve.cjs`, `hooks/aviso-fluxo.cjs`, `hooks/portaria.cjs`, `hooks/testa-bloqueio-fluxo.cjs`, `hooks/testa-portaria-fluxo-pulado.cjs`, `CHANGELOG.md`
depende de: 10
paralela: nao
prova: `node hooks/testa-bloqueio-fluxo.cjs`
mutacao:
  arquivo: `hooks/lib/caminho-leve.cjs`
  de: `if (typeof dados.branch === 'string') return dados.branch === branch;`
  para: `if (false) return false;`
  bateria: `node hooks/testa-bloqueio-fluxo.cjs`
  fixture: caso "protheus: gates.json recente de outra branch nao abre o fluxo desta"
pronto quando: em repositório protheus (`docs/plans/x.gates.json`), com a sessão na branch `b1`: (a) `.gates.json` com `"branch": "b2"` e mtime de agora → Edit de `.prw` sai 2 e despacho de `executor` sai 2; (b) `"branch": "b1"` com mtime de 3 dias atrás → Edit sai 0 e despacho sai 0; (c) sem campo `branch`, mtime de agora → sai 0; (d) sem campo `branch`, mtime de 3 dias → sai 2; (e) `.gates.json` ilegível não derruba o hook (é ignorado). A decisão por arquivo mora numa função exportada de `hooks/lib/caminho-leve.cjs` usada pelos dois hooks, e a linha da mutação é escrita literalmente como no `de:`. Provado por `node hooks/testa-bloqueio-fluxo.cjs` e `node hooks/testa-portaria-fluxo-pulado.cjs` (`falhou: 0`, `skipped: 0`).
