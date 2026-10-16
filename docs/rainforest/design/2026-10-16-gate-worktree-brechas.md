# gate-worktree: {cd,X} e cmdlets de escrita do PowerShell (#530, #533)

## Objetivo
Um subagente não escreve no checkout principal por duas grafias que hoje o gate de worktree não enxerga: o `cd` escrito como expansão de chaves (`{cd,X}`, `{pushd,X}`) e a escrita por cmdlet do PowerShell (`Set-Content`, `Add-Content`, `Out-File`, `New-Item`, `Copy-Item`, `Move-Item`, `Tee-Object` e `[IO.File]::Write*`).

## Decisões fechadas
- **D1 — Expansão de chaves na posição de comando vira as palavras que o bash roda** — porquê: medido na `origin/main` (`e69ef6f7`), `A=1 cd X` e `then cd X` já barram (#514), mas `{cd,X} && echo x > f` e `{pushd,X} && echo x > f` saem 0 a partir do worktree. Em posição de comando, `{a,b}` sem espaço dentro é expansão, não grupo: o bash roda `a b`. `resolverMovedor` normaliza o início do segmento nessa forma antes de testar `CD`/`PUSHD`/`SET_LOCATION`. Grupo de verdade (`{ cmd; }`, com espaço) e chave fora da posição de comando não mudam.
- **D2 — Cmdlets de escrita do PowerShell têm alvo** — porquê: com a ferramenta PowerShell no principal, `Set-Content <P>/f x`, `Out-File <P>/f` e `[IO.File]::WriteAllText('<P>/f','x')` saem 0. `alvosBashEscrita`, só quando a ferramenta é PowerShell, reconhece em posição de comando, sem diferenciar caixa: `Set-Content`/`sc`, `Add-Content`/`ac`, `Out-File`, `New-Item`/`ni` e `Tee-Object` (alvo = valor de `-Path`, `-LiteralPath` ou `-FilePath`, ou o primeiro posicional), e `Copy-Item`/`copy`/`cpi`, `Move-Item`/`move`/`mi` (alvo = `-Destination` ou o último posicional). O alvo resolve contra o cwd do segmento, como o redirecionamento.
- **D3 — Chamada .NET de escrita usa o caminho literal, ou fica incerta** — porquê: `[IO.File]::WriteAllText(...)`, `AppendAllText`, `WriteAllLines`, `WriteAllBytes`, `AppendAllLines`, `Copy`, `Move` e `[System.IO.File]::...` não têm sintaxe de comando. Quando o primeiro argumento é uma string literal (aspas simples ou duplas sem `$`), ele é o alvo (para `Copy` e `Move`, o segundo). Quando não é literal, o alvo é incerto, e o gate barra dentro de repositório, como já faz com `cd` não resolvido no ramo de CLI.

## Avaliado e descartado
- Tornar incerta toda escrita depois de qualquer `cd` não resolvido (P2 da #530): `cd $X && echo x > f` e `{ echo a; } > f` passariam a barrar dentro do próprio worktree, e as três grafias medidas se fecham pelo D1 sem esse custo.
- Barrar toda chamada `[IO.File]` (D3): o caminho literal dentro do worktree é o uso comum e legítimo.

## Fora de escopo
- `cd $X` com variável seguido de escrita: segue como hoje (alvo no cwd inicial).
- PowerShell chamado de dentro do Bash (`pwsh -c "Set-Content ..."`): é o ramo de comando dinâmico, outra frente.

## Varredura
docs/rainforest/varredura/2026-10-16-gate-worktree-brechas.txt — além das duas Issues, só a #514/PR #535 (chaves em posição de argumento, já entregue) e o PR #97 (origem do `alvosBashEscrita`), que este design estende sem mudar.

## Em aberto
nada
