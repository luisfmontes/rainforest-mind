# Plano: jornada e janela parada por relógio (mod, linha na faixa acima do prompt)

Design: docs/rainforest/design/2026-10-03-mod-jornada-relogio.md

Base: `d2dba6cd202e1035cac2b4dd1e380130a9a297f9` (branch `fluxo/mod-jornada-relogio`), versão publicada 1.38.1. Destino: 1.39.0 (MINOR). Claude Code medido: 2.1.289 (tipos de referência do 2.1.288).

## Achados que ajustam o briefing

Medidos pelo planejador em 2026-10-03 na base `d2dba6cd`; spikes em plugin descartável em `$TEMP`, já apagado.

1. **`scripts/jornada.cjs` custa 14–18 s, não ~3 s (contradizia a D8; design emendado).** `--json` mediu 16,3/18,3/18,3 s hoje e 14,2 s com `--dia 2026-10-02`: lê os 3.944 transcripts de `~/.claude-personal` e `~/.claude` (1.134 MB), dos quais só 272 (59 MB) foram tocados hoje. Transcript com `mtime` anterior à meia-noite local não pode ter mensagem de hoje. A tarefa 1 corta pela `mtime` sem mudar a saída; `timeoutMs` do mod é 60 000.
2. **`--json` já existe** (`scripts/jornada.cjs:226`): `{"escopo","mensagens","efetiva_min","bruto_min","primeiro","ultimo","corte_min","descartadas"}`; sem mensagem humana no dia sai exit 2 com `{"escopo","mensagens":0,"erro":...}`. `new Date(ultimo)` lê o ISO com offset. Nenhuma tarefa muda a interface.
3. **`sessoes.json`: chave por sessão, campos `cwd`, `prompt_ts`, `stop_ts` (ms).** A chave é o nome do transcript, e `$.session.id()` devolve "the transcript file's name": a própria janela se exclui por `$.session.id()`. `hooks/heartbeat.cjs:45-78` grava `prompt_ts` no `UserPromptSubmit`, `stop_ts` no `Stop`, apaga no `SessionEnd`, poda só com 24 h, `writeFileSync` sem trava.
4. **A poda de 24 h deixa janela fantasma** (worktrees `agent-*` paradas há 1.346 min; a lib já as exclui por `ehWorktreeDeAgente`). A abertura usa janela de 6 h (`hooks/foco-session-start.cjs:264`, `sessoesVivas(state, agora, 6 * 3600 * 1000)`) — decisão C.
5. **Reuso:** `hooks/lib/contexto-sessao.cjs` exporta `sessoesVivas`, `ehWorktreeDeAgente`, `ociosidadeDoFoco` (linha 1436); default 45 min em `hooks/foco-session-start.cjs:278`; `hooks/lib/raiz.cjs` resolve a raiz, a mesma do heartbeat e do `faixa-dados.cjs`.
6. **`$.clock` funciona em `claude plugin test` por `mock.clock(on, { now })`** (`{ advance, set, settle, sleep, now }`): `after` disparou no `advance`, `every(60000)` a cada 60 s, `cancel()` no `session.end` parou os ticks, guarda `emCurso` impediu empilhar (`maxVoo` = 1), `$` capturado em closure do `session.start` valeu no callback. Não existe evento de tick.
7. **A nota da D5 vai por `classic.UserPromptSubmit` com `additionalContext`.** `prompt.context` dispara uma vez por conversa; `prompt.attachment` é do engine; `prompt.section` gasta cache; `prompt.submit` reescreve o texto visível. Spike: `['NOTA-DE-JORNADA sessao-teste-123']` no prompt certo e `[]` no seguinte. `UserPromptSubmitHookInput.source` distingue `user` de `loop_wakeup`/`schedule_wakeup`/`system`/`sdk`: a nota só vale com `source` ausente ou `user`.
8. **`$.ui.invalidate` é síncrono**; escrita de `$.state` lida no desenho redesenha sozinha.
9. **`claude plugin validate` recusa chave de estado fora do contrato (exit 1).** Os átomos novos entram em `types/index.d.ts` no mesmo passo.
10. **O mod roda em `claude -p` e subagente:** timers só nascem com `e.isInteractive` (`SessionStartInput.isInteractive` falso em `-p`/SDK).
11. **`hooks/testa-mod-faixa.cjs:245-247` ("MAX_LINHAS vale 3") muda para 4** (D7). `⏰` (U+23F0) já conta 2 células em `largura`.
12. **A regra 17 chega inteira com o mod; a 8 não** (`hooks/abertura-mod.json` `"elaboracoes": [16, 12, 11, 17]`). A nota da D5 leva a regra 8 ao modelo na hora que importa (decisão D).
13. **Madrugada:** `jornada.cjs` conta o dia civil; "depois das 19h" não cobria 0h–5h (decisão B; design D3 emendado).
14. **`FORCE_COLOR=3` no ambiente de agente quebra baterias que interpolam `node -e`** (`testa-jornada.sh`: 13 ok/2 falhas com, 15 ok sem). Baterias novas apagam `FORCE_COLOR` dos filhos; provas que interpolam saída de `node` rodam com `env -u FORCE_COLOR`.
15. **Base verde:** `node hooks/testa-mod-abertura.cjs` 28 ok; `node hooks/testa-mod-faixa.cjs` 22 ok; `claude plugin test .` 4 pass; `bash scripts/testa-faixa-dados.sh` 14 ok; `bash scripts/testa-versao.sh` ok 5; `conferir-categoria` e `contrato-plugin-codex` passam.
16. **`conferir-fluxo.cjs cobertura` e `conferir-prova.cjs plano` aceitam `--plano <arquivo>`;** o texto passou nos dois.

## Decisões do usuário

Respondidas em 2026-10-04, todas na recomendada:
- **A. Prioridade quando falta espaço: Q > relógio > fluxo > foco.**
- **B. Madrugada incluída:** `hora >= 19 || hora < 5`, com mensagem do usuário nos últimos 30 min (`HORA_FIM_MADRUGADA = 5`).
- **C. Teto de idade da janela parada: 6 h** (`JANELA_VIVA_MS`), o mesmo do radar da abertura.
- **D. A regra 8 não entra em `elaboracoes`;** a nota da D5 a leva ao modelo.
- **E. Medição em cópia descartável do plugin em `$TEMP`** com limiares baixados à mão só na cópia; nenhuma variável de ambiente de teste no código de produção.

## O que não pode quebrar

- **A abertura do mod fica idêntica:** `hooks/register.ts`, `hooks/abertura-mod-puro.mjs`, `hooks/testa-mod-abertura.cjs`, `hooks/mod-abertura.test.ts` sem mudança (`git diff --quiet d2dba6cd -- <os quatro>`); `node hooks/testa-mod-abertura.cjs` 28 ok.
- **A faixa atual intacta no que já faz:** `node hooks/testa-mod-faixa.cjs` 22 ok (só "MAX_LINHAS vale 3" vira 4); `claude plugin test .` mantém os 4 casos; sem relógio aceso, `montarLinhas` e `assinatura` devolvem o que devolviam.
- **`hooks/hooks.json` e `.claude-plugin/plugin.json` não mudam antes da tarefa 8** (base: `MSYS_NO_PATHCONV=1 git cat-file -p d2dba6cd:hooks/hooks.json`, conferir saída não vazia).
- **Falha de leitura apaga só a linha do relógio:** exit ≠ 0, JSON inválido, timeout ou exceção → `null` no átomo; tudo em `try/catch`; exceção no `ui.render` → `next(e)`. `jornada.cjs` exit 2 = "sem linha".
- **Statusline intocada** (`statusline/` fora do diff). O relógio não escreve em `~/.rainforest`.
- **Codex só muda de versão;** `node scripts/contrato-plugin-codex.cjs` passa.
- **A saída humana e o `--json` do `jornada.cjs` não mudam;** `env -u FORCE_COLOR bash scripts/testa-jornada.sh` 15 ok.
- **`varrer-baterias` não depende do binário `claude`:** lógica em `.mjs`/`.cjs` testada em Node; provas de engine em `*.test.tsx`.
- **Ambiente do usuário não muda;** `tsconfig.json`/`.claude-plugin/types/` nunca no commit; `git status --short` ao fim de cada tarefa que roda `claude`.
- **`node scripts/conferir-categoria.cjs` exit 0;** arquivo novo leva `@categoria` (`bateria` nas baterias, `guia` nos scripts de dados).
- **`claude plugin validate .claude-plugin/plugin.json` sai 0** depois de cada tarefa que toca `hooks/*.mjs|ts|tsx` ou `types/`.

## Contrato dos dados

**`node scripts/relogio-sessoes.cjs --cwd <dir> --sessao <id>`** (tarefa 2) → JSON em uma linha, exit 0:
`{"ociosidade_min": 45, "janelas": [{"cwd": "<caminho>", "desde": <ms>}]}`
- `janelas` = esperando o usuário: `!(prompt_ts > stop_ts)`, `desde = stop_ts || prompt_ts` (como `foco-session-start.cjs:270`); só vivas por `JANELA_VIVA_MS` (6 h) via `sessoesVivas`; sem `agent-*`; sem a chave `--sessao`; mais antiga primeiro.
- `ociosidade_min` = `ociosidadeDoFoco(FOCO.md da raiz)` ou 45; raiz por `resolverRaiz({ cwd, plugin })`.
- Exit 2 sem `--sessao`; exit 1 sem raiz ou com `sessoes.json` ausente/ilegível.

**`node scripts/jornada.cjs --json`** (existente): o mod lê `efetiva_min` e `ultimo`; exit ≠ 0 → `null`.

**Átomos novos** (`$.state`, plugin `rainforest-mind`, contrato em `types/index.d.ts`): `relogioJornada` (`{ efetiva_min, ultimo_ms } | null`), `relogioSessoes` (`{ ociosidade_min, janelas: { cwd, desde }[] } | null`), `relogioNotaPendente` (`string | null`, dia `AAAA-MM-DD`), `relogioNotaEntregue` (`string | null`). `faixaOculta` segue a única assinatura de "esconder".

**`hooks/relogio-puro.mjs`** (sem Node, sem `$`): constantes `LIMITE_EFETIVA_MIN = 540`, `HORA_NOITE = 19`, `HORA_FIM_MADRUGADA = 5`, `JANELA_MSG_MIN = 30`, `OCIOSIDADE_PADRAO_MIN = 45`; `hhmm(min)` (forma do `jornada.cjs`: `9h12`, `45 min`), `diaLocal(ms)`, `horaLocal(ms)` (`20h41`), `avaliarRelogio({ jornada, sessoes, agora })` → `{ jornada: { efetiva_min, hora, dia } | null, parada: { cwd, pasta, min, outras } | null }`, `linhaRelogio(r)`, `assinaturaRelogio(r)`, `notaJornada(r)`.

**Linha (D7):** `⏰ jornada 9h12 · 20h40 | <pasta> parada há 32 min` (` (+k)` com mais k janelas acima do limite); só jornada `⏰ jornada 9h12 · 20h40`; só parada `⏰ <pasta> parada há 32 min`; 60 min ou mais vira `2h48`; `<pasta>` = último segmento do `cwd`.
- **Jornada acende:** `efetiva_min > 540` **ou** (`hora >= 19 || hora < 5`) com `agora - ultimo_ms <= 30 min`.
- **Parada acende:** janela com `(agora - desde) / 60000 > ociosidade_min`; nomeada a mais antiga.

**Assinatura do relógio (D6):** `j:<dia>` e `p:<cwd da mais parada>:<quantas acima do limite>`, nunca os minutos; `assinatura(dados, qs, assinaturaRelogio)` acrescenta o trecho só quando existe.

**Nota (D5):** `classic.UserPromptSubmit` → `additionalContext`, uma vez por dia, só com `source` ausente ou `user`, independente de "esconder". Texto:

> Relógio do mod (regra 8): a jornada efetiva de hoje é 9h12 e são 20h40. Avalie o aviso da regra 8 neste turno: se o usuário está produzindo ativamente, avise uma única vez (a hora, um ponto de parada concreto, a checagem de corpo); se está delegando em projeto de descanso, não avise. Esta nota não se repete hoje.

**Relógio (D8):** no `session.start` com `e.isInteractive`: `$.session.id()` e `$.session.cwd()`; `$.clock.after(1000, lerSessoes)` e `$.clock.after(2000, lerJornada)`; `$.clock.every(60000, lerSessoes)` (`node scripts/relogio-sessoes.cjs --cwd <cwd> --sessao <id>`, `timeoutMs` 5000); `$.clock.every(300000, lerJornada)` (`node scripts/jornada.cjs --json`, `timeoutMs` 60000); guarda `emCurso` por leitora; grava átomo, decide a nota, `$.ui.invalidate('ui.render')`; `session.end` e novo `session.start` cancelam; `ui.render` lê `$.clock.now()` para os minutos.

## Ordem e paradas

Cadeia: 1 ∥ 2 → 3 → 4 → 5 → 6 → 7 → 8. Tarefas 1 e 2 em arquivos disjuntos (`paralela: sim`); as demais `paralela: nao`.
- **Emenda pós-medição (2026-10-04):** a tarefa 9 entra entre a 5 e a 6 (a nota não chegava ao modelo pelo `classic.UserPromptSubmit` no REPL).
- **PARADA 1, depois da tarefa 9:** a tarefa 6 pede ao usuário a tela de um REPL real (`claude -p` não desenha nem tica). Falhou, volta ao usuário.
- **Pendente pós-merge:** repetir a leitura da tarefa 6 numa sessão pelo marketplace, com os limites reais.

## Tarefas

### 1. `jornada.cjs` lê só transcript tocado no dia [tipo: implementar]
atende: D8, D9
arquivos: `scripts/jornada.cjs`, `scripts/testa-jornada-filtro.cjs`
depende de: nenhuma
paralela: sim
prova: `node scripts/testa-jornada-filtro.cjs`
mutacao:
  arquivo: `scripts/jornada.cjs`
  de: `if (st.mtimeMs < desde) continue;`
  para: `if (false) continue;`
  bateria: `node scripts/testa-jornada-filtro.cjs`
  fixture: `testa-jornada-filtro.cjs, caso "transcript mais velho que o dia nao e lido"`
pronto quando: com os transcripts reais deste PC, `node scripts/jornada.cjs --json --dia 2026-10-02` devolve stdout byte a byte igual ao do `scripts/jornada.cjs` da base (`git show d2dba6cd:scripts/jornada.cjs` gravado em arquivo temporário e rodado igual), o mesmo para a saída humana (sem `--json`), e o novo leva no máximo 5 s onde a base leva 14–18 s — provado por um `node -e` com `execFileSync` que roda os quatro comandos, compara os stdout e mede `Date.now()`, saindo 1 se algum par diferir ou o novo passar de 5 s; e `env -u FORCE_COLOR bash scripts/testa-jornada.sh` segue `15 ok, 0 falha(s)`.

Nota: `transcriptsDisponiveis(desdeMs = 0)` mantém export e assinatura compatível; filtro `fs.statSync(arquivo).mtimeMs < desde`, com `desde` = meia-noite local do `--dia` (`new Date(ano, mes - 1, dia).getTime()`); `--dia` fora de `AAAA-MM-DD` não filtra. O `de:` é texto que a tarefa escreve, uma vez só. `--transcript` não muda. A bateria monta `USERPROFILE` numa caixa com dois transcripts de formato real (o de `testa-jornada.sh`): A com `mtime` de agora e duas mensagens de hoje; B com `mtime` de 3 dias atrás (`fs.utimesSync`) e duas mensagens carimbadas hoje — B é sintético de propósito: só ele separa "filtrou" de "leu tudo"; o caso do `de:` espera `"mensagens":2`. Controle contra filtro demais: B lido com `--dia` de 3 dias atrás conta as suas; arquivo com `mtime` de agora e mensagens antigas segue contando em `--dia` antigo. Apaga `FORCE_COLOR` dos filhos; zero `skipped`.

### 2. Script de dados do relógio: janelas esperando e ociosidade [tipo: implementar]
atende: D4, D8, D9
arquivos: `scripts/relogio-sessoes.cjs`, `scripts/testa-relogio-sessoes.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-relogio-sessoes.sh`
mutacao:
  arquivo: `scripts/relogio-sessoes.cjs`
  de: `.filter(([id]) => id !== eu)`
  para: `.filter(() => true)`
  bateria: `bash scripts/testa-relogio-sessoes.sh`
  fixture: `testa-relogio-sessoes.sh, caso "a propria janela nao entra"`
pronto quando: com o `sessoes.json` real em `~/.rainforest`, `node scripts/relogio-sessoes.cjs --cwd C:/Projetos/rainforest-mind --sessao da2628ca-c4c2-4c85-9335-967778ffae56` sai 0 com JSON cujas `janelas` (a) não contêm cwd de `.claude/worktrees/agent-*`, (b) têm `desde` entre agora menos 6 h e agora, (c) correspondem cada uma a uma entrada real com `prompt_ts` que não passa de `stop_ts`, (d) não contêm a chave do `--sessao`, e `ociosidade_min` é o número do `FOCO.md` da raiz real ou 45 — provado por um `node -e` que lê `sessoes.json` por conta própria, roda o script por `execFileSync` e sai 1 se alguma condição falhar; a bateria (raiz temporária por `RFM_ROOT`, `sessoes.json` no formato real) cobre própria janela fora, `agent-*` fora, janela trabalhando fora, parada há mais de 6 h fora, `Ociosidade máxima: 20 min` → 20 e sem a linha → 45, ordem do mais antigo, JSON quebrado → exit 1, `--sessao` ausente → exit 2.

Nota: o `de:` é texto que a tarefa escreve, uma vez só, sobre o resultado de `sessoesVivas` (reuso, nunca cópia); `eu` = valor de `--sessao`. Reusa `sessoesVivas`, `ehWorktreeDeAgente`, `ociosidadeDoFoco` e `resolverRaiz`. Somente leitura, sem `gh`; `// @categoria: guia`. A bateria nunca lê o `~/.rainforest` vivo (HOME, USERPROFILE, RFM_ROOT em caixas); só o `pronto quando` lê o real, para conferir.

### 3. Lógica pura do relógio: limiares, linha, assinatura e nota [tipo: implementar]
atende: D2, D3, D4, D5, D6, D7
arquivos: `hooks/relogio-puro.mjs`, `hooks/testa-mod-relogio.cjs`
depende de: 2
paralela: nao
prova: `node hooks/testa-mod-relogio.cjs`
mutacao:
  arquivo: `hooks/relogio-puro.mjs`
  de: `agora - ultimo_ms <= JANELA_MSG_MIN * 60000`
  para: `agora - ultimo_ms > JANELA_MSG_MIN * 60000`
  bateria: `node hooks/testa-mod-relogio.cjs`
  fixture: `testa-mod-relogio.cjs, caso "depois das 19h sem mensagem nos ultimos 30 min nao acende"`
pronto quando: com a saída real de `scripts/relogio-sessoes.cjs` (tarefa 2) sobre raiz temporária e a de `node scripts/jornada.cjs --json --transcript <arquivo sintético de formato real>`, `avaliarRelogio` + `linhaRelogio` devolvem `⏰ jornada 9h12 · 20h40` para 552 min às 20h40 com mensagem às 20h30; `⏰ jornada 9h12 · 20h40 | mod-faixa-foco parada há 32 min` com uma janela parada há 32 min e `Ociosidade máxima: 30 min`; ` parada há 2h48 (+1)` com duas acima do limite, a mais antiga nomeada; `null` com 8h59 às 14h; `null` às 20h com 8h00 e última mensagem há 31 min; acesa às 3h com mensagem há 5 min (decisão B); `null` com a janela exatamente no limite; `assinaturaRelogio` igual com 32 e 33 min, muda quando outra pasta vira a mais parada e quando uma nova cruza o limite, e `j:<dia>` muda no dia seguinte; `notaJornada` cita `9h12`, `20h40` e a regra 8 — provado por `node hooks/testa-mod-relogio.cjs`, que importa o `.mjs`, roda os dois scripts reais e confere `hhmm` contra o `hhmm` exportado por `scripts/jornada.cjs` para 0, 59, 60, 61, 552 e 1439 min.

Nota: o `de:` é texto que a tarefa escreve, uma vez só, na condição da noite. Superfície humana: jornada, hora, pasta e minutos — a bateria falha se algum sumir; a linha não traz ponto de parada nem checagem de corpo (D2). Sem `$`, sem Node, sem `Date.now()` (`agora` por argumento). Instantes por `new Date(ano, mes, dia, h, m).getTime()`; apaga `FORCE_COLOR` dos filhos; `// @categoria: bateria`.

### 4. A linha do relógio entra na faixa: 4 linhas, prioridade e assinatura [tipo: implementar]
atende: D1, D6, D7
arquivos: `hooks/faixa-puro.mjs`, `hooks/testa-mod-faixa-relogio.cjs`, `hooks/testa-mod-faixa.cjs`
depende de: 3
paralela: nao
prova: `node hooks/testa-mod-faixa-relogio.cjs`
mutacao:
  arquivo: `hooks/faixa-puro.mjs`
  de: `['q', q], ['relogio', relogio], ['fluxo', fluxo], ['foco', foco]`
  para: `['q', q], ['fluxo', fluxo], ['foco', foco], ['relogio', relogio]`
  bateria: `node hooks/testa-mod-faixa-relogio.cjs`
  fixture: `testa-mod-faixa-relogio.cjs, caso "com 2 linhas disponiveis ficam a Q e o relogio"`
pronto quando: com a linha real de `linhaRelogio` (tarefa 3) e os dados reais de `scripts/faixa-dados.cjs`, `montarLinhas(dados, qs, 80, 4, linhaRelogio)` devolve 4 linhas na ordem foco, fluxo, relógio, Q, nenhuma acima de 80 células; com `maxLinhas` 2 só relógio e Q; com 1 só a Q; com relógio e sem fluxo nem Q, foco e relógio (o relógio acende a faixa); sem relógio, exatamente o da base (`["foco  F", "fluxo s: plano", "Q 1 aberta(s): Q1 T"]`); `assinatura(dados, qs)` sem terceiro argumento igual à da base, e com `assinaturaRelogio` muda com `j:<outro dia>`; `MAX_LINHAS` vale 4 — provado por `node hooks/testa-mod-faixa-relogio.cjs`; e `node hooks/testa-mod-faixa.cjs` segue `22 ok, 0 falha(s), 0 skipped` com o único caso editado ("MAX_LINHAS vale 3" → 4).

Nota: o `de:` é texto que a tarefa escreve, uma vez só, no array `prioridade` (decisão A). `montarLinhas(dados, qs, cols, maxLinhas, relogio)` recebe a linha pronta (`string | null`); exibição foco, fluxo, relógio, Q (a Q rente ao prompt); `semControle` e `cortar` valem para a linha nova (o `cwd` vem de arquivo). Mudam só a constante, o `if (!q && !fluxo && !relogio)`, o array, a ordem e os comentários de "3 linhas". `// @categoria: bateria` na bateria nova.

### 5. Fiação do relógio no mod e prova de engine com relógio simulado [tipo: implementar]
atende: D1, D2, D3, D4, D5, D6, D7, D8, D9
arquivos: `hooks/mod.tsx`, `types/index.d.ts`, `hooks/mod-relogio.test.tsx`, `hooks/testa-mod-relogio.cjs`
depende de: 4
paralela: nao
prova: `claude plugin test . 2>&1 | grep -q mod-relogio.test.tsx`
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `await update($, relogioNotaPendente, () => null)`
  para: `await update($, relogioNotaPendente, () => dia)`
  bateria: `claude plugin test .`
  fixture: `mod-relogio.test.tsx, caso "relogio (<surface>): linha, minutos, esconder, nota e virada do dia" (a nota chega no `context` do primeiro prompt e não no segundo)`
pronto quando: com a saída real de `scripts/relogio-sessoes.cjs` e de `jornada.cjs --json` (coladas como `FIXTURE_SESSOES` e `FIXTURE_JORNADA`, servidas por `on('process.run')` conforme o `argv`), `$.session.id()` respondido por `on('session.id')` e `mock.clock(on, { now })` às 20h40 de um dia local, `claude plugin test .` sai 0 com `(pass)` e 0 fail, um `test(...)` por surface (`terminal` e `desktop`), mais os 4 casos existentes; `claude plugin validate .claude-plugin/plugin.json` sai 0 e lista `$.clock.after`, `$.clock.every`, `$.session.id`, `$.ui.invalidate` e `declares state:` com `relogioJornada`, `relogioSessoes`, `relogioNotaPendente`, `relogioNotaEntregue`; `node hooks/testa-mod-abertura.cjs` 28 ok e `node hooks/testa-mod-faixa.cjs` 22 ok; `git diff --quiet d2dba6cd -- hooks/register.ts hooks/abertura-mod-puro.mjs hooks/testa-mod-abertura.cjs hooks/mod-abertura.test.ts hooks/hooks.json statusline` sai 0 — provado por esses comandos.

Casos por surface: (1) quieta antes de qualquer tick; (2) depois de `session.start` + `advance(2000)`, com 552 min e mensagem às 20h30, `find` acha `jornada 9h12` e `20h40`; (3) com `ociosidade_min` 30 e uma janela parada há 32 min, a linha traz a pasta e `parada há 32 min`; com duas acima, `(+1)`; (4) `advance(60000)` muda `32 min` → `33 min` e a assinatura não muda; (5) 8h59 às 14h, e 8h00 às 20h com mensagem há 31 min, deixam quieta; (6) `esconder` deixa quieta, `advance(300000)` com a mesma jornada mantém escondida, outra janela virando a mais parada ou uma nova cruzando traz de volta, a virada do dia traz a jornada de volta; (7) o primeiro `$.classic.UserPromptSubmit({ prompt, source: 'user' })` depois do aceso devolve `additionalContext` com `regra 8`, `9h12` e `20h40`, o segundo do mesmo dia sem, `source: 'loop_wakeup'` não gasta, esconder não impede, o dia seguinte entrega outra; (8) `process.run` exit 1 apaga só a linha, e `jornada.cjs` exit 2 também, sem exceção; (9) `session.start` com `isInteractive: false` não dispara nenhum `process.run` do relógio; (10) `session.end` cancela: `advance(600000)` depois não chama `process.run`; (11) o `argv` da leitura de janelas leva `--sessao` com o id de `$.session.id()`; (12) leitura de jornada lenta (`relogio.sleep`) não é reentrada por um tick de 5 min; (13) com `bodyColumns` 30 cada `Text` cabe em 30 células; com `maxRows` 3 sobram Q e relógio; (14) o texto do relógio nunca traz `ponto de parada` nem `água`.

Nota: o engine recusa `$` passado como argumento: a leitura é `rodarJson(io, argv, timeoutMs)` com `io = { rodar }` montado no ponto de chamada (molde de `buscar(io)`); `lerSessoes`, `lerJornada`, o cancelamento e `reavaliar` são closures dentro do `register`. `ui.render` lê `await $.clock.now()`; se falhar no teste, guarda-se o `agora` do último tick num átomo. `types/index.d.ts` ganha os quatro átomos e `RainforestMindRelogioJornada`/`RainforestMindRelogioSessoes`, só `type` exportado. O `de:` é texto que a tarefa escreve, uma vez só, no hook `classic.UserPromptSubmit` (que hoje só zera as Q): lê `relogioNotaPendente` e, ao entregar, grava `relogioNotaEntregue` com o dia, zera o pendente (esse `update`) e devolve `{ ...r, additionalContext: [...] }` do `next(e)`; o tick só arma o pendente quando o dia ainda não foi entregue. Mutações extras para a revisão: `if (!e.isInteractive) return next(e)` → `if (false) return next(e)` (caso 9) e remover o `cancel()` do `session.end` (caso 10). `hooks/testa-mod-relogio.cjs` ganha o caso que lê `mod-relogio.test.tsx` como texto e confere que as chaves de `FIXTURE_SESSOES` e `FIXTURE_JORNADA` são as da saída real dos dois scripts (nunca pula). Nenhuma edição em `hooks/hooks.json` nem em `plugin.json`.

### 9. Nota e limpeza das Q por `prompt.submit` (emenda pós-medição) [tipo: implementar]
atende: D5, D6
arquivos: `hooks/mod.tsx`, `hooks/mod-relogio.test.tsx`, `hooks/mod-faixa.test.tsx`
depende de: 5
paralela: nao
prova: `grep -c "on('prompt.submit'" hooks/mod.tsx | grep -qx 1`
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `return next({ ...e, context: [...(e.context ?? []), nota] })`
  para: `return next(e)`
  bateria: `claude plugin test .`
  fixture: `mod-relogio.test.tsx, caso "relogio (<surface>): linha, minutos, esconder, nota e virada do dia" (a nota chega no `context` do primeiro prompt e não no segundo)`
pronto quando: `hooks/mod.tsx` deixa de registrar `classic.UserPromptSubmit` e registra `prompt.submit` uma vez: limpa `faixaQ` em todo envio e, com `e.origin` ausente ou `e.origin.kind === 'composer'`, entrega a nota pendente do dia como `context` (`next({ ...e, context: [...(e.context ?? []), nota] })`, nunca depois do `next`), gravando `relogioNotaEntregue` e zerando o pendente; os testes de engine passam a chamar `$.prompt.submit` (fundo `on('prompt.submit')`) e o caso da nota confere o `context` que chega ao fundo; `claude plugin test .` sai 0 com 0 fail, `claude plugin validate .claude-plugin/plugin.json` sai 0 e lista `prompt.submit` sem `classic.UserPromptSubmit` no `mod.tsx`, e as baterias Node (`testa-mod-abertura` 28 ok, `testa-mod-faixa` 22 ok, `testa-mod-faixa-relogio`, `testa-mod-relogio`) seguem verdes — provado por esses comandos.

Nota: medido na tarefa 6 (REPL real, 2.1.289, cópia por `--plugin-dir`): o handler de mod para `classic.UserPromptSubmit` **não roda** no envio do composer interativo — um diagnóstico que escrevia na linha de Q da faixa não apareceu durante nem depois do turno —, enquanto o mesmo handler roda em `claude -p`. A linha do relógio desenhou, então era a cópia que estava carregada. Pesquisa: `prompt.submit` aceita `context?: readonly string[]` ("what the model reads beside the prompt and the user never sees"); em `-p`, um `context` com palavra secreta fez o modelo respondê-la, com o texto visível intacto. A limpeza das Q da 1.38.1 usava o mesmo evento e cai junto: o conserto vale para as duas. O `de:` é texto que a tarefa escreve, uma vez só.

### 6. Medição no REPL real: a linha, a nota, o esconder e a janela nomeada [tipo: pesquisar]
atende: D1, D2, D3, D4, D5, D6, D8
arquivos: nenhum
depende de: 1, 5, 9
paralela: nao
mutacao: n/a
  motivo: tarefa de medição em sessão interativa real; o controle é a faixa sem relógio quando nenhum limite foi cruzado e o relato do que apareceu na tela, mais as provas com limiares reais da tarefa 5.
pronto quando: com REPLs interativos abertos por `claude --plugin-dir <cópia descartável do plugin>` (decisão E), o usuário cola o texto da faixa com `⏰ jornada <h>h<mm> · <hora>` e `<pasta da janela parada> parada há <n> min`; a resposta do modelo citando a nota literal no primeiro prompt depois do aceso e "nenhuma" no segundo; o desaparecimento ao apertar `esconder` e a permanência escondida depois de um tick de 5 min; o retorno da faixa com `(+1)` quando uma segunda janela cruza o limite; a tela sem linha de relógio numa janela sem outra janela parada; e `time node scripts/jornada.cjs --json` ≤ 5 s, `time node scripts/relogio-sessoes.cjs --cwd . --sessao x` ≤ 1,5 s, `git status --short` sem `tsconfig.json` nem `.claude-plugin/types/` — provado pelas saídas coladas na evidência e no PR.

Nota: PARADA 1 (bola com o usuário). Procedimento que a janela principal prepara: (1) fora do repo, `$TEMP/rfm-medicao-relogio` com `raiz/FOCO.md` (`# Foco`, `## Ativo`, `**Medicao do relogio** [trabalho]`, `Ociosidade máxima: 1 min.`), pastas `janela-a`, `janela-b`, `janela-c`, e o plugin por `git archive HEAD | tar -x -C <M>/plugin`, editando **só na cópia** `LIMITE_EFETIVA_MIN = 1` e `HORA_NOITE = 0`; (2) janela A em `janela-a` com `RFM_ROOT=<M>/raiz`, um "oi" e parar; (3) janela B em `janela-b`: primeiro prompt "Cite literalmente qualquer nota do relógio do mod (regra 8) que chegou com esta mensagem; se nenhuma, diga nenhuma.", depois de ≥ 2 min colar a faixa (esperado `⏰ jornada ... | janela-a parada há 2 min`), segundo prompt igual (esperado: nenhuma); (4) `esconder`, `date`, esperar > 5 min, colar com `date`; (5) janela C (um prompt e parar); em ≥ 2 min a faixa de B volta com `(+1)`; (6) controle: B reiniciada sem A e C; (7) `cat <M>/raiz/sessoes.json`, encerrar as janelas, `rm -rf <M>`, `git status --short`. Colar também o atraso no `session.start`, se o `esconder` voltou antes de 5 min, e o que o REPL mostrou se `$.clock.every` não disparou. Nota que não chega ao modelo, ou `$` que deixa de valer no timer, devolve o fluxo ao `plano`. O `~/.rainforest` real não é tocado (`RFM_ROOT`).

### 7. Documentação do relógio [tipo: docs]
atende: D2, D3, D5, D7, D8
arquivos: `CONTRIBUTING.md`, `README.md`, `skills/rainforest-mind/references/regra-08.md`, `skills/rainforest-mind/references/regra-17.md`
depende de: 6
paralela: nao
mutacao: n/a
  motivo: tarefa de documentação, sem comportamento a inverter; a falsificação é a coerência com o design e com o código entregue.
pronto quando: a seção "A faixa do mod" do `CONTRIBUTING.md` diz que a faixa tem no máximo `MAX_LINHAS` linhas (foco, fluxo, relógio, Q); que a linha do relógio mostra jornada efetiva e hora quando as efetivas passam de `LIMITE_EFETIVA_MIN / 60` h, ou de noite (`HORA_NOITE` h a `HORA_FIM_MADRUGADA` h) com mensagem do usuário nos últimos `JANELA_MSG_MIN` min; que a janela parada mais antiga além da `Ociosidade máxima:` (`OCIOSIDADE_PADRAO_MIN` se ausente) é nomeada pela pasta; que o relógio lê `sessoes.json` a cada 1 min e `scripts/jornada.cjs` a cada 5 min por `$.clock.every`; que a nota de uma vez por dia vai no prompt seguinte por `classic.UserPromptSubmit` e a decisão de avisar continua do modelo; que "esconder" não volta com os minutos; que o relógio só nasce em sessão interativa; o `README.md` diz, junto do requisito da faixa, que o mesmo mod acende os avisos; `references/regra-17.md` e `references/regra-08.md` ganham uma frase cada dizendo que o relógio do mod acende o aviso — provado por um `node -e` que importa `hooks/relogio-puro.mjs` e `hooks/faixa-puro.mjs`, extrai do `CONTRIBUTING.md` os números e confere contra as constantes, confere eventos e `$.clock` de `hooks/mod.tsx`, e sai 1 se algo divergir; e `bash hooks/testa-contexto-sessao.sh`, `bash hooks/testa-abertura-mod-config.sh`, `bash scripts/testa-mapa-regras.sh` e `node hooks/testa-mod-abertura.cjs` seguem verdes.

Nota: números do texto vêm do código; nada que a tarefa 6 não tenha medido. Uma frase só em cada regra, na elaboração (a 17 chega com o mod, a 8 é consulta). O núcleo de `SKILL.md` não muda. Não toca o badge de versão.

### 8. Versão 1.39.0, CHANGELOG e fim de lote [tipo: configurar]
atende: D1
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 7
paralela: nao
mutacao: n/a
  motivo: tarefa de configuração de versão; quem prova o efeito é o sensor de versão e a medição em sessão instalada pelo marketplace, pendente pós-merge.
pronto quando: com a versão 1.39.0 em `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` e no badge do `README.md`, e a nota `## 1.39.0` no topo do `CHANGELOG.md` no commit `Versao 1.39.0: ...` (último do lote), `node scripts/conferir-versao.cjs --sem-fetch` sai 0, `node scripts/contrato-plugin-codex.cjs` sai 0 e o diff de `.codex-plugin/plugin.json` contra `d2dba6cd` é só a linha `version` — provado por esses três comandos.

Nota: o CHANGELOG diz, nesta ordem: a linha `⏰` (jornada e hora no limite, janela parada nomeada com `(+k)`); a faixa de até 4 linhas; o "esconder" que não volta com os minutos; a nota de uma vez por dia que leva a regra 8 ao modelo; o `jornada.cjs` que passou a ler só os transcripts do dia (14–18 s antes, e o medido na tarefa 6 depois); o requisito (2.1.287+, sem mod nada muda) e que vale na sessão seguinte à atualização.

## Cobertura

D1 → 4, 5, 6, 8. D2 → 3, 5, 6, 7. D3 → 3, 5, 6, 7. D4 → 2, 3, 5, 6. D5 → 3, 5, 6, 7, 9. D6 → 3, 4, 5, 6, 9. D7 → 3, 4, 5, 7. D8 → 1, 2, 5, 6, 7. D9 → 1, 2, 5.

## Lacunas conhecidas

- **`$` no callback de `$.clock.every` num REPL real:** provado só no engine de teste; a tarefa 6 mostra o timer vivo depois do `session.start`.
- **A nota chega ao modelo?** O contrato é do tipo e passou no teste; só a tarefa 6 lê o que o modelo recebeu.
- **`timeoutMs: 60000`** sem teto documentado; a tarefa 6 mede com o `jornada.cjs` já filtrado.
- **O env do `$.process.run` herda o do processo?** Inferido da 1.38.0; a medição com `RFM_ROOT` prova na tarefa 6.
- **Leitura de `sessoes.json` durante a escrita** (heartbeat sem trava): JSON cortado apaga a linha até o tick seguinte (1 min); aceito (D9).
- **"Esconder" e a condição que some e reaparece:** sem o trecho do relógio a assinatura muda e a faixa reaparece sem o aviso, como já ocorre com Q respondida; a tarefa 6 anota se incomoda.
- **Jornada depois da virada do dia:** às 0h a jornada recomeça; a linha de madrugada mostra a do dia novo (do `jornada.cjs`, que a regra 8 manda usar).
- **Janelas no mesmo `cwd`:** contam `(+1)` por janela, não por pasta.
- **Desktop:** a pintura real só a tarefa 6 vê, e só no terminal.
