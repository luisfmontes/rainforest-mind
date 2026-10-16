# Plano: gate-worktree: {cd,X} e cmdlets de escrita do PowerShell (#530, #533)

Design: docs/rainforest/design/2026-10-16-gate-worktree-brechas.md

## O que não pode quebrar
- `bash hooks/testa-gate-worktree.sh` segue verde.
- Leitura com chaves em posição de argumento (`ls {a,b}`, #514) continua saindo 0.
- Escrita por cmdlet dentro do próprio worktree continua saindo 0.

## Tarefas

### 1. Chaves em posição de comando e escrita por cmdlet do PowerShell [tipo: implementar]
atende: D1, D2, D3, D4
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`, `hooks/testa-cwd-efetivo.sh`
depende de: nenhuma
prova-na-base: verde — as seções "#530" e "#533" da bateria só nascem nesta tarefa; na base a bateria não tem caso que as exerça
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: if (ehPowerShell) alvosDeCmdlet(toks, posCmd, base, empurra);
  para: if (false) alvosDeCmdlet(toks, posCmd, base, empurra);
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: testa-gate-worktree.sh, secao "#533: cmdlets de escrita do PowerShell"
pronto quando: com o payload real de PreToolUse (`agent_type` de subagente, `tool_name` e `cwd`), (a) a partir de um worktree linkado, `{cd,<principal>} && echo x > f` e `{pushd,<principal>} && echo x > f` saem 2, enquanto `{cd,<worktree>} && echo x > f`, `ls {a,b}` e `{ echo a; echo b; } > f` (no worktree) saem 0; (b) com a ferramenta PowerShell e cwd no principal, `Set-Content <P>/f x`, `Set-Content -Path <P>/f -Value x`, `sc <P>/f x`, `Add-Content <P>/f x`, `"x" | Out-File <P>/f`, `Out-File -FilePath <P>/f`, `New-Item -ItemType File <P>/f`, `Copy-Item a <P>/f`, `Move-Item -Destination <P>/f a` e `"x" | Tee-Object -FilePath <P>/f` saem 2, e os mesmos com `<P>` trocado pelo worktree, a partir do worktree, saem 0; (c) `[IO.File]::WriteAllText('<P>/f','x')` e `[System.IO.File]::AppendAllText("<P>/f","x")` saem 2, `[IO.File]::WriteAllText('<W>/f','x')` a partir do worktree sai 0, e `[IO.File]::WriteAllText($p,'x')` a partir do worktree sai 2 (incerto); (d) com a ferramenta Bash, `Set-Content <P>/f x` não ganha alvo novo (D2 é só PowerShell); (e) emendas: com a ferramenta PowerShell, `{cd,<P>}` não é tratado como `cd`; `Microsoft.PowerShell.Management\Set-Content <P>/f x`, `Set-Content -PSPath <P>/f x`, `Set-Content -LP <P>/f x`, `Set-Content $p x` e `Set-Content -Desconhecido y <W>/f` (worktree) saem 2; `[IO.File]::Replace('a','<P>/f',$null)` e `[IO.Directory]::CreateDirectory('<P>/d')` saem 2; `[IO.File]::ReadAllText('<P>/f')` e `Select-String "[IO.File]::WriteAllText(" arq` a partir do worktree saem 0; (f) D4: `echo x > <P>/f && git commit -m y` (Bash) e `Set-Content <P>/f x; git commit -m y` (PowerShell), a partir do worktree, saem 2, e `echo x > f && git commit -m y` no worktree sai 0; (g) `bash hooks/testa-cwd-efetivo.sh` verde, com o caso (514c) reescrito para o D1 — provado por `bash hooks/testa-gate-worktree.sh` com zero falha, com uma seção "#530: chaves em posição de comando" e uma seção "#533: cmdlets de escrita do PowerShell" que montam o payload real, e nenhum caso lendo o texto do fonte.

Forma do código: em `hooks/lib/cwd-efetivo.cjs`, uma função pura que, só no começo do segmento (depois de espaço), troca uma expansão `{a,b,...}` sem espaço, aspas, `$` nem chave interna pelas palavras separadas por espaço; `resolverMovedor` a aplica antes dos regex de movedor. Em `hooks/gate-worktree.cjs`, `alvosBashEscrita` ganha, dentro do laço de segmentos, a linha exata `if (ehPowerShell) alvosDeCmdlet(toks, posCmd, base, empurra);`, e uma função `alvosDeCmdlet` cobre D2 e D3 (incerto do D3 sai como alvo com `incerto: true`, e o mapeamento em `main` passa a respeitar o `incerto` dos alvos de escrita).

### 2. CHANGELOG e versão [tipo: docs]
atende: D1, D2, D3
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: entrada de CHANGELOG e número de versão; não há comportamento a inverter
pronto quando: com a tarefa 1 no repo, a entrada nova do CHANGELOG (PATCH sobre a versão da `origin/main` no momento) lista as grafias que passam a barrar e diz o que segue de fora (`cd $X`, `pwsh -c`); as duas `plugin.json` e o selo do README batem — provado por `node scripts/conferir-versao.cjs` saindo 0 e pela leitura do revisor confrontando o texto com D1–D3.
