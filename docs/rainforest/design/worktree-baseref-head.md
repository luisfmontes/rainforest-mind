# Design — worktree do agente nasce do HEAD da sessão (`worktree.baseRef: "head"`)

Data: 2026-10-10. Enxerto A da comparação do `executar` com o orquestrador do
plugin `wildz-data` (Rafael Siqueira), decidido pelo Luís em 2026-10-09.

## Objetivo

A regra 11 trata como comportamento fixo do harness que o worktree de
`isolation: "worktree"` nasce na ponta de `origin/main`, não no commit de
trabalho. Daí o hash da base no briefing ser o de `origin/main`, o
`merge --ff-only origin/main` antes de despachar e o `preparar-worktree.cjs`
fazendo fast-forward dentro do worktree do agente. Dois incidentes de base
errada (2026-08-07, 2026-08-23) vieram dessa distância. A chave
`worktree.baseRef` do harness muda o comportamento, e o texto do plugin
precisa descrever os dois modos em vez de supor um.

Fato medido: a descrição do `EnterWorktree` no CLI instalado diz "The base
ref is governed by the `worktree.baseRef` setting: `fresh` (default) branches
from origin/<default-branch>; `head` branches from your current local HEAD".
Sonda despachada em 2026-10-10 com `isolation: "worktree"`, de dentro do
worktree deste fluxo, relatou HEAD `b5dcff7` (o commit de design, hash que não
estava no briefing), não `origin/main` `7bd36fb` — sem reiniciar a sessão.

## Decisões fechadas

- **D1 — A chave é configuração do usuário, não do plugin.** Gravada em
  2026-10-10 nas duas `settings.json` (`~/.claude` e `~/.claude-personal`),
  com backup `settings.json.bak-baseref-20261010`. Plugin não escreve settings
  (regra 15).
- **D2 — O texto do plugin passa a ser condicional à chave.** Com `head`, a
  base do agente é o HEAD do diretório da sessão que despacha, e o hash do
  briefing é `git rev-parse HEAD` desse diretório. Com `fresh` ou chave
  ausente (o padrão de quem instala o plugin), vale o texto anterior
  (`origin/main` + `--ff-only`).
- **D3 — A conferência de base não sai.** `preparar-worktree.cjs --hash` e
  `conferir-entrega.cjs --base` continuam obrigatórios: a chave muda qual hash
  se espera, não a necessidade de conferir — outro escopo de settings pode
  sobrepor o do usuário.
- **D4 — "HEAD da sessão" depende de onde a sessão está.** Sessão que
  despacha do checkout principal (na `main`) dá ao agente a `main`. O texto
  diz que é a sessão estar no worktree do trabalho que faz o agente nascer na
  branch de trabalho.
- **D5 — O glossário acompanha.** O verbete "worktree de agente" descreve os
  dois modos (aprovado pelo Luís em 2026-10-10).

## Avaliado e descartado

- Remover o `--ff-only` e o `preparar-worktree.cjs`: descartado por D3 — quem
  instala o plugin sem a chave continua no modo `fresh`.
- Plugin gravar a chave nas settings: descartado por D1 (regra 15).

## Fora de escopo

Effort dos agentes (enxerto B), veredito em JSON (C), laço de iteração (D),
painel do fluxo (G, plantado).

## Em aberto

Nada.

## Varredura

`docs/rainforest/varredura/worktree-baseref-head.txt` — termos `origin/main`,
`baseRef`, `ponta da`. Os pontos normativos achados foram `regra-11.md`,
o núcleo da regra 11 em `skills/rainforest-mind/SKILL.md`,
`skills/executar/SKILL.md` e `GLOSSARIO.md`; os demais são relatórios e mapas
datados, que registram o que valia na época e não se reescrevem.
