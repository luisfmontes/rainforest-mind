# Plano: Agentes do rainforest em Codex ou Claude, por escolha do usuário

Design: docs/rainforest/design/2026-09-08-agentes-em-codex.md

## Fatos que precedem as tarefas

- `hooks/lib/config.cjs` só resolve valor **booleano**: `buscar()` filtra com
  `typeof cfg[nome] === 'boolean'`. As chaves `codex-modelo-*` da D4 guardam
  modelo e esforço, então a Tarefa 2 estende o tipo antes de a Tarefa 3 ler.
- `codex exec --json` emite como primeiro evento
  `{"type":"thread.started","thread_id":"<uuid>"}` (medido em 2026-09-08,
  codex-cli 0.151.0). Sessão aberta por `exec` é retomável por
  `codex resume <thread_id>`, então a `transfer` da D8 cabe no transporte da
  D2. A importação nativa de sessão do `codex-plugin-cc`
  (`importExternalAgentSession`, `codex.mjs:1058-1093`) só existe via
  `app-server`; este plano **não** a replica: transfere o texto das mensagens,
  não a sessão byte a byte.
- Payload do hook `Stop` traz `transcript_path` (uso real em
  `hooks/memoria-marca.cjs`); a última entrada do transcript tem o shape
  `{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"..."}]}}`.
- `hooks/portaria.cjs` está registrado só em `.claude/settings.json` deste
  repositório, não em `hooks/hooks.json`. Pré-existente; a Tarefa 1 tem
  efeito aqui e em quem registrar o hook, e este plano não muda isso.

## O que não pode quebrar

- Despacho de subagente Claude sem `Runtime:` no briefing continua idêntico:
  `runtime` ausente resolve para `"claude"` e a portaria decide pelos mesmos
  motivos. Prova: os casos existentes de `hooks/testa-portaria-nucleo.cjs`
  continuam verdes depois da Tarefa 1.
- Toda chave booleana de `hooks/lib/config.cjs` mantém valor e precedência
  depois da Tarefa 2. Prova: casos existentes de `hooks/testa-config.sh`.
- Nenhuma chamada real a `codex` fora da Tarefa 8, que roda com o usuário
  presente. Tarefas 1 a 7 usam dublê (`RFM_TEST=1` + `CODEX_CMD`, molde de
  `CONSELHO_CMD_CODEX` em `scripts/conselho.cjs`).
- `.rainforest/portaria/despachos.jsonl` continua fora do git.
- Scripts novos nascem neutros de host (D13): zero dependência nova e nenhum
  `CLAUDE_*` obrigatório; ausência é opcional, nunca erro fatal.
- Branches `codex/*` e worktrees `.claude/worktrees/codex-*` não são tocados.

## Tarefas

### 1. Portaria registra e valida `runtime` [tipo: implementar]
atende: D1
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-nucleo.cjs`, `.rainforest/agentes.json`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: a função nova `runtimeEfetivo(agentConfig, prompt)` — quando `prompt` contém uma linha `Runtime: codex` (case-insensitive, linha isolada), devolve `"codex"` mesmo com `agentConfig.runtime` ausente ou `"claude"`
  para: a função ignora o prompt e devolve sempre `agentConfig.runtime || "claude"`
  bateria: `node hooks/testa-portaria-nucleo.cjs`
  fixture: caso novo "override de runtime no bloco 1 do prompt vence o default do manifesto" — manifesto sem `runtime` para o agente, `tool_input.prompt` com a linha `Runtime: codex`
pronto quando: com um payload real do `Agent` tool (`tool_input = {subagent_type, prompt, isolation, name}`) cujo `prompt` traz `Runtime: codex` no bloco "Contexto", contra um manifesto onde o agente não declara `runtime`, a última linha de `.rainforest/portaria/despachos.jsonl` contém `"runtime":"codex"`; e com `runtime: "gemini"` no manifesto a portaria nega com motivo citando os valores aceitos — provado por `node hooks/testa-portaria-nucleo.cjs` (dois casos novos, rodando o hook por `spawnSync` e lendo o jsonl)

Convenção fixada aqui: a linha `Runtime: <claude|codex>` no bloco 1 do briefing é o override; `agentConfig.runtime`, quando presente, tem de ser exatamente `"claude"` ou `"codex"`, no mesmo espírito da checagem de forma de `escreve`. O `.rainforest/agentes.json` deste repositório ganha `"runtime": "claude"` explícito no `executor` e no `revisor` como exemplo documentado; os demais ficam sem o campo, provando o default.

### 2. `hooks/lib/config.cjs` ganha chave de valor não-booleano [tipo: implementar]
atende: D4, D8, D9
arquivos: `hooks/lib/config.cjs`, `hooks/testa-config.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/config.cjs`
  de: a checagem de forma de chave `tipo: 'modelo'` — aceita só quando `typeof cfg[nome] === 'object' && cfg[nome] !== null && typeof cfg[nome].modelo === 'string'`; falhando, cai para o próximo nível da cadeia (padrão `null` = não passar `-m` nem esforço)
  para: remove a checagem e aceita qualquer valor, inclusive string solta
  bateria: `bash hooks/testa-config.sh`
  fixture: caso novo "chave tipo 'modelo' mal formada no config do usuário cai no padrão nulo" — `.rainforest/config.json` com `{"codex-modelo-sonnet": "so-uma-string"}`
pronto quando: com `<projeto>/.rainforest/config.json` contendo `{"codex-modelo-sonnet": {"modelo": "gpt-5.6-sol", "esforco": "high"}}`, `resolverConfig().valores['codex-modelo-sonnet']` devolve esse objeto e `origem['codex-modelo-sonnet']` diz `"projeto"`; com o valor `"so-uma-string"`, devolve `null` — provado por `bash hooks/testa-config.sh` (casos novos)

Acrescenta no mesmo arquivo as chaves `codex-modelo-haiku`, `codex-modelo-sonnet`, `codex-modelo-opus` (`tipo: 'modelo'`, `padrao: null`) e as booleanas `transfer-codex` e `gate-review-codex` (`padrao: false`).

### 3. `scripts/despachar-codex.cjs` — transporte via `codex exec` [tipo: implementar]
atende: D2, D4, D5, D6, D13
arquivos: `scripts/despachar-codex.cjs`
depende de: 2
paralela: nao
mutacao:
  arquivo: `scripts/despachar-codex.cjs`
  de: `const sandbox = escreve ? "workspace-write" : "read-only";`, que decide `-s <sandbox>` a partir de `--escreve`
  para: `const sandbox = "read-only";` fixo
  bateria: `bash scripts/testa-despachar-codex.sh`
  fixture: caso "despacho com `--escreve true` monta `-s workspace-write` e `--add-dir <repo>/.git`" em `scripts/testa-despachar-codex.sh`
pronto quando: com `--agente revisor --worktree <dir> --escreve false --briefing-file <arquivo>`, o comando entregue a `rodarCli` contém `-s read-only`, `--skip-git-repo-check`, `-c approval_policy="never"`, `-C <dir>`, `-o <arquivo>` e não contém `--add-dir`; com `--escreve true` num worktree cujo `.git` é arquivo `gitdir: <repo>/.git/worktrees/<n>`, contém `-s workspace-write` e `--add-dir <repo>/.git`; nunca contém `--dangerously-bypass-approvals-and-sandbox` — provado por `bash scripts/testa-despachar-codex.sh` capturando o comando montado via `RFM_TEST=1`/`CODEX_CMD`

Contrato: lê `agents/<agente>.md`, separa frontmatter do corpo com a regex já usada em `hooks/portaria.cjs`, remove o preâmbulo de ponte (delimitado por marcador `<!-- ponte-codex -->` … `<!-- /ponte-codex -->`, Tarefa 5) para não recursar, extrai `model:` e mapeia para `codex-modelo-<model>` (Tarefa 2): `-m <modelo>` e `-c model_reasoning_effort="<esforco>"` só quando a chave tem valor. Corpo + briefing vão por stdin para `rodarCli` de `hooks/lib/cli-externo.cjs`. `--timeout-ms` default `540000` (D6); timeout ou exit ≠ 0 sai com exit ≠ 0 e o conteúdo parcial de `-o` quando houver. Imprime no stdout a última mensagem (arquivo `-o`) e no stderr uma linha `comando: <cmd>` para auditoria. `RFM_TEST=1` + `CODEX_CMD` substitui o comando inteiro.

### 4. `scripts/testa-despachar-codex.sh` — bateria com dublê [tipo: teste]
atende: D11
arquivos: `scripts/testa-despachar-codex.sh`, `scripts/fixtures/codex-duble.cjs`
depende de: 3
paralela: nao
mutacao:
  arquivo: `scripts/despachar-codex.cjs`
  de: a leitura de `process.env.RFM_TEST === '1' && process.env.CODEX_CMD`, que troca o comando `codex exec ...` pelo dublê
  para: ignora `CODEX_CMD` e monta sempre o `codex exec` real
  bateria: `bash scripts/testa-despachar-codex.sh`
  fixture: caso "dublê é chamado e a saída dele volta literal" — com a mutação, o teste não recebe a saída do dublê e falha
pronto quando: com `RFM_TEST=1` e `CODEX_CMD` apontando para o dublê Node, `node scripts/despachar-codex.cjs --agente revisor --worktree <dir-de-teste> --escreve false --briefing-file <arquivo>` sai 0 e devolve exatamente o texto do dublê, o stdin recebido pelo dublê contém o corpo de `agents/revisor.md` sem o preâmbulo de ponte seguido do briefing, e nenhum processo `codex` é criado; com o dublê saindo 1 o script sai ≠ 0; com dublê que dorme além de `--timeout-ms 1000` o script sai ≠ 0 e reporta timeout — provado por `bash scripts/testa-despachar-codex.sh`

### 5. Preâmbulo de ponte nos 9 `agents/*.md` [tipo: implementar]
atende: D3, D10
arquivos: `agents/arqueologo.md`, `agents/auditor-de-seguranca.md`, `agents/depurador.md`, `agents/documentador.md`, `agents/executor.md`, `agents/planejador.md`, `agents/resolvedor-de-build.md`, `agents/revisor.md`, `agents/tester.md`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: o preâmbulo é instrução no system prompt do agente, sem ramo de código a inverter; a falsificação é comportamental e só se observa com Codex real, na Tarefa 8.
pronto quando: nos 9 arquivos, o bloco entre `<!-- ponte-codex -->` e `<!-- /ponte-codex -->` cita exatamente as flags que `scripts/despachar-codex.cjs` aceita (`--agente`, `--worktree`, `--escreve`, `--briefing-file`, `--timeout-ms`), o valor de `--escreve` coerente com o `escreve` do agente em `.rainforest/agentes.json`, e instrui a fazer uma única chamada Bash e devolver a saída literal — provado por `grep -oE -- '--[a-z-]+' scripts/despachar-codex.cjs | sort -u` bater com o conjunto de flags citado em cada preâmbulo, sem flag a mais nem a menos, e por `grep -c 'ponte-codex' agents/*.md` devolver 2 em cada arquivo

### 6. `transferir-para-codex.cjs` — transfer opt-in por `codex exec` [tipo: implementar]
atende: D8
arquivos: `scripts/transferir-para-codex.cjs`, `scripts/testa-transferir-para-codex.sh`, `commands/transferir.md`, `hooks/codex-transfer-session-start.cjs`, `hooks/hooks.json`
depende de: 2, 3
paralela: nao
mutacao:
  arquivo: `scripts/transferir-para-codex.cjs`
  de: a checagem de que o caminho resolvido de `--source` (ou da variável gravada por `hooks/codex-transfer-session-start.cjs`) fica dentro de `~/.claude/projects` antes de ler o arquivo
  para: remove a checagem e lê qualquer caminho
  bateria: `bash scripts/testa-transferir-para-codex.sh`
  fixture: caso "transcript fora de `~/.claude/projects` é recusado com mensagem citando a pasta"
pronto quando: com um `.jsonl` fora de `~/.claude/projects`, o script sai ≠ 0 e a mensagem cita `.claude/projects`; com um transcript real (shape `type: "user"|"assistant"`, `message.content[].type === "text"`) e `CODEX_CMD` dublê que emite `{"type":"thread.started","thread_id":"abc-123"}` seguido do restante do JSONL, o stdin do dublê contém o texto das últimas mensagens e o stdout do script termina com a linha `codex resume abc-123` — provado por `bash scripts/testa-transferir-para-codex.sh`

Escopo: transfere o **texto** das mensagens (não a sessão byte a byte) como primeiro prompt de um `codex exec --json` novo, via `rodarCli`, e extrai `thread_id` do evento `thread.started`. `hooks/codex-transfer-session-start.cjs` só grava `transcript_path` em `CLAUDE_ENV_FILE` quando `transfer-codex` está ligado; desligado, não escreve nada. `commands/transferir.md` é fino: chama o script e devolve a saída.

### 7. `hooks/gate-review-codex.cjs` — review gate opt-in no `Stop` [tipo: implementar]
atende: D9
arquivos: `hooks/gate-review-codex.cjs`, `hooks/testa-gate-review-codex.sh`, `hooks/hooks.json`
depende de: 2, 3
paralela: nao
mutacao:
  arquivo: `hooks/gate-review-codex.cjs`
  de: quando o despacho do `revisor` via `scripts/despachar-codex.cjs` falha (exit ≠ 0, timeout, ou saída sem `ALLOW`/`BLOCK` reconhecível), o hook emite `{"decision":"block","reason":"..."}`
  para: em qualquer falha, sai silencioso com exit 0
  bateria: `bash hooks/testa-gate-review-codex.sh`
  fixture: caso "despacho falha (dublê sai 1) → decision block com motivo"
pronto quando: com `gate-review-codex` ligado, `stop_hook_active` ausente ou falso, e `transcript_path` apontando para um `.jsonl` cuja última entrada é `{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"..."}]}}`, contra dublê que devolve `BLOCK: motivo-x`, `echo '<payload-stop>' | node hooks/gate-review-codex.cjs` imprime `{"decision":"block","reason":"...motivo-x..."}`; com dublê `ALLOW: ok` não imprime decisão e sai 0; com a chave desligada não chama o despacho e sai 0; com `stop_hook_active: true` sai 0 sem chamar — provado por `bash hooks/testa-gate-review-codex.sh`

### 8. Validação real com Codex — `executor` e `revisor` [tipo: teste]
atende: D10
arquivos: `agents/executor.md`, `agents/revisor.md`, `scripts/despachar-codex.cjs`
depende de: 1, 3, 5
paralela: nao
mutacao: n/a
  motivo: validação fim a fim com binário externo real, fora do controle do repositório; não há linha de produção a inverter. Roda no `verificar`, com o usuário presente e a conta Codex fora do limite de uso.
pronto quando: com o Claude Code despachando pelo `Agent` o `executor` com `Runtime: codex` no bloco 1 (tarefa pequena e real: criar um arquivo num worktree isolado e commitar) e depois o `revisor` com `Runtime: codex` sobre esse diff, os dois devolvem a saída literal de um `codex exec` real (sem `RFM_TEST`) — provado colando no relatório: (a) `git log -1` do worktree com o commit feito pelo Codex; (b) o parecer devolvido pelo Codex; (c) a linha `comando: codex exec ...` do stderr do despacho, sem `CODEX_CMD` no ambiente; (d) as duas linhas de `despachos.jsonl` com `"runtime":"codex"`

### 9. Documentação e versão [tipo: docs]
atende: D1, D3, D7, D12, D13
arquivos: `README.md`, `docs/pontes.md`, `skills/rainforest-mind/references/regra-10-portaria.md`, `skills/executar/SKILL.md`, `skills/modo-dev/SKILL.md`, `.claude-plugin/plugin.json`
depende de: 1, 2, 3, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: documentação; a falsificação é coerência textual com o código e com o design, não presença de string.
pronto quando: `.claude-plugin/plugin.json` sobe MINOR (`1.7.0` → `1.8.0`) e o badge do `README.md` mostra o mesmo número — provado por `node scripts/conferir-versao.cjs` saindo 0 e `grep -o "vers%C3%A3o-[0-9.]*" README.md` batendo com `"version"`; a sintaxe `Runtime: <claude|codex>` descrita em `skills/modo-dev/SKILL.md` (bloco 1 do briefing) e em `skills/executar/SKILL.md` é a mesma que a regex de `hooks/portaria.cjs` reconhece — provado por extrair a regex do hook e casá-la contra o exemplo literal da skill; `regra-10-portaria.md` documenta o campo `runtime` e o override com os mesmos valores aceitos pelo código (`claude`, `codex`); `docs/pontes.md` distingue esta frente (Codex como runtime de subagente dentro do Claude) da frente do agente paralelo (Codex como host, D13) sem corrigir contagens pré-existentes (D12); `README.md` lista `/transferir` em "Do dia a dia" e registra que `review`, `adversarial-review` e `rescue` não ganharam comando porque já existem como função (D7)
