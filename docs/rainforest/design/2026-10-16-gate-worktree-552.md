# gate-worktree: rede de caminho do principal (#552)

## Objetivo
Um subagente, a partir do próprio worktree, não escreve nem apaga nada no checkout principal com Bash ou PowerShell, por grafia nenhuma que cite o caminho do principal. Hoje o gate reconhece a escrita por uma lista de formas conhecidas (redirecionamento, `cp`/`mv`/`tee`/`sed -i`, os cmdlets do #533, `[IO.*]::`). Nas cinco revisões do fluxo #530/#533, cada rodada achou formas novas, e a #552 acumula umas 40: remoção (`rm`, `Remove-Item`), `New-Object`, redirecionamento com variável, alvo entre parênteses, pipeline, provedor (`FileSystem::`), outros cmdlets, `robocopy`/`xcopy`/`curl -o`/`tar -C`, indireção .NET, texto executado fora do `iex`, aspas aninhadas em `$( )` e pai inexistente com `-Force`.

## Decisões fechadas
- **D1 — Rede como segunda camada, por cima da lista** — porquê: a lista resolve `cd`, caminho relativo e o alvo exato, e continua valendo. A rede cobre a cauda que a lista não converge para cobrir. Ela vale onde o gate já vale: ferramentas Bash e PowerShell de subagente (`agent_id` presente). (Luís, 2026-10-16: recomendada.)
- **D2 — Na rede, qualquer comando conta como escrita, exceto uma lista de leitura conhecida (falha fechada)** — porquê: uma lista de verbos de escrita repete o defeito da lista atual. A rede trabalha por segmento (`segmentosComAspas`). O segmento cujo comando é de leitura conhecida não dispara: `cat`, `head`, `tail`, `less`, `ls`, `dir`, `stat`, `file`, `wc`, `grep`, `rg`, `find` sem `-delete`/`-exec`, `diff`, `Get-Content`/`gc`/`type`, `Get-ChildItem`/`gci`/`ls`, `Get-Item`, `Test-Path`, `Resolve-Path`, `Select-String`/`sls`, `Get-FileHash`, `Measure-Object`, e `git` com subcomando de leitura (`log`, `show`, `diff`, `status`, `rev-parse`, `ls-files`, `blame`, `grep`, `cat-file`). O destino de um redirecionamento (`> <P>/f`) conta sempre, inclusive em segmento de leitura. Quando a segmentação não é confiável, a linha inteira vira um segmento só e qualquer caminho do principal barra. "Não confiável" quer dizer, no PowerShell, crase, `#` ou here-string fora de aspas, aspa tipográfica, ou `$(` dentro de aspas. (Luís: recomendada.)
- **D3 — O principal protegido é o do mesmo repositório do worktree** — porquê: uma chamada de `git` por comando (`rev-parse --git-common-dir` a partir do cwd), não uma por caminho citado. O principal é o toplevel do diretório comum. Ficam isentos os worktrees linkados desse repositório (`git worktree list --porcelain`, que inclui `<P>/.claude/worktrees/*`) e o scratchpad da sessão. O caminho citado é comparado depois de normalizado: `\` e `/`, a forma MSYS (`/c/...`) e sem diferenciar caixa no Windows. Comando rodado fora de worktree linkado (cwd no principal ou fora de repositório) não passa pela rede. (Luís: recomendada.)
- **D4 — Texto de mensagem não é alvo** — porquê: `git commit -m "corrigido em <P>/x"` e `gh issue comment --body "..."` citam o caminho como texto. Em segmento de `git` ou `gh`, o valor de `-m`, `--message`, `--body`, `--title` e `-t` sai da rede. Fora desses, o caminho entre aspas continua contando (`rm "<P>/f"` barra). (Luís: recomendada.)
- **D5 — Token com `..` é resolvido contra o cwd do segmento** — porquê: `rm ../../../f` a partir de `<P>/.claude/worktrees/x` cai no principal sem citar o caminho literal. Todo token com `..` como componente de caminho é resolvido contra o cwd do segmento (o mesmo que a lista usa) e entra na comparação do D3. (Luís: recomendada.)
- **D6 — `dirDe` sobe até um diretório que existe** — porquê: hoje, com pai inexistente, `dirDe` sobe um nível só, `estadoDoRepo` não acha o repositório e o alvo passa (`New-Item <P>/n1/n2/f -Force`, `[IO.Directory]::CreateDirectory('<P>/n1/n2')`). Subir até o primeiro ancestral existente devolve o repositório certo. (Luís: recomendada.)

## Avaliado e descartado
- Só estender a lista (remoção, `New-Object`, redirecionamento com variável): fecha os quatro casos do corpo da #552 e deixa a cauda dos comentários, que cresceu a cada revisão.
- Trocar a lista pela rede: a rede não vê `cd <P>` seguido de caminho relativo nem a escrita com alvo relativo no cwd. A lista vê.
- Rede por lista de verbos de escrita: um comando desconhecido passaria, que é o mesmo defeito.
- Proteger qualquer checkout principal citado: custaria uma chamada de `git` por caminho, e a revisão do #533 já mediu cerca de 40 ms por chamada.
- Barrar o texto de mensagem e mandar usar `-F`: os briefings já mandam, mas um `-m` com caminho do principal não é escrita.

## Fora de escopo
- Caminho montado por pedaços (`'C:/Pro'+'jetos'`), por variável de ambiente sem o literal no comando, ou lido de arquivo: a rede só vê o que está escrito.
- A janela principal (sem `agent_id`) e as ferramentas Write/Edit, que já têm regra própria.
- Os outros gates que usam `segmentosComAspas` sem `ehPowerShell` (dívida do PR #554).

## Varredura
docs/rainforest/varredura/2026-10-16-gate-worktree-552.txt — além da #552, só PRs já mergeados (#554, #535 e anteriores) que este design estende sem mudar.

## Em aberto
nada
