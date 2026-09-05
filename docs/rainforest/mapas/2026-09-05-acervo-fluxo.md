# Acervo do fluxo — o que foi decidido e nunca terminou de ser entregue

Fatia: `docs/rainforest/planos/*.md`, `docs/rainforest/design/*.md`,
`docs/rainforest/estado/*.json` deste repositório. Método: `skills/arqueologia/SKILL.md`.
`docs/rainforest/mapas/COBERTURA.md` não tinha linha para esta fatia — extração
nova, não conferência.

**Hash-base:** `b31634bd3de54a48d08cfbead372ba31ebdacc94` (HEAD do worktree no
início do trabalho, batendo com a ponta de `origin/main` recebida no briefing).

## Aviso sobre a premissa do briefing

O briefing que originou este mapa presumia "~30 planos contra só 10 estados" como
"o coração da fatia" — um fluxo largo sem registro de estado. **Essa premissa não
bate com o repositório real, hoje:**

- `ls docs/rainforest/planos/*.md | grep -v README | wc -l` → **36**.
- `ls docs/rainforest/estado/*.json | wc -l` → **37**.
- Os 36 planos têm, cada um, um `docs/rainforest/estado/<slug>.json` companheiro
  (conferido nome a nome). O único estado "sobrando" é
  `docs/rainforest/estado/2026-08-24-camada-obsidian-para-o-harness.json`, que
  **não tem plano** — ver seção "Fora da tabela" no fim.

CONFIRMADO: a lacuna que o briefing esperava encontrar (design/plano sem estado)
não existe nesta base. O que existe — e é o achado real desta fatia — está
descrito abaixo: PRs com número desatualizado no estado, entregáveis que
trocaram de nome sem o plano ser corrigido, e dois designs decididos que nunca
viraram plano nenhum.

## Método usado nesta rodada

Para cada um dos 36 planos: (1) identifiquei o estado companheiro e o campo
`fechar.status`; (2) extraí de `arquivos:` das tarefas um conjunto de caminhos
representativos citados como entregáveis; (3) confirmei existência real com
`ls`/teste de caminho no worktree; (4) quando o estado citava um número de PR,
cruzei com `gh pr list --state merged` e, nos casos suspeitos, com
`git log --follow` para achados de rename ou PR fechada sem merge. Não executei
as baterias de teste de cada entrega (rodar ~36 suítes não cabe numa sessão) —
"entregáveis existem no repo" aqui significa **presença confirmada do
artefato**, não "a bateria daquela entrega passa hoje". Isso é declarado, não
escondido: é a fronteira da minha confiança.

## Tabela

| artefato | data | tem estado? | último estágio fechado | entregáveis existem no repo? | veredito | confiança |
|---|---|---|---|---|---|---|
| `docs/rainforest/planos/2026-08-13-orcamento-de-token-do-rainforest.md` | 2026-08-13 | sim — `estado/2026-08-13-orcamento-de-token-do-rainforest.json` | `fechar: ok`, PR #10 mesclada 2026-08-14 (`estado/...json:45`) | sim — `scripts/medir-injecao.py` existe | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-14-conferencia-de-entrega-em-paralelo.md` | 2026-08-14 | sim — `estado/2026-08-14-conferencia-de-entrega-em-paralelo.json` | `fechar: ok`, PR #13 mesclada 2026-08-17 (`:47`) | sim — `scripts/conferir-entrega.cjs`, `scripts/testa-conferir-entrega.sh` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-14-isencoes-do-radar-mecanizadas.md` | 2026-08-14 | sim — `estado/2026-08-14-isencoes-do-radar-mecanizadas.json` | `fechar: ok`, PR #12 mesclada 2026-08-17 (`:49`) | sim — `hooks/lib/contexto-sessao.cjs`, `hooks/foco-session-start.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-17-memoria-e-dados-do-rainforest.md` | 2026-08-17 | sim — `estado/2026-08-17-memoria-e-dados-do-rainforest.json` | `fechar: ok`, PR #22 mesclada 2026-08-20 (`:51`) | sim — `scripts/memoria.cjs`, `scripts/esquema-memoria.sql`, `scripts/observar.cjs` existem (11 caminhos citados, todos conferidos) | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-19-captura-por-projeto-e-virada-do-claude-mem.md` | 2026-08-19 | sim — `estado/2026-08-19-captura-por-projeto-e-virada-do-claude-mem.json` | `fechar: ok`, PR #24 mesclada 2026-08-20 (`:44`) | sim — `scripts/importar-claude-mem.cjs`, `hooks/memoria-session-start.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-20-statusline-no-plugin-e-temp-da-bateria.md` | 2026-08-20 | sim — `estado/2026-08-20-statusline-no-plugin-e-temp-da-bateria.json` | `fechar: ok`, PR #40 mesclada 2026-08-22 (`:48`) | sim — `statusline/statusline.py`, `statusline/statusline-jornada.sh`, `scripts/instalar-statusline.sh` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.md` | 2026-08-21 | sim — `estado/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.json` | `fechar: ok` (campo `pr` vazio no estado; confirmado PR #46, commit `40e3f3b`, mesclada 2026-08-22 — `:95`) | sim, com nome trocado — `hooks/gate-worktree.cjs`, `scripts/estado.cjs` existem; **mas** `scripts/conferir-esteira.cjs`, citado como entregável da tarefa 5 (`planos/...md:68,136`), está AUSENTE hoje — `git log --follow -M` mostra que a própria PR #46 o renomeou para `scripts/conferir-fluxo.cjs`, que existe | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-22-agente-arqueologo.md` | 2026-08-22 | sim — `estado/2026-08-22-agente-arqueologo.json` | `fechar: ok`, PR #52 mesclada 2026-08-23 (`:104`) | sim — `scripts/triagem.cjs`, `skills/arqueologia/SKILL.md`, `agents/arqueologo.md`, `docs/rainforest/mapas/COBERTURA.md` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-22-atualizar-cli-e-aviso-de-versao.md` | 2026-08-22 | sim — `estado/2026-08-22-atualizar-cli-e-aviso-de-versao.json` | `fechar: ok`, PR #44 mesclada 2026-08-22 (`:33`) | sim — `scripts/atualizar-cli.sh`, `statusline/statusline-versao.sh`, `statusline/testa-statusline-versao.py` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-24-auditor-de-api-owasp.md` | 2026-08-24 | sim — `estado/2026-08-24-auditor-de-api-owasp.json` | `fechar: ok`, PR #87 mesclada 2026-08-25 (`:85`) | sim, mas **consolidado** — `agents/auditor-de-api.md` e `scripts/testa-auditor-de-api.sh` (entregáveis citados nas tarefas 1–3, `planos/...md:17,30`) nunca existiram como arquivos próprios (`git log --all` para os dois nomes não retorna nenhum commit); a PR #87 juntou este plano com `2026-08-25-auditor-de-seguranca-tres-reguas` num único agente, `agents/auditor-de-seguranca.md`, cuja "Régua 2" (linhas 398–406) é literalmente a OWASP API Security Top 10 que este plano pediu | entregue (consolidado em outro artefato) | CONFIRMADO |
| `docs/rainforest/planos/2026-08-24-orcamento-medida-estavel-e-folga.md` | 2026-08-24 | sim — `estado/2026-08-24-orcamento-medida-estavel-e-folga.json` | `fechar: ok`, PR #85 mesclada 2026-08-25 (`:96`) | sim — `hooks/lib/folga.cjs`, `scripts/orcamento.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-24-skills-finas-com-references.md` | 2026-08-24 | sim — `estado/2026-08-24-skills-finas-com-references.json` | `fechar: ok`, PR #80 mesclada 2026-08-24 (`:102`) | sim — `skills/rainforest-mind/references/regra-01.md` até `regra-17.md` e `scripts/medir-skill.cjs` existem (18 caminhos citados, todos conferidos) | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-25-auditor-de-seguranca-tres-reguas.md` | 2026-08-25 | sim — `estado/2026-08-25-auditor-de-seguranca-tres-reguas.json` | `fechar: ok`, PR #87 mesclada 2026-08-25 (`:71`) | sim — `agents/auditor-de-seguranca.md` existe (692 linhas, 3 réguas confirmadas no corpo) | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-25-catalogo-de-ferramentas.md` | 2026-08-25 | sim — `estado/2026-08-25-catalogo-de-ferramentas.json` | `fechar: ok`, PR #116 mesclada 2026-08-26 (`:78`) | sim — `scripts/ferramentas.cjs`, `hooks/ferramentas-consulta.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-25-regua-do-batedor-enxertar.md` | 2026-08-25 | sim — `estado/2026-08-25-regua-do-batedor-enxertar.json` | `fechar: ok`, PR #109 mesclada 2026-08-25 (`:69`) | sim — `vigias/fila-de-repos.jsonl`, `vigias/livro-de-repos.md`, `vigias/batedor-repos.md`, `scripts/conferir-livro-de-repos.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-26-backup-do-sentinela.md` | 2026-08-26 | sim — `estado/2026-08-26-backup-do-sentinela.json` | `fechar: ok`, PR #122 mesclada 2026-08-26 (`:110`) | sim — `vigias/run-vigia.ps1`, `vigias/backup-estado.ps1`, `scripts/foco.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-26-catraca-por-relogio.md` | 2026-08-26 | sim — `estado/2026-08-26-catraca-por-relogio.json` | `fechar: ok`; campo `pr` do estado diz **"a abrir"** (`:71`), desatualizado — CONFIRMADO PR #126 mesclada 2026-08-26 (commit `fix/121-catraca-por-relogio`) | sim — `scripts/conferir-mutacao.cjs` existe | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-26-raiz-do-erros-md.md` | 2026-08-26 | sim — `estado/2026-08-26-raiz-do-erros-md.json` | `fechar: ok`; campo `pr` do estado diz **"a abrir"** (`:72`), desatualizado — CONFIRMADO PR #123 mesclada 2026-08-26 | sim — `vigias/run-vigia.ps1`, `scripts/testa-erros-md-raiz.sh` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-28-ciclo-por-maquina-e-ok-com-evidencia.md` | 2026-08-30 | sim — `estado/2026-08-28-ciclo-por-maquina-e-ok-com-evidencia.json` | `fechar: ok`; estado cita **PR #132** (`:78`), mas essa PR está **CLOSED sem merge** (`gh pr view 132` → `state: CLOSED, mergedAt: null`) — era o mesmo branch `fluxo/ciclo-por-maquina` contra uma base intermediária; o merge real para `main` é a **PR #134**, mesmo diff (`scripts/estado.cjs`, `scripts/testa-estado.sh`), mesclada 2026-08-31 | sim — `scripts/estado.cjs`, `scripts/testa-estado.sh` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-28-memoria-indice-vivo-e-consolidacao.md` | 2026-08-30 | sim — `estado/2026-08-28-memoria-indice-vivo-e-consolidacao.json` | `fechar: ok`, PR #133 mesclada 2026-08-31 (`:86`) | sim — `scripts/esquema-memoria.sql`, `hooks/lib/memoria-sessao.cjs`, `scripts/saude.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-28-ponte-bloco-do-projeto-e-integracoes.md` | 2026-08-31 | sim — `estado/2026-08-28-ponte-bloco-do-projeto-e-integracoes.json` | `fechar: ok`, PR #135 mesclada 2026-09-01 (`:187`) | sim — `scripts/ponte.cjs`, `hooks/lib/ponte-corpo.cjs`, `skills/ponte/SKILL.md`, `commands/ponte.md`, `relatorios/2026-08-31-handover-fluxos.md` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-08-31-fluxo-5-fase-0-poda.md` | 2026-08-31 | sim — `estado/2026-08-31-fluxo-5-fase-0-poda.json` | `fechar: ok`, PR #136 mesclada 2026-09-01 (`:113`) | sim — `scripts/poda.cjs`, `hooks/lib/poda-dados.cjs`, `hooks/lib/poda-estagio.cjs`, `scripts/relatorio-poda.cjs` existem | entregue (só a fase 0; ver nota fora da tabela sobre as fases 1/2) | CONFIRMADO |
| `docs/rainforest/planos/2026-09-02-fluxo-6-portoes.md` | 2026-09-01 | sim — `estado/2026-09-02-fluxo-6-portoes.json` | `fechar: ok`; campo `pr` vazio no estado (`:85`) — CONFIRMADO PR #147 mesclada 2026-09-02 | sim — `scripts/portoes.cjs` existe | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-09-02-fluxo-7-recibo.md` | 2026-09-02 | sim — `estado/2026-09-02-fluxo-7-recibo.json` | `fechar: ok`; campo `pr` vazio no estado (`:98`) — CONFIRMADO PR #172 mesclada 2026-09-03 | sim — `scripts/recibo.cjs` existe | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-09-03-guardas.md` | 2026-09-03 | sim — `estado/2026-09-03-guardas.json` | `fechar: ok`, PR #183 mesclada 2026-09-04 (`:382`) | sim — `hooks/lib/cwd-efetivo.cjs`, `hooks/gate-staging-total.cjs`, `hooks/portaria.cjs`, `scripts/limpar-worktrees.cjs`, `scripts/backup.cjs`, `scripts/fechar-issue.cjs`, `hooks/gate-fechar-issue.cjs` existem (7 de 16 grupos de tarefas conferidos) | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-09-04-lote-4-guardas.md` | 2026-09-04 | sim — `estado/2026-09-04-lote-4-guardas.json` | `fechar: ok`, PR #188 mesclada 2026-09-05 (`:161`; o campo `pr` guarda a URL completa, não só o número) | sim — `hooks/gate-publicacao-destino.cjs`, `scripts/conferir-versao.cjs`, `scripts/limpar-branches.cjs`, `hooks/gate-agente-em-voo.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/2026-09-04-nao-mente.md` | 2026-09-04 | sim — `estado/2026-09-04-nao-mente.json` | `fechar: ok`, PR #186 mesclada 2026-09-05 (`:99`) | sim — `hooks/gate-git-verificacao.cjs`, `agents/executor.md` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/decisao-que-evapora-na-esteira.md` | 2026-08-13 | sim — `estado/decisao-que-evapora-na-esteira.json` | `fechar: ok`; campo `pr` vazio no estado (`:43`) — CONFIRMADO PR #9 mesclada 2026-08-14 | sim, com nome trocado — `scripts/conferir-esteira.cjs` (o entregável literal citado nas tarefas, `planos/...md:26,46,61`) está AUSENTE; `git log --follow -M` traça a cadeia de rename até `scripts/conferir-fluxo.cjs`, que existe hoje | entregue | CONFIRMADO |
| `docs/rainforest/planos/divergir-como-workflow.md` | 2026-08-22 | sim — `estado/divergir-como-workflow.json` | `fechar: ok`, PR #59 mesclada 2026-08-23 (`:148`) | sim — `workflows/divergir-frames.js`, `scripts/divergencias.cjs`, `skills/divergir/SKILL.md` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/fluxo-11-conselho.md` | 2026-08-31 | sim — `estado/fluxo-11-conselho.json` | `fechar: ok`, PR #137 mesclada 2026-09-01 (`:133`) | sim — `scripts/conselho.cjs`, `scripts/fixtures/conselho/membro-ok.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/fluxo-12-regua.md` | 2026-09-04 | sim — `estado/fluxo-12-regua.json` | `fechar: ok`, PR #177 mesclada 2026-09-04 (`:61`) | sim — `skills/regua/SKILL.md`, `docs/rainforest/criterios/fluxo-12-regua.md` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/fluxo-9-portaria.md` | 2026-08-30 | sim — `estado/fluxo-9-portaria.json` | `fechar: ok`; campo `pr` vazio no estado (`:120`) — CONFIRMADO PR #141 mesclada 2026-09-02 | sim — `hooks/portaria.cjs`, `hooks/lib/estagio-ativo.cjs`, `.rainforest/agentes.json` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/partir-elaboracao-regra-12.md` | 2026-08-26 | sim — `estado/partir-elaboracao-regra-12.json` | `fechar: ok`, PR #119 mesclada 2026-08-26 (`:70`) | sim — `skills/rainforest-mind/references/regra-12.md`, `skills/rainforest-mind/references/regra-12-acervo.md` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/segunda-opiniao-cross-model.md` | 2026-09-01 | sim — `estado/segunda-opiniao-cross-model.json` | `fechar: ok`, PR #140 mesclada 2026-09-01 (`:111`) | sim — `hooks/lib/cli-externo.cjs`, `scripts/segunda-opiniao.cjs` existem | entregue | CONFIRMADO |
| `docs/rainforest/planos/trava-de-cwd.md` | 2026-08-26 | sim — `estado/trava-de-cwd.json` | `fechar: ok`, PR #128 mesclada 2026-08-26 (`:66`) | sim — `hooks/gate-repo-alheio.cjs` existe | entregue | CONFIRMADO |
| `docs/rainforest/planos/vigias.md` | 2026-09-01 | sim — `estado/vigias.json` | `fechar: ok`, PR #150 mesclada 2026-09-02 (`:91`) | sim — `vigias/erros.ps1`, `scripts/conferir-encoding.cjs` existem; **mas** a tarefa 12 (`planos/vigias.md:221`, "arquivos: (nenhum — altera o Agendador de Tarefas do Windows, nao o repositorio)") não deixa nenhum artefato no repo para conferir | entregue no repo; a tarefa 12 é LACUNA — não dá para confirmar por `ls` se a tarefa de máquina foi de fato executada | CONFIRMADO (repo) / LACUNA (tarefa 12) |

**Contagem:** 36 arquivos em `docs/rainforest/planos/*.md` (excluindo `README.md`)
→ 36 linhas na tabela acima. Bate.

## O que está de fato inacabado

Nenhuma das 36 linhas fechou como `parcial`, `parado`, `abandonado` ou
`nao-da-para-dizer` — todas fecharam `entregue`, com pelo menos um caminho
citável e existente. Isso não é isenção de escrutínio: é o resultado de
conferir, plano a plano, o estado, um conjunto de entregáveis representativos
e, nos sete casos em que o número de PR do estado não batia com a realidade
(PR fechada sem merge, PR faltando, ou "a abrir" desatualizado), o
`gh pr list`/`git log` real. Esta seção fica **vazia por achado, não por
omissão** — é exatamente o tipo de afirmação que a régua de "silêncio não
distingue" pede para registrar.

O que **de fato ficou pendurado** nesta base não são planos — são **designs
que nunca chegaram a virar plano**, e por isso não entram na tabela acima (que
é por arquivo de `planos/`). Registro aqui porque respondem à pergunta da
fatia mais diretamente que qualquer linha `entregue`:

1. **`docs/rainforest/design/2026-08-24-camada-obsidian-para-o-harness.md`**
   (2026-08-24) — design aprovado (`estado/2026-08-24-camada-obsidian-para-o-harness.json`,
   `design.status: "aprovado"`), mas `plano.status`, `executar`, `revisar`,
   `verificar` e `fechar` continuam `"pendente"` e **não existe**
   `docs/rainforest/planos/2026-08-24-camada-obsidian-para-o-harness.md`.
   Decidido, nunca planejado. CONFIRMADO.

2. **`docs/rainforest/design/2026-08-28-contrato-de-territorio.md`** (2026-08-28)
   — o próprio texto diz "Status: rascunho — colher depois dos fluxos 1–3"
   (`design/2026-08-28-contrato-de-territorio.md:8`). Os fluxos 1, 2 e 3 (linhas
   19, 20 e 21 da tabela acima) já fecharam `entregue` há dias — a precondição
   que o design citou está satisfeita, e ainda assim não existe plano nem
   estado para este design. CONFIRMADO que não foi colhido; INFERIDO que
   poderia ser, dado o texto do próprio design.

3. **`docs/rainforest/design/fluxo-8-design-handover-regente.md`** e
   **`docs/rainforest/design/fluxo-10-design-critico.md`** — nenhum dos dois
   tem plano nem estado. O fluxo 10 se declara "rascunho — Q1–Q4 abertas"
   (`fluxo-10-design-critico.md:5`), então nem chegou a aprovado; o fluxo 8 diz
   só "Status: design". Nenhuma Issue nem plano os retoma no acervo atual.

4. **`docs/rainforest/design/adendo-fluxo-5-deepagents.md`** — conteúdo é
   explicitamente fase 1/2 do fluxo 5; a fase 0 (linha 22 da tabela) fechou
   `entregue`, mas a "Fora de escopo desta fase (reafirmado, não é omissão)"
   (`docs/rainforest/planos/2026-08-31-fluxo-5-fase-0-poda.md:42`) nunca ganhou
   plano próprio de continuação.

Todos os quatro pontos acima são `INFERIDO`+`CONFIRMADO` misto: confirmado que
não há plano/estado para eles; inferido (não confirmado com o usuário) que
"deveriam" ter virado plano — pode ser decisão deliberada de backlog, não
descuido. Não tenho como saber qual dos dois sem perguntar.

## Fora da tabela

- `docs/rainforest/design/LEIA-PRIMEIRO-CONSOLIDADO-v2.md` é índice, não decisão
  — não entra.
- `docs/rainforest/planos/README.md` é o índice da pasta, excluído pelo próprio
  critério da fatia.
- `docs/rainforest/estado/2026-08-24-camada-obsidian-para-o-harness.json` é o
  único estado sem plano companheiro — coberto no item 1 acima.
