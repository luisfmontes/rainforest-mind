# Batedor — ronda de 2026-10-09

**Âncora:** 3 problemas escolhidos de 162 ideias abertas (159 ficaram de fora). Fila de repos: 0 candidatos, 0 recusados — nenhum repo novo avaliado nesta ronda.

## Busca ancorada (3 problemas)

1. **Hook que pendura e mata o prompt** (`deadline-de-hook-com-force-exit-por-dentro`). Busca: issues do Claude Code mostram hook sem `timeout` travando o SDK/CLI sem saída, e SessionStart travando no Windows mesmo com `timeout` setado. Nenhum repo de terceiro com deadline de dentro do processo. Sem candidato. O achado reforça a ideia, não a muda.
2. **Subagente escritor com worktree por filho** (`subagente-escritor-com-worktree-por-filho`). Busca: é recurso nativo do Claude Code (`isolation: "worktree"`), já usado pela regra 11. Não há repo de terceiro a avaliar. Sem candidato.
3. **Worker destacado com status/result/cancel** (`worker-codex-em-background-com-status-result-cancel`). Busca achou `zebbern/agent-collab` (Apache-2.0, 33★, último push 2026-09-29, 0 issues abertas) e `tigercosmos/codexmon` (MIT, 8★, último push 2026-10-05). Não estão na fila, então não passaram pelas perguntas de trilha: ficam como achado, sem veredito. A ideia já está plantada.

## Revisitas (gatilho duplo: 60+ dias E push posterior)

- **`Graphify-Labs/graphify`** — avaliado 2026-08-09, push visto 2026-08-08, push atual 2026-10-09. Reprovou em 1 (cobertura de `.prw`/`.tlpp`). Busca de código por `prw` no repo: nenhum resultado. Segue reprovado.
- **`tirth8205/code-review-graph`** — avaliado 2026-08-09, push visto 2026-08-02, push atual 2026-10-06. Reprovou em 1 (`custom_languages` exige gramática do tree-sitter-language-pack). `languages.toml` existe, mas continua apontando só para essas gramáticas; ADVPL não está lá. Segue reprovado.
- **`headroomlabs-ai/headroom`** — avaliado 2026-08-09, push visto 2026-08-09, push atual 2026-10-09. Reprovou em 4 (Windows) por causa da issue #1466, que estava aberta e sem resposta. Essa issue foi **fechada em 2026-09-25**. Mudou: saída (b), vira candidato da ronda 3 da próxima semana. Não reavaliado nesta ronda.

Elegíveis além do teto de 3 (não revisitados): `upstash/context7` (push 2026-10-09 > 2026-08-07) e `bmad-code-org/BMAD-METHOD` (push 2026-10-07 > 2026-08-09).

## Vale um /ideia?

Nada novo. Os três achados de busca já estão em ideias abertas.
