# gate-fechar-issue: flags curtas do corpo do PR com caixa exata, -F e forma colada (#664)

## Objetivo
O `extrairCorpoDoPR` de `hooks/gate-fechar-issue.cjs` passa a achar o corpo do
`gh pr create`/`gh pr edit` em toda grafia que o `gh` (pflag) aceita, para que
`Closes #N` sem evidência não passe por causa da grafia da flag.

Brainstorm conduzido em modo autônomo (autorização do Luís em 2026-11-11: "pode
decidir e executar no automatico"). Toda decisão abaixo é **decidido pela sessão**,
com a opção recomendada, e fica aberta a veto no PR.

## Decisões fechadas
- **D1 — Flag curta compara com a caixa exata; só a longa compara em minúsculas.** `-b` é `--body`, `-F` é `--body-file`; `-B` (`--base`) e `-f` (`--fill`) não são corpo. — porquê: o código atual faz `toLowerCase()` na chave inteira, e `-B main` vira corpo "main". Reproduzido em 2026-11-11 na `main` (7882b947): `gh pr create -B main --title t --body-file <arquivo com "Closes #12">` sai **0**, e `gh pr edit 5 -B main --body-file <mesmo>` também. O `gh pr merge` do mesmo arquivo (`COM_VALOR_PR_MERGE`, linha 711) já compara com caixa exata; esta decisão alinha o `create`/`edit` a ele.
- **D2 — `-F` é reconhecido como `--body-file`, nas três formas do pflag: `-F x`, `-F=x` e `-Fx`; `-b` ganha a forma colada `-bx`.** — porquê: é a #664 (`gh pr create -F` cai na recusa "editor interativo", razão errada) e, pior, `gh pr edit 5 -F <arquivo com Closes #12>` sai **0**, porque o edit sem corpo reconhecido é tratado como "não toca a descrição". O mesmo vale para `gh pr edit 5 -bCloses-#12` (**0**). O pflag aceita valor colado à flag curta, então a forma colada é corpo de verdade.
- **D3 — Todas as ocorrências de corpo no segmento são lidas, não só a primeira.** Qualquer uma ilegível decide pela recusa dela; legíveis, o conteúdo checado é a junção de todas. — porquê: o laço atual devolve na primeira flag que casa; `-b x --body-file <Closes #12>` checaria só "x". Juntar é o superconjunto do que o `gh` pode usar (último vence no pflag, ou erro de exclusão mútua), então nunca checa menos do que vai para o PR.
- **D4 — Modelo de ameaça: protege contra agente que fecha Issue pelo corpo do PR sem evidência usando grafia de flag que o `gh` aceita.** Fica fora: alias do `gh` (`gh alias set`), `gh api` direto, variável de ambiente do `gh`, `--template`/`--fill` (já recusados como "editor interativo" no `create`, porque não trazem `--body`), e flag longa abreviada (o `gh`/cobra não aceita prefixo de flag longa). `--fill` **com** `-B` antes era contorno (o `-B main` virava corpo e escondia a falta dele) e entra pelo D1: sem corpo reconhecido, o `create` volta à recusa "editor interativo". — porquê: gate novo ou ampliado precisa do modelo escrito, senão cada revisão acha um vetor novo e a auditoria não converge (skill brainstorm).

- **D5 — Token que é valor de outra flag não é lido como flag.** As flags de valor do `gh pr create`/`pr edit`/`issue create`/`issue comment` (`--title`/`-t`, `--base`/`-B`, `--head`/`-H`, `--repo`/`-R`, `--assignee`/`-a`, `--label`/`-l`, `--milestone`/`-m`, `--project`/`-p`, `--reviewer`/`-r`, `--template`/`-T`, `--recover`, `--attach`, `--blocked-by`, `--blocking`, `--parent`, `--type`, `--add-*` e `--remove-*` de assignee, label, project e reviewer — lista conferida contra o manual oficial de `gh_pr_create`, `gh_pr_edit`, `gh_issue_create` e `gh_issue_comment` em 2026-11-11) consomem o token seguinte quando o valor não vem colado; as flags de corpo também. Flags curtas agrupadas (`-dF x`) ficam fora: no `create` caem na recusa "editor interativo" (lado seguro), e o `pr edit` não tem atalho booleano. — porquê: achado 1 da revisão 1, decidido pela sessão em modo autônomo. Com a caixa exata do D1 e o valor colado do D2, `gh pr create --fill --title "-bar"` passou a sair 0 (o título virava `-b` + corpo "ar" e escondia o `--fill`); na base saía 2. A premissa do plano ("lido como flag, como já era") estava errada, porque antes a chave era o token inteiro.

## Avaliado e descartado
- **Ler o argv real com um `gh` intermediário no PATH** (ideia `gh-intermediario-no-path`): resolveria toda grafia de uma vez, mas é mudança de ambiente do usuário (regra 15) e de outra escala. A correção do parser fecha os desvios medidos com o mecanismo que já existe.
- **Recusar `-F`/`-b` colados em vez de lê-los**: barraria uso legítimo (o `-F` sem fechamento que a #664 pede para passar) pela razão errada, que é o defeito da própria #664.

## Fora de escopo
- Mensagem da recusa e receita do corpo do PR (fluxo `2026-11-07-receita-corpo-pr`, D1/D2 intactas): este trabalho muda **quais** comandos passam, não o texto.
- `gh pr merge`: já compara com caixa exata e já conhece `-F`.

## Varredura
docs/rainforest/varredura/gate-pr-flag-curta.txt — só a própria #664 aberta; PRs #665 e #615 mexeram no gate sem tocar a comparação de flag; ideia `gh-intermediario-no-path` virou o primeiro item descartado. `conferir-fluxo deriva` no `gate-fechar-issue.cjs`: 17 decisões, todas intactas; nenhuma fixa o `toLowerCase` da chave.

## Em aberto
