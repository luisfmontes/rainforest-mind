# Plano: fechar com push conferido e merge confirmado pelo state do PR

Design: docs/rainforest/design/2026-10-13-fechar-push-merge.md

## Achados que contradizem o briefing (lidos no fonte, na base 2e1808d8)
- O `gate-fechar-issue.cjs` já lê `gh pr merge` por lista de formas permitidas (`analisarPrMerge`, linha 791, #496), e `--auto` está em `BOOLEANAS_PR_MERGE` (linha 631). A trava do D7 entra ali; não nasce hook novo, e por isso `hooks/hooks.json`, `hooks/testa-titulo-sessao-registro.sh` (17 em `PreToolUse`) e `scripts/testa-conferir-categoria.sh` (58 peças) ficam sem diff.
- O mesmo gate lê o corpo do PR no `gh pr create` e no `gh pr merge` atrás de `closes #N` sem evidência. Por isso o script não roda `gh pr create` nem `gh pr merge` por dentro (D2, D3).
- `.rainforest/config.json` não existe neste repositório e não está no `.gitignore` (`git check-ignore` sem saída): a tarefa 1 o cria versionado, só com a chave `fechar-mergear`.
- `skills/fechar/SKILL.md` tem 13127 B (teto 16384).

## O que não pode quebrar
- `bash hooks/testa-gate-fechar-issue.sh` verde: nenhuma forma hoje aceita de `gh pr merge` passa a ser barrada, exceto as com `--auto`.
- `bash hooks/testa-config.sh` verde, e `ligado()` continua falhando para o lado de LIGAR em config ilegível; a chave nova `fechar-mergear` é a única com padrão `false`, e config ilegível nela vale DESLIGADA (merge é mão única).
- `bash scripts/testa-teto-skills.sh` verde (`skills/fechar/SKILL.md` abaixo de 16384 B) e `node scripts/orcamento.cjs` sem mudança: nenhuma `description` muda.
- O script nunca faz push com conflito detectado nem com o `merge-tree` falhando, e nunca reescreve histórico (sem rebase, sem `--force`).

## Decisões assumidas pelo plano (técnicas; o design não fixa)
- Conflito: `git merge-tree --write-tree --name-only HEAD origin/<base>`. Exit 0 limpo, exit 1 conflito (os nomes dos arquivos depois da primeira linha vão para o stdout do script), qualquer outro exit ou sinal é falha do comando e sai 69 (fail-closed: nunca lido como limpo).
- Base: `--base <ref>`, padrão a branch padrão do remoto (`git symbolic-ref refs/remotes/origin/HEAD`), e `main` se não resolver.
- "Remoto GitHub" é `git remote get-url origin` casando `github.com`. Sem isso, `publicar` faz conflito, push e `@{u}` e imprime `PR aberto: n/a (remoto não é GitHub)` com exit 0; `esperar-ci` e `confirmar-merge` saem 69.
- `esperar-ci`: `gh pr checks <n> --watch --interval 20`; exit 0 do `gh` é verde, exit 8 (pendente) não acontece com `--watch`, qualquer outro exit diferente de 0 é vermelho (5). PR sem check nenhum (`gh` diz "no checks reported") sai 5 com a mensagem, porque merge sem CI é exatamente o que o D3 evita.
- `confirmar-merge`: relê `gh pr view <n> --json state` a cada 5 s por até 60 s (`RFM_MERGE_PRAZO_S` encurta na bateria).

## Em aberto
- Nada.

## Tarefas

### 1. `scripts/publicar-branch.cjs` e a chave `fechar-mergear` [tipo: implementar]
atende: D1, D2, D3, D4, D5, D6
arquivos: `scripts/publicar-branch.cjs`, `scripts/testa-publicar-branch.sh`, `hooks/lib/config.cjs`, `.rainforest/config.json`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-publicar-branch.sh`
mutacao:
  arquivo: `scripts/publicar-branch.cjs`
  de: `if (mt.status === 1) {`
  para: `if (mt.status === 99) {`
  bateria: `bash scripts/testa-publicar-branch.sh`
  fixture: `testa-publicar-branch.sh, secao "conflito com a base: sai 3, lista o arquivo e nao faz push"`
pronto quando: num repo-caixa com `origin` sendo um repositório bare local de URL `https://github.com/caixa/repo.git` reescrita por `url.<bare>.insteadOf` (o `get-url` devolve a URL GitHub, o push vai para o bare) e um stub de `gh` em caminho POSIX conferido por `command -v gh` antes do primeiro caso: (a) branch limpa sobre a base: `node scripts/publicar-branch.cjs publicar` sai 0, `git rev-parse HEAD` igual a `git rev-parse @{u}`, e a última linha é `PR aberto: nenhum` com o stub sem PR, ou `PR aberto: 7` com o stub devolvendo o PR 7 aberto para a branch, e em nenhum dos dois o stub registra chamada `pr create`; (b) a base andou no bare com mudança na mesma linha do mesmo arquivo: sai 3, imprime o caminho do arquivo em conflito, e `git ls-remote` do bare não tem a branch; (c) a base andou sem conflito: sai 0 e faz o push; (d) `merge-tree` falhando (base inexistente `--base nao-existe`): sai 69 sem push; (e) push recusado (hook `pre-receive` do bare saindo 1): sai 4 e não imprime `PR aberto`; (f) remoto sem `github.com`: sai 0 com `PR aberto: n/a (remoto não é GitHub)` e o stub sem chamada; (g) `esperar-ci --pr 7` sai 0 com o stub de checks saindo 0 e a chave `fechar-mergear` ligada no `.rainforest/config.json` da caixa, sai 7 com ela ausente ou `false`, sai 7 com o arquivo de config ilegível (`{`), sai 5 com checks saindo 1, e sai 69 com o stub ausente do PATH; (h) `confirmar-merge --pr 7` sai 0 quando o stub devolve `{"state":"MERGED"}`, sai 6 com `OPEN` dentro de `RFM_MERGE_PRAZO_S=2`, e sai 6 com `CLOSED`; (i) sem subcomando, com flag desconhecida ou `--pr abc`: sai 1; e `git -C <repo real> diff --quiet 2e1808d8 -- hooks/gate-fechar-issue.cjs` sai 0 nesta tarefa — provado por `bash scripts/testa-publicar-branch.sh` com a última linha `ok: N   falhou: 0` e zero `pulado`

Nota: código a nascer; nenhum caso de teste afirma sobre o texto do fonte. Forma prescrita: o resultado do `spawnSync('git', ['merge-tree', '--write-tree', '--name-only', 'HEAD', base])` fica em `mt`, e o ramo de conflito é `if (mt.status === 1) {` (uma ocorrência), seguido do ramo `if (mt.status !== 0)` que sai 69. A chave `fechar-mergear` entra no **fim** do objeto `CHAVES` de `hooks/lib/config.cjs` (`tipo: 'boolean'`, `padrao: false`), e o script a lê com `resolverConfig({ projeto: raiz }).valores['fechar-mergear'] === true` dentro de `try` que, em erro, vale `false`, nunca com `ligado()` (que falha para LIGAR). `.rainforest/config.json` versionado com `{"fechar-mergear": true}`. A bateria usa `mktemp -d` fora do worktree, stub de `gh` em Node com o registro de chamadas num arquivo, e nunca chama o `gh` real (conferir com `command -v gh` apontando para o stub). Parada do modelo de ameaça (D5): o script não protege contra quem roda `git push` à mão nem contra CI verde com bateria quebrada.

### 2. `--auto` barrado no `gh pr merge`, chave `gate-merge-auto` [tipo: implementar]
atende: D7
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/lib/config.cjs`, `hooks/testa-gate-merge-auto.sh`
depende de: 1
paralela: nao
prova: `bash hooks/testa-gate-merge-auto.sh`
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `if (tok === "--auto" && autoBarrado) {`
  para: `if (tok === "--auto-nunca" && autoBarrado) {`
  bateria: `bash hooks/testa-gate-merge-auto.sh`
  fixture: `testa-gate-merge-auto.sh, secao "gh pr merge 5 --squash --auto barra"`
pronto quando: com o JSON que o harness manda no `PreToolUse` de `Bash` (`{"tool_name":"Bash","tool_input":{"command":...},"cwd":<repo-caixa>}`) e um stub de `gh` cujo `pr view --json body` devolve corpo sem `closes`, `node hooks/gate-fechar-issue.cjs` sai 2 com uma mensagem que cita `publicar-branch.cjs esperar-ci` e o motivo (sem check obrigatório o `--auto` mergeia na hora) para `gh pr merge 5 --squash --auto`, `gh pr merge --auto 5`, `gh pr merge https://github.com/o/r/pull/5 --auto --squash` e para o mesmo comando vindo com `tool_name` `PowerShell`; passam (exit 0) `gh pr merge 5 --squash`, `gh pr merge 5 --disable-auto`, `gh pr view 5 --json autoMergeRequest`, `grep -n -- "--auto" README.md` e `echo "gh pr merge 5 --auto"`; com `RAINFOREST_GATE_OFF=1` e com `{"gate-merge-auto": false}` no `.rainforest/config.json` da caixa, `gh pr merge 5 --squash --auto` deixa de ser barrado pelo `--auto`; com o arquivo de config ilegível, continua barrado (falha para LIGAR) — provado por `bash hooks/testa-gate-merge-auto.sh` com a última linha `ok: N   falhou: 0`, e por `bash hooks/testa-gate-fechar-issue.sh` e `bash hooks/testa-config.sh` saindo 0

Nota: a chave `gate-merge-auto` (`tipo: 'boolean'`, `padrao: true`) entra logo depois de `gate-fechar-issue` em `CHAVES`, depois que a tarefa 1 já pôs `fechar-mergear` no fim do objeto. `autoBarrado` é `require("./lib/config.cjs").ligado("gate-merge-auto", { projeto: cwdDoEvento })`, lido uma vez antes do laço de tokens. `--auto` continua em `BOOLEANAS_PR_MERGE`, e a checagem nova vem antes do `continue` dela. Parada declarada (critério de trava): a trava vale só dentro da forma que o `analisarPrMerge` já aceita; forma fora dela já é barrada pela #496, e o plano não acrescenta parser. `--auto` com o `gate-fechar-issue` desligado fica fora (design, Fora de escopo).

### 3. Passo 5 do `fechar`, README, CHANGELOG e versão 1.64.0 [tipo: docs]
atende: D1, D2, D3, D6, D7
arquivos: `skills/fechar/SKILL.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`, `scripts/baterias-obrigatorias.txt`, `scripts/contrato-plugin-codex.cjs`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: texto de skill e de documentação, sem comportamento a inverter; a falsificação é a coerência com o script e com o design.
pronto quando: com o script da tarefa 1 na branch, todo subcomando e todo código de saída que `skills/fechar/SKILL.md` cita existem no script e batem com o D6 (os subcomandos `publicar`, `esperar-ci` e `confirmar-merge` e os exits 0, 1, 3, 4, 5, 6, 7 e 69, cada um com a ação que a skill toma), o passo 5 manda rodar `gh pr create` só quando o `publicar` imprimiu `PR aberto: nenhum`, manda `esperar-ci` em background e só depois `gh pr merge <n> --squash` (nunca `--auto`) seguido de `confirmar-merge`, e diz o que fazer com a chave `fechar-mergear` desligada (parar no PR aberto); o README cita o script e as duas chaves novas, o CHANGELOG tem a entrada 1.64.0, e a versão é 1.64.0 nos dois manifestos — provado por `node scripts/conferir-versao.cjs`, `bash scripts/testa-teto-skills.sh` e `node scripts/orcamento.cjs` saindo 0, e por leitura cruzada na revisão: cada exit citado na skill procurado com `grep -n "process.exit(<n>)\|exit(<n>)" scripts/publicar-branch.cjs`

Emenda (revisar volta 1, 2026-10-13): (1) a versão 1.64.0 vale também no `.codex-plugin/plugin.json` e no selo do `README.md`, e a tarefa 3 passa a ser provada também por `bash scripts/testa-versao.sh` saindo 0; (2) as baterias novas entram em `scripts/baterias-obrigatorias.txt` (tarefa 3); (3) na tarefa 1, exit 1 do `merge-tree` só é conflito com o OID da árvore na 1ª linha e ao menos um arquivo; sem isso sai 69 — casos novos `(d2)` (fetch passa, `origin/<base>` ausente) e `(d3)` (base sem história em comum, exit 128) em `scripts/testa-publicar-branch.sh`, e a mutação `if (mt.status !== 0) {` → `if (false) {` também tem de deixar a bateria vermelha.

Emenda (CI do PR #506, 2026-10-13): mudar o corpo de `skills/fechar/SKILL.md` exige re-medir a âncora binária `fechar` em `scripts/contrato-plugin-codex.cjs` (tarefa 3); provado por `bash scripts/testa-plugin-codex.sh` saindo 0.
