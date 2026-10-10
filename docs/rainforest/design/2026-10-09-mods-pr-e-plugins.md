# Mods do painel de PR e plugins em dia dentro do rainforest

## Objetivo

Trazer para o mod do rainforest-mind dois mods prototipados e provados em 2026-10-09 (`~/.claude-personal/dev-mods/2fa5b85b-bd65-4f9c-9b7b-9c53e2cc811d/`): um painel que acompanha o PR do fim ao merge e acorda o Claude nas viradas, e uma atualização dos plugins que roda dentro da sessão. Origem: o painel e o mod de atualização que o Rafael mostrou no WhatsApp em 2026-10-09 10:27.

## Decisões fechadas

- **D1 — Serve a ele e ao Claude no fim do fluxo, do `gh pr create` ao merge; o `plugins-em-dia` serve a toda sessão, nas duas contas** — porquê: é o momento em que a espera de máquina parece travamento (memória "espera de máquina não devolve a vez"); o plugin está nas duas contas, então o mod também está.
- **D2 — O painel de PR é um pane próprio, separado do `/painel`** — porquê: abre sozinho e vive enquanto o PR vive; dentro do `/painel` sequestraria a tela de contexto e custo.
- **D3 — O painel mostra o nível de detalhe do painel do Rafael**: branch → base, autor, idade da última atualização; transições como antes → depois; se dá para mergear e o motivo (`mergeable`, `mergeStateStatus`); review threads abertas × total; reviews, inclusive de bot; "quieto há N min"; ícone por tipo de evento (↑ push, + comentário, × bloqueio, ✓ ok, ◐ rodando) — porquê: pedido dele ao comparar os dois prints. Fato conferido: `gh pr view --json` entrega `mergeable`, `mergeStateStatus`, `baseRefName`, `headRefName`, `author`, `updatedAt` e `latestReviews`, mas **não** `reviewThreads`, que vem de `gh api graphql` (`reviewThreads{totalCount nodes{isResolved}}`), uma segunda chamada por consulta.
- **D4 — Nas viradas decisivas (checks terminaram, review pediu mudança, conflito, merge), o mod grava uma nota na conversa e pode acordar a sessão, só para PR desta sessão** — porquê: o Claude age sem ele vigiar; PR acompanhado à mão por `/pr` só mostra, para não gastar token sem pedido.
- **D5 — Acordado, o Claude age assim: CI verde e PR mergeável → mergeia (autorização da memória "run autônomo"); CI vermelha → investiga e conserta na própria branch; review pedindo mudança ou conflito → resume e traz para ele, sem alterar nada** — porquê: os dois primeiros casos são o roteiro atual; os dois últimos envolvem opinião de outra pessoa ou escolha dele.
- **D6 — "PR desta sessão" = PR que esta sessão criou (`gh pr create` observado) ou PR aberto de branch `fluxo/*` na abertura da sessão (retomada)** — porquê: na retomada o PR é do fluxo e a sessão é a continuação dele; outra branch só mostra.
- **D7 — A nota entra sempre na conversa (`$.session.append`, user, meta); a sessão só é acordada (`$.prompt.submit`) se estiver parada e o PR ficar quieto 3 min depois da virada** — porquê: os 3 min evitam acordar no meio da troca de estado da CI; sessão parada evita interromper ele em outra coisa.
- **D8 — O `plugins-em-dia` só recarrega sozinho (`/reload-plugins`) depois de medida, na conta de trabalho, a ideia `append-conta-org-perde-flag-no-reload`; se o risco se confirmar, ele avisa em vez de recarregar** — porquê: recarregar e perder a abertura da conta de trabalho em silêncio é pior que um aviso.
- **D9 — A lista de plugins a atualizar é opção (`userConfig`), com padrão rainforest-mind e apontamento-horas** — porquê: as duas contas têm plugins diferentes; hoje a lista mora só no perfil do PowerShell.
- **D10 — Decisões técnicas**: consulta a cada 60 s; a linha "sem checks" logo após push some (é o intervalo antes da CI registrar); aviso nativo (`$.ui.notify`) mantido nas viradas; lógica pura em `*-puro.mjs` com testes no padrão `hooks/mod-*.test.tsx`; módulo próprio importado por `hooks/mod.tsx`, como o `register.ts` da abertura; versão 1.54.0 (MINOR, capacidade nova) — porquê: segue o padrão do mod que já existe.

## Avaliado e descartado

- **Proxy de contas (CLIProxyAPI) para balancear as duas assinaturas**: descartado na conversa de 2026-10-09; a troca de conta vai como fluxo próprio, trocando a credencial que o Claude Code oficial lê (medido: a sessão relê o `.credentials.json` sem reiniciar).
- **Painel de PR como seção do `/painel`**: ver D2.

## Fora de escopo

- Troca automática de conta pelo uso — fluxo próprio, depois da #456.
- Os buracos do gate de staging da Issue #456 — fluxo próprio, antes da troca de conta.
- GitLab (`glab`): o painel do Rafael é de MR do GitLab; aqui só GitHub (`gh`), que é onde estão os repositórios dele.

## Varredura

docs/rainforest/varredura/2026-10-09-mods-pr-e-plugins.txt — nenhuma Issue, PR ou branch faz painel de PR ou atualização de plugin dentro da sessão; o `/painel` (PR #422) é o mod vizinho, o que levou à D2. A ideia plantada `append-conta-org-perde-flag-no-reload` mostra que `/reload-plugins` pode fazer a conta de trabalho perder o append da abertura, o que levou à D8.

## Em aberto

- Medir a ideia `append-conta-org-perde-flag-no-reload` (o `ao_colher` dela) na conta de trabalho: é tarefa do plano e decide se a D8 recarrega ou avisa.
