# Doze repos indicados pelo usuário — 2026-09-23

Chegaram por indicação, catorze de uma vez. Dois já estavam no livro e **não foram
reavaliados**: `bytedance/deer-flow` (26/08) e `DeusData/codebase-memory-mcp` (01/09)
têm push posterior, mas o gatilho de revisita é duplo e exige 60+ dias. As peças dos
dois continuam **plantadas, não enxertadas** — `canal-fora-do-terminal-para-o-que-nao-cabe-na-sessao`,
`escada-de-confianca-derivada-da-estrategia`, `lacuna-declarada-por-maquina-no-mapa` e
`sonda-de-drift-do-mapa-por-stat-e-hash` seguem abertas no `ideias.jsonl`, que é a
pergunta de revisita da trilha Enxertar.

O `beads` estava na fila desde 09/08 como `steveyegge/beads`, recusado pelo
`dados-batedor-repos.js` por falta de trilha. O repo mudou de dono: `gh api
repos/steveyegge/beads` devolve o mesmo objeto, com o mesmo `id`, de `gastownhall/beads`.
A linha de 09/08 fica; a desta rodada entra com o nome novo.

Oito avaliadores (sonnet) em paralelo, clone raso no scratchpad, só leitura, lista
literal de comandos no fim de cada relato. **As afirmações que decidem cada veredito
foram reconferidas na janela principal**, contra os mesmos clones, antes de virar linha.

## Âncoras declaradas antes da busca

| Repo | Problema ancorado | Trilha |
|---|---|---|
| `cloudflare/security-audit-skill` | `regua-owasp-agentic-skills-para-auditar-o-proprio-plugin` + corpo do agente `auditor-de-seguranca` | instalar |
| `NVIDIA/SkillSpector` | `auditar-descricao-de-ferramenta-de-terceiro-como-superficie-de-ataque` + `regua-owasp-agentic-skills-…` | instalar |
| `alibaba/open-code-review` | `revisor-que-despacha-sub-revisores-nomeados` + `contrato-de-veredito-de-uma-linha-no-revisar` | instalar |
| `mem0ai/mem0` | `trazer-a-memoria-pra-dentro-do-rainforest` + `memoria-sinal-de-utilidade-no-ranking` + `memoria-encurta-antes-de-cortar-e-superada-sai-primeiro` | instalar |
| `rohitg00/agentmemory` | as mesmas três de memória | instalar |
| `MemPalace/mempalace` | as mesmas três de memória | instalar |
| `topoteretes/cognee` | as três de memória + `semantica-agi-grafo-para-segundo-cerebro` | instalar |
| `gastownhall/beads` | `beads-no-lugar-ou-por-cima-do-ideias-jsonl` | instalar |
| `rtk-ai/rtk` | `contrato-de-compressao-do-headroom-reimplementado` + `poda-de-resultado-com-invariante-de-convergencia` + `poda-verbatim-de-tool-calls-na-compaction` | instalar |
| `code-yeongyu/oh-my-openagent` | `claude-central-despachante` + `subagente-escritor-com-worktree-por-filho` + `revisor-que-despacha-sub-revisores-nomeados` | instalar |
| `deepset-ai/haystack` | `trazer-a-memoria-pra-dentro-do-rainforest` + `semantica-agi-grafo-para-segundo-cerebro` | enxertar (framework, Instalar fora da mesa) |
| `DreambigOu/ELI5` | **nenhuma ideia aberta cobre**; o mais perto é a skill pessoal `segundo-cerebro` | instalar |

## O que a rodada ensinou, e vale mais que os doze vereditos

**1. O mecanismo famoso de dois repos de memória está morto no código.** O mem0 é
conhecido pelo ciclo ADD/UPDATE/DELETE/NOOP decidido por LLM — o prompt existe
(`mem0/configs/prompts.py:176-324`) e `get_update_memory_messages` (`:406-455`) **não
tem chamador fora de teste**; o `add()` de hoje roda um pipeline "V3" (`main.py:916`)
que só faz ADD (`ADDITIVE_EXTRACTION_PROMPT`, `prompts.py:468-472`) mais dedup por MD5
exato. O MemPalace tem a fórmula de reforço e decaimento mais bem fundamentada da
rodada (`dynamics.py`, Hebb/Ebbinghaus/Cepeda) — e o próprio docstring (`:12-17`)
confessa que *"nothing potentiates them on access and nothing decays them over
time"*. Nos dois casos, quem lesse o README (ou os posts sobre o repo) enxertaria um
mecanismo que o autor não usa. É a mesma família da `suposicao-que-resolve-vira-ideia`,
agora vista do lado do repo.

**2. Três headlines de número tinham script — a primeira rodada em que isso é maioria.**
`rtk` (60-90%: `scripts/benchmark.sh` + `run.ts`), `MemPalace` (96,6% LongMemEval raw:
`benchmarks/longmemeval_bench.py`, e o `BENCHMARKS.md:87-94` desconta o próprio 100%
como *teaching to the test*) e `agentmemory` (`benchmark/scale-eval.ts` + dado bruto;
`README.md:484` separa o que mediu do que é autodeclarado de terceiros). Sem fonte:
`open-code-review` (dataset externo no Hugging Face), `SkillSpector` (corpus de 31.132
skills declarado externo em `scripts/compare_scan_accuracy.py:4-8`) e `ELI5`.

**3. A peça que a ideia `memoria-sinal-de-utilidade-no-ranking` pedia existe ligada
em um só dos quatro repos de memória.** `agentmemory` grava acesso toda vez que a
memória é **servida** (`access-tracker.ts:53-83`, chamado de `context.ts:255`,
`search.ts:604` e outros) e o lê de volta numa fórmula (`retention.ts:88-94`:
`min(1, saliência·e^(−λ·idade) + Σ 1/dias-desde-o-acesso)`). O `TencentDB` (16/09)
tinha `usage_count` morto; o MemPalace tem a fórmula sem fiação. Ressalva: lá o score
decide **eviction**, não a seleção do SessionStart (`context.ts:234` ordena por recência).

## Vereditos

### `rohitg00/agentmemory` — Instalar → Enxertar: enxerta
Reprova em 2 (12 eventos de hook, colide nos 5 que o plugin ocupa), 3 (as 26
descriptions somam 4.172 B, mais 54 tools MCP), 4 (`ci.yml:49-54` tira Windows da
matriz por path POSIX; #1331 aberta: `.env` não carrega no Windows e a integração
falha em silêncio reportando saudável) e 5 (daemon `iii-engine` em `localhost:3111`,
hooks com `fetch(...).catch(() => {})`). **Peça:** o sinal de utilidade descrito acima,
~150-200 linhas. Não resolve `encurta antes de cortar` (`context.ts:234-251` descarta o
bloco inteiro). ★28.747, Apache-2.0.

### `MemPalace/mempalace` — Instalar → Enxertar: enxerta
Reprova em 2 (`.claude-plugin/hooks/hooks.json`: Stop, SessionEnd, PreCompact) e 3
(`mcp_server/schemas.py`: 47 tools, não 45 como o `plugin.json` anuncia, ~49 KB de
descrição+schema — três vezes o teto inteiro). 4 também reprovaria: 19 issues de
Windows abertas, #1660 e #378 no mecanismo de hook. Roda sem LLM por padrão (Chroma
local + ONNX MiniLM; `closet_llm.py:8-11`), busca híbrida vetor+BM25 0,6/0,4.
**Peça:** `dynamics.py:49-280`, funções puras (~80 linhas) de potenciação no co-acesso,
decaimento e efeito de espaçamento — **fórmula, não pipeline provado** (ver acima).
Complementa o `agentmemory`: um tem a fiação, o outro a matemática melhor. ★59.245, MIT.

### `topoteretes/cognee` — Instalar → Enxertar → Ler: vale voltar
Instalar: 2 passa (sem plugin nem hook), 4 passa com a melhor evidência da rodada
(matriz com `windows-latest` em `test_different_operating_systems.yml:16`, shim de
OpenSSL em `cognee_db_workers/_windows_openssl.py`, zero issue de Windows aberta), 3
reprova: `remember`/`recall`/`forget` somam 4.774 B de docstring e o `cognify` extrai o
grafo por LLM, `openai` por padrão (`llm/config.py:109`, `extract_graph_from_data.py:9`)
— mesmo precedente do `TencentDB`. Enxertar reprova em 4: a peça pequena legível
(exposição de tools MCP por tag, `cognee-mcp/src/tool_registry.py:22-65`) não tem onde
aplicar aqui, e o resto é o produto. Ler: vale voltar **para a
`semantica-agi-grafo-para-segundo-cerebro`** — armazenamento embutido (LanceDB +
ladybug/kuzu, sem servidor) e `temporal_graph/` + `cascade_extract/`, **não lidos**,
como pista de validade temporal de fato. O clone raso falhou no Windows por nome de
arquivo longo. ★30.938, Apache-2.0.

### `mem0ai/mem0` — fora da ancora
Nenhuma das três âncoras tem mecanismo no código aberto: o ciclo UPDATE/DELETE está
morto (acima) e o decaimento é do lado pago — `main.py:469-470` levanta erro com
`decay=True` e `notices.py:134` diz *"not supported by the OSS Memory SDK"*. O plugin
do Claude Code exige chave da nuvem (`api_key` obrigatória, `DEFAULT_API_URL =
"https://api.mem0.ai"`), registra 9 eventos e manda telemetria PostHog identificada
(*"Not anonymous"*, opt-out por `MEM0_TELEMETRY=false`). ★65.882, Apache-2.0.

### `gastownhall/beads` — Instalar → Enxertar: enxerta
Reprova em 2 (`plugins/beads/.claude-plugin/plugin.json:19-33`: SessionStart e
PreCompact rodando `bd prime`), 3 (`cmd/bd/prime.go:92-93`: *"CLI mode: ~1-2k tokens"*
— estimativa do autor, sem medição) e 5 (Dolt embutido é o único backend; a proposta
de backend plugável é só design). Windows passa com folga: job `test-windows`, binários
assinados amd64/arm64 no release, `winget/`, `install.ps1`. **Peças:** (1) ID por
`sha256` + nonce em base36 (`internal/idgen/hash.go:53-84`, ~90 linhas) contra o slug
digitado à mão do `ideias.jsonl`; (2) bloqueio e *ready work* derivados do grafo de
dependência, recalculados na mesma transação (`issueops/blockedstate.go:15-58` +
`cycledetector.go:9-60`, ~330 linhas) — o `ideias.jsonl` não tem dependência entre
ideias. **Não se enxerta:** o CAS por `row_lock` (resolve merge célula a célula do Dolt;
o lock de arquivo do `ideias.cjs` basta) e a compactação (exige LLM por item). A
resposta à pergunta da ideia é **por cima, em peças — não no lugar**. ★27.382, MIT.

### `alibaba/open-code-review` — Instalar → Enxertar: enxerta
Reprova em 5 (binário Go único). Não tem persona nem sub-revisor nomeado: divide por
partição determinística do change-set (`grouping.go:22`; abaixo de 4 arquivos ou 200
linhas nem chama LLM) e por regra de linguagem. **Peças:** (1) veredito por tool-call
**mutuamente exclusiva** — `report_incorrect_comments` xor `approve_all_comments`
(`internal/agent/agent.go:1558-1608`) —, garantido pelo parser da API em vez do grep na
última linha do `claudex-loop`; (2) ordem dos campos é *load-bearing*: `analysis`
antes de `comment_ids`, com o incidente de replay documentado no comentário
(`:1567-1574`); (3) assuntos protegidos que o filtro não pode remover (memória,
concorrência, mudança de comportamento) e falha do filtro que **mantém** o achado
(`:1864-1873`); (4) linha do achado resolvida por casamento textual contra o hunk real,
o LLM nunca fixa a linha (`internal/diff/resolver.go:151-301`, `relocation.go:44-49`);
(5) timeout por subtarefa com falha contabilizada, nunca espera indefinida
(`agent.go:674,734-808`) — o sintoma do incidente da âncora de sub-revisores. ★40.046,
Apache-2.0.

### `cloudflare/security-audit-skill` — Instalar → Enxertar: enxerta
Reprova em 2: duplica o gatilho do agente `auditor-de-seguranca` (framework de método,
a classe de BMAD/gstack/base) e despacha subagentes pelo slot que a portaria controla.
Windows é fato pesado: issue #53 **aberta**, do próprio autor — *"Validator CLIs cannot
read any input on Windows"* (`O_NOFOLLOW` indefinido no win32) —, ou seja, a fase de
validação independente que é o coração da skill não roda aqui. 398 B de description;
bus factor 1, zero release. **Peças (contrato, ~150-250 linhas de JS):** ledger de
cobertura como máquina de estado que impede declarar "completo" (`HUNTING.md:217`);
verificador fresco por candidato com ordem de refutar (`VALIDATION-AND-REPORTING.md:7,12`);
três vereditos de campos disjuntos por schema — `confirmed`/`needs_validation`/`rejected`
(`report-schema.json`) — com severidade **só** para `confirmed`; `rejected` retido como
supressão entre rodadas (`:101`); fingerprint estável (`HUNTING.md:153`). Novo frente a
`claudex-loop` e `codegraff`: o ledger, o `needs_validation` e o rejeitado retido. ★20.592, MIT.

### `NVIDIA/SkillSpector` — Instalar → Enxertar: enxerta
É o hit mais direto de `auditar-descricao-de-ferramenta-de-terceiro-…`, e passa em 1 e 2
(sem hook, sem MCP; a skill `skill-inspector` tem 268 B e degrada sozinha sem o
binário). Reprova em 5: `pyproject.toml:38-51` torna obrigatórios `langgraph`,
`langchain-anthropic/aws/openai`, `boto3`, `langsmith`, `openai` e `yara-python`
**mesmo para `--no-llm`**. Windows: CI só Ubuntu, #617 e #485 abertas. A detecção é
**regex determinística**, não LLM julgando prosa: `mcp_tool_poisoning.py:219-239`
(`_HTML_COMMENT_RE`, `_MARKDOWN_COMMENT_RE`, `_ZERO_WIDTH_RE`, `_DATA_URI_RE`) aplicadas
em `_check_tp1` (`:242-294`); 15 módulos `static_patterns_*` (13.228 linhas), ≥63
`rule_id` (contagem parcial), 20 regras YARA — o `malware.yar.b64` é um stub de 57 B.
**Peça:** as regex e o vocabulário de `rule_id` — o degrau em código do que o
`mukul975/Anthropic-Cybersecurity-Skills` (26/08) só tinha em prosa. ★18.143, Apache-2.0.

### `rtk-ai/rtk` — Instalar → Enxertar: enxerta
Reprova em 2: `rtk init` grava um PreToolUse com matcher `Bash` rodando `rtk hook
claude` (`src/hooks/constants.rs:11`), que devolve `updatedInput` + `permissionDecision:
allow` — o comando que executa deixa de ser o texto que o `gate-worktree` leu, o ponto
cego já registrado para `claudex-loop` e `Graft`. E em 3: o `@RTK.md` no CLAUDE.md custa
460 / 998 / 1.146 B por nível. Windows passa com ressalva: CI e winget existem, mas 79
issues de Windows no título, com #3632 aberta (hook falha em 100% das chamadas, em
silêncio, sob Git Bash). Telemetria opt-in de verdade (`telemetry.rs:31-58`).
**Peças:** guarda `never_worse` — devolve a saída crua se a filtrada não for menor
(`src/core/guard.rs:17`, ~15 linhas); e *tee* por hash que só elide saída de comando
**que falhou** e ≥500 B, devolvendo `[full output: rtk recall <hash>]` (`tee.rs:24,62`)
— a saída de erro fica indireta, nunca perdida. Novo frente a `headroom`,
`context-mode` e `fast-jev`: atua **antes** do transcript, não depois. ★81.519, Apache-2.0.

### `code-yeongyu/oh-my-openagent` — Instalar → Enxertar: enxerta
Reprova em 2: é outro harness (plugin do OpenCode e adaptador de Codex); a camada
`claude-code-compat-core` **importa** plugins do Claude Code para dentro do OpenCode, na
direção oposta. Licença não é OSI: `LICENSE.md` é *Sustainable Use License* — uso
interno ou não comercial, sem redistribuir por preço. **Peças:** (1) guarda de
profundidade de delegação — `COORDINATOR_AGENT_NAMES = ["prometheus"]` e
`isCoordinatorAgent()` (`delegate-task/constants.ts:405-415`), rejeitada **antes** de
spawnar, com teste de regressão amarrado à issue #4027 — alvo natural é a
`portaria.cjs`; (2) laço de continuação por objetivo no `session.idle`
(`hooks/goal/`, 380 linhas) que fecha em código, mas cuja parada é **autorrelato**
(`update_goal({status:"complete"})`, `tools.ts:36-63`) — enxertar exige levar o
verificador que falta; (3) merge de patch de agente num índice git descartável
(`isolation-core/src/merge/branch-mode.ts:31-50`) + lock + abort automático no
conflito. O `ultrawork` são 21.809 B de prompt injetados por regex no prompt do
usuário. ★69.317.

### `deepset-ai/haystack` — fora da ancora
Não há grafo de conhecimento (o único grafo é o DAG do pipeline,
`core/pipeline/base.py:15,116`), e a fusão de rankings (RRF em `utils/misc.py:156-185`,
DBSF no `document_joiner.py:224-257`) pressupõe duas listas, BM25 e vetor — o
`2026-09-18-recall-fts5-reconciliacao.md` decidiu ficar sem vetor, e `memorix` e
`TencentDB` já tinham trazido o mesmo. ★26.584, Apache-2.0.

### `DreambigOu/ELI5` — fora da ancora
Nenhuma ideia aberta; a observação `nao-consulto-o-segundo-cerebro-sem-ser-mandado` é
sobre disparo, e o ELI5 só acrescentaria um segundo gatilho concorrente para o mesmo
território. Reprovaria em 6 de qualquer modo: dois dias de commits em março, zero
release, `LICENSE:3` sem titular (issue #1 sem resposta). "83% vs 42%" sem script.

## Achado lateral, consertado

Ao comparar com o haystack, o avaliador leu o `buscar` do `scripts/memoria.cjs`:
texto cru no `MATCH` do FTS5. Reproduzido na janela principal — `buscar --texto
"claude-mem"` devolvia `no such column: mem` e lista vazia, com exit 0, e é o comando
que a abertura da sessão anuncia. Consertado no PR #320 (sintaxe válida segue crua;
no erro, repete com os termos citados), com teste que falha sem o conserto.

## O que ficou sem conferir

- `tools/list` real do `agentmemory` (54 tools) — inferido por escala, não medido.
- `cognee`: `temporal_graph/`, `cascade_extract/` — é exatamente o que o `vale voltar`
  aponta.
- `SkillSpector`: contagem exata de `rule_id` (63 é piso) e wheel de `yara-python` no Windows.
- `oh-my-openagent`: `team-mailbox`, `team-tasklist`, `boulder-state`; Windows.
- Nenhum binário foi rodado; tamanhos de injeção são de arquivo ou comentário de fonte.
