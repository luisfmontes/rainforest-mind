# Plano: portaria fora de repo e aviso de escrita pelo shell (#565, #564)

Design: docs/rainforest/design/2026-10-21-portaria-aviso-bash.md

## O que não pode quebrar
- Com o cwd dentro de repo, agente que escreve sem `isolation: "worktree"` continua negado pela regra 11.
- Agente que escreve continua nunca nomeado, e o estágio do fluxo continua decidindo.
- O `aviso-fluxo.cjs` mantém o texto e o veredito de hoje (`hooks/testa-aviso-fluxo.cjs` verde).
- Sessão com o cwd dentro de repo não ganha linha nova na abertura.

## Tarefas

### 1. Portaria aceita o worktree declarado fora de repo [tipo: implementar]
atende: D1, D4
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-fora-de-repo.cjs`
depende de: nenhuma
prova: `node hooks/testa-portaria-fora-de-repo.cjs`
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `if (isolamento !== "worktree" && !worktreeDeclarado) {`
  para: `if (isolamento !== "worktree") {`
  bateria: `node hooks/testa-portaria-fora-de-repo.cjs`
  fixture: `testa-portaria-fora-de-repo.cjs, casos A1 e A2`
pronto quando: com o payload PreToolUse de `Agent` que o harness manda (`cwd` numa pasta fora de repo git, `subagent_type: rainforest-mind:executor`, sem `isolation`, `prompt` com a linha isolada `Worktree: <worktree linkado>` cujo fluxo está em `executar`), a portaria sai 0 (com barras e com contrabarras), e o `arqueologo` no mesmo payload sai 2 pelo estágio. Sem a linha, ela sai 2 pela regra 11 e a mensagem aponta `Worktree: <caminho absoluto>`. Com o cwd no worktree, sem `isolation`, ela sai 2 pela regra 11 mesmo com a linha, e a mensagem não oferece a linha. Com `isolation: "worktree"` ela sai 0. Provado por `node hooks/testa-portaria-fora-de-repo.cjs` com placar `0 falha(s)`.

### 2. Portaria confere que o worktree declarado é linkado e é o toplevel [tipo: implementar]
atende: D1, D4
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-fora-de-repo.cjs`
depende de: 1
prova: `node hooks/testa-portaria-fora-de-repo.cjs`
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `if (norm(gitDir) === norm(comum)) return null;`
  para: `if (false) return null;`
  bateria: `node hooks/testa-portaria-fora-de-repo.cjs`
  fixture: `testa-portaria-fora-de-repo.cjs, caso B2 (Worktree: apontando o checkout principal)`
pronto quando: com o cwd fora de repo e `Worktree:` apontando para o checkout principal (não linkado), para um subdiretório do worktree, para pasta que não existe, ou com caminho relativo, ou com a linha no meio da frase, a portaria sai 2 pela regra 11. Com `Worktree:` válido e `name` no despacho, ela sai 2 pela regra 10. Provado por `node hooks/testa-portaria-fora-de-repo.cjs` (casos B2 a B7) com placar `0 falha(s)`.

### 3. Abertura avisa quando o cwd não é repo git [tipo: implementar]
atende: D2, D4
arquivos: `hooks/foco-session-start.cjs`, `hooks/testa-contexto-sessao.sh`
depende de: nenhuma
prova: `bash -c 'D=$(mktemp -d); CLAUDE_PROJECT_DIR=$D node hooks/foco-session-start.cjs | grep -q "cwd fora de repo git"'`
mutacao:
  arquivo: `hooks/foco-session-start.cjs`
  de: `if (!dentroDeRepoGit(process.env.CLAUDE_PROJECT_DIR || process.cwd())) {`
  para: `if (false) {`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: `testa-contexto-sessao.sh, casos "#565 cwd fora de repo"`
pronto quando: com o `foco-session-start.cjs` rodado como no SessionStart, com `CLAUDE_PROJECT_DIR` numa pasta temporária fora de repo, o `additionalContext` traz no bloco "Dependências de ambiente" a linha `cwd fora de repo git: agente com isolation "worktree" não despacha daqui`, que aponta `Worktree: <caminho absoluto>`. Com `CLAUDE_PROJECT_DIR` no repo do plugin, a linha não sai. Provado por `bash hooks/testa-contexto-sessao.sh` com placar `falhou: 0`.

### 4. Helpers do aviso-fluxo numa lib comum [tipo: implementar]
atende: D3
arquivos: `hooks/lib/aviso-fluxo-comum.cjs`, `hooks/aviso-fluxo.cjs`
depende de: nenhuma
prova-na-base: verde — a tarefa move código sem mudar comportamento; a bateria do aviso-fluxo passa na base e tem de continuar passando
mutacao:
  arquivo: `hooks/aviso-fluxo.cjs`
  de: `if (fluXoAberto(gitTop, trilho)) {`
  para: `if (true) {`
  bateria: `node hooks/testa-aviso-fluxo.cjs`
  fixture: `testa-aviso-fluxo.cjs, caso "rainforest sem fluxo aberto: bloqueia na primeira edicao"`
pronto quando: com o payload PreToolUse de Edit num `.cjs` fora de `docs/` de um repo rainforest sem fluxo aberto, o `aviso-fluxo.cjs` sai 2 com o mesmo texto de antes, agora importando trilho, fluxo aberto, branch padrão e mensagens de `hooks/lib/aviso-fluxo-comum.cjs`. Provado por `node hooks/testa-aviso-fluxo.cjs` com `10 ok, 0 falha(s)`.

### 5. Hook PostToolUse avisa código novo escrito pelo shell [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/hooks.json`, `hooks/testa-aviso-fluxo-shell.cjs`, `hooks/testa-config.sh`, `hooks/testa-memoria-marca.sh`, `scripts/testa-conferir-categoria.sh`
depende de: 4
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `const sujosNovos = [...atual].filter((c) => !guardado.caminhos.has(c));`
  para: `const sujosNovos = [];`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, casos A2, A4 e A8`
pronto quando: com o payload PostToolUse de Bash da sessão principal num repo rainforest sem fluxo aberto, depois de o comando deixar `x.py` novo (ou de mudar o `a.sh` rastreado), o hook sai 2 com o aviso que nomeia o arquivo, diz que o comando já rodou e traz as saídas (abrir o fluxo, `leve`). O mesmo vale para o payload de PowerShell. Saem 0: código sob `docs/`, `.txt`, subagente (`agent_id`), chave `aviso-fluxo` desligada, `leve` na branch, fluxo aberto, repo sem trilho, cwd fora de repo. Na `main`, o aviso manda para o worktree e não oferece o `leve`. O `hooks/hooks.json` registra o hook em `PostToolUse` com matcher `Bash|PowerShell`, e é o único hook nesse evento: `bash hooks/testa-config.sh` confere isso e sai com `0 falha(s)`, `bash hooks/testa-memoria-marca.sh` segue barrando outro hook em `PostToolUse`, e `bash scripts/testa-conferir-categoria.sh` conta 61 peças, 25 guia, 33 sensor e 3 dado, com o hook novo marcado `sensor` porque roda depois da ação. Provado por `node hooks/testa-aviso-fluxo-shell.cjs` com placar `0 falha(s)`.

### 6. Cada caminho avisa uma vez por sessão [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 5
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `  gravarConjunto(arquivo, vistos, headAtual);`
  para: `  void 0;`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, casos A3 e A4`
pronto quando: com duas chamadas seguidas do PostToolUse de Bash na mesma sessão sem mudança nova entre elas, a segunda sai 0. Depois de outro arquivo mudar, o aviso nomeia só o caminho novo. Outra sessão, sem conjunto guardado, avisa o código já sujo uma vez. Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos A3, A4 e A9) com placar `0 falha(s)`.

### 7. Versão 1.71.0, CHANGELOG e README [tipo: docs]
atende: D5
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `docs/rainforest/estado/2026-10-19-gate-worktree-home.json`, `hooks/lib/config.cjs`, `skills/setup/SKILL.md`
depende de: 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19
mutacao: n/a
  motivo: texto e número de versão, sem comportamento a inverter
pronto quando: com o `.claude-plugin/plugin.json` e o `.codex-plugin/plugin.json` em `1.71.0`, `node scripts/conferir-versao.cjs` sai 0 com `versao 1.71.0`. O CHANGELOG abre com `## 1.71.0` e descreve o que D1, D2 e D3 decidiram: a linha `Worktree:` conferida como worktree linkado fora de repo, o aviso na abertura e o hook PostToolUse que decide pelo `git status`, com o custo de um processo por chamada de shell. O README traz o badge `1.71.0`, a exceção fora de repo na linha da `portaria.cjs` e o parágrafo do `aviso-fluxo-shell.cjs`. O estado do fluxo `2026-10-19-gate-worktree-home` entra com `fechar ok` e PR 572. A descrição da chave `aviso-fluxo` em `hooks/lib/config.cjs` e em `skills/setup/SKILL.md` diz que ela também desliga o aviso do shell, e `node scripts/conferir-setup.cjs` sai 0.

### 8. Código criado e commitado na mesma chamada também avisa [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 6
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `const comitados = codigoComitadoDesde(gitTop, guardado, headAtual);`
  para: `const comitados = [];`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, caso D1`
pronto quando: com o payload PostToolUse de Bash depois de o comando criar `novo.py` e commitá-lo, com a árvore limpa, o hook sai 2 nomeando `novo.py`. A chamada seguinte sem commit novo sai 0, e um commit só com `docs/` e `.txt` sai 0. Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos D0, D1, D2 e D4) com placar `0 falha(s)`.

### 9. A foto acumula o que a sessão já viu [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 8
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `const vistos = new Set([...guardado.caminhos, ...atual, ...comitados]);`
  para: `const vistos = new Set([...atual]);`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, casos D6 e D7`
pronto quando: com o payload PostToolUse de Bash, `z.py` novo e sujo avisa (exit 2); depois de `git add` e `git commit` do mesmo `z.py` a chamada sai 0, e depois de `git commit --amend` também sai 0; mexido de novo e commitado na mesma chamada, o mesmo `z.py` também sai 0. Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos D6 e D7) com placar `0 falha(s)`.

### 10. Arquivos do commit lidos sem citação, para pasta com acento [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 9
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `const arquivos = git(gitTop, ['-c', 'core.quotepath=false', 'diff-tree', '--no-commit-id', '-r', '-z',`
  para: `const arquivos = git(gitTop, ['diff-tree', '--no-commit-id', '-r',`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, caso D5`
pronto quando: com o payload PostToolUse de Bash depois de o comando criar `Gestão/Contrato.prw` e commitá-lo, com a árvore limpa, o hook sai 2 nomeando `Gestão/Contrato.prw` sem aspas nem escape octal. Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (caso D5) com placar `0 falha(s)`.

### 11. Só o commit da própria sessão conta, pelo reflog [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 10
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `if (!/^commit( \((amend|initial)\))?:/.test(assunto)) continue;`
  para: `if (false) continue;`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, caso D3`
pronto quando: com o payload PostToolUse de Bash depois de `git pull --ff-only` de um clone em que outra pessoa commitou `colega.py` agora (data de commit recente), o hook sai 0. O commit feito pela própria sessão segue avisando (caso D1). Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos D1 e D3) com placar `0 falha(s)`.

### 12. Merge, cherry-pick ou revert em andamento não avisa [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 11
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `  if (emOperacaoAlheia(gitTop)) process.exit(0);`
  para: `  void 0;`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, caso E1`
pronto quando: com o payload PostToolUse de Bash depois de `git merge al` em conflito (o `alheio.py` da outra branch fica staged), o hook sai 0. Depois do `git commit` que resolve o merge, a chamada seguinte também sai 0. Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos E1 e E2) com placar `0 falha(s)`.

### 13. O amend não avisa o código de antes da sessão [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 12
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `const novos = candidatos.filter((c) => !liquido || liquido.has(c)).sort();`
  para: `const novos = candidatos.sort();`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, casos E3 e E4`
pronto quando: com o payload PostToolUse de Bash depois de `git commit --amend -m "mensagem corrigida"` num commit de antes da sessão que tem `anterior.py`, o hook sai 0. Depois de um `--amend --no-edit` que acrescenta `emenda.py`, ele sai 2 nomeando `emenda.py` e não `anterior.py`. Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos E3 e E4) com placar `0 falha(s)`.

### 14. Rebase em andamento e merge --squash não avisam [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 13
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `const OPERACOES_EM_PASTA = ['rebase-merge', 'rebase-apply', 'SQUASH_MSG'];`
  para: `const OPERACOES_EM_PASTA = [];`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, casos F2 e F3`
pronto quando: com o payload PostToolUse de Bash depois de `git rebase outra` parado em conflito (os commits de antes da sessão ficam staged com o HEAD destacado), o hook sai 0. Depois de `git merge --squash al` de uma branch alheia, que deixa `colega.py` staged sem `MERGE_HEAD`, ele também sai 0. Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos F2 e F3) com placar `0 falha(s)`.

### 15. Só avisa caminho que difere do HEAD da foto [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 14
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `const novos = candidatos.filter((c) => !liquido || liquido.has(c)).sort();`
  para: `const novos = candidatos.sort();`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, caso F1`
pronto quando: com o payload PostToolUse de Bash depois de `git reset --soft HEAD~2 && git commit -m squash` sobre `p1.py` e `p2.py` commitados antes da sessão, o hook sai 0. O código criado e commitado na sessão segue avisando (casos D1 e D5). Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos F1, D1 e D5) com placar `0 falha(s)`.

### 16. O aviso diz "código novo ou mexido", e a remoção avisa [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 15
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `e há código novo ou mexido, sujo ou commitado nesta sessão,`
  para: `e há código novo, sujo ou commitado nesta sessão,`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, caso F4`
pronto quando: com o payload PostToolUse de Bash depois de `rm a.sh` (arquivo de código rastreado), o hook sai 2 nomeando `a.sh`, com o texto "há código novo ou mexido". Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (caso F4) com placar `0 falha(s)`.

### 17. Não rastreado igual ao HEAD da foto não avisa [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 16
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo-shell.cjs`
  de: `(naoRastreados.has(c) ? !igualNaFoto(gitTop, headFoto, c) : mudados.has(c))`
  para: `(naoRastreados.has(c) || mudados.has(c))`
  bateria: `node hooks/testa-aviso-fluxo-shell.cjs`
  fixture: `testa-aviso-fluxo-shell.cjs, caso F5`
pronto quando: com o payload PostToolUse de Bash depois de `git reset HEAD~1` que desfaz o commit de `p1.py`, feito antes da sessão, o hook sai 0. O `p1.py` volta como não rastreado com o mesmo conteúdo do HEAD da foto. Arquivo novo não rastreado criado na sessão segue avisando (casos A2 e D5). Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos F5, A2 e D5) com placar `0 falha(s)`.

### 18. O HEAD da foto só vale como hash [tipo: implementar]
atende: D3, D4
arquivos: `hooks/aviso-fluxo-shell.cjs`, `hooks/testa-aviso-fluxo-shell.cjs`
depende de: 17
prova: `node hooks/testa-aviso-fluxo-shell.cjs`
mutacao: n/a
  motivo: defesa dupla. O HEAD é validado como hash hexadecimal e vai ao git depois de `--end-of-options`, então tirar qualquer uma das duas sozinha não muda a saída observável. O caso G1 confere o efeito das duas juntas.
pronto quando: com a foto da sessão adulterada para `head: "--output=<arquivo>"`, a chamada seguinte do PostToolUse de Bash não cria o `<arquivo>` e segue avisando o código novo `g.py` (exit 2). Provado por `node hooks/testa-aviso-fluxo-shell.cjs` (casos G0 e G1) com placar `0 falha(s)`.

### 19. A bateria da abertura do mod roda em projeto que é repo [tipo: teste]
atende: D2
arquivos: `hooks/testa-abertura-mod-foco.sh`
depende de: 3
prova-na-base: verde — fixture de bateria; na base o aviso de fora de repo não existe e a bateria já passa
mutacao:
  arquivo: `hooks/testa-abertura-mod-foco.sh`
  de: `git init -q "$PROJ"`
  para: `true`
  bateria: `bash hooks/testa-abertura-mod-foco.sh`
  fixture: `testa-abertura-mod-foco.sh, secao "2. sem a flag = golden"`
pronto quando: com o `CLAUDE_PROJECT_DIR` do sandbox apontando para um repo git, como num projeto real, a abertura sem `--destino mod` sai igual (cmp) à do commit golden e não traz a linha "cwd fora de repo git". Provado por `bash hooks/testa-abertura-mod-foco.sh` com placar `falhou: 0`.
