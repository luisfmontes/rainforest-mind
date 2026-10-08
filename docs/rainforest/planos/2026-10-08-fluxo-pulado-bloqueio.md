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
arquivos: `README.md`, `CHANGELOG.md`, `skills/rainforest-mind/SKILL.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `hooks/lib/config.cjs`
depende de: 2, 3
paralela: nao
mutacao: n/a
  motivo: só texto e número de versão; a falsificação é a coerência com o design e o `testa-versao.sh`.
pronto quando: com o design aprovado ao lado, o README deixa de listar o `aviso-fluxo` entre os hooks que "avisam sem barrar" e o descreve na tabela de travas com as duas saídas (abrir fluxo, `leve`) e a chave `aviso-fluxo` (a descrição da chave em `hooks/lib/config.cjs` deixa de dizer "avisa"); a linha da regra 10 no README e o núcleo em `skills/rainforest-mind/SKILL.md` deixam de dizer que estágio é só log e nomeiam a exceção do D5 (`escreve: true` fora do estágio dele, sem `leve`, é barrado); o CHANGELOG ganha a versão **1.49.0** dizendo o que muda para quem usa (bloqueio nos dois trilhos, `leve` por branch, despacho barrado, chave para desligar) e o que fica de fora (Bash, D2); `plugin.json` dos dois manifestos e o badge do README em 1.49.0 — provado por `bash scripts/testa-versao.sh` com `falhou: 0`, `bash hooks/testa-abertura-mod-foco.sh` com `falhou: 0` (o núcleo injetado mudou) e leitura lado a lado de cada D1–D9 contra o texto novo, registrada no relato do `executar` com a linha do doc que realiza cada uma.
