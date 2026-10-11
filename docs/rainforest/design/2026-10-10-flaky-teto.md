# Estado flaky e teto de despachos no executar

## Objetivo
Gate que falha por acaso não decide a entrega, e fluxo não gasta despacho de
agente sem fim. Enxerto E da comparação com o orquestrador do plugin
`wildz-data` (Rafael Siqueira): `skills/execute/SKILL.md` §9 (flaky-retry-once
e estado `flaky`) e `hooks/ceiling-check.sh` (teto de despachos).

## Decisões fechadas
- **D1 — Um fluxo só, duas partes independentes no plano (flaky e teto)** — porquê: pequenas, nasceram da mesma ideia e tocam o mesmo `estado.cjs`; dois PRs disputariam o arquivo.
- **D2 — Serve à janela principal girando `executar` → `revisar` no run autônomo, não ao usuário na mão** — porquê: é onde bateria instável e laço sem fim custam caro sem ninguém olhando.
- **D3 — Modelo de ameaça: protege contra (a) bateria instável aprovar ou reprovar entrega por acaso e (b) fluxo gastar despacho sem fim; não protege contra bateria determinística que mede a coisa errada (é da catraca de mutação) nem contra agente despachado fora de fluxo (é da portaria)** — porquê: o que fica fora é critério de parada do revisor, não buraco.
- **D4 — A nova tentativa mora em script, nunca em prosa: um `scripts/rodar-gate.cjs` para a bateria do critério e a repetição dentro do `conferir-mutacao.cjs`; repete só o que falhou, uma vez, e grava o flake no estado do fluxo** — porquê: retry em prosa é a janela decidindo o próprio veredito, o que a catraca existe para impedir.
- **D5 — Teto de despachos num hook novo `PreToolUse` com matcher `Task|Agent`, separado da portaria; conta despachos do fluxo ativo resolvido pela branch (mesmo resolvedor da portaria), nega ao bater o teto, e fora de fluxo passa sem contar** — porquê: a portaria passou a só registrar (#264) e não volta a barrar; o teto é portão por definição.
- **D6 — Vira `flaky` terminal quando o mesmo gate (tarefa + gate) só passa na nova tentativa em 2 voltas seguidas do laço: o `executar` fecha com o status novo `flaky`, distinto de `reprovado`, que não consome `TETO_TENTATIVAS` e sobe ao usuário; flake de uma volta só fica gravado e o laço segue** — porquê: o teto do laço é 3, esperar 3 faria `flaky` nunca chegar antes do teto.
- **D7 — Aprovação da catraca também se confirma: `conferir-mutacao` com bateria vermelha após a mutação roda a bateria mutada de novo e só sai 0 com vermelho duas vezes** — porquê: vermelho por acaso é aprovação falsa, o lado (a) de D3; custa uma corrida a mais só nas aprovações.
- **D8 — Ganham nova tentativa: bateria do critério com exit ≠ 0; catraca com exit 2 (verde pós-mutação) e 4 (íntegro vermelho). Nunca 1, 3, 5 e 69 (uso, declaração, corte de shell, ambiente)** — porquê: só se repete o que o acaso pode ter produzido.
- **D9 — Teto padrão de 40 despachos por fluxo; o plano declara outro com `teto-despachos: N` no cabeçalho** — porquê: 40 fica acima do maior fluxo real medido (36, `zerar-issues-5`; mediana 9, p90 22 em 82 worktrees do `despachos.jsonl`); teto derivado das tarefas acoplaria o hook ao parser do plano sem ganho medido.
- **D10 — Conta todo despacho de agente desde o `iniciar` do fluxo, em todos os estágios e de qualquer tipo** — porquê: o orçamento é do fluxo, e a medição de D9 contou assim.
- **D11 — O contador mora fora do repo, em `<dados>/fluxos/<slug>/despachos.json`, gravado sob a trava de `hooks/lib/trava-jsonl.cjs`; os flakes e o `liberar` ficam no estado versionado** — porquê: hook a cada despacho sujaria o diff e correria contra commits no mesmo worktree; flakes são poucos e são rastro de auditoria.
- **D12 — Contador ou teto declarado ilegível, com fluxo ativo resolvido: o hook nega com motivo (fail-closed)** — porquê: contador corrompido lido como 0 zera o teto em silêncio (`ceiling-check.sh`, `is_uint`).
- **D13 — Cada `liberar` do teto destrava +10 despachos e grava o motivo (a palavra do usuário)** — porquê: `liberar` que desarma para sempre já foi achado de revisão no `TETO_TENTATIVAS`; 10 cobre uma volta completa do laço com folga.

## Avaliado e descartado
- Contador de despachos dentro do estado JSON versionado: descartado por D11 — gravação a cada despacho no arquivo que o agente também commita.
- Retry instruído só na skill `executar`: descartado por D4 — a janela redigiria o próprio veredito.
- Teto de tempo de parede (`max_wall_minutes` do Rafael): fora — nenhum incidente medido de fluxo longo demais; o caro medido é despacho.
- Reaproveitar a portaria para negar: descartado por D5 — reverteria a decisão da #264.

## Fora de escopo
- Leitor/rotação do `despachos.jsonl` da portaria (ideia `despachos-jsonl-rotacao-e-cli`, #276).
- DAG com `touches` e retomada por sentinela (ideia `executar-dag-touches-e-retomada`).
- Concorrência máxima de tarefas paralelas (`max_parallel_tasks`).

## Varredura
docs/rainforest/varredura/2026-10-10-flaky-teto.txt — termos `flaky`, `teto-de-despachos`, `despachos`, `instavel`, `intermitente`, `teto de despacho`. Achou o laço (#484) com `TETO_TENTATIVAS = 3`, que fez o teto daqui contar despachos e não voltas; a portaria que já registra despachos sem slug e sem leitor (#264, #276), que levou o contador para arquivo próprio (D11); e as Issues de bateria intermitente na CI (#475, #342, #273), que são o caso que D6–D8 tratam. Nenhuma Issue aberta sobre flaky ou teto.

## Em aberto
- Nada.
