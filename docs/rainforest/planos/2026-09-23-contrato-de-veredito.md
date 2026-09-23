# Plano: Contrato de veredito de uma linha no revisar

Design: `docs/rainforest/design/2026-09-23-contrato-de-veredito.md` (9 decisões, `aprovado` em 2026-09-23 — `docs/rainforest/estado/2026-09-23-contrato-de-veredito.json:8-13`)

## Achados que corrigem o texto do design (leia antes das tarefas)

**1. O teto de 3 reprovações já existe — genérico, testado, e a via literal do D7 ("`exigir revisar --rodada-extra`") criaria um deadlock se implementada ao pé da letra.**

`scripts/estado.cjs` já tem `TETO_TENTATIVAS = 3` (linha 160), incrementado em `blocoNovo.tentativas` sempre que `marcar <estagio> reprovado` roda (linha 1789), e uma trava em `exigir` (linhas 1507-1522) que recusa reentrar no estágio reaberto (`executar`) quando `tentativas >= 3` e não há `liberado_em`. O destrave hoje é `node scripts/estado.cjs liberar --slug <s> --estagio revisar` (a mensagem de erro na linha 1518 já usa exatamente `--estagio revisar`, porque `estagio_reprovador` = `'revisar'` quando é o revisor que reprova). Tudo isso é testado em `scripts/testa-estado.sh` seção "17. contador tentativas: teto de 3 com destrave" (linhas ~732-930), incluindo o ciclo `rev-teto` (913-924) que reprova 3x e confirma o teto.

Tracei o que aconteceria se D7 virasse um novo *flag* em `exigir --estagio revisar` (a leitura literal do design): na 3ª reprovação, `executar` ganha `reaberto_por` (linha 1798); `exigir --estagio executar` é quem primeiro bate no teto (1510-1521), não `exigir --estagio revisar` — porque `estado.revisar.reaberto_por` nunca é setado (`upstreamImediato` sempre devolve `'executar'`, linha 273-278). Um `--rodada-extra` pendurado em `exigir revisar` não desbloquearia `exigir executar`, que é quem realmente recusa — precisaria dos DOIS destraves para uma decisão só, e o design promete um.

**Decisão técnica (não de produto — não muda nada visível ao usuário além do nome do comando): estender `liberar --estagio revisar`, não `exigir`.** `liberar` (linhas 1578-1589) não tem NENHUMA trava própria hoje — nunca é bloqueado pelo "upstream reaberto" (esse cheque só existe dentro de `cmd === 'exigir'`, linhas 1531-1545). Faço `liberar --estagio revisar` exigir `--rodada-extra "<texto>"` + o arquivo de impasse SOMENTE quando `--estagio revisar` (outros estágios continuam com o `liberar` incondicional de hoje — fora do escopo deste design). Isso fecha exatamente o mesmo ciclo que o design pede, sem tocar no mecanismo genérico que `testa-estado.sh` §17 já cobre, e sem inventar um segundo contador (o `tentativas` existente, uma vez que D9 passa a exigir veredito por trás de cada `marcar reprovado`, já conta exatamente "reprovações reais").

**2. `docs/rainforest/portoes/<slug>-impasse.md` (a grafia literal do D7) não bate com a isenção de creep que já existe.** `skills/revisar/SKILL.md:139` e `scripts/conferir-fluxo.cjs:514-523` isentam `docs/rainforest/portoes/*${slug}.md` — um glob real (`*` → `[^/]*`, `scripts/conferir-fluxo.cjs:676-683`), que exige o slug **imediatamente antes** de `.md`. `<slug>-impasse.md` tem `-impasse` depois do slug — não casa. Sem ajuste, o arquivo de impasse fica creep e reprova a própria revisão que o D7 autoriza. Task 7 adiciona uma entrada literal à lista `globs_isentos`.

**3. O payload do `SubagentStop` tem uma lacuna real, e a premissa do briefing ("`agent_transcript_path`") não está confirmada.** Consultei a doc oficial (`code.claude.com/docs/en/hooks`) direto e via um agente `claude-code-guide` dedicado: campos comuns confirmados — `session_id`, `cwd`, `hook_event_name`, `transcript_path`, `scratchpad_dir`, `permission_mode`, `effort`; específicos de `SubagentStop` confirmados — `agent_id`, `agent_type`, `last_assistant_message`. A doc **recomenda usar `last_assistant_message` em vez de reler o transcript** (pode estar atrasado) — isso resolve a extração do veredito sem tocar em arquivo. Mas a doc **não confirma** um campo `agent_transcript_path` distinto, nem diz se `transcript_path` no `SubagentStop` aponta para o transcript do subagente ou da sessão principal, nem onde o transcript do subagente fica em disco. Empiricamente encontrei a pasta `subagents/` dentro de `~/.claude-personal/projects/<projeto>/<sessão>/` com arquivos `agent-<id>.jsonl` + `agent-<id>.meta.json` (`agentType` no meta bate com o `agent_id` do nome do arquivo) — e `scripts/conferir-divergencia.cjs:13-17,99-129` já documenta e lê exatamente esse formato para outro mecanismo (`divergir-frames`). É fortemente sugestivo, mas não é confirmação do payload real do hook. **Task 1 captura o payload ao vivo antes de qualquer código do hook ser escrito** — é o mesmo erro que a skill `plano` cita do incidente de 2026-08-19 (campo que a produção nunca envia, só a fixture injetava à mão).

**4. Amostra real do formato de veredito atual (antes deste design).** Abri `.../033532e9-e484-455a-8c68-75288d64bb63/subagents/agent-a09a300b85fe409dc.jsonl` (revisão real, 2026-09-17): a primeira mensagem tem `content` como **string pura** (não array de blocos) — confirma que o parser de `Slug:` precisa aceitar os dois formatos, defensivamente. A última mensagem do assistente termina em prosa livre `"...**APROVADO**"` (negrito, dentro de um parágrafo) — não uma linha isolada `VEREDITO: ok`. Isso confirma que D2 é mudança de comportamento real do revisor (não só formalização do que já acontece), e que os textos de `skills/revisar/SKILL.md`/`agents/revisor.md` precisam instruir explicitamente uma última linha **sem markdown, sem prosa ao redor**.

**5. Risco de injeção por `--json` não coberto pelo design.** `scripts/estado.cjs:1784` funde `--json` cru no bloco do estágio (`{...baseAnterior, ...extra, status, em}`). Sem trava, `marcar revisar ok --json '{"vereditos":[{"veredito":"ok"}]}'` forja a prova que a task 5/6 supostamente exige — o mesmo buraco que a linha 1643-1646 já fecha para `reaberto_por` (Issue #148). Task 5 replica esse padrão para `vereditos`.

**6. Escrita concorrente é o cenário que o próprio D6 assume (revisores em paralelo).** Dois hooks de `SubagentStop` podem rodar em paralelo (dois revisores despachados juntos) e fazer leitura-modificação-escrita não serializada no mesmo `docs/rainforest/estado/<slug>.json` — `gravar()` (linhas 212-217) é atômico por escrita, não por ciclo ler→empilhar→gravar. `hooks/lib/trava-jsonl.cjs` já existe, com `Trava`/`comTrava` (lock por PID com detecção de dono morto) usado hoje por `scripts/ideias.cjs`/`scripts/divergencias.cjs`. Task 3 reaproveita esse módulo em vez de inventar outro.

**7. Um mesmo subagente pode disparar `SubagentStop` mais de uma vez.** A própria notificação de tarefa em segundo plano deste ambiente registra isso ("a same task-id may notify more than once" quando a sessão é retomada). Sem *upsert* por `agent_id`, um revisor retomado que muda de veredito (ex.: `reprovado` → depois `ok` após conversa adicional) deixaria as duas entradas na janela, e o gate "todos ok" (D6) nunca fecharia mesmo com o veredito final correto. Task 3 faz upsert por `agent_id`, não `push` cego.

## Premissas aceitas sem conferir (quem despachou corrige se erradas)

- Que o `agent_type` relatado pelo `SubagentStop` para este agente é literalmente `rainforest-mind:revisor` (confirmado só no `.meta.json` do armazenamento de sessão, não no payload do hook em si — Task 1 confirma).
- Que a pasta de scratch (`scratchpad_dir`, campo comum do payload) é gravável pelo hook durante a captura de Task 1 sem prompt de permissão adicional.
- Que nenhum outro hook de `SubagentStop` será adicionado por este design além do novo (não há registro `SubagentStop` hoje em `hooks/hooks.json`, confirmado).

## O que não pode quebrar

- `scripts/testa-estado.sh` inteiro (137+ asserções na última medição registrada em `docs/rainforest/portoes/2026-09-02-fluxo-6-portoes.md:36`), em especial a seção 17 (teto genérico com `verificar` como reprovador) e o backstop de mutação (seção 10, HEAD/sujos).
- `scripts/testa-segunda-opiniao.sh` inteiro — vocabulário `concordo|discordo`, exit codes, e a fixture `parecer-multilinhas.cjs` continuam se comportando igual após o refactor da task 2.
- `CAMPOS_EFEMEROS` (`pendentes`, `reaberto_por`, `em_voo`) — `vereditos` **não** entra nessa lista (é histórico da janela, zera só em `exigir revisar`, não em todo fechamento `ok`).
- Fluxos hoje parados em `revisar` cujo `exigir` rodou **antes** deste design (sem `vereditos` no bloco) continuam fechando `marcar revisar ok|reprovado` sem trava nova — só avisam em stderr.
- Revisão avulsa (sem `Slug:` no briefing) continua funcionando exatamente como hoje: hook não escreve nada, `marcar` não pede nada extra (D5, já no design).

---

## Tarefas

### 1. Capturar o payload real do `SubagentStop` [tipo: pesquisa]
atende: D1, D5
arquivos: `(nenhum arquivo de produção — grava captura em scratchpad_dir/temp, fora do repositório)`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: pesquisa não produz comportamento de produção a inverter; o artefato é uma captura de dado real, não código.
pronto quando: com um agente `rainforest-mind:revisor` real despachado (via `Agent`/`Task`, briefing qualquer, incluindo a linha `Slug: captura-payload-teste`), e um hook temporário registrado em `SubagentStop` que faz só `fs.writeFileSync(path.join(process.env.CLAUDE_PROJECT_DIR||'.', 'captura-subagentstop.json'), fs.readFileSync(0,'utf8'))` — ao o agente terminar, `captura-subagentstop.json` contém um JSON válido cujas chaves são listadas — provado por `node -e "console.log(Object.keys(JSON.parse(require('fs').readFileSync('captura-subagentstop.json','utf8'))))"` mostrando se `agent_id`, `agent_type`, `last_assistant_message`, `transcript_path` (e, se existir, `agent_transcript_path`) estão presentes, e qual caminho de arquivo `transcript_path` contém (deve apontar para dentro de `.../subagents/agent-<agent_id>.jsonl` ou ser confirmado como outra coisa). O hook temporário e o arquivo de captura são removidos ao final; o resultado (nomes de campo confirmados) vai para o briefing da task 8.
**Como registrar o hook temporário sem mexer no ambiente do usuário (regra 15):** numa sessão headless `claude -p` rodada dentro de um diretório de caixa temporário, com `--settings <arquivo-temporário.json>` contendo só o hook `SubagentStop` de captura — nunca em `~/.claude*/settings.json`, nunca no `hooks/hooks.json` do plugin. O prompt da sessão headless despacha um `rainforest-mind:revisor` com briefing mínimo.

### 2. `scripts/lib/extrair-veredito.cjs` — extrair e reaproveitar em `segunda-opiniao.cjs` [tipo: implementar]
atende: D2
arquivos: `scripts/lib/extrair-veredito.cjs`, `scripts/segunda-opiniao.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/lib/extrair-veredito.cjs`
  de: `return linhas[linhas.length - 1].trim().toLowerCase();`
  para: `return linhas[0].trim().toLowerCase();`
  bateria: `bash scripts/testa-segunda-opiniao.sh`
  fixture: `scripts/fixtures/segunda-opiniao/parecer-multilinhas.cjs` (exercida na seção em torno da linha 288-310 de `scripts/testa-segunda-opiniao.sh` — parecer com várias linhas e veredito `concordo` só na última)
pronto quando: com o mesmo binário `scripts/segunda-opiniao.cjs --modelo codex ...` de hoje, o comportamento não muda — provado por `bash scripts/testa-segunda-opiniao.sh` saindo 0 com a mesma contagem de "ok" de antes da mudança (comando roda e o número de "ok"/"falha" bate com a execução anterior ao refactor).

### 3. `estado.cjs`: subcomando `veredito` (grava/upsert, com trava) [tipo: implementar]
atende: D1
arquivos: `scripts/estado.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const idx = agenteId ? vereditos.findIndex((v) => v.agente_id === agenteId) : -1;`
  para: `const idx = -1;`
  bateria: `bash scripts/testa-estado.sh`
  fixture: `contrato de veredito: registrar duas vezes o mesmo agente-id substitui, nao duplica` (novo caso: `node scripts/estado.cjs veredito --slug <s> --estagio revisar --veredito reprovado --agente rainforest-mind:revisor --agente-id AAA` duas vezes seguidas com veredito diferente na segunda chamada; `ler` deve mostrar 1 entrada, com o veredito da SEGUNDA chamada)
pronto quando: com o comando real `node scripts/estado.cjs veredito --slug <slug-de-teste> --estagio revisar --veredito ok --agente rainforest-mind:revisor --agente-id X` rodado contra um slug existente com `revisar` pendente, `docs/rainforest/estado/<slug-de-teste>.json` passa a ter `revisar.vereditos` com uma entrada `{agente,agente_id,veredito:"ok",em}` — provado por `node scripts/estado.cjs ler --slug <slug-de-teste>` mostrando o campo, e por duas chamadas concorrentes (`&` no shell, mesmo slug, `agente-id` diferentes) resultando em 2 entradas (não 1, não 0) — provado por `bash scripts/testa-estado.sh` (novo caso "duas escritas concorrentes preservam as duas").
Nota de implementação (não é código, é a decisão que a task herda): trava via `hooks/lib/trava-jsonl.cjs` (`comTrava`), lock em `path.join(DIR_ESTADO, '.'+slug+'.veredito.lock')`, releitura de `ler(slug)` **dentro** da trava (nunca reaproveitar o `estado` já carregado por `main()` antes do lock).

### 4. `estado.cjs`: `exigir --estagio revisar` zera a janela [tipo: implementar]
atende: D6
arquivos: `scripts/estado.cjs`
depende de: 3
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `estado.revisar = { ...estado.revisar, snapshot, vereditos: [] };`
  para: `estado.revisar = { ...estado.revisar, snapshot };`
  bateria: `bash scripts/testa-estado.sh`
  fixture: `contrato de veredito: janela de vereditos zera a cada exigir revisar` (novo caso: registra 1 veredito, roda `exigir --estagio revisar` de novo — via um novo ciclo `executar ok` — e confere `revisar.vereditos` voltou a `[]`)
pronto quando: com `node scripts/estado.cjs exigir --slug <slug-de-teste> --estagio revisar` rodado numa segunda vez (depois de já ter 1+ vereditos gravados de uma rodada anterior), `docs/rainforest/estado/<slug-de-teste>.json` mostra `revisar.vereditos: []` — provado por `node scripts/estado.cjs ler --slug <slug-de-teste>` (campo presente e vazio, não ausente).

### 5. `estado.cjs`: `marcar revisar ok` exige a janela toda `ok` [tipo: implementar]
atende: D3, D6
arquivos: `scripts/estado.cjs`
depende de: 4
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const naoOk = bloco_atual.vereditos.filter((v) => v.veredito !== 'ok');`
  para: `const naoOk = bloco_atual.vereditos.filter((v) => v.veredito === 'ok');`
  bateria: `bash scripts/testa-estado.sh`
  fixture: `contrato de veredito: marcar revisar ok recusa quando ha veredito reprovado na janela` (registra 1 `ok` + 1 `reprovado`, `marcar --status ok` tem que sair 2)
pronto quando: (a) com um slug cujo `revisar.vereditos` (janela armada) está **vazio**, `node scripts/estado.cjs marcar --slug <s> --estagio revisar --status ok` sai 2 e a mensagem de erro nomeia "nenhum veredito gravado" — provado pela saída de stderr contendo essa frase (critério de superfície humana: quem lê decide o que fazer sem abrir o código); (b) com a mesma janela tendo 2 vereditos `ok` de agentes diferentes, o mesmo comando sai 0; (c) com `--json '{"vereditos":[{"veredito":"ok"}]}'`, o comando recusa (exit 1) citando que `vereditos` não entra por `--json` — provado por `bash scripts/testa-estado.sh` cobrindo os três.

### 6. `estado.cjs`: `marcar revisar reprovado` exige veredito reprovado gravado [tipo: implementar]
atende: D9
arquivos: `scripts/estado.cjs`
depende de: 5
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `!bloco_atual.vereditos.some((v) => v.veredito === 'reprovado')`
  para: `!bloco_atual.vereditos.some((v) => v.veredito === 'ok')`
  bateria: `bash scripts/testa-estado.sh`
  fixture: `contrato de veredito: marcar revisar reprovado recusa sem veredito reprovado gravado` (janela só com vereditos `ok`, `marcar --status reprovado` tem que sair 2)
pronto quando: com uma janela contendo só vereditos `ok` (nenhum `reprovado`), `node scripts/estado.cjs marcar --slug <s> --estagio revisar --status reprovado` sai 2 com mensagem citando "nenhum veredito 'reprovado' gravado" — provado por stderr; com a mesma janela tendo 1 `reprovado`, o comando sai 0 e incrementa `estado.revisar.tentativas` normalmente (herda o mecanismo já testado em `testa-estado.sh` §17, sem tocar nele) — provado por `bash scripts/testa-estado.sh`.

### 7. `estado.cjs`: `liberar --estagio revisar` exige impasse + `--rodada-extra`; isenção de creep [tipo: implementar]
atende: D4, D7
arquivos: `scripts/estado.cjs`, `scripts/conferir-fluxo.cjs`
depende de: 6
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `if (!fs.existsSync(caminhoImpasse)) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-estado.sh`
  fixture: `contrato de veredito: liberar --estagio revisar recusa sem o arquivo de impasse` (roda `liberar --estagio revisar --rodada-extra "texto"` sem o `.md` existir; espera exit 2)
pronto quando: (a) com o teto de 3 reprovações do fluxo `revisar` atingido (mesmo ciclo do `rev-teto` de `testa-estado.sh` §17, mas reprovando `revisar` em vez de `verificar`, com vereditos reais gravados via task 3), `node scripts/estado.cjs liberar --slug <s> --estagio revisar` **sem** `--rodada-extra` sai 2 pedindo o texto — provado por stderr (critério de superfície humana); (b) com `--rodada-extra "<texto>"` mas sem `docs/rainforest/portoes/<s>-impasse.md` no disco, sai 2 nomeando o caminho esperado do arquivo; (c) criando esse arquivo e repetindo o comando, sai 0, grava `estado.revisar.liberado_em` e `estado.revisar.rodadas_extra` (array, não sobrescreve entradas anteriores) — provado por `node scripts/estado.cjs ler --slug <s>`; (d) com o arquivo de impasse presente no diff de um `revisar` normal (outro slug), `node scripts/conferir-fluxo.cjs cobertura --slug <outro-slug>` (ou o mecanismo de creep do `revisar`) não o acusa de creep — provado rodando o `conferir-fluxo.cjs` contra um diff sintético que só toca esse arquivo.

### 8. `hooks/veredito-revisor.cjs` [tipo: implementar]
atende: D1, D3, D5
arquivos: `hooks/veredito-revisor.cjs`, `scripts/lib/primeiro-prompt-jsonl.cjs`
depende de: 1, 2, 3
paralela: nao
mutacao:
  arquivo: `hooks/veredito-revisor.cjs`
  de: `if (!['revisor', 'rainforest-mind:revisor'].includes(agentType)) process.exit(0);`
  para: `if (false) process.exit(0);`
  bateria: `bash hooks/testa-veredito-revisor.sh`
  fixture: `secao "agent_type que nao e revisor e ignorado" — payload com agent_type:"outro-agente" cujo transcript de fixture TEM 'Slug:' e veredito válidos; sem o filtro, o hook gravaria mesmo assim`
pronto quando: (a) com um payload de `SubagentStop` real ou fielmente reproduzido a partir da captura da task 1 (`agent_type` confirmado ali, `last_assistant_message` terminando em `VEREDITO: ok`, e um transcript de fixture cuja primeira linha tem `Slug: <slug-de-teste>` em `message.content` string), rodado via `node hooks/veredito-revisor.cjs < payload.json`, `docs/rainforest/estado/<slug-de-teste>.json` passa a ter `revisar.vereditos` com 1 entrada `ok` — provado por `node scripts/estado.cjs ler --slug <slug-de-teste>`; (b) sem a linha `Slug:` na primeira mensagem, o hook sai 0 e NADA é gravado — provado pelo arquivo de estado ficando byte-idêntico ao de antes da chamada; (c) com `last_assistant_message` cuja última linha não bate o vocabulário (`"parece bom"`), o hook grava veredito `invalido` (não `ok`, não `reprovado`, não silêncio) — decisão explícita de D3: a linha "a revisão não existe" vale para os GATES de `marcar` (nem conta como ok, nem como reprovado), mas o registro em si fica auditável — provado por `ler` mostrando `veredito:"invalido"` na janela.

### 9. `hooks/hooks.json` + `hooks/lib/config.cjs` — registrar e permitir desligar [tipo: configurar]
atende: D1
arquivos: `hooks/hooks.json`, `hooks/lib/config.cjs`
depende de: 8
paralela: nao
mutacao:
  arquivo: `hooks/hooks.json`
  de: `"command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/veredito-revisor.cjs\""`
  para: `"command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/nao-existe-de-propositado.cjs\""`
  bateria: `bash hooks/testa-veredito-revisor.sh`
  fixture: `secao "hooks.json aponta para o hook certo" — le hooks.json, resolve ${CLAUDE_PLUGIN_ROOT} para a raiz do repo, roda o comando exato encontrado e confere que ele executa sem ENOENT`
pronto quando: com `hooks/hooks.json` tendo a chave `SubagentStop` apontando para `veredito-revisor.cjs` (chave que hoje não existe no arquivo — confirmado em `hooks/hooks.json:1-191`), e com `node scripts/setup.cjs --desligar contrato-veredito` rodado, o hook sai 0 sem gravar nada mesmo recebendo um payload válido de revisor com `Slug:` — provado por `node hooks/veredito-revisor.cjs < payload-valido.json` seguido de `node scripts/estado.cjs ler --slug <slug-de-teste>` mostrando `revisar.vereditos` inalterado; religando (`--ligar`), o mesmo payload volta a gravar.

### 10. `skills/revisar/SKILL.md` — contrato de veredito [tipo: docs]
atende: D2, D5, D7, D8
arquivos: `skills/revisar/SKILL.md`
depende de: 5, 6, 7, 8, 9
paralela: nao
mutacao: n/a
  motivo: doc não tem comportamento de sistema a inverter; a falsificação é coerência com as decisões, feita no critério abaixo.
pronto quando: o texto novo (a) instrui a última linha do relato do revisor a ser exatamente `VEREDITO: ok` ou `VEREDITO: reprovado`, sem negrito nem texto depois — coerente com D2 e com o achado de que o formato atual usa `**APROVADO**` em prosa (achado 4 acima); (b) instrui incluir `Slug: <slug>` na PRIMEIRA linha do briefing despachado (molde da seção "Molde do briefing do revisor", hoje sem essa linha — confirmado em `skills/revisar/SKILL.md:73-83`), espelhando a convenção real de `Runtime:`/`Sensor:` de `skills/executar/SKILL.md:71-79`; (c) documenta o comando real de destrave da 4ª rodada como `node scripts/estado.cjs liberar --slug <s> --estagio revisar --rodada-extra "<texto>"` — não `exigir revisar --rodada-extra`, corrigindo o desvio descrito no Achado 1; (d) atualiza a frase da seção "Trava de cobertura de creep e mutação" (linhas 202-205, "`reprovado` não exige nada disso") para citar a nova exigência de D9 (veredito `reprovado` gravado) — provado por revisão humana comparando cada um dos 4 pontos contra o texto publicado, e por `grep -c "VEREDITO:" skills/revisar/SKILL.md` ≥ 1.

### 11. `agents/revisor.md` — seção (f) do veredito [tipo: docs]
atende: D2, D5, D8
arquivos: `agents/revisor.md`
depende de: 5, 6, 7, 8, 9
paralela: nao
mutacao: n/a
  motivo: mesmo motivo da task 10.
pronto quando: a seção (f) (hoje "Veredito honesto, resultado primeiro", `agents/revisor.md:73-76`) passa a instruir a última linha do relato como `VEREDITO: ok`/`VEREDITO: reprovado`, mantendo a primeira frase como resumo em prosa (D2 não pede que a primeira linha mude — só a última) — provado por leitura comparando o texto novo com D2, e pela ausência de instrução contraditória em outro ponto do arquivo (`grep -n "APROVADO\|REPROVADO" agents/revisor.md` não deve sobrar nenhuma referência ao vocabulário antigo como exemplo a seguir).

### 12. `hooks/testa-veredito-revisor.sh` [tipo: teste]
atende: D1, D3, D5
arquivos: `hooks/testa-veredito-revisor.sh`, `hooks/fixtures/veredito-revisor/` (novos arquivos de fixture — transcritos `.jsonl` sintéticos)
depende de: 8, 9
paralela: nao
mutacao: n/a
  motivo: a própria bateria É a prova; as mutações que ela precisa detectar já estão nomeadas nas tasks 8 e 9 (o `de`/`para` mora nelas, não aqui — bateria nova não tem comportamento próprio a inverter, só exercita o hook).
pronto quando: rodando `bash hooks/testa-veredito-revisor.sh` contra os fixtures reais gerados a partir da captura da task 1 (não inventados à mão sem essa base — é o requisito de "entrada real" desta skill), a bateria cobre pelo menos: agent_type correto grava; agent_type errado não grava; sem `Slug:` não grava; `Slug:` presente mas slug inexistente em disco não grava (best-effort); veredito fora do vocabulário grava `invalido`; dois hooks concorrentes (mesmo slug, `agente-id` diferentes, disparados em paralelo via `&` no bash) preservam as duas entradas — provado por `bash hooks/testa-veredito-revisor.sh` terminando em "N ok, 0 falha(s)" com N ≥ 6, e por essa contagem N sendo maior que 0 skips (nenhum caso pulado por infraestrutura ausente).

### 13. `scripts/testa-estado.sh` — extensão [tipo: teste]
atende: D4, D6, D7, D9
arquivos: `scripts/testa-estado.sh`
depende de: 3, 4, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: as mutações que esta bateria precisa pegar já estão declaradas nas tasks 3-7 (cada uma cita `bash scripts/testa-estado.sh` como bateria); esta task é a extensão da própria bateria, não um comportamento de produção adicional.
pronto quando: rodando `bash scripts/testa-estado.sh` completo, a contagem final de "ok" cresce em pelo menos 10 em relação à contagem de hoje (registrada em `docs/rainforest/portoes/2026-09-02-fluxo-6-portoes.md:36`: "137 ok, 0 falhas") — provado pela linha final da bateria — e a seção 17 (teto genérico com `verificar` como reprovador) continua passando sem alteração no seu próprio código, só no arquivo estendido — provado por diff mostrando que os casos `t3-frontier`/`rev-teto` (linhas 732-930 hoje) não mudaram de conteúdo, só de posição no arquivo.

---

