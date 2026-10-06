# Regras inteiras na conta de trabalho via session.append

## Objetivo
Na conta de trabalho (login org, `cc-plugin-sec-default` carregado), entregar a abertura
inteira (foco + 17 regras + memória) que hoje só chega pelo `prompt.compose` — barrado lá —
usando `$.session.append`, sem mexer no caminho da conta pessoal, onde o compose funciona e
aproveita o cache.

## Decisões fechadas
- **D1 — O append carrega a abertura inteira, o mesmo texto da seção do compose** (os dois
  geradores com `--destino mod`, a mesma montagem memoizada de `abertura-mod-puro.mjs`) —
  porquê: um gerador só, nada diverge entre as contas; o custo é uma escrita de ~12k tokens
  por sessão nova, e dentro da sessão a linha entra no prefixo cacheado da conversa.
- **D2 — Na conta de trabalho o núcleo do SessionStart clássico fica, duplicado** (~3 KB) —
  porquê: o filtro `semAbertura` do `classic.SessionStart` também é bypassed pelo
  sec-default (medido: `rainforest-mind: classic.SessionStart bypassed by
  cc-plugin-sec-default (tier user); beneath runs`), então o mod não consegue tirá-lo; cortar
  o núcleo do texto anexado quebraria D1. Falha aberta continua: se o append falhar, nada
  muda em relação a hoje.
- **D3 — Detecção pela política, não pela conta: o mod hooka `engine.create` e só usa o
  append quando `cc-plugin-sec-default` está em `e.plugins`** — porquê: é exatamente o módulo
  que barra o compose, tem contrato tipado (`EngineCreateInput.plugins`), e o evento não
  está na lista do sec-default (medido: `PLUGINS-VISTOS: cc-plugin-sec-default,rf-append-spike,rainforest-mind,...`).
  "O compose não rodou" não é observável a tempo: o compose dispara no primeiro request,
  depois do `session.start`. Custo aceito: hookar `engine.create` faz todo reload recarregar
  todos os módulos. Sem sec-default, o mod segue só no compose, como hoje.
- **D4 — Resume não anexa em dobro: antes de todo append, ler `$.session.messages()` e não
  anexar se a marca `rainforest-mind:abertura` já estiver no transcript; a marca é a primeira
  linha do texto anexado** — porquê: no `--resume` o `session.start` dispara de novo e a
  sonda duplicou o canário (2 linhas `isMeta`); `messages()` já enxerga o transcript
  carregado durante o `session.start` (medido: `MSGS-ANTES: 3 | CANARIOS-ANTES: 2`).
- **D5 — `/clear` reanexa no primeiro `prompt.submit` depois de `session.end` com
  `reason: 'clear'`, passando pela checagem de D4** — porquê: depois do `/clear` não há
  `session.start` (tipo: "no `session.start` fires for it"); `prompt.submit` não está na lista
  do sec-default e o tipo não restringe de onde `$.session.append` é chamado. Ainda não
  medido: a medição entra no critério do plano.
- **D6 — Compactação: na volta do `next(e)` do `session.compact`, se a marca não estiver nas
  mensagens devolvidas, reanexar** — porquê: não há evento "after" separado nem
  `classic.PostCompact` utilizável (bypassed); a regra cobre os dois casos — linha
  preservada literal (não faz nada) ou virada resumo (reanexa) — sem depender de medir qual.

## Avaliado e descartado
- **Tornar o rainforest mod da organização** (managed-settings.json local com
  `prependPlugins`, clone em `C:\ProgramData`) — funcionaria pela doc, mas troca o
  auto-update do GitHub por `git pull` elevado e põe o guarda também na conta pessoal;
  descartado pelo usuário em 2026-10-06 ("complica demais o que já temos"). Não reoferecer.
- **Console de admin do claude.ai** — valeria para a org TOTVS inteira.
- **`prompt.compose`/`prompt.section`/`prompt.context`** — bypassed pelo sec-default na conta
  de trabalho (sonda com 3 canários: `NONE`).
- **Detectar por `organizationType` no `.claude.json`** — formato sem contrato.
- **Detectar por `plugin.register` ou `next.trace`** — `plugin.register` está na lista do
  sec-default; `next.trace` só mostra elos abaixo de um hook que rodou, e o bypassed não roda.
- **Anexar sempre e desligar o compose** — perde o cache do system prompt na conta pessoal.
- **Tirar o núcleo do texto anexado** — faz o texto divergir do compose (contra D1).

## Fora de escopo
- O hook `sessionend-hook.ps1` que falhou com "Hook cancelled" na sonda 2 — de outro plugin,
  alheio a isto.
- `superpowers` habilitado em project settings sem estar instalado — alheio.
- Radar próprio vs. `cc-plugin-you-should-know` — ideia separada.

## Varredura
docs/rainforest/varredura/2026-10-06-regras-inteiras-conta-org.txt — só achou o commit do
handoff e a ideia de origem `regras-inteiras-barradas-pelo-sec-default-na-conta-org`
(que este fluxo colhe); nenhuma Issue, PR ou branch anterior. Não mudou a árvore.

## Em aberto
- Medição, no plano: D5 (append a partir de `prompt.submit` depois de `/clear`, no REPL
  interativo — as sondas foram só em `-p`) e o comportamento de D6 numa compactação real.
