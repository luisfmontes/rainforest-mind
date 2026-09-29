# Três repos indicados pelo usuário — strands harness-sdk, reef, flowsint — 2026-09-29

O pedido veio com duas partes: enxertar código **e** a ideia de cada repo. Por isso a trilha
declarada foi **Enxertar**, com **Ler** como degrau de baixo da cascata. A seção "Ideias" de
cada repo não é enfeite: ela é a trilha Ler pedida de forma explícita.

Foram três avaliadores (sonnet) em paralelo, com clone raso no scratchpad, só leitura, e
cada um fechou o relato com a lista literal dos comandos que rodou. **As afirmações que
decidem cada veredito foram reconferidas na janela principal, contra os mesmos clones.** Uma
delas foi medida rodando o código (strands, poda).

| Repo | Commit lido | Licença | Push (API) |
|---|---|---|---|
| `strands-agents/harness-sdk` | `db34d01` | Apache-2.0 | 2026-09-29 |
| `Human-Agent-Society/reef` | `52775d4` | Apache-2.0 | 2026-09-29 |
| `reconurge/flowsint` | `4c05849` | Apache-2.0 | 2026-09-24 |

## Âncoras declaradas antes da busca

| Repo | Problema ancorado | Trilha |
|---|---|---|
| harness-sdk | `papel-de-advisor-que-observa-a-janela-principal`, `quebra-laco-advisory-com-argumento-canonicalizado`, `portao-mecanico-para-a-regra-15`, `poda-de-resultado-com-invariante-de-convergencia` | enxertar |
| reef | `perfil-de-trabalho-que-aprende-sozinho`, `memoria-sinal-de-utilidade-no-ranking`, `regra-escrita-nao-impede-a-propria-reincidencia` | enxertar |
| flowsint | `escada-de-confianca-derivada-da-estrategia`, `skill-advpl-graph-grafo-de-conhecimento`, `semantica-agi-grafo-para-segundo-cerebro`, `opcao-avaliada-e-morta-some-do-design-doc` | enxertar |

## O que a rodada ensinou

**1. Nos três repos o mecanismo mais interessante está desligado, sem consumidor ou só
declarado.** A família é a mesma do mem0 e do MemPalace em 23/09.

- **reef.** O manifesto de falhas e o histórico de rejeições são gravados e repassados aos
  proposers, e os três proposers do repo os jogam fora:
  - `reef/recipe/reefine/agent.py:523` diz *"reads none of manifest, rejected or sources;
    they are the contract's, unused here"*;
  - `recipes/meta_harness/method.py:175` faz `del nodes, manifest, rejected`.

  Os freios do laço também vêm todos desligados de fábrica (`reef/recipe/cordis.py:288-296`):
  `promote_failures=False`, `recheck_every=0` e `max_failure_streak=0`. O grader padrão é um
  health-check (`evolution.py:43-45`, `{"[health]": "reef-ok"}`).
- **flowsint.** `GraphEdge.confidence_level` é declarado (`graph/types.py:55`) e esse é o
  único acerto do grep em todo o Python. Ninguém grava o campo, e a UI renderiza um valor que
  nunca chega. O `MERGE` de aresta tem chave `(label, sketch_id)`
  (`graph/repository.py:152-153`), então dois enrichers que afirmam a mesma relação colapsam
  numa aresta só, e o histórico de quem afirmou o quê se perde.
- **strands.** O design doc promete `agent.interventions.auditLog`
  (`team/designs/0007-intervention-primitive.md:162`) e o grep dá zero no código. O teste
  `'is logged in the audit trail'` não afirma nada.

**2. O invariante de convergência que a ideia `poda-de-resultado-…` pede não está no strands,
medido.** `buildPreview` (`strands-ts/src/context-manager/methods/truncate.ts:33-64`) garante
duas coisas:
- a poda nunca aumenta o texto (`:59-61`);
- a configuração converge, porque `threshold > previewTokens` é validado na construção
  (`strategies/offload/truncate.ts:35-43`).

Ele **não** garante que a segunda passada seja nula. Rodei a função copiada do clone sobre
200.000 caracteres com `previewTokens: 500`. A primeira passada dá 2072 caracteres. A segunda
dá 2064, com conteúdo diferente (`p1 === p2` → `false`): ela poda de novo o que já estava
podado, porque o marcador `[... N chars elided ...]` encolhe junto com N. O
`TRUNCATED_PREFIX` existe (`truncate.ts:10`), mas o único uso é na montagem do cabeçalho
(`:56`), e nenhum leitor o usa para pular texto já podado. O enxerto tem que ser
**cabeça+marcador+cauda + guarda de não-crescimento + pular quando o marcador já está
presente**, com teste de `f(f(x)) === f(x)`. O strands dá as duas primeiras partes, e a
terceira é nossa.

**3. Dois repos corroboram, pelo código, observações que já estavam abertas aqui.**
- **strands e `gate-por-parser-de-shell-e-poco-sem-fundo`.** O strands não faz parse de
  shell. O bash tool se declara *"without sandboxing"* (`vended-tools/bash/README.md:15`) e o
  ambiente local se chama `NotASandboxLocalEnvironment`. A resposta dele ao "o agente não pode
  mexer no ambiente" é isolamento (docker/ssh), nunca gate lendo o texto do comando.
- **reef e `regra-escrita-nao-impede-a-propria-reincidencia`.** O laço do reef fecha em
  **caso medido**, não em regra escrita. A falha reportada vira tarefa permanente de regressão
  (`backend.py:301-359`), e o candidato só é publicado se vence a versão atual em pares
  intercalados (`backend.py:538-566, 1265-1290`).

## strands-agents/harness-sdk — `Enxertar: enxerta`

Monorepo com o SDK em Python e em TypeScript, em paridade, mais o "harness" opinativo e uma
TUI. O controle é feito por **interventions** sobre hooks Before/After (Invocation, ModelCall,
ToolCall), com 5 ações: `proceed`, `deny`, `guide`, `confirm` e `transform`
(`interventions/actions.ts:38-152`). A matriz ação×evento está em `:136-150`.

**Por âncora:**

1. **advisor.** Reprova na pergunta 4. O que existe são dois avaliadores pontuais.
   - `LLMSteeringHandler` cria um Agent **novo** a cada decisão (`steering/handlers/llm.ts:226-244`).
     Ele vê só o ledger de chamadas, nunca o transcript, e devolve
     `{proceed|guide|confirm, reason}` (`:153-160`).
   - O juiz do `GoalLoop` recebe o transcript comprimido depois da invocação
     (`goal/judge.ts:73-100`).

   Um modelo por PreToolUse custa latência e token em toda chamada. O desenho que sobra
   (contexto restrito, saída estruturada, avaliador sem estado) vai para Ler.
2. **quebra-laço.** Fora da âncora. Não há contador de chamadas idênticas nem canonicalização:
   o `ToolLedgerProvider` guarda os `args` crus (`tool-ledger.ts:86`), e a detecção de
   "falhas repetidas" fica com o LLM, pelo prompt (`llm.ts:86-90`). Achado colateral: `guide`
   em `beforeToolCall` **veta** (`registry.ts:123-125` seta `event.cancel`), e o empurrão sem
   veto só existe em `beforeModelCall` (`:161-165`).
3. **portão da regra 15.** Fora da âncora quanto ao problema real, que é o texto de shell. O
   Cedar autoriza por nome da tool e por argumentos estruturados, com falha fechada por padrão
   (`cedar/cedar.ts:168-210`, `interventions/handler.ts:46`). O HITL tem lista por nome em que
   `!nome` vence até o trust (`hitl/hitl.ts:231-233`).
4. **poda.** **Enxerta**, com o reparo medido no item 2 acima. Custa ~30 linhas em Node.

**Ideias (Ler), com a origem de cada uma:**
- **Negar ≠ orientar ≠ pedir confirmação**, como ações separadas. Motivo declarado:
  `cancelTool` misturava "não pode" com "tente de novo" (`0007:39`). A matriz está em código.
  Para a **portaria**: barrar e orientar são saídas diferentes, e hoje as duas saem como
  recusa.
- **Falha fecha, configurável por handler** (`onError: throw|proceed|deny`,
  `handler.ts:19,46`). Código.
- **Juiz cético e sem estado.** *"Na dúvida, não passou"*; instrução dentro do transcript
  não muda o veredito; juiz novo por chamada para não vazar julgamento anterior
  (`goal/judge.ts:43-48`, `goal/plugin.ts:389-391`). Código (prompt). Encaixa no crítico cego
  da `regua` e no `revisar`.
- **Todo laço tem limite.** `maxAttempts`/`timeout`, com aviso se os dois forem infinitos, e
  o tempo é checado **antes** do validador caro (`goal/plugin.ts:148,253-269,335-345`).
  Código.
- **Invariante validado na construção**, com erro em vez de aviso
  (`offload/truncate.ts:35-43`). Código.
- **Nome honesto:** `NotASandboxLocalEnvironment`. Código.
- **Injeção efêmera.** O texto injetado por gatilho (`userTurn`/`everyTurn`) nunca persiste
  na conversa, e o renderer que falha não derruba nada (fail-open;
  `vended-plugins/context-injector/plugin.ts`). Código. É parente direto do núcleo+índice do
  SessionStart.
- **"Barato e determinístico primeiro, LLM por último"**, com precedência
  Deny > Interrupt > Transform > Guide > Proceed (`0007:116,154`). **Só doc.** O código despacha
  por ordem de registro (`registry.ts:219`) e não impõe essa precedência.
- **O porquê mora em `team/`** (TENETS, DECISIONS, designs numerados). **Só doc**: os arquivos
  existem, e não conferi se os PRs os respeitam.

**Peças fora das âncoras:**
- `_dispatch` (`interventions/registry.ts:211-270`): deny corta, guides acumulam, transform
  age no lugar, erro do handler vira ação. Destino: portaria.
- Stash com chave recomputável após reinício (`context-manager/stash.ts:57,74`). Destino:
  saída podada que continua recuperável pelo `memoria.cjs`.
- `GoalLoop` (`goal/plugin.ts:331-382`): valida no fim e rearma com feedback. Destino: gate
  do `verificar`.

## Human-Agent-Society/reef — `Enxertar: enxerta`

Serviço Python (~95 mil linhas) que serve o agente, grava as interações, recebe nota e
feedback, e evolui uma "árvore de harness" (regras, skills, comandos). A versão nova só é
publicada se um seletor aprova. O laço de ponta a ponta:
1. `POST /reef/report` traz nota e feedback, amarrados por recibo à versão exata que produziu
   a resposta.
2. Um proposer (LLM) muda uma skill por passo (`evolution.py:449-514`).
3. `evaluate` roda o candidato contra a versão atual, em pares intercalados, para a deriva do
   provedor cair nos dois lados.
4. O seletor aprova por vitórias − derrotas > margem (`backend.py:538-566`).
5. Toda versão é commit numa cadeia com pai; o `recheck` reavalia a anterior contra a
   publicada e faz rollback se ela vencer (`backend.py:1111-1135,1366-1388`).
6. Código de laço (`native_loop`) nunca é publicado sem uma pessoa (`reef/harness/tree/nodes.py:47`).

**Por âncora:**
1. **perfil que aprende sozinho.** Fora da âncora. Não há reforço, decaimento nem invalidação
   temporal de preferência. O que invalida é a *versão publicada*, quando o modelo servido
   muda.
2. **sinal de utilidade no ranking.** Fora da âncora. O SkillClaw detecta leitura de
   `SKILL.md` e agrupa as sessões por skill (`recipes/skillclaw/harness/sessions.py:41-60,247-254`),
   mas o sinal alimenta a **reescrita** da skill. Nenhum ranking usa.
3. **regra escrita não impede reincidência.** **Enxerta.** Duas peças lidas no código:
   - **Impressão digital de falha.** `normalize_cause` troca caminho por `<path>`, id longo por
     `<id>` e dígito por `<n>`; `fingerprint` = sha256(tarefa, estágio, causa normalizada)
     (`reef/train/cordis_backend/manifest.py:41-63`). A classificação é
     nova / persistente / corrigida a cada passo (`:163-215`). São ~100 linhas em Node, e
     encaixam no `ideias.cjs`: saber que a **mesma** observação da regra 13 voltou, sem
     depender de quem escreve lembrar.
   - **Falha vira caso de regressão permanente**, com teto total (50) e por cliente (5), e com
     triagem de texto que tenha forma de segredo ou de diretiva (`backend.py:301-359`,
     `_screened` `:323-325`). Encaixa no `ao_colher` das observações virando caso em
     `evals/`.

   O que **não** cabe é a medição em pares, porque exige executor de episódios. A `regua` e os
   `evals/` são o equivalente mais fraco que temos.

**Ideias (Ler):**
- **Fechar o laço em caso medido, não em regra escrita.** É a resposta direta à observação
  ancorada: a regra 13 grava a observação e nada mede se o comportamento mudou. Código.
- **Reavaliar quando o contexto de avaliação muda.** No reef, quando o modelo servido troca.
  Aqui seria reavaliar regras e ganchos quando o modelo da sessão muda. Código.
- **Disjuntor por N rejeições seguidas + teto de passos** (`backend.py:1057-1069`). Os vigias
  não têm freio de "N tentativas seguidas sem efeito". Código.
- **Texto do cliente entra cercado como dado** (`untrusted_text`, `evolution.py:490-493`):
  feedback e falha nunca falam como prompt. Código. Destino: jardineiro-ideias.
- **Tipo de artefato que exige pessoa para publicar.** Código.
- **Critério pré-registrado.** O ganho só conta acima de 2 desvios-padrão do controle,
  calibrado a 5,6% de falso positivo (`recipes/skillclaw/harness/stats.py:1-19`). O script é
  código. O dado bruto não está no repo.
- **Separar "artefato servido" de "estado de execução".** **Só doc** (RFC `evolution-scope`,
  marcado *Deprecated*).
- "Human-Agent Society" como filosofia: **não conferido**. O nome só aparece em URL.

**Números:** Meta-Harness 22/60 contra 21/60 (`recipes/meta_harness/RESULTS.md:27`), com
*"raw histories … remain internal"*: autodeclarado. SkillClaw "+12,05": `stats.py` existe,
mas nenhum `summary.json` de rodada está no repo, então não se reproduz a partir do clone.

## reconurge/flowsint — `Enxertar → Ler: vale voltar`

Ferramenta de OSINT em grafo, com FastAPI + Celery + Postgres (metadados) + Neo4j (grafo) no
back e React/xyflow no front. As entidades são ~40 classes Pydantic registradas por decorador.
Cada **enricher** declara `InputType` e `OutputType` (`enricher_base.py:111-113`), e o schema
de entrada e saída é derivado do tipo (`:253-336`). Os flows encadeiam as saídas de um passo
como entradas do seguinte (`orchestrator.py:483`). Não executei nada contra alvo nenhum.

**Por âncora:**
1. **confiança derivada da estratégia.** Fora da âncora. É justamente o buraco do repo (ver
   "O que a rodada ensinou", item 1).
2. **advpl-graph.** Passa na 1 só pela modelagem e reprova na **4**:
   - tipo declarado uma vez e reusado em schema, validação e nó;
   - chave natural `(tipo, label, escopo)` com upsert que mescla propriedades
     (`repository.py:119-125`);
   - `exclude_unset` para não apagar campo que outro enricher gravou (`serializer.py:164-176`).

   Tudo isso é Neo4j/Cypher. O equivalente em sqlite é `ON CONFLICT DO UPDATE` com
   `COALESCE`, uma linha: mecanismo trivial, sem nada a copiar.
3. **grafo para o segundo cérebro.** Fora da âncora. É grafo de entidades tipadas, sem
   semântica sobre texto, e o chat não lê o grafo (`chat_service.py:136-193`).
4. **opção avaliada e morta.** Reprova na 4. O soft delete (`deleted_at`) esconde nó e aresta
   **sem guardar o porquê**, e `Analysis.content` é JSON livre.

**Ideias (Ler) — o motivo do `vale voltar`:**
- **Coletor tipado por entrada e saída, com descoberta por tipo.** `list_by_input_type`
  responde "o que posso rodar sobre este fato?" (`flowsint-enrichers/.../registry.py:102-123`).
  Código. Para o `advpl-graph`: cada extrator declara o que consome (fonte, função, tabela) e o
  que produz.
- **Fonte nova como configuração, não como código.** O template enricher em YAML tem `input`,
  `request`, `response.map` e `output` (`template_enricher.py:73-195`). Código.
- **Auditoria por passo, com `inputs`, `outputs`, `status`, `error`, `cache_hit` e tempo**
  (`orchestrator.py:423-435`). É o mais perto de proveniência que o repo tem, e mora **fora**
  do grafo. Código.
- **Contra-lição, e a ideia mais útil do repo para nós.** A proveniência sem dono virou campo
  opcional espalhado (`source`, `confidence` ad hoc em alguns tipos), e a aresta única por
  `MERGE` apaga quem afirmou o quê. Para a `escada-de-confianca-derivada-da-estrategia`, isso
  quer dizer: a estratégia que produziu o fato tem que fazer parte da **chave** da aresta, ou
  a confiança derivada não tem de onde ser derivada.
- **Segredo por referência, não por valor** (`vaultSecret`, `enricher_base.py:160-195`).
  Código.
- **Sketch como visão do estado num momento, várias por investigação.** Só glossário
  (`docs/syllabus.mdx`).

**Confissões:**
- `update_results_mapping` admite *"a pre-existing gap not fixed here"* (`orchestrator.py:311-315`).
- `execute` engole toda exceção e devolve `[]` (`enricher_base.py:442-448`), então "sem
  resultado" e "erro" ficam indistinguíveis.
- `preprocess` descarta entrada inválida em silêncio (`:401-402`).

## Comandos da reconferência na janela principal

```
gh api repos/<owner>/<repo> --jq '[.full_name,.stargazers_count,.pushed_at,.license.spdx_id]'
# flowsint
sed -n 55p .../graph/types.py; grep -rn confidence_level --include=*.py .
sed -n 147,155p .../graph/repository.py; sed -n 440,448p .../enricher_base.py; sed -n 311,315p .../orchestrator.py
# reef
sed -n 288,296p reef/recipe/cordis.py; sed -n 521,524p reef/recipe/reefine/agent.py
sed -n 175p recipes/meta_harness/method.py; sed -n 41,63p .../manifest.py; sed -n 43,45p .../evolution.py
# strands
sed -n 33,64p .../truncate.ts; sed -n 120,126p .../interventions/registry.ts
grep -rn "auditLog|audit_log" strands-ts/src strands-py/src harness-ts harness-py   -> vazio
grep -rn TRUNCATED_PREFIX -> só truncate.ts:10 e :56
node idem.cjs  (buildPreview copiado do clone; 200.000 chars, previewTokens 500) -> "2072 2064 false"
```
