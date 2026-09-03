# Handover — publicação do repositório e 1.0.0 (2026-09-02)

Sessão longa (começou de handover, terminou publicando o repo). Este arquivo é
o estado final + a fila recomendada para a próxima sessão.

## O que mudou hoje (e onde está a prova)

**O repositório é UM só, público, com a história inteira.**
`luisfmontes/rainforest-mind` é o repo original (ex-`rainforest-mind-lab`),
renomeado de volta e virado público em 2026-09-02. O repo público criado mais
cedo no mesmo dia foi **apagado** — a separação em dois tinha nascido de uma
premissa inflada (os "vazamentos" eram o nome do usuário, o caminho da home e
números sintéticos que ele não reconhece; decidido por ele que não bloqueiam
publicação). Ninguém tinha clonado o antigo; só instalação de plugin.

- História: 634 commits (reescrita de 2026-09-02 com git-filter-repo), 168 PRs,
  issues com a numeração original.
- Ressalva **decidida e aceita**: as ~110 `refs/pull/*` antigas guardam a
  história pré-reescrita e ficam acessíveis a quem buscar. Não reabrir esse
  debate sem fato novo.
- Actions agora é ilimitado (repo público).

**Versão 1.0.0, com release.**
PR #168 (merge `7a8e0dd`), tag `v1.0.0`, release em
<https://github.com/luisfmontes/rainforest-mind/releases/tag/v1.0.0>.
Racional: o plugin tem usuários reais; `0.x` deixou de ser honesto. **Contrato
a partir daqui: quebra de interface (manifesto `.rainforest/agentes.json`,
nome de hook, assinatura de script) vira major bump.**

**Issue #165 fechada pelo PR #167 (merge `ddda360`).**
O gate de publicação passou a conferir o **commit** (`git show :<arquivo>` para
o índice; worktree com `-a`), não só as ferramentas `Write`/`Edit`. Bateria
`hooks/testa-gate-commit.cjs` (19 ok), 3 mutações vermelhas. Evidência colada
no comentário de fechamento da issue #165.

## O que o USUÁRIO ainda precisa fazer

1. `/plugin marketplace update rainforest-mind` + janela nova — o cache dele
   está em 0.81.1 e a publicada agora é **1.0.0**. Se o update recusar (o cache
   é clone git e a história foi reescrita), remover e adicionar o marketplace.
2. Nada de avisar colaboradores sobre re-clone: ninguém tinha clonado.

## Fila recomendada (ordem defendida na sessão, aceita por ele)

1. **Issue #158 primeiro, sessão própria, fora de fluxo.** A bateria
   `testa-gate-publicacao-destino.sh` monta payload com `jq` e, sem `jq`,
   reporta "ok" sobre casos que não exerceu — instrumento que passa mais alto
   quando a ferramenta some. O placar dela foi usado como evidência em dois PRs
   de 2026-09-02; consertar antes de medir mais coisa. A bateria nova da trava
   de commit já nasceu em node por causa disso (o cabeçalho dela explica).
2. **Fluxo 7 (recibo).** Parado em `executar` 0/7, branch `fluxo/recibo`
   (`4d2ed15`). O bloqueio que o parou (nenhum agente admitido para `executar`)
   morreu no PR #152. Retomar com
   `/rainforest-mind:executar --slug 2026-09-02-fluxo-7-recibo` — a skill manda
   trazer a `origin/main` (agora `7a8e0dd`) para a branch antes de despachar.
3. **Família dos guards** — #153 (4 baterias vermelhas conhecidas no CI:
   `testa-ferramentas-nao-toca-abertura`, `testa-gate-repo-alheio`,
   `testa-conferir-comparacao`, `testa-saude`), #142, #143, #127. Mesma raiz:
   guard medindo o repositório errado. Enquanto abertas, o critério de merge é
   "só essas 4 vermelhas, nenhuma nova" — foi assim que #167 e #168 entraram.
4. **Issues do John** (#157–#163) e o resto (#148, #145, #144, #131, #125, #120).

## Estado local desta máquina

- Checkout principal `C:\Projetos\rainforest-mind` na `main`, adiantado até
  `7a8e0dd`. Remote `arquivo` (duplicado) foi removido; só `origin`.
- Worktree `.claude/worktrees/gate-commit` na branch `fix/gate-no-commit`, já
  mergeada e apagada no remoto — o worktree pode ser removido
  (`git worktree remove .claude/worktrees/gate-commit`).
