# Design — Fluxo 8: `handover.cjs` (entrega completa) — formato canônico para o checador

Este arquivo é a forma canônica (`conferir-fluxo.cjs design/cobertura`) do
design consolidado em `docs/rainforest/design/fluxo-8-design-handover-regente.md`
— leia aquele para a narrativa completa (princípios, riscos, ciclo de vida da
tarefa). Divergência entre os dois se resolve a favor deste arquivo nos
pontos em que o consolidado ficou desatualizado pelo que o repositório
entregou desde 2026-08-30 (fluxos 5 fase 0, 6, 7 e 9) — e, principalmente,
no corte de escopo do `regente.cjs`, que o consolidado original não previa.

## Objetivo

Sessão longa apodrece antes de o objetivo — rodar o pipeline sem interação
humana — ser alcançado. Este design entrega a metade que se sustenta
sozinha: um handover mecânico por tarefa (`handover.cjs`, monta e nunca
julga), reusando infraestrutura que não existia em 2026-08-30 — resolução
de estágio por branch, portões re-executáveis, identidade de entregável.
O `regente.cjs` do consolidado original **não é construído nesta entrega**:
das duas razões estruturais que o justificavam, as duas já têm solução por
convenção do repositório (worktree por tarefa, detecção de processo
travado); a única coisa genuinamente nova que sobraria — spawnar sessão
headless completa e aguardar — depende de uma decisão que ainda não existe
(Q1, política de reprova) e herdaria um vazamento de processo documentado
e sem correção (Issue #187). Ver "Avaliado e descartado".

## Decisões fechadas

- **D1 — `handover.cjs` nasce completo nesta entrega; `regente.cjs` não é construído.** Ancorado na seção "Ordem na fila" do consolidado (o handover pode nascer antes e já servir sessão interativa sozinho) e no corte registrado em "Avaliado e descartado" abaixo.

- **D2 — a unidade do handover é o `slug` do fluxo, o mesmo identificador de `docs/rainforest/estado/<slug>.json`** — não um conceito novo de "tarefa". Caminho: `.rainforest/handover/<slug>/atual.md`. Ancorado na tabela "Ciclo de vida da tarefa" do consolidado, que amarra o fim da "tarefa" ao último `fechar` do fluxo — que é, por definição, por slug.

- **D3 — a montagem mecânica lê, sem julgamento, quatro fontes já existentes e nenhuma outra:** estágio atual por `hooks/lib/estagio-ativo.cjs` (resolvedor canônico, fail-closed, já usado pela portaria — nunca reimplementado); decisões e evidências dos estágios fechados por `docs/rainforest/estado/<slug>.json`; veredito re-executável dos portões por `node scripts/portoes.cjs status <arquivo>` quando o estágio os declarar; identidade do entregável por `node scripts/recibo.cjs mostrar <slug>` quando existir recibo gravado; arquivos tocados por `git status --porcelain` e `git diff --stat` no worktree do slug.

- **D4 — a montagem mecânica é acionada por um ponto único: `scripts/estado.cjs marcar`, no sucesso de qualquer gate** (não só no estágio `fechar`). `handover.cjs` exporta uma função `montar(slug)` reusável por `require`, chamada por `estado.cjs` após gravar `status: "ok"`. A seção do modelo (≤10 linhas, "próximos passos + armadilhas") continua sendo texto que a sessão escreve à mão no arquivo — `estado.cjs marcar` avisa em stderr, não-bloqueante, quando ela está ausente ou mais velha que o snapshot mecânico atual, mas nunca a gera sozinho.

- **D5 — `handover.cjs status <slug>` devolve frescor por coerência de estágio, com exit code: `0` handover existe e o estágio gravado nele bate com `estagio-ativo.cjs`; `1` ausente ou divergente.** O limiar de idade (TTL, Q3) fica fora — `status` mede coerência, não idade em horas, até o dono fechar o número.

- **D6 — fronteira com o git: `.gitignore` ganha `.rainforest/handover/`**, seguindo o padrão path-a-path já em uso para `.rainforest/portaria/despachos.jsonl` e `.rainforest/colheita/` — nunca um `.rainforest/` genérico, que apagaria o manifesto versionado `agentes.json`.

- **D7 — hook de `SessionStart` interativo lista tarefas com handover coerente** (via `handover.cjs status`, D5) e oferece ao usuário escolher qual assumir. Ancorado no consolidado: "sessão interativa: hook de início lista tarefas com handover fresco e pergunta qual assumir — único ponto de escolha humana, e é seu por direito." Não depende de `regente.cjs` existir.

## Avaliado e descartado

- **Construir `regente.cjs`, mesmo em versão mínima de estágio único, nesta entrega.** Descartado. Dos dois pilares que o design original presumia como problema em aberto, os dois já têm solução na convenção do repositório: worktree por tarefa é a regra 11 universal hoje (9 worktrees vivos simultâneos, `scripts/limpar-worktrees.cjs` classificando e removendo); detecção de processo travado tem precedente direto em `estado.cjs`'s `em_voo` + `hooks/gate-agente-em-voo.cjs` — embora escopado a subagente despachado por sessão viva, não a processo `claude -p` headless externo (que não tem turno nem Stop hook). O que sobra de genuinamente novo — spawnar uma sessão headless completa para um estágio e aguardar o resultado — depende de uma decisão que ainda não existe: a forma do comando IMPLICA uma política de retry (Q1, sem fato novo), e construir agora decidiria Q1 por omissão. Herdaria também, sem alternativa, o vazamento de processo documentado na Issue #187 (aberta, outro dono, sem PR): o `rodarCli` de `hooks/lib/cli-externo.cjs` mata o processo que ele mesmo spawna, não a árvore inteira que o comando dispara — medido com 7 processos vivos 95,8h depois de uma execução real. Nenhum uso do fluxo hoje, incluindo o planejamento desta própria entrega, é headless — não há necessidade demonstrada que justifique o risco.

- **Reimplementar resolução de branch→estágio dentro de `handover.cjs`.** Descartado: `hooks/lib/estagio-ativo.cjs` já existe, é canônico e fail-closed. Reimplementar repetiria o defeito medido ao vivo em `hooks/lib/poda-estagio.cjs` — uma cópia divergente sem bateria que cobrisse o caso real de branch `fluxo/<slug>`.

## Fora de escopo

- **`regente.cjs`, em qualquer versão** — ver "Avaliado e descartado". Depende de Q1 fechada pelo dono (política de reprova, que decide a forma do comando) antes de fazer sentido desenhar de novo.
- **Conserto de `hooks/lib/poda-estagio.cjs`** — pertence ao fluxo 5 (dependência externa). Bloqueia a calibração de Q2 até ser corrigido; nenhuma tarefa deste plano toca esse arquivo.
- **Conserto de `hooks/lib/cli-externo.cjs` / Issue #187** (vazamento de processo no timeout de `rodarCli`) — dependência externa, outro dono, correção em avaliação. Nenhuma tarefa deste plano toca esse arquivo.
- **Compressão de contexto** — território do fluxo 5 (poda).
- **Memória semântica / consolidação de observações** — território do `memoria.cjs` (Q5, ver "Em aberto").
- **Multi-repo / multi-máquina.**

## Em aberto

- **Q1** — política de reprova de um futuro `regente.cjs` (parar na 1ª vs. N retries) — decisão do dono, sem fato novo; agora também pré-condição para o `regente.cjs` voltar a ser desenhado.
- **Q2** — limiar de contexto — decisão do dono, e **bloqueada** até o conserto de `hooks/lib/poda-estagio.cjs` (fluxo 5) ser feito e a medição real rodar algumas vezes.
- **Q3** — TTL do handover para injeção automática — decisão do dono, sem fato novo.
- **Q5** — formato exato do destilamento de encerramento para memória — decisão do dono; `memoria.cjs consolidar` existe mas não resolve o "quê" específico de fluxo.
