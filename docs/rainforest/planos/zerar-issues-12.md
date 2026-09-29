# Plano: Zerar as Issues abertas, rodada 12 — variável que o gate não resolve (#350)

Design: docs/rainforest/design/zerar-issues-12.md

## O que não pode quebrar
- Nenhum alvo com `$`, crase ou `$(` passa a ser liberado: as duas travas continuam saindo 2 onde saíam na base (D1). Só a mensagem muda.
- `git -C <caminho literal de outro repo> switch -c x` com sessão co-locada continua 0, e `git -C <principal literal> switch -c x` continua 2.
- `--body-file` com caminho absoluto literal continua lido e checado como hoje; `cd <dinâmico> && gh pr create --body-file rel.md` continua com a mensagem de caminho relativo.
- Nenhuma expansão de variável entra em `hooks/lib/cwd-efetivo.cjs` nem em `hooks/lib/tokens-comando.cjs` (os dois ficam idênticos à base).

## Tarefas

### 1. Trava co-locada nomeia o alvo não resolvido [tipo: implementar]
atende: D1, D2
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: bloqueiaColocada(alvo.verbo, daqui.toplevel, outras, agora, alvo.incerto === true);
  para: bloqueiaColocada(alvo.verbo, daqui.toplevel, outras, agora, false);
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: testa-gate-worktree.sh, seção "(#350) sessao co-locada: alvo com variavel barra citando o caminho literal"
Implementação: `bloqueiaColocada` ganha o 5º parâmetro `incerto`; quando verdadeiro, a mensagem ganha, logo depois da linha `Repo:`, um parágrafo dizendo que o alvo do comando usa variável, substituição (`$(...)`) ou `cd` que o gate não resolve, que por isso ele foi lido como este checkout, e que com o caminho literal o gate compara o repo de verdade (clone de outro repo passa). A chamada em `gateDeSessaoColocada` passa a ser exatamente a linha do `de:` acima. O docblock de `gateDeSessaoColocada` ganha a distinção do D2: "falha para liberar" vale para o que a trava não consegue medir por falta de infraestrutura (sem `session_id`, sem `sessoes.json`, sem raiz de dados, fora de repo git); alvo que o parser não resolve barra. `alvosBash` e `hooks/lib/*` não mudam.
pronto quando: com o payload PreToolUse real (`{"session_id":…,"cwd":<principal>,"tool_name":"Bash","tool_input":{"command":"H=/x/repo-b; git -C \"$H\" switch -q -c fix/y"}}`) e um `sessoes.json` com outra sessão ativa no mesmo cwd, `node hooks/gate-worktree.cjs` sai 2 e o stderr contém "caminho literal"; o mesmo payload com `git -C <clone literal de outro repo> switch -q -c fix/y` sai 0; com `git -C <principal literal> switch -q -c fix/y` sai 2 e o stderr NÃO contém "caminho literal" — provado pela seção nova de `bash hooks/testa-gate-worktree.sh` (os três casos, 0 falhas, 0 skipped) e por `git diff origin/main -- hooks/lib/` vazio.

### 2. `--body-file` com variável tem mensagem própria [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: if (/[$\x60]/.test(arquivo)) {
  para: if (false) {
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, seção "(#350) --body-file com variavel → exit 2 citando variavel nao resolvivel"
Implementação: em `extrairCorpoDoPR`, no ramo `--body-file`, logo depois de `arquivo = normalizarMsys(arquivo);`, entra `if (/[$\x60]/.test(arquivo)) {` devolvendo `{ tipo: "arquivo", conteudo: null, legivel: false, variavel: true }` (a classe usa `\x60` para a crase, para o padrão não carregar crase literal). No bloco de corpo ilegível, `corpoDoPR.variavel` vem antes do `cwdIncerto` e bloqueia com "--body-file usa variável que o gate não resolve (…): use o caminho literal". Nenhuma expansão de variável.
pronto quando: com o payload PreToolUse real `{"cwd":<repo>,"tool_name":"Bash","tool_input":{"command":"SP=C:/x; gh pr create --title t --body-file \"$SP/pr.md\""}}`, `node hooks/gate-fechar-issue.cjs` sai 2 e o stderr contém "variável que o gate não resolve" e NÃO contém "caminho relativo"; `cd $D && gh pr create --body-file pr.md` sai 2 com "caminho relativo"; `gh pr create --body-file <absoluto literal com "Closes #12">` continua na checagem de fechamento de hoje (caso (d) intacto) — provado pela seção nova de `bash hooks/testa-gate-fechar-issue.sh` (0 falhas) e pelos casos (d) e (bk) existentes verdes.

### 3. Versão e registro [tipo: docs]
atende: D4
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: texto de registro e número de versão; não há comportamento a inverter — a coerência se confere pela bateria de versão e pela leitura contra o design.
pronto quando: com `origin/main` em 1.29.0, os manifestos dizem 1.30.0 e `bash scripts/testa-versao.sh` sai com 0 falhas; a entrada do registro descreve o que o design decidiu (mensagens novas nos dois gates, nenhuma expansão de variável, com o porquê da rodada 9) e não promete expansão nem liberação de alvo com variável — conferido lendo a entrada contra D1–D3.
