# Enxertar o terminal-desk no mod do rainforest

## Objetivo
Trocar a faixa acima do prompt (foco, fluxos, Q, relógio), que o usuário ignora, pela barra
de sessão do terminal-desk (GraniteAI, MIT) e pelo pane `/painel`, adaptados ao rainforest:
português, relógio ⏰ mantido, "Left undone" checado contra a regra 12.

## Decisões fechadas
- **D1 — Enxerto dentro do `hooks/mod.tsx`, uma faixa só** — porquê: dois mods escrevendo
  em `AbovePrompt` sem chamar `next(e)` se tapam (desk `register.tsx:635`, rainforest
  `mod.tsx:251`); um dono do slot acaba com a disputa. Código de origem:
  terminal-desk 0.2.1, `hooks/register.tsx`, licença MIT, titular `ClariSortAi` (GraniteAI é o site de distribuição; LICENSE do zip) — crédito em `NOTICE` (ou
  `THIRD_PARTY.md`) com o texto da licença e comentário de cabeçalho no arquivo enxertado.
- **D2 — Sai da faixa: foco e linhas Q** — porquê: o usuário ignora o foco ("eu sempre ignoro
  o foco e nem ligo pra ele", 2026-10-07) e escolheu tirar as Q. O código que só servia a
  isso (`extrairQs`, `montarLinhas`, assinatura de esconder, campo foco do desenho) sai —
  YAGNI; `faixa-dados.cjs` continua servindo os fluxos (D4).
- **D3 — O relógio ⏰ vira uma figura da barra** — porquê: é a única parte da faixa que ele
  manteve; timers, `relogio-sessoes.cjs`, `jornada.cjs` e a nota da regra 8 no
  `prompt.submit` ficam como estão (Issues #386, #387, #388 já fechadas sobre eles).
- **D4 — "Fluxos em curso" vira um painel no pane `/painel`**, fora da barra — porquê: útil
  com sessões paralelas, não precisa ocupar a linha.
- **D5 — Entram da barra/pane do desk: estado (trabalhando/pronto), tokens, custo, contexto
  0–100, cache quente/frio com estimativa, ferramentas/min, subagentes, turnos, erros; pane
  com contexto por fatia, cache, subagentes, custo** — porquê: escolha do usuário (Q3 da
  rodada de 2026-10-07). Barra de subagente quando o transcript dele está em tela também
  entra.
- **D6 — `note_assumption` e a seção de system prompt dele ficam fora** — porquê: manda
  assumir e registrar, a regra 16 manda perguntar; e o `prompt.compose` é bypassed pelo
  `cc-plugin-sec-default` na conta de trabalho (design `2026-10-06-regras-inteiras-conta-org`,
  sonda com 3 canários: `NONE`). Sem ele, o enxerto não depende de compose.
- **D7 — "Deixado para depois" (Left undone) entra adaptado** — porquê: Q3 da primeira rodada.
  (a) varredura de frases em português e inglês ("por enquanto", "não rodei", "fica para
  depois", "próxima fase", "placeholder"…); (b) marcadores em arquivo como no original
  (TODO, FIXME, skip); (c) o checker Haiku recebe o pedido, o fim do relato **e a lista de
  ferramentas do turno com as falhas** (nome + deny/erro) — porquê: regra 12, relato não
  prova; pega "feito" sem comando que o sustente e item que virou "próxima fase". Roda em
  turno com 5+ ferramentas; `/painel checar desligar` o desliga. Rascunho do "Faz agora"
  em português, nunca enviado sozinho.
- **D8 — Comando `/painel`** — porquê: tudo do rainforest é em português; não colide com
  o `/desk` original. Subcomandos: `esconder`, `mostrar`, `cache 5m|1h`,
  `checar ligar|desligar`.
- **D9 — Esconder é alternância explícita (`/painel esconder` / `mostrar`)** — porquê: a
  barra muda a cada segundo; esconder por assinatura de conteúdo a faria voltar sempre. O
  botão "esconder" e o atom `faixaOculta` saem.
- **D10 — Vale para as duas contas, com falha aberta** — porquê: o usuário quer as duas
  ("1 para as duas, tem outra sessão ajustando na de trabalho"). O enxerto não usa
  `prompt.compose` (D6); o que o sec-default barrar na conta de trabalho (`ui.render`,
  `$.model.complete`, `$.session.usage` — ainda não medido) apaga só a peça afetada, nunca
  quebra a sessão. A medição na conta de trabalho é critério do `verificar`.
- **D11 — Não tocar `hooks/register.ts` nem `abertura-mod-puro.mjs`** — porquê: a sessão
  paralela do worktree `regras-inteiras-conta-org` edita esses dois; o enxerto mora só em
  `mod.tsx`, módulos puros novos e `types`. Conflito de merge fica restrito ao CHANGELOG e
  à versão.
- **D12 — Lógica pura testável fora do engine** — porquê: padrão do repo (`faixa-puro.mjs`,
  `relogio-puro.mjs` com baterias). Cálculos do desk (cache, fatias, deferimento, ritmo)
  vão para um `painel-puro.mjs` com bateria; `mod.tsx` só liga eventos.
- **D13 — Painel "Mapa da sessão" no `/painel`** (Builder Map do guia de mods, Actionable AI) — porquê: pedido do usuário na mesma rodada (2026-10-07). Lista arquivos escritos, skills usadas, subagentes e serviços (MCP por nome de servidor), atualizado a cada ferramenta.
- **D14 — Desvio medido contra a soma dos `arquivos:` de todas as tarefas do plano do fluxo deste worktree; fora de fluxo, o mapa só lista** — porquê: o estado do fluxo registra o estágio, não a tarefa em curso (lido em `docs/rainforest/estado/*.json`); o plano é o único lugar com arquivos declarados (`skills/plano/SKILL.md:61-66`).
- **D15 — Arquivo fora do plano: linha vermelha no painel e um toast por arquivo, nada vai ao modelo** — porquê: o aviso é para o usuário; avisar o modelo é outra regra e outro custo.
- **D16 — "Tocar" = escrever por Edit, Write ou NotebookEdit** — porquê: ler fora do plano é investigação normal; escrita via Bash não é detectável com segurança e fica fora, dito no próprio painel.

## Avaliado e descartado
- **Rodar o terminal-desk como plugin separado ao lado do rainforest** — os dois desenham
  `AbovePrompt` sem `next(e)` (lido nos dois fontes): um some.
- **Manter a varredura de frases só em inglês** — as sessões dele são em português; a regex
  original (`register.tsx:87`) quase nunca acenderia.
- **Checker lendo só o relato** (como no original) — mede o que o agente admite, não o que
  houve; contra a regra 12.

## Fora de escopo
- Investigar por que o foco não serve a ele (Q4 da primeira rodada: depois, vendo o que ele
  passa a olhar na barra nova).
- O mecanismo do foco em si (FOCO.md, radar da regra 3) — só sai da faixa.
- Caliper — plantado (`caliper-medir-quais-regras-pagam`): não é mod, é CLI Python e custa N execuções do agente.
- Exportar o mapa (`/map`, Mermaid no navegador) — plantado como HTML (`mapa-da-sessao-exportado-em-html`): exige gravar arquivo e abrir navegador.
- Fazer o sec-default deixar passar eventos na conta de trabalho — é da sessão paralela.

## Varredura
docs/rainforest/varredura/2026-10-07-desk-no-mod.txt — nada sobre terminal-desk nem "left
undone"; achou a história da faixa (PRs #383, #384, #389, #390; Issues #386, #387, #388,
todas fechadas) e as ideias de origem dela (`mods-faixa-foco-e-checkpoint`,
`mods-jornada-e-janela-parada-por-relogio`). Mudou: o relógio e seus consertos ficam
intactos (D3), e a remoção mira só no que servia a foco e Q (D2).

## Em aberto
- Se `ui.render`, `$.model.complete` e `$.session.usage` rodam na conta de trabalho — fato a
  medir no `verificar` (D10), não decisão.
