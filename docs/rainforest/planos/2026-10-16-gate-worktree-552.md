# Plano: gate-worktree: rede de caminho do principal (#552)

Design: docs/rainforest/design/2026-10-16-gate-worktree-552.md

## O que não pode quebrar
- `bash hooks/testa-gate-worktree.sh` e `bash hooks/testa-cwd-efetivo.sh` seguem verdes.
- `node hooks/testa-corpus-comandos.cjs` segue verde: nenhum comando legítimo do corpus passa a ser barrado no gate-worktree.
- Escrita dentro do próprio worktree, com caminho absoluto do worktree (`<P>/.claude/worktrees/x/f`), continua saindo 0.
- Leitura do principal a partir do worktree (`cat <P>/a`, `Get-Content <P>/a`, `git -C <P> log`) continua saindo 0.

## Tarefas

### 1. Rede de caminho do principal [tipo: implementar]
atende: D1, D2, D3, D4, D5
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`, `hooks/fixtures/corpus-comandos/legitimos.jsonl`, `hooks/testa-corpus-comandos.cjs`
depende de: nenhuma
prova-na-base: verde — a seção "#552: rede de caminho do principal" da bateria só nasce nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: const rede = alvosDaRede(entrada.command, cwd, ehPS);
  para: const rede = [];
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: testa-gate-worktree.sh, secao "#552: rede de caminho do principal"
  timeout: 600000
pronto quando: com o payload real de PreToolUse de subagente (`agent_id`, `agent_type` "executor", `tool_name`, `cwd` igual a um worktree linkado em `<P>/.claude/worktrees/x` e principal em `<P>`):
(a) saem 2, com a ferramenta PowerShell: `Remove-Item <P>/f`, `New-Object IO.StreamWriter('<P>/f')`, `Set-Content -Path (Join-Path '<P>' f) x`, `Get-Item <P>/a.txt | Set-Content -Value x`, `Set-Content FileSystem::<P>/f x`, `Clear-Content <P>/f`, `Rename-Item <P>/a b`, `Expand-Archive a.zip -DestinationPath <P>/o` e `Invoke-Command -ScriptBlock ([scriptblock]::Create('Set-Content <P>/f x'))`;
(b) saem 2, com a ferramenta Bash: `rm <P>/f`, `P=<P>; echo x > $P/f`, `{touch,<P>/f}`, `robocopy src <P>/dst`, `curl -o <P>/f http://x`, `tar -xf a.tar -C <P>` e `rm ../../../f`, este a partir de `<P>/.claude/worktrees/x`;
(c) com a mesma grafia, `<P>` escrito com `\`, como `/c/...` (Bash) e com outra caixa sai 2;
(d) saem 0: `cat <P>/a.txt`, `Get-Content <P>/a.txt`, `Select-String x <P>/a.txt`, `git -C <P> log -1`, `ls <P>`, `Test-Path <P>/a`, `rm <P>/.claude/worktrees/x/f` e `Set-Content <P>/.claude/worktrees/x/f y` (o próprio worktree), `git commit -m "corrigido em <P>/a"` e `gh issue comment 1 --body "ver <P>/a"` (D4);
(e) saem 2: `cat <P>/a > <P>/b` (redirecionamento em segmento de leitura) e `Get-Content <P>/a | Out-File <P>/b`;
(f) sai 2 uma linha de PowerShell com here-string, ou com `$(` dentro de aspas, que cita `<P>` só em segmento de leitura (segmentação não confiável, D2);
(g) `node hooks/testa-corpus-comandos.cjs` verde, com casos novos no corpus de legítimos para os vizinhos de (d);
provado por `bash hooks/testa-gate-worktree.sh` com zero falha, com a seção "#552: rede de caminho do principal" montando o payload real, e nenhum caso lendo o texto do fonte.

Forma do código: em `hooks/gate-worktree.cjs`, uma função `alvosDaRede(comando, cwd, ehPowerShell)` que devolve a lista de alvos `{dir, incerto: true}` para cada caminho do principal citado fora de leitura (D2–D5); em `main`, no ramo Bash/PowerShell, a linha exata `const rede = alvosDaRede(entrada.command, cwd, ehPS);` e a soma de `rede` aos alvos (com motivo próprio quando a lista não achou nada). O principal e os worktrees saem de uma chamada `git worktree list --porcelain` a partir do cwd. Se o cwd não for um worktree linkado, a rede devolve vazio.

### 2. dirDe sobe até um diretório que existe [tipo: implementar]
atende: D6
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 1
prova-na-base: verde — a seção "#552 D6: pai inexistente" da bateria só nasce nesta tarefa
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: while (!fs.existsSync(atual) && path.dirname(atual) !== atual) atual = path.dirname(atual);
  para: atual = path.dirname(atual);
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: testa-gate-worktree.sh, secao "#552 D6: pai inexistente"
  timeout: 600000
pronto quando: com o payload real de subagente e cwd no próprio checkout principal (onde a rede não age, D3, e só a lista decide), `New-Item -ItemType File -Path n1/n2/f -Force` e `[IO.Directory]::CreateDirectory('n1/n2/d')` (PowerShell) e `echo x > n1/n2/f` (Bash) saem 2, com `n1` inexistente. Com cwd num worktree linkado, as mesmas três linhas saem 0. Provado por `bash hooks/testa-gate-worktree.sh` com zero falha, numa seção "#552 D6: pai inexistente".

Forma do código: `dirDe(alvo)` devolve o primeiro ancestral existente, com a linha exata `while (!fs.existsSync(atual) && path.dirname(atual) !== atual) atual = path.dirname(atual);`.

### 3. CHANGELOG e versão [tipo: docs]
atende: D1, D2, D3, D4, D5, D6
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 2
mutacao: n/a
  motivo: entrada de CHANGELOG e número de versão; não há comportamento a inverter
pronto quando: com as tarefas 1 e 2 no repo, a entrada nova do CHANGELOG é MINOR (trava nova, pela tabela do CONTRIBUTING) sobre a versão da `origin/main`. Ela descreve a rede (o que barra, a lista de leitura, as isenções de worktree, scratchpad e texto de mensagem), o conserto do pai inexistente, e o que segue de fora: caminho montado por pedaços, variável sem literal e a janela principal. As duas `plugin.json` e o selo do README batem. Provado por `node scripts/conferir-versao.cjs` saindo 0 e pela leitura do revisor confrontando o texto com D1–D6.
