# fechar: push conferido e merge confirmado pelo state do PR

## Objetivo
O passo 5 do `fechar` deixa de publicar em prosa: um script confere conflito antes do push,
confere o push depois, reaproveita PR aberto e, onde o merge é autorizado, espera o CI e
confirma o merge pelo `state` do PR, nunca pela linha de sucesso do CLI. Um hook barra o
`gh pr merge --auto`, que neste repositório mergeia na hora por falta de check obrigatório.

Enxerto do skill `commit` do wildz-data 1.0.126 (Rafael Siqueira): `skills/commit/SKILL.md:325-367`
(merge-tree fail-closed, `@{u}`, MR existente), `skills/commit/coderabbit-review.md:483-502` e
`common-mistakes.md:56-59` (só o state MERGED prova o merge). As decisões D1 a D7 são as
recomendações da rodada 1, aceitas pelo Luís em 2026-10-13 ("segue o fluxo todo como recomendado").

## Decisões fechadas
- **D1 — Vale em todo `fechar`, em qualquer repositório; conflito e conferência do push são git puro e rodam sempre, PR/CI/merge só com remoto GitHub (`gh`), e fora dele o passo sai com aviso de uma linha e segue** — porquê: repo de cliente ganha a trava de conflito, e o que depende de `gh` não quebra GitLab ou Azure DevOps.
- **D2 — `scripts/publicar-branch.cjs` substitui o push implícito do passo 5 e cerca os dois comandos `gh` que continuam com a sessão**: subcomando `publicar` faz `git fetch origin <base>`, `merge-base` e `merge-tree` (fail-closed: comando que falha não é "sem conflito"), push com `-u`, confere `HEAD == @{u}` e termina com a linha `PR aberto: <n>` (reaproveita, sem criar) ou `PR aberto: nenhum` (a sessão roda `gh pr create` pelo Bash); o script nunca roda `gh pr create` nem `gh pr merge` por dentro — porquê: passo em prosa é o que a sessão pula, e `gh` chamado por dentro do script escaparia do `gate-fechar-issue`, que lê o corpo do PR atrás de `closes #N` sem evidência (ajuste do plano, 2026-10-13, lido no fonte do gate).
- **D3 — Merge dentro do `fechar` só com a chave de config `fechar-mergear` ligada (padrão desligado; ligada no `.rainforest/config.json` deste repositório)**: subcomando `esperar-ci --pr <n>` roda `gh pr checks <n> --watch` e decide; com CI verde e chave ligada a sessão roda `gh pr merge <n> --squash` pelo Bash (nunca `--auto`), e o subcomando `confirmar-merge --pr <n>` só sai 0 quando `gh pr view <n> --json state` devolve `MERGED`, relendo por até 60 s; `esperar-ci` roda em background (Monitor ou `run_in_background`) porque as baterias levam ~13 min; desligada a chave, o `fechar` para no PR aberto com o CI acompanhado — porquê: aqui a sessão já mergeia com CI verde (run autônomo); em repo de cliente merge sem revisão humana é mão única.
- **D4 — Conflito detectado para, lista os arquivos e não faz push; resolver (merge da base ou rebase) é ato explícito da sessão, e o script roda de novo** — porquê: rebase automático reescreve histórico e esconde o conflito que a trava existe para mostrar.
- **D5 — Modelo de ameaça: protege contra a própria sessão declarar "pushado" ou "mergeado" pelo texto do CLI, e contra push às cegas sobre uma base que andou; fica fora humano mergeando pelo site, force-push de terceiro e CI verde com bateria quebrada (defeito da bateria, não deste passo)** — porquê: com o fora escrito, a revisão tem critério de parada.
- **D6 — Códigos de saída: `0` ok; `1` uso; `3` conflito; `4` push divergiu (`HEAD != @{u}` ou push recusado); `5` CI vermelho; `6` merge pedido mas o state não virou `MERGED` no prazo; `7` CI verde com a chave `fechar-mergear` desligada (merge não autorizado); `69` ambiente (rede, `gh` ausente ou sem auth, sem remoto GitHub)** — porquê: um código por causa deixa a skill decidir sem ler prosa; segue a convenção do `critica-do-revisor.cjs`.
- **D7 — `gh pr merge ... --auto` é barrado (exit 2, mensagem apontando para `publicar-branch.cjs esperar-ci`) dentro do `analisarPrMerge` do `hooks/gate-fechar-issue.cjs`, com chave própria `gate-merge-auto` no `config.cjs` e desligável por `RAINFOREST_GATE_OFF`** — porquê: o erro se repetiu (#178 em 2026-09-04, #426 em 2026-10-07) com a regra já escrita em memória; só trava resolve. O gate já lê `gh pr merge` por lista de formas permitidas (#496) e `--auto` está nela: um hook novo reimplementaria esse parser (ajuste do plano, 2026-10-13).

## Avaliado e descartado
- Confiar no `gh pr merge --auto` como gate: medido no #178 e no #426, mergeou com as baterias `IN_PROGRESS` porque a `main` não tem proteção (`gh api .../branches/main/protection` devolve 404).
- Contar marcadores `<<<<<<<` com `pipefail` (como alerta o wildz-data): `grep -c` sai 1 em zero casamentos e leria merge limpo como erro; no script em node o exit do `merge-tree` e a contagem são lidos separados.

- Script rodar `gh pr create`/`gh pr merge` por dentro (desenho da rodada 1): escaparia do `gate-fechar-issue`, que confere evidência de Issue fechada pelo corpo do PR.
- Hook novo `gate-merge-auto.cjs`: duplicaria o parser de `gh pr merge` que o `gate-fechar-issue` já tem desde a #496.

## Fora de escopo
- Tornar as baterias checks obrigatórios na proteção da `main`: decisão do Luís sobre o repositório, não do plugin.
- CodeRabbit e prefixo de ticket do wildz-data: decidido fora em 2026-10-10 na ideia de origem.
- GitLab (`glab`) e Azure DevOps: D1 só avisa; suporte a outro host é trabalho próprio.
- `--auto` com o `gate-fechar-issue` desligado: a chave `gate-merge-auto` vive dentro desse gate e desliga junto.

## Varredura
docs/rainforest/varredura/2026-10-13-fechar-push-merge.txt — termos `merge-tree`, `auto-merge`, `MERGED`, `checks --watch`, `@{u}`, `pr create`. Nenhuma Issue ou PR sobre conflito antes do push ou confirmação de merge; os casamentos são de gates de staging/fechar-issue e de limpeza de branch squashed, sem relação. A ideia de origem (`fechar-push-conferido-e-merge-confirmado`) está no `ideias.jsonl`, marcada em colheita. As memórias `gh-auto-merge-sem-check-obrigatorio` e `auto-merge-nao-espera-baterias` deram a premissa de D3 e D7.

## Em aberto
