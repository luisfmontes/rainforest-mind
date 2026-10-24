# Releitura do livro, 2026-10-24

Releitura feita em 2026-10-24 dos cerca de 80 repos do livro e dos créditos do README, em 10 grupos lidos no código, pela lente de memória, de desenvolvimento e de entendimento de código. Serve de inventário de ideias, não de veredito de adoção: cada peça traz o repo e o `arquivo:linha` de onde saiu, e a adoção é decidida caso a caso no design e no plano. Em cada grupo, as top 5 peças novas e, em seguida, as peças abaixo do corte. O texto é o do consolidado, só com a divisão em itens.

## G1 memória A

### Top 5

1. claude-mem tag-stripping.ts:1-60 — captura remove blocos injetados (private, contexto do próprio plugin, reminders do harness, persisted-output) com aninhamento; private sem fechamento fica intacto. POSSÍVEL DEFEITO no rainforest: grep não achou strip na captura → memória pode recapturar o que a abertura injetou. Conferir onde a captura lê o texto.
2. cognee temporal_hybrid_retriever.py + temporal_hints.py — buscar com janela de tempo (--desde/--ate ou "semana passada" por regra), âncora reordena por precisão (tightness_rank), fallback com motivo; datas relativas normalizadas na escrita contra a última data com ano. memoria.cjs buscar não filtra data hoje.
3. context-mode store.ts:263-348,1288-1335 — rerank por proximidade sobre top-N do bm25: bônus de título, 1/(1+minSpan/len), pares adjacentes saturados. Stopwords PT-BR próprias. + mem0 scoring.py sigmoide adaptativa pelo nº de termos para somar sinal limitado com bm25.
4. claude-mem rank.ts:55-106 + strength.ts — ranking da abertura ACT-R: ln(1+idade^-0.5+α·Σ idade_reforço^-0.5), reforço = duplicata que colapsa (até 10 dias), ¼ das vagas por recência pura, α=0 = comportamento atual.
5. agentmemory cascade.ts + cognee invalidate_sessions.py — invalidação em cascata por proveniência: superada marca stale o que foi derivado (resumos, mapas), índice inverso, lotes retomáveis.

### Abaixo do corte

- claude-mem nearDuplicate+idfVeto (dedup barato antes do LLM, veto por token raro)
- context-mode retomada consumida uma vez (claim atômico por UPDATE)
- context-mode atribuição de projeto por evento com confiança (medir se observacoes.projeto mistura worktrees)
- mempalace supersede com intervalo semiaberto e instante único
- cognee pesos que decaem por turnos ociosos com neutro exato
- TencentDB portão estrito "quando em dúvida, silêncio" na importação em lote + "primeiro o arquivo, depois a tarefa" (ordem observacao x marca_dagua)
- claude-mem bloco de abertura pré-computado com placeholders (serve territorio-frescor)
- mempalace lição: conferir que a coluna de ranking é preenchida.

## G2 memória B / contexto

### Top 5

1. OpenViking session/working_memory.py:508,841,919 — documento de estado com 7 seções; LLM propõe KEEP/UPDATE/APPEND por seção e o código mescla com guards: append-only rebaixa UPDATE, UPDATE que perde caminho de arquivo é rejeitado, pendência sumida é restaurada com marca "[silently dropped, restored]", cobertura de âncoras >=70%. Aplica a handover e estado do fluxo. (âncoras em inglês)
2. rtk src/learn/detector.rs:222 find_corrections — minerador falha→correção do transcrito, sem LLM: falha real, janela das 3 seguintes, similaridade>=0.5, confiança>=0.6, descarta idêntico/caminho/TDD; classify_error tipa; gera cli-corrections.md.
3. Segurança de entrada: headroom managed_block.py:34 sanitize_block_text (neutraliza marcadores no texto derivado de transcrito antes de injetar — memoria-sessao.cjs não sanitiza, conferido por grep) + rtk hooks/trust.rs (config de projeto só carrega depois de `trust` gravar SHA-256; mudou = desconfia). Aplicação: .rainforest de projeto de cliente decide comportamento sem revisão.
4. memorix orchestrate/effect-ledger.ts:67,145 — ledger de efeitos de ferramenta por pipeline:task:attempt:callId; retry safe vs requires-idempotency-key; sem resultado = unknown. Antes de repetir push/merge/fechar issue após despacho interrompido.
5. beads cmd/bd/gate.go — gates tipados de espera (human, timer, gh:run, gh:pr) + `mol ready --gated` retoma o que destravou por descoberta. "CI rodando" vira estado conferível. (só descrição) + mol stale: filhos fechados e raiz aberta = revisar escopo.

### Abaixo do corte

- OpenViking externalize_group (teto agregado por turno 100k, maiores primeiro, sinopse tipada)
- OpenViking skill-experience (PostToolUse Read de SKILL.md injeta observações da skill — rainforest tem skill-observations/)
- memorix checkpoint de compaction em dois tempos (pre no PreCompact, complete casa, deliveredAt impede reentrega)
- memorix admission por âncora em código vivo
- memorix feedback com sinais negativos e revogação
- headroom loops.py minerador de re-fetch com desperdício medido e dedup de replay
- aar compute_file_lists (arquivos lidos/modificados calculados do transcrito, anexados ao resumo)
- aar read-only nudge após 8 passos só lendo
- haystack não podar resultado que já virou ponteiro (skip_meta_keys) + prompt de resumo que proíbe afirmar ausência
- beads compact conduzido pelo agente (script lista, agente escreve, script grava)
- OpenViking receita claude -p sem recursão (childEnv desliga hooks)
- headroom estabilidade de prefixo de cache (só plano).

## G3 entendimento de código

### Top 5

1. codebase-memory test_impact_engine.h + Graft TestSignal + code-review-graph coverage none|indirect — dúvida nunca estreita seleção de testes: evidência incerta = rodar tudo com motivo; config lida do merge-base; teste que alcança e ficou intocado = estado próprio (stale).
2. Graft check/local-check.ts — aprendizado ancorado em arquivo/símbolo (touches, kind, status, replaces) confrontado com o diff: só falha com evidência citada e aprendizado commitado na base; resto é pista; learning-edits lê a versão da base.
3. code-review-graph uncertainty.py — resultado vazio diz o que o zero vale: não indexado > grafo velho (sha ou mtime) > lacuna conhecida > ausência real; wording forte só com currency_verified.
4. Understand-Anything merge-batch-graphs.py:1066 recover_imports_from_scan — backfill determinístico do que o agente deixou cair (~25% das arestas), marcado recoveredFromImportMap; relatório Fixed / Could not fix.
5. graphify reflect.py — lições com decaimento 0.5^(idade/30d), corroboração mínima 2, dead_end/corrected negativos, sidecar com code_fingerprint e _is_stale = reverificar.

### Abaixo do corte

- acoplamento por co-mudança (codebase-memory pass_githistory: 6 meses, ignora commit >20 arquivos, min 3, score>=0.3)
- note-signals.ts do Graft (quando pedir lição por sinais do transcript, teto 3/sessão) + note-gate.ts (recusa nota sem código, status que envelhece, decisão sem motivo)
- code-review-graph get_impact_radius_sql (relaxamento de melhor score com peso por tipo de aresta, truncated/total separados) e compute_risk_score (teste indireto não desconta)
- graphify racily-clean (mtime+2s<=indexed_at) e cache semântico por fingerprint de prompt
- codegraff arquivar-não-apagar (spill com caminho no stub) e repo_map byte-estável com rodapé de omitidos
- codebase-memory hook_augment que nunca bloqueia
- pass_importance
- code-review-graph base incremental = sha do último build + round-trip por hash + merge-base.

## G4 frameworks de fluxo

### Top 5

1. gstack bin/gstack-evidence — wrapper que nunca altera exit; jsonl {cmd_sha,exit,commit,wtree,tests_ran}; tests_ran lido da cauda do resumo do runner em 3 estados (n, 0=ZERO-RUN=stale, unknown); frescor pelo fingerprint da árvore, não commit; check exige rótulos por nome. Furo: conferir-prova.cjs:233 aceita "nenhuma prova executada".
2. gstack lib/lane-ownership.ts — globs planejados x diffs de branches/PRs em voo contra merge-base; LANE_CONFLICT por arquivo; ref que não resolve = unavailable, nunca limpa. Caso: worktrees codex-*.
3. gstack autoplan-reconcile.ts — revisor devolve INPUT: <fase> <sha256> do que leu + achados em JSONL com ids da rodada; parse confere ambos.
4. BMAD deep-recon — firewall (pesquisador só recebe pergunta factual, sem a demanda; áreas de git ls-tree; plano/spec excluídos; commit fixo) + recon_kit.py:389-481 anchors re-encontra path:line (symbol) @ sha por git cat-file, symbol_found, changed_since. Para arqueologia.
5. superpowers builder-check-prompt.md — leitor cego do design: subagente fresco só com o caminho do doc devolve perguntas que faltam antes de planejar, ou "nothing important left". + Ruling: <decisão> — <porquê> — <custo se errado> no ledger, lista final exaustiva (modo autônomo).

### Abaixo do corte

- gstack plan-reality REALITY: com recibo + already-done (git log origin/base --since -- arquivos antes de planejar) + surface-check (flag/comando nomeado conferido contra --help)
- gstack verify-gate Stop roda comando declarado com --trust por hash
- gsd-verifier existe/substantivo/ligado
- BMAD verification-gap (adoção faltando, verificação obsoleta que ainda passa)
- BMAD intent-contract congelado + matriz I/O com teste que RODOU
- BMAD claims-check lê o plano só depois do trace
- superpowers fix-loop escada (3 mesmos, 2 tier acima, re-review escopado ADDRESSED/NOT)
- superpowers review-package (base ancestral, intervalo não vazio, diff em arquivo)
- gsd graduation (recorrência >=3 em 5 propõe promoção)
- gsd read-injection-scanner com padrões de sumarização
- ralph aprendizado gravado no CLAUDE.md do diretório tocado
- BMAD wake imprime mapa da memória, não conteúdo
- gstack decisions supersede/redact.

## G5 créditos do README

### Top 5

1. ponytail hooks/ponytail-map.js buildMap — mapa de código com orçamento: git ls-files + regex de definição de topo por linguagem, 1 linha por pasta, 2000 chars, compartilhado primeiro, testes/gerados pulados, injetado no início com 3 s e falha aberta. Canal possível: SubagentStart (escada-subagente.cjs).
2. ponytail band/metrics.ts addedLines/defsIn/duplicateOf/callsIn — duplicata de definição na hora da edição (nome normalizado já existe em outro arquivo) + reuso % como métrica. Hoje conferir-duplicacao.cjs só olha o plugin.
3. unlazy scripts/stop-hook.mjs — Stop bloqueia fim de turno com portão aberto; MAX_BLOCKS=6 sem progresso; progresso = hash do ESTADO RESOLVIDO dos portões (não bytes). Rainforest tem portoes.cjs mas não esse Stop.
4. chief-of-staff (pocock in-progress) + task-observer skill-load.sh — memória ancorada em commit ("As of repo@abc1234"), nunca "atualmente" sem data/commit; recall chaveado pelo nome nu da skill/agente prestes a ser usado; "0 abertas" sem cabeçalho parseado = exit 1.
5. pocock code-review — revisão em dois eixos paralelos (Padrões x Spec) sem fusão + baseline de 12 cheiros de Fowler cedendo ao padrão do repo. + pocock ask-matt/PHASE-BOUNDARIES: árvore continuar/clear/handoff/subagente/compact só na fronteira de fase, primária x secundária.

### Abaixo do corte

- unlazy claim de posse de arquivo entre folhas paralelas (OWNS:, interseção recusada)
- task-observer "segunda violação exige barreira armada" (contar reincidência por regra) e tetos com razão datada que rebaixam teto ocioso
- pocock codebase-design teste da exclusão + 4 categorias de dependência + substituir-não-empilhar
- improve-codebase-architecture churn por git log para priorizar
- wayfinder mapa multissessão com névoa e fronteira
- triage AGENT-BRIEF durável (contrato, não caminho/linha)
- i-have-adhd espiral de depuração (3 "ainda quebrado" = parar e nomear suposição)
- autoresearch critério de simplicidade no keep/discard e triagem de crash
- ponytail testes "stale" (edição depois da última rodada).

## G6 revisão/verificação

### Top 5

1. open-code-review session/manifest.go:228-232,840-857 — manifesto de cobertura: selected = completed+reused+failed+waived, Finalize rejeita soma errada; TerminalState só da cobertura; FailureClass enum fechado.
2. open-code-review session/compare.go:17-97 — comparação entre revisões em new/persisting/resolved/not_reviewed; chave sem nº de linha (caminho+categoria+trecho normalizado).
3. strix report/coverage.py — cobertura com proveniência: agent_reported x machine_observed; lacunas derivadas (needs_follow_up, skill sem linha no ledger, agente mudo); complete:false se run falhou.
4. flaky-tests-detection check_flakes.py:25-40,80-96 — flip rate pass/fail na série ordenada separa intermitente de quebrado (~15 linhas).
5. claudex-loop runner.py:116-146 — veredito estruturado com invariantes: APPROVED com achado high/medium rejeitado, REVISE sem achado rejeitado, BLOCKED exige limitations, coverage obrigatória.

### Abaixo do corte

- baseline de supressão presa a conteúdo+versão (SkillSpector suppression.py:218-285)
- escalada por falha repetida de tool (open-code-review tool_failure_streak.go)
- resumo de compaction com "Failed Attempts" e proibição de fundir itens (strix llm/compaction.py:96-140)
- testes removidos desde o baseline (ctrf run-insights.ts:799-822)
- catraca de dívida que só encolhe (mukul975 lint-descriptions.py)
- strix provas verificadas antes de gravar achado (reporting/tool.py:231-270).

## G7 harness / agentes

### Top 5

1. deer-flow receipt_verification.py:80-107 + acceptance_checks.py — recibo posicional [rN] por tool_result; relatório do filho cita [rN], código confere contra o stream do filho; verbo de ação sem citação = UNVERIFIED; critérios tipados (file exists/non-empty/json-valid/tests_passed:<cmd> casado por estrutura de shell na execução registrada); vocabulário "holds", nunca "verified"; texto sempre diz o limite da evidência. + worker.py:365 diff de workspace antes/depois: arquivo produzido tem de ter sido apresentado.
2. base corrections/mod.rs + propose.rs — correção por sinais fracos (frase, interrupção, recusa, edição manual posterior de arquivo da IA, pedido repetido >=4 palavras); nenhum decide, IA decide no prompt seguinte (0/36 interrupções seguidas de Stop). Triagem por BM25 contra regras: servida e quebrada = rewrite; não servida = keyword gap; nada = regra nova. Exige log do que foi servido por sessão. + shadow/mod.rs: matcher candidato em sombra, promoção pelas correções seguintes; hook nunca chama LLM.
3. hermes tool_guardrails.py:380-575 — laço por sha(nome+args canon+RESULTADO); ciclo A,B,A,B período 2-4; mutação bem-sucedida zera falhas ("retry é experimento novo"); resultado idêntico >=512 vira stub; teto por turno antes da chamada. Supera quebra-laco-advisory plantada.
4. oh-my-openagent agreements/mutate.ts:30-98 — ledger de acordos: id sha do texto, cada correção cita sessionId+messageId do USUÁRIO, contagem idempotente por recibo no arquivo, n>=limiar = needs-human; humano imutável; não remove contado. + reflection/park.ts disjuntor: 3 falhas iguais estacionam, half-open a cada 6h.
5. hermes subagent_worktree.py:116-212 — destruição só com prova afirmativa: poda se commits==0 E limpo E as duas sondas tiveram sucesso; senão inspection_failed "UNKNOWN"; com trabalho arquiva em refs/<x>/archive antes de remover. Serve limpar/fechar.

### Abaixo do corte

- hermes delegation_output_schema (1 retry de correção com erros literais)
- deer-flow eviction reserva 10% de slots para correction
- strands modo de autoridade por eixo do despacho, capacidade do filho ⊆ pai
- omo stale-work (ativo sem toque 6h vira paused)
- omo memória como repo git, consolidar em worktree e squash só do válido
- deepseek goal desarmado após resume até humano
- deepseek sem fila por deadlock
- deer-flow goal progresso = operação nova
- hermes curator stale 14d/arquiva 30d com pin
- hermes rebaixar ruído no bm25 sem excluir
- hermes anti-thrash após 2 compactações ineficazes
- base ast_hint só em busca de código
- base vocabulário de relações derivado do código + teste de contrato
- omo EVIDENCE_RECORDED frescor vs nascimento do transcrito.

## G8 skills / ferramentas

### Top 5

1. claude-plugins-official code-modernization trace_rules.py + extract-rules.js:287,364 — escada regra→teste: tested(teste que rodou nomeia a regra) > named not run > code only > claimed only > none; exit 1 se P0 não tested; árbitro por regra confirmed/refuted/wrong-citation, sem árbitro = unverified. Ponte arqueologia "Regras implícitas" → verificar.
2. claude-security finding.py:205 + scan.js:143 — 3 lentes (reachability/impact/defenses), mantém só com >=2 de 3, high só unânime, voto PREDATES_CHANGE separa defeito preexistente. revisar não tem "preexistente".
3. security-guidance hooks.json asyncRewake em Stop e git commit/push: revisor em background acorda a sessão com exit 2; baseline_sha por sessão, dedup (arquivo,trecho) com TTL.
4. codeburn yield.ts:264-497 — desfecho da sessão pelo git: productive/reverted/abandoned/ambiguous por "This reverts commit", squash salvo por hash de árvore na main.
5. math-proof ledger.py sentinela "=== END OF ANSWER ===" detecta saída truncada de agente + codeburn workflow-insights.ts USER_CORRECTION_PATTERNS pré-filtro regex de correção (tirou "answer" porque prosa de skill injetada caía no slot do usuário → correções fantasma).

### Abaixo do corte

- last30days remover bloco injetado antes de indexar (marcadores start/end) + piso de confiança com vazio honesto no SessionStart
- code-review blame/PRs anteriores no briefing do revisor
- doc-coauthoring reader testing (subagente só com o doc responde perguntas previstas)
- skill-creator holdout estratificado e grader que critica a própria asserção
- improve-system auditoria de ferrugem (regra não vista, MCP nunca chamado, skill morta)
- awesome-claude-code 10 candidatos não lidos (cxpak, selvedge, claude-code-tools, presence, roampal-core, tdd-guard, ctxlint, plannotator, fable, vir).

## G9 resto

### Top 5

1. ttgo pkg/tracker/failureanalysis/autoapply.go:7-45 — gate de autonomia por concordância medida: >=50 decisões julgadas e >=95% em 90 dias sob a versão vigente da política; trocar política fecha o gate; rótulo humano nunca tocado. (laya reforça: limiar vem de acurácia medida, não de confiança declarada.)
2. ttgo store/triage_examples.go — few-shot de correções humanas: só decisões anteriores ao evento, nunca a mesma execução nem clone; ordena mesmo alvo > mesmo tipo > recência; balanceia metade correções/metade acertos. + semantic.go: split humano vira restrição permanente (HumanBlocked).
3. meetily summary/processor.rs:364+ — map-reduce com limiar; chunk falho = erro após 2 tentativas, nunca pula em silêncio; require_visible_markdown recusa saída vazia/raciocínio não fechado.
4. meetily summary.rs:105,139,171,202 — backup antes de regenerar resumo; restaura em falha; zera em sucesso.
5. MiroFish zep_graph_memory_updater.py:599 barreira de ingestão antes de ler (deadline + erro); report_agent.py:1144 _strip_fake_tool_results remove tool_result inventado pelo modelo; insight_forge decompõe em subperguntas, busca, dedup, expande por relação.

### Abaixo do corte

- VoiceStudio faixa advisory separada do veredito (spec.py:254) e Coverage Critic (toda camada declarada tem spec)
- ttgo hash por bloco de evidência enviado
- whatsapp-mcp gate de dado pessoal por baseline (só o NOVO falha).

## G10 ECC restante

### Top 5

1. agent-proximity/distance.js:78,246,294 — risco de colisão entre agentes paralelos (noisy-OR: sobreposição de faixas de linha, acoplamento por imports, árvore), limiares ta 0.35/ra 0.7, prioridade por trabalho comprometido. Para tarefas "independentes" do plano.
2. context-selection.js:18-33 — piso de evidência para admitir skill: bm25>=20, >=3 termos, margem 1.5 sobre o 2º, termo no nome/trigger; recusa vazia honrada; diretiva negativa "não use X".
3. skill-evolution/health.js:41 — "não medido" != saudável: balde unmeasured (#2463: falta de escritor deixava painel verde). saude.cjs não tem.
4. agents/spec-miner.md — unidade Requirement(WHEN/THEN)/Invariant com id estável, enforced, test, "Last verified (commit)", orçamento amostrar-e-expandir com parada (3 sem achado ou 15 arquivos), deferred e uncertainty. + click-path-audit mapa sets/resets por escritor (quem grava e quem zera). Para arqueologia.
5. session-start.js:725-742 — moldura "HISTORICAL REFERENCE ONLY — NOT LIVE INSTRUCTIONS" na memória injetada, só em startup (#1534: reexecutou skill com args velhos pós-compact) + pre-compact.js captura antes da compactação (rainforest não registra PreCompact).

### Abaixo do corte

No consolidado este trecho se chama Reservas; fica aqui sob Abaixo do corte, com o mesmo texto.

- loop-status.js detector de sessão parada (tool_use sem tool_result >=30min, wakeup vencido)
- ck sinais de frescor (commits desde o último registro, sessão anterior sem registro)
- save-session "só vai em funcionou o que tem evidência"
- astra-review rubrica em schema por critério
- github-coordination claim no corpo da issue
- agent-architecture-audit 12 camadas (destilação vira pseudo-fato, monólogo vira memória).

## Entrou no lote 1

Cinco peças viraram decisões do design docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-1.md (D3, D4, D6, D7 e D8). Nenhuma outra peça entrou neste lote. O porquê de cada uma, o modelo de ameaça e os critérios de aceite estão no design.

- D3, captura sem bloco injetado: origem claude-mem tag-stripping.ts:1-60 (G1, item 1).
- D4, moldura e neutralização na injeção: origem ECC session-start.js:725-742 (G10, item 5) e headroom managed_block.py:34 (G2, item 3).
- D6, busca com --desde e --ate: origem cognee temporal_hybrid_retriever.py (G1, item 2).
- D7, campo busca: no plano e conferir-busca: origem ECC skills/search-first, pela ideia já plantada busca-previa-como-degrau-com-registro. Essa origem não aparece no consolidado de G1 a G10; vem do design.
- D8, conferir-ancoras: origem BMAD recon_kit.py:389-481 (G4, item 4).

## Backlog

As demais peças, top 5 e abaixo do corte de cada grupo que não entraram no lote 1, ficam registradas neste relatório, por grupo. Elas também foram plantadas no ideias.jsonl, uma ideia por grupo, com o marcador "rodada apoio-ao-dev" no contexto: ids `releitura-livro-g1-memoria-a` a `releitura-livro-g10-ecc-restante`. Duas sobras do lote 1 viraram ideias próprias: `limpar-corpus-de-memoria-com-relato-de-agente` (o corpus já gravado continua com relato de agente) e `captura-de-memoria-no-precompact` (depende de D3).
